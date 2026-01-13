import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Actions")

extension MenuBarManager {
    
    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        logger.debug("Menu will open - checking targets...")
        for item in menu.items where !item.isSeparatorItem {
            let targetStatus = item.target == nil ? "nil" : "set"
            logger.debug("  '\(item.title)': target=\(targetStatus)")
        }
    }

    // MARK: - Menu Actions

    @objc func menuToggleHiddenItems(_ sender: Any?) {
        logger.info("Menu: Toggle Hidden Items")
        toggleHiddenItems()
    }

    @objc func openSettings(_ sender: Any?) {
        logger.info("Menu: Opening Settings")
        SettingsOpener.open()
    }

    @objc func openFindIcon(_ sender: Any?) {
        logger.info("Menu: Find Icon")
        SearchWindowController.shared.toggle()
    }

    @objc func quitApp(_ sender: Any?) {
        logger.info("Menu: Quit")
        NSApplication.shared.terminate(nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        logger.info("Menu: Check for Updates")
        Task {
            await performUpdateCheck()
        }
    }
    
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        switch StatusBarController.clickType(from: event) {
        case .optionClick:
            logger.info("Option-click: opening Power Search")
            SearchWindowController.shared.toggle()
        case .leftClick:
            toggleHiddenItems()
        case .rightClick:
            showStatusMenu()
        }
    }

    func showStatusMenu() {
        guard let statusMenu = statusMenu,
              let item = mainStatusItem,
              let button = item.button else { return } // Removed redundant nil check on button
        logger.info("Right-click: showing menu")
        // Let AppKit choose the best placement (avoids weird clipping/partially-collapsed menus)
        item.popUpMenu(statusMenu)
    }
}
