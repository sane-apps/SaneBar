import AppKit
import ApplicationServices
import Combine

// MARK: - MenuBarManager

/// Central manager for menu bar item discovery and visibility control
@MainActor
final class MenuBarManager: ObservableObject {

    // MARK: - Singleton

    static let shared = MenuBarManager()

    // MARK: - Published State

    @Published private(set) var statusItems: [StatusItemModel] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastScanMessage: String?
    @Published private(set) var hidingState: HidingState = .hidden
    @Published var settings: SaneBarSettings = SaneBarSettings()

    // MARK: - Computed Properties

    /// Items in the always-visible section
    var visibleItems: [StatusItemModel] {
        statusItems.filter { $0.section == .alwaysVisible }
    }

    /// Items in the hidden section
    var hiddenItems: [StatusItemModel] {
        statusItems.filter { $0.section == .hidden }
    }

    /// Items in the always-hidden section
    var collapsedItems: [StatusItemModel] {
        statusItems.filter { $0.section == .collapsed }
    }

    // MARK: - Services

    let accessibilityService: AccessibilityServiceProtocol
    let permissionService: PermissionServiceProtocol
    let hidingService: HidingService
    let hoverService: HoverService
    let persistenceService: PersistenceServiceProtocol

    // MARK: - Status Items (Section Delimiters)

    /// Main SaneBar icon - acts as delimiter between visible and hidden
    private var mainStatusItem: NSStatusItem?

