import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - MenuBarSearchView

/// SwiftUI view for finding hidden menu bar icons
struct MenuBarSearchView: View {
    @State private var searchText = ""
    @State private var selectedIndex: Int?
    @State private var menuBarApps: [RunningApp] = []
    @State private var isLoading = true
    @State private var hasAccessibility = false
    @State private var permissionMonitorTask: Task<Void, Never>?

    let service: SearchServiceProtocol
    let onDismiss: () -> Void

    init(service: SearchServiceProtocol = SearchService.shared, onDismiss: @escaping () -> Void) {
        self.service = service
        self.onDismiss = onDismiss
    }

    var filteredApps: [RunningApp] {
        if searchText.isEmpty {
            return menuBarApps
        }
        return menuBarApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Find Hidden Icon")
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

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type to filter...", text: $searchText)
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
            .padding(.bottom, 8)

            Divider()

            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading menu bar icons...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasAccessibility {
                accessibilityPrompt
            } else if menuBarApps.isEmpty {
                emptyState
            } else if filteredApps.isEmpty {
                noMatchState
            } else {
                appList
            }
        }
        .frame(width: 360, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadApps()
            startPermissionMonitoring()
        }
        .onDisappear {
            permissionMonitorTask?.cancel()
        }
    }

    /// Monitor for permission changes - auto-reload when user grants permission
    private func startPermissionMonitoring() {
        permissionMonitorTask = Task { @MainActor in
            for await granted in AccessibilityService.shared.permissionStream(includeInitial: false) {
                if granted && !hasAccessibility {
                    // Permission was just granted - reload the app list
                    hasAccessibility = true
                    isLoading = true
                    loadApps()
                }
            }
        }
    }

    // MARK: - Subviews

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
                    // Request again to show system prompt
                    _ = AccessibilityService.shared.requestAccessibility()
                }
                .buttonStyle(.bordered)

                Button("Try Again") {
                    isLoading = true
                    loadApps()
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

            Text("No hidden icons!")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("All your menu bar icons are visible.\nDrag icons to the left of the **/** separator to hide them.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
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

    private var appList: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: $selectedIndex) {
                    ForEach(Array(filteredApps.enumerated()), id: \.offset) { index, app in
                        AppRow(app: app, isSelected: selectedIndex == index) {
                            activateApp(app)
                        }
                        .tag(index)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .onChange(of: selectedIndex) { _, newIndex in
                    if let index = newIndex {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }

            Divider()

            // Footer hint
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.down")
                    Text("navigate")
                }
                HStack(spacing: 4) {
                    Image(systemName: "return")
                    Text("open")
                }
                Spacer()
                Text("\(filteredApps.count) hidden")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let index = selectedIndex, index < filteredApps.count {
                activateApp(filteredApps[index])
            }
            return .handled
        }
    }

    // MARK: - Actions

    private func loadApps() {
        Task {
            // Request accessibility - this shows system prompt if not granted
            hasAccessibility = AccessibilityService.shared.requestAccessibility()

            if hasAccessibility {
                // Get ONLY the hidden menu bar apps (pushed off-screen by SaneBar)
                menuBarApps = await service.getHiddenMenuBarApps()
            }
            isLoading = false

            // Select first item by default
            if !menuBarApps.isEmpty {
                selectedIndex = 0
            }
        }
    }

    private func moveSelection(by delta: Int) {
        let count = filteredApps.count
        guard count > 0 else { return }

        if let current = selectedIndex {
            selectedIndex = max(0, min(count - 1, current + delta))
        } else {
            selectedIndex = delta > 0 ? 0 : count - 1
        }
    }

    private func activateApp(_ app: RunningApp) {
        Task {
            await service.activate(app: app)
            onDismiss()
        }
    }
}

// MARK: - AppRow

struct AppRow: View {
    let app: RunningApp
    let isSelected: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "app.fill")
                        .font(.title2)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }

                Text(app.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MenuBarSearchView(onDismiss: {})
}
