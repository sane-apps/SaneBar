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

    // MARK: - Status Items

    /// Main SaneBar icon you click (always visible)
    private var mainStatusItem: NSStatusItem?
    /// Separator that expands to hide items (the actual delimiter)
    private var separatorItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var onboardingPopover: NSPopover?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()
    private var positionMonitorTask: Task<Void, Never>?

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
        hoverService: HoverService? = nil
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

        super.init()

        logger.info("MenuBarManager init starting...")
        
        // Skip UI initialization in headless/test environments
        // CI environments don't have a window server, so NSStatusItem creation will crash
        guard !isRunningInHeadlessEnvironment() else {
            logger.info("Headless environment detected - skipping UI initialization")
            return
        }
        
        setupStatusItem()
        loadSettings()
        updateSpacers()
        setupObservers()
        updateAppearance()

        // Configure trigger service with self
        self.triggerService.configure(menuBarManager: self)

        // Configure icon hotkeys service with self
        self.iconHotkeysService.configure(with: self)

        // Configure network trigger service
        self.networkTriggerService.configure(menuBarManager: self)
        if settings.showOnNetworkChange {
            self.networkTriggerService.startMonitoring()
        }

        // Configure hover service
        configureHoverService()

        // Show onboarding on first launch
        showOnboardingIfNeeded()
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
                if self.settings.autoRehide {
                    self.hidingService.scheduleRehide(after: self.settings.rehideDelay)
                }
            }
        }

        // Apply initial settings
        updateHoverService()
    }
    
    /// Detects if running in a headless environment (CI, tests without window server)
    private func isRunningInHeadlessEnvironment() -> Bool {
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
        statusMenu = statusBarController.createMenu(
            toggleAction: #selector(menuToggleHiddenItems),
            settingsAction: #selector(openSettings),
            quitAction: #selector(quitApp),
            target: self
        )
        separatorItem?.menu = statusMenu
        statusMenu?.delegate = self

        // Configure hiding service with delimiter
        if let separator = separatorItem {
            hidingService.configure(delimiterItem: separator)
        }

        // Validate positions on startup (with delay for UI to settle)
        validatePositionsOnStartup()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .leftMouseUp {
            toggleHiddenItems()
        } else if event.type == .rightMouseUp {
            showStatusMenu()
        }
    }

    private func showStatusMenu() {
        guard let statusMenu = statusMenu,
              let item = mainStatusItem,
              let button = item.button else { return }
        logger.info("Right-click: showing menu")
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height), in: button)
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
            }
            .store(in: &cancellables)
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
        case click
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
                let ok = await authenticate(reason: "Show hidden menu bar icons")
                guard ok else { return }
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

            await hidingService.toggle()

            // Schedule auto-rehide if enabled and we just showed
            if hidingService.state == .expanded && settings.autoRehide {
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

        await hidingService.show()
        if settings.autoRehide {
            hidingService.scheduleRehide(after: settings.rehideDelay)
        }
        return true
    }

    /// Schedule a rehide specifically from Find Icon search (always hides, ignores autoRehide setting)
    func scheduleRehideFromSearch(after delay: TimeInterval) {
        hidingService.scheduleRehide(after: delay)
    }

    func showHiddenItems() {
        Task {
            _ = await showHiddenItemsNow(trigger: .settingsButton)
        }
    }

    func hideHiddenItems() {
        Task {
            // Safety check: verify separator is LEFT of main icon before hiding
            guard validateSeparatorPosition() else {
                logger.warning("⚠️ Separator is RIGHT of main icon - refusing to hide to prevent eating the main icon")
                showPositionWarning()
                return
            }
            await hidingService.hide()
        }
    }

    // MARK: - Position Validation

    /// Returns true if separator is correctly positioned (LEFT of main icon)
    /// Returns true if we can't determine position (assume valid on startup)
    private func validateSeparatorPosition() -> Bool {
        // If buttons aren't ready, assume valid (don't block on startup)
        guard let mainButton = mainStatusItem?.button,
              let separatorButton = separatorItem?.button else {
            logger.debug("validateSeparatorPosition: buttons not ready - assuming valid")
            return true
        }

        // If windows aren't ready, assume valid (don't block on startup)
        guard let mainWindow = mainButton.window,
              let separatorWindow = separatorButton.window else {
            logger.debug("validateSeparatorPosition: windows not ready - assuming valid")
            return true
        }

        let mainFrame = mainWindow.frame
        let separatorFrame = separatorWindow.frame

        // If frames are zero/invalid, assume valid (UI not ready)
        if mainFrame.width == 0 || separatorFrame.width == 0 {
            logger.debug("validateSeparatorPosition: frames not ready - assuming valid")
            return true
        }

        // Check: separator must be LEFT of main icon (lower X in screen coordinates)
        // Menu bar: LEFT = lower X, RIGHT = higher X
        let separatorRightEdge = separatorFrame.origin.x + separatorFrame.width
        let mainLeftEdge = mainFrame.origin.x

        if separatorRightEdge > mainLeftEdge {
            logger.warning("Position error: separator (right edge \(separatorRightEdge)) is RIGHT of main (left edge \(mainLeftEdge))")
            return false
        }

        logger.debug("Position valid: separator right=\(separatorRightEdge), main left=\(mainLeftEdge)")
        return true
    }

    /// Validates positions on startup with a delay to let UI settle
    /// If validation passes, hides the items. If it fails, shows a warning and stays expanded.
    func validatePositionsOnStartup() {
        // Delay to let status items get their final positions (2s for safety)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.validateSeparatorPosition() {
                // Position is valid - safe to hide
                logger.info("Startup position validation passed - hiding items")
                Task {
                    await self.hidingService.hide()
                }
            } else {
                // Position is wrong - stay expanded and warn user
                logger.warning("Startup position validation failed! Staying expanded.")
                self.showPositionWarning()
            }

            // Start continuous position monitoring to prevent separator from eating main icon
            self.startPositionMonitoring()
        }
    }

    // MARK: - Continuous Position Monitoring

    /// Monitor separator position continuously to prevent it from "eating" the main icon
    /// If user drags separator to an invalid position while items are hidden, auto-expand
    private func startPositionMonitoring() {
        positionMonitorTask?.cancel()

        positionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                // Check every 500ms - balance between responsiveness and CPU usage
                try? await Task.sleep(nanoseconds: 500_000_000)

                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self?.checkPositionAndAutoExpand()
                }
            }
        }
    }

    /// Check position and auto-expand if separator is eating the main icon
    private func checkPositionAndAutoExpand() {
        // Only check when hidden - that's when the 10,000px spacer can push the main icon off
        guard hidingState == .hidden else { return }

        // If position is invalid, auto-expand immediately to rescue the main icon
        if !validateSeparatorPosition() {
            logger.warning("⚠️ POSITION EMERGENCY: Separator is eating main icon! Auto-expanding...")
            Task {
                await hidingService.show()
            }
            showPositionWarning()
        }
    }

    /// Stop position monitoring (called on deinit or when appropriate)
    private func stopPositionMonitoring() {
        positionMonitorTask?.cancel()
        positionMonitorTask = nil
    }

    private func showPositionWarning() {
        guard let button = mainStatusItem?.button else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 120)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PositionWarningView())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Auto-close after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            popover.close()
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

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        logger.debug("Menu will open - checking targets...")
        for item in menu.items where !item.isSeparatorItem {
            let targetStatus = item.target == nil ? "nil" : "set"
            logger.debug("  '\(item.title)': target=\(targetStatus)")
        }
    }

    // MARK: - Menu Actions

    @objc private func menuToggleHiddenItems(_ sender: Any?) {
        logger.info("Menu: Toggle Hidden Items")
        toggleHiddenItems()
    }

    @objc private func openSettings(_ sender: Any?) {
        logger.info("Menu: Opening Settings")
        SettingsOpener.open()
    }

    @objc private func quitApp(_ sender: Any?) {
        logger.info("Menu: Quit")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Spacers

    /// Update spacer items based on settings
    func updateSpacers() {
        statusBarController.updateSpacers(count: settings.spacerCount)
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
