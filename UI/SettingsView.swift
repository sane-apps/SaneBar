import SwiftUI
import KeyboardShortcuts

// MARK: - SettingsView

/// Main settings view for SaneBar
struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showingPermissionAlert = false
    @State private var selectedTab: SettingsTab = .items
    @State private var searchText = ""
    @State private var showWelcomeBanner = !UserDefaults.standard.hasSeenWelcome
    @State private var dropTargetSection: StatusItemModel.ItemSection?

    enum SettingsTab: String, CaseIterable {
        case items = "Items"
        case shortcuts = "Shortcuts"
        case behavior = "Behavior"
        case profiles = "Profiles"
        case usage = "Usage"
    }

    /// Items filtered by search text
    private var filteredItems: [StatusItemModel] {
        if searchText.isEmpty {
            return menuBarManager.statusItems
        }
        return menuBarManager.statusItems.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if menuBarManager.permissionService.permissionState != .granted {
                permissionRequestContent
            } else {
                mainContent
            }
        }
        .frame(minWidth: 340, minHeight: 480)
        // BUG-007 fix: Wire showingPermissionAlert from PermissionService to UI alert
        .onReceive(NotificationCenter.default.publisher(for: .showPermissionAlert)) { _ in
            showingPermissionAlert = true
        }
        .alert("Accessibility Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open System Settings") {
                menuBarManager.permissionService.openAccessibilitySettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(PermissionService.permissionInstructions)
        }
    }

    // MARK: - Permission Request

    private var permissionRequestContent: some View {
        PermissionRequestView(
            permissionService: menuBarManager.permissionService
        ) {
            Task {
                await menuBarManager.scan()
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Welcome banner for first-time users
            if showWelcomeBanner {
                WelcomeBanner(isVisible: $showWelcomeBanner) {
                    UserDefaults.standard.hasSeenWelcome = true
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Tab content
            switch selectedTab {
            case .items:
                itemsTabContent
            case .shortcuts:
                shortcutsTabContent
            case .behavior:
                behaviorTabContent
            case .profiles:
                ProfilesView(menuBarManager: menuBarManager)
            case .usage:
                UsageStatsView(menuBarManager: menuBarManager)
            }

            Divider()

            // Footer
            footerView
        }
        .onAppear {
            menuBarManager.startAutoRefresh()
        }
        .onDisappear {
            menuBarManager.stopAutoRefresh()
        }
    }

    // MARK: - Items Tab

    private var itemsTabContent: some View {
        VStack(spacing: 0) {
            headerView

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search items...", text: $searchText)
                    .textFieldStyle(.plain)
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
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if menuBarManager.statusItems.isEmpty {
                emptyStateView
            } else if filteredItems.isEmpty {
                noSearchResultsView
            } else {
                itemListView
            }
        }
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No items match '\(searchText)'")
                .foregroundStyle(.secondary)
            Button("Clear Search") {
                searchText = ""
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTabContent: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Hidden Items:", name: .toggleHiddenItems)
                    .help("Show or hide the hidden menu bar section")

                KeyboardShortcuts.Recorder("Show Hidden Items:", name: .showHiddenItems)
                    .help("Temporarily show hidden items")

                KeyboardShortcuts.Recorder("Hide Items:", name: .hideItems)
                    .help("Hide items immediately")

                KeyboardShortcuts.Recorder("Open Settings:", name: .openSettings)
                    .help("Open SaneBar settings window")
            } header: {
                Text("Global Keyboard Shortcuts")
            } footer: {
                Text("Click a field and press your desired key combination. These shortcuts work system-wide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Behavior Tab

    private var behaviorTabContent: some View {
        Form {
            Section {
                Toggle("Auto-hide after delay", isOn: $menuBarManager.settings.autoRehide)

                if menuBarManager.settings.autoRehide {
                    HStack {
                        Text("Delay:")
                        Slider(value: $menuBarManager.settings.rehideDelay, in: 1...10, step: 0.5)
                        Text("\(menuBarManager.settings.rehideDelay, specifier: "%.1f")s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            } header: {
                Text("Hidden Section")
            }

            Section {
                Toggle("Show on hover", isOn: $menuBarManager.settings.showOnHover)

                if menuBarManager.settings.showOnHover {
                    HStack {
                        Text("Hover delay:")
                        Slider(value: $menuBarManager.settings.hoverDelay, in: 0.1...1.0, step: 0.1)
                        Text("\(menuBarManager.settings.hoverDelay, specifier: "%.1f")s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            } header: {
                Text("Hover Behavior")
            }

            Section {
                Toggle("Remember which icons I use", isOn: $menuBarManager.settings.analyticsEnabled)
                    .help("Stored locally on your Mac - never sent anywhere")

                Toggle("Smart suggestions", isOn: $menuBarManager.settings.smartSuggestionsEnabled)
                    .help("Suggest what to hide based on your usage")
            } header: {
                Text("Local Usage Data")
            } footer: {
                Text("All data stays on your Mac. Nothing is ever sent to us or anyone else.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: menuBarManager.settings) { _, _ in
            menuBarManager.saveSettings()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Items")
                    .font(.headline)

                if let message = menuBarManager.lastScanMessage {
                    // Show scan success message
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(message)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                } else if menuBarManager.isScanning {
                    // Show scanning status
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Scanning...")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    // Show auto-refresh indicator
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.tertiary)
                        Text("\(menuBarManager.statusItems.count) items • auto-refreshing")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: menuBarManager.lastScanMessage)

            Spacer()
        }
        .padding()
    }

    // MARK: - Item List

    private var itemListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(StatusItemModel.ItemSection.allCases, id: \.self) { section in
                    sectionView(for: section)
                }
            }
            .padding()
        }
    }

    private func sectionView(for section: StatusItemModel.ItemSection) -> some View {
        let items = filteredItems.filter { $0.section == section }

        return Group {
            if !items.isEmpty || section == .alwaysVisible {
                VStack(alignment: .leading, spacing: 8) {
                    // Section header with explanation
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: section.systemImage)
                            Text(section.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(items.count)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)

                        // Explanatory subtitle
                        Text(sectionSubtitle(for: section))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Items (with drag source)
                    if items.isEmpty {
                        Text("No items — drag items here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(items) { item in
                            StatusItemRow(item: item) { newSection in
                                menuBarManager.updateItem(item, section: newSection)
                            }
                            .draggable(item)
                        }
                    }
                }
                .padding(.bottom, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(dropTargetSection == section ? Color.accentColor.opacity(0.1) : Color.clear)
                        .animation(.easeInOut(duration: 0.15), value: dropTargetSection)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            dropTargetSection == section ? Color.accentColor : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                        )
                        .animation(.easeInOut(duration: 0.15), value: dropTargetSection)
                )
                .dropDestination(for: StatusItemModel.self) { droppedItems, _ in
                    for item in droppedItems {
                        menuBarManager.updateItem(item, section: section)
                    }
                    dropTargetSection = nil
                    return true
                } isTargeted: { isTargeted in
                    dropTargetSection = isTargeted ? section : nil
                }
            }
        }
    }

    /// Returns explanatory subtitle for each section
    private func sectionSubtitle(for section: StatusItemModel.ItemSection) -> String {
        switch section {
        case .alwaysVisible:
            return "These icons stay in your menu bar all the time"
        case .hidden:
            return "Click the SaneBar icon to reveal these when needed"
        case .collapsed:
            return "These icons are completely hidden from view"
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Menu Bar Items Found")
                .font(.headline)

            if let error = menuBarManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if menuBarManager.isScanning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning...")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Auto-scanning every 5 seconds...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Import/Export buttons
            Button {
                exportConfiguration()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export your SaneBar configuration")

            Button {
                importConfiguration()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import a SaneBar configuration")

            Spacer()

            // Privacy indicator - always visible for peace of mind
            CompactPrivacyBadge()

            Spacer()

            // Show welcome guide button
            Button {
                withAnimation {
                    showWelcomeBanner = true
                }
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show welcome guide")

            Button("Quit SaneBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }

    // MARK: - Import/Export

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SaneBar-Config.json"
        panel.title = "Export SaneBar Configuration"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try menuBarManager.persistenceService.exportConfiguration()
                try data.write(to: url)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.title = "Import SaneBar Configuration"
        panel.message = "Select a SaneBar configuration file"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let (items, settings) = try menuBarManager.persistenceService.importConfiguration(from: data)

                // Apply imported configuration
                try menuBarManager.persistenceService.saveItemConfigurations(items)
                try menuBarManager.persistenceService.saveSettings(settings)

                // Reload
                Task {
                    await menuBarManager.scan()
                }
            } catch {
                print("Import failed: \(error)")
            }
        }
    }
}

// MARK: - UniformTypeIdentifiers

import UniformTypeIdentifiers

// MARK: - Preview

#Preview {
    SettingsView()
}
