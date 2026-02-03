import SwiftUI

struct MenuBarAppGrid: View {
    let apps: [RunningApp]
    let mode: String
    let selectedGroupId: UUID?
    let onActivate: (RunningApp, Bool) -> Void
    let onSetHotkey: (RunningApp) -> Void
    let onRemoveFromGroup: (String, UUID) -> Void
    let onMoveIcon: (String, String?, Bool) -> Void
    let onRefresh: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 8
            let availableWidth = max(0, proxy.size.width - (padding * 2))
            let availableHeight = max(0, proxy.size.height - (padding * 2))
            let grid = gridSizing(availableWidth: availableWidth, availableHeight: availableHeight, count: apps.count)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(grid.tileSize), spacing: grid.spacing), count: grid.columns),
                    alignment: .leading,
                    spacing: grid.spacing
                ) {
                    ForEach(apps) { app in
                        MenuBarAppTile(
                            app: app,
                            iconSize: grid.iconSize,
                            tileSize: grid.tileSize,
                            onActivate: { isRightClick in onActivate(app, isRightClick) },
                            onSetHotkey: { onSetHotkey(app) },
                            onRemoveFromGroup: selectedGroupId.map { groupId in
                                { onRemoveFromGroup(app.bundleId, groupId) }
                            },
                            isHidden: mode == "hidden",
                            onToggleHidden: mode == "all" ? nil : {
                                onMoveIcon(app.bundleId, app.menuExtraIdentifier, mode == "visible")
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private struct GridSizing {
        let columns: Int
        let tileSize: CGFloat
        let iconSize: CGFloat
        let spacing: CGFloat
    }

    private func gridSizing(availableWidth: CGFloat, availableHeight: CGFloat, count: Int) -> GridSizing {
        let spacing: CGFloat = 8
        let minTile: CGFloat = 44
        let maxTile: CGFloat = 112

        guard count > 0 else {
            return GridSizing(columns: 1, tileSize: 84, iconSize: 52, spacing: spacing)
        }

        let maxColumnsByWidth = max(1, Int((availableWidth + spacing) / (minTile + spacing)))
        let maxColumns = min(maxColumnsByWidth, count)
        let height = max(1, availableHeight)

        var best = GridSizing(columns: 1, tileSize: minTile, iconSize: 26, spacing: spacing)
        var bestScore: CGFloat = -1_000_000

        for columns in 1...maxColumns {
            let rawTile = (availableWidth - (CGFloat(columns - 1) * spacing)) / CGFloat(columns)
            let tileSize = max(minTile, min(maxTile, floor(rawTile)))

            let rows = Int(ceil(Double(count) / Double(columns)))
            let contentHeight = (CGFloat(rows) * tileSize) + (CGFloat(max(0, rows - 1)) * spacing)
            let overflow = max(0, contentHeight - height)

            let score: CGFloat
            if overflow <= 0 {
                score = 10_000 + tileSize - (CGFloat(rows) * 4) + (CGFloat(columns) * 0.5)
            } else {
                score = tileSize - ((overflow / height) * 24)
            }

            if score > bestScore {
                bestScore = score
                best = GridSizing(
                    columns: columns,
                    tileSize: tileSize,
                    iconSize: max(28, min(72, floor(tileSize * 0.72))),
                    spacing: spacing
                )
            }
        }
        return best
    }
}
