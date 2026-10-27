import AppKit
import KeyboardShortcuts
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "IconHotkeysService")


@MainActor
final class IconHotkeysService {


    static let shared = IconHotkeysService()


    private weak var menuBarManager: MenuBarManager?
    private var registeredShortcuts: Set<String> = []


    func configure(with manager: MenuBarManager) {
        self.menuBarManager = manager
        registerHotkeys(from: manager.settings)
    }


    func registerHotkeys(from settings: SaneBarSettings) {
        unregisterAllHotkeys()

        for (bundleID, shortcutData) in settings.iconHotkeys {
            registerHotkey(for: bundleID, shortcut: shortcutData)
        }
    }

    private func registerHotkey(for bundleID: String, shortcut: KeyboardShortcutData) {
        let shortcutName = KeyboardShortcuts.Name("iconHotkey-\(bundleID)")

        let key = KeyboardShortcuts.Key(rawValue: Int(shortcut.keyCode))
        let modifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)

        let shortcutValue = KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
        KeyboardShortcuts.setShortcut(shortcutValue, for: shortcutName)

        KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
            Task { @MainActor in
                self?.handleHotkey(for: bundleID)
            }
        }

        registeredShortcuts.insert(bundleID)
        logger.info("Registered hotkey for \(bundleID)")
    }

    func unregisterAllHotkeys() {
        for bundleID in registeredShortcuts {
            let shortcutName = KeyboardShortcuts.Name("iconHotkey-\(bundleID)")
            KeyboardShortcuts.reset(shortcutName)
        }
        registeredShortcuts.removeAll()
    }


    private func handleHotkey(for bundleID: String) {
        logger.info("Per-icon hotkey triggered for \(bundleID)")

        guard let manager = menuBarManager else { return }
        Task { @MainActor in
            let didReveal = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .hotkey)
            guard didReveal else { return }

            activateApp(bundleID: bundleID)
        }
    }

    private func activateApp(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return
        }

        app.activate(options: [])
        logger.info("Activated app: \(bundleID)")
    }


    static func shortcutName(for bundleID: String) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name("iconHotkey-\(bundleID)")
    }
}
