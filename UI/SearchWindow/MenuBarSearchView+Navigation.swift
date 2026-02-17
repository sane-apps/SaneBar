import AppKit
import SwiftUI

// MARK: - Zone Classification, Action Factories & Keyboard Navigation

extension MenuBarSearchView {
    // MARK: - Zone Classification (for All tab context menus)

    enum AppZone { case visible, hidden, alwaysHidden }

    /// Classify an app's current zone based on its X position vs separator positions.
    func appZone(for app: RunningApp) -> AppZone {
        guard let xPos = app.xPosition else { return .visible }
        let midX = xPos + ((app.width ?? 22) / 2)
        let margin: CGFloat = 6

        if let ahX = menuBarManager.getAlwaysHiddenSeparatorOriginX(),
           midX < (ahX - margin) {
            return .alwaysHidden
        }
        if let sepX = menuBarManager.getSeparatorOriginX(),
           midX < (sepX - margin) {
            return .hidden
        }
        return .visible
    }

    // MARK: - Action Factories

    func makeToggleHiddenAction(for app: RunningApp) -> (() -> Void)? {
        // Determine direction based on tab (or actual zone for All tab)
        let toHidden: Bool
        let isAH: Bool
        switch mode {
        case .visible: toHidden = true; isAH = false
        case .hidden: toHidden = false; isAH = false
        case .alwaysHidden: toHidden = false; isAH = true
        case .all:
            let zone = appZone(for: app)
            switch zone {
            case .visible: toHidden = true; isAH = false
            case .hidden: toHidden = false; isAH = false
            case .alwaysHidden: toHidden = false; isAH = true
            }
        }

        return {
            let bundleID = app.bundleId
            let menuExtraId = app.menuExtraIdentifier
            let statusItemIndex = app.statusItemIndex

            self.movingAppId = app.uniqueId

            if isAH {
                self.menuBarManager.unpinAlwaysHidden(app: app)
                _ = self.menuBarManager.moveIconFromAlwaysHidden(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex
                )
            } else {
                _ = self.menuBarManager.moveIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    toHidden: toHidden
                )
            }
        }
    }

    func makeMoveToHiddenAction(for app: RunningApp) -> (() -> Void)? {
        // Show "Move to Hidden" for AH tab, or for AH apps in All tab
        let isAH = mode == .alwaysHidden || (mode == .all && appZone(for: app) == .alwaysHidden)
        guard isAH else { return nil }
        return {
            let bundleID = app.bundleId
            let menuExtraId = app.menuExtraIdentifier
            let statusItemIndex = app.statusItemIndex

            self.movingAppId = app.uniqueId
            self.menuBarManager.unpinAlwaysHidden(app: app)
            _ = self.menuBarManager.moveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }
    }

    func makeMoveToAlwaysHiddenAction(for app: RunningApp) -> (() -> Void)? {
        guard isAlwaysHiddenEnabled else { return nil }
        // Don't show for AH tab, or for AH apps in All tab
        let isAH = mode == .alwaysHidden || (mode == .all && appZone(for: app) == .alwaysHidden)
        guard !isAH else { return nil }
        return {
            let bundleID = app.bundleId
            let menuExtraId = app.menuExtraIdentifier
            let statusItemIndex = app.statusItemIndex

            self.movingAppId = app.uniqueId
            self.menuBarManager.pinAlwaysHidden(app: app)
            _ = self.menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }
    }

    func activateApp(_ app: RunningApp, isRightClick: Bool = false) {
        Task {
            await service.activate(app: app, isRightClick: isRightClick)
        }
    }

    func handleGridReorderDrop(_ payloads: [String], targetApp: RunningApp) -> Bool {
        guard LicenseService.shared.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceBundleID = payloads.first else { return false }
        guard sourceBundleID != targetApp.bundleId else { return false }
        guard let sourceApp = filteredApps.first(where: { $0.bundleId == sourceBundleID }) else { return false }

        let sourceX = sourceApp.xPosition ?? 0
        let targetX = targetApp.xPosition ?? 0
        let placeAfterTarget = sourceX < targetX

        _ = menuBarManager.reorderIcon(
            sourceBundleID: sourceApp.bundleId,
            sourceMenuExtraID: sourceApp.menuExtraIdentifier,
            sourceStatusItemIndex: sourceApp.statusItemIndex,
            targetBundleID: targetApp.bundleId,
            targetMenuExtraID: targetApp.menuExtraIdentifier,
            targetStatusItemIndex: targetApp.statusItemIndex,
            placeAfterTarget: placeAfterTarget
        )

        movingAppId = sourceApp.uniqueId
        return true
    }

    // MARK: - Keyboard Navigation

    /// Whether keyboard navigation should be active (not when modals are open)
    var isKeyboardNavigationActive: Bool {
        !isCreatingGroup && hotkeyApp == nil
    }

    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Don't capture keys when modals/popovers are open
        // Let them handle their own keyboard events
        guard isKeyboardNavigationActive else {
            return .ignored
        }

        // If search field is focused, let it handle most keys
        if isSearchFieldFocused {
            switch keyPress.key {
            case .downArrow:
                // Exit search field and select first app
                isSearchFieldFocused = false
                selectedAppIndex = filteredApps.isEmpty ? nil : 0
                return .handled
            case .upArrow:
                // Exit search field and select last app
                isSearchFieldFocused = false
                selectedAppIndex = filteredApps.isEmpty ? nil : filteredApps.count - 1
                return .handled
            case .return:
                // Activate first match while typing
                if let first = filteredApps.first {
                    activateApp(first)
                    return .handled
                }
                return .ignored
            default:
                return .ignored // Let TextField handle it
            }
        }

        // Grid navigation mode
        switch keyPress.key {
        case .downArrow:
            moveSelection(by: 1)
            return .handled
        case .upArrow:
            moveSelection(by: -1)
            return .handled
        case .leftArrow:
            moveSelectionHorizontal(by: -1)
            return .handled
        case .rightArrow:
            moveSelectionHorizontal(by: 1)
            return .handled
        case .return:
            // Activate selected app, then clear selection so repeat Enter
            // doesn't re-trigger the same icon (window now persists after activation)
            if let index = selectedAppIndex, index < filteredApps.count {
                activateApp(filteredApps[index])
                selectedAppIndex = nil
                return .handled
            } else if let first = filteredApps.first {
                activateApp(first)
                return .handled
            }
            return .ignored
        default:
            // Letter keys auto-show search and start typing
            if let char = keyPress.characters.first, char.isLetter || char.isNumber {
                showSearchAndFocus()
                // The character will be typed into the now-focused search field
                return .ignored // Let the character through to TextField
            }
            return .ignored
        }
    }

    func showSearchAndFocus() {
        withAnimation(.easeInOut(duration: 0.12)) {
            isSearchVisible = true
        }
        // Delay focus slightly to ensure field is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isSearchFieldFocused = true
        }
    }

    func moveSelection(by delta: Int) {
        guard !filteredApps.isEmpty else { return }

        if let current = selectedAppIndex {
            let newIndex = current + delta
            if newIndex >= 0, newIndex < filteredApps.count {
                selectedAppIndex = newIndex
            }
        } else {
            // No selection - start from first or last
            selectedAppIndex = delta > 0 ? 0 : filteredApps.count - 1
        }
    }

    func moveSelectionHorizontal(by delta: Int) {
        // For now, treat left/right same as up/down (linear navigation)
        // Could be enhanced later with grid-aware navigation using column count
        moveSelection(by: delta)
    }
}
