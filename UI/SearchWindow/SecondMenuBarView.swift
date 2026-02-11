import AppKit
import SwiftUI

// MARK: - Second Menu Bar View

/// Horizontal strip showing all menu bar icons organized by zone.
///
/// Visible → Hidden → Always Hidden, separated by thin vertical dividers.
/// Right-click any icon to move it between zones.
struct SecondMenuBarView: View {
    let visibleApps: [RunningApp]
    let apps: [RunningApp]
    let alwaysHiddenApps: [RunningApp]
    let hasAccessibility: Bool
    let isRefreshing: Bool
    let onDismiss: () -> Void
    let onActivate: (RunningApp, Bool) -> Void
    let onRetry: () -> Void
    var onIconMoved: (() -> Void)?

    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @Environment(\.colorScheme) private var colorScheme

    // Filter out system items that can't be moved (Clock, Control Center)
    private var movableVisible: [RunningApp] { visibleApps.filter { !$0.isUnmovableSystemItem } }
    private var movableHidden: [RunningApp] { apps.filter { !$0.isUnmovableSystemItem } }
    private var movableAlwaysHidden: [RunningApp] { alwaysHiddenApps.filter { !$0.isUnmovableSystemItem } }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            panelDivider
            if !hasAccessibility {
                accessibilityPrompt
            } else if movableVisible.isEmpty, movableHidden.isEmpty, movableAlwaysHidden.isEmpty {
                emptyState
            } else {
                iconStrip
            }
        }
        .frame(minWidth: 220)
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.teal.opacity(0.15),
                    lineWidth: 1
                )
        )
        .onExitCommand { onDismiss() }
    }

    // MARK: - Background

    private var panelBackground: some View {
        SaneGradientBackground()
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))

            Text("Second Menu Bar")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            let total = movableVisible.count + movableHidden.count + movableAlwaysHidden.count
            if total > 0 {
                Text("\(total)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.5)))
            }

            Spacer()

            Button {
                SettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.teal.opacity(0.12))
            .frame(height: 1)
    }

    // MARK: - Horizontal Icon Strip

    private var iconStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !movableVisible.isEmpty {
                zoneRow(label: "Visible", icon: "eye", apps: movableVisible, zone: .visible)
            }

            if !movableVisible.isEmpty, !movableHidden.isEmpty || !movableAlwaysHidden.isEmpty {
                zoneDivider
            }

            if !movableHidden.isEmpty {
                zoneRow(label: "Hidden", icon: "eye.slash", apps: movableHidden, zone: .hidden)
            }

            if !movableHidden.isEmpty, !movableAlwaysHidden.isEmpty {
                zoneDivider
            }

            if !movableAlwaysHidden.isEmpty {
                zoneRow(label: "Always Hidden", icon: "lock", apps: movableAlwaysHidden, zone: .alwaysHidden)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func zoneRow(label: String, icon: String, apps: [RunningApp], zone: IconZone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(apps.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(apps) { app in
                        makeTile(for: app, zone: zone)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var zoneDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.teal.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
    }

    // MARK: - Tile Factory

    private func makeTile(for app: RunningApp, zone: IconZone) -> PanelIconTile {
        PanelIconTile(
            app: app,
            zone: zone,
            colorScheme: colorScheme,
            onActivate: { isRightClick in onActivate(app, isRightClick) },
            onMoveToVisible: zone != .visible ? { moveIcon(app, from: zone, to: .visible) } : nil,
            onMoveToHidden: zone != .hidden ? { moveIcon(app, from: zone, to: .hidden) } : nil,
            onMoveToAlwaysHidden: zone != .alwaysHidden ? { moveIcon(app, from: zone, to: .alwaysHidden) } : nil
        )
    }

    // MARK: - Icon Movement

    private func moveIcon(_ app: RunningApp, from source: IconZone, to target: IconZone) {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex

        switch (source, target) {
        case (_, .visible):
            if source == .alwaysHidden { menuBarManager.unpinAlwaysHidden(app: app) }
            _ = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex, toHidden: false
            )

        case (.visible, .hidden):
            _ = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex, toHidden: true
            )

        case (.alwaysHidden, .hidden):
            menuBarManager.unpinAlwaysHidden(app: app)
            _ = menuBarManager.moveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )

        case (_, .alwaysHidden):
            menuBarManager.pinAlwaysHidden(app: app)
            _ = menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )

        default:
            break
        }

        // Refresh the panel data after the move takes effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onIconMoved?()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning menu bar...")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.7))
            } else {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.primary.opacity(0.3))
                Text("No menu bar icons found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                Text("Hold \u{2318} and drag icons past the separator")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    // MARK: - Accessibility Prompt

    private var accessibilityPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Needed")
                    .font(.system(size: 13, weight: .medium))
                Text("Required to detect menu bar icons")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.8))
            }

            Spacer()

            Button("Grant Access") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)

            Button { onRetry() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(14)
    }
}

// MARK: - Icon Zone

enum IconZone {
    case visible, hidden, alwaysHidden
}

// MARK: - Panel Icon Tile

/// Individual icon tile with hover effects, white icons, and zone management.
private struct PanelIconTile: View {
    let app: RunningApp
    let zone: IconZone
    let colorScheme: ColorScheme
    let onActivate: (Bool) -> Void
    var onMoveToVisible: (() -> Void)?
    var onMoveToHidden: (() -> Void)?
    var onMoveToAlwaysHidden: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        Button { onActivate(false) } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Card background — SaneUI glass style
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tileBackground)

                    iconImage
                        .frame(width: 24, height: 24)
                }
                .frame(width: 44, height: 44)

                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(isHovering ? 1.0 : 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 48, maxWidth: 120)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.name)
        .contextMenu { contextMenuItems }
        .accessibilityLabel(Text(app.name))
    }

    private var tileBackground: some ShapeStyle {
        if isHovering {
            return AnyShapeStyle(Color.teal.opacity(0.18))
        }
        return AnyShapeStyle(
            colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.white.opacity(0.8)
        )
    }

    @ViewBuilder
    private var iconImage: some View {
        if let icon = app.iconThumbnail ?? app.icon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(icon.isTemplate ? .template : .original)
                // White icons in dark mode, full color in light — clear contrast
                .foregroundStyle(.primary)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.primary.opacity(0.6))
                .aspectRatio(contentMode: .fit)
        }
    }

    // MARK: - Context Menu (Zone Management)

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Left-Click (Open)") { onActivate(false) }
        Button("Right-Click") { onActivate(true) }

        Divider()

        // Zone labels
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
                moveToVisible()
            } label: {
                SwiftUI.Label("Move to Visible", systemImage: "eye")
            }
        }

        if let moveToHidden = onMoveToHidden {
            Button {
                moveToHidden()
            } label: {
                SwiftUI.Label("Move to Hidden", systemImage: "eye.slash")
            }
        }

        if let moveToAH = onMoveToAlwaysHidden {
            Button {
                moveToAH()
            } label: {
                SwiftUI.Label("Move to Always Hidden", systemImage: "lock")
            }
        }
    }
}
