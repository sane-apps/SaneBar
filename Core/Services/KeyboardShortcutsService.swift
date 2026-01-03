import AppKit
import KeyboardShortcuts

// MARK: - Shortcut Names

extension KeyboardShortcuts.Name {
    /// Toggle visibility of hidden menu bar items
    static let toggleHiddenItems = Self("toggleHiddenItems")

    /// Show hidden items temporarily
    static let showHiddenItems = Self("showHiddenItems")

    /// Hide items immediately
    static let hideItems = Self("hideItems")

    /// Open SaneBar settings
    static let openSettings = Self("openSettings")

    /// Open menu bar search
    static let searchMenuBar = Self("searchMenuBar")
}

// MARK: - KeyboardShortcutsServiceProtocol

/// @mockable
@MainActor
protocol KeyboardShortcutsServiceProtocol {
    func registerAllHandlers()
    func unregisterAllHandlers()
}

// MARK: - KeyboardShortcutsService

/// Service for managing global keyboard shortcuts
/// Uses sindresorhus/KeyboardShortcuts library
@MainActor
final class KeyboardShortcutsService: KeyboardShortcutsServiceProtocol {

    // MARK: - Singleton

    static let shared = KeyboardShortcutsService()

    // MARK: - Dependencies

    private weak var menuBarManager: MenuBarManager?

    // MARK: - Initialization

    init(menuBarManager: MenuBarManager? = nil) {
        self.menuBarManager = menuBarManager
    }

    // MARK: - Configuration

    /// Connect to MenuBarManager for handling shortcuts
    func configure(with manager: MenuBarManager) {
        self.menuBarManager = manager
        registerAllHandlers()
    }

    // MARK: - Handler Registration

    /// Register all keyboard shortcut handlers
    func registerAllHandlers() {
        // Toggle hidden items (primary shortcut)
        KeyboardShortcuts.onKeyUp(for: .toggleHiddenItems) { [weak self] in
            Task { @MainActor in
                self?.menuBarManager?.toggleHiddenItems()
            }
        }

        // Show hidden items
        KeyboardShortcuts.onKeyUp(for: .showHiddenItems) { [weak self] in
            Task { @MainActor in
                self?.menuBarManager?.showHiddenItems()
            }
        }

        // Hide items
        KeyboardShortcuts.onKeyUp(for: .hideItems) { [weak self] in
            Task { @MainActor in
                self?.menuBarManager?.hideHiddenItems()
            }
        }

        // Open settings
        KeyboardShortcuts.onKeyUp(for: .openSettings) {
            Task { @MainActor in
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        // Open menu bar search
        KeyboardShortcuts.onKeyUp(for: .searchMenuBar) {
            Task { @MainActor in
                SearchWindowController.shared.toggle()
            }
        }
    }

    /// Unregister all handlers (for cleanup)
    func unregisterAllHandlers() {
        KeyboardShortcuts.reset(.toggleHiddenItems)
        KeyboardShortcuts.reset(.showHiddenItems)
        KeyboardShortcuts.reset(.hideItems)
        KeyboardShortcuts.reset(.openSettings)
        KeyboardShortcuts.reset(.searchMenuBar)
    }

    // MARK: - Default Shortcuts

    /// Set default shortcuts if none configured
    func setDefaultsIfNeeded() {
        // Only set defaults if user hasn't configured any
        if KeyboardShortcuts.getShortcut(for: .toggleHiddenItems) == nil {
            // Default: Cmd+\ for toggle (avoids conflict with Bold shortcut)
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: .command), for: .toggleHiddenItems)
        }

        if KeyboardShortcuts.getShortcut(for: .searchMenuBar) == nil {
            // Default: Cmd+Shift+B for search
            KeyboardShortcuts.setShortcut(.init(.b, modifiers: [.command, .shift]), for: .searchMenuBar)
        }
    }
}
