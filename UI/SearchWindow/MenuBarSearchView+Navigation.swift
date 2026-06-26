import AppKit
import SwiftUI

// MARK: - Zone Classification, Action Factories & Keyboard Navigation

extension MenuBarSearchView {
    // MARK: - Zone Classification (for All tab context menus)

    /// Classify an app's current zone based on its X position vs separator positions.
    func appZone(for app: RunningApp) -> AppZone {
        let pinnedIds = Set(menuBarManager.settings.alwaysHiddenPinnedItemIds)
        if pinnedIds.contains(app.uniqueId) || pinnedIds.contains(app.bundleId) {
            return .alwaysHidden
        }

        guard let xPos = app.xPosition else { return .visible }
        let midX = xPos + ((app.width ?? 22) / 2)
        let separatorBoundaryX = BrowsePanelZoneClassifier.separatorBoundaryForAllTab(
            separatorRightEdgeX: menuBarManager.geometryResolver.separatorRightEdgeX(),
            separatorOriginX: menuBarManager.geometryResolver.separatorOriginX()
        )
        let alwaysHiddenBoundaryX = BrowsePanelZoneClassifier.alwaysHiddenBoundaryForAllTab(
            separatorBoundaryX: separatorBoundaryX,
            alwaysHiddenBoundaryX: menuBarManager.geometryResolver.alwaysHiddenSeparatorBoundaryX(),
            alwaysHiddenOriginX: menuBarManager.geometryResolver.alwaysHiddenSeparatorOriginX()
        )

        return BrowsePanelZoneClassifier.classifyAllTabZone(
            midX: midX,
            separatorBoundaryX: separatorBoundaryX,
            alwaysHiddenSeparatorX: alwaysHiddenBoundaryX
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
            // Use the async (AfterDrop) path so the move never runs the
            // synchronous prepare (nested RunLoop.current.run) on the main
            // thread. Context-menu/keyboard moves used to beachball for
            // seconds during Always-Hidden separator prep; drag-drop already
            // routed here. (Bug A: menu-bar move beachball.)
            _ = self.queueMoveAfterDrop(app, from: sourceZone, to: targetZone)
        }
    }

    func makeMoveToHiddenAction(for app: RunningApp) -> (() -> Void)? {
        // Show "Move to Hidden" for AH tab, or for AH apps in All tab
        let isAH = mode == .alwaysHidden || (mode == .all && appZone(for: app) == .alwaysHidden)
        guard isAH else { return nil }
        return {
            _ = self.queueMoveAfterDrop(app, from: .alwaysHidden, to: .hidden)
        }
    }

    func makeMoveToAlwaysHiddenAction(for app: RunningApp) -> (() -> Void)? {
        guard isAlwaysHiddenEnabled else { return nil }
        // Don't show for AH tab, or for AH apps in All tab
        let isAH = mode == .alwaysHidden || (mode == .all && appZone(for: app) == .alwaysHidden)
        guard !isAH else { return nil }
        return {
            _ = self.queueMoveAfterDrop(app, from: self.appZone(for: app), to: .alwaysHidden)
        }
    }

    private func queueMove(_ app: RunningApp, from sourceZone: AppZone, to targetZone: AppZone) -> Bool {
        BrowsePanelMoveQueue.queueMove(
            app: app,
            from: sourceZone,
            to: targetZone,
            context: moveContext
        )
    }

    private func queueMoveAfterDrop(_ app: RunningApp, from sourceZone: AppZone, to targetZone: AppZone) -> Bool {
        BrowsePanelMoveQueue.queueMoveAfterDrop(
            app: app,
            from: sourceZone,
            to: targetZone,
            context: moveContext
        )
    }

    private func queueReorder(_ sourceApp: RunningApp, targetApp: RunningApp) -> Bool {
        BrowsePanelMoveQueue.queueReorder(
            sourceApp: sourceApp,
            targetApp: targetApp,
            context: moveContext
        )
    }

    private func queueReorderAfterDrop(_ sourceApp: RunningApp, targetApp: RunningApp) -> Bool {
        BrowsePanelMoveQueue.queueReorderAfterDrop(
            sourceApp: sourceApp,
            targetApp: targetApp,
            context: moveContext
        )
    }

    private var moveContext: BrowsePanelMoveContext {
        BrowsePanelMoveContext(
            isAlwaysHiddenEnabled: isAlwaysHiddenEnabled,
            manager: menuBarManager,
            setMovingAppID: {
                movingAppId = $0
                // A fresh in-flight move clears any stale failure marker so a
                // retry doesn't keep showing the previous failure affordance.
                if $0 != nil { lastFailedMoveAppId = nil }
            },
            recordFailedMove: { lastFailedMoveAppId = $0 }
        )
    }

    @MainActor
    func activateApp(_ app: RunningApp, isRightClick: Bool = false) {
        Task { @MainActor in
            await service.activate(app: app, isRightClick: isRightClick, origin: .browsePanel)
        }
    }

    func handleGridReorderDrop(_ payloads: [String], targetApp: RunningApp) -> Bool {
        if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: LicenseService.shared.isPro) {
            proUpsellFeature = feature
            return false
        }

        guard let sourceID = payloads.first else { return false }
        guard sourceID != targetApp.uniqueId else { return false }
        guard let sourceApp = filteredApps.first(where: { $0.uniqueId == sourceID }) else { return false }

        return queueReorderAfterDrop(sourceApp, targetApp: targetApp)
    }

    func handleZoneDrop(_ payloads: [String], targetMode: Mode) -> Bool {
        guard LicenseService.shared.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first else { return false }

        // Pull from the shared cache so zone drops work regardless of current tab.
        let classified = service.cachedClassifiedApps()
        guard let source = BrowsePanelDropResolver.sourceForDropPayload(
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
            return queueMoveAfterDrop(sourceApp, from: sourceZone, to: .visible)
        case .hidden:
            return queueMoveAfterDrop(sourceApp, from: sourceZone, to: .hidden)
        case .alwaysHidden:
            return queueMoveAfterDrop(sourceApp, from: sourceZone, to: .alwaysHidden)
        case .all:
            return false
        }
    }

    // MARK: - Keyboard Navigation

    /// Whether keyboard navigation should be active (not when modals are open)
    var isKeyboardNavigationActive: Bool {
        hotkeyApp == nil && proUpsellFeature == nil
    }

    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard isKeyboardNavigationActive else {
            return .ignored
        }

        return BrowsePanelKeyboardNavigation.handleKeyPress(
            keyPress,
            context: BrowsePanelKeyboardNavigationContext(
                isSearchFieldFocused: isSearchFieldFocused,
                setSearchFieldFocused: { isSearchFieldFocused = $0 },
                selectedAppIndex: selectedAppIndex,
                setSelectedAppIndex: { selectedAppIndex = $0 },
                filteredApps: filteredApps,
                activate: { activateApp($0) },
                showSearchAndFocus: showSearchAndFocus
            )
        )
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
}
