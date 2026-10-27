import AppKit
import KeyboardShortcuts
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "KeyboardShortcutsService")


extension KeyboardShortcuts.Name {
    static let toggleHiddenItems = Self("toggleHiddenItems")

    static let showHiddenItems = Self("showHiddenItems")

    static let hideItems = Self("hideItems")

    static let openSettings = Self("openSettings")

    static let searchMenuBar = Self("searchMenuBar")
}


@MainActor
protocol KeyboardShortcutsServiceProtocol {
    func registerAllHandlers()
    func unregisterAllHandlers()
}


@MainActor
final class KeyboardShortcutsService: KeyboardShortcutsServiceProtocol {

    static let shared = KeyboardShortcutsService()


    private weak var menuBarManager: MenuBarManager?


    init(menuBarManager: MenuBarManager? = nil) {
        self.menuBarManager = menuBarManager
    }


    func configure(with manager: MenuBarManager) {
        menuBarManager = manager
        registerAllHandlers()
    }


    func registerAllHandlers() {
        KeyboardShortcuts.onKeyUp(for: .toggleHiddenItems) { [weak self] in
            logger.info("Hotkey: toggleHiddenItems")
            Task { @MainActor in
                self?.menuBarManager?.visibilityWorkflow.toggleHiddenItems()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .showHiddenItems) { [weak self] in
            logger.info("Hotkey: showHiddenItems")
            Task { @MainActor in
                self?.menuBarManager?.visibilityWorkflow.showHiddenItems()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .hideItems) { [weak self] in
            logger.info("Hotkey: hideItems")
            Task { @MainActor in
                self?.menuBarManager?.visibilityWorkflow.hideHiddenItems()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openSettings) {
            logger.info("Hotkey: openSettings")
            Task { @MainActor in
                SettingsOpener.open()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .searchMenuBar) {
            logger.info("Hotkey: searchMenuBar")
            Task { @MainActor in
                SearchWindowController.shared.toggle()
            }
        }
    }

    func unregisterAllHandlers() {
        KeyboardShortcuts.reset(.toggleHiddenItems)
        KeyboardShortcuts.reset(.showHiddenItems)
        KeyboardShortcuts.reset(.hideItems)
        KeyboardShortcuts.reset(.openSettings)
        KeyboardShortcuts.reset(.searchMenuBar)
    }


    private static let defaultsInitializedKey = "KeyboardShortcutsDefaultsInitialized"

    func setDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.defaultsInitializedKey) else { return }

        if KeyboardShortcuts.getShortcut(for: .toggleHiddenItems) == nil {
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: .command), for: .toggleHiddenItems)
        }

        if KeyboardShortcuts.getShortcut(for: .showHiddenItems) == nil {
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: [.command, .shift]), for: .showHiddenItems)
        }

        if KeyboardShortcuts.getShortcut(for: .hideItems) == nil {
            KeyboardShortcuts.setShortcut(.init(.backslash, modifiers: [.command, .option]), for: .hideItems)
        }

        if KeyboardShortcuts.getShortcut(for: .searchMenuBar) == nil {
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.command, .shift]), for: .searchMenuBar)
        }


        UserDefaults.standard.set(true, forKey: Self.defaultsInitializedKey)
    }
}
