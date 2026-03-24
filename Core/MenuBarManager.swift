import AppKit
import Combine
import os.log
import SaneUI
import ServiceManagement
import SwiftUI

// swiftlint:disable file_length

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager")

// MARK: - MenuBarManager

/// Central manager for menu bar hiding using the length toggle technique.
///
/// HOW IT WORKS (standard length-toggle technique):
/// 1. User Cmd+drags menu bar icons to position them left or right of our delimiter
/// 2. Icons to the RIGHT of delimiter = always visible
/// 3. Icons to the LEFT of delimiter = can be hidden
/// 4. To HIDE: Set delimiter's length to 10,000 → pushes everything to its left off screen (x < 0)
/// 5. To SHOW: Set delimiter's length back to 20 → reveals the hidden icons
///
/// NO accessibility API needed. NO CGEvent simulation. Just simple NSStatusItem.length toggle.
@MainActor
final class MenuBarManager: NSObject, ObservableObject, NSMenuDelegate {
    // MARK: - Singleton

    static let shared = MenuBarManager()

    // MARK: - Published State

    /// Starts expanded - we validate positions first, then hide if safe
    @Published private(set) var hidingState: HidingState = .expanded
    @Published var settings: SaneBarSettings = .init()

    /// When true, the user explicitly chose to keep icons revealed ("Reveal All")
    /// and we should not auto-hide until they explicitly hide again.
    @Published var isRevealPinned: Bool = false

    /// Tracks whether the status menu is currently open
    @Published var isMenuOpen: Bool = false

    /// Guards against duplicate auth prompts
    var isAuthenticating: Bool = false

    /// Delayed overlap check task for temporarily hiding app menus while expanded.
    var appMenuSuppressionTask: Task<Void, Never>?
    /// Keeps reasserting accessory activation policy while app menus are temporarily suppressed.
    var appMenuDockPolicyTask: Task<Void, Never>?
    /// Tracks whether SaneBar temporarily hid front app menus for overlap.
    var isAppMenuSuppressed = false
    /// Front app to reactivate after temporary menu suppression.
    var appToReactivateAfterSuppression: NSRunningApplication?
    /// Explicit right-click menu opens should not depend on NSApp.currentEvent
    /// still looking like a right click by the time NSMenuDelegate fires.
    var pendingExplicitStatusMenuRightClick = false
    /// Tracks the reveal source so passive hover reveals can avoid focus-stealing
    /// inline app-menu suppression.
    var lastRevealTrigger: RevealTrigger = .automation
    /// Monotonic token used to invalidate older position-validation passes when
    /// screen/wake notifications or recovery flows schedule a newer pass.
    var positionValidationGeneration: Int = 0
    /// Prevent overlapping structural recovery passes from tearing down and
    /// rebuilding the status items multiple times inside one launch.
    var isExecutingStatusItemRecovery = false

    /// Rate limiting for auth attempts (security hardening)
    var failedAuthAttempts: Int = 0
    var lastFailedAuthTime: Date?
    let maxFailedAttempts: Int = 5
    let lockoutDuration: TimeInterval = 30 // seconds

    /// Reference to the currently active icon move task to ensure atomicity
    var activeMoveTask: Task<Bool, Never>?

    /// Best-effort enforcement task for pinned always-hidden items (avoid overlapping runs)
    var alwaysHiddenPinEnforcementTask: Task<Void, Never>?
    var lastAlwaysHiddenRepairAt: Date?
    var isRepairingAlwaysHiddenSeparator = false

    // MARK: - Screen Detection

    private var statusItemScreen: NSScreen? {
        mainStatusItem?.button?.window?.screen ??
            separatorItem?.button?.window?.screen ??
            NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ??
            NSScreen.main
    }

    /// Returns true if the main screen has a notch (MacBook Pro 14/16 inch models)
    var hasNotch: Bool {
        guard let screen = statusItemScreen else { return false }
        // auxiliaryTopLeftArea is non-nil on notched Macs (macOS 12+)
        return screen.auxiliaryTopLeftArea != nil
    }

    /// Returns true if the mouse cursor is currently on an external (non-built-in) monitor
    var isOnExternalMonitor: Bool {
        // Find the screen containing the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        guard let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            // Safe mode: assume external when screen state is uncertain (hot-plug, sleep wake)
            return true
        }

