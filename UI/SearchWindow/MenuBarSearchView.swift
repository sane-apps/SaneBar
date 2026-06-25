import AppKit
import KeyboardShortcuts
import SaneUI
import SwiftUI

// MARK: - MenuBarSearchView

/// SwiftUI view for finding (and clicking) menu bar icons.
struct MenuBarSearchView: View {
    typealias Mode = BrowsePanelMode
    typealias AppZone = BrowseAppZone

    @AppStorage("MenuBarSearchView.mode") private var storedMode: String = Mode.all.rawValue

    @State private var searchText: String
    @State private var searchTextDebounced: String
    @State var isSearchVisible = true
    @FocusState var isSearchFieldFocused: Bool
    @State var selectedAppIndex: Int?

    @State private var menuBarApps: [RunningApp] = []
    @State private var visibleApps: [RunningApp] = []
    @State private var alwaysHiddenApps: [RunningApp] = []
    @State private var isRefreshing = false
    @State private var hasAccessibility = false
    @State private var permissionMonitorTask: Task<Void, Never>?
    @State private var refreshTask: Task<Void, Never>?
    @State private var postMoveRefreshTask: Task<Void, Never>?
    @State private var crowdedVisibleHintTask: Task<Void, Never>?
    @State private var crowdedVisibleHintDismissTask: Task<Void, Never>?
    @State private var refreshGeneration = 0
    @State private var postMoveRefreshGeneration = 0

    @State var hotkeyApp: RunningApp?
    @State var proUpsellFeature: ProFeature?
    @State private var showingBrowseHelp = false
    @State private var targetedModeDrop: Mode?
    @State private var isModeStripDropActive = false
    @State private var activeModeStripSourceZone: AppZone?
    @State private var localModeStripDragEndMonitor: Any?
    @State private var globalModeStripDragEndMonitor: Any?
    // Fix: Implicit Optional Initialization Violation
    @State private var selectedGroupId: UUID?
    @State private var selectedSmartCategory: AppCategory?
    @State var movingAppId: String?
    /// Set when a move resolves to a non-silent, retryable failure so the row can
    /// surface a "couldn't move — try again" affordance instead of going silent.
    @State var lastFailedMoveAppId: String?
    /// Set after a move completes so the next tab switch does a fresh scan
    @State private var needsPostMoveRefresh = false
    @State private var showingCrowdedVisibleHint = false
    @ObservedObject var menuBarManager = MenuBarManager.shared

    static let resetSearchNotification = Notification.Name("MenuBarSearchView.resetSearch")
    static let setSearchTextNotification = Notification.Name("MenuBarSearchView.setSearchText")
    let service: SearchServiceProtocol
    let onDismiss: () -> Void
    let isSecondMenuBar: Bool

    init(
        isSecondMenuBar: Bool = false,
        service: SearchServiceProtocol = SearchService.shared,
        initialSearchText: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        let initialSearchText = initialSearchText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _searchText = State(initialValue: initialSearchText)
        _searchTextDebounced = State(initialValue: initialSearchText)
        self.isSecondMenuBar = isSecondMenuBar
        self.service = service
        self.onDismiss = onDismiss
    }

    var isAlwaysHiddenEnabled: Bool {
        LicenseService.shared.isPro && menuBarManager.alwaysHiddenSeparatorItem != nil
    }

    var mode: Mode {
        let current = Mode(rawValue: storedMode) ?? .all
        if current == .alwaysHidden, !isAlwaysHiddenEnabled {
            return .all
        }
        return current
    }

    private var availableModes: [Mode] {
        Mode.allCases
    }

    private func modeSupportsZoneDrop(_ mode: Mode) -> Bool {
        switch mode {
        case .hidden, .visible:
            true
        case .alwaysHidden:
            isAlwaysHiddenEnabled
        case .all:
            false
        }
    }

    private func modeForZone(_ zone: AppZone) -> Mode {
        switch zone {
        case .visible:
            .visible
        case .hidden:
            .hidden
        case .alwaysHidden:
            .alwaysHidden
        }
    }

