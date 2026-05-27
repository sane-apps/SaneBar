import AppKit
import SaneUI
import SwiftUI

/// Compact icon tile: icon only, tooltip on hover, context menu for zone moves.
struct PanelIconTile: View {
    let app: RunningApp
    let zone: IconZone
    let colorScheme: ColorScheme
    var isPro: Bool = true
    var duplicateMarker: BrowseDuplicateMarker?
    var onInteraction: (() -> Void)?
    let onActivate: (Bool) -> Void
    var onMoveToVisible: (() -> Void)?
    var onMoveToHidden: (() -> Void)?
    var onMoveToAlwaysHidden: (() -> Void)?
    @State private var isHovering = false

    /// Icon frame is oversized to compensate for transparent padding baked into menu-bar NSImages.
    private let tileSize: CGFloat = 32
    private var iconSize: CGFloat {
        let icon = app.icon
        return icon?.isTemplate == true ? tileSize * 0.65 : tileSize * 1.15
    }

    var body: some View {
        Button {
            onInteraction?()
            onActivate(false)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(tileBackground)

                iconImage
                    .frame(width: iconSize, height: iconSize)
            }
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(1)
        .overlay(alignment: .topTrailing) {
            if let duplicateMarker {
                BrowseDuplicateBadge(marker: duplicateMarker, compact: true)
                    .padding(.top, 1)
                    .padding(.trailing, 1)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isPro {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(SaneBarChrome.accentHighlight)
                    .padding(2)
                    .background(Circle().fill(.ultraThinMaterial))
                    .offset(x: 2, y: 2)
            }
        }
        .onHover {
            isHovering = $0
            if $0 {
                onInteraction?()
            }
        }
        .help(helpText)
        .contextMenu { contextMenuItems }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var duplicateBaseName: String {
        if let duplicateMarker {
            return duplicateMarker.helpLabel(baseName: app.name)
        }
        return app.name
    }

    private var helpText: String {
        duplicateBaseName
    }

    private var accessibilityLabel: String {
        duplicateBaseName
    }

    private var tileBackground: some ShapeStyle {
        if isHovering {
            return AnyShapeStyle(SaneBarChrome.activeControlFill)
        }
        if colorScheme == .dark {
            return AnyShapeStyle(SaneBarChrome.utilityFill)
        }
        return AnyShapeStyle(Color.white.opacity(0.8))
    }

    @ViewBuilder
    private var iconImage: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(icon.isTemplate ? .template : .original)
                .foregroundStyle(.white.opacity(icon.isTemplate ? 0.95 : 1.0))
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.white.opacity(0.9))
                .aspectRatio(contentMode: .fit)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Left-Click (Open)") {
            onInteraction?()
            onActivate(false)
        }
        Button("Right-Click") {
            onInteraction?()
            onActivate(true)
        }

        Divider()

        Button("Copy Icon ID") {
            onInteraction?()
            copyIconID(app.uniqueId)
        }

        Divider()

        switch zone {
        case .hidden:
            SwiftUI.Label("Currently: Hidden", systemImage: "eye.slash")
                .disabled(true)
        case .alwaysHidden:
            SwiftUI.Label("Currently: Always Hidden", systemImage: "lock")
                .disabled(true)
        case .visible:
            SwiftUI.Label("Currently: Visible", systemImage: "eye")
                .disabled(true)
        }

        Divider()

        if let moveToVisible = onMoveToVisible {
            Button {
                onInteraction?()
                moveToVisible()
            } label: {
                SwiftUI.Label("Move to Visible", systemImage: "eye")
            }
        }

        if let moveToHidden = onMoveToHidden {
            Button {
                onInteraction?()
                moveToHidden()
            } label: {
                SwiftUI.Label("Move to Hidden", systemImage: "eye.slash")
            }
        }

        if let moveToAH = onMoveToAlwaysHidden {
            Button {
                onInteraction?()
                moveToAH()
            } label: {
                SwiftUI.Label("Move to Always Hidden", systemImage: "lock")
            }
        }
    }

    private func copyIconID(_ iconID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(iconID, forType: .string)
    }
}
