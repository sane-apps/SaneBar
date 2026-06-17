import AppKit
import Combine
import os.log
import SaneUI
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
final class MenuBarManager: NSObject, ObservableObject {
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

    func setObservedHidingState(_ state: HidingState) {
        hidingState = state
    }

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
    var lastMenuBarRevealTrigger: MenuBarRevealTrigger = .automation
    /// Monotonic token used to invalidate older position-validation passes when
    /// screen/wake notifications or recovery flows schedule a newer pass.
    var positionValidationGeneration: Int = 0
    /// Prevent overlapping structural recovery passes from tearing down and
    /// rebuilding the status items multiple times inside one launch.
    var isExecutingStatusItemRecovery = false
    /// Debounce unexpected status-item visibility recovery so one removal or
    /// WindowServer blip cannot trigger multiple structural recreates in a row.
    var lastUnexpectedVisibilityRecoveryAt: Date?

    /// Rate limiting for auth attempts (security hardening)
    var failedAuthAttempts: Int = 0
    var lastFailedAuthTime: Date?
    let maxFailedAttempts: Int = 5
    let lockoutDuration: TimeInterval = 30 // seconds

    /// Reference to the currently active icon move task to ensure atomicity
    var activeMoveTask: Task<Bool, Never>?
    var lastManualZoneMoveSettledAt: Date?

    /// Best-effort enforcement task for pinned always-hidden items (avoid overlapping runs)
    var alwaysHiddenPinEnforcementTask: Task<Void, Never>?
    /// Best-effort enforcement task for hide-all-other profile rules.
    var hideAllOtherRuleEnforcementTask: Task<Void, Never>?
    /// Retries persisted visibility intent replay after wake/recovery until anchors are healthy.
    var visibilityIntentReplayTask: Task<Void, Never>?
    /// Tracks delayed AH separator repair verification so newer moves/recoveries can cancel stale follow-ups.
    var alwaysHiddenSeparatorRepairFollowUpTask: Task<Void, Never>?
    var alwaysHiddenSeparatorRepairGeneration: Int = 0
    var lastAlwaysHiddenRepairAt: Date?
    var isRepairingAlwaysHiddenSeparator = false
    var mainStatusItemHoverTrackingArea: NSTrackingArea?

    // MARK: - Screen Detection

    private let statusItemScreenResolver = StatusItemScreenResolver()

    private func cachedStatusItemScreen() -> NSScreen? {
        statusItemScreenResolver.screen(mainStatusItem: mainStatusItem, separatorItem: separatorItem)
    }

    private var statusItemScreen: NSScreen? {
        cachedStatusItemScreen()
    }

    func currentRecoveryReferenceScreen() -> NSScreen? {
        statusItemScreen
    }

    /// Returns true if the main screen has a notch (MacBook Pro 14/16 inch models)
    var hasNotch: Bool {
        guard let screen = statusItemScreen else { return false }
        // auxiliaryTopLeftArea is non-nil on notched Macs (macOS 12+)
        return screen.auxiliaryTopLeftArea != nil
    }

    /// Returns true if the mouse cursor is currently on an external (non-built-in) monitor
    var isOnExternalMonitor: Bool {
        guard let resolvedScreen = statusItemScreen else {
            return true
        }

        return statusItemScreenResolver.isExternalScreen(resolvedScreen)
    }

