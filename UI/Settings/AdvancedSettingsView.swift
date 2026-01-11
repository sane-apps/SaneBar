import SwiftUI
import AppKit

struct AdvancedSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""

    var body: some View {
        Form {
            // 1. Privacy - important, people care about this
            Section {
                Toggle("Require Touch ID or password to reveal", isOn: $menuBarManager.settings.requireAuthToShowHiddenIcons)
            } header: {
                Text("Privacy")
            } footer: {
                Text("You'll need to authenticate before hidden icons appear.")
            }

            // 2. Auto-show triggers - moderately common
            Section {
                Toggle("When battery is low", isOn: $menuBarManager.settings.showOnLowBattery)

                Toggle("When certain apps open", isOn: $menuBarManager.settings.showOnAppLaunch)
                if menuBarManager.settings.showOnAppLaunch {
                    AppPickerView(
                        selectedBundleIDs: $menuBarManager.settings.triggerApps,
                        title: "Show icons when these apps open"
                    )
                }

                Toggle("On specific WiFi networks", isOn: $menuBarManager.settings.showOnNetworkChange)
                if menuBarManager.settings.showOnNetworkChange {
                    TextField("Network names (comma-separated)", text: Binding(
                        get: { menuBarManager.settings.triggerNetworks.joined(separator: ", ") },
                        set: { menuBarManager.settings.triggerNetworks = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    if let ssid = menuBarManager.networkTriggerService.currentSSID {
                        Button("Add current network (\(ssid))") {
                            if !menuBarManager.settings.triggerNetworks.contains(ssid) {
                                menuBarManager.settings.triggerNetworks.append(ssid)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Automatically show hidden icons")
            }

            // 3. Look & feel - for customizers
            Section {
                Toggle("Custom menu bar style", isOn: $menuBarManager.settings.menuBarAppearance.isEnabled)
                if menuBarManager.settings.menuBarAppearance.isEnabled {
                    // Liquid Glass toggle - only show on macOS 26+
                    if MenuBarAppearanceSettings.supportsLiquidGlass {
                        Toggle("Use Liquid Glass effect", isOn: $menuBarManager.settings.menuBarAppearance.useLiquidGlass)
                    }
                    
                    ColorPicker("Tint color", selection: Binding(
                        get: { Color(hex: menuBarManager.settings.menuBarAppearance.tintColor) },
                        set: { menuBarManager.settings.menuBarAppearance.tintColor = $0.toHex() }
                    ), supportsOpacity: false)
                    Stepper("Tint strength: \(Int(menuBarManager.settings.menuBarAppearance.tintOpacity * 100))%",
                            value: $menuBarManager.settings.menuBarAppearance.tintOpacity,
                            in: 0.05...0.5, step: 0.05)
                    Toggle("Add shadow", isOn: $menuBarManager.settings.menuBarAppearance.hasShadow)
                    Toggle("Add border", isOn: $menuBarManager.settings.menuBarAppearance.hasBorder)
                    Toggle("Rounded corners", isOn: $menuBarManager.settings.menuBarAppearance.hasRoundedCorners)
                    if menuBarManager.settings.menuBarAppearance.hasRoundedCorners {
                        Stepper("Corner size: \(Int(menuBarManager.settings.menuBarAppearance.cornerRadius))pt",
                                value: $menuBarManager.settings.menuBarAppearance.cornerRadius,
                                in: 4...16, step: 2)
                    }
                }

                Stepper("Extra dividers: \(menuBarManager.settings.spacerCount)", value: $menuBarManager.settings.spacerCount, in: 0...12)

                if menuBarManager.settings.spacerCount > 0 {
                    Picker("Divider style", selection: $menuBarManager.settings.spacerStyle) {
                        Text("Line").tag(SaneBarSettings.SpacerStyle.line)
                        Text("Dot").tag(SaneBarSettings.SpacerStyle.dot)
                    }
                    .pickerStyle(.segmented)

                    Picker("Divider width", selection: $menuBarManager.settings.spacerWidth) {
                        Text("Compact").tag(SaneBarSettings.SpacerWidth.compact)
                        Text("Normal").tag(SaneBarSettings.SpacerWidth.normal)
                        Text("Wide").tag(SaneBarSettings.SpacerWidth.wide)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Appearance")
            } footer: {
                if MenuBarAppearanceSettings.supportsLiquidGlass {
                    Text("Liquid Glass uses macOS Tahoe's new translucent material. Dividers help organize icons.")
                } else {
                    Text("Dividers help you visually group icons. ⌘+drag to position them.")
                }
            }

            // 5. Icon hotkeys - rare
            if !menuBarManager.settings.iconHotkeys.isEmpty {
                Section {
                    ForEach(Array(menuBarManager.settings.iconHotkeys.keys.sorted()), id: \.self) { bundleID in
                        HStack {
                            Text(appName(for: bundleID))
                            Spacer()
                            Button(role: .destructive) {
                                menuBarManager.settings.iconHotkeys.removeValue(forKey: bundleID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("App shortcuts")
                } footer: {
                    Text("Press Search, pick an app, and assign a key to add more.")
                }
            }

            // 6. Profiles - very rare, power user
            Section {
                if savedProfiles.isEmpty {
                    Text("No saved settings")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Load") { loadProfile(profile) }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) { deleteProfile(profile) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Save current settings…") {
                    newProfileName = SaneBarProfile.generateName(basedOn: savedProfiles.map(\.name))
                    showingSaveProfileAlert = true
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Saved settings")
            } footer: {
                Text("Save your setup to restore later or share between Macs.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadProfiles() }
        .alert("Save Settings", isPresented: $showingSaveProfileAlert) {
            TextField("Name", text: $newProfileName)
            Button("Save") { saveCurrentProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this configuration a name.")
        }
        .onChange(of: menuBarManager.settings) { _, _ in
            menuBarManager.saveSettings()
        }
    }

    // MARK: - Helpers

    private func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private func loadProfiles() {
        do {
            savedProfiles = try PersistenceService.shared.listProfiles()
        } catch {
            print("[SaneBar] Failed to load profiles: \(error)")
        }
    }

    private func saveCurrentProfile() {
        guard !newProfileName.isEmpty else { return }
        var profile = SaneBarProfile(name: newProfileName, settings: menuBarManager.settings)
        profile.modifiedAt = Date()
        do {
            try PersistenceService.shared.saveProfile(profile)
            loadProfiles()
        } catch {
            print("[SaneBar] Failed to save profile: \(error)")
        }
    }

    private func loadProfile(_ profile: SaneBarProfile) {
        menuBarManager.settings = profile.settings
        menuBarManager.saveSettings()
    }

    private func deleteProfile(_ profile: SaneBarProfile) {
        do {
            try PersistenceService.shared.deleteProfile(id: profile.id)
            loadProfiles()
        } catch {
            print("[SaneBar] Failed to delete profile: \(error)")
        }
    }
}

// MARK: - App Picker

/// A picker that shows running apps instead of requiring bundle IDs
struct AppPickerView: View {
    @Binding var selectedBundleIDs: [String]
    let title: String

    @State private var showingPicker = false
    @State private var availableApps: [AppInfo] = []
    @State private var searchText = ""

    struct AppInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let icon: NSImage?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedBundleIDs.isEmpty {
                Text("None selected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 6) {
                        Text(appName(for: bundleID))
                        Spacer()
                        Button {
                            selectedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Add App…") {
                loadApps()
                showingPicker = true
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingPicker) {
            appPickerSheet
        }
    }

    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingPicker = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredApps) { app in
                Button {
                    toggleApp(app)
                } label: {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app")
                                .frame(width: 24, height: 24)
                        }
                        Text(app.name)
                        Spacer()
                        if selectedBundleIDs.contains(app.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 350, height: 400)
    }

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return availableApps }
        return availableApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func toggleApp(_ app: AppInfo) {
        if selectedBundleIDs.contains(app.id) {
            selectedBundleIDs.removeAll { $0 == app.id }
        } else {
            selectedBundleIDs.append(app.id)
        }
    }

    private func loadApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
            .compactMap { app -> AppInfo? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AppInfo(id: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
            }

        var seen = Set<String>()
        availableApps = running.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
