import AppKit
import Combine
import SwiftUI

// MARK: - MenuBarManager

/// Central manager for menu bar hiding using the length toggle technique.
///
/// HOW IT WORKS (same as Bartender, Dozer, Hidden Bar):
/// 1. User Cmd+drags menu bar icons to position them left or right of our delimiter
/// 2. Icons to the LEFT of delimiter = always visible
/// 3. Icons to the RIGHT of delimiter = can be hidden
/// 4. To HIDE: Set delimiter's length to 10,000 → pushes everything to its right off screen
/// 5. To SHOW: Set delimiter's length back to 22 → reveals the hidden icons
///
/// NO accessibility API needed. NO CGEvent simulation. Just simple NSStatusItem.length toggle.
@MainActor
final class MenuBarManager: ObservableObject {

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
    let triggerService: TriggerService
    let iconHotkeysService: IconHotkeysService

    // MARK: - Status Items

    /// Main SaneBar icon you click (always visible)
    private var mainStatusItem: NSStatusItem?
    /// Separator that expands to hide items (the actual delimiter)
    private var separatorItem: NSStatusItem?
    /// Additional spacers for organizing hidden items
    private var spacerItems: [NSStatusItem] = []
    private var statusMenu: NSMenu?
    private var onboardingPopover: NSPopover?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        hidingService: HidingService? = nil,
        persistenceService: PersistenceServiceProtocol = PersistenceService.shared,
        triggerService: TriggerService? = nil,
        iconHotkeysService: IconHotkeysService? = nil
    ) {
        self.hidingService = hidingService ?? HidingService()
        self.persistenceService = persistenceService
        self.triggerService = triggerService ?? TriggerService()
        self.iconHotkeysService = iconHotkeysService ?? IconHotkeysService.shared

        setupStatusItem()
        loadSettings()
        updateSpacers()
        setupObservers()

        // Configure trigger service with self
        self.triggerService.configure(menuBarManager: self)

        // Configure icon hotkeys service with self
        self.iconHotkeysService.configure(with: self)

        // Show onboarding on first launch
        showOnboardingIfNeeded()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        // Based on Hidden Bar's proven implementation:
        // - Items created FIRST appear to the RIGHT (higher X coordinate)
        // - Items created SECOND appear to the LEFT
        // - When separator expands to 10000, items to its LEFT get pushed off screen
        // - Main icon (to separator's RIGHT) stays visible
        //
        // Order on screen: [items to hide] [separator] [main icon] [system icons]

        // 1. Create MAIN ICON first - appears to the RIGHT (stays visible when collapsed)
        mainStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mainStatusItem?.autosaveName = "SaneBar_main"

        if let button = mainStatusItem?.button {
            configureButton(button)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 2. Create SEPARATOR second - appears to the LEFT of main icon
        // Start at 20 (expanded state - hidden items visible)
        // When user clicks to hide, this expands to 10000
        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        separatorItem?.autosaveName = "SaneBar_separator"
        if let button = separatorItem?.button {
            button.image = NSImage(
                systemSymbolName: "line.diagonal",
                accessibilityDescription: "Separator"
            )
            button.image?.isTemplate = true
        }

        // Setup menu (attached to separator for right-click, like Hidden Bar)
        setupMenu()
        separatorItem?.menu = statusMenu

        // Configure hiding service with the SEPARATOR (not the icon)
        if let separator = separatorItem {
            hidingService.configure(delimiterItem: separator)
        }
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
        guard let statusMenu = statusMenu else { return }
        print("[SaneBar] Right-click: showing menu")
        mainStatusItem?.menu = statusMenu
        mainStatusItem?.button?.performClick(nil)
        // Clear menu so left-click works again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.mainStatusItem?.menu = nil
        }
    }

    private func configureButton(_ button: NSStatusBarButton) {
        // Use SF Symbol circle icon
        button.image = NSImage(
            systemSymbolName: "line.3.horizontal.decrease.circle",
            accessibilityDescription: "SaneBar"
        )
    }

    private func setupMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle Hidden Items",
            action: #selector(menuToggleHiddenItems),
            keyEquivalent: "\\"
        )
        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = [.command]
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit SaneBar",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
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

        // Observe settings changes to update spacers
        $settings
            .dropFirst() // Skip initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSpacers()
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings

    private func loadSettings() {
        do {
            settings = try persistenceService.loadSettings()
        } catch {
            print("[SaneBar] Failed to load settings: \(error)")
        }
    }

    func saveSettings() {
        do {
            try persistenceService.saveSettings(settings)
            // Re-register hotkeys when settings change
            iconHotkeysService.registerHotkeys(from: settings)
        } catch {
            print("[SaneBar] Failed to save settings: \(error)")
        }
    }

    // MARK: - Visibility Control

    func toggleHiddenItems() {
        Task {
            await hidingService.toggle()

            // Schedule auto-rehide if enabled and we just showed
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
            await hidingService.hide()
        }
    }

    // MARK: - Appearance

    private func updateStatusItemAppearance() {
        guard let button = mainStatusItem?.button else { return }

        // Change icon based on state (filled when expanded, outline when hidden)
        let iconName = hidingState == .expanded
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"

        button.image = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: "SaneBar"
        )
    }

    // MARK: - Menu Actions

    @objc private func menuToggleHiddenItems(_ sender: Any?) {
        print("[SaneBar] Menu: Toggle Hidden Items")
        toggleHiddenItems()
    }

    @objc private func openSettings(_ sender: Any?) {
        // Post notification - handled by SettingsOpenerView (macOS Tahoe workaround)
        NotificationCenter.default.post(name: .openSaneBarSettings, object: nil)
    }

    @objc private func quitApp(_ sender: Any?) {
        print("[SaneBar] Menu: Quit")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Spacers

    /// Update spacer items based on settings
    func updateSpacers() {
        let desiredCount = min(max(settings.spacerCount, 0), 3) // Clamp to 0-3

        // Remove excess spacers
        while spacerItems.count > desiredCount {
            if let item = spacerItems.popLast() {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        // Add missing spacers
        while spacerItems.count < desiredCount {
            let spacer = NSStatusBar.system.statusItem(withLength: 12)
            spacer.autosaveName = "SaneBar_spacer_\(spacerItems.count)"
            if let button = spacer.button {
                button.image = NSImage(
                    systemSymbolName: "minus",
                    accessibilityDescription: "Spacer"
                )
                button.image?.isTemplate = true
            }
            spacerItems.append(spacer)
        }
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
