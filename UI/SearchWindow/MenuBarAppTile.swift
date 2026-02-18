import AppKit
import SwiftUI

// MARK: - Tile

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
        })
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if !isPro {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.teal)
                    .padding(3)
                    .background(Circle().fill(.ultraThinMaterial))
                    .offset(x: 3, y: 3)
            }
        }
        .draggable(app.uniqueId) // Unique payload avoids collisions for multi-item bundles
        .help(isPro ? app.name : "\(app.name) — Pro required to activate")
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
        .accessibilityLabel(Text(app.name))
    }

    @ViewBuilder
    private var tileIcon: some View {
        if let icon = app.iconThumbnail ?? app.icon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(icon.isTemplate ? .template : .original)
                .foregroundStyle(.primary.opacity(icon.isTemplate ? 0.6 : 1.0))
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize * 0.7, height: iconSize * 0.7)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.primary.opacity(0.6))
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize * 0.7, height: iconSize * 0.7)
        }
    }
}
