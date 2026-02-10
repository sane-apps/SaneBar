import AppKit
import SwiftUI

// MARK: - Second Menu Bar View

/// Floating panel showing hidden menu bar icons below the menu bar.
///
/// Uses SaneApps brand styling (hudWindow + teal gradient), white icons for
/// contrast, and context menus for moving icons between zones.
struct SecondMenuBarView: View {
    let apps: [RunningApp]
    let alwaysHiddenApps: [RunningApp]
    let hasAccessibility: Bool
    let isRefreshing: Bool
    let onDismiss: () -> Void
    let onActivate: (RunningApp, Bool) -> Void
    let onRetry: () -> Void

    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            panelDivider
            if !hasAccessibility {
                accessibilityPrompt
            } else if apps.isEmpty, alwaysHiddenApps.isEmpty {
                emptyState
            } else {
                iconContent
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

    // MARK: - Background (SaneUI brand)

    private var panelBackground: some View {
        ZStack {
            if colorScheme == .dark {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [
                        Color.teal.opacity(0.08),
                        Color.blue.opacity(0.05),
                        Color.teal.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.98, blue: 0.99),
                        Color(red: 0.92, green: 0.96, blue: 0.98),
                        Color(red: 0.94, green: 0.97, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))

            Text("Hidden Icons")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            let total = apps.count + alwaysHiddenApps.count
            if total > 0 {
                Text("\(total)")
                    .font(.system(size: 13, weight: .bold))
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

    // MARK: - Icon Content

    private var iconContent: some View {
        VStack(spacing: 0) {
            if !apps.isEmpty {
                iconRow(apps: apps, zone: .hidden)
            }

            if !alwaysHiddenApps.isEmpty {
                sectionDivider(label: "Always Hidden")
                iconRow(apps: alwaysHiddenApps, zone: .alwaysHidden)
            }
        }
    }

    private func iconRow(apps: [RunningApp], zone: IconZone) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(apps) { app in
                    PanelIconTile(
                        app: app,
                        zone: zone,
                        colorScheme: colorScheme,
                        onActivate: { isRightClick in onActivate(app, isRightClick) },
                        onMoveToVisible: { moveIcon(app, toZone: .visible) },
                        onMoveToHidden: zone == .alwaysHidden ? { moveIcon(app, toZone: .hidden) } : nil,
                        onMoveToAlwaysHidden: zone == .hidden ? { moveIcon(app, toZone: .alwaysHidden) } : nil
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func sectionDivider(label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.teal.opacity(0.1))
                .frame(height: 1)

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize()

            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.teal.opacity(0.1))
                .frame(height: 1)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Icon Movement

    private func moveIcon(_ app: RunningApp, toZone: IconZone) {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex

        switch toZone {
        case .visible:
            _ = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex, toHidden: false
            )
        case .hidden:
            // From always-hidden → regular hidden zone
            menuBarManager.unpinAlwaysHidden(app: app)
            _ = menuBarManager.moveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        case .alwaysHidden:
            menuBarManager.pinAlwaysHidden(app: app)
            _ = menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
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
                Text("No hidden icons")
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
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(isHovering ? 1.0 : 0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 44, maxWidth: 80)
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
