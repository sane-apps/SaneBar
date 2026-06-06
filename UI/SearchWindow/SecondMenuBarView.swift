import SaneUI
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
        SaneGradientBackground(style: .panel)
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
            Text("Drag icons here")
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
                if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .rightClick, isPro: licenseService.isPro),
                   isRightClick {
                    proUpsellFeature = feature
                    return
                }
                onActivate(app, isRightClick)
            },
            onMoveToVisible: zone != .visible ? {
                if licenseService.isPro {
                    _ = moveIcon(app, from: zone, to: .visible)
                } else {
                    proUpsellFeature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro)
                }
            } : nil,
            onMoveToHidden: zone != .hidden ? {
                if licenseService.isPro {
                    _ = moveIcon(app, from: zone, to: .hidden)
                } else {
                    proUpsellFeature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro)
                }
            } : nil,
            onMoveToAlwaysHidden: (menuBarManager.settings.alwaysHiddenSectionEnabled && zone != .alwaysHidden) ? {
                if licenseService.isPro {
                    _ = moveIcon(app, from: zone, to: .alwaysHidden)
                } else {
                    proUpsellFeature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro)
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

    private func observeQueuedMoveResult(_ task: Task<Bool, Never>, target: IconZone) {
        Task { @MainActor in
            let moved = await task.value
            if moved {
                applySuccessfulMovePresentation(for: target)
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

    private func zoneMoveRequest(from source: IconZone, to target: IconZone) -> MenuBarZoneMoveRequest? {
        switch (source, target) {
        case (.visible, .hidden):
            return .visibleToHidden
        case (.hidden, .visible):
            return .hiddenToVisible
        case (.visible, .alwaysHidden):
            return menuBarManager.settings.alwaysHiddenSectionEnabled ? .visibleToAlwaysHidden : nil
        case (.hidden, .alwaysHidden):
            return menuBarManager.settings.alwaysHiddenSectionEnabled ? .hiddenToAlwaysHidden : nil
        case (.alwaysHidden, .visible):
            return .alwaysHiddenToVisible
        case (.alwaysHidden, .hidden):
            return .alwaysHiddenToHidden
        case (.visible, .visible), (.hidden, .hidden), (.alwaysHidden, .alwaysHidden):
            return nil
        }
    }

    private func queueMove(_ app: RunningApp, from source: IconZone, to target: IconZone) -> Bool {
        let request = zoneMoveRequest(from: source, to: target)

        guard let request,
              let task = menuBarManager.moveQueueWorkflow.queueZoneMove(
                  app: app,
                  request: request,
                  physicalMoveOrigin: .explicitUserAction
              ) else { return false }

        observeQueuedMoveResult(task, target: target)
        return true
    }

    private func queueMoveAfterDrop(_ app: RunningApp, from source: IconZone, to target: IconZone) -> Bool {
        guard let request = zoneMoveRequest(from: source, to: target) else { return false }
        Task { @MainActor in
            await Task.yield()
            notePanelInteraction()
            guard let task = await menuBarManager.moveQueueWorkflow.queueZoneMoveAfterDrop(
                app: app,
                request: request,
                physicalMoveOrigin: .explicitUserAction
            ) else { return }
            observeQueuedMoveResult(task, target: target)
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
        notePanelInteraction()
        if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro) {
            proUpsellFeature = feature
            return false
        }

        guard let sourceID = payloads.first,
              let source = sourceForDragID(sourceID),
              source.zone != targetZone
        else {
            return false
        }

        return queueMoveAfterDrop(source.app, from: source.zone, to: targetZone)
    }

    private func handleTileDrop(_ payloads: [String], targetApp: RunningApp, targetZone: IconZone) -> Bool {
        notePanelInteraction()
        if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro) {
            proUpsellFeature = feature
            return false
        }

        guard let sourceID = payloads.first,
              let source = sourceForDragID(sourceID)
        else {
            return false
        }

        if source.zone != targetZone {
            return queueMoveAfterDrop(source.app, from: source.zone, to: targetZone)
        }

        guard sourceID != targetApp.uniqueId else { return false }
        return handleReorderDrop(payloads, targetApp: targetApp)
    }

    private func handleReorderDrop(_ payloads: [String], targetApp: RunningApp) -> Bool {
        notePanelInteraction()
        if let feature = BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro) {
            proUpsellFeature = feature
            return false
        }

        guard let sourceID = payloads.first, sourceID != targetApp.uniqueId else { return false }
        let allApps = movableVisible + movableHidden + movableAlwaysHidden
        guard let sourceApp = allApps.first(where: { $0.uniqueId == sourceID }) else { return false }

        let sourceX = sourceApp.xPosition ?? 0
        let targetX = targetApp.xPosition ?? 0
        let placeAfterTarget = sourceX < targetX

        Task { @MainActor in
            await Task.yield()
            guard let task = menuBarManager.moveQueueWorkflow.queueReorderIcon(
                sourceBundleID: sourceApp.bundleId,
                sourceMenuExtraID: sourceApp.menuExtraIdentifier,
                sourceStatusItemIndex: sourceApp.statusItemIndex,
                targetBundleID: targetApp.bundleId,
                targetMenuExtraID: targetApp.menuExtraIdentifier,
                targetStatusItemIndex: targetApp.statusItemIndex,
                placeAfterTarget: placeAfterTarget,
                physicalMoveOrigin: .explicitUserAction
            ) else { return }

            observeQueuedReorderResult(task)
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
