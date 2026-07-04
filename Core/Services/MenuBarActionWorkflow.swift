import AppKit
import os.log
import SaneUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarActionWorkflow")

@MainActor
final class MenuBarActionWorkflow: NSObject, NSMenuDelegate {
    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
        super.init()
    }

    nonisolated static func isStatusMenuRightClick(
        explicitTriggerPending: Bool,
        eventType: NSEvent.EventType?,
        buttonNumber: Int?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        if explicitTriggerPending { return true }
        if eventType == .rightMouseUp || eventType == .rightMouseDown { return true }
        if eventType == .leftMouseUp || eventType == .leftMouseDown {
            if modifierFlags.contains(.control) { return true }
        }
        return buttonNumber == 1
    }

    nonisolated static func normalizedLeftClickOpensBrowseIcons(
        isPro _: Bool,
        useSecondMenuBar _: Bool,
        leftClickOpensBrowseIcons: Bool
    ) -> Bool {
        leftClickOpensBrowseIcons
    }

    nonisolated static func effectiveAlwaysHiddenSectionEnabled(
        isPro: Bool,
        alwaysHiddenSectionEnabled: Bool
    ) -> Bool {
        isPro && alwaysHiddenSectionEnabled
    }

    nonisolated static func normalizedSecondMenuBarRows(
        isPro: Bool,
        showVisible: Bool,
        showAlwaysHidden: Bool
    ) -> (showVisible: Bool, showAlwaysHidden: Bool) {
        guard !isPro else {
            return (showVisible, showAlwaysHidden)
        }
        return (true, false)
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated static func shouldOpenSecondMenuBarFallback(
        useSecondMenuBar: Bool,
        leftClickOpensBrowseIcons: Bool,
        requireAuthToShowHiddenIcons: Bool,
        preToggleState: HidingState,
        postToggleState: HidingState,
        isBrowseVisible: Bool
    ) -> Bool {
        guard useSecondMenuBar else { return false }
        guard !leftClickOpensBrowseIcons else { return false }
        guard !requireAuthToShowHiddenIcons else { return false }
        guard preToggleState == .hidden, postToggleState == .hidden else { return false }
        return !isBrowseVisible
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildProfileSubmenu(in: menu)

        let event = NSApp.currentEvent
        let mainHasMenu = manager.mainStatusItem?.menu != nil
        let sepHasMenu = manager.separatorItem?.menu != nil
        logger.debug("Menu will open (event=\(String(describing: event?.type.rawValue)) mainHasMenu=\(mainHasMenu) sepHasMenu=\(sepHasMenu))")
        #if DEBUG
            let eventType = event.map { Int($0.type.rawValue) } ?? -1
            let buttonNumber = event?.buttonNumber ?? -1
            print("[MenuBarManager] menuWillOpen eventType=\(eventType) button=\(buttonNumber) mainHasMenu=\(mainHasMenu) sepHasMenu=\(sepHasMenu)")
        #endif

        let isRightClick = Self.isStatusMenuRightClick(
            explicitTriggerPending: manager.pendingExplicitStatusMenuRightClick,
            eventType: event?.type,
            buttonNumber: event?.buttonNumber,
            modifierFlags: event?.modifierFlags ?? []
        )

        if !isRightClick {
            logger.warning("Menu opened from non-right click; cancelling and toggling instead")
            menu.cancelTracking()
            manager.isMenuOpen = false
            manager.visibilityWorkflow.toggleHiddenItems()
            return
        }

        manager.isMenuOpen = true
        manager.hidingService.cancelRehide()

        logger.debug("Menu will open - checking targets...")
        for item in menu.items where !item.isSeparatorItem {
            let targetStatus = item.target == nil ? "nil" : "set"
            logger.debug("  '\(item.title)': target=\(targetStatus)")
        }
    }

    func menuDidClose(_: NSMenu) {
        logger.debug("Menu did close")
        manager.isMenuOpen = false
        manager.pendingExplicitStatusMenuRightClick = false

        if manager.hidingState == .expanded,
           manager.settings.autoRehide,
           !manager.isRevealPinned,
           !manager.shouldSkipHideForExternalMonitor {
            logger.debug("Restarting auto-rehide timer after menu close")
            manager.hidingService.scheduleRehide(after: manager.settings.rehideDelay)
        }
    }

    func normalizeLicenseDependentDefaults() {
        let isPro = LicenseService.shared.isPro
        let normalized = Self.normalizedLeftClickOpensBrowseIcons(
            isPro: isPro,
            useSecondMenuBar: manager.settings.useSecondMenuBar,
            leftClickOpensBrowseIcons: manager.settings.leftClickOpensBrowseIcons
        )
        let normalizedRows = Self.normalizedSecondMenuBarRows(
            isPro: isPro,
            showVisible: manager.settings.secondMenuBarShowVisible,
            showAlwaysHidden: manager.settings.secondMenuBarShowAlwaysHidden
        )

        var changed = false
        if normalized != manager.settings.leftClickOpensBrowseIcons {
            manager.settings.leftClickOpensBrowseIcons = normalized
            changed = true
        }
        if normalizedRows.showVisible != manager.settings.secondMenuBarShowVisible {
            manager.settings.secondMenuBarShowVisible = normalizedRows.showVisible
            changed = true
        }
        if normalizedRows.showAlwaysHidden != manager.settings.secondMenuBarShowAlwaysHidden {
            manager.settings.secondMenuBarShowAlwaysHidden = normalizedRows.showAlwaysHidden
            changed = true
        }

        if changed, !isPro {
            logger.info("Normalized free-mode Second Menu Bar rows to Visible + Hidden")
        }

        manager.updateAlwaysHiddenSeparatorIfReady()

        if changed {
            manager.saveSettings()
        }
    }

    @objc func menuToggleHiddenItems(_: Any?) {
        logger.info("Menu: Toggle Hidden Items")
        manager.visibilityWorkflow.toggleHiddenItems()
    }

    @objc func menuArrangeNow(_: Any?) {
        logger.info("Menu: Arrange Now")
        manager.profileWorkflow.arrangeNow(reason: "status-menu")
    }

    @objc func openSettings(_: Any?) {
        logger.info("Menu: Opening Settings")
        SettingsOpener.open()
    }

    @objc func openLicense(_: Any?) {
        logger.info("Menu: Opening License")
        SettingsOpener.open(tab: .license)
    }

    @objc func openDonate(_: Any?) {
        logger.info("Menu: Opening donation page")
        NSWorkspace.shared.open(LicenseService.donationURL())
    }

    @objc func openAbout(_: Any?) {
        logger.info("Menu: Opening About / Report")
        SettingsOpener.open(tab: .about)
    }

    @objc func openHealth(_: Any?) {
        logger.info("Menu: Opening Health")
        SettingsOpener.open(tab: .health)
    }

    @objc func showReleaseNotes(_: Any?) {
        logger.info("Menu: Opening Setapp release notes")
        SetappIntegration.showReleaseNotes()
    }

    @objc func openFindIcon(_: Any?) {
        logger.info("Menu: Browse Icons")
        SearchWindowController.shared.toggle()
    }

    @objc func quitApp(_: Any?) {
        logger.info("Menu: Quit")
        NotificationCenter.default.post(name: .saneBarExplicitTerminationRequested, object: nil)
        NSApplication.shared.terminate(nil)
    }

    @objc func userDidClickCheckForUpdates(_: Any? = nil) {
        logger.info("User requested update check")
        manager.settings.lastUpdateCheck = Date()
        manager.saveSettings()
        NSApp.activate()
        manager.updateService.checkForUpdates()
    }

    func syncUpdateConfiguration() {
        manager.updateService.automaticallyChecksForUpdates = manager.settings.checkForUpdatesAutomatically
    }

    func updateUpdateMenuAvailability() {
        guard let updateItem = manager.statusMenu?.item(withTitle: "Check for Updates...") else { return }
        updateItem.isEnabled = manager.updateService.isUpdateChannelEnabled
        if manager.updateService.isUpdateChannelEnabled {
            updateItem.toolTip = nil
        } else {
            updateItem.toolTip = Self.updateUnavailableTooltip(for: LicenseService.shared.distributionChannel)
        }
    }

    nonisolated static func updateUnavailableTooltip(for channel: SaneDistributionChannel) -> String {
        switch channel {
        case .setapp:
            "Updates are managed by Setapp."
        case .appStore:
            "Updates are managed by the App Store."
        case .direct:
            "Updates are available from the installed /Applications/SaneBar.app build."
        }
    }

    @objc func statusItemClicked(_ sender: Any?) {
        manager.mainStatusItem?.menu = nil
        manager.separatorItem?.menu = nil
        manager.mainStatusItem?.button?.menu = nil
        manager.separatorItem?.button?.menu = nil

        #if DEBUG
            if let button = sender as? NSStatusBarButton {
                let id = button.identifier?.rawValue ?? "nil"
                let hasMenu = button.menu != nil
                logger.debug("statusItemClicked sender=\(id) hasMenu=\(hasMenu)")
                print("[MenuBarManager] statusItemClicked sender=\(id) hasMenu=\(hasMenu)")
            }
        #endif

        if manager.hidingService.isAnimating {
            logger.info("Ignoring click while animating")
            return
        }

        SetappIntegration.reportMenuBarInteraction()

        guard let event = NSApp.currentEvent else {
            logger.warning("statusItemClicked: No current event available; defaulting to left click")
            #if DEBUG
                print("[MenuBarManager] statusItemClicked: no event")
            #endif
            manager.visibilityWorkflow.toggleHiddenItems(trigger: .click)
            return
        }

        let clickType = StatusBarController.clickType(from: event)
        logger.info("statusItemClicked: event type=\(event.type.rawValue), clickType=\(String(describing: clickType))")
        #if DEBUG
            print("[MenuBarManager] statusItemClicked eventType=\(event.type.rawValue) button=\(event.buttonNumber) modifiers=\(event.modifierFlags.rawValue) clickType=\(clickType)")
        #endif

        let clickedButton = sender as? NSStatusBarButton
        manager.hoverService.noteExplicitStatusItemInteraction()

        switch clickType {
        case .optionClick:
            logger.info("Option-click: opening Browse Icons")
            SearchWindowController.shared.toggle()
        case .leftClick:
            handleLeftClick()
        case .rightClick:
            showStatusMenu(anchorButton: clickedButton, triggeringEvent: event)
        }
    }

    func showStatusMenu(anchorButton preferredButton: NSStatusBarButton? = nil, triggeringEvent event: NSEvent? = nil) {
        guard let statusMenu = manager.statusMenu else { return }
        guard let button = preferredButton ?? manager.mainStatusItem?.button ?? manager.separatorItem?.button else { return }

        let anchor = button.identifier?.rawValue ?? "unknown"
        let buttonFrame = button.frame
        let windowFrame = button.window?.frame ?? .zero
        logger.info("Showing status menu (anchor: \(anchor, privacy: .public), buttonFrame: \(buttonFrame.debugDescription, privacy: .public), windowFrame: \(windowFrame.debugDescription, privacy: .public))")

        manager.pendingExplicitStatusMenuRightClick = true
        if let event {
            NSMenu.popUpContextMenu(statusMenu, with: event, for: button)
            manager.pendingExplicitStatusMenuRightClick = false
            return
        }

        let origin = NSPoint(x: button.bounds.midX, y: button.bounds.maxY)
        statusMenu.popUp(positioning: nil, at: origin, in: button)
        manager.pendingExplicitStatusMenuRightClick = false
    }

    func applyProfileFromMenu(_ sender: NSMenuItem) {
        guard let rawId = sender.representedObject as? String,
              let id = UUID(uuidString: rawId) else { return }
        _ = manager.profileWorkflow.applyProfile(id: id, reason: "status-menu")
    }

    @objc func applyProfileFromMenuAction(_ sender: NSMenuItem) {
        applyProfileFromMenu(sender)
    }

    func saveCurrentProfileFromMenu() {
        let existingNames = manager.profileWorkflow.savedProfiles().map(\.name)
        let name = SaneBarProfile.generateName(basedOn: existingNames)
        do {
            try manager.profileWorkflow.saveCurrentProfile(named: name)
        } catch {
            logger.error("Menu: failed to save profile \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc func saveCurrentProfileFromMenuAction(_: Any?) {
        saveCurrentProfileFromMenu()
    }

    private func handleLeftClick() {
        if manager.settings.leftClickOpensBrowseIcons {
            logger.info("Left-click: opening Browse Icons (leftClickOpensBrowseIcons)")
            SearchWindowController.shared.toggle()
            return
        }

        logger.info("Left-click: calling toggleHiddenItems()")
        let preToggleState = manager.hidingService.state
        let fallbackShouldBeEvaluated = manager.settings.useSecondMenuBar &&
            !manager.settings.requireAuthToShowHiddenIcons &&
            preToggleState == .hidden
        manager.visibilityWorkflow.toggleHiddenItems(trigger: .click)
        guard fallbackShouldBeEvaluated else { return }

        Task { @MainActor [weak manager] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let manager else { return }

            if Self.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: manager.settings.useSecondMenuBar,
                leftClickOpensBrowseIcons: manager.settings.leftClickOpensBrowseIcons,
                requireAuthToShowHiddenIcons: manager.settings.requireAuthToShowHiddenIcons,
                preToggleState: preToggleState,
                postToggleState: manager.hidingService.state,
                isBrowseVisible: SearchWindowController.shared.isVisible
            ) {
                logger.info("Left-click fallback: reveal stayed hidden; opening Second Menu Bar")
                SearchWindowController.shared.toggle()
            }
        }
    }

    private func rebuildProfileSubmenu(in menu: NSMenu) {
        let title = "Profiles"
        let profileMenuItem: NSMenuItem
        if let existing = menu.items.first(where: { $0.title == title }) {
            profileMenuItem = existing
        } else {
            profileMenuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let insertAfter = menu.items.firstIndex(where: { $0.title == "Show / Hide Icons" }) {
                menu.insertItem(profileMenuItem, at: insertAfter + 1)
            } else {
                menu.insertItem(profileMenuItem, at: min(2, menu.items.count))
            }
        }

        let submenu = NSMenu()
        let profiles = manager.profileWorkflow.savedProfiles()
        if profiles.isEmpty {
            let empty = NSMenuItem(title: "No Saved Profiles", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for profile in profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(MenuBarActionWorkflow.applyProfileFromMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id.uuidString
                submenu.addItem(item)
            }
        }
        submenu.addItem(NSMenuItem.separator())
        let saveItem = NSMenuItem(title: "Save Current as Profile", action: #selector(MenuBarActionWorkflow.saveCurrentProfileFromMenuAction(_:)), keyEquivalent: "")
        saveItem.target = self
        submenu.addItem(saveItem)
        profileMenuItem.submenu = submenu
    }
}