    private func modeAcceptsCurrentDrag(_ mode: Mode) -> Bool {
        guard modeSupportsZoneDrop(mode) else { return false }
        guard isModeStripDropActive, let activeModeStripSourceZone else { return true }
        let originMode = modeForZone(activeModeStripSourceZone)
        return originMode != mode
    }

    @MainActor
    func noteModeStripDragStarted(sourceZone: AppZone) {
        guard LicenseService.shared.isPro else { return }
        activeModeStripSourceZone = sourceZone
        isModeStripDropActive = true
        if targetedModeDrop == modeForZone(sourceZone) {
            targetedModeDrop = nil
        }
    }

    @MainActor
    func clearModeStripDragState() {
        isModeStripDropActive = false
        activeModeStripSourceZone = nil
        targetedModeDrop = nil
    }

    @MainActor
    private func installModeStripDragEndMonitors() {
        guard localModeStripDragEndMonitor == nil else { return }
        let monitors = BrowsePanelModeStripDragMonitor.install(clearDragState: clearModeStripDragState)
        localModeStripDragEndMonitor = monitors.local
        globalModeStripDragEndMonitor = monitors.global
    }

    @MainActor
    private func removeModeStripDragEndMonitors() {
        BrowsePanelModeStripDragMonitor.remove(
            local: &localModeStripDragEndMonitor,
            global: &globalModeStripDragEndMonitor
        )
    }

    /// Categories that have at least one app (for smart group tabs)
    private var availableCategories: [AppCategory] {
        let categories = Set(menuBarApps.map(\.category))
        // Return in a sensible order, filtering to only those with apps
        return AppCategory.allCases.filter { categories.contains($0) }
    }

    private var accentHighlight: Color {
        SaneBarChrome.accentHighlight
    }

    private var shouldShowMoveHint: Bool {
        LicenseService.shared.isPro && isModeStripDropActive && !moveHintModes.isEmpty
    }

    private var moveHintModes: [Mode] {
        availableModes.filter(modeAcceptsCurrentDrag)
    }

    var filteredApps: [RunningApp] {
        var apps = menuBarApps
            .filter { !$0.isUnmovableSystemItem }

        // Filter by custom group (takes precedence)
        if let groupId = selectedGroupId,
           let group = menuBarManager.settings.iconGroups.first(where: { $0.id == groupId }) {
            let bundleIds = Set(group.appBundleIds)
            apps = apps.filter { bundleIds.contains($0.bundleId) }
        }
        // Filter by smart category (when no custom group selected)
        else if let category = selectedSmartCategory {
            apps = apps.filter { $0.category == category }
        }

        // Filter by search text
        if !searchTextDebounced.isEmpty {
            apps = apps.filter { $0.name.localizedCaseInsensitiveContains(searchTextDebounced) }
        }

        // Sort by X position for ALL modes (Hidden, Visible, and All)
        // This ensures the grid always matches the visual menu bar order (Left-to-Right)
        apps.sort { ($0.xPosition ?? 0) < ($1.xPosition ?? 0) }

        return apps
    }

    var body: some View {
        Group {
            if isSecondMenuBar {
                secondMenuBarBody
            } else {
                findIconBody
            }
        }
        .modifier(panelLifecycleModifier)
    }

    private var panelLifecycleModifier: BrowsePanelLifecycleModifier {
        BrowsePanelLifecycleModifier(
            isSecondMenuBar: isSecondMenuBar,
            storedMode: $storedMode,
            searchText: $searchText,
            searchTextDebounced: $searchTextDebounced,
            isSearchVisible: $isSearchVisible,
            setSearchFieldFocused: { isSearchFieldFocused = $0 },
            selectedAppIndex: $selectedAppIndex,
            movingAppId: $movingAppId,
            hotkeyApp: $hotkeyApp,
            proUpsellFeature: $proUpsellFeature,
            needsPostMoveRefresh: $needsPostMoveRefresh,
            filteredAppsCount: filteredApps.count,
            syncAccessibilityState: syncAccessibilityState,
            loadCachedApps: loadCachedApps,
            refreshApps: { refreshApps(force: $0) },
            startPermissionMonitoring: startPermissionMonitoring,
            installModeStripDragEndMonitors: installModeStripDragEndMonitors,
            clearModeStripDragState: clearModeStripDragState,
            removeModeStripDragEndMonitors: removeModeStripDragEndMonitors,
            cancelPanelTasks: cancelPanelTasks,
            schedulePostMoveFollowupRefresh: schedulePostMoveFollowupRefresh,
            scheduleCrowdedVisibleHintEvaluation: scheduleCrowdedVisibleHintEvaluation(from:),
            handleKeyPress: handleKeyPress,
            onDismiss: onDismiss
        )
    }