        // Get the display ID for the screen with the mouse
        guard let displayID = screenWithMouse.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            // Safe mode: assume external when lookup fails (unusual display config)
            return true
        }

        // CGDisplayIsBuiltin returns non-zero for the built-in laptop display
        return CGDisplayIsBuiltin(displayID) == 0
    }

    /// Check if hiding should be skipped due to external monitor setting
    var shouldSkipHideForExternalMonitor: Bool {
        Self.shouldSkipHide(
            disableOnExternalMonitor: settings.disableOnExternalMonitor,
            isOnExternalMonitor: isOnExternalMonitor
        )
    }

    /// Prevent development/test builds from mutating persistent login-item state.
    /// This avoids DerivedData/dev runs poisoning launch-at-login on user machines.
    private func canMutateLaunchAtLogin() -> Bool {
        let bundlePath = Bundle.main.bundleURL.path
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        if bundlePath.contains("/DerivedData/") { return false }
        if bundleID.hasSuffix(".dev") { return false }
        return bundlePath.hasPrefix("/Applications/")
    }

    // MARK: - Services

    let hidingService: HidingService
    let persistenceService: PersistenceServiceProtocol
    let settingsController: SettingsController
    let triggerService: TriggerService
    let iconHotkeysService: IconHotkeysService
    let appearanceService: MenuBarAppearanceService
    let networkTriggerService: NetworkTriggerService
    let focusModeService: FocusModeService
    let scheduleTriggerService: ScheduleTriggerService
    let scriptTriggerService: ScriptTriggerService
    let hoverService: HoverService
    let updateService: UpdateService
    private let injectedStatusBarController: StatusBarController?
    private var statusBarControllerStorage: StatusBarController?

    // MARK: - Status Items

    /// Main SaneBar icon you click (always visible)
    var mainStatusItem: NSStatusItem?
    /// Separator that expands to hide items (the actual delimiter)
    var separatorItem: NSStatusItem?
    /// Optional separator for always-hidden zone (experimental)
    var alwaysHiddenSeparatorItem: NSStatusItem?
    /// Cached position of main separator when at visual size (not blocking).
    /// Used when separator is in blocking mode (length > 1000) and live position is off-screen.
    var lastKnownSeparatorX: CGFloat?
    /// Cached right edge of main separator when at visual size (not blocking).
    /// Used by getSeparatorRightEdgeX() when separator is in blocking mode.
    var lastKnownSeparatorRightEdgeX: CGFloat?
    /// Cached position of always-hidden separator when at visual size (not blocking).
    /// Used for classification when the separator is at 10,000 length (blocking mode).
    var lastKnownAlwaysHiddenSeparatorX: CGFloat?
    /// Cached right edge of always-hidden separator when at visual size.
    /// Used when AH boundary checks run while live frames are stale/off-screen.
    var lastKnownAlwaysHiddenSeparatorRightEdgeX: CGFloat?
    var statusMenu: NSMenu?
    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    var statusBarController: StatusBarController {
        guard let controller = statusBarControllerStorage else {
            preconditionFailure("StatusBarController accessed before deferred UI setup")
        }
        return controller
    }

    @discardableResult
    private func ensureStatusBarController() -> StatusBarController {
        if let controller = statusBarControllerStorage {
            return controller
        }

        let controller = injectedStatusBarController ?? StatusBarController()
        statusBarControllerStorage = controller
        return controller
    }

    nonisolated static func statusItemCreationDelaySeconds(
        environmentOverrideMs: String?,
        majorOSVersion: Int
    ) -> TimeInterval {
        if let environmentOverrideMs,
           let delayValue = Double(environmentOverrideMs) {
            return max(0.0, delayValue / 1000.0)
        }

        return majorOSVersion >= 26 ? 0.35 : 0.1
    }

    nonisolated static let maxStatusItemRecoveryCount = 2

    nonisolated static func statusItemValidationInitialDelaySeconds(
        context: MenuBarOperationCoordinator.PositionValidationContext,
        recoveryCount: Int
    ) -> TimeInterval {
        switch context {
        case .startupFollowUp:
            return recoveryCount == 0 ? 0.5 : 1.0
        case .manualLayoutRestore:
            return recoveryCount == 0 ? 0.35 : 0.75
        case .screenParametersChanged:
            return recoveryCount == 0 ? 1.5 : 2.0
        case .wakeResume:
            return recoveryCount == 0 ? 2.0 : 2.5
        }
    }

    init(
        hidingService: HidingService? = nil,
        persistenceService: PersistenceServiceProtocol = PersistenceService.shared,
        settingsController: SettingsController? = nil,
        statusBarController: StatusBarController? = nil,
        triggerService: TriggerService? = nil,
        iconHotkeysService: IconHotkeysService? = nil,
        appearanceService: MenuBarAppearanceService? = nil,
        networkTriggerService: NetworkTriggerService? = nil,
        focusModeService: FocusModeService? = nil,
        scheduleTriggerService: ScheduleTriggerService? = nil,
        scriptTriggerService: ScriptTriggerService? = nil,
        hoverService: HoverService? = nil,
        updateService: UpdateService? = nil
    ) {
        self.hidingService = hidingService ?? HidingService()
        self.persistenceService = persistenceService
        self.settingsController = settingsController ?? SettingsController(persistence: persistenceService)
        self.triggerService = triggerService ?? TriggerService()
        self.iconHotkeysService = iconHotkeysService ?? IconHotkeysService.shared
        self.appearanceService = appearanceService ?? MenuBarAppearanceService()
        self.networkTriggerService = networkTriggerService ?? NetworkTriggerService()
        self.focusModeService = focusModeService ?? FocusModeService()
        self.scheduleTriggerService = scheduleTriggerService ?? ScheduleTriggerService()
        self.scriptTriggerService = scriptTriggerService ?? ScriptTriggerService()
        self.hoverService = hoverService ?? HoverService()
        self.updateService = updateService ?? UpdateService()
        injectedStatusBarController = statusBarController

        super.init()

        logger.info("MenuBarManager init starting...")

        // Skip UI initialization in headless/test environments
        // CI environments don't have a window server, so NSStatusItem creation will crash
        guard !isRunningInHeadlessEnvironment() else {
            logger.info("Headless environment detected - skipping UI initialization")
            return
        }

        // Load settings first - this doesn't depend on status items
        loadSettings()

        // Defer ALL status-bar-dependent initialization to ensure WindowServer is ready
        // This fixes crashes on Mac Mini M4 and other systems where GUI isn't
        // immediately available at app launch (e.g., Login Items, fast boot)
        deferredUISetup()
    }

    private func configureHoverService() {
        hoverService.onTrigger = { [weak self] reason in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isMenuOpen else {
                    logger.debug("Ignoring hover trigger while status menu is open")
                    return
                }
                logger.debug("Hover trigger received: \(String(describing: reason))")

                switch reason {
                case .hover:
                    // Hover always reveals only (toggling on hover would be annoying)
                    _ = await self.showHiddenItemsNow(trigger: .hover)

                case let .scroll(direction):
                    if self.settings.useDirectionalScroll {
                        // Ice-style directional: up=show, down=hide (standard behavior)
                        // Takes priority over gestureToggles for scrolling
                        if direction == .up {
                            _ = await self.showHiddenItemsNow(trigger: .scroll)
                        } else if !self.shouldSkipHideForExternalMonitor {
                            self.hideHiddenItems()
                        }
                    } else if self.settings.gestureToggles {
                        // Legacy toggle mode (any scroll toggles) - for backwards compatibility
                        if self.shouldSkipHideForExternalMonitor {
                            _ = await self.showHiddenItemsNow(trigger: .scroll)
                        } else {
                            self.toggleHiddenItems(trigger: .scroll)
                        }
                    } else {
                        // Show only: scroll reveals without hiding
                        _ = await self.showHiddenItemsNow(trigger: .scroll)
                    }

                case .click:
                    if self.settings.gestureToggles {
                        // Toggle can hide, so respect external monitor setting
                        if self.shouldSkipHideForExternalMonitor {
                            // On external monitor with setting enabled - only allow show
                            _ = await self.showHiddenItemsNow(trigger: .click)
                        } else {
                            self.toggleHiddenItems(trigger: .click)
                        }
                    } else {
                        _ = await self.showHiddenItemsNow(trigger: .click)
                    }

                case .userDrag:
                    // ⌘+drag: reveal all icons so user can rearrange
                    _ = await self.showHiddenItemsNow(trigger: .userDrag)
                    // Pin the reveal so auto-hide doesn't kick in while dragging
                    self.isRevealPinned = true
                }
            }
        }

        hoverService.onUserDragEnd = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isMenuOpen else { return }

                // Reconcile AH pins with physical positions after Cmd+drag
                await self.reconcilePinsAfterUserDrag()

                // Un-pin and allow auto-hide to resume
                self.isRevealPinned = false
                if self.settings.autoRehide, !self.shouldSkipHideForExternalMonitor {
                    self.hidingService.scheduleRehide(after: self.settings.rehideDelay)
                }
            }
        }

        hoverService.onLeaveMenuBar = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isMenuOpen else { return }
                // Only auto-hide if autoRehide is enabled and not on external monitor
                if self.settings.autoRehide, !self.isRevealPinned, !self.shouldSkipHideForExternalMonitor {
                    self.hidingService.scheduleRehide(after: self.settings.rehideDelay)
                }
            }
        }

        // Apply initial settings
        updateHoverService()
    }

    /// Detects if running in a headless environment (CI, tests without window server)
    private func isRunningInHeadlessEnvironment() -> Bool {
        // Allow UI tests to force UI loading via environment variable
        if ProcessInfo.processInfo.environment["SANEBAR_UI_TESTING"] != nil {
            return false
        }

        // Check for common CI environment variables
        let env = ProcessInfo.processInfo.environment
        if env["CI"] != nil || env["GITHUB_ACTIONS"] != nil {
            return true
        }

        // Check if running in test bundle by examining bundle identifier
        // Test bundles typically have "Tests" suffix or "xctest" in their identifier
        if let bundleID = Bundle.main.bundleIdentifier {
            if bundleID.hasSuffix("Tests") || bundleID.contains("xctest") {
                return true
            }
        }

        // Fallback: Check for XCTest framework presence
        // This catches edge cases where bundle ID doesn't follow conventions
        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        return false
    }

    private func currentEffectiveAlwaysHiddenSectionEnabled() -> Bool {
        Self.effectiveAlwaysHiddenSectionEnabled(
            isPro: LicenseService.shared.isPro,
            alwaysHiddenSectionEnabled: settings.alwaysHiddenSectionEnabled
        )
    }

    // MARK: - Setup

    /// Deferred UI setup with initial delay to ensure WindowServer is ready
    /// Fixes crash on Mac Mini M4 / macOS 15.7.3 where GUI isn't immediately available
    private func deferredUISetup() {
        // Initial delay of 100ms gives the system time to fully establish
        // the WindowServer connection, especially important for:
        // - Login Items that launch before GUI is ready
        // - Fast boot systems (M4 Macs)
        // - Remote desktop sessions
        let initialDelay = Self.statusItemCreationDelaySeconds(
            environmentOverrideMs: ProcessInfo.processInfo.environment["SANEBAR_STATUSITEM_DELAY_MS"],
            majorOSVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            guard let self else { return }
            logger.info("Starting deferred UI setup")

            // Create status items (with additional retry logic inside)
            setupStatusItem()

            // These all depend on status items being ready
            updateSpacers()
            setupObservers()
            updateAppearance()

            // Configure services
            triggerService.configure(menuBarManager: self)
            iconHotkeysService.configure(with: self)
            networkTriggerService.configure(menuBarManager: self)
            if settings.showOnNetworkChange {
                networkTriggerService.startMonitoring()
            }

            // Configure Focus Mode trigger
            focusModeService.configure(menuBarManager: self)
            if settings.showOnFocusModeChange {
                focusModeService.startMonitoring()
            }

            // Configure schedule trigger
            scheduleTriggerService.configure(menuBarManager: self)
            if settings.showOnSchedule {
                scheduleTriggerService.startMonitoring()
            }

            // Configure Script trigger
            scriptTriggerService.configure(menuBarManager: self)
            if settings.scriptTriggerEnabled {
                scriptTriggerService.startMonitoring()
            }

            // Configure hover service
            configureHoverService()

            // Show onboarding on first launch
            showOnboardingIfNeeded()

            // Sync update settings to Sparkle
            syncUpdateConfiguration()

            // Pre-warm menu bar icon cache (async background task)
            AccessibilityService.shared.prewarmCache()

            logger.info("Deferred UI setup complete")
        }
    }

    @MainActor
    private func scheduleInitialPositionValidationAfterStartup() {
        // Avoid racing the first geometry check against the startup
        // hide/recovery path. Validate only after launch settles.
        schedulePositionValidation(context: .startupFollowUp)
    }

    private func setupStatusItem() {
        let statusBarController = ensureStatusBarController()

        // Create and configure status items only after the deferred startup
        // delay so Tahoe-class systems have time to attach the status-bar scene.
        statusBarController.configureStatusItems(
            clickAction: #selector(statusItemClicked),
            target: self
        )

        // Copy references for local use
        mainStatusItem = statusBarController.mainItem
        separatorItem = statusBarController.separatorItem
        statusBarController.ensureAlwaysHiddenSeparator(enabled: currentEffectiveAlwaysHiddenSectionEnabled())
        alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem

        // Setup menu using controller (shown via right-click on main icon)
        statusMenu = statusBarController.createMenu(configuration: MenuConfiguration(
            findIconAction: #selector(openFindIcon),
            settingsAction: #selector(openSettings),
            showReleaseNotesAction: LicenseService.shared.usesSetappDistribution ? #selector(showReleaseNotes) : nil,
            checkForUpdatesAction: #selector(userDidClickCheckForUpdates),
            quitAction: #selector(quitApp)
        ))
        wireStatusMenuTargets()
        updateUpdateMenuAvailability()
        statusMenu?.delegate = self
        clearStatusItemMenus()

        // Configure hiding service with delimiter
        if let separator = separatorItem {
            hidingService.configure(delimiterItem: separator)
        }
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)

        // Unified fire-time guard for ALL auto-rehide paths (#97).
        // Checked when the timer actually fires, not when it's scheduled.
        // Prevents hiding while user is interacting with any menu (SaneBar's or third-party).
        hidingService.shouldRehide = { [weak self] in
            guard let self else { return true }
            return self.canAutoRehideAtFireTime()
        }

        // If WindowServer position cache is corrupted and the controller
        // recreates items with a bumped autosave namespace, re-wire references.
        statusBarController.onItemsRecreated = { [weak self] main, separator in
            guard let self else { return }
            self.mainStatusItem = main
            self.separatorItem = separator
            self.alwaysHiddenSeparatorItem = self.statusBarController.alwaysHiddenSeparatorItem

            if let button = main.button {
                button.action = #selector(statusItemClicked)
                button.target = self
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }

            self.hidingService.configure(delimiterItem: separator)
            self.hidingService.configureAlwaysHiddenDelimiter(self.alwaysHiddenSeparatorItem)
            self.clearStatusItemMenus()
            self.updateMainIconVisibility()
            self.updateDividerStyle()
            self.updateIconStyle()
            self.updateAlwaysHiddenSeparator()
            self.updateSpacers()

            logger.info("Re-wired status items after autosave recovery")
        }

        // Apply main icon visibility based on settings
        updateMainIconVisibility()
        updateDividerStyle()
        updateIconStyle()

        // Hide icons on startup (default behavior)
        // Give UI time to settle, then hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                // Cache stable separator coordinates while delimiters are still at
                // visual size. This avoids nil separator classification after startup hide.
                await self.warmSeparatorPositionCache()

                // Stamp calibrated screen width now that positions are stable
                if let w = NSScreen.main?.frame.width {
                    UserDefaults.standard.set(w, forKey: "SaneBar_CalibratedScreenWidth")
                }
                let startupSnapshot = self.currentStatusItemRecoverySnapshot()
                let hasConnectedExternalMonitorWithAlwaysShow = self.settings.disableOnExternalMonitor &&
                    NSScreen.screens.contains(where: { screen in
                        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
                        return CGDisplayIsBuiltin(displayID) == 0
                    })
                let startupAction = MenuBarOperationCoordinator.statusItemRecoveryAction(
                    snapshot: startupSnapshot,
                    context: .startupInitial(.init(
                        hasCompletedOnboarding: self.settings.hasCompletedOnboarding,
                        autoRehideEnabled: self.settings.autoRehide,
                        shouldSkipHideForExternalMonitor: self.shouldSkipHideForExternalMonitor,
                        hasConnectedExternalMonitorWithAlwaysShow: hasConnectedExternalMonitorWithAlwaysShow
                    )),
                    recoveryCount: 0,
                    maxRecoveryCount: Self.maxStatusItemRecoveryCount
                )

                switch startupAction {
                case let .repairPersistedLayoutAndRecreate(reason):
                    self.logStatusItemRecoveryReason(
                        reason,
                        snapshot: startupSnapshot,
                        prefix: "Startup recovery"
                    )
                    self.executeStatusItemRecoveryAction(
                        startupAction,
                        trigger: "startup-\(reason?.rawValue ?? "recovery")",
                        validationContext: nil,
                        recoveryCount: 0
                    )
                    await self.hidingService.show()
                    self.scheduleInitialPositionValidationAfterStartup()
                    return

                case .keepExpanded(.waitingForLiveCoordinates):
                    logger.warning("Startup coordinates were still missing after initial settle — skipping initial hide and relying on position validation")
                    self.scheduleInitialPositionValidationAfterStartup()
                    return

                case let .keepExpanded(reason):
                    self.repairAlwaysHiddenSeparatorPositionIfNeeded(reason: "startup")
                    switch reason {
                    case .autoRehideDisabled:
                        logger.info("Skipping initial hide: auto-rehide disabled")
                    case .externalMonitorPolicy:
                        logger.info("Skipping initial hide: user is on external monitor")
                    case .externalMonitorConnectedAlwaysShow:
                        logger.info("Skipping initial hide: external monitor connected with always-show enabled")
                    case .waitingForLiveCoordinates:
                        break
                    }
                    self.scheduleInitialPositionValidationAfterStartup()
                    return

                case .performInitialHide:
                    // Repair AH separator ordering drift before any startup hide.
                    self.repairAlwaysHiddenSeparatorPositionIfNeeded(reason: "startup")

                case .captureCurrentDisplayBackup, .recreateFromPersistedLayout, .bumpAutosaveVersion, .stop:
                    logger.error("Unexpected startup recovery action \(String(describing: startupAction), privacy: .public) — continuing with initial hide path")
                }

                let hasAccessibilityPermission = AccessibilityService.shared.isGranted
                if !hasAccessibilityPermission {
                    logger.warning(
                        "Accessibility permission not granted at startup — continuing initial hide; launch-time pin automation is deferred"
                    )
                } else if !self.settings.alwaysHiddenPinnedItemIds.isEmpty {
                    // Launch-time pin enforcement used Cmd+drag automation before the
                    // first hide and could keep the menu bar expanded long enough to
                    // look like auto-rehide was broken. Keep startup deterministic:
                    // hide first, then rely on normal runtime enforcement paths.
                    logger.info("Skipping launch-time always-hidden pin automation to keep startup hide deterministic")
                }

                await self.hidingService.hide()
                logger.info("Initial hide complete")
                self.scheduleInitialPositionValidationAfterStartup()
            }
        }
    }

    private func wireStatusMenuTargets() {
        for item in statusMenu?.items ?? [] where item.action != nil {
            item.target = self
        }
    }

    @MainActor
    private func clearCachedSeparatorGeometry() {
        lastKnownSeparatorX = nil
        lastKnownSeparatorRightEdgeX = nil
        lastKnownAlwaysHiddenSeparatorX = nil
        lastKnownAlwaysHiddenSeparatorRightEdgeX = nil
    }

    @MainActor
    func currentRuntimeSnapshot(
        identityPrecision: MenuBarIdentityPrecision = .unknown
    ) -> MenuBarRuntimeSnapshot {
        let controller = statusBarControllerStorage
        let mainItem = mainStatusItem ?? controller?.mainItem
        let separator = separatorItem ?? controller?.separatorItem
        let alwaysHiddenSeparatorX = getAlwaysHiddenSeparatorOriginX()
        let startupItemsValid: Bool = {
            guard let mainItem, let separator else { return false }
            return StatusBarController.validateStartupItems(
                main: mainItem,
                separator: separator
            )
        }()
        let separatorX = getSeparatorOriginX()
        let mainX = getMainStatusItemLeftEdgeX()
        let mainWindow = mainItem?.button?.window
        let screenWidth = mainWindow?.screen?.frame.width ?? NSScreen.main?.frame.width
        let notchRightSafeMinX = mainWindow?.screen?.auxiliaryTopRightArea?.minX
            ?? NSScreen.main?.auxiliaryTopRightArea?.minX
        let mainRightGap: CGFloat? = {
            guard let mainWindow else { return nil }
            guard let rightEdge = mainWindow.screen?.frame.maxX ?? NSScreen.main?.frame.maxX else { return nil }
            return rightEdge - mainWindow.frame.origin.x
        }()
        let alwaysHiddenSeparatorMisordered = Self.alwaysHiddenSeparatorNeedsRepair(
            hasAlwaysHiddenSeparator: alwaysHiddenSeparatorItem != nil,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
        )

        let geometryConfidence: MenuBarGeometryConfidence = {
            guard mainItem != nil, separator != nil else { return .missing }
            guard startupItemsValid else { return .stale }
            guard separatorX != nil, mainX != nil else { return .missing }
            guard !alwaysHiddenSeparatorMisordered else { return .stale }
            if Self.shouldRecoverStartupPositions(
                separatorX: separatorX,
                mainX: mainX,
                mainRightGap: mainRightGap,
                screenWidth: screenWidth,
                notchRightSafeMinX: notchRightSafeMinX
            ) {
                return .stale
            }
            return .live
        }()

        return MenuBarRuntimeSnapshot(
            identityPrecision: identityPrecision,
            geometryConfidence: geometryConfidence,
            visibilityPhase: hidingService.isAnimating || hidingService.isTransitioning ? .transitioning : (hidingService.state == .hidden ? .hidden : .expanded),
            browsePhase: SearchWindowController.shared.isMoveInProgress ? .moveInProgress : (SearchWindowController.shared.isBrowseSessionActive ? .open : .idle),
            startupItemsValid: startupItemsValid,
            hasAlwaysHiddenSeparator: alwaysHiddenSeparatorItem != nil,
            hasActiveMoveTask: activeMoveTask?.isCancelled == false,
            hasAnyScreens: !NSScreen.screens.isEmpty,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
            mainX: mainX,
            mainRightGap: mainRightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX
        )
    }

    @MainActor
    private func currentStatusItemRecoverySnapshot() -> MenuBarRuntimeSnapshot {
        currentRuntimeSnapshot()
    }

    @MainActor
    private func stableSnapshotNeedsAlwaysHiddenRepair(_ snapshot: MenuBarRuntimeSnapshot) -> Bool {
        Self.alwaysHiddenSeparatorNeedsRepair(
            hasAlwaysHiddenSeparator: snapshot.hasAlwaysHiddenSeparator,
            separatorX: snapshot.separatorX,
            alwaysHiddenSeparatorX: snapshot.alwaysHiddenSeparatorX
        )
    }

    @MainActor
    private func logAlwaysHiddenSeparatorRecoveryNeed(
        snapshot: MenuBarRuntimeSnapshot,
        prefix: String
    ) {
        logger.error(
            "\(prefix, privacy: .public): always-hidden separator misordered (ah=\(snapshot.alwaysHiddenSeparatorX ?? -1, privacy: .public), sep=\(snapshot.separatorX ?? -1, privacy: .public))"
        )
    }

    @MainActor
    private func captureCurrentDisplayBackupAfterStableValidation(
        maxAttempts: Int = 6,
        delay: Duration = .milliseconds(150)
    ) async -> Bool {
        for attempt in 1 ... maxAttempts {
            if StatusBarController.captureCurrentDisplayPositionBackupIfPossible() {
                return true
            }
            if StatusBarController.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay() {
                return true
            }
            if attempt < maxAttempts {
                try? await Task.sleep(for: delay)
            }
        }
        return StatusBarController.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay()
    }

    @MainActor
    private func logStatusItemRecoveryReason(
        _ reason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        snapshot: MenuBarRuntimeSnapshot,
        prefix: String
    ) {
        guard let reason else { return }

        switch reason {
        case .invalidStatusItems:
            logger.error("\(prefix, privacy: .public): status-item windows are invalid")
        case .missingCoordinates:
            logger.error("\(prefix, privacy: .public): live coordinates are still missing")
        case .invalidGeometry:
            logger.error(
                "\(prefix, privacy: .public): geometry drift detected (separator=\(snapshot.separatorX ?? -1, privacy: .public), main=\(snapshot.mainX ?? -1, privacy: .public), rightGap=\(snapshot.mainRightGap ?? -1, privacy: .public), width=\(snapshot.screenWidth ?? -1, privacy: .public))"
            )
        }
    }

    @MainActor
    private func executeStatusItemRecoveryAction(
        _ action: MenuBarOperationCoordinator.StatusItemRecoveryAction,
        trigger: String,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext? = nil,
        recoveryCount: Int = 0,
        validationGeneration: Int? = nil
    ) {
        if let validationGeneration,
           positionValidationGeneration != validationGeneration {
            logger.debug(
                "Skipping stale status item recovery action for \(trigger, privacy: .public) (expected generation \(validationGeneration, privacy: .public), current \(self.positionValidationGeneration, privacy: .public))"
            )
            return
        }

        switch action {
        case .captureCurrentDisplayBackup:
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible()

        case .repairPersistedLayoutAndRecreate:
            guard !isExecutingStatusItemRecovery else {
                logger.warning("Skipping overlapping status item recovery action for \(trigger, privacy: .public)")
                return
            }
            isExecutingStatusItemRecovery = true
            positionValidationGeneration += 1
            defer { isExecutingStatusItemRecovery = false }
            StatusBarController.recoverStartupPositions(
                alwaysHiddenEnabled: currentEffectiveAlwaysHiddenSectionEnabled()
            )
            clearCachedSeparatorGeometry()
            recreateStatusItemsFromPersistedLayout(reason: trigger)
            if let validationContext {
                schedulePositionValidation(context: validationContext, recoveryCount: recoveryCount + 1)
            }

        case .recreateFromPersistedLayout:
            guard !isExecutingStatusItemRecovery else {
                logger.warning("Skipping overlapping status item recovery action for \(trigger, privacy: .public)")
                return
            }
            isExecutingStatusItemRecovery = true
            positionValidationGeneration += 1
            defer { isExecutingStatusItemRecovery = false }
            recreateStatusItemsFromPersistedLayout(reason: trigger)
            if let validationContext {
                schedulePositionValidation(context: validationContext, recoveryCount: recoveryCount + 1)
            }

        case .bumpAutosaveVersion:
            guard !isExecutingStatusItemRecovery else {
                logger.warning("Skipping overlapping status item recovery action for \(trigger, privacy: .public)")
                return
            }
            isExecutingStatusItemRecovery = true
            positionValidationGeneration += 1
            defer { isExecutingStatusItemRecovery = false }
            let (newMain, newSep) = statusBarController.recreateItemsWithBumpedVersion()
            statusBarController.onItemsRecreated?(newMain, newSep)
            if let validationContext {
                schedulePositionValidation(context: validationContext, recoveryCount: recoveryCount + 1)
            }

        case let .stop(reason):
            logger.error(
                "Status item recovery stopped after \(recoveryCount, privacy: .public) attempt(s) for \(trigger, privacy: .public); last reason=\(reason?.rawValue ?? "none", privacy: .public)"
            )

        case .keepExpanded, .performInitialHide:
            break
        }
    }

    /// Validate status-item position after layout settles. If WindowServer has a
    /// corrupted position cache, recover by bumping autosave namespace and recreating.
    private func schedulePositionValidation(
        context: MenuBarOperationCoordinator.PositionValidationContext = .startupFollowUp,
        recoveryCount: Int = 0
    ) {
        positionValidationGeneration += 1
        let validationGeneration = positionValidationGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }

            let initialDelay = Self.statusItemValidationInitialDelaySeconds(
                context: context,
                recoveryCount: recoveryCount
            )
            let initialDelayDuration: Duration = .milliseconds(Int(initialDelay * 1000))
            let retryDelay: Duration = .milliseconds(250)
            let maxAttempts = 4

            try? await Task.sleep(for: initialDelayDuration)
            guard self.positionValidationGeneration == validationGeneration else {
                logger.debug("Skipping stale status item validation task for \(context.rawValue, privacy: .public)")
                return
            }

            var lastSnapshot: MenuBarRuntimeSnapshot?
            var lastAlwaysHiddenNeedsRepair = false

            for attempt in 1 ... maxAttempts {
                guard self.positionValidationGeneration == validationGeneration else {
                    logger.debug("Aborting stale status item validation retry for \(context.rawValue, privacy: .public)")
                    return
                }

                let snapshot = self.currentStatusItemRecoverySnapshot()
                let recoveryReason = MenuBarOperationCoordinator.startupRecoveryReason(snapshot: snapshot)
                let alwaysHiddenNeedsRepair = self.stableSnapshotNeedsAlwaysHiddenRepair(snapshot)

                lastSnapshot = snapshot
                lastAlwaysHiddenNeedsRepair = alwaysHiddenNeedsRepair

                if recoveryReason == nil, !alwaysHiddenNeedsRepair {
                    let capturedBackup = await self.captureCurrentDisplayBackupAfterStableValidation()
                    if !capturedBackup {
                        logger.warning(
                            "Status item validation reached a healthy layout without a current-width backup for \(context.rawValue, privacy: .public)"
                        )
                    }
                    if attempt > 1 {
                        logger.info("Status item position validation recovered after \(attempt, privacy: .public) checks")
                    }
                    return
                }

                if alwaysHiddenNeedsRepair {
                    self.logAlwaysHiddenSeparatorRecoveryNeed(
                        snapshot: snapshot,
                        prefix: "Status item validation"
                    )
                    self.repairAlwaysHiddenSeparatorPositionIfNeeded(reason: "position-validation-\(context.rawValue)")
                } else {
                    self.logStatusItemRecoveryReason(
                        recoveryReason,
                        snapshot: snapshot,
                        prefix: "Status item validation"
                    )
                }

                if attempt < maxAttempts {
                    try? await Task.sleep(for: retryDelay)
                }
            }

            guard self.positionValidationGeneration == validationGeneration else {
                logger.debug("Skipping stale recovery escalation for \(context.rawValue, privacy: .public)")
                return
            }

            if lastAlwaysHiddenNeedsRepair {
                logger.error(
                    "Always-hidden separator remained misordered after \(maxAttempts, privacy: .public) checks — triggering persisted-layout recovery"
                )
                let action = MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                    context: context,
                    recoveryCount: recoveryCount,
                    maxRecoveryCount: Self.maxStatusItemRecoveryCount
                )
                self.executeStatusItemRecoveryAction(
                    action,
                    trigger: "always-hidden-position-validation-\(context.rawValue)",
                    validationContext: context,
                    recoveryCount: recoveryCount,
                    validationGeneration: validationGeneration
                )
                return
            }

            logger.error(
                "Status item remained off-menu-bar after \(maxAttempts, privacy: .public) checks — triggering autosave recovery"
            )
            let snapshot = lastSnapshot ?? self.currentStatusItemRecoverySnapshot()
            let action = MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(context),
                recoveryCount: recoveryCount,
                maxRecoveryCount: Self.maxStatusItemRecoveryCount
            )
            self.executeStatusItemRecoveryAction(
                action,
                trigger: "position-validation-\(context.rawValue)",
                validationContext: context,
                recoveryCount: recoveryCount,
                validationGeneration: validationGeneration
            )
        }
    }

    private func setupObservers() {
        // Observe hiding state changes
        hidingService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.hidingState = state
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)

        // Observe settings changes to update all dependent services and persist
        $settings
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.updateSpacers()
                self?.updateAppearance()
                self?.updateNetworkTrigger(enabled: newSettings.showOnNetworkChange)
                self?.updateFocusModeTrigger(enabled: newSettings.showOnFocusModeChange)
                self?.updateScheduleTrigger(enabled: newSettings.showOnSchedule)
                self?.updateScriptTrigger(settings: newSettings)
                self?.triggerService.updateBatteryMonitoring(enabled: newSettings.showOnLowBattery)
                self?.updateHoverService()
                self?.syncUpdateConfiguration()
                self?.updateMainIconVisibility()
                self?.updateDividerStyle()
                self?.updateIconStyle()
                self?.updateAlwaysHiddenSeparator()
                self?.enforceExternalMonitorVisibilityPolicy(reason: "settingsChanged")
                if newSettings.showDockIcon {
                    self?.restoreApplicationMenusIfNeeded(reason: "dockIconEnabled")
                } else if self?.hidingState == .expanded {
                    self?.scheduleAppMenuSuppressionEvaluation()
                }
                self?.saveSettings() // Auto-persist all settings changes
            }
            .store(in: &cancellables)

        // Rehide on app change - hide when user switches to a different app
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if hidingState == .expanded {
                    scheduleAppMenuSuppressionEvaluation()
                }

                let activatedBundleID =
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                        .bundleIdentifier
                let browseSessionActive = SearchWindowController.shared.isBrowseSessionActive
                let ownBundleID = Bundle.main.bundleIdentifier

                if Self.shouldScheduleRehideOnAppChange(
                    rehideOnAppChange: settings.rehideOnAppChange,
                    hidingState: hidingState,
                    isRevealPinned: isRevealPinned,
                    shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor,
                    isBrowseSessionActive: browseSessionActive,
                    activatedBundleID: activatedBundleID,
                    ownBundleID: ownBundleID
                ) {
                    logger.debug(
                        "App changed - scheduling auto-hide for \(activatedBundleID ?? "unknown", privacy: .public)"
                    )
                    hidingService.scheduleRehide(after: 0.5)
                } else if settings.rehideOnAppChange, hidingState == .expanded {
                    if browseSessionActive {
                        logger.debug("App changed - skipping auto-hide while Browse Icons is active")
                    } else if let activatedBundleID,
                              let ownBundleID,
                              activatedBundleID == ownBundleID {
                        logger.debug("App changed - ignoring SaneBar self-activation")
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .hiddenSectionShown)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAppMenuSuppressionEvaluation()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .hiddenSectionHidden)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.restoreApplicationMenusIfNeeded(reason: "sectionHidden")
            }
            .store(in: &cancellables)

        // Invalidate cached separator position when screen geometry changes
        // (monitor plugged/unplugged, resolution change, etc.)
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearCachedSeparatorGeometry()
                logger.debug("Screen parameters changed — invalidated cached separator positions")
                self?.enforceExternalMonitorVisibilityPolicy(reason: "screenParametersChanged")
                self?.schedulePositionValidation(context: .screenParametersChanged)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.positionValidationGeneration += 1
                self.clearCachedSeparatorGeometry()
                logger.debug("System will sleep — cancelled pending position validation and invalidated cached separator positions")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.positionValidationGeneration += 1
                self.clearCachedSeparatorGeometry()
                logger.debug("Screens did sleep — cancelled pending position validation and invalidated cached separator positions")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.clearCachedSeparatorGeometry()
                logger.debug("System did wake — invalidated cached separator positions")
                self.enforceExternalMonitorVisibilityPolicy(reason: "wakeResume")
                self.schedulePositionValidation(context: .wakeResume)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.clearCachedSeparatorGeometry()
                logger.debug("Screens did wake — invalidated cached separator positions")
                self.enforceExternalMonitorVisibilityPolicy(reason: "wakeResume")
                self.schedulePositionValidation(context: .wakeResume)
            }
            .store(in: &cancellables)

        // Always-hidden pin enforcement: if a pinned app launches later, move it into place.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                guard alwaysHiddenSeparatorItem != nil else { return }
                guard !settings.alwaysHiddenPinnedItemIds.isEmpty else { return }

                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }

                let pinnedBundleIds = alwaysHiddenPinnedBundleIds()
                guard pinnedBundleIds.contains(bundleID) else { return }

                scheduleAlwaysHiddenPinEnforcement(
                    reason: "didLaunch:\(bundleID)",
                    filterBundleId: bundleID,
                    delay: .seconds(1)
                )
            }
            .store(in: &cancellables)

        LicenseService.shared.$isPro
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.normalizeLicenseDependentDefaults()
            }
            .store(in: &cancellables)
    }

    func clearStatusItemMenus() {
        mainStatusItem?.menu = nil
        separatorItem?.menu = nil
        alwaysHiddenSeparatorItem?.menu = nil
        mainStatusItem?.button?.menu = nil
        separatorItem?.button?.menu = nil
        alwaysHiddenSeparatorItem?.button?.menu = nil
    }

    private func updateDividerStyle() {
        let isHidden = hidingService.state == .hidden
        statusBarController.updateSeparatorStyle(settings.dividerStyle, isHidden: isHidden)
    }

    private func updateIconStyle() {
        let style = settings.menuBarIconStyle
        if style == .custom {
            let customIcon = (persistenceService as? PersistenceService)?.loadCustomIcon()
            statusBarController.updateIconStyle(style, customIcon: customIcon)
        } else {
            statusBarController.updateIconStyle(style)
        }
    }

    func updateAlwaysHiddenSeparator() {
        statusBarController.ensureAlwaysHiddenSeparator(enabled: currentEffectiveAlwaysHiddenSectionEnabled())
        alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
    }

    func updateAlwaysHiddenSeparatorIfReady(forceRecreateIfMissing: Bool = false) {
        guard let statusBarControllerStorage else { return }
        updateAlwaysHiddenSeparator()
        guard forceRecreateIfMissing,
              currentEffectiveAlwaysHiddenSectionEnabled(),
              alwaysHiddenSeparatorItem == nil
        else { return }

        logger.warning("Force-recreating always-hidden separator after nil update")
        statusBarControllerStorage.ensureAlwaysHiddenSeparator(enabled: false)
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
        statusBarControllerStorage.ensureAlwaysHiddenSeparator(enabled: true)
        alwaysHiddenSeparatorItem = statusBarControllerStorage.alwaysHiddenSeparatorItem
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
        AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
    }

    func enforceExternalMonitorVisibilityPolicy(reason: String) {
        guard settings.disableOnExternalMonitor else { return }
        guard shouldSkipHideForExternalMonitor else { return }

        logger.info("Enforcing external monitor visibility policy (\(reason, privacy: .public))")
        hidingService.cancelRehide()

        Task { @MainActor in
            if self.hidingService.state == .hidden {
                await self.hidingService.show()
            }
        }
    }

    // MARK: - Main Icon Visibility

    /// Show or hide the main SaneBar icon based on settings
    /// When main icon is hidden, separator becomes the primary click target for toggle
    func updateMainIconVisibility() {
        guard let mainItem = mainStatusItem,
              let separator = separatorItem else { return }

        if settings.hideMainIcon {
            settings.hideMainIcon = false
            settingsController.settings.hideMainIcon = false
            settingsController.saveQuietly()
            logger.info("hideMainIcon is deprecated - forcing visible main icon")
        }

        mainItem.isVisible = true
        separator.isVisible = true
        alwaysHiddenSeparatorItem?.isVisible = true
        mainItem.menu = nil
        mainItem.button?.menu = nil

        // Always wire main icon for left/right click toggle + menu
        if let button = mainItem.button {
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Separator should only offer right-click menu
        if let button = separator.button {
            button.action = nil
            button.target = nil
            button.sendAction(on: [])
        }

        separator.menu = nil
        separator.button?.menu = nil

        clearStatusItemMenus()

        logger.info("Main icon visible - separator menu-only mode")
    }

    private func updateAppearance() {
        appearanceService.updateAppearance(settings.menuBarAppearance)
    }

    private func updateHoverService() {
        hoverService.isEnabled = settings.showOnHover
        hoverService.scrollEnabled = settings.showOnScroll
        hoverService.clickEnabled = settings.showOnClick
        hoverService.userDragEnabled = settings.showOnUserDrag
        hoverService.trackMouseLeave = settings.autoRehide
        hoverService.hoverDelay = settings.hoverDelay

        let needsMonitoring = settings.showOnHover ||
            settings.showOnScroll ||
            settings.showOnClick ||
            settings.showOnUserDrag ||
            settings.autoRehide

        if needsMonitoring {
            hoverService.start()
        } else {
            hoverService.stop()
        }
    }

    private func updateNetworkTrigger(enabled: Bool) {
        if enabled {
            networkTriggerService.startMonitoring()
        } else {
            networkTriggerService.stopMonitoring()
        }
    }

    private func updateFocusModeTrigger(enabled: Bool) {
        if enabled {
            focusModeService.startMonitoring()
        } else {
            focusModeService.stopMonitoring()
        }
    }

    private func updateScheduleTrigger(enabled: Bool) {
        if enabled {
            scheduleTriggerService.startMonitoring()
        } else {
            scheduleTriggerService.stopMonitoring()
        }
    }

    private func updateScriptTrigger(settings: SaneBarSettings) {
        if settings.scriptTriggerEnabled {
            scriptTriggerService.restartIfRunning()
            scriptTriggerService.startMonitoring()
        } else {
            scriptTriggerService.stopMonitoring()
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        settingsController.loadOrDefault()
        settings = settingsController.settings

        // BUG-023 Fix: Apply dock visibility IMMEDIATELY on settings load
        // This prevents the dock icon from flashing visible on startup when disabled
        SaneActivationPolicy.applyPolicy(showDockIcon: settings.showDockIcon)
    }

    func saveSettings() {
        settingsController.settings = settings
        settingsController.saveQuietly()
        iconHotkeysService.registerHotkeys(from: settings)
        updateHoverService()
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        settingsController.resetToDefaults()
        settings = settingsController.settings
        updateSpacers()
        updateAppearance()
        iconHotkeysService.registerHotkeys(from: settings)
        logger.info("All settings reset to defaults")
    }

    // MARK: - Appearance

    private func updateStatusItemAppearance() {
        statusBarController.updateAppearance(for: hidingState)
    }

    // MARK: - Spacers

    /// Update spacer items based on settings
    func updateSpacers() {
        statusBarController.updateSpacers(
            count: settings.spacerCount,
            style: settings.spacerStyle,
            width: settings.spacerWidth
        )
    }

    func restoreStatusItemLayoutIfNeeded() {
        guard statusBarControllerStorage != nil else { return }
        let snapshot = currentStatusItemRecoverySnapshot()
        let action = MenuBarOperationCoordinator.statusItemRecoveryAction(
            snapshot: snapshot,
            context: .manualLayoutRestoreRequest,
            recoveryCount: 0,
            maxRecoveryCount: Self.maxStatusItemRecoveryCount
        )
        executeStatusItemRecoveryAction(
            action,
            trigger: "manual-layout-restore",
            validationContext: .manualLayoutRestore,
            recoveryCount: 0
        )
    }

    private func recreateStatusItemsFromPersistedLayout(reason: String) {
        lastKnownSeparatorX = nil
        lastKnownSeparatorRightEdgeX = nil
        lastKnownAlwaysHiddenSeparatorX = nil
        lastKnownAlwaysHiddenSeparatorRightEdgeX = nil
        let (newMain, newSeparator) = statusBarController.recreateItemsFromPersistedPositions()
        statusBarController.onItemsRecreated?(newMain, newSeparator)
        logger.info("Recreated status items from persisted layout (\(reason, privacy: .public))")
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        if !settings.hasCompletedOnboarding {
            // New user — apply Smart defaults and show full onboarding
            settings.autoRehide = true
            settings.rehideDelay = 5.0
            settings.showOnHover = true
            settings.showOnScroll = true
            settings.showOnUserDrag = true
            settings.hasSeenFreemiumIntro = true
            saveSettings()
            Task.detached { await EventTracker.log("new_free_user") }

            // Enable launch at login by default (installed app only).
            if canMutateLaunchAtLogin() {
                try? SMAppService.mainApp.register()
                logger.info("Applied Smart defaults for first-launch onboarding (incl. launch at login)")
            } else {
                logger.warning("Skipping launch-at-login auto-register for non-canonical app path: \(Bundle.main.bundleURL.path, privacy: .public)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardingController.shared.show()
            }
        } else if !settings.hasSeenFreemiumIntro {
            // Existing user upgrading — show freemium intro once.
            // Do NOT auto-grant Pro from local settings state; that path is spoofable.
            settings.hasSeenFreemiumIntro = true
            saveSettings()
            logger.info("Legacy upgrade detected — showing freemium intro (manual grant only)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardingController.shared.show()
            }
        }
    }
}

// swiftlint:enable file_length
