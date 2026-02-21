import AppKit
import Combine
import os.log
import ServiceManagement
import SwiftUI

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
    enum HideRequestOrigin: Sendable {
        case manual
        case automatic
    }

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

    /// Returns true if the main screen has a notch (MacBook Pro 14/16 inch models)
    var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
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
        shouldIgnoreHideRequest(origin: .automatic)
    }

    func shouldIgnoreHideRequest(origin: HideRequestOrigin) -> Bool {
        Self.shouldIgnoreHideRequest(
            disableOnExternalMonitor: settings.disableOnExternalMonitor,
            isOnExternalMonitor: isOnExternalMonitor,
            origin: origin
        )
    }

    static func shouldSkipHide(disableOnExternalMonitor: Bool, isOnExternalMonitor: Bool) -> Bool {
        shouldIgnoreHideRequest(
            disableOnExternalMonitor: disableOnExternalMonitor,
            isOnExternalMonitor: isOnExternalMonitor,
            origin: .automatic
        )
    }

    static func shouldIgnoreHideRequest(
        disableOnExternalMonitor: Bool,
        isOnExternalMonitor: Bool,
        origin: HideRequestOrigin
    ) -> Bool {
        disableOnExternalMonitor && isOnExternalMonitor && origin == .automatic
    }

    static func shouldRecoverStartupPositions(separatorX: CGFloat?, mainX: CGFloat?) -> Bool {
        guard let separatorX, let mainX else { return false }
        guard separatorX > 0, mainX > 0 else { return false }
        return separatorX >= mainX
    }

    // MARK: - Services

    let hidingService: HidingService
    let persistenceService: PersistenceServiceProtocol
    let settingsController: SettingsController
    let statusBarController: StatusBarController
    let triggerService: TriggerService
    let iconHotkeysService: IconHotkeysService
    let appearanceService: MenuBarAppearanceService
    let networkTriggerService: NetworkTriggerService
    let focusModeService: FocusModeService
    let scheduleTriggerService: ScheduleTriggerService
    let scriptTriggerService: ScriptTriggerService
    let hoverService: HoverService
    let updateService: UpdateService

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
    var statusMenu: NSMenu?
    private var onboardingPopover: NSPopover?
    /// Flag to prevent setupStatusItem from overwriting externally-provided items
    private var usingExternalItems = false

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

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
        self.statusBarController = statusBarController ?? StatusBarController()
        self.triggerService = triggerService ?? TriggerService()
        self.iconHotkeysService = iconHotkeysService ?? IconHotkeysService.shared
        self.appearanceService = appearanceService ?? MenuBarAppearanceService()
        self.networkTriggerService = networkTriggerService ?? NetworkTriggerService()
        self.focusModeService = focusModeService ?? FocusModeService()
        self.scheduleTriggerService = scheduleTriggerService ?? ScheduleTriggerService()
        self.scriptTriggerService = scriptTriggerService ?? ScriptTriggerService()
        self.hoverService = hoverService ?? HoverService()
        self.updateService = updateService ?? UpdateService()

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
                    _ = await self.showHiddenItemsNow(trigger: .automation)

                case let .scroll(direction):
                    if self.settings.useDirectionalScroll {
                        // Ice-style directional: up=show, down=hide (standard behavior)
                        // Takes priority over gestureToggles for scrolling
                        if direction == .up {
                            _ = await self.showHiddenItemsNow(trigger: .automation)
                        } else if !self.shouldSkipHideForExternalMonitor {
                            self.hideHiddenItems()
                        }
                    } else if self.settings.gestureToggles {
                        // Legacy toggle mode (any scroll toggles) - for backwards compatibility
                        if self.shouldSkipHideForExternalMonitor {
                            _ = await self.showHiddenItemsNow(trigger: .automation)
                        } else {
                            self.toggleHiddenItems()
                        }
                    } else {
                        // Show only: scroll reveals without hiding
                        _ = await self.showHiddenItemsNow(trigger: .automation)
                    }

                case .click:
                    if self.settings.gestureToggles {
                        // Toggle can hide, so respect external monitor setting
                        if self.shouldSkipHideForExternalMonitor {
                            // On external monitor with setting enabled - only allow show
                            _ = await self.showHiddenItemsNow(trigger: .automation)
                        } else {
                            self.toggleHiddenItems()
                        }
                    } else {
                        _ = await self.showHiddenItemsNow(trigger: .automation)
                    }

                case .userDrag:
                    // ⌘+drag: reveal all icons so user can rearrange
                    _ = await self.showHiddenItemsNow(trigger: .automation)
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

    // MARK: - External Item Injection

    /// Use status items that were created externally (by SaneBarAppDelegate)
    /// This is the WORKING approach - items created before MenuBarManager
    /// with pre-set position values appear on the RIGHT side correctly.
    func useExistingItems(main: NSStatusItem, separator: NSStatusItem) {
        logger.info("Using externally-created status items")

        // Set flag FIRST to prevent setupStatusItem from overwriting these items
        usingExternalItems = true

        // IMPORTANT: Remove the items that StatusBarController created in its init()
        // because we want to use the externally-created ones with correct positioning
        NSStatusBar.system.removeStatusItem(statusBarController.mainItem)
        NSStatusBar.system.removeStatusItem(statusBarController.separatorItem)
        logger.info("Removed StatusBarController's auto-created items")

        // Store the external items
        mainStatusItem = main
        separatorItem = separator
        statusBarController.ensureAlwaysHiddenSeparator(enabled: settings.alwaysHiddenSectionEnabled)
        alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem

        // Wire up click handler for main item
        if let button = main.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Setup menu (shown via right-click on main icon)
        statusMenu = statusBarController.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(menuToggleHiddenItems),
            findIconAction: #selector(openFindIcon),
            settingsAction: #selector(openSettings),
            checkForUpdatesAction: #selector(userDidClickCheckForUpdates),
            quitAction: #selector(quitApp),
            target: self
        ))
        statusMenu?.delegate = self
        separator.menu = nil
        clearStatusItemMenus()

        // Configure hiding service with delimiter
        hidingService.configure(delimiterItem: separator)
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)

        // Now do the rest of setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }

            updateSpacers()
            setupObservers()
            updateAppearance()

            triggerService.configure(menuBarManager: self)
            iconHotkeysService.configure(with: self)
            networkTriggerService.configure(menuBarManager: self)
            if settings.showOnNetworkChange {
                networkTriggerService.startMonitoring()
            }

            focusModeService.configure(menuBarManager: self)
            if settings.showOnFocusModeChange {
                focusModeService.startMonitoring()
            }

            scheduleTriggerService.configure(menuBarManager: self)
            if settings.showOnSchedule {
                scheduleTriggerService.startMonitoring()
            }

            scriptTriggerService.configure(menuBarManager: self)
            if settings.scriptTriggerEnabled {
                scriptTriggerService.startMonitoring()
            }

            configureHoverService()
            showOnboardingIfNeeded()
            syncUpdateConfiguration()
            updateMainIconVisibility()
            updateDividerStyle()
            updateIconStyle()

            logger.info("External items setup complete")
        }
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
        let initialDelay: TimeInterval = {
            if let delayMs = ProcessInfo.processInfo.environment["SANEBAR_STATUSITEM_DELAY_MS"],
               let delayValue = Double(delayMs) {
                return max(0.0, delayValue / 1000.0)
            }
            return 0.1
        }()

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

    private func setupStatusItem() {
        // If using external items (from useExistingItems), skip this setup
        // because the external items are already configured and we don't want to overwrite them
        if usingExternalItems {
            logger.info("Skipping setupStatusItem - using external items")
            return
        }

        // Configure status items (already created as property initializers)
        statusBarController.configureStatusItems(
            clickAction: #selector(statusItemClicked),
            target: self
        )

        // Copy references for local use
        mainStatusItem = statusBarController.mainItem
        separatorItem = statusBarController.separatorItem
        statusBarController.ensureAlwaysHiddenSeparator(enabled: settings.alwaysHiddenSectionEnabled)
        alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem

        // Setup menu using controller (shown via right-click on main icon)
        statusMenu = statusBarController.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(menuToggleHiddenItems),
            findIconAction: #selector(openFindIcon),
            settingsAction: #selector(openSettings),
            checkForUpdatesAction: #selector(userDidClickCheckForUpdates),
            quitAction: #selector(quitApp),
            target: self
        ))
        statusMenu?.delegate = self
        clearStatusItemMenus()

        // Configure hiding service with delimiter
        if let separator = separatorItem {
            hidingService.configure(delimiterItem: separator)
        }
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)

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

                // Startup invariant: the separator must be left of the main icon.
                // If not, soft-recover seeds and keep the bar visible for this run.
                let startupSeparatorX = self.getSeparatorOriginX()
                let startupMainX = self.getMainStatusItemLeftEdgeX()
                if Self.shouldRecoverStartupPositions(separatorX: startupSeparatorX, mainX: startupMainX) {
                    logger.error(
                        "Startup invariant failed (separator=\(startupSeparatorX ?? -1, privacy: .public), main=\(startupMainX ?? -1, privacy: .public)) — applying soft recovery and skipping initial hide"
                    )
                    StatusBarController.recoverStartupPositions(alwaysHiddenEnabled: self.settings.alwaysHiddenSectionEnabled)
                    self.lastKnownSeparatorX = nil
                    self.lastKnownSeparatorRightEdgeX = nil
                    self.lastKnownAlwaysHiddenSeparatorX = nil
                    await self.hidingService.show()
                    return
                }

                // Repair AH separator ordering drift before any startup hide.
                self.repairAlwaysHiddenSeparatorPositionIfNeeded(reason: "startup")

                // If the user has pinned items to the always-hidden section, enforce them early
                // (before initial hide) to reduce startup drift/flicker.
                await self.enforceAlwaysHiddenPinnedItems(reason: "startup")

                // Skip startup hide if user is on external monitor
                if self.shouldSkipHideForExternalMonitor {
                    logger.info("Skipping initial hide: user is on external monitor")
                    return
                }
                // Also skip if setting is enabled and any external monitor is connected
                // (mouse may be on built-in now but user wants icons visible on external)
                if self.settings.disableOnExternalMonitor,
                   NSScreen.screens.contains(where: { screen in
                       guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
                       return CGDisplayIsBuiltin(displayID) == 0
                   }) {
                    logger.info("Skipping initial hide: external monitor connected with always-show enabled")
                    return
                }
                await self.hidingService.hide()
                logger.info("Initial hide complete")
            }
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
                self?.saveSettings() // Auto-persist all settings changes
            }
            .store(in: &cancellables)

        // Rehide on app change - hide when user switches to a different app
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Only trigger if the setting is enabled and icons are currently visible
                if settings.rehideOnAppChange,
                   hidingState == .expanded,
                   !isRevealPinned,
                   !shouldSkipHideForExternalMonitor {
                    logger.debug("App changed - triggering auto-hide")
                    hidingService.scheduleRehide(after: 0.5) // Small delay for smooth transition
                }
            }
            .store(in: &cancellables)

        // Invalidate cached separator position when screen geometry changes
        // (monitor plugged/unplugged, resolution change, etc.)
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastKnownSeparatorX = nil
                self?.lastKnownSeparatorRightEdgeX = nil
                self?.lastKnownAlwaysHiddenSeparatorX = nil
                logger.debug("Screen parameters changed — invalidated cached separator positions")
                self?.enforceExternalMonitorVisibilityPolicy(reason: "screenParametersChanged")
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

    private func updateAlwaysHiddenSeparator() {
        statusBarController.ensureAlwaysHiddenSeparator(enabled: settings.alwaysHiddenSectionEnabled)
        alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
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
        ActivationPolicyManager.applyPolicy(showDockIcon: settings.showDockIcon)
    }

    func saveSettings() {
        // Sync to controller and save
        settingsController.settings = settings
        settingsController.saveQuietly()
        // Re-register hotkeys when settings change
        iconHotkeysService.registerHotkeys(from: settings)
        // Ensure hover service is updated
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

            // Enable launch at login by default
            try? SMAppService.mainApp.register()
            logger.info("Applied Smart defaults for first-launch onboarding (incl. launch at login)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardingController.shared.show()
            }
        } else if !settings.hasSeenFreemiumIntro {
            // Existing user upgrading — grant early adopter Pro and re-show onboarding
            settings.hasSeenFreemiumIntro = true
            saveSettings()
            LicenseService.shared.grantEarlyAdopterPro()
            logger.info("Early adopter detected — granted Pro, re-showing onboarding")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardingController.shared.show()
            }
        }
    }
}
