import SwiftUI
import KeyboardShortcuts
import ServiceManagement

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case advanced = "Advanced"
        case about = "About"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            advancedTab
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Quick Start
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("How it works", systemImage: "questionmark.circle")
                            .font(.headline)

                        Text("1. **\u{2318}+drag** menu bar icons to rearrange them")
                        Text("2. Icons **left** of SaneBar icon = always visible")
                        Text("3. Icons **right** of SaneBar icon = can be hidden")
                        Text("4. **Click** SaneBar icon to show/hide")
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Auto-hide
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-hide after showing", isOn: $menuBarManager.settings.autoRehide)

                        if menuBarManager.settings.autoRehide {
                            HStack {
                                Text("Hide after")
                                Slider(value: $menuBarManager.settings.rehideDelay, in: 1...10, step: 1)
                                Text("\(Int(menuBarManager.settings.rehideDelay))s")
                                    .monospacedDigit()
                                    .frame(width: 25)
                            }
                            .font(.callout)

                            Text("Hidden icons automatically disappear after this delay.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Auto-hide", systemImage: "eye.slash")
                }

                // Launch at Login
                GroupBox {
                    Toggle("Start SaneBar when you log in", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { LaunchAtLogin.isEnabled = $0 }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Startup", systemImage: "power")
                }
            }
            .padding()
        }
        .onChange(of: menuBarManager.settings) { _, _ in
            menuBarManager.saveSettings()
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Click a field, then press your shortcut keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        KeyboardShortcuts.Recorder("Toggle visibility:", name: .toggleHiddenItems)
                        KeyboardShortcuts.Recorder("Show hidden:", name: .showHiddenItems)
                        KeyboardShortcuts.Recorder("Hide items:", name: .hideItems)
                        KeyboardShortcuts.Recorder("Search apps:", name: .searchMenuBar)
                        KeyboardShortcuts.Recorder("Open Settings:", name: .openSettings)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Global Shortcuts", systemImage: "keyboard")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Control SaneBar from Terminal or automation tools:")
                            .font(.callout)

                        Text("osascript -e 'tell app \"SaneBar\" to toggle'")
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)

                        Text("Commands: **toggle**, **show hidden**, **hide items**")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("AppleScript", systemImage: "applescript")
                }
            }
            .padding()
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Profiles
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save and restore your settings configurations.")
                            .font(.callout)

                        if savedProfiles.isEmpty {
                            HStack {
                                Image(systemName: "square.stack")
                                    .foregroundStyle(.secondary)
                                Text("No saved profiles")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(savedProfiles) { profile in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(profile.name)
                                            .font(.body)
                                        Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Load") {
                                        loadProfile(profile)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Button(role: .destructive) {
                                        deleteProfile(profile)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Divider()

                        Button("Save Current Settings as Profile...") {
                            newProfileName = SaneBarProfile.generateName(basedOn: savedProfiles.map(\.name))
                            showingSaveProfileAlert = true
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Profiles", systemImage: "square.stack")
                }
                .onAppear { loadProfiles() }
                .alert("Save Profile", isPresented: $showingSaveProfileAlert) {
                    TextField("Profile name", text: $newProfileName)
                    Button("Save") { saveCurrentProfile() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Enter a name for this profile.")
                }

                // Always Visible Apps
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Keep specific menu bar icons always visible, even when hiding others.")
                            .font(.callout)

                        TextField("App bundle IDs", text: Binding(
                            get: { menuBarManager.settings.alwaysVisibleApps.joined(separator: ", ") },
                            set: { newValue in
                                menuBarManager.settings.alwaysVisibleApps = newValue
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("**How to set up:**")
                            Text("1. Enter bundle IDs above (e.g., com.1password.1password)")
                            Text("2. \u{2318}+drag those icons to the LEFT of the separator (⧵)")
                            Text("3. They'll stay visible when you hide other icons")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Find bundle ID: osascript -e 'id of app \"AppName\"'")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Always Visible", systemImage: "pin.fill")
                }

                // Spacers
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("Number of spacers: \(menuBarManager.settings.spacerCount)", value: $menuBarManager.settings.spacerCount, in: 0...3)

                        Text("Spacers are small dividers you can drag around to organize your hidden icons into groups. Use \u{2318}+drag to position them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Spacers", systemImage: "rectangle.split.3x1")
                }

                // Per-Icon Hotkeys
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Assign keyboard shortcuts to quickly access specific app icons.")
                            .font(.callout)

                        if menuBarManager.settings.iconHotkeys.isEmpty {
                            HStack {
                                Image(systemName: "keyboard.badge.ellipsis")
                                    .foregroundStyle(.secondary)
                                Text("No hotkeys configured")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
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
                                .padding(.vertical, 2)
                            }
                        }

                        Text("Use **Search apps** shortcut to find apps and add hotkeys from there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Per-Icon Hotkeys", systemImage: "keyboard.badge.ellipsis")
                }

                // App Launch Triggers
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show hidden items when apps launch", isOn: $menuBarManager.settings.showOnAppLaunch)

                        if menuBarManager.settings.showOnAppLaunch {
                            TextField("App bundle IDs", text: Binding(
                                get: { menuBarManager.settings.triggerApps.joined(separator: ", ") },
                                set: { newValue in
                                    menuBarManager.settings.triggerApps = newValue
                                        .split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Text("Example: com.apple.Safari, com.zoom.us\nFind bundle ID: osascript -e 'id of app \"AppName\"'")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("App Triggers", systemImage: "app.badge")
                }
            }
            .padding()
        }
        .onChange(of: menuBarManager.settings) { _, _ in
            menuBarManager.saveSettings()
        }
    }

    // MARK: - Helpers

    /// Get app name from bundle ID
    private func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        // Fallback: extract last component of bundle ID
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    // MARK: - Profile Management

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

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("SaneBar")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(spacing: 8) {
                    Label("100% On-Device", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)

                    Text("No analytics. No telemetry. No network requests. Everything stays on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 40)

            Link("View on GitHub", destination: URL(string: "https://github.com/stephanjoseph/SaneBar")!)
                .font(.callout)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Launch at Login Helper

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[SaneBar] Launch at login error: \(error)")
            }
        }
    }
}

#Preview {
    SettingsView()
}
