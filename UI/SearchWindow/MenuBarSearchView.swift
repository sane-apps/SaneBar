// swiftlint:disable file_length
import AppKit
import KeyboardShortcuts
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarSearchView")

// MARK: - MenuBarSearchView

/// SwiftUI view for finding (and clicking) menu bar icons.
struct MenuBarSearchView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case hidden
        case visible
        case alwaysHidden
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hidden: "Hidden"
            case .visible: "Visible"
            case .alwaysHidden: "Always Hidden"
            case .all: "All"
            }
        }
    }

    @AppStorage("MenuBarSearchView.mode") private var storedMode: String = Mode.all.rawValue

    @State private var searchText = ""
    @State private var searchTextDebounced = ""
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
    @State private var refreshGeneration = 0
    @State private var postMoveRefreshGeneration = 0

    @State var hotkeyApp: RunningApp?
    @State var proUpsellFeature: ProFeature?
    @State private var showingBrowseHelp = false
    // Fix: Implicit Optional Initialization Violation
    @State private var selectedGroupId: UUID?
    @State private var selectedSmartCategory: AppCategory?
    @State var isCreatingGroup = false
    @State private var newGroupName = ""
    @State var movingAppId: String?
    /// Set after a move completes so the next tab switch does a fresh scan
    @State private var needsPostMoveRefresh = false
    @ObservedObject var menuBarManager = MenuBarManager.shared

    static let resetSearchNotification = Notification.Name("MenuBarSearchView.resetSearch")
    static let setSearchTextNotification = Notification.Name("MenuBarSearchView.setSearchText")

    let service: SearchServiceProtocol
    let onDismiss: () -> Void
    let isSecondMenuBar: Bool

    init(
        isSecondMenuBar: Bool = false,
        service: SearchServiceProtocol = SearchService.shared,
        onDismiss: @escaping () -> Void
    ) {
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

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { storedMode = $0.rawValue }
        )
    }

    private var availableModes: [Mode] {
        Mode.allCases
    }

    /// Categories that have at least one app (for smart group tabs)
    private var availableCategories: [AppCategory] {
        let categories = Set(menuBarApps.map(\.category))
        // Return in a sensible order, filtering to only those with apps
        return AppCategory.allCases.filter { categories.contains($0) }
    }

    private var accentStart: Color {
        Color(red: 0.11, green: 0.32, blue: 0.50)
    }

    private var accentEnd: Color {
        Color(red: 0.11, green: 0.23, blue: 0.39)
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentStart, accentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        .onAppear {
            _ = syncAccessibilityState()
            loadCachedApps()
            refreshApps(force: isSecondMenuBar)
            startPermissionMonitoring()

            // Focus search field on appear for instant searching (Find Icon only)
            if !isSecondMenuBar {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isSearchFieldFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.resetSearchNotification)) { _ in
            searchText = ""
            isSearchVisible = true
            isSearchFieldFocused = true
            refreshApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.setSearchTextNotification)) { notification in
            let text = notification.object as? String ?? ""
            searchText = text
            searchTextDebounced = text
            isSearchVisible = true
            isSearchFieldFocused = true
            refreshApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarIconsDidChange)) { _ in
            // Icons were moved — clear loading state and refresh.
            // Skip loadCachedApps() here: the cache was just invalidated,
            // so reading it would return stale/empty data. Go straight to
            // a fresh AX scan which will populate the list correctly.
            movingAppId = nil
            needsPostMoveRefresh = true
            refreshApps(force: true)
            schedulePostMoveFollowupRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: SearchWindowController.iconMoveDidFinishNotification)) { _ in
            // Some move pipelines finish after the first icon-change event has fired.
            // Force one more converged refresh when move state fully clears.
            movingAppId = nil
            needsPostMoveRefresh = true
            refreshApps(force: true)
        }
        .onChange(of: storedMode) { _, _ in
            if needsPostMoveRefresh {
                // After a move, tabs must do a fresh scan — cache has stale zone data
                needsPostMoveRefresh = false
                refreshApps(force: true)
            } else {
                loadCachedApps()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SearchWindowController.windowDidShowNotification)) { _ in
            // Window reused (not destroyed on close) — reload when re-shown
            _ = syncAccessibilityState()
            loadCachedApps()
            refreshApps(force: isSecondMenuBar)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let nowTrusted = syncAccessibilityState()
            if nowTrusted {
                loadCachedApps()
                refreshApps(force: true)
            }
        }
        .onDisappear {
            permissionMonitorTask?.cancel()
            refreshTask?.cancel()
            postMoveRefreshTask?.cancel()
        }
        .sheet(item: $hotkeyApp) { app in
            HotkeyAssignmentSheet(app: app, onDone: { hotkeyApp = nil })
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
        .onChange(of: filteredApps.count) { _, _ in
            // Reset selection when filter results change
            selectedAppIndex = nil
        }
        .onChange(of: searchText) { _, newValue in
            // Debounce search to save CPU
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                if searchText == newValue {
                    logger.debug("Applying debounced search filter: \(newValue, privacy: .public)")
                    searchTextDebounced = newValue
                }
            }
        }
        .onChange(of: movingAppId) { _, newValue in
            // Auto-clear spinner after 5s in case the notification never fires
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(5))
                if movingAppId == newValue {
                    movingAppId = nil
                }
            }
        }
        .onExitCommand {
            onDismiss()
        }
    }

    // MARK: - Find Icon Body (original layout)

    private var findIconBody: some View {
        VStack(spacing: 0) {
            controls

            groupTabs

            if isSearchVisible {
                searchField
            }

            Divider()

            content

            footer
        }
        .frame(width: 420, height: 520)
        .background { SaneGradientBackground() }
    }

    // MARK: - Second Menu Bar Body

    private var secondMenuBarBody: some View {
        SecondMenuBarView(
            visibleApps: filteredVisible,
            apps: filteredHidden,
            alwaysHiddenApps: filteredAlwaysHidden,
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
            // Moves already emit .menuBarIconsDidChange after cache invalidation.
            // Avoid a second forced refresh path here to reduce scan latency/races.
            onIconMoved: nil,
            searchText: $searchText
        )
    }

    /// Visible apps filtered by search text (for second menu bar inline search)
    private var filteredVisible: [RunningApp] {
        guard !searchTextDebounced.isEmpty else { return visibleApps }
        return visibleApps.filter { $0.name.localizedCaseInsensitiveContains(searchTextDebounced) }
    }

    /// Always-hidden apps filtered by search text
    private var filteredAlwaysHidden: [RunningApp] {
        guard !searchTextDebounced.isEmpty else { return alwaysHiddenApps }
        return alwaysHiddenApps.filter { $0.name.localizedCaseInsensitiveContains(searchTextDebounced) }
    }

    /// Hidden apps filtered by search text (uses existing filteredApps which already filters menuBarApps)
    private var filteredHidden: [RunningApp] {
        filteredApps
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
                guard self.postMoveRefreshGeneration == generation else { return }
                self.refreshApps(force: true)
            }
        }
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
                guard self.refreshGeneration == generation else { return }
                self.isRefreshing = true
            }

            if force {
                await MainActor.run {
                    AccessibilityService.shared.invalidateMenuBarItemCache()
                }
            }

            // Single-pass refresh for all modes — same backend, consistent results.
            let classified = await service.refreshClassifiedApps()
            let allModeApps = effectiveMode == .all && !isSecondMenuBar ? await service.refreshMenuBarApps() : []

            await MainActor.run {
                guard self.refreshGeneration == generation else { return }
                defer { self.isRefreshing = false }
                guard !Task.isCancelled else { return }

                if isSecondMenuBar {
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
                        menuBarApps = classified.hidden
                    case .visible:
                        menuBarApps = classified.visible
                    case .alwaysHidden:
                        menuBarApps = classified.alwaysHidden
                    case .all:
                        menuBarApps = allModeApps
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(availableModes) { segmentMode in
                    modeSegment(segmentMode)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isSearchVisible.toggle()
                }
                if !isSearchVisible {
                    searchText = ""
                }
            } label: {
                Image(systemName: isSearchVisible ? "xmark.circle" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(isSearchVisible ? "Hide filter" : "Filter")

            Button {
                refreshApps(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, isSearchVisible ? 6 : 10)
    }

    private func modeSegment(_ segmentMode: Mode) -> some View {
        let selected = mode == segmentMode
        let isLockedAlwaysHidden = segmentMode == .alwaysHidden && !isAlwaysHiddenEnabled

        return HStack(spacing: 5) {
            Text(segmentMode.title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
            if isLockedAlwaysHidden {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
            }
        }
            .foregroundStyle(selected ? .white : .white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        selected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [accentStart.opacity(0.30), accentEnd.opacity(0.22)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : isLockedAlwaysHidden
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [accentStart.opacity(0.24), accentEnd.opacity(0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.11), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selected
                            ? Color.white.opacity(0.26)
                            : isLockedAlwaysHidden
                                ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
            )
            .shadow(color: selected ? Color.black.opacity(0.2) : .clear, radius: 6, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                if isLockedAlwaysHidden {
                    proUpsellFeature = .alwaysHidden
                } else {
                    storedMode = segmentMode.rawValue
                }
            }
            .dropDestination(for: String.self) { payloads, _ in
                handleZoneDrop(payloads, targetMode: segmentMode)
            }
            .help(
                isLockedAlwaysHidden
                    ? "Pro unlocks the Always Hidden zone, a third tab for icons you never want to see."
                    : segmentMode.title
            )
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" tab - shows everything
                SmartGroupTab(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: selectedGroupId == nil && selectedSmartCategory == nil,
                    action: {
                        selectedGroupId = nil
                        selectedSmartCategory = nil
                    }
                )

                // Smart category tabs (auto-detected from apps)
                ForEach(availableCategories, id: \.self) { category in
                    SmartGroupTab(
                        title: category.rawValue,
                        icon: category.iconName,
                        isSelected: selectedGroupId == nil && selectedSmartCategory == category,
                        action: {
                            selectedGroupId = nil
                            selectedSmartCategory = category
                        }
                    )
                }

                // Divider between smart and custom groups
                if !menuBarManager.settings.iconGroups.isEmpty {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)
                }

                // User-created custom groups (drop targets for icons)
                ForEach(menuBarManager.settings.iconGroups) { group in
                    let groupId = group.id
                    GroupTabButton(
                        title: group.name,
                        isSelected: selectedGroupId == groupId,
                        action: {
                            selectedGroupId = groupId
                            selectedSmartCategory = nil
                        }
                    )
                    .dropDestination(for: String.self) { bundleIds, _ in
                        for payload in bundleIds {
                            addAppToGroup(bundleId: Self.bundleIDFromPayload(payload), groupId: groupId)
                        }
                        return !bundleIds.isEmpty
                    }
                    .contextMenu {
                        Button("Delete Group", role: .destructive) {
                            deleteGroup(groupId: groupId)
                        }
                    }
                }

                // Add custom group button
                Button {
                    if LicenseService.shared.isPro {
                        isCreatingGroup = true
                    } else {
                        proUpsellFeature = .iconGroups
                    }
                } label: {
                    Label("Custom", systemImage: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isCreatingGroup, arrowEdge: .top) {
                    VStack(spacing: 12) {
                        Text("New Custom Group")
                            .font(.headline)
                        TextField("Group name", text: $newGroupName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit {
                                createGroup(named: newGroupName)
                                newGroupName = ""
                                isCreatingGroup = false
                            }
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                newGroupName = ""
                                isCreatingGroup = false
                            }
                            .keyboardShortcut(.cancelAction)
                            Button("Create") {
                                createGroup(named: newGroupName)
                                newGroupName = ""
                                isCreatingGroup = false
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    private let maxGroupCount = 50 // Prevent UI performance issues

    private func createGroup(named name: String) {
        // Validate: trim whitespace, check not empty
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Limit total groups to prevent performance issues
        guard menuBarManager.settings.iconGroups.count < maxGroupCount else {
            // Silently fail - UI should prevent this
            return
        }

        let newGroup = SaneBarSettings.IconGroup(name: trimmedName)
        menuBarManager.settings.iconGroups.append(newGroup)
        menuBarManager.saveSettings()
        selectedGroupId = newGroup.id
    }

    private func deleteGroup(groupId: UUID) {
        // Fresh lookup - group might have been deleted between click and action
        guard menuBarManager.settings.iconGroups.contains(where: { $0.id == groupId }) else { return }

        menuBarManager.settings.iconGroups.removeAll { $0.id == groupId }
        if selectedGroupId == groupId {
            selectedGroupId = nil
        }
        menuBarManager.saveSettings()
    }

    private func addAppToGroup(bundleId: String, groupId: UUID) {
        // Fresh lookup by ID - group object could be stale after drag operation
        guard let index = menuBarManager.settings.iconGroups.firstIndex(where: { $0.id == groupId }) else {
            // Group was deleted during drag - silently ignore
            return
        }

        // Bounds check (defensive - shouldn't be needed but prevents crash)
        guard index < menuBarManager.settings.iconGroups.count else { return }

        // Avoid duplicates
        if !menuBarManager.settings.iconGroups[index].appBundleIds.contains(bundleId) {
            menuBarManager.settings.iconGroups[index].appBundleIds.append(bundleId)
            menuBarManager.saveSettings()
        }
    }

    private func removeAppFromGroup(bundleId: String, groupId: UUID) {
        // Fresh lookup - group might have been modified
        guard let index = menuBarManager.settings.iconGroups.firstIndex(where: { $0.id == groupId }) else { return }

        // Bounds check (defensive)
        guard index < menuBarManager.settings.iconGroups.count else { return }

        menuBarManager.settings.iconGroups[index].appBundleIds.removeAll { $0 == bundleId }
        menuBarManager.saveSettings()
    }

    static func bundleIDFromPayload(_ payload: String) -> String {
        guard let split = payload.range(of: "::") else { return payload }
        return String(payload[..<split.lowerBound])
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.9))
            TextField(
                "Filter by name…",
                text: $searchText,
                prompt: Text("Filter by name…").foregroundStyle(.white.opacity(0.9))
            )
            .textFieldStyle(.plain)
            .font(.body)
            .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var content: some View {
        Group {
            if !hasAccessibility {
                accessibilityPrompt
            } else if menuBarApps.isEmpty {
                if isRefreshing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Scanning menu bar icons…")
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            } else if filteredApps.isEmpty {
                noMatchState
            } else {
                appGrid
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            let label = switch mode {
            case .hidden: "hidden"
            case .visible: "visible"
            case .alwaysHidden: "always hidden"
            case .all: "icons"
            }

            Text("\(filteredApps.count) \(label)")
                .foregroundStyle(.white.opacity(0.9))

            Spacer()
            Button {
                showingBrowseHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .help("How Browse Icons works")
            .accessibilityLabel("Browse actions help")
            .popover(isPresented: $showingBrowseHelp, arrowEdge: .bottom) {
                browseHelpPopover
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05))
    }

    private var browseHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Browse Icons works")
                .font(.system(size: 13, weight: .semibold))
            if LicenseService.shared.isPro {
                Text("Use the Hidden, Visible, and Always Hidden tabs to browse each zone.")
                Text("Drag an icon onto one of those tabs to move it there.")
                Text("Right-click an icon for Move actions.")
            } else {
                Text("Use the Hidden and Visible tabs to browse each zone.")
                Text("Click an icon to open it from the panel.")
                Text("The teal Always Hidden tab is locked in Basic. Upgrade to unlock that third zone.")
            }
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private var accessibilityPrompt: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.97, blue: 0.95),
                            Color(red: 0.35, green: 0.83, blue: 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Grant Access")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.97))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.93))
                        .frame(width: 20)
                    Text("No screen recording.")
                        .foregroundStyle(.white.opacity(0.92))
                }
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.93))
                        .frame(width: 20)
                    Text("No screenshots.")
                        .foregroundStyle(.white.opacity(0.92))
                }
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.93))
                        .frame(width: 20)
                    Text("No data collected.")
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .font(.system(size: 17, weight: .medium))
            .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button("Open Accessibility Settings") {
                    _ = AccessibilityService.shared.openAccessibilitySettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.23, green: 0.66, blue: 0.88),
                                    Color(red: 0.16, green: 0.47, blue: 0.74)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                )
                .shadow(color: Color(red: 0.10, green: 0.28, blue: 0.48).opacity(0.35), radius: 8, x: 0, y: 3)

                Button("Try Again") {
                    _ = syncAccessibilityState(forceProbe: true, promptUser: true)
                    loadCachedApps()
                    refreshApps(force: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            Text(emptyStateSubtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch mode {
        case .hidden: "No hidden icons"
        case .visible: "No visible icons"
        case .alwaysHidden: "No always hidden icons"
        case .all: "No menu bar icons"
        }
    }

    private var emptyStateSubtitle: String {
        switch mode {
        case .hidden:
            "All your menu bar icons are visible.\nUse ⌘-drag to hide icons left of the separator."
        case .visible:
            "All your menu bar icons are hidden.\nUse ⌘-drag to show icons right of the separator."
        case .alwaysHidden:
            "Nothing is in the always-hidden zone.\nUse the context menu to move icons there."
        case .all:
            "Try Refresh, or grant Accessibility permission."
        }
    }

    private var noMatchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.9))

            Text("No matches for \(searchText)")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appGrid: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 8 // Reduced from 12 for larger icons
            let availableWidth = max(0, proxy.size.width - (padding * 2))
            let availableHeight = max(0, proxy.size.height - (padding * 2))
            let count = filteredApps.count
            let grid = SearchGridSizing.compute(availableWidth: availableWidth, availableHeight: availableHeight, count: count)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(grid.tileSize), spacing: grid.spacing), count: grid.columns),
                    alignment: .leading, // Align grid content to left
                    spacing: grid.spacing
                ) {
                    ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                        makeTile(
                            app: app,
                            index: index,
                            grid: grid,
                            duplicateMarker: duplicateMarkers[app.uniqueId]
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading) // Push to top-left
                .padding(padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tile Factory

    /// Extracted to a helper to keep the type checker happy — the tile has many
    /// optional closures and inline ternaries that blow up `appGrid` otherwise.
    @ViewBuilder
    private func makeTile(
        app: RunningApp,
        index: Int,
        grid: SearchGridSizing,
        duplicateMarker: BrowseDuplicateMarker?
    ) -> some View {
        let isPro = LicenseService.shared.isPro
        MenuBarAppTile(
            app: app,
            iconSize: grid.iconSize,
            tileSize: grid.tileSize,
            onActivate: { isRightClick in
                if isRightClick, !isPro {
                    proUpsellFeature = .rightClickFromPanels
                    return
                }
                activateApp(app, isRightClick: isRightClick)
            },
            onSetHotkey: {
                if isPro {
                    hotkeyApp = app
                } else {
                    proUpsellFeature = .perIconHotkeys
                }
            },
            onRemoveFromGroup: selectedGroupId.map { groupId in
                { removeAppFromGroup(bundleId: app.bundleId, groupId: groupId) }
            },
            isHidden: mode == .hidden || mode == .alwaysHidden || (mode == .all && appZone(for: app) != .visible),
            onToggleHidden: isPro ? makeToggleHiddenAction(for: app) : { proUpsellFeature = .zoneMoves },
            onMoveToAlwaysHidden: isPro ? makeMoveToAlwaysHiddenAction(for: app) : { proUpsellFeature = .zoneMoves },
            onMoveToHidden: isPro ? makeMoveToHiddenAction(for: app) : { proUpsellFeature = .zoneMoves },
            isMoving: movingAppId == app.uniqueId,
            isSelected: selectedAppIndex == index,
            isPro: isPro,
            duplicateMarker: duplicateMarker
        )
        .dropDestination(for: String.self) { payloads, _ in
            handleGridReorderDrop(payloads, targetApp: app)
        }
    }
}

#Preview {
    MenuBarSearchView(onDismiss: {})
}
// swiftlint:enable file_length
