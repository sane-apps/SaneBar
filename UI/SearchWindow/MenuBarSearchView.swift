import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - Visual Effect Background

/// NSVisualEffectView wrapper for proper vibrancy on older macOS
private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active  // Keep effect active even when not key window
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - MenuBarSearchView

/// SwiftUI view for finding (and clicking) menu bar icons.
struct MenuBarSearchView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case hidden
        case visible
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hidden: "Hidden"
            case .visible: "Visible"
            case .all: "All"
            }
        }
    }

    @AppStorage("MenuBarSearchView.mode") private var storedMode: String = Mode.all.rawValue

    @State private var searchText = ""
    @State private var isSearchVisible = false

    @State private var menuBarApps: [RunningApp] = []
    @State private var isRefreshing = false
    @State private var hasAccessibility = false
    @State private var permissionMonitorTask: Task<Void, Never>?
    @State private var refreshTask: Task<Void, Never>?

    @State private var hotkeyApp: RunningApp?
    @State private var selectedGroupId: UUID? = nil  // nil = show smart groups, non-nil = custom group
    @State private var selectedSmartCategory: AppCategory? = nil  // nil = "All" within smart view
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var showMoveInstructions = false
    @State private var moveInstructionsForHidden = false  // true if moving FROM hidden TO visible
    @ObservedObject private var menuBarManager = MenuBarManager.shared

    let service: SearchServiceProtocol
    let onDismiss: () -> Void

    init(service: SearchServiceProtocol = SearchService.shared, onDismiss: @escaping () -> Void) {
        self.service = service
        self.onDismiss = onDismiss
    }

    private var mode: Mode {
        Mode(rawValue: storedMode) ?? .all
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { Mode(rawValue: storedMode) ?? .all },
            set: { storedMode = $0.rawValue }
        )
    }

    /// Categories that have at least one app (for smart group tabs)
    private var availableCategories: [AppCategory] {
        let categories = Set(menuBarApps.map { $0.category })
        // Return in a sensible order, filtering to only those with apps
        return AppCategory.allCases.filter { categories.contains($0) }
    }

    private var filteredApps: [RunningApp] {
        var apps = menuBarApps

        // Filter by custom group (takes precedence)
        if let groupId = selectedGroupId,
           let group = menuBarManager.settings.iconGroups.first(where: { $0.id == groupId }) {
            let bundleIds = Set(group.appBundleIds)
            apps = apps.filter { bundleIds.contains($0.id) }
        }
        // Filter by smart category (when no custom group selected)
        else if let category = selectedSmartCategory {
            apps = apps.filter { $0.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            apps = apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return apps
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            controls

            // Group tabs (always visible so users can create groups)
            groupTabs

            if isSearchVisible {
                searchField
            }

            Divider()

            content

            footer
        }
        .frame(width: 420, height: 520)
        .background {
            // NSVisualEffectView with popover material for solid frosted appearance
            VisualEffectBackground(
                material: .popover,
                blendingMode: .behindWindow
            )
        }
        .onAppear {
            loadCachedApps()
            refreshApps()
            startPermissionMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarIconsDidChange)) { _ in
            // Icons were moved - refresh the list
            loadCachedApps()
            refreshApps(force: true)
        }
        .onChange(of: storedMode) { _, _ in
            loadCachedApps()
            refreshApps()
        }
        .onDisappear {
            permissionMonitorTask?.cancel()
            refreshTask?.cancel()
        }
        .sheet(item: $hotkeyApp) { app in
            hotkeySheet(for: app)
        }
        .alert(
            moveInstructionsForHidden ? "Move to Visible" : "Move to Hidden",
            isPresented: $showMoveInstructions
        ) {
            Button("OK") { }
        } message: {
            if moveInstructionsForHidden {
                Text("To show this icon:\n\n⌘-drag it to the RIGHT of the / separator in your menu bar.")
            } else {
                Text("To hide this icon:\n\n⌘-drag it to the LEFT of the / separator in your menu bar.")
            }
        }
    }

    /// Monitor for permission changes - auto-reload when user grants permission
    private func startPermissionMonitoring() {
        permissionMonitorTask = Task { @MainActor in
            for await granted in AccessibilityService.shared.permissionStream(includeInitial: false) {
                if granted && !hasAccessibility {
                    // Permission was just granted - reload the app list
                    hasAccessibility = true
                    loadCachedApps()
                    refreshApps(force: true)
                }
            }
        }
    }

    private func loadCachedApps() {
        hasAccessibility = AccessibilityService.shared.isGranted

        guard hasAccessibility else {
            menuBarApps = []
            return
        }

        switch mode {
        case .hidden:
            menuBarApps = service.cachedHiddenMenuBarApps()
        case .visible:
            menuBarApps = service.cachedVisibleMenuBarApps()
        case .all:
            menuBarApps = service.cachedMenuBarApps()
        }
    }

    private func refreshApps(force: Bool = false) {
        refreshTask?.cancel()

        guard hasAccessibility else {
            isRefreshing = false
            return
        }

        refreshTask = Task {
            await MainActor.run {
                isRefreshing = true
            }

            if force {
                await MainActor.run {
                    AccessibilityService.shared.invalidateMenuBarItemCache()
                }
            }

            let refreshed: [RunningApp]
            switch mode {
            case .hidden:
                refreshed = await service.refreshHiddenMenuBarApps()
            case .visible:
                refreshed = await service.refreshVisibleMenuBarApps()
            case .all:
                refreshed = await service.refreshMenuBarApps()
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                menuBarApps = refreshed
                isRefreshing = false
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Find Icon")
                .font(.headline)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("", selection: modeBinding) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isSearchVisible.toggle()
                }
                if !isSearchVisible {
                    searchText = ""
                }
            } label: {
                Image(systemName: isSearchVisible ? "xmark.circle" : "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help(isSearchVisible ? "Hide filter" : "Filter")

            Button {
                refreshApps(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal)
        .padding(.bottom, isSearchVisible ? 6 : 10)
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
                        for bundleId in bundleIds {
                            addAppToGroup(bundleId: bundleId, groupId: groupId)
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
                    isCreatingGroup = true
                } label: {
                    Label("Custom", systemImage: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
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

    private let maxGroupCount = 50  // Prevent UI performance issues

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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by name…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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

            Text("\(filteredApps.count) \(mode == .hidden ? "hidden" : mode == .visible ? "visible" : "icons")")
                .foregroundStyle(.tertiary)

            Spacer()
            Text("Right-click an icon for hotkeys")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05))
    }

    private var accessibilityPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Accessibility Permission Needed")
                .font(.headline)

            Text("SaneBar needs Accessibility access to see menu bar icons.\n\nA system dialog should have appeared. Enable SaneBar in System Settings, then try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    // Actually open System Settings to Accessibility pane
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("Try Again") {
                    loadCachedApps()
                    refreshApps(force: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(emptyStateSubtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch mode {
        case .hidden: "No hidden icons"
        case .visible: "No visible icons"
        case .all: "No menu bar icons"
        }
    }

    private var emptyStateSubtitle: String {
        switch mode {
        case .hidden:
            "All your menu bar icons are visible.\nUse ⌘-drag to hide icons left of the separator."
        case .visible:
            "All your menu bar icons are hidden.\nUse ⌘-drag to show icons right of the separator."
        case .all:
            "Try Refresh, or grant Accessibility permission."
        }
    }

    private var noMatchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No matches for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appGrid: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 8  // Reduced from 12 for larger icons
            let availableWidth = max(0, proxy.size.width - (padding * 2))
            let availableHeight = max(0, proxy.size.height - (padding * 2))
            let count = filteredApps.count
            let grid = gridSizing(availableWidth: availableWidth, availableHeight: availableHeight, count: count)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(grid.tileSize), spacing: grid.spacing), count: grid.columns),
                    alignment: .leading,  // Align grid content to left
                    spacing: grid.spacing
                ) {
                    ForEach(filteredApps) { app in
                        MenuBarAppTile(
                            app: app,
                            iconSize: grid.iconSize,
                            tileSize: grid.tileSize,
                            onActivate: { activateApp(app) },
                            onSetHotkey: { hotkeyApp = app },
                            onRemoveFromGroup: selectedGroupId.map { groupId in
                                { removeAppFromGroup(bundleId: app.id, groupId: groupId) }
                            },
                            isHidden: mode == .hidden,
                            // Only show move button in Hidden/Visible views (not All)
                            onToggleHidden: mode == .all ? nil : {
                                // Capture values before async work to avoid race conditions
                                let bundleID = app.id
                                let menuExtraId = app.menuExtraIdentifier  // For Control Center items
                                let toHidden = (mode == .visible)

                                menuBarManager.moveIcon(bundleID: bundleID, menuExtraId: menuExtraId, toHidden: toHidden)

                                // Delay refresh to let the CGEvent drag complete (~200ms for move)
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(400))
                                    refreshApps(force: true)
                                }
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)  // Push to top-left
                .padding(padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct GridSizing {
        let columns: Int
        let tileSize: CGFloat
        let iconSize: CGFloat
        let spacing: CGFloat
    }

    private func gridSizing(availableWidth: CGFloat, availableHeight: CGFloat, count: Int) -> GridSizing {
        let spacing: CGFloat = 8  // Reduced from 12 for tighter grid

        let minTile: CGFloat = 44
        let maxTile: CGFloat = 112

        guard count > 0 else {
            return GridSizing(columns: 1, tileSize: 84, iconSize: 52, spacing: spacing)
        }

        let maxColumnsByWidth = max(1, Int((availableWidth + spacing) / (minTile + spacing)))
        let maxColumns = min(maxColumnsByWidth, count)

        let height = max(1, availableHeight)

        var best = GridSizing(columns: 1, tileSize: minTile, iconSize: 26, spacing: spacing)
        var bestScore: CGFloat = -1_000_000

        for columns in 1...maxColumns {
            let rawTile = (availableWidth - (CGFloat(columns - 1) * spacing)) / CGFloat(columns)
            let tileSize = max(minTile, min(maxTile, floor(rawTile)))

            let rows = Int(ceil(Double(count) / Double(columns)))
            let contentHeight = (CGFloat(rows) * tileSize) + (CGFloat(max(0, rows - 1)) * spacing)
            let overflow = max(0, contentHeight - height)

            let score: CGFloat
            if overflow <= 0 {
                // Fits without scrolling: prefer a more horizontal grid (fewer rows)
                // while still keeping tiles reasonably large.
                score = 10_000 + tileSize - (CGFloat(rows) * 4) + (CGFloat(columns) * 0.5)
            } else {
                // Prefer less scrolling for very large icon counts.
                score = tileSize - ((overflow / height) * 24)
            }

            if score > bestScore {
                bestScore = score
                best = GridSizing(
                    columns: columns,
                    tileSize: tileSize,
                    iconSize: max(28, min(72, floor(tileSize * 0.72))),  // Larger icons (was 0.62)
                    spacing: spacing
                )
            }
        }

        return best
    }

    private func activateApp(_ app: RunningApp) {
        Task {
            await service.activate(app: app)
            onDismiss()
        }
    }

    private func hotkeySheet(for app: RunningApp) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Set hotkey")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    hotkeyApp = nil
                }
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }

                Text(app.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Hotkey:")
                    .foregroundStyle(.secondary)

                KeyboardShortcuts.Recorder(for: IconHotkeysService.shortcutName(for: app.id))
                    .onChange(of: KeyboardShortcuts.getShortcut(for: IconHotkeysService.shortcutName(for: app.id))) { _, newShortcut in
                        if let shortcut = newShortcut {
                            menuBarManager.settings.iconHotkeys[app.id] = KeyboardShortcutData(
                                keyCode: UInt16(shortcut.key?.rawValue ?? 0),
                                modifiers: shortcut.modifiers.rawValue
                            )
                        } else {
                            menuBarManager.settings.iconHotkeys.removeValue(forKey: app.id)
                        }

                        menuBarManager.saveSettings()
                        IconHotkeysService.shared.registerHotkeys(from: menuBarManager.settings)
                    }

                Spacer()
            }
        }
        .padding(16)
        .frame(width: 360)
    }

}

// MARK: - Tile

private struct MenuBarAppTile: View {
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

    var body: some View {
        Button(action: onActivate) {
            VStack(spacing: 4) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: max(8, iconSize * 0.18))
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))

                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
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
        }
        .buttonStyle(.plain)
        .draggable(app.id)  // Enable drag with bundle ID as payload
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

// MARK: - Smart Group Tab (with icon)

private struct SmartGroupTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? .white.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Group Tab Button (custom groups)

private struct GroupTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MenuBarSearchView(onDismiss: {})
}
