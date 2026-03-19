import AppKit
import SwiftUI

// MARK: - Second Menu Bar View

/// Compact horizontal strip showing all menu bar icons organized by row.
///
/// Visible → Hidden → Always Hidden, separated by thin vertical dividers.
/// Right-click any icon to move it between rows.
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
    @State private var showingUsageHelp = false
    @State private var targetedEmptyZone: IconZone?

    // Second-menu-bar readability: force high-contrast white text on glass background.
    private let textPrimary = Color.white
    private let textSecondary = Color.white.opacity(0.92)
    private let textMuted = Color.white.opacity(0.82)
    private let accentStart = SaneBarChrome.accentStart
    private let accentEnd = SaneBarChrome.accentEnd
    private let accentHighlight = SaneBarChrome.accentHighlight

    // Filter out system items that can't be moved (Clock, Control Center)
    private var allMovableVisible: [RunningApp] { visibleApps.filter { !$0.isUnmovableSystemItem } }
    private var movableVisible: [RunningApp] {
        guard menuBarManager.settings.secondMenuBarShowVisible else { return [] }
        return allMovableVisible
    }

    private var movableHidden: [RunningApp] { apps.filter { !$0.isUnmovableSystemItem } }
    private var allMovableAlwaysHidden: [RunningApp] { alwaysHiddenApps.filter { !$0.isUnmovableSystemItem } }
    private var movableAlwaysHidden: [RunningApp] {
        guard licenseService.isPro else { return [] }
        guard menuBarManager.settings.alwaysHiddenSectionEnabled else { return [] }
        guard menuBarManager.settings.secondMenuBarShowAlwaysHidden else { return [] }
        return allMovableAlwaysHidden
    }
    private var shouldShowVisibleDropZone: Bool {
        SecondMenuBarLayout.shouldShowVisibleZone(
            includeVisibleIcons: menuBarManager.settings.secondMenuBarShowVisible
        )
    }
    private var shouldShowAlwaysHiddenDropZone: Bool {
        guard licenseService.isPro else { return false }
        return SecondMenuBarLayout.shouldShowAlwaysHiddenZone(
            alwaysHiddenZoneEnabled: menuBarManager.settings.alwaysHiddenSectionEnabled,
            includeAlwaysHiddenIcons: menuBarManager.settings.secondMenuBarShowAlwaysHidden
        )
    }
    private var duplicateMarkers: [String: BrowseDuplicateMarker] {
        BrowseDuplicateMarker.markers(for: visibleApps + apps + alwaysHiddenApps)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            if hasAccessibility {
                rowStateControls
            }
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
                    colorScheme == .dark ? SaneBarChrome.rowStroke : accentStart.opacity(0.18),
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
        .onChange(of: searchText) { (_: String, _: String) in
            notePanelInteraction()
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
                    .foregroundStyle(textMuted)
                TextField(
                    "Search",
                    text: $searchText,
                    prompt: Text("Search").foregroundStyle(textSecondary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(textPrimary)
                .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(SaneBarChrome.utilityFill)
            )

            Button {
                SettingsOpener.open()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(textPrimary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(SaneBarChrome.utilityFill))
                    .overlay(Circle().stroke(SaneBarChrome.controlStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                showingUsageHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accentHighlight)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(SaneBarChrome.utilityFill))
                    .overlay(Circle().stroke(SaneBarChrome.controlStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("How Browse Icons works")
            .popover(isPresented: $showingUsageHelp, arrowEdge: .top) {
                usageHelpPopover
            }

            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(textPrimary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(SaneBarChrome.utilityFill))
                    .overlay(Circle().stroke(SaneBarChrome.controlStroke, lineWidth: 1))
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
        let showHiddenZone = true
        let showAlwaysHiddenZone = shouldShowAlwaysHiddenDropZone

        return VStack(alignment: .leading, spacing: 0) {
            if showVisibleZone {
                zoneRow(
                    label: "Visible",
                    icon: "eye",
                    apps: movableVisible,
                    totalCount: allMovableVisible.count,
                    zone: .visible
                )
            }

            if showVisibleZone, showHiddenZone || showAlwaysHiddenZone {
                zoneDivider
            }

            if showHiddenZone {
                zoneRow(
                    label: "Hidden",
                    icon: "eye.slash",
                    apps: movableHidden,
                    totalCount: movableHidden.count,
                    zone: .hidden
                )
            }

            if showHiddenZone, showAlwaysHiddenZone {
                zoneDivider
            }

            if showAlwaysHiddenZone {
                zoneRow(
                    label: "Always Hidden",
                    icon: "lock",
                    apps: movableAlwaysHidden,
                    totalCount: allMovableAlwaysHidden.count,
                    zone: .alwaysHidden
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Row State Controls

    private var rowStateControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                rowStateChip(
                    title: "Visible",
                    isOn: menuBarManager.settings.secondMenuBarShowVisible,
                    isLocked: false,
                    isInteractive: licenseService.isPro,
                    helpText: licenseService.isPro ? "Show or hide the Visible row" : nil
                ) {
                    menuBarManager.settings.secondMenuBarShowVisible.toggle()
                }

                rowStateChip(
                    title: "Always Hidden",
                    isOn: menuBarManager.settings.alwaysHiddenSectionEnabled &&
                        menuBarManager.settings.secondMenuBarShowAlwaysHidden,
                    isLocked: !licenseService.isPro,
                    helpText: licenseService.isPro ? "Show or hide the Always Hidden row" : nil
                ) {
                    guard licenseService.isPro else {
                        proUpsellFeature = .alwaysHidden
                        return
                    }

                    if !menuBarManager.settings.alwaysHiddenSectionEnabled {
                        menuBarManager.settings.alwaysHiddenSectionEnabled = true
                        menuBarManager.settings.secondMenuBarShowAlwaysHidden = true
                    } else {
                        menuBarManager.settings.secondMenuBarShowAlwaysHidden.toggle()
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func rowStateChip(
        title: String,
        isOn: Bool,
        isLocked: Bool,
        isInteractive: Bool = true,
        helpText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let chip = Button {
            notePanelInteraction()
            action()
        } label: {
            HStack(spacing: 4) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(accentHighlight)
                }
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(textPrimary)
                Text(SecondMenuBarLayout.rowStateLabel(isOn: isOn))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isOn ? accentHighlight : textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                ChromeGlassCapsuleBackground(
                    tint: isOn ? SaneBarChrome.accentTeal : SaneBarChrome.controlNavyDeep,
                    edgeTint: isOn ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal,
                    tintStrength: isOn ? 0.62 : 0.10,
                    glowOpacity: isOn ? 0.22 : 0.06,
                    shadowOpacity: isOn ? 0.18 : 0.12,
                    shadowRadius: isOn ? 8 : 6,
                    shadowY: 3
                )
            )
        }
        .buttonStyle(ChromePressablePlainStyle())
        .disabled(!isInteractive)
        .opacity(isInteractive ? 1 : 0.95)
        .accessibilityLabel(Text("\(title) row"))
        .accessibilityValue(Text(SecondMenuBarLayout.rowStateLabel(isOn: isOn)))

        if let helpText {
            chip.help(helpText)
        } else {
            chip
        }
    }

    private func zoneRow(
        label: String,
        icon: String,
        apps: [RunningApp],
        totalCount: Int,
        zone: IconZone
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                Text("\(totalCount)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(textMuted)
            }
            .foregroundStyle(textPrimary)
            .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 1) {
                    ForEach(apps) { app in
                        makeTile(for: app, zone: zone)
                    }
                    if apps.isEmpty {
                        emptyZoneDropTarget(for: zone)
                            .padding(.leading, 2)
                    }
                }
            }
            .scrollIndicators(.visible)
            .onHover { inside in
                if inside {
                    notePanelInteraction()
                }
            }

        }
        .padding(.vertical, 2)
        .dropDestination(for: String.self) { payloads, _ in
            handleZoneDrop(payloads, targetZone: zone)
        } isTargeted: { isTargeted in
            targetedEmptyZone = isTargeted ? zone : (targetedEmptyZone == zone ? nil : targetedEmptyZone)
        }
    }

    private func emptyZoneDropTarget(for zone: IconZone) -> some View {
        let isTargeted = targetedEmptyZone == zone

        return HStack(spacing: 6) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "tray")
                .font(.system(size: 11, weight: .semibold))
            Text(isTargeted ? "Drop here" : "Drag icons here")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isTargeted ? textPrimary : textMuted)
        .frame(minWidth: 148, minHeight: 28)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isTargeted ? SaneBarChrome.targetControlFill : SaneBarChrome.utilityFill
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isTargeted
                        ? accentHighlight.opacity(0.54)
                        : SaneBarChrome.controlStroke,
                    lineWidth: 1
                )
        )
        .shadow(color: isTargeted ? accentHighlight.opacity(0.18) : .clear, radius: 6, y: 2)
        .scaleEffect(isTargeted ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var usageHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Browse Icons works")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("1. Click any icon here to open it.")
            Text("2. Drag an icon into another row to move it there.")
            Text("3. Right-click an icon for more actions.")
            Text("4. Use the chips above to show or hide rows.")
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private var zoneDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : accentStart.opacity(0.12))
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
            duplicateMarker: duplicateMarkers[app.uniqueId],
            onInteraction: notePanelInteraction,
            onActivate: { isRightClick in
                if isRightClick, !licenseService.isPro {
                    proUpsellFeature = .rightClickFromPanels
                    return
                }
                onActivate(app, isRightClick)
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
            onMoveToAlwaysHidden: (menuBarManager.settings.alwaysHiddenSectionEnabled && zone != .alwaysHidden) ? {
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
        notePanelInteraction()
        return queueMove(app, from: source, to: target)
    }

    private func rollbackAlwaysHiddenMutation(for app: RunningApp, from source: IconZone, to target: IconZone) {
        switch (source, target) {
        case (.alwaysHidden, .visible), (.alwaysHidden, .hidden):
            menuBarManager.pinAlwaysHidden(app: app)
        case (.hidden, .alwaysHidden), (.visible, .alwaysHidden):
            menuBarManager.unpinAlwaysHidden(app: app)
        default:
            break
        }
    }

    private func applySuccessfulMovePresentation(for target: IconZone) {
        switch target {
        case .visible where !menuBarManager.settings.secondMenuBarShowVisible:
            menuBarManager.settings.secondMenuBarShowVisible = true
        case .alwaysHidden where !menuBarManager.settings.secondMenuBarShowAlwaysHidden:
            menuBarManager.settings.secondMenuBarShowAlwaysHidden = true
        default:
            break
        }
        onIconMoved?()
    }

    private func observeQueuedMoveResult(
        _ task: Task<Bool, Never>,
        app: RunningApp,
        source: IconZone,
        target: IconZone
    ) {
        Task { @MainActor in
            let moved = await task.value
            if moved {
                applySuccessfulMovePresentation(for: target)
            } else {
                rollbackAlwaysHiddenMutation(for: app, from: source, to: target)
            }
        }
    }

    private func observeQueuedReorderResult(_ task: Task<Bool, Never>) {
        Task { @MainActor in
            let moved = await task.value
            if moved {
                onIconMoved?()
            }
        }
    }

    private func queueMove(_ app: RunningApp, from source: IconZone, to target: IconZone) -> Bool {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex

        let started: Bool
        switch (source, target) {
        // From Always Hidden
        case (.alwaysHidden, .visible):
            menuBarManager.unpinAlwaysHidden(app: app)
            started = menuBarManager.moveIconFromAlwaysHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX
            )

        case (.alwaysHidden, .hidden):
            menuBarManager.unpinAlwaysHidden(app: app)
            started = menuBarManager.moveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX
            )

        // From Hidden
        case (.hidden, .visible):
            started = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX,
                toHidden: false
            )

        case (.hidden, .alwaysHidden):
            guard menuBarManager.settings.alwaysHiddenSectionEnabled else { return false }
            menuBarManager.pinAlwaysHidden(app: app)
            started = menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX
            )

        // From Visible
        case (.visible, .hidden):
            started = menuBarManager.moveIcon(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX,
                toHidden: true
            )

        case (.visible, .alwaysHidden):
            guard menuBarManager.settings.alwaysHiddenSectionEnabled else { return false }
            menuBarManager.pinAlwaysHidden(app: app)
            started = menuBarManager.moveIconToAlwaysHidden(
                bundleID: bundleID, menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: app.preferredCenterX
            )

        // No-op (same zone)
        case (.visible, .visible), (.hidden, .hidden), (.alwaysHidden, .alwaysHidden):
            started = false
        }

        guard started, let task = menuBarManager.activeMoveTask else {
            rollbackAlwaysHiddenMutation(for: app, from: source, to: target)
            return false
        }

        observeQueuedMoveResult(task, app: app, source: source, target: target)
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
        notePanelInteraction()
        guard licenseService.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first,
              let source = sourceForDragID(sourceID),
              source.zone != targetZone
        else {
            return false
        }

        return moveIcon(source.app, from: source.zone, to: targetZone)
    }

    private func handleTileDrop(_ payloads: [String], targetApp: RunningApp, targetZone: IconZone) -> Bool {
        notePanelInteraction()
        guard licenseService.isPro else {
            proUpsellFeature = .zoneMoves
            return false
        }

        guard let sourceID = payloads.first,
              let source = sourceForDragID(sourceID)
        else {
            return false
        }

        if source.zone != targetZone {
            return moveIcon(source.app, from: source.zone, to: targetZone)
        }

        guard sourceID != targetApp.uniqueId else { return false }
        return handleReorderDrop(payloads, targetApp: targetApp)
    }

    private func handleReorderDrop(_ payloads: [String], targetApp: RunningApp) -> Bool {
        notePanelInteraction()
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

        guard started, let task = menuBarManager.activeMoveTask else { return false }

        observeQueuedReorderResult(task)
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
                    .foregroundStyle(textSecondary)
            } else {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 18))
                    .foregroundStyle(textMuted)
                Text("No icons found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textSecondary)
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
                Text("Grant Access")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textPrimary)
                Text("Required to detect icons")
                    .font(.system(size: 11))
                    .foregroundStyle(textSecondary)
            }

            Spacer()

            Button("Grant") {
                _ = AccessibilityService.shared.openAccessibilitySettings()
            }
            .controlSize(.small)
            .buttonStyle(ChromeActionButtonStyle(prominent: true))

            Button { onRetry() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(10)
    }

    private func notePanelInteraction() {
        SearchWindowController.shared.noteSecondMenuBarInteraction()
    }
}
// swiftlint:enable file_length

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
    static func rowStateLabel(isOn: Bool) -> String {
        isOn ? "On" : "Off"
    }

    static func shouldShowVisibleZone(
        includeVisibleIcons: Bool
    ) -> Bool {
        includeVisibleIcons
    }

    static func shouldShowAlwaysHiddenZone(
        alwaysHiddenZoneEnabled: Bool,
        includeAlwaysHiddenIcons: Bool
    ) -> Bool {
        alwaysHiddenZoneEnabled && includeAlwaysHiddenIcons
    }

}

// MARK: - Panel Icon Tile

/// Compact icon tile — icon only, tooltip on hover, context menu for zone moves.
private struct PanelIconTile: View {
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

    /// Squircle container size.
    /// Icon frame is intentionally oversized to compensate for the transparent
    /// padding baked into menu-bar NSImages (~28 % border).  The squircle
    /// clipShape trims the overflow so glyphs visually fill ≈80-90 % of the tile
    /// while `.fit` preserves aspect ratio (no deformation).
    private let tileSize: CGFloat = 32
    private let accentStart = SaneBarChrome.accentStart
    private let accentEnd = SaneBarChrome.accentEnd
    private var iconSize: CGFloat {
        let icon = app.iconThumbnail ?? app.icon
        // System template icons are non-square and deform when overscaled.
        // Regular app icons have padding that needs overscaling to fill the tile.
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
        if let icon = app.iconThumbnail ?? app.icon {
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

    // MARK: - Context Menu (Zone Management)

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
