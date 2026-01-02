import SwiftUI
import KeyboardShortcuts

// MARK: - SettingsView

/// Main settings view for SaneBar
struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showingPermissionAlert = false
    @State private var selectedTab: SettingsTab = .items
    @State private var searchText = ""

    enum SettingsTab: String, CaseIterable {
        case items = "Items"
        case shortcuts = "Shortcuts"
        case behavior = "Behavior"
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
        .frame(minWidth: 450, minHeight: 400)
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
            case .usage:
                UsageStatsView(menuBarManager: menuBarManager)
            }

            Divider()

            // Footer
            footerView
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
                Toggle("Track usage analytics", isOn: $menuBarManager.settings.analyticsEnabled)
                    .help("Track click counts to suggest frequently used items")

                Toggle("Smart suggestions", isOn: $menuBarManager.settings.smartSuggestionsEnabled)
                    .help("Suggest items to hide based on usage patterns")
            } header: {
                Text("Analytics")
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
                    Text("\(menuBarManager.statusItems.count) items discovered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: menuBarManager.lastScanMessage)

            Spacer()

            Button {
                Task {
                    await menuBarManager.scan()
                }
            } label: {
                if menuBarManager.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(menuBarManager.isScanning)
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
                    // Section header
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

                    // Items
                    if items.isEmpty {
                        Text("No items")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(items) { item in
                            StatusItemRow(item: item) { newSection in
                                menuBarManager.updateItem(item, section: newSection)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
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
            } else {
                Text("Click Refresh to scan for items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Scan Now") {
                Task {
                    await menuBarManager.scan()
                }
            }
            .buttonStyle(.borderedProminent)

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

            Text("Right-click items to change section")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

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
