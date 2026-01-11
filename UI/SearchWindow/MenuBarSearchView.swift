import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - MenuBarSearchView

/// SwiftUI view for finding (and clicking) menu bar icons.
struct MenuBarSearchView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case hidden
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hidden: "Hidden"
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

    private var filteredApps: [RunningApp] {
        guard !searchText.isEmpty else { return menuBarApps }
        return menuBarApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            controls

            if isSearchVisible {
                searchField
            }

            Divider()

            content

            footer
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadCachedApps()
            refreshApps()
            startPermissionMonitoring()
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
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

            Text("\(filteredApps.count) \(mode == .hidden ? "hidden" : "icons")")
                .foregroundStyle(.tertiary)

            Spacer()
            Text("Right-click an icon for hotkeys")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
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

            Text(mode == .hidden ? "No hidden icons" : "No menu bar icons")
                .font(.headline)
                .foregroundStyle(.secondary)

            if mode == .hidden {
                Text("All your menu bar icons are visible.\nHide mode only shows icons currently pushed off-screen by SaneBar.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Try Refresh, or grant Accessibility permission.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let padding: CGFloat = 12
            let availableWidth = max(0, proxy.size.width - (padding * 2))
            let availableHeight = max(0, proxy.size.height - (padding * 2))
            let count = filteredApps.count
            let grid = gridSizing(availableWidth: availableWidth, availableHeight: availableHeight, count: count)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(grid.tileSize), spacing: grid.spacing), count: grid.columns),
                    spacing: grid.spacing
                ) {
                    ForEach(filteredApps) { app in
                        MenuBarAppTile(
                            app: app,
                            iconSize: grid.iconSize,
                            tileSize: grid.tileSize,
                            onActivate: { activateApp(app) },
                            onSetHotkey: { hotkeyApp = app }
                        )
                    }
                }
                .padding(padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let spacing: CGFloat = 12

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
                    iconSize: max(24, min(64, floor(tileSize * 0.62))),
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

    var body: some View {
        Button(action: onActivate) {
            ZStack {
                RoundedRectangle(cornerRadius: max(10, tileSize * 0.18))
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
                .frame(width: iconSize, height: iconSize)
            }
            .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(.plain)
        .help(app.name)
        .contextMenu {
            Button("Open") {
                onActivate()
            }
            Button("Set Hotkey…") {
                onSetHotkey()
            }
        }
        .accessibilityLabel(Text(app.name))
    }
}
#Preview {
    MenuBarSearchView(onDismiss: {})
}
