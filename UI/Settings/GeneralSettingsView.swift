import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var launchAtLogin = false
    
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
                    CompactDivider()
                    CompactToggle(label: "Show app in Dock", isOn: showDockIconBinding)
                }

                // 2. Privacy (Auth)
                CompactSection("Security") {
                    CompactToggle(label: "Require password to show icons", isOn: $menuBarManager.settings.requireAuthToShowHiddenIcons)
                }
                
                // 3. Updates
                CompactSection("Software Updates") {
                    CompactToggle(label: "Check for updates automatically", isOn: $menuBarManager.settings.checkForUpdatesAutomatically)
                    CompactDivider()
                    CompactRow("Actions") {
                        Button("Check Now") {
                            menuBarManager.userDidClickCheckForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
    
    private func setLaunchAtLogin(_ enabled: Bool) {
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
