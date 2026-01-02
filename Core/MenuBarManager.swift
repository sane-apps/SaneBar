import AppKit
import ApplicationServices

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

    // MARK: - Services

    let accessibilityService = AccessibilityService()
    let permissionService = PermissionService()

    // MARK: - Menu Bar Status Item

    private var ownStatusItem: NSStatusItem?

    // MARK: - Initialization

    private init() {
        setupOwnStatusItem()

        // Scan if we have permission
        if permissionService.permissionState == .granted {
            Task {
                await scan()
            }
        }
    }

    // MARK: - Setup

    /// Create SaneBar's own menu bar icon
    private func setupOwnStatusItem() {
        ownStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = ownStatusItem?.button {
            // Use custom menu bar icon, fall back to SF Symbol
            let customIcon = NSImage(named: "MenuBarIcon")
            print("🔍 MenuBarIcon lookup: \(customIcon != nil ? "FOUND" : "NOT FOUND")")

            if let icon = customIcon {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
                print("✅ Using custom MenuBarIcon")
            } else {
                button.image = NSImage(
                    systemSymbolName: "line.3.horizontal.decrease.circle",
                    accessibilityDescription: "SaneBar"
                )
                print("⚠️ Falling back to SF Symbol")
            }
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }

        // Add a menu - BUG-005: Must set target explicitly since MenuBarManager isn't in responder chain
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle Hidden Items", action: #selector(menuToggleHiddenItems), keyEquivalent: "b")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let scanItem = NSMenuItem(title: "Scan Menu Bar", action: #selector(scanMenuItems), keyEquivalent: "r")
        scanItem.target = self
        menu.addItem(scanItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit SaneBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        ownStatusItem?.menu = menu
    }

    // MARK: - Scanning

    /// Scan for menu bar items
    func scan() async {
        guard permissionService.permissionState == .granted else {
            lastError = "Accessibility permission required"
            permissionService.showPermissionRequest()
            return
        }

        isScanning = true
        lastError = nil

        do {
            let items = try await accessibilityService.scanMenuBarItems()
            statusItems = items
            print("✅ Found \(items.count) menu bar items")
        } catch {
            lastError = error.localizedDescription
            print("❌ Scan failed: \(error)")
        }

        isScanning = false
    }

    // MARK: - Visibility Control

    /// Toggle visibility of hidden items
    func toggleHiddenItems() {
        // Phase 2: Implement show/hide logic
        print("Toggle hidden items - coming in Phase 2")
    }

    /// Update an item's section and visibility
    func updateItem(_ item: StatusItemModel, section: StatusItemModel.ItemSection) {
        guard let index = statusItems.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItem = item
        updatedItem.section = section
        updatedItem.isVisible = section == .alwaysVisible

        statusItems[index] = updatedItem

        // TODO: Persist changes
        // TODO: Apply visibility changes via AX API
    }

    // MARK: - Actions

    @objc private func handleStatusItemClick() {
        // Left-click shows menu (handled by NSMenu)
        // Option-click could toggle hidden items
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
        // Open the Settings window
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
