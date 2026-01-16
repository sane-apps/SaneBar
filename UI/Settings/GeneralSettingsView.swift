import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var launchAtLogin = false
    
    // Profiles Logic
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.showDockIcon },
            set: { newValue in
                menuBarManager.settings.showDockIcon = newValue
                ActivationPolicyManager.applyPolicy(showDockIcon: newValue)
            }
        )
    }

    private var hideMainIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.hideMainIcon },
            set: { newValue in
                menuBarManager.settings.hideMainIcon = newValue
                menuBarManager.updateMainIconVisibility()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Startup Status
                CompactSection("Startup & Visibility") {
                    CompactToggle(label: "Open SaneBar when I log in", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            setLaunchAtLogin(newValue)
                        }
                    ))
                    CompactDivider()
                    CompactToggle(label: "Show SaneBar icon in Dock", isOn: showDockIconBinding)
                    CompactDivider()
                    CompactToggle(label: "Hide Menu Bar icon (divider only)", isOn: hideMainIconBinding)
                }

                // 2. Privacy (Auth)
                CompactSection("Privacy") {
                    CompactToggle(label: "Require ID/Password to show hidden icons", isOn: $menuBarManager.settings.requireAuthToShowHiddenIcons)
                }
                
                // 3. Updates
                CompactSection("Updates") {
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
                CompactSection("Profiles") {
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
