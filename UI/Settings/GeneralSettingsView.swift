import SwiftUI
import ServiceManagement
import LocalAuthentication

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var launchAtLogin = false
    @State private var isAuthenticating = false  // Prevent duplicate auth prompts
    @State private var isCheckingForUpdates = false  // Debounce update checks

    // Profiles Logic
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingResetAlert = false

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.showDockIcon },
            set: { newValue in
                menuBarManager.settings.showDockIcon = newValue
                ActivationPolicyManager.applyPolicy(showDockIcon: newValue)
            }
        )
    }

    /// Custom binding that requires auth to DISABLE the security setting
    private var requireAuthBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.requireAuthToShowHiddenIcons },
            set: { newValue in
                let currentValue = menuBarManager.settings.requireAuthToShowHiddenIcons

                // Enabling: allow immediately
                if newValue == true && currentValue == false {
                    menuBarManager.settings.requireAuthToShowHiddenIcons = true
                    return
                }

                // Disabling: require auth first (if currently enabled)
                // Guard against duplicate auth requests
                if currentValue == true && newValue == false && !isAuthenticating {
                    isAuthenticating = true
                    Task {
                        let authenticated = await authenticateToDisable()
                        await MainActor.run {
                            if authenticated {
                                menuBarManager.settings.requireAuthToShowHiddenIcons = false
                            }
                            isAuthenticating = false
                        }
                    }
                }
            }
        )
    }

    private func authenticateToDisable() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: "Disable password protection for hidden icons") { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Startup Status
                CompactSection("Startup") {
                    CompactToggle(label: "Start automatically at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            setLaunchAtLogin(newValue)
                        }
                    ))
                    .help("Launch SaneBar when you log in to your Mac")
                    CompactDivider()
                    CompactToggle(label: "Show app in Dock", isOn: showDockIconBinding)
                    .help("Show SaneBar icon in the Dock (menu bar icon always visible)")
                }

                // 2. Privacy (Auth)
                CompactSection("Security") {
                    CompactToggle(label: "Require password to show icons", isOn: requireAuthBinding)
                    .help("Require Touch ID or password to reveal hidden menu bar icons")
                }
                
                // 3. Updates
                CompactSection("Software Updates") {
                    CompactToggle(label: "Check for updates automatically", isOn: $menuBarManager.settings.checkForUpdatesAutomatically)
                    .help("Periodically check for new versions of SaneBar")
                    CompactDivider()
                    CompactRow("Actions") {
                        Button(isCheckingForUpdates ? "Checking…" : "Check Now") {
                            guard !isCheckingForUpdates else { return }
                            isCheckingForUpdates = true
                            menuBarManager.userDidClickCheckForUpdates()
                            // Re-enable after 5 seconds (debounce)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                isCheckingForUpdates = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isCheckingForUpdates)
                        .help("Check for updates right now")
                    }
                }
                
                // 4. Profiles
                CompactSection("Saved Profiles") {
                    if savedProfiles.isEmpty {
                        CompactRow("Saved") {
                            Text("No saved profiles")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(savedProfiles) { profile in
                            CompactRow(profile.name) {
                                HStack {
                                    Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Button("Load") { loadProfile(profile) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    
                                    Button {
                                        deleteProfile(profile)
                                    } label: {
                                        Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            CompactDivider()
                        }
                    }
                    
                    CompactDivider()
                    
                    CompactRow("Current Settings") {
                        Button("Save as Profile…") {
                            newProfileName = SaneBarProfile.generateName(basedOn: savedProfiles.map(\.name))
                            showingSaveProfileAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Save all current settings as a named profile")
                    }
                }

                // 5. Troubleshooting
                CompactSection("Maintenance") {
                    CompactRow("Reset App") {
                        Button("Reset to Defaults…") {
                            showingResetAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                        .help("Reset all settings to factory defaults")
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            checkLaunchAtLogin()
            loadProfiles()
        }
        .alert("Save Profile", isPresented: $showingSaveProfileAlert) {
            TextField("Name", text: $newProfileName)
            Button("Save") { saveCurrentProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your current configuration to restore later.")
        }
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                menuBarManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their defaults. This cannot be undone.")
        }
    }

    // MARK: - Startup Helpers
    
    /// Whether this build is running from a proper install location (not DerivedData).
    /// Debug builds from Xcode run from DerivedData and should never register as login items,
    /// because that pollutes the Background Task Management database with stale paths.
    private var isProperInstall: Bool {
        let path = Bundle.main.bundlePath
        return !path.contains("DerivedData")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard isProperInstall else {
            print("[SaneBar] Skipping login item registration — running from DerivedData")
            launchAtLogin = false
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
            launchAtLogin = !launchAtLogin
        }
    }

    private func checkLaunchAtLogin() {
        do {
            let status = try SMAppService.mainApp.status
            launchAtLogin = (status == .enabled)
        } catch {
            launchAtLogin = false
        }
    }
    
    // MARK: - Profile Helpers
    
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
        let currentAuthEnabled = menuBarManager.settings.requireAuthToShowHiddenIcons
        let profileAuthEnabled = profile.settings.requireAuthToShowHiddenIcons

        // SECURITY: If current auth is ON and profile would turn it OFF, require auth first
        if currentAuthEnabled && !profileAuthEnabled && !isAuthenticating {
            isAuthenticating = true
            Task {
                let authenticated = await authenticateToDisable()
                await MainActor.run {
                    if authenticated {
                        menuBarManager.settings = profile.settings
                        menuBarManager.saveSettings()
                    }
                    isAuthenticating = false
                }
            }
        } else {
            // No auth needed - either auth is off, or profile keeps it on
            menuBarManager.settings = profile.settings
            menuBarManager.saveSettings()
        }
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
