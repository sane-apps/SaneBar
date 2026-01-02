import Accessibility
import Cocoa

class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()

    @Published var statusItems: [StatusItem] = []

    private let systemUIServerBundleId = "com.apple.systemuiserver"
    private let controlCenterBundleId = "com.apple.controlcenter"

    // Our own status item (the "handle")
    private var statusItem: NSStatusItem?

    private init() {
        setupStatusItem()
        // Delay scan to allow permissions to settle if needed, though we should check immediately
        scanForStatusItems()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "circle.circle", accessibilityDescription: "SaneBar")
            button.action = #selector(toggleHiding)
            button.target = self
        }
    }

    @objc func toggleHiding() {
        print("Toggling visibility...")
        // Logic to hide/show items will go here
        // For now, just re-scan
        scanForStatusItems()
    }

    // MARK: - Scanning

    func scanForStatusItems() {
        // macOS 15+ usually hosts these in Control Center or separate processes
        // We need to query the Menu Bar AX element directly.

        guard checkAccessibilityPermissions() else {
            print("❌ No Accessibility Permissions")
            return
        }

        // Find the System Menu Bar
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if accessEnabled {
            // Get System Wide Element
            let systemWide = AXUIElementCreateSystemWide()

            // Get the Menu Bar
            // Note: This is an expensive traversal, simplified for MVP
            // In reality, we might need to filter specifically for the menu bar window
        }
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

struct StatusItem: Identifiable {
    let id = UUID()
    let title: String
    let position: Int
}
