import SwiftUI
import AppKit

// MARK: - Tile

struct MenuBarAppTile: View {
    let app: RunningApp
    let iconSize: CGFloat
    let tileSize: CGFloat
    let onActivate: () -> Void
    let onSetHotkey: () -> Void
    var onRemoveFromGroup: (() -> Void)?

    /// Whether this icon is currently in the hidden section
    var isHidden: Bool = false
    /// Callback when user wants to toggle hidden status (shows instructions)
    var onToggleHidden: (() -> Void)?

    /// Whether to show app name below icon (for users with many apps)
    var showName: Bool = true

    /// Whether this tile is selected via keyboard navigation
    var isSelected: Bool = false

    var body: some View {
        Button(action: onActivate) {
            VStack(spacing: 4) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: max(8, iconSize * 0.18))
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))

                    Group {
                        if let icon = app.iconThumbnail ?? app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .renderingMode(icon.isTemplate ? .template : .original)
                                .foregroundStyle(icon.isTemplate ? .secondary : .primary)
                        } else {
                            Image(systemName: "app.fill")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                }
                .frame(width: iconSize, height: iconSize)

                // App name below icon
                if showName {
                    Text(app.name)
                        .font(.system(size: max(9, iconSize * 0.18)))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: tileSize - 4)
                }
            }
            .frame(width: tileSize, height: showName ? tileSize + 16 : tileSize)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .draggable(app.bundleId)  // Enable drag with bundle ID as payload
        .help(app.name)
        .contextMenu {
            Button("Open") {
                onActivate()
            }
            Button("Set Hotkey…") {
                onSetHotkey()
            }
            if let toggleAction = onToggleHidden {
                Divider()
                Button(isHidden ? "Move to Visible" : "Move to Hidden") {
                    toggleAction()
                }
            }
            if let removeAction = onRemoveFromGroup {
                Divider()
                Button("Remove from Group", role: .destructive) {
                    removeAction()
                }
            }
        }
        .accessibilityLabel(Text(app.name))
    }
}