    /// Secondary delimiter for always-hidden section (optional)
    private var alwaysHiddenStatusItem: NSStatusItem?

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        accessibilityService: AccessibilityServiceProtocol? = nil,
        permissionService: PermissionServiceProtocol? = nil,
        hidingService: HidingService? = nil,
        hoverService: HoverService? = nil,
        persistenceService: PersistenceServiceProtocol = PersistenceService.shared
    ) {
        self.accessibilityService = accessibilityService ?? AccessibilityService()
        self.permissionService = permissionService ?? PermissionService()
        self.persistenceService = persistenceService
        self.hidingService = hidingService ?? HidingService()
        self.hoverService = hoverService ?? HoverService()

        // Connect hover service to hiding service
        self.hoverService.configure(with: self.hidingService)

        setupStatusItems()
        loadSettings()
        setupObservers()

        // Scan if we have permission
        if self.permissionService.permissionState == .granted {
            Task {
                await scan()
            }
        }
    }

    // MARK: - Setup

    private func setupStatusItems() {
        // Main status item (delimiter between visible and hidden)
        mainStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = mainStatusItem?.button {
            configureMainButton(button)
            button.action = #selector(handleMainClick)
            button.target = self
            // Send action on left click, show menu on right click
            button.sendAction(on: [.leftMouseUp])
        }

        // Setup context menu
        setupMenu()

        // Update delimiter position after a short delay (let menu bar settle)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            updateDelimiterPositions()
        }
    }

    private func configureMainButton(_ button: NSStatusBarButton) {
        // Use custom menu bar icon, fall back to SF Symbol
        let customIcon = NSImage(named: "MenuBarIcon")

        if let icon = customIcon {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
        } else {
            button.image = NSImage(
                systemSymbolName: "line.3.horizontal.decrease.circle",
                accessibilityDescription: "SaneBar"
            )
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle Hidden Items",
            action: #selector(menuToggleHiddenItems),
            keyEquivalent: "b"
        )
        toggleItem.target = self
        toggleItem.keyEquivalentModifierMask = [.command]
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let scanItem = NSMenuItem(
            title: "Scan Menu Bar",
            action: #selector(scanMenuItems),
            keyEquivalent: "r"
        )
        scanItem.target = self
        scanItem.keyEquivalentModifierMask = [.command]
        menu.addItem(scanItem)

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

        mainStatusItem?.menu = menu
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

        // Observe notifications for analytics
        NotificationCenter.default.publisher(for: .hiddenSectionShown)
            .sink { [weak self] _ in
                self?.handleSectionShown()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .hiddenSectionHidden)
            .sink { [weak self] _ in
                self?.handleSectionHidden()
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings

    private func loadSettings() {
        do {
            settings = try persistenceService.loadSettings()
            let savedItems = try persistenceService.loadItemConfigurations()
            if !savedItems.isEmpty {
                statusItems = savedItems
            }
        } catch {
            print("Failed to load settings: \(error)")
        }
    }

    func saveSettings() {
        do {
            try persistenceService.saveSettings(settings)
            try persistenceService.saveItemConfigurations(statusItems)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    // MARK: - Delimiter Position

    private func updateDelimiterPositions() {
        guard let button = mainStatusItem?.button,
              let window = button.window else { return }

        let frame = window.frame
        let delimiterX = frame.midX

        hidingService.setDelimiterPositions(
            hidden: delimiterX,
            alwaysHidden: nil // Could add secondary delimiter
        )

        // Update hover service region
        hoverService.setHoverRegion(around: button, padding: 30)

        // Configure hover behavior from settings
        hoverService.isEnabled = settings.showOnHover
        hoverService.hoverDelay = settings.hoverDelay

        // Start/stop monitoring based on settings
        if settings.showOnHover {
            hoverService.startMonitoring()
        } else {
            hoverService.stopMonitoring()
        }
    }

    // MARK: - Scanning

    func scan() async {
        guard permissionService.permissionState == .granted else {
            lastError = "Accessibility permission required"
            permissionService.showPermissionRequest()
            return
        }

        isScanning = true
        lastError = nil
        lastScanMessage = nil

        do {
            var scannedItems = try await accessibilityService.scanMenuBarItems()

            // Merge with saved configurations
            let savedItems = try? persistenceService.loadItemConfigurations()
            if let saved = savedItems, !saved.isEmpty {
                scannedItems = persistenceService.mergeWithSaved(
                    scannedItems: scannedItems,
                    savedItems: saved
                )
            }

            statusItems = scannedItems
            lastScanMessage = "Found \(scannedItems.count) menu bar item\(scannedItems.count == 1 ? "" : "s")"

            // Save updated configurations
            try? persistenceService.saveItemConfigurations(statusItems)

            // Update delimiter positions after scan
            updateDelimiterPositions()
        } catch {
            lastError = error.localizedDescription
            lastScanMessage = nil
        }

        isScanning = false

        // Clear success message after 3 seconds
        if lastScanMessage != nil {
            Task {
                try? await Task.sleep(for: .seconds(3))
                lastScanMessage = nil
            }
        }
    }

    // MARK: - Visibility Control

    func toggleHiddenItems() {
        Task {
            do {
                try await hidingService.toggle()

                // Schedule auto-rehide if enabled and we just showed
                if hidingState == .expanded && settings.autoRehide {
                    hidingService.scheduleRehide(after: settings.rehideDelay)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func showHiddenItems() {
        Task {
            do {
                try await hidingService.show()
                if settings.autoRehide {
                    hidingService.scheduleRehide(after: settings.rehideDelay)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func hideHiddenItems() {
        Task {
            do {
                try await hidingService.hide()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Update an item's section
    func updateItem(_ item: StatusItemModel, section: StatusItemModel.ItemSection) {
        guard let index = statusItems.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItem = item
        updatedItem.section = section
        updatedItem.isVisible = section == .alwaysVisible

        statusItems[index] = updatedItem

        // Persist changes
        saveSettings()

        // Move the item in the menu bar
        Task {
            do {
                try await hidingService.moveItem(item, to: section)
                await scan() // Rescan to update positions
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Record a click on an item (for analytics)
    func recordItemClick(_ item: StatusItemModel) {
        guard let index = statusItems.firstIndex(where: { $0.id == item.id }) else { return }

        statusItems[index].clickCount += 1
        statusItems[index].lastClickDate = Date()

        saveSettings()
    }

    // MARK: - Appearance

    private func updateStatusItemAppearance() {
        guard let button = mainStatusItem?.button else { return }

        // Could change icon based on state
        let iconName = hidingState == .expanded
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"

        // Only use SF Symbol if we don't have custom icon
        if NSImage(named: "MenuBarIcon") == nil {
            button.image = NSImage(
                systemSymbolName: iconName,
                accessibilityDescription: "SaneBar"
            )
        }
    }

    // MARK: - Event Handlers

    private func handleSectionShown() {
        // Update show timestamps for analytics
        for index in statusItems.indices where statusItems[index].section == .hidden {
            statusItems[index].lastShownDate = Date()
        }
    }

    private func handleSectionHidden() {
        hidingService.cancelRehide()
    }

    // MARK: - Actions

    @objc private func handleMainClick() {
        // Left-click toggles hidden items
        toggleHiddenItems()
    }

    @objc private func menuToggleHiddenItems(_ sender: Any?) {
        toggleHiddenItems()
    }

    @objc private func scanMenuItems(_ sender: Any?) {
        Task {
            await scan()
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}
