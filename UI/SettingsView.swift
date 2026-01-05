import SwiftUI
import KeyboardShortcuts
import ServiceManagement

// MARK: - HelpButton

struct HelpButton: View {
    let tip: String
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isShowingPopover) {
            Text(tip)
                .padding()
                .frame(maxWidth: 280)
        }
    }
}

// MARK: - Scroll Position Detection

private struct BottomVisibleKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

// MARK: - GlassGroupBoxStyle

struct GlassGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.headline)
                .foregroundStyle(.primary)

            configuration.content
        }
        .padding(16)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled

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
        .frame(width: 520, height: 480)
        .groupBoxStyle(GlassGroupBoxStyle())
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Startup - FIRST (most important)
                GroupBox {
                    Toggle("Start SaneBar when you log in", isOn: $launchAtLoginEnabled)
                        .onChange(of: launchAtLoginEnabled) { _, newValue in
                            LaunchAtLogin.isEnabled = newValue
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Startup", systemImage: "power")
                }

                // Auto-hide
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-hide after showing", isOn: $menuBarManager.settings.autoRehide)

                        if menuBarManager.settings.autoRehide {
                            HStack {
                                Text("Delay:")
                                Slider(value: $menuBarManager.settings.rehideDelay, in: 1...10, step: 1)
                                Text("\(Int(menuBarManager.settings.rehideDelay)) seconds")
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Auto-hide", systemImage: "eye.slash")
                }

                // How it works - clear step-by-step
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // Step 1: The icons
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your menu bar icons:").fontWeight(.medium)
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .foregroundStyle(.blue)
                                    Text("SaneBar")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "line.diagonal")
                                        .foregroundStyle(.secondary)
                                    Text("Separator")
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Step 2: How to organize
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.draw")
                                    .foregroundStyle(.blue)
                                Text("**⌘+drag** icons to organize them")
                            }
                            Text("• Left of separator = always visible\n• Right of separator = can be hidden")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 28)
                        }

                        Divider()

                        // Step 3: Toggle
                        HStack(spacing: 8) {
                            Image(systemName: "cursorarrow.click.2")
                                .foregroundStyle(.blue)
                            Text("**Click SaneBar icon** to show/hide")
                        }

                        if menuBarManager.hasNotch {
                            Divider()
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("**Notch detected** — keep important icons to the right of SaneBar")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("How it works", systemImage: "questionmark.circle")
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("osascript -e 'tell app \"SaneBar\" to toggle'")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("osascript -e 'tell app \"SaneBar\" to toggle'", forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)

                        Text("Commands: **toggle**, **show hidden**, **hide items**")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("AppleScript & Automation", systemImage: "applescript")
                }
            }
            .padding()
        }
    }

    // MARK: - Advanced Tab

    @State private var isAtBottom = false
    @State private var showAppearanceOptions = false
    @State private var showAutomationOptions = false

    private var advancedTab: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Profiles
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save and restore your settings configurations.")
                            

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
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Divider()

                        Button {
                            newProfileName = SaneBarProfile.generateName(basedOn: savedProfiles.map(\.name))
                            showingSaveProfileAlert = true
                        } label: {
                            Label("Save Current Settings as Profile...", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
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
                        HStack {
                            Text("Keep specific icons always visible.")
                            Spacer()
                            HelpButton(tip: "Enter bundle IDs separated by commas.\n\n⌘+drag those icons LEFT of the separator.\n\nFind bundle ID:\nosascript -e 'id of app \"AppName\"'")
                        }

                        TextField("com.1password.1password, com.apple.Safari", text: Binding(
                            get: { menuBarManager.settings.alwaysVisibleApps.joined(separator: ", ") },
                            set: { newValue in
                                menuBarManager.settings.alwaysVisibleApps = newValue
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Always Visible", systemImage: "pin.fill")
                }

                // Spacers
                GroupBox {
                    HStack {
                        Stepper("Number of spacers: \(menuBarManager.settings.spacerCount)", value: $menuBarManager.settings.spacerCount, in: 0...3)
                        Spacer()
                        HelpButton(tip: "Spacers are small dividers (—) that appear in your menu bar.\n\n⌘+drag them to organize hidden icons into groups.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Spacers", systemImage: "rectangle.split.3x1")
                }

                // Per-Icon Hotkeys
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Quick access shortcuts for specific apps")
                                .foregroundStyle(.secondary)
                            Spacer()
                            HelpButton(tip: "Use the Search apps shortcut (set in Shortcuts tab) to find apps and assign hotkeys.")
                        }

                        if menuBarManager.settings.iconHotkeys.isEmpty {
                            Text("No hotkeys configured")
                                .foregroundStyle(.tertiary)
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
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Icon Hotkeys", systemImage: "keyboard.badge.ellipsis")
                }

                // Menu Bar Appearance - collapsible
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable custom menu bar style", isOn: $menuBarManager.settings.menuBarAppearance.isEnabled)

                        if menuBarManager.settings.menuBarAppearance.isEnabled {
                            DisclosureGroup("Style Options", isExpanded: $showAppearanceOptions) {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Tint Color
                                    HStack {
                                        Text("Tint:")
                                        ColorPicker(
                                            "",
                                            selection: Binding(
                                                get: { Color(hex: menuBarManager.settings.menuBarAppearance.tintColor) },
                                                set: { menuBarManager.settings.menuBarAppearance.tintColor = $0.toHex() }
                                            ),
                                            supportsOpacity: false
                                        )
                                        .labelsHidden()
                                        Spacer()
                                        Text("Opacity:")
                                        Slider(
                                            value: $menuBarManager.settings.menuBarAppearance.tintOpacity,
                                            in: 0.05...0.5,
                                            step: 0.05
                                        )
                                        .frame(width: 80)
                                        Text("\(Int(menuBarManager.settings.menuBarAppearance.tintOpacity * 100))%")
                                            .monospacedDigit()
                                            .frame(width: 35, alignment: .trailing)
                                    }

                                    // Effects row
                                    HStack(spacing: 16) {
                                        Toggle("Shadow", isOn: $menuBarManager.settings.menuBarAppearance.hasShadow)
                                        Toggle("Border", isOn: $menuBarManager.settings.menuBarAppearance.hasBorder)
                                        Toggle("Rounded", isOn: $menuBarManager.settings.menuBarAppearance.hasRoundedCorners)
                                    }

                                    if menuBarManager.settings.menuBarAppearance.hasRoundedCorners {
                                        HStack {
                                            Text("Corner radius:")
                                            Slider(
                                                value: $menuBarManager.settings.menuBarAppearance.cornerRadius,
                                                in: 4...16,
                                                step: 2
                                            )
                                            .frame(width: 100)
                                            Text("\(Int(menuBarManager.settings.menuBarAppearance.cornerRadius))pt")
                                                .monospacedDigit()
                                                .frame(width: 35, alignment: .trailing)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }

                // Automation - grouped triggers with disclosure
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // Simple triggers always visible
                        Toggle("Show on hover", isOn: $menuBarManager.settings.showOnHover)
                        if menuBarManager.settings.showOnHover {
                            HStack {
                                Text("Delay:")
                                    .foregroundStyle(.secondary)
                                Slider(value: $menuBarManager.settings.hoverDelay, in: 0.1...1.0, step: 0.1)
                                    .frame(width: 100)
                                Text("\(menuBarManager.settings.hoverDelay, specifier: "%.1f")s")
                                    .monospacedDigit()
                                    .frame(width: 35)
                            }
                            .padding(.leading, 20)
                        }

                        Toggle("Show when battery is low", isOn: $menuBarManager.settings.showOnLowBattery)

                        // Advanced triggers in disclosure
                        DisclosureGroup("More Triggers", isExpanded: $showAutomationOptions) {
                            VStack(alignment: .leading, spacing: 12) {
                                // App Launch Trigger
                                Toggle("Show when specific apps launch", isOn: $menuBarManager.settings.showOnAppLaunch)
                                if menuBarManager.settings.showOnAppLaunch {
                                    TextField("com.apple.Safari, com.zoom.us", text: Binding(
                                        get: { menuBarManager.settings.triggerApps.joined(separator: ", ") },
                                        set: { newValue in
                                            menuBarManager.settings.triggerApps = newValue
                                                .split(separator: ",")
                                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                                .filter { !$0.isEmpty }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.leading, 20)
                                }

                                // Network Trigger
                                HStack {
                                    Toggle("Show on WiFi networks", isOn: $menuBarManager.settings.showOnNetworkChange)
                                    Spacer()
                                    HelpButton(tip: "Auto-show hidden icons when connecting to specific networks.")
                                }
                                if menuBarManager.settings.showOnNetworkChange {
                                    VStack(alignment: .leading, spacing: 8) {
                                        TextField("Home WiFi, Work Network", text: Binding(
                                            get: { menuBarManager.settings.triggerNetworks.joined(separator: ", ") },
                                            set: { newValue in
                                                menuBarManager.settings.triggerNetworks = newValue
                                                    .split(separator: ",")
                                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                                    .filter { !$0.isEmpty }
                                            }
                                        ))
                                        .textFieldStyle(.roundedBorder)

                                        if let currentSSID = menuBarManager.networkTriggerService.currentSSID {
                                            Button {
                                                if !menuBarManager.settings.triggerNetworks.contains(currentSSID) {
                                                    menuBarManager.settings.triggerNetworks.append(currentSSID)
                                                }
                                            } label: {
                                                Label("Add \"\(currentSSID)\"", systemImage: "plus.circle")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Automation", systemImage: "gearshape.2")
                }

                // Bottom anchor to detect scroll position
                GeometryReader { geo in
                    Color.clear
                        .preference(key: BottomVisibleKey.self, value: geo.frame(in: .named("scroll")).maxY)
                }
                .frame(height: 1)
            }
            .padding()
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(BottomVisibleKey.self) { maxY in
            // Consider "at bottom" when bottom anchor is visible (within ~400pt of top)
            isAtBottom = maxY < 420
        }
        .scrollIndicators(.visible)
        .overlay(alignment: .bottom) {
            // Gradient fade + hint - only show when NOT at bottom
            if !isAtBottom {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, Color(NSColor.windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)

                    HStack {
                        Spacer()
                        Label("Scroll for more", systemImage: "chevron.down")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAtBottom)
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

    @State private var showResetConfirmation = false

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
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(spacing: 8) {
                    Label("100% On-Device", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)

                    Text("No analytics. No telemetry. No network requests. Everything stays on your Mac.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 40)

            HStack(spacing: 16) {
                Link("View on GitHub", destination: URL(string: "https://github.com/stephanjoseph/SaneBar")!)

                Button("Reset to Defaults") {
                    showResetConfirmation = true
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .alert("Reset Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                menuBarManager.resetToDefaults()
                launchAtLoginEnabled = LaunchAtLogin.isEnabled
            }
        } message: {
            Text("This will reset all settings to their defaults. This cannot be undone.")
        }
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
