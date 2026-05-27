import SwiftUI

struct BrowseAppGridView: View {
    let apps: [RunningApp]
    let duplicateMarkers: [String: BrowseDuplicateMarker]
    let selectedGroupId: UUID?
    let selectedAppIndex: Int?
    let movingAppId: String?
    let mode: BrowsePanelMode
    let appZone: (RunningApp) -> BrowseAppZone
    let activateApp: (RunningApp, Bool) -> Void
    let setHotkey: (RunningApp) -> Void
    let removeAppFromGroup: (String, UUID) -> Void
    let makeToggleHiddenAction: (RunningApp) -> (() -> Void)?
    let makeMoveToAlwaysHiddenAction: (RunningApp) -> (() -> Void)?
    let makeMoveToHiddenAction: (RunningApp) -> (() -> Void)?
    let showRestrictedFeature: (ProFeature) -> Void
    let noteDragStarted: (BrowseAppZone) -> Void
    let handleGridDrop: ([String], RunningApp) -> Bool
    let clearDragState: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 8
            let availableWidth = max(0, proxy.size.width - (padding * 2))
            let availableHeight = max(0, proxy.size.height - (padding * 2))
            let grid = SearchGridSizing.compute(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                count: apps.count
            )

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(grid.tileSize), spacing: grid.spacing), count: grid.columns),
                    alignment: .leading,
                    spacing: grid.spacing
                ) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        makeTile(
                            app: app,
                            index: index,
                            grid: grid,
                            duplicateMarker: duplicateMarkers[app.uniqueId]
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func makeTile(
        app: RunningApp,
        index: Int,
        grid: SearchGridSizing,
        duplicateMarker: BrowseDuplicateMarker?
    ) -> some View {
        let isPro = LicenseService.shared.isPro
        MenuBarAppTile(
            app: app,
            iconSize: grid.iconSize,
            tileSize: grid.tileSize,
            onActivate: { isRightClick in
                if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .rightClick, isPro: isPro),
                   isRightClick {
                    showRestrictedFeature(feature)
                    return
                }
                activateApp(app, isRightClick)
            },
            onSetHotkey: {
                if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .perIconHotkey, isPro: isPro) {
                    showRestrictedFeature(feature)
                } else {
                    setHotkey(app)
                }
            },
            onRemoveFromGroup: selectedGroupId.map { groupId in
                { removeAppFromGroup(app.bundleId, groupId) }
            },
            isHidden: mode == .hidden || mode == .alwaysHidden || (mode == .all && appZone(app) != .visible),
            onToggleHidden: isPro ? makeToggleHiddenAction(app) : {
                if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: isPro) {
                    showRestrictedFeature(feature)
                }
            },
            onMoveToAlwaysHidden: isPro ? makeMoveToAlwaysHiddenAction(app) : {
                if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: isPro) {
                    showRestrictedFeature(feature)
                }
            },
            onMoveToHidden: isPro ? makeMoveToHiddenAction(app) : {
                if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: isPro) {
                    showRestrictedFeature(feature)
                }
            },
            isMoving: movingAppId == app.uniqueId,
            isSelected: selectedAppIndex == index,
            isPro: isPro,
            duplicateMarker: duplicateMarker,
            onDragStart: {
                noteDragStarted(appZone(app))
            }
        )
        .dropDestination(for: String.self) { payloads, _ in
            let didHandle = handleGridDrop(payloads, app)
            clearDragState()
            return didHandle
        }
    }
}
