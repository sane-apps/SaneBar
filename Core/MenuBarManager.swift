import AppKit
import Combine
import os.log
import SwiftUI
import LocalAuthentication

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager")

// MARK: - MenuBarManager

/// Central manager for menu bar hiding using the length toggle technique.
///
/// HOW IT WORKS (same technique as Dozer, Hidden Bar, and similar tools):
/// 1. User Cmd+drags menu bar icons to position them left or right of our delimiter
/// 2. Icons to the LEFT of delimiter = always visible
/// 3. Icons to the RIGHT of delimiter = can be hidden
/// 4. To HIDE: Set delimiter's length to 10,000 → pushes everything to its right off screen
/// 5. To SHOW: Set delimiter's length back to 22 → reveals the hidden icons
///
/// NO accessibility API needed. NO CGEvent simulation. Just simple NSStatusItem.length toggle.
@MainActor
final class MenuBarManager: NSObject, ObservableObject, NSMenuDelegate {

    // MARK: - Singleton

    static let shared = MenuBarManager()

    // MARK: - Published State

    /// Starts expanded - we validate positions first, then hide if safe
    @Published private(set) var hidingState: HidingState = .expanded
    @Published var settings: SaneBarSettings = SaneBarSettings()

    /// When true, the user explicitly chose to keep icons revealed ("Reveal All")
    /// and we should not auto-hide until they explicitly hide again.
    @Published private(set) var isRevealPinned: Bool = false
    
    /// Tracks whether the status menu is currently open
    @Published var isMenuOpen: Bool = false

    // MARK: - Screen Detection

    /// Returns true if the main screen has a notch (MacBook Pro 14/16 inch models)
    var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        // auxiliaryTopLeftArea is non-nil on notched Macs (macOS 12+)
        return screen.auxiliaryTopLeftArea != nil
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
    let hoverService: HoverService
    let updateService: UpdateService

    // MARK: - Status Items

