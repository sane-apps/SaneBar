import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Actions")

extension MenuBarManager {
    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        let event = NSApp.currentEvent
        let mainHasMenu = (mainStatusItem?.menu != nil)
        let sepHasMenu = (separatorItem?.menu != nil)
        logger.debug("Menu will open (event=\(String(describing: event?.type.rawValue)) mainHasMenu=\(mainHasMenu) sepHasMenu=\(sepHasMenu))")
        #if DEBUG
            let eventType = event.map { Int($0.type.rawValue) } ?? -1
            let buttonNumber = event?.buttonNumber ?? -1
            print("[MenuBarManager] menuWillOpen eventType=\(eventType) button=\(buttonNumber) mainHasMenu=\(mainHasMenu) sepHasMenu=\(sepHasMenu)")
        #endif

        let isRightClick: Bool = {
            guard let event else { return false }
            if event.type == .rightMouseUp || event.type == .rightMouseDown { return true }
            if event.type == .leftMouseUp || event.type == .leftMouseDown {
                if event.modifierFlags.contains(.control) { return true }
            }
            return event.buttonNumber == 1
        }()

        if !isRightClick {
            logger.warning("Menu opened from non-right click; cancelling and toggling instead")
            menu.cancelTracking()
            isMenuOpen = false
            toggleHiddenItems()
            return
        }

        isMenuOpen = true

        // Cancel any pending auto-rehide to prevent the menu from being
        // forcefully closed if the bar retracts while the user is navigating.
        hidingService.cancelRehide()

        logger.debug("Menu will open - checking targets...")
        for item in menu.items where !item.isSeparatorItem {
            let targetStatus = item.target == nil ? "nil" : "set"
            logger.debug("  '\(item.title)': target=\(targetStatus)")
        }
    }

    func menuDidClose(_: NSMenu) {
        logger.debug("Menu did close")
        isMenuOpen = false

        // If we are expanded and auto-rehide is enabled, restart the timer
        // so the bar doesn't stay stuck open after a menu interaction.
        if hidingState == .expanded, settings.autoRehide, !isRevealPinned, !shouldSkipHideForExternalMonitor {
            logger.debug("Restarting auto-rehide timer after menu close")
            hidingService.scheduleRehide(after: settings.rehideDelay)
        }
    }

    // MARK: - Menu Actions

    @objc func menuToggleHiddenItems(_: Any?) {
        logger.info("Menu: Toggle Hidden Items")
        toggleHiddenItems()
    }

    @objc func openSettings(_: Any?) {
        logger.info("Menu: Opening Settings")
        SettingsOpener.open()
    }

    @objc func openFindIcon(_: Any?) {
        logger.info("Menu: Browse Icons")
        SearchWindowController.shared.toggle()
    }

    @objc func quitApp(_: Any?) {
        logger.info("Menu: Quit")
        NSApplication.shared.terminate(nil)
    }

    @objc func checkForUpdates(_: Any?) {
        logger.info("Menu: Check for Updates")
        Task { @MainActor in
            userDidClickCheckForUpdates()
        }
    }

    @objc func statusItemClicked(_ sender: Any?) {
        // Ensure no status item has an attached menu (left-click must not open menu)
        mainStatusItem?.menu = nil
        separatorItem?.menu = nil
        mainStatusItem?.button?.menu = nil
        separatorItem?.button?.menu = nil

        #if DEBUG
            if let button = sender as? NSStatusBarButton {
                let id = button.identifier?.rawValue ?? "nil"
                let hasMenu = (button.menu != nil)
                logger.debug("statusItemClicked sender=\(id) hasMenu=\(hasMenu)")
                print("[MenuBarManager] statusItemClicked sender=\(id) hasMenu=\(hasMenu)")
            }
        #endif

        // Prevent interaction during animation to avoid race conditions
        if hidingService.isAnimating {
            logger.info("Ignoring click while animating")
            return
        }

        guard let event = NSApp.currentEvent else {
            logger.warning("statusItemClicked: No current event available; defaulting to left click")
            #if DEBUG
                print("[MenuBarManager] statusItemClicked: no event")
            #endif
            toggleHiddenItems()
            return
        }

        let clickType = StatusBarController.clickType(from: event)
        logger.info("statusItemClicked: event type=\(event.type.rawValue), clickType=\(String(describing: clickType))")
        #if DEBUG
            print("[MenuBarManager] statusItemClicked eventType=\(event.type.rawValue) button=\(event.buttonNumber) modifiers=\(event.modifierFlags.rawValue) clickType=\(clickType)")
        #endif

        switch clickType {
        case .optionClick:
            logger.info("Option-click: opening Browse Icons")
            SearchWindowController.shared.toggle()
        case .leftClick:
            if settings.leftClickOpensBrowseIcons {
                logger.info("Left-click: opening Browse Icons (leftClickOpensBrowseIcons)")
                SearchWindowController.shared.toggle()
            } else {
                logger.info("Left-click: calling toggleHiddenItems()")
                toggleHiddenItems()
            }
        case .rightClick:
            showStatusMenu()
        }
    }

    func showStatusMenu() {
        guard let statusMenu,
              let button = mainStatusItem?.button else { return }

        logger.info("Showing status menu (anchor: main icon)")
        // Pop up directly — avoids performClick re-triggering statusItemClicked
        let origin = NSPoint(x: 0, y: button.bounds.maxY + 5)
        statusMenu.popUp(positioning: nil, at: origin, in: button)
    }
}
