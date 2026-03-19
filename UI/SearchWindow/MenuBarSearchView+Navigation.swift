import AppKit
import SwiftUI

// MARK: - Zone Classification, Action Factories & Keyboard Navigation

extension MenuBarSearchView {
    // MARK: - Zone Classification (for All tab context menus)

    enum AppZone { case visible, hidden, alwaysHidden }

    static func separatorBoundaryForAllTabClassification(
        separatorRightEdgeX: CGFloat?,
        separatorOriginX: CGFloat?
    ) -> CGFloat? {
        if let separatorRightEdgeX, separatorRightEdgeX > 0 {
            return separatorRightEdgeX
        }
        if let separatorOriginX, separatorOriginX > 0 {
            return separatorOriginX
        }
        return nil
    }

    static func classifyAllTabZone(
        midX: CGFloat,
        separatorBoundaryX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?,
        margin: CGFloat = 6
    ) -> AppZone {
        guard let separatorBoundaryX else { return .visible }

        if let alwaysHiddenSeparatorX,
           alwaysHiddenSeparatorX > 0,
           alwaysHiddenSeparatorX < separatorBoundaryX,
           midX < (alwaysHiddenSeparatorX - margin) {
            return .alwaysHidden
        }

        return midX < (separatorBoundaryX - margin) ? .hidden : .visible
    }

    /// Classify an app's current zone based on its X position vs separator positions.
    func appZone(for app: RunningApp) -> AppZone {
        guard let xPos = app.xPosition else { return .visible }
        let midX = xPos + ((app.width ?? 22) / 2)
        let separatorBoundaryX = Self.separatorBoundaryForAllTabClassification(
            separatorRightEdgeX: menuBarManager.getSeparatorRightEdgeX(),
            separatorOriginX: menuBarManager.getSeparatorOriginX()
        )

        return Self.classifyAllTabZone(
            midX: midX,
            separatorBoundaryX: separatorBoundaryX,
            alwaysHiddenSeparatorX: menuBarManager.getAlwaysHiddenSeparatorOriginX()
        )
    }

    // MARK: - Action Factories

    func makeToggleHiddenAction(for app: RunningApp) -> (() -> Void)? {
        // Determine direction based on tab (or actual zone for All tab)
        let sourceZone: AppZone
        let targetZone: AppZone
        switch mode {
        case .visible:
            sourceZone = .visible
            targetZone = .hidden
        case .hidden:
            sourceZone = .hidden
            targetZone = .visible
        case .alwaysHidden:
            sourceZone = .alwaysHidden
            targetZone = .visible
        case .all:
            let zone = appZone(for: app)
            switch zone {
            case .visible:
                sourceZone = .visible
                targetZone = .hidden
            case .hidden:
                sourceZone = .hidden
                targetZone = .visible
            case .alwaysHidden:
                sourceZone = .alwaysHidden
                targetZone = .visible
            }
        }

        return {
            _ = self.queueMove(app, from: sourceZone, to: targetZone)
        }
    }

    func makeMoveToHiddenAction(for app: RunningApp) -> (() -> Void)? {
        // Show "Move to Hidden" for AH tab, or for AH apps in All tab
        let isAH = mode == .alwaysHidden || (mode == .all && appZone(for: app) == .alwaysHidden)
        guard isAH else { return nil }
        return {
            _ = self.queueMove(app, from: .alwaysHidden, to: .hidden)
        }
    }

    func makeMoveToAlwaysHiddenAction(for app: RunningApp) -> (() -> Void)? {
        guard isAlwaysHiddenEnabled else { return nil }
        // Don't show for AH tab, or for AH apps in All tab
        let isAH = mode == .alwaysHidden || (mode == .all && appZone(for: app) == .alwaysHidden)
        guard !isAH else { return nil }
        return {
            _ = self.queueMove(app, from: self.appZone(for: app), to: .alwaysHidden)
        }
    }

    private func rollbackAlwaysHiddenMutation(for app: RunningApp, from sourceZone: AppZone, to targetZone: AppZone) {
        switch (sourceZone, targetZone) {
        case (.alwaysHidden, .visible), (.alwaysHidden, .hidden):
            menuBarManager.pinAlwaysHidden(app: app)
        case (.hidden, .alwaysHidden), (.visible, .alwaysHidden):
            menuBarManager.unpinAlwaysHidden(app: app)
        default:
            break
        }
    }

    private func observeQueuedMoveResult(
        _ task: Task<Bool, Never>,
        app: RunningApp,
        sourceZone: AppZone,
        targetZone: AppZone
    ) {
        Task { @MainActor in
            let moved = await task.value
            if !moved {
                rollbackAlwaysHiddenMutation(for: app, from: sourceZone, to: targetZone)
                movingAppId = nil
            }
        }
    }

    private func observeQueuedReorderResult(_ task: Task<Bool, Never>) {
        Task { @MainActor in
            let moved = await task.value
            if !moved {
                movingAppId = nil
            }
        }
    }

