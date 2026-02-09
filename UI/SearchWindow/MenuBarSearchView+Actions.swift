import KeyboardShortcuts
import SwiftUI

// MARK: - Hotkey Sheet

/// Self-contained hotkey assignment sheet, extracted from MenuBarSearchView
/// to keep the main file under the 1000-line lint limit.
struct HotkeyAssignmentSheet: View {
    let app: RunningApp
    let onDone: () -> Void

    @ObservedObject private var menuBarManager = MenuBarManager.shared

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Set hotkey")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(icon.isTemplate ? .template : .original)
                        .foregroundStyle(icon.isTemplate ? .secondary : .primary)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }

                Text(app.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Hotkey:")
                    .foregroundStyle(.secondary)

                KeyboardShortcuts.Recorder(for: IconHotkeysService.shortcutName(for: app.bundleId))
                    .onChange(of: KeyboardShortcuts.getShortcut(for: IconHotkeysService.shortcutName(for: app.bundleId))) { _, newShortcut in
                        if let shortcut = newShortcut {
                            menuBarManager.settings.iconHotkeys[app.bundleId] = KeyboardShortcutData(
                                keyCode: UInt16(shortcut.key?.rawValue ?? 0),
                                modifiers: shortcut.modifiers.rawValue
                            )
                        } else {
                            menuBarManager.settings.iconHotkeys.removeValue(forKey: app.bundleId)
                        }

                        menuBarManager.saveSettings()
                        IconHotkeysService.shared.registerHotkeys(from: menuBarManager.settings)
                    }

                Spacer()
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

// MARK: - Grid Sizing

/// Pure computation for adaptive grid layout, extracted from MenuBarSearchView.
struct SearchGridSizing {
    let columns: Int
    let tileSize: CGFloat
    let iconSize: CGFloat
    let spacing: CGFloat

    static func compute(availableWidth: CGFloat, availableHeight: CGFloat, count: Int) -> SearchGridSizing {
        let spacing: CGFloat = 8

        let minTile: CGFloat = 44
        let maxTile: CGFloat = 112

        guard count > 0 else {
            return SearchGridSizing(columns: 1, tileSize: 84, iconSize: 52, spacing: spacing)
        }

        let maxColumnsByWidth = max(1, Int((availableWidth + spacing) / (minTile + spacing)))
        let maxColumns = min(maxColumnsByWidth, count)

        let height = max(1, availableHeight)

        var best = SearchGridSizing(columns: 1, tileSize: minTile, iconSize: 26, spacing: spacing)
        var bestScore: CGFloat = -1_000_000

        for columns in 1 ... maxColumns {
            let rawTile = (availableWidth - (CGFloat(columns - 1) * spacing)) / CGFloat(columns)
            let tileSize = max(minTile, min(maxTile, floor(rawTile)))

            let rows = Int(ceil(Double(count) / Double(columns)))
            let contentHeight = (CGFloat(rows) * tileSize) + (CGFloat(max(0, rows - 1)) * spacing)
            let overflow = max(0, contentHeight - height)

            let score: CGFloat = if overflow <= 0 {
                // Fits without scrolling: prefer a more horizontal grid (fewer rows)
                // while still keeping tiles reasonably large.
                10000 + tileSize - (CGFloat(rows) * 4) + (CGFloat(columns) * 0.5)
            } else {
                // Prefer less scrolling for very large icon counts.
                tileSize - ((overflow / height) * 24)
            }

            if score > bestScore {
                bestScore = score
                best = SearchGridSizing(
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