    @MainActor
    private func cancelPanelTasks() {
        permissionMonitorTask?.cancel()
        refreshTask?.cancel()
        postMoveRefreshTask?.cancel()
        crowdedVisibleHintTask?.cancel()
        crowdedVisibleHintDismissTask?.cancel()
    }

    // MARK: - Find Icon Body (original layout)

    private var findIconBody: some View {
        BrowseFindIconPanelView(
            availableModes: availableModes,
            mode: mode,
            isAlwaysHiddenEnabled: isAlwaysHiddenEnabled,
            isSearchVisible: $isSearchVisible,
            targetedModeDrop: $targetedModeDrop,
            shouldShowMoveHint: shouldShowMoveHint,
            moveHintModes: moveHintModes,
            accentHighlight: accentHighlight,
            onSearchHidden: { searchText = "" },
            onModeSelected: { selectedMode in
                if selectedMode == .alwaysHidden, !isAlwaysHiddenEnabled {
                    proUpsellFeature = .alwaysHidden
                } else {
                    storedMode = selectedMode.rawValue
                }
            },
            onRefresh: { refreshApps(force: true) },
            handleZoneDrop: handleZoneDrop(_:targetMode:),
            clearDragState: clearModeStripDragState,
            availableCategories: availableCategories,
            iconGroups: menuBarManager.settings.iconGroups,
            selectedGroupId: $selectedGroupId,
            selectedSmartCategory: $selectedSmartCategory,
            addAppToGroup: { bundleId, groupId in
                BrowsePanelGroupEditor.addAppToGroup(bundleId: bundleId, groupId: groupId, manager: menuBarManager)
            },
            deleteGroup: { groupId in
                selectedGroupId = BrowsePanelGroupEditor.deleteGroup(
                    groupId: groupId,
                    selectedGroupId: selectedGroupId,
                    manager: menuBarManager
                )
            },
            createCustomGroup: {
                BrowsePanelGroupEditor.openCustomGroupCreation(
                    isPro: LicenseService.shared.isPro,
                    manager: menuBarManager,
                    showUpsell: { proUpsellFeature = .iconGroups },
                    selectGroup: { selectedGroupId = $0 }
                )
            },
            searchText: $searchText,
            isSearchFieldFocused: $isSearchFieldFocused,
            showingBrowseHelp: $showingBrowseHelp,
            hasAccessibility: hasAccessibility,
            hasMenuBarApps: !menuBarApps.isEmpty,
            isRefreshing: isRefreshing,
            filteredApps: filteredApps,
            duplicateMarkers: duplicateMarkers,
            selectedAppIndex: selectedAppIndex,
            movingAppId: movingAppId,
            appZone: appZone(for:),
            activateApp: activateApp(_:isRightClick:),
            setHotkey: { hotkeyApp = $0 },
            removeAppFromGroup: { bundleId, groupId in
                BrowsePanelGroupEditor.removeAppFromGroup(bundleId: bundleId, groupId: groupId, manager: menuBarManager)
            },
            makeToggleHiddenAction: makeToggleHiddenAction(for:),
            makeMoveToAlwaysHiddenAction: makeMoveToAlwaysHiddenAction(for:),
            makeMoveToHiddenAction: makeMoveToHiddenAction(for:),
            showRestrictedFeature: { proUpsellFeature = $0 },
            noteDragStarted: noteModeStripDragStarted(sourceZone:),
            handleGridDrop: handleGridReorderDrop(_:targetApp:),
            openAccessibilitySettings: {
                _ = AccessibilityService.shared.openAccessibilitySettings()
            },
            retryAccessibility: {
                _ = syncAccessibilityState(forceProbe: true, promptUser: true)
                loadCachedApps()
                refreshApps(force: true)
            },
            showingCrowdedVisibleHint: showingCrowdedVisibleHint,
            dismissCrowdedVisibleHint: dismissCrowdedVisibleHint,
            enableSecondMenuBarFromHint: enableSecondMenuBarFromHint
        )
    }

