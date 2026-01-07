import AppKit
import Combine
import os.log
import SwiftUI

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

    @Published private(set) var hidingState: HidingState = .hidden
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
    let hoverService: HoverService
    let appearanceService: MenuBarAppearanceService
    let networkTriggerService: NetworkTriggerService

    // MARK: - Status Items

    /// Main SaneBar icon you click (always visible)
    private var mainStatusItem: NSStatusItem?
    /// Separator that expands to hide items (the actual delimiter)
    private var separatorItem: NSStatusItem?
    /// Always-hidden delimiter - items to LEFT of this are only shown with Option+click
    private var alwaysHiddenDelimiter: NSStatusItem?
    private var statusMenu: NSMenu?
    private var onboardingPopover: NSPopover?

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
        hoverService: HoverService? = nil,
        appearanceService: MenuBarAppearanceService? = nil,
        networkTriggerService: NetworkTriggerService? = nil
    ) {
        self.hidingService = hidingService ?? HidingService()
        self.persistenceService = persistenceService
        self.settingsController = settingsController ?? SettingsController(persistence: persistenceService)
        self.statusBarController = statusBarController ?? StatusBarController()
        self.triggerService = triggerService ?? TriggerService()
        self.iconHotkeysService = iconHotkeysService ?? IconHotkeysService.shared
        self.hoverService = hoverService ?? HoverService()
        self.appearanceService = appearanceService ?? MenuBarAppearanceService()
        self.networkTriggerService = networkTriggerService ?? NetworkTriggerService()

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
        setupHoverService()
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

        // Show onboarding on first launch
        showOnboardingIfNeeded()
    }
    
    /// Detects if running in a headless environment (CI, tests without window server)
    private func isRunningInHeadlessEnvironment() -> Bool {
        // Check for common CI environment variables
        if ProcessInfo.processInfo.environment["CI"] != nil ||
           ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil {
            return true
        }
        
        // Check if we're running in XCTest context
        // In test bundles, NSApp.windows is empty but that's not reliable
        // Better to check for XCTest framework
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

        // Copy references for local use (backward compatibility)
        mainStatusItem = statusBarController.mainItem
        separatorItem = statusBarController.separatorItem
        alwaysHiddenDelimiter = statusBarController.alwaysHiddenDelimiter

        // Setup menu using controller, attach to separator
        statusMenu = statusBarController.createMenu(
            toggleAction: #selector(menuToggleHiddenItems),
            settingsAction: #selector(openSettings),
            quitAction: #selector(quitApp),
            target: self
        )
        separatorItem?.menu = statusMenu
        statusMenu?.delegate = self

        // Debug: Verify menu items have targets
        if let items = statusMenu?.items {
            for item in items where !item.isSeparatorItem {
                logger.debug("Menu item '\(item.title)': target=\(item.target == nil ? "nil" : "set"), action=\(item.action?.description ?? "nil")")
            }
        }

        // Configure hiding service with BOTH delimiters
        if let separator = separatorItem {
            hidingService.configure(
                delimiterItem: separator,
                alwaysHiddenDelimiter: alwaysHiddenDelimiter
            )
        }

        // Validate positions on startup (with delay for UI to settle)
        validatePositionsOnStartup()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .leftMouseUp {
            // Option+click reveals always-hidden section
            let optionPressed = event.modifierFlags.contains(.option)
            toggleHiddenItems(withModifier: optionPressed)
        } else if event.type == .rightMouseUp {
            showStatusMenu()
        }
    }

    private func showStatusMenu() {
        guard let statusMenu = statusMenu,
              let item = mainStatusItem else { return }
        logger.info("Right-click: showing menu via popUpMenu API")
        item.popUpMenu(statusMenu)
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

        // Observe settings changes to update spacers, hover, appearance, and network trigger
        $settings
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.updateSpacers()
                self?.updateHoverSettings()
                self?.updateAppearance()
                self?.updateNetworkTrigger(enabled: newSettings.showOnNetworkChange)
            }
            .store(in: &cancellables)
    }

    private func updateAppearance() {
        appearanceService.updateAppearance(settings.menuBarAppearance)
    }

    private func updateNetworkTrigger(enabled: Bool) {
        if enabled {
            networkTriggerService.startMonitoring()
        } else {
            networkTriggerService.stopMonitoring()
        }
    }

    private func setupHoverService() {
        guard let mainItem = mainStatusItem, let separator = separatorItem else {
            logger.warning("Cannot setup hover service - status items not ready")
            return
        }

        hoverService.configure(
            mainItem: mainItem,
            separatorItem: separator,
            onHoverStart: { [weak self] in
                self?.handleHoverStart()
            },
            onHoverEnd: { [weak self] in
                self?.handleHoverEnd()
            }
        )

        updateHoverSettings()
    }

    private func updateHoverSettings() {
        hoverService.setEnabled(settings.showOnHover)
        hoverService.setDelay(settings.hoverDelay)
    }

    private func handleHoverStart() {
        // Only show if currently hidden
        guard hidingState == .hidden else { return }
        logger.info("Hover triggered - showing hidden items")
        showHiddenItems()
    }

    private func handleHoverEnd() {
        // Auto-rehide if setting enabled
        if settings.autoRehide {
            hidingService.scheduleRehide(after: settings.rehideDelay)
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

    func toggleHiddenItems(withModifier: Bool = false) {
        Task {
            logger.info("toggleHiddenItems(withModifier: \(withModifier)) called, current state: \(self.hidingState.rawValue)")

            // If about to hide, validate position first
            if hidingState == .expanded && !withModifier {
                logger.info("State is expanded, validating position before hiding...")
                guard validateSeparatorPosition() else {
                    logger.warning("⚠️ Separator is RIGHT of main icon - refusing to hide")
                    showPositionWarning()
                    return
                }
                logger.info("Position valid, proceeding to hide")
            }

            await hidingService.toggle(withModifier: withModifier)

            // Schedule auto-rehide if enabled and we just showed (not always-hidden)
            if hidingState == .expanded && settings.autoRehide {
                hidingService.scheduleRehide(after: settings.rehideDelay)
            }
        }
    }

    func showHiddenItems() {
        Task {
            await hidingService.show()
            if settings.autoRehide {
                hidingService.scheduleRehide(after: settings.rehideDelay)
            }
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

    /// Enum describing position validation errors
    enum PositionError {
        case separatorRightOfMain      // Main separator is right of main icon
        case alwaysHiddenRightOfSeparator  // Always-hidden delimiter is right of main separator
        case separatorsOverlapping     // Both separators are at same position
    }

    /// Published property to track position errors for UI
    @Published private(set) var positionError: PositionError?

    /// Returns true if all status items are correctly positioned
    /// Correct order (left to right): [alwaysHiddenDelimiter] [separatorItem] [mainStatusItem]
    /// Uses Ice's pattern: check window.frame intersects screen to detect off-screen items
    private func validateSeparatorPosition() -> Bool {
        positionError = nil

        guard let mainButton = mainStatusItem?.button,
              let separatorButton = separatorItem?.button else {
            logger.error("validateSeparatorPosition: buttons are nil - blocking hide for safety")
            return false
        }

        guard let mainWindow = mainButton.window,
              let separatorWindow = separatorButton.window else {
            logger.error("validateSeparatorPosition: windows are nil - blocking hide for safety")
            return false
        }

        // Get screen for intersection check (Ice pattern)
        guard let screen = mainWindow.screen ?? NSScreen.main else {
            logger.error("validateSeparatorPosition: no screen available")
            return false
        }

        let mainFrame = mainWindow.frame
        let separatorFrame = separatorWindow.frame

        // Check 0: Verify separators are visible on screen (Ice pattern)
        // If they don't intersect screen, they may have been pushed off
        if !screen.frame.intersects(separatorFrame) {
            logger.warning("Position error: separator is off-screen!")
            positionError = .separatorsOverlapping  // Reuse for "not visible" case
            return false
        }

        // Check 1: Main separator must be LEFT of main icon
        let separatorRightEdge = separatorFrame.origin.x + separatorFrame.width
        let mainLeftEdge = mainFrame.origin.x
        let separatorIsLeftOfMain = separatorRightEdge <= mainLeftEdge

        if !separatorIsLeftOfMain {
            logger.warning("Position error: separator is RIGHT of main icon!")
            positionError = .separatorRightOfMain
            return false
        }

        // Check 2: If alwaysHiddenDelimiter exists, validate its position too
        if let alwaysHiddenButton = alwaysHiddenDelimiter?.button,
           let alwaysHiddenWindow = alwaysHiddenButton.window {
            let alwaysHiddenFrame = alwaysHiddenWindow.frame

            // Check if alwaysHidden is visible on screen
            if !screen.frame.intersects(alwaysHiddenFrame) {
                logger.warning("Position error: always-hidden delimiter is off-screen!")
                positionError = .separatorsOverlapping
                return false
            }

            let alwaysHiddenRightEdge = alwaysHiddenFrame.origin.x + alwaysHiddenFrame.width
            let separatorLeftEdge = separatorFrame.origin.x

            // Check for overlapping (within 5px tolerance)
            let areOverlapping = abs(alwaysHiddenRightEdge - separatorLeftEdge) < 5 &&
                                 abs(alwaysHiddenFrame.origin.x - separatorFrame.origin.x) < 5

            if areOverlapping {
                logger.warning("Position error: separators are overlapping!")
                positionError = .separatorsOverlapping
                return false
            }

            let alwaysHiddenIsLeftOfSeparator = alwaysHiddenRightEdge <= separatorLeftEdge + 5

            if !alwaysHiddenIsLeftOfSeparator {
                logger.warning("Position error: always-hidden delimiter is RIGHT of separator!")
                positionError = .alwaysHiddenRightOfSeparator
                return false
            }

            logger.debug("""
                Position check: alwaysHidden frame=\(NSStringFromRect(alwaysHiddenFrame)), \
                separator frame=\(NSStringFromRect(separatorFrame)), \
                main frame=\(NSStringFromRect(mainFrame)) - ALL VALID
                """)
        }

        return true
    }

    /// Validates positions on startup with a delay to let UI settle
    func validatePositionsOnStartup() {
        // Delay to let status items get their final positions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if !self.validateSeparatorPosition() {
                logger.warning("Startup position validation failed!")
                self.showPositionWarning()
            }
        }
    }

    private func showPositionWarning() {
        // Show a brief notification or popover explaining the issue
        guard let button = mainStatusItem?.button else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 120)
        popover.behavior = .transient

        let warningView = PositionWarningView(errorType: positionError)
        popover.contentViewController = NSHostingController(rootView: warningView)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Auto-close after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            popover.close()
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
        let optionPressed = NSEvent.modifierFlags.contains(.option)
        logger.info("Menu: Toggle Hidden Items (Option: \(optionPressed))")
        toggleHiddenItems(withModifier: optionPressed)
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
