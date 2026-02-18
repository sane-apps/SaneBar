import AppKit
import SwiftUI

// MARK: - Second Menu Bar View

/// Compact horizontal strip showing all menu bar icons organized by zone.
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
    @Binding var searchText: String

    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var licenseService = LicenseService.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var proUpsellFeature: ProFeature?

    // Filter out system items that can't be moved (Clock, Control Center)
    private var allMovableVisible: [RunningApp] { visibleApps.filter { !$0.isUnmovableSystemItem } }
    private var movableVisible: [RunningApp] {
        guard menuBarManager.settings.secondMenuBarShowVisible else { return [] }
        return allMovableVisible
    }

    private var movableHidden: [RunningApp] { apps.filter { !$0.isUnmovableSystemItem } }
    private var movableAlwaysHidden: [RunningApp] { alwaysHiddenApps.filter { !$0.isUnmovableSystemItem } }
    private var shouldShowVisibleDropZone: Bool {
        SecondMenuBarLayout.shouldShowVisibleZone(
            includeVisibleIcons: menuBarManager.settings.secondMenuBarShowVisible,
            hiddenCount: movableHidden.count,
            alwaysHiddenCount: movableAlwaysHidden.count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            if !hasAccessibility {
                accessibilityPrompt
            } else if movableVisible.isEmpty, movableHidden.isEmpty, movableAlwaysHidden.isEmpty {
                emptyState
            } else {
                iconStrip
            }
        }
        .frame(minWidth: 180)
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
        .onChange(of: proUpsellFeature) { (_: ProFeature?, feature: ProFeature?) in
            if let feature {
                ProUpsellWindow.show(feature: feature)
                proUpsellFeature = nil
            }
        }
    }

    // MARK: - Background

    private var panelBackground: some View {
        SaneGradientBackground()
    }

    // MARK: - Compact Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 6) {
            // Inline search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(0.4))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )

            Button {
                SettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    // MARK: - Horizontal Icon Strip

    private var iconStrip: some View {
        let showVisibleZone = shouldShowVisibleDropZone
        let showHiddenZone = !movableHidden.isEmpty
        let showAlwaysHiddenZone = !movableAlwaysHidden.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            if showVisibleZone {
                zoneRow(label: "Visible", icon: "eye", apps: movableVisible, zone: .visible)
            }

            if showVisibleZone, showHiddenZone || showAlwaysHiddenZone {
                zoneDivider
            }

            if showHiddenZone {
                zoneRow(label: "Hidden", icon: "eye.slash", apps: movableHidden, zone: .hidden)
            }

            if showHiddenZone, showAlwaysHiddenZone {
                zoneDivider
            }

            if showAlwaysHiddenZone {
                zoneRow(label: "Always Hidden", icon: "lock", apps: movableAlwaysHidden, zone: .alwaysHidden)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func zoneRow(label: String, icon: String, apps: [RunningApp], zone: IconZone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(apps.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            .foregroundStyle(.primary.opacity(0.7))
            .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 1) {
                    ForEach(apps) { app in
                        makeTile(for: app, zone: zone)
                    }
                    if apps.isEmpty {
                        Text("Drop here")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.55))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                            )
                            .padding(.leading, 2)
                    }
                }
            }
            .scrollIndicators(.visible)

            if apps.count > 14 {
                Text("Scroll sideways to see all icons")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
                    .padding(.leading, 2)
            }
        }
        .padding(.vertical, 2)
        .dropDestination(for: String.self) { payloads, _ in
            handleZoneDrop(payloads, targetZone: zone)
        }
    }

    private var zoneDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.teal.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
    }

    // MARK: - Tile Factory

    private func makeTile(for app: RunningApp, zone: IconZone) -> some View {
        PanelIconTile(
            app: app,
            zone: zone,
            colorScheme: colorScheme,
            isPro: licenseService.isPro,
            onActivate: { isRightClick in
                if licenseService.isPro {
                    onActivate(app, isRightClick)
                } else {
                    proUpsellFeature = isRightClick ? .rightClickFromPanels : .iconActivation
                }
            },
            onMoveToVisible: zone != .visible ? {
                if licenseService.isPro {
                    _ = moveIcon(app, from: zone, to: .visible)
                } else {
                    proUpsellFeature = .zoneMoves
                }
            } : nil,
            onMoveToHidden: zone != .hidden ? {
                if licenseService.isPro {
                    _ = moveIcon(app, from: zone, to: .hidden)
                } else {
                    proUpsellFeature = .zoneMoves
                }
            } : nil,
            onMoveToAlwaysHidden: zone != .alwaysHidden ? {
                if licenseService.isPro {
                    _ = moveIcon(app, from: zone, to: .alwaysHidden)
                } else {
                    proUpsellFeature = .zoneMoves
                }
            } : nil
        )
        .draggable(app.uniqueId)
        .dropDestination(for: String.self) { payloads, _ in
            handleTileDrop(payloads, targetApp: app, targetZone: zone)
        }
    }

    // MARK: - Icon Movement

    private func moveIcon(_ app: RunningApp, from source: IconZone, to target: IconZone) -> Bool {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex

        let started: Bool
        switch (source, target) {
        case (_, .visible):
            if source == .alwaysHidden { menuBarManager.unpinAlwaysHidden(app: app) }
            started = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex, toHidden: false
            )

        case (.visible, .hidden):
            started = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex, toHidden: true
            )

        case (.alwaysHidden, .hidden):
            menuBarManager.unpinAlwaysHidden(app: app)
            started = menuBarManager.moveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )

        case (_, .alwaysHidden):
            menuBarManager.pinAlwaysHidden(app: app)
            started = menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )

        default:
            started = false
        }

        guard started else { return false }

        // Refresh the panel data after the move takes effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onIconMoved?()
        }
        return true
    }

    private func sourceForDragID(_ sourceID: String) -> (app: RunningApp, zone: IconZone)? {
        SecondMenuBarDropResolver.sourceForDragID(
            sourceID,
            visible: movableVisible,
            hidden: movableHidden,
            alwaysHidden: movableAlwaysHidden
        )
    }

    private func handleZoneDrop(_ payloads: [String], targetZone: IconZone) -> Bool {
        guard licenseService.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first,
              let source = sourceForDragID(sourceID),
              source.zone != targetZone else {
            return false
        }

        return moveIcon(source.app, from: source.zone, to: targetZone)
    }

    private func handleTileDrop(_ payloads: [String], targetApp: RunningApp, targetZone: IconZone) -> Bool {
        guard licenseService.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first,
              let source = sourceForDragID(sourceID) else {
            return false
        }

        if source.zone != targetZone {
            return moveIcon(source.app, from: source.zone, to: targetZone)
        }

        guard sourceID != targetApp.uniqueId else { return false }
        return handleReorderDrop(payloads, targetApp: targetApp)
    }

    private func handleReorderDrop(_ payloads: [String], targetApp: RunningApp) -> Bool {
        guard licenseService.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first, sourceID != targetApp.uniqueId else { return false }
        let allApps = movableVisible + movableHidden + movableAlwaysHidden
        guard let sourceApp = allApps.first(where: { $0.uniqueId == sourceID }) else { return false }

        let sourceX = sourceApp.xPosition ?? 0
        let targetX = targetApp.xPosition ?? 0
        let placeAfterTarget = sourceX < targetX

        let started = menuBarManager.reorderIcon(
            sourceBundleID: sourceApp.bundleId,
            sourceMenuExtraID: sourceApp.menuExtraIdentifier,
            sourceStatusItemIndex: sourceApp.statusItemIndex,
            targetBundleID: targetApp.bundleId,
            targetMenuExtraID: targetApp.menuExtraIdentifier,
            targetStatusItemIndex: targetApp.statusItemIndex,
            placeAfterTarget: placeAfterTarget
        )

        guard started else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onIconMoved?()
        }
        return true
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning...")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.6))
            } else {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary.opacity(0.3))
                Text("No icons found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
    }

    // MARK: - Accessibility Prompt

    private var accessibilityPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility Needed")
                    .font(.system(size: 11, weight: .medium))
                Text("Required to detect icons")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.7))
            }

            Spacer()

            Button("Grant") {
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
        .padding(10)
    }
}

