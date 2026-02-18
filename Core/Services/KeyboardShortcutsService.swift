import AppKit
import KeyboardShortcuts
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "KeyboardShortcutsService")

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
        menuBarManager = manager
        registerAllHandlers()
    }

    // MARK: - Handler Registration

    /// Register all keyboard shortcut handlers
    func registerAllHandlers() {
        // Toggle hidden items (primary shortcut)
        KeyboardShortcuts.onKeyUp(for: .toggleHiddenItems) { [weak self] in
            logger.info("Hotkey: toggleHiddenItems")
            Task { @MainActor in
                self?.menuBarManager?.toggleHiddenItems()
            }
        }

        // Show hidden items
        KeyboardShortcuts.onKeyUp(for: .showHiddenItems) { [weak self] in
            logger.info("Hotkey: showHiddenItems")
            Task { @MainActor in
                self?.menuBarManager?.showHiddenItems()
            }
        }

        // Hide items
        KeyboardShortcuts.onKeyUp(for: .hideItems) { [weak self] in
            logger.info("Hotkey: hideItems")
            Task { @MainActor in
                self?.menuBarManager?.hideHiddenItems()
            }
        }

        // Open settings
        KeyboardShortcuts.onKeyUp(for: .openSettings) {
            logger.info("Hotkey: openSettings")
            Task { @MainActor in
                SettingsOpener.open()
            }
        }

        // Menu bar search
        KeyboardShortcuts.onKeyUp(for: .searchMenuBar) {
            logger.info("Hotkey: searchMenuBar")
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

    private static let defaultsInitializedKey = "KeyboardShortcutsDefaultsInitialized"

    /// Set default shortcuts on first launch only.
    /// After first run, user changes (including clearing shortcuts) are preserved.
    func setDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.defaultsInitializedKey) else { return }

        // Toggle: Cmd+\ (primary action)
        if KeyboardShortcuts.getShortcut(for: .toggleHiddenItems) == nil {
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: .command), for: .toggleHiddenItems)
        }

        // Show hidden: Cmd+Shift+\
        if KeyboardShortcuts.getShortcut(for: .showHiddenItems) == nil {
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: [.command, .shift]), for: .showHiddenItems)
        }

        // Hide items: Cmd+Option+\
        if KeyboardShortcuts.getShortcut(for: .hideItems) == nil {
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: [.command, .option]), for: .hideItems)
        }

        // Search apps: Cmd+Shift+Space
        if KeyboardShortcuts.getShortcut(for: .searchMenuBar) == nil {
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.command, .shift]), for: .searchMenuBar)
        }

        // Note: No default for openSettings - ⌘, is a standard macOS convention
        // for app-specific Settings. A global hotkey would override ALL apps.
        // Users can manually set this in Settings → Shortcuts if desired.

        UserDefaults.standard.set(true, forKey: Self.defaultsInitializedKey)
    }
}