    /// Main SaneBar icon you click (always visible)
    internal var mainStatusItem: NSStatusItem?
    /// Separator that expands to hide items (the actual delimiter)
    internal var separatorItem: NSStatusItem?
    internal var statusMenu: NSMenu?
    private var onboardingPopover: NSPopover?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()
    internal var positionMonitorTask: Task<Void, Never>?
    /// Counter for consecutive invalid position checks (debounce for drag operations)
    internal var invalidPositionCount = 0
    /// Threshold before triggering warning (3 checks × 500ms = 1.5 seconds)
    internal let invalidPositionThreshold = 3

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
            guard let self = self else { return }
            Task { @MainActor in
                logger.debug("Hover trigger received: \(String(describing: reason))")
                _ = await self.showHiddenItemsNow(trigger: .automation)
            }
        }

        hoverService.onLeaveMenuBar = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                // Only auto-hide if autoRehide is enabled
                if self.settings.autoRehide && !self.isRevealPinned {
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

    // MARK: - Setup

    /// Deferred UI setup with initial delay to ensure WindowServer is ready
    /// Fixes crash on Mac Mini M4 / macOS 15.7.3 where GUI isn't immediately available
    private func deferredUISetup() {
        // Initial delay of 100ms gives the system time to fully establish
        // the WindowServer connection, especially important for:
        // - Login Items that launch before GUI is ready
        // - Fast boot systems (M4 Macs)
        // - Remote desktop sessions
        let initialDelay: TimeInterval = 0.1

        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            guard let self = self else { return }
            logger.info("Starting deferred UI setup")

            // Create status items (with additional retry logic inside)
            self.setupStatusItem()

            // These all depend on status items being ready
            self.updateSpacers()
            self.setupObservers()
            self.updateAppearance()

            // Configure services
            self.triggerService.configure(menuBarManager: self)
            self.iconHotkeysService.configure(with: self)
            self.networkTriggerService.configure(menuBarManager: self)
            if self.settings.showOnNetworkChange {
                self.networkTriggerService.startMonitoring()
            }

            // Configure hover service
            self.configureHoverService()

            // Show onboarding on first launch
            self.showOnboardingIfNeeded()

            // Sync update settings to Sparkle
            self.syncUpdateConfiguration()

            logger.info("Deferred UI setup complete")
        }
    }

    private func setupStatusItem() {
        // Delegate status item creation to controller
        statusBarController.createStatusItems(
            clickAction: #selector(statusItemClicked),
            target: self
        )

        // Copy references for local use
        mainStatusItem = statusBarController.mainItem
        separatorItem = statusBarController.separatorItem

        // Setup menu using controller, attach to separator
        statusMenu = statusBarController.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(menuToggleHiddenItems),
            findIconAction: #selector(openFindIcon),
            settingsAction: #selector(openSettings),
            checkForUpdatesAction: #selector(userDidClickCheckForUpdates),
            quitAction: #selector(quitApp),
            target: self
        ))
        separatorItem?.menu = statusMenu
        statusMenu?.delegate = self

        // Configure hiding service with delimiter
        if let separator = separatorItem {
            hidingService.configure(delimiterItem: separator)
        }

        // Validate positions on startup (with delay for UI to settle)
        validatePositionsOnStartup()

        // Apply main icon visibility based on settings
        updateMainIconVisibility()
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

        // Observe settings changes to update all dependent services
        $settings
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.updateSpacers()
                self?.updateAppearance()
                self?.updateNetworkTrigger(enabled: newSettings.showOnNetworkChange)
                self?.triggerService.updateBatteryMonitoring(enabled: newSettings.showOnLowBattery)
                self?.updateHoverService()
                self?.syncUpdateConfiguration()
                self?.updateMainIconVisibility()
            }
            .store(in: &cancellables)
    }

    // MARK: - Main Icon Visibility

    /// Show or hide the main SaneBar icon based on settings
    func updateMainIconVisibility() {
        guard let mainItem = mainStatusItem else { return }
        mainItem.isVisible = !settings.hideMainIcon
        logger.info("Main icon visibility: \(mainItem.isVisible ? "visible" : "hidden")")
    }

    private func updateAppearance() {
        appearanceService.updateAppearance(settings.menuBarAppearance)
    }

    private func updateHoverService() {
        hoverService.isEnabled = settings.showOnHover
        hoverService.scrollEnabled = settings.showOnScroll
        hoverService.hoverDelay = settings.hoverDelay

        if settings.showOnHover || settings.showOnScroll {
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

    // MARK: - Settings

    private func loadSettings() {
        settingsController.loadOrDefault()
        settings = settingsController.settings
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

    // MARK: - Visibility Control

    enum RevealTrigger: String, Sendable {
        case hotkey
        case search
        case automation
        case settingsButton
    }

    func toggleHiddenItems() {
        Task {
            logger.info("toggleHiddenItems() called, current state: \(self.hidingState.rawValue)")

            // If we're about to SHOW (hidden -> expanded), optionally gate with auth.
            if hidingState == .hidden, settings.requireAuthToShowHiddenIcons {
                logger.info("Auth required to show hidden icons, prompting...")
                let ok = await authenticate(reason: "Show hidden menu bar icons")
                guard ok else {
                    logger.info("Auth failed or cancelled, aborting toggle")
                    return
                }
            }

            // If about to hide, validate position first
            if hidingState == .expanded {
                logger.info("State is expanded, validating position before hiding...")
                guard validateSeparatorPosition() else {
                    logger.warning("⚠️ Separator is RIGHT of main icon - refusing to hide")
                    showPositionWarning()
                    return
                }
                logger.info("Position valid, proceeding to hide")
            }

            logger.info("Calling hidingService.toggle()...")
            await hidingService.toggle()
            logger.info("hidingService.toggle() completed, new state: \(self.hidingService.state.rawValue)")

            // If user explicitly hid everything, unpin.
            if hidingService.state == .hidden {
                isRevealPinned = false
                hidingService.cancelRehide()
            }

            // Schedule auto-rehide if enabled and we just showed
            if hidingService.state == .expanded && settings.autoRehide && !isRevealPinned {
                hidingService.scheduleRehide(after: settings.rehideDelay)
            }
        }
    }

    /// Reveal hidden icons immediately, returning whether the reveal occurred.
    /// Search and hotkeys should await this before attempting virtual clicks.
    @MainActor
    func showHiddenItemsNow(trigger: RevealTrigger) async -> Bool {
        if settings.requireAuthToShowHiddenIcons {
            let ok = await authenticate(reason: "Show hidden menu bar icons")
            guard ok else { return false }
        }

        // Manual reveal should pin and cancel any pending auto-rehide.
        if trigger == .settingsButton {
            isRevealPinned = true
            hidingService.cancelRehide()
        }

        let didReveal = hidingService.state == .hidden
        await hidingService.show()
        if didReveal, settings.autoRehide, !isRevealPinned {
            hidingService.scheduleRehide(after: settings.rehideDelay)
        }
        return didReveal
    }

    /// Schedule a rehide specifically from Find Icon search (always hides, ignores autoRehide setting)
    func scheduleRehideFromSearch(after delay: TimeInterval) {
        guard !isRevealPinned else { return }
        hidingService.scheduleRehide(after: delay)
    }

    func showHiddenItems() {
        Task {
            _ = await showHiddenItemsNow(trigger: .settingsButton)
        }
    }

    func hideHiddenItems() {
        Task {
            isRevealPinned = false
            hidingService.cancelRehide()

            // Safety check: verify separator is LEFT of main icon before hiding
            guard validateSeparatorPosition() else {
                logger.warning("⚠️ Separator is RIGHT of main icon - refusing to hide to prevent eating the main icon")
                showPositionWarning()
                return
            }
            await hidingService.hide()
        }
    }

    // MARK: - Privacy Auth

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
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
        guard !settings.hasCompletedOnboarding else { return }

        // Delay slightly to ensure menu bar is fully set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.showOnboardingPopover()
        }
    }

    private func showOnboardingPopover() {
        guard let button = mainStatusItem?.button else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 240)
        popover.behavior = .transient

        let hostingController = NSHostingController(rootView: OnboardingTipView(onDismiss: { [weak self] in
            self?.completeOnboarding()
        }))
        popover.contentViewController = hostingController

        onboardingPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func completeOnboarding() {
        onboardingPopover?.close()
        onboardingPopover = nil
        settings.hasCompletedOnboarding = true
        saveSettings()
    }
}