// MARK: - Icon Zone

enum IconZone {
    case visible, hidden, alwaysHidden
}

enum SecondMenuBarDropResolver {
    static func sourceForDragID(
        _ sourceID: String,
        visible: [RunningApp],
        hidden: [RunningApp],
        alwaysHidden: [RunningApp]
    ) -> (app: RunningApp, zone: IconZone)? {
        if let app = visible.first(where: { $0.uniqueId == sourceID }) {
            return (app, .visible)
        }
        if let app = hidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .hidden)
        }
        if let app = alwaysHidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .alwaysHidden)
        }
        return nil
    }
}

enum SecondMenuBarLayout {
    static func shouldShowVisibleZone(
        includeVisibleIcons: Bool,
        hiddenCount: Int,
        alwaysHiddenCount: Int
    ) -> Bool {
        if includeVisibleIcons {
            return true
        }
        return hiddenCount > 0 || alwaysHiddenCount > 0
    }
}

// MARK: - Panel Icon Tile

/// Compact icon tile — icon only, tooltip on hover, context menu for zone moves.
private struct PanelIconTile: View {
    let app: RunningApp
    let zone: IconZone
    let colorScheme: ColorScheme
    var isPro: Bool = true
    let onActivate: (Bool) -> Void
    var onMoveToVisible: (() -> Void)?
    var onMoveToHidden: (() -> Void)?
    var onMoveToAlwaysHidden: (() -> Void)?
    @State private var isHovering = false

    /// Squircle container size.
    /// Icon frame is intentionally oversized to compensate for the transparent
    /// padding baked into menu-bar NSImages (~28 % border).  The squircle
    /// clipShape trims the overflow so glyphs visually fill ≈80-90 % of the tile
    /// while `.fit` preserves aspect ratio (no deformation).
    private let tileSize: CGFloat = 32
    private var iconSize: CGFloat {
        let icon = app.iconThumbnail ?? app.icon
        // System template icons are non-square and deform when overscaled.
        // Regular app icons have padding that needs overscaling to fill the tile.
        return icon?.isTemplate == true ? tileSize * 0.65 : tileSize * 1.15
    }

    var body: some View {
        Button { onActivate(false) } label: {
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
        .overlay(alignment: .bottomTrailing) {
            if !isPro {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.teal)
                    .padding(2)
                    .background(Circle().fill(.ultraThinMaterial))
                    .offset(x: 2, y: 2)
            }
        }
        .onHover { isHovering = $0 }
        .help(isPro ? app.name : "\(app.name) — Pro required to activate")
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