    /// Check if hiding should be skipped due to external monitor setting
    var shouldSkipHideForExternalMonitor: Bool {
        MenuBarVisibilityPolicy.shouldSkipHide(
            disableOnExternalMonitor: settings.disableOnExternalMonitor,
            isOnExternalMonitor: isOnExternalMonitor
        )
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
    var statusBarControllerStorage: StatusBarController?

    // MARK: - Status Items

    /// Main SaneBar icon you click (always visible)
    var mainStatusItem: NSStatusItem?
    /// Separator that expands to hide items (the actual delimiter)
    var separatorItem: NSStatusItem?
    /// Optional separator for always-hidden zone (experimental)
    var alwaysHiddenSeparatorItem: NSStatusItem?
    let geometryCache = MenuBarGeometryCache()
    lazy var geometryResolver = MenuBarGeometryResolver(manager: self)
    lazy var moveTargetResolver = MenuBarMoveTargetResolver(manager: self)
    lazy var moveTaskCoordinator = MenuBarMoveTaskCoordinator(manager: self)
    lazy var moveQueueWorkflow = MenuBarMoveQueueWorkflow(manager: self)
    lazy var statusItemSetupWorkflow = MenuBarStatusItemSetupWorkflow(manager: self)
    lazy var statusItemRecoveryWorkflow = MenuBarStatusItemRecoveryWorkflow(manager: self)
    lazy var visibilityWorkflow = MenuBarVisibilityWorkflow(manager: self)
    lazy var observerWorkflow = MenuBarObserverWorkflow(manager: self)
    lazy var lifecycleWorkflow = MenuBarLifecycleWorkflow(manager: self)
    lazy var actionWorkflow = MenuBarActionWorkflow(manager: self)
    lazy var hideAllOtherWorkflow = MenuBarHideAllOtherWorkflow(manager: self)
    lazy var profileWorkflow = MenuBarProfileWorkflow(manager: self)
    lazy var iconReorderWorkflow = MenuBarIconReorderWorkflow(manager: self)
    lazy var standardIconMoveWorkflow = MenuBarStandardIconMoveWorkflow(manager: self)
    lazy var alwaysHiddenIconMoveWorkflow = MenuBarAlwaysHiddenIconMoveWorkflow(manager: self)
    lazy var alwaysHiddenPinWorkflow = MenuBarAlwaysHiddenPinWorkflow(manager: self)
    /// Recovery rebuilds temporarily reconfigure the delimiter in expanded mode.
    /// Preserve a prior hidden state so wake/display recovery can restore it.
    var pendingRecoveryHideRestore = false
    /// Explicitly tracks the post-create/recreate bootstrap window where status
    /// items exist but live geometry is still settling.
    var statusItemBootstrapPhase: MenuBarBootstrapPhase = .steady
    var statusMenu: NSMenu?

    // MARK: - Initialization

    var statusBarController: StatusBarController {
        guard let controller = statusBarControllerStorage else {
            preconditionFailure("StatusBarController accessed before deferred UI setup")
        }
        return controller
    }

    @discardableResult
    func ensureStatusBarController() -> StatusBarController {
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

    nonisolated static let maxStatusItemRecoveryCount = 4
    nonisolated static let maxVisibilityIntentReplayAttempts = 8
    nonisolated static let unexpectedVisibilityRecoveryDebounceSeconds: TimeInterval = 1.0

    nonisolated static func statusItemValidationInitialDelaySeconds(
        context: MenuBarOperationCoordinator.PositionValidationContext,
        recoveryCount: Int
    ) -> TimeInterval {
        MenuBarStatusItemRecoveryWorkflow.statusItemValidationInitialDelaySeconds(
            context: context,
            recoveryCount: recoveryCount
        )
    }

    nonisolated static func statusItemValidationRetryDelaySeconds(
        context: MenuBarOperationCoordinator.PositionValidationContext
    ) -> TimeInterval {
        MenuBarStatusItemRecoveryWorkflow.statusItemValidationRetryDelaySeconds(context: context)
    }

    nonisolated static func statusItemValidationMaxAttempts(
        context: MenuBarOperationCoordinator.PositionValidationContext
    ) -> Int {
        MenuBarStatusItemRecoveryWorkflow.statusItemValidationMaxAttempts(context: context)
    }

    nonisolated static func shouldRecoverUnexpectedVisibilityLoss(
        isVisible: Bool,
        isExecutingRecovery: Bool,
        lastRecoveryAt: Date?,
        now: Date,
        minimumInterval: TimeInterval
    ) -> Bool {
        MenuBarStatusItemRecoveryWorkflow.shouldRecoverUnexpectedVisibilityLoss(
            isVisible: isVisible,
            isExecutingRecovery: isExecutingRecovery,
            lastRecoveryAt: lastRecoveryAt,
            now: now,
            minimumInterval: minimumInterval
        )
    }

    nonisolated static func shouldResetPersistentStateForStatusItemRecovery(
        reason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        isStartupRecovery: Bool = false,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext? = nil
    ) -> Bool {
        MenuBarStatusItemRecoveryWorkflow.shouldResetPersistentStateForStatusItemRecovery(
            reason: reason,
            isStartupRecovery: isStartupRecovery,
            validationContext: validationContext
        )
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
        lifecycleWorkflow.loadSettings()

        // Defer ALL status-bar-dependent initialization to ensure WindowServer is ready
        // This fixes crashes on Mac Mini M4 and other systems where GUI isn't
        // immediately available at app launch (e.g., Login Items, fast boot)
        lifecycleWorkflow.deferredUISetup()
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

    func currentEffectiveAlwaysHiddenSectionEnabled() -> Bool {
        MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
            isPro: LicenseService.shared.isPro,
            alwaysHiddenSectionEnabled: settings.alwaysHiddenSectionEnabled
        )
    }

    @MainActor
    func scheduleInitialPositionValidationAfterStartup() {
        // Avoid racing the first geometry check against the startup
        // hide/recovery path. Validate only after launch settles.
        schedulePositionValidation(context: .startupFollowUp)
    }

    @MainActor
    func schedulePostRecoveryGeometryWarmup(restoreHiddenStateAfterWarmup: Bool = false) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
            try? await Task.sleep(for: .milliseconds(150))

            await self.geometryResolver.warmSeparatorPositionCache(maxAttempts: 32)
            await self.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 32)

            let snapshot = self.currentStatusItemRecoverySnapshot()
            if snapshot.separatorAnchorSource == .live, snapshot.mainAnchorSource == .live {
                logger.info("Warmed status item geometry caches after structural recovery")
            } else {
                logger.warning("Status item recovery completed before geometry caches could be re-warmed")
            }

            if restoreHiddenStateAfterWarmup {
                self.restoreHiddenStateAfterPostRecoveryGeometryWarmupIfNeeded(snapshot: snapshot)
            }

            self.appearanceService.refreshAfterStatusItemRecovery()
        }
    }

    @MainActor
    func clearCachedSeparatorGeometry() {
        geometryCache.clearSeparatorGeometry()
    }

    nonisolated static func shouldPreserveCachedGeometryForHiddenLifecycle(
        hidingState: HidingState,
        separatorX: CGFloat?,
        separatorRightEdgeX: CGFloat?,
        mainStatusItemX: CGFloat?,
        displayStillPresent: Bool
    ) -> Bool {
        guard hidingState == .hidden, displayStillPresent else { return false }
        guard let separatorX, separatorX.isFinite,
              let separatorRightEdgeX, separatorRightEdgeX.isFinite, separatorRightEdgeX > separatorX,
              let mainStatusItemX, mainStatusItemX.isFinite, mainStatusItemX > separatorRightEdgeX
        else {
            return false
        }
        return true
    }

    @MainActor
    func clearCachedSeparatorGeometryForLifecycleTransition(reason: String) {
        let displayStillPresent = statusItemScreenResolver.lastKnownDisplayStillPresent()

        guard !Self.shouldPreserveCachedGeometryForHiddenLifecycle(
            hidingState: hidingService.state,
            separatorX: geometryCache.lastKnownSeparatorX,
            separatorRightEdgeX: geometryCache.lastKnownSeparatorRightEdgeX,
            mainStatusItemX: geometryCache.lastKnownMainStatusItemX,
            displayStillPresent: displayStillPresent
        ) else {
            logger.info("Preserving cached separator geometry during \(reason, privacy: .public) while hidden")
            return
        }

        clearCachedSeparatorGeometry()
    }

    @MainActor
    func currentRuntimeSnapshot(
        identityPrecision: MenuBarIdentityPrecision = .unknown
    ) -> MenuBarRuntimeSnapshot {
        statusItemRecoveryWorkflow.currentRuntimeSnapshot(identityPrecision: identityPrecision)
    }

    @MainActor
    func markStatusItemsAwaitingAnchor(reason: String) {
        statusItemRecoveryWorkflow.markStatusItemsAwaitingAnchor(reason: reason)
    }

    @MainActor
    func currentStatusItemRecoverySnapshot() -> MenuBarRuntimeSnapshot {
        statusItemRecoveryWorkflow.currentStatusItemRecoverySnapshot()
    }

    @MainActor
    func logStatusItemRecoveryReason(
        _ reason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        snapshot: MenuBarRuntimeSnapshot,
        prefix: String
    ) {
        statusItemRecoveryWorkflow.logStatusItemRecoveryReason(reason, snapshot: snapshot, prefix: prefix)
    }

    @MainActor
    func executeStatusItemRecoveryAction(
        _ action: MenuBarOperationCoordinator.StatusItemRecoveryAction,
        trigger: String,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext? = nil,
        recoveryCount: Int = 0,
        validationGeneration: Int? = nil
    ) {
        statusItemRecoveryWorkflow.executeStatusItemRecoveryAction(
            action,
            trigger: trigger,
            validationContext: validationContext,
            recoveryCount: recoveryCount,
            validationGeneration: validationGeneration
        )
    }

    /// Validate status-item position after layout settles. If WindowServer has a
    /// corrupted position cache, recover by bumping autosave namespace and recreating.
    func schedulePositionValidation(
        context: MenuBarOperationCoordinator.PositionValidationContext = .startupFollowUp,
        recoveryCount: Int = 0
    ) {
        statusItemRecoveryWorkflow.schedulePositionValidation(
            context: context,
            recoveryCount: recoveryCount
        )
    }

    func clearStatusItemMenus() {
        mainStatusItem?.menu = nil
        separatorItem?.menu = nil
        alwaysHiddenSeparatorItem?.menu = nil
        mainStatusItem?.button?.menu = nil
        separatorItem?.button?.menu = nil
        alwaysHiddenSeparatorItem?.button?.menu = nil
    }

    func updateDividerStyle() {
        let isHidden = hidingService.state == .hidden
        statusBarController.updateSeparatorStyle(settings.dividerStyle, isHidden: isHidden)
    }

    func updateIconStyle() {
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
        statusItemSetupWorkflow.installStatusItemVisibilityObservers()
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
        statusItemSetupWorkflow.updateMainIconVisibility()
    }

    func installMainStatusItemHoverTrackingArea(on button: NSStatusBarButton) {
        statusItemSetupWorkflow.installMainStatusItemHoverTrackingArea(on: button)
    }

    @objc func mouseEntered(with event: NSEvent) {
        guard (event.trackingArea?.userInfo?["role"] as? String) == "mainStatusItem" else { return }
        guard settings.showOnHover else { return }

        Task { @MainActor in
            _ = await self.visibilityWorkflow.showHiddenItemsNow(trigger: .hover)
        }
    }

    func updateAppearance() {
        appearanceService.updateAppearance(settings.menuBarAppearance)
    }

    func updateHoverService() {
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

    func updateNetworkTrigger(enabled: Bool) {
        lifecycleWorkflow.updateNetworkTrigger(enabled: enabled)
    }

    func updateFocusModeTrigger(enabled: Bool) {
        lifecycleWorkflow.updateFocusModeTrigger(enabled: enabled)
    }

    func updateScheduleTrigger(enabled: Bool) {
        lifecycleWorkflow.updateScheduleTrigger(enabled: enabled)
    }

    func updateScriptTrigger(settings: SaneBarSettings) {
        lifecycleWorkflow.updateScriptTrigger(settings: settings)
    }

    // MARK: - Settings

    func saveSettings() {
        settingsController.settings = settings
        settingsController.saveQuietly()
        lifecycleWorkflow.applySettingsSideEffects()
    }

    func saveSettingsStrict() throws {
        settingsController.settings = settings
        try settingsController.save()
        lifecycleWorkflow.applySettingsSideEffects()
    }

    func schedulePostRecoveryVisibilityIntentReplay(reason: String) {
        let shouldReplayAlwaysHidden = !settings.alwaysHiddenPinnedItemIds.isEmpty
        let shouldReplayHideAllOther = settings.hideAllOtherMenuBarItems
        guard shouldReplayAlwaysHidden || shouldReplayHideAllOther else {
            schedulePostRecoveryAutoRehideIfNeeded(reason: "\(reason)-no-visibility-intent")
            return
        }

        visibilityIntentReplayTask?.cancel()
        visibilityIntentReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 1 ... Self.maxVisibilityIntentReplayAttempts {
                let delayMs = attempt == 1 ? 900 : 500
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { return }

                let replayReason = "\(reason)-attempt-\(attempt)"
                guard self.shouldRunVisibilityIntentEnforcement(reason: replayReason) else {
                    continue
                }

                var shouldRetryVisibilityReplay = false
                if shouldReplayAlwaysHidden {
                    let alwaysHiddenPinsEnforced = await self.alwaysHiddenPinWorkflow.enforce(reason: replayReason, mode: .auditOnly)
                    shouldRetryVisibilityReplay = !alwaysHiddenPinsEnforced || self.alwaysHiddenAnchorsNeedReplayRetry()
                    if shouldRetryVisibilityReplay {
                        logger.warning(
                            "Visibility intent replay waiting for healthy always-hidden anchors (\(replayReason, privacy: .public))"
                        )
                    }
                }
                if shouldReplayHideAllOther {
                    let hideAllOtherMode = self.visibilityIntentReplayHideAllOtherMode(reason: replayReason)
                    let hideAllOtherEnforced = await self.hideAllOtherWorkflow.enforce(
                        reason: replayReason,
                        mode: hideAllOtherMode.mode,
                        physicalMoveOrigin: hideAllOtherMode.physicalMoveOrigin
                    )
                    if !hideAllOtherEnforced {
                        logger.warning(
                            "Visibility intent replay waiting for hide-all-other completion (\(replayReason, privacy: .public))"
                        )
                        shouldRetryVisibilityReplay = true
                    }
                }
                if shouldRetryVisibilityReplay {
                    continue
                }
                self.schedulePostRecoveryAutoRehideIfNeeded(reason: replayReason)
                return
            }

            logger.warning(
                "Visibility intent replay gave up after \(Self.maxVisibilityIntentReplayAttempts, privacy: .public) attempts (\(reason, privacy: .public))"
            )
            self.schedulePostRecoveryAutoRehideIfNeeded(reason: "\(reason)-replay-gave-up")
        }
    }

    private func alwaysHiddenAnchorsNeedReplayRetry() -> Bool {
        guard !settings.alwaysHiddenPinnedItemIds.isEmpty else { return false }
        guard settings.alwaysHiddenSectionEnabled else { return false }
        guard alwaysHiddenSeparatorItem != nil else { return true }
        guard let alwaysHiddenBoundaryX = geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX(),
              let separatorFrame = geometryResolver.currentLiveSeparatorFrame(),
              alwaysHiddenBoundaryX.isFinite,
              separatorFrame.origin.x.isFinite
        else {
            return true
        }
        return alwaysHiddenBoundaryX >= separatorFrame.origin.x
    }

    func shouldRunVisibilityIntentEnforcement(reason: String) -> Bool {
        if isExecutingStatusItemRecovery {
            logger.debug("Visibility intent enforcement skipped during status-item recovery (\(reason, privacy: .public))")
            return false
        }

        let snapshot = currentStatusItemRecoverySnapshot()
        guard snapshot.structuralState == .ready,
              snapshot.hasTrustworthyBootstrapAnchors,
              snapshot.visibilityPhase != .transitioning,
              snapshot.geometryConfidence == .live || snapshot.geometryConfidence == .cached
        else {
            logger.warning(
                "Visibility intent enforcement skipped until status-item anchors are healthy (\(reason, privacy: .public), structure=\(snapshot.structuralState.rawValue, privacy: .public), geometry=\(snapshot.geometryConfidence.rawValue, privacy: .public), main=\(snapshot.mainAnchorSource.rawValue, privacy: .public), separator=\(snapshot.separatorAnchorSource.rawValue, privacy: .public))"
            )
            return false
        }

        return true
    }

    func applyAutoRehideSettingsChange(from oldSettings: SaneBarSettings, to newSettings: SaneBarSettings) {
        if oldSettings.autoRehide, !newSettings.autoRehide {
            hidingService.cancelRehide()
            return
        }

        let rehideContext = AutoRehideSettingsChangeContext(
            wasAutoRehideEnabled: oldSettings.autoRehide,
            isAutoRehideEnabled: newSettings.autoRehide,
            hidingState: hidingState,
            isRevealPinned: isRevealPinned,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor,
            isStatusMenuOpen: isMenuOpen
        )
        guard MenuBarVisibilityPolicy.shouldArmAutoRehideAfterSettingsChange(rehideContext) else {
            return
        }

        logger.info("Auto-rehide enabled from settings while icons are visible — starting the hide timer")
        hidingService.scheduleRehide(after: newSettings.rehideDelay)
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        settingsController.resetToDefaults()
        settings = settingsController.settings
        try? MenuBarSpacingService.shared.resetToDefaults()
        MenuBarSpacingService.shared.attemptGracefulRefresh()
        clearCachedSeparatorGeometry()
        recreateStatusItemsFromPersistedLayout(reason: "reset-to-defaults") {
            StatusBarController.resetPersistentStatusItemState(
                alwaysHiddenEnabled: self.currentEffectiveAlwaysHiddenSectionEnabled(),
                referenceScreen: self.statusItemScreen,
                freshAutosaveNamespace: true
            )
        }
        schedulePositionValidation(context: .manualLayoutRestore, recoveryCount: 0)
        updateSpacers()
        updateAppearance()
        iconHotkeysService.registerHotkeys(from: settings)
        logger.info("All settings reset to defaults")
    }

    // MARK: - Appearance

    func updateStatusItemAppearance() {
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

    func recreateStatusItemsFromPersistedLayout(
        reason: String,
        afterRemovingExistingItems: (() -> Void)? = nil
    ) {
        geometryCache.clearSeparatorGeometry()
        let (newMain, newSeparator) = statusBarController.recreateItemsFromPersistedPositions(
            afterRemovingExistingItems: afterRemovingExistingItems
        )
        statusBarController.onItemsRecreated?(newMain, newSeparator)
        logger.info("Recreated status items from persisted layout (\(reason, privacy: .public))")
    }
}