    // MARK: - Second Menu Bar Body

    private var secondMenuBarBody: some View {
        BrowseSecondMenuBarPanelView(
            visibleApps: visibleApps,
            hiddenApps: filteredApps,
            alwaysHiddenApps: alwaysHiddenApps,
            searchText: searchTextDebounced,
            hasAccessibility: hasAccessibility,
            isRefreshing: isRefreshing,
            onDismiss: onDismiss,
            onActivate: { app, isRightClick in
                if isRightClick, !LicenseService.shared.isPro {
                    proUpsellFeature = .rightClickFromPanels
                    return
                }
                activateApp(app, isRightClick: isRightClick)
            },
            onRetry: {
                _ = syncAccessibilityState(forceProbe: true, promptUser: true)
                loadCachedApps()
                refreshApps(force: true)
            },
            searchTextBinding: $searchText
        )
    }

    private var duplicateMarkers: [String: BrowseDuplicateMarker] {
        BrowseDuplicateMarker.markers(for: filteredApps)
    }

    /// Monitor for permission changes - auto-reload when user grants permission
    @MainActor
    private func startPermissionMonitoring() {
        permissionMonitorTask = Task { @MainActor in
            for await granted in AccessibilityService.shared.permissionStream(includeInitial: false) {
                guard granted != hasAccessibility else { continue }

                hasAccessibility = granted
                if granted {
                    // Permission was granted - reload from cache then force refresh.
                    loadCachedApps()
                    refreshApps(force: true)
                } else {
                    // Permission was revoked - clear data and stop refresh work.
                    refreshTask?.cancel()
                    isRefreshing = false
                    menuBarApps = []
                    visibleApps = []
                    alwaysHiddenApps = []
                }
            }
        }
    }

    /// The effective mode for data loading — panel mode always shows hidden icons
    private var effectiveMode: Mode {
        isSecondMenuBar ? .hidden : mode
    }

    @MainActor
    private func syncAccessibilityState() -> Bool {
        syncAccessibilityState(forceProbe: false, promptUser: false)
    }

    @MainActor
    private func syncAccessibilityState(forceProbe: Bool, promptUser: Bool = false) -> Bool {
        // Passive paths should use cached published state to avoid repeated TCC hits.
        // Only explicit retry actions should force a live check.
        let liveStatus = forceProbe ? AccessibilityService.shared.requestAccessibility(promptUser: promptUser) : AccessibilityService.shared.isGranted
        hasAccessibility = liveStatus
        return liveStatus
    }

    @MainActor
    private func loadCachedApps() {
        _ = syncAccessibilityState()

        guard hasAccessibility else {
            menuBarApps = []
            visibleApps = []
            alwaysHiddenApps = []
            return
        }

        // Single-pass classification for all modes — one backend, consistent results.
        let classified = service.cachedClassifiedApps()

        if isSecondMenuBar {
            visibleApps = classified.visible
            menuBarApps = classified.hidden
            alwaysHiddenApps = classified.alwaysHidden
        } else {
            switch effectiveMode {
            case .hidden:
                menuBarApps = classified.hidden
            case .visible:
                menuBarApps = classified.visible
            case .alwaysHidden:
                menuBarApps = classified.alwaysHidden
            case .all:
                menuBarApps = service.cachedMenuBarApps()
            }
        }
    }