    private func queueMove(_ app: RunningApp, from sourceZone: AppZone, to targetZone: AppZone) -> Bool {
        let bundleID = app.bundleId
        let menuExtraID = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex

        let started: Bool
        switch targetZone {
        case .visible:
            guard sourceZone != .visible else { return false }
            if sourceZone == .alwaysHidden {
                menuBarManager.unpinAlwaysHidden(app: app)
                started = menuBarManager.moveIconFromAlwaysHidden(
                    bundleID: bundleID,
                    menuExtraId: menuExtraID,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: app.preferredCenterX
                )
            } else {
                started = menuBarManager.moveIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraID,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: app.preferredCenterX,
                    toHidden: false
                )
            }

        case .hidden:
            guard sourceZone != .hidden else { return false }
            if sourceZone == .alwaysHidden {
                menuBarManager.unpinAlwaysHidden(app: app)
                started = menuBarManager.moveIconFromAlwaysHiddenToHidden(
                    bundleID: bundleID,
                    menuExtraId: menuExtraID,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: app.preferredCenterX
                )
            } else {
                started = menuBarManager.moveIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraID,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: app.preferredCenterX,
                    toHidden: true
                )
            }

        case .alwaysHidden:
            guard isAlwaysHiddenEnabled else { return false }
            guard sourceZone != .alwaysHidden else { return false }
            menuBarManager.pinAlwaysHidden(app: app)
            started = menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraID,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX
            )
        }

        guard started, let task = menuBarManager.activeMoveTask else {
            rollbackAlwaysHiddenMutation(for: app, from: sourceZone, to: targetZone)
            return false
        }

        movingAppId = app.uniqueId
        observeQueuedMoveResult(task, app: app, sourceZone: sourceZone, targetZone: targetZone)
        return true
    }

    private func queueReorder(_ sourceApp: RunningApp, targetApp: RunningApp) -> Bool {
        let sourceX = sourceApp.xPosition ?? 0
        let targetX = targetApp.xPosition ?? 0
        let placeAfterTarget = sourceX < targetX

        let started = menuBarManager.reorderIcon(
            sourceBundleID: sourceApp.bundleId,
            sourceMenuExtraID: sourceApp.menuExtraIdentifier,
            sourceStatusItemIndex: sourceApp.statusItemIndex,
            targetBundleID: targetApp.bundleId,
            targetMenuExtraID: targetApp.menuExtraIdentifier,
            targetStatusItemIndex: targetApp.statusItemIndex,
            placeAfterTarget: placeAfterTarget
        )

        guard started, let task = menuBarManager.activeMoveTask else {
            return false
        }

        movingAppId = sourceApp.uniqueId
        observeQueuedReorderResult(task)
        return true
    }

    @MainActor
    func activateApp(_ app: RunningApp, isRightClick: Bool = false) {
        SearchWindowController.shared.noteBrowseActivationStarted()
        Task { @MainActor in
            defer { SearchWindowController.shared.noteBrowseActivationFinished() }
            await service.activate(app: app, isRightClick: isRightClick, origin: .browsePanel)
        }
    }

    func handleGridReorderDrop(_ payloads: [String], targetApp: RunningApp) -> Bool {
        guard LicenseService.shared.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first else { return false }
        guard sourceID != targetApp.uniqueId else { return false }
        guard let sourceApp = filteredApps.first(where: { $0.uniqueId == sourceID }) else { return false }

        return queueReorder(sourceApp, targetApp: targetApp)
    }

    func handleZoneDrop(_ payloads: [String], targetMode: Mode) -> Bool {
        guard LicenseService.shared.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first else { return false }

        // Pull from the shared cache so zone drops work regardless of current tab.
        let classified = service.cachedClassifiedApps()
        guard let source = Self.sourceForDropPayload(
            sourceID,
            classified: classified,
            filteredApps: filteredApps,
            mode: mode,
            zoneForAllMode: { app in self.appZone(for: app) }
        ) else {
            return false
        }

        let sourceApp = source.app
        let sourceZone = source.zone

        switch targetMode {
        case .visible:
            return queueMove(sourceApp, from: sourceZone, to: .visible)
        case .hidden:
            return queueMove(sourceApp, from: sourceZone, to: .hidden)
        case .alwaysHidden:
            return queueMove(sourceApp, from: sourceZone, to: .alwaysHidden)
        case .all:
            return false
        }
    }

    static func sourceForDropPayload(
        _ sourceID: String,
        classified: SearchClassifiedApps,
        filteredApps: [RunningApp] = [],
        mode: Mode? = nil,
        zoneForAllMode: ((RunningApp) -> AppZone)? = nil
    ) -> (app: RunningApp, zone: AppZone)? {
        if let app = classified.visible.first(where: { $0.uniqueId == sourceID }) {
            return (app, .visible)
        }
        if let app = classified.hidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .hidden)
        }
        if let app = classified.alwaysHidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .alwaysHidden)
        }
        guard let app = filteredApps.first(where: { $0.uniqueId == sourceID }),
              let mode else {
            return nil
        }

        switch mode {
        case .visible:
            return (app, .visible)
        case .hidden:
            return (app, .hidden)
        case .alwaysHidden:
            return (app, .alwaysHidden)
        case .all:
            if let zone = zoneForAllMode?(app) {
                return (app, zone)
            }
            return (app, .visible)
        }
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
