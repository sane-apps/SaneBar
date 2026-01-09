import AppKit
import KeyboardShortcuts
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "IconHotkeysService")

// MARK: - IconHotkeysService

/// Service for managing per-icon keyboard shortcuts
/// When triggered, shows hidden items and activates the target app
@MainActor
final class IconHotkeysService {

    // MARK: - Singleton

    static let shared = IconHotkeysService()

    // MARK: - Dependencies

    private weak var menuBarManager: MenuBarManager?
    private var registeredShortcuts: Set<String> = []  // Bundle IDs with registered shortcuts

    // MARK: - Configuration

    func configure(with manager: MenuBarManager) {
        self.menuBarManager = manager
        registerHotkeys(from: manager.settings)
    }

    // MARK: - Shortcut Registration

    /// Register all configured per-icon hotkeys
    func registerHotkeys(from settings: SaneBarSettings) {
        // Unregister old shortcuts first
        unregisterAllHotkeys()

        // Register new shortcuts
        for (bundleID, shortcutData) in settings.iconHotkeys {
            registerHotkey(for: bundleID, shortcut: shortcutData)
        }
    }

    /// Register a single hotkey for an app
    private func registerHotkey(for bundleID: String, shortcut: KeyboardShortcutData) {
        let shortcutName = KeyboardShortcuts.Name("iconHotkey-\(bundleID)")

        // Set the shortcut key combination
        let key = KeyboardShortcuts.Key(rawValue: Int(shortcut.keyCode))
        let modifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)

        let shortcutValue = KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
        KeyboardShortcuts.setShortcut(shortcutValue, for: shortcutName)

        // Register the handler
        KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
            Task { @MainActor in
                self?.handleHotkey(for: bundleID)
            }
        }

        registeredShortcuts.insert(bundleID)
        logger.info("Registered hotkey for \(bundleID)")
    }

    /// Unregister all hotkeys
    func unregisterAllHotkeys() {
        for bundleID in registeredShortcuts {
            let shortcutName = KeyboardShortcuts.Name("iconHotkey-\(bundleID)")
            KeyboardShortcuts.reset(shortcutName)
        }
        registeredShortcuts.removeAll()
    }

    // MARK: - Hotkey Handler

    /// Handle a per-icon hotkey press
    private func handleHotkey(for bundleID: String) {
        logger.info("Per-icon hotkey triggered for \(bundleID)")

        guard let manager = menuBarManager else { return }
        Task { @MainActor in
            let didReveal = await manager.showHiddenItemsNow(trigger: .hotkey)
            guard didReveal else { return }

            // Activate the target app (this may trigger its status bar menu)
            activateApp(bundleID: bundleID)
        }
    }

    /// Activate an app by bundle ID
    private func activateApp(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return
        }

        // Activate the app
        app.activate(options: [])
        logger.info("Activated app: \(bundleID)")
    }

    // MARK: - Shortcut Name Generation

    /// Get the KeyboardShortcuts.Name for an app's hotkey
    static func shortcutName(for bundleID: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("iconHotkey-\(bundleID)")
    }
}