    @MainActor
    private func schedulePostMoveFollowupRefresh() {
        // A single delayed refresh smooths out WindowServer/AX settle races after drag moves.
        postMoveRefreshTask?.cancel()
        postMoveRefreshGeneration += 1
        let generation = postMoveRefreshGeneration

        postMoveRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            await MainActor.run {
                guard postMoveRefreshGeneration == generation else { return }
                refreshApps(force: true)
            }
        }
    }

    @MainActor
    private func scheduleCrowdedVisibleHintEvaluation(from notification: Notification) {
        crowdedVisibleHintTask?.cancel()
        crowdedVisibleHintTask = BrowsePanelCrowdingHintCoordinator.evaluationTask(
            from: notification,
            context: BrowsePanelCrowdingHintContext(
                isSecondMenuBar: isSecondMenuBar,
                useSecondMenuBar: { menuBarManager.settings.useSecondMenuBar },
                isShowing: showingCrowdedVisibleHint,
                visibleApps: { service.cachedClassifiedApps().visible },
                show: showCrowdedVisibleHint
            )
        )
    }

    @MainActor
    private func showCrowdedVisibleHint() {
        crowdedVisibleHintDismissTask?.cancel()
        BrowsePanelCrowdingHintCoordinator.show(
            setShowing: { showingCrowdedVisibleHint = $0 },
            setDismissTask: { crowdedVisibleHintDismissTask = $0 },
            dismiss: dismissCrowdedVisibleHint
        )
    }

    @MainActor
    private func dismissCrowdedVisibleHint() {
        BrowsePanelCrowdingHintCoordinator.dismiss(
            cancelDismissTask: { crowdedVisibleHintDismissTask?.cancel() },
            setShowing: { showingCrowdedVisibleHint = $0 }
        )
    }

    @MainActor
    private func enableSecondMenuBarFromHint() {
        BrowsePanelCrowdingHintCoordinator.enableSecondMenuBar(
            manager: menuBarManager,
            dismiss: dismissCrowdedVisibleHint
        )
    }

    @MainActor
    private func refreshApps(force: Bool = false) {
        refreshTask?.cancel()

        guard syncAccessibilityState() else {
            isRefreshing = false
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration

        refreshTask = Task {
            await MainActor.run {
                guard refreshGeneration == generation else { return }
                isRefreshing = true
            }

            if force {
                await MainActor.run {
                    // Force-refresh browse surfaces for new geometry, but keep
                    // the owner cache warm. Repeated panel opens usually do not
                    // need to rediscover the entire owner set from scratch.
                    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
                }
            }

            let classified: SearchClassifiedApps?
            let allModeApps: [RunningApp]
            if isSecondMenuBar || effectiveMode != .all {
                // Zone-only browse surfaces are typically reacting to relayouts
                // or moves where the owner set is stable. Rebuild positions
                // from the known owners first and keep All-mode discovery on
                // its dedicated merged list path.
                classified = await service.refreshKnownClassifiedApps()
                allModeApps = []
            } else {
                classified = nil
                allModeApps = await service.refreshMenuBarApps()
            }

            await MainActor.run {
                guard refreshGeneration == generation else { return }
                defer { self.isRefreshing = false }
                guard !Task.isCancelled else { return }

                if isSecondMenuBar, let classified {
                    visibleApps = classified.visible
                    menuBarApps = classified.hidden
                    alwaysHiddenApps = classified.alwaysHidden
                    SearchWindowController.shared.recordSecondMenuBarClassifiedCounts(
                        visible: classified.visible.count,
                        hidden: classified.hidden.count,
                        alwaysHidden: classified.alwaysHidden.count,
                        forcedRefresh: force
                    )
                    SearchWindowController.shared.refitSecondMenuBarWindowIfNeeded()
                } else {
                    switch effectiveMode {
                    case .hidden:
                        menuBarApps = classified?.hidden ?? []
                    case .visible:
                        menuBarApps = classified?.visible ?? []
                    case .alwaysHidden:
                        menuBarApps = classified?.alwaysHidden ?? []
                    case .all:
                        menuBarApps = allModeApps
                    }
                }
            }
        }
    }
}

#Preview {
    MenuBarSearchView(onDismiss: {})
}
