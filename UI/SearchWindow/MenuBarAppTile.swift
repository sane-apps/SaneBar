import AppKit
import SwiftUI

// MARK: - Tile

struct BrowseDuplicateMarker: Equatable {
    let ordinal: Int
    let total: Int

    func helpLabel(baseName: String) -> String {
        "\(baseName) \(ordinal) of \(total)"
    }

    static func markers(for apps: [RunningApp]) -> [String: BrowseDuplicateMarker] {
        var grouped = [String: [RunningApp]]()
        for app in apps {
            grouped[groupKey(for: app), default: []].append(app)
        }

        var markers = [String: BrowseDuplicateMarker]()
        for apps in grouped.values {
            guard apps.count > 1 else { continue }
            let ordered = apps.sorted { lhs, rhs in
                let leftX = lhs.xPosition ?? .greatestFiniteMagnitude
                let rightX = rhs.xPosition ?? .greatestFiniteMagnitude
                if leftX != rightX {
                    return leftX < rightX
                }
                return lhs.uniqueId < rhs.uniqueId
            }

            for (index, app) in ordered.enumerated() {
                markers[app.uniqueId] = BrowseDuplicateMarker(
                    ordinal: index + 1,
                    total: ordered.count
                )
            }
        }
        return markers
    }

    private static func groupKey(for app: RunningApp) -> String {
        let normalizedName = app.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(app.bundleId)\n\(normalizedName)"
    }
}

struct BrowseDuplicateBadge: View {
    let marker: BrowseDuplicateMarker
    var compact: Bool = false

    var body: some View {
        Text("\(marker.ordinal)")
            .font(.system(size: compact ? 8 : 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, compact ? 1.5 : 2.5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.58))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

struct MenuBarAppTile: View {
    let app: RunningApp
    let iconSize: CGFloat
    let tileSize: CGFloat
    let onActivate: (Bool) -> Void
    let onSetHotkey: () -> Void
    var onRemoveFromGroup: (() -> Void)?

    /// Whether this icon is currently in the hidden section
    var isHidden: Bool = false
    /// Callback when user wants to toggle hidden status (shows instructions)
    var onToggleHidden: (() -> Void)?

    /// Callback when user wants to move an icon into the always-hidden zone
    var onMoveToAlwaysHidden: (() -> Void)?

    /// Callback when user wants to move an icon from always-hidden to the regular hidden zone
    var onMoveToHidden: (() -> Void)?

    /// Whether to show app name below icon (for users with many apps)
    var showName: Bool = true

    /// Whether a move operation is in progress for this tile
    var isMoving: Bool = false

    /// Whether this tile is selected via keyboard navigation
    var isSelected: Bool = false

    /// Whether the user has Pro license (affects action gating and badges)
    var isPro: Bool = true

    /// Optional disambiguator for apps that expose multiple menu extras
    var duplicateMarker: BrowseDuplicateMarker?

    var body: some View {
        Button(action: { onActivate(false) }, label: {
            VStack(spacing: 4) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: max(8, iconSize * 0.18))
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))

                    tileIcon
                        .opacity(isMoving ? 0.4 : 1.0)

                    if isMoving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: iconSize, height: iconSize)

                // App name below icon
                if showName {
                    Text(app.name)
                        .font(.system(size: max(9, iconSize * 0.18)))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: tileSize - 4)
                }
            }
            .frame(width: tileSize, height: showName ? tileSize + 16 : tileSize)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.11, green: 0.32, blue: 0.50).opacity(0.16),
                                        Color(red: 0.11, green: 0.23, blue: 0.39).opacity(0.11)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.28) : Color.clear, lineWidth: 1.5)
            )
        })
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let duplicateMarker {
                BrowseDuplicateBadge(marker: duplicateMarker)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isPro {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.11, green: 0.32, blue: 0.50),
                                Color(red: 0.11, green: 0.23, blue: 0.39)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(3)
                    .background(Circle().fill(.ultraThinMaterial))
                    .offset(x: 3, y: 3)
            }
        }
        .draggable(app.uniqueId) // Unique payload avoids collisions for multi-item bundles
        .help(helpText)
        .contextMenu {
            Button("Left-Click (Open)") {
                onActivate(false)
            }
            Button("Right-Click") {
                onActivate(true)
            }
            Divider()
            Button("Set Hotkey…") {
                onSetHotkey()
            }
            Divider()
            Button("Copy Icon ID") {
                copyIconID(app.uniqueId)
            }
            if let toggleAction = onToggleHidden {
                Divider()
                Button(isHidden ? "Move to Visible" : "Move to Hidden") {
                    toggleAction()
                }
            }
            if let moveToHidden = onMoveToHidden {
                Divider()
                Button("Move to Hidden") {
                    moveToHidden()
                }
            }
            if let moveToAlwaysHidden = onMoveToAlwaysHidden {
                Divider()
                Button("Move to Always Hidden") {
                    moveToAlwaysHidden()
                }
            }
            if let removeAction = onRemoveFromGroup {
                Divider()
                Button("Remove from Group", role: .destructive) {
                    removeAction()
                }
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var duplicateBaseName: String {
        if let duplicateMarker {
            return duplicateMarker.helpLabel(baseName: app.name)
        }
        return app.name
    }

    private var helpText: String {
        isPro ? duplicateBaseName : "\(duplicateBaseName) — Pro unlocks right-click and move actions"
    }

    private var accessibilityLabel: String {
        duplicateBaseName
    }

    @ViewBuilder
    private var tileIcon: some View {
        if let icon = app.iconThumbnail ?? app.icon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(icon.isTemplate ? .template : .original)
                .foregroundStyle(.white.opacity(icon.isTemplate ? 0.6 : 1.0))
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize * 0.7, height: iconSize * 0.7)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.9))
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize * 0.7, height: iconSize * 0.7)
        }
    }

    private func copyIconID(_ iconID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(iconID, forType: .string)
    }
}
