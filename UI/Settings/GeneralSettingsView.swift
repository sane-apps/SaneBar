import AppKit
import KeyboardShortcuts
import LocalAuthentication
import os.log
import ServiceManagement
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.sanebar.app", category: "Settings")

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var launchAtLogin = false
    @State private var isAuthenticating = false // Prevent duplicate auth prompts
    @State private var isCheckingForUpdates = false // Debounce update checks

    // Profiles Logic
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingResetAlert = false

    private struct SettingsExport: Codable {
        let version: Int
        let exportedAt: Date
        let settings: SaneBarSettings
    }

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
                if newValue == true, currentValue == false {
                    menuBarManager.settings.requireAuthToShowHiddenIcons = true
                    return
                }

                // Disabling: require auth first (if currently enabled)
                // Guard against duplicate auth requests
                if currentValue == true, newValue == false, !isAuthenticating {
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

                // 3. Browse Icons
                CompactSection("Browse Icons") {
                    CompactRow("Opens as") {
                        Picker("", selection: Binding(
                            get: { menuBarManager.settings.useSecondMenuBar },
                            set: { newValue in
                                menuBarManager.settings.useSecondMenuBar = newValue
                                SearchWindowController.shared.resetWindow()
                            }
                        )) {
                            Text("Icon Panel").tag(false)
                            Text("Second Menu Bar").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                    .help("Icon Panel: Search, hotkeys, and icon management. Second Menu Bar: A bar below the menu bar showing your hidden icons.")
                    if menuBarManager.settings.useSecondMenuBar {
                        CompactDivider()
                        CompactToggle(
                            label: "Include visible icons",
                            isOn: $menuBarManager.settings.secondMenuBarShowVisible
                        )
                        .help("Show visible (non-hidden) icons in the Second Menu Bar for organizing. Off by default since visible icons are already in the menu bar.")
                    }
                    CompactDivider()
                    CompactRow("Shortcut") {
                        KeyboardShortcuts.Recorder(for: .searchMenuBar)
                    }
                    .help("Customizable keyboard shortcut to open Browse Icons")
                }

                // 4. Updates
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

                // 5. Profiles
                CompactSection("Saved Profiles") {
                    if savedProfiles.isEmpty {
                        CompactRow("Saved") {
                            Text("No saved profiles")
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    } else {
                        ForEach(savedProfiles) { profile in
                            CompactRow(profile.name) {
                                HStack {
                                    Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary.opacity(0.7))

                                    Button("Load") { loadProfile(profile) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                    Button {
                                        deleteProfile(profile)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.primary.opacity(0.6))
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

                // 6. Data
                CompactSection("Data") {
                    CompactRow("Settings") {
                        Button("Export Settings...") {
                            exportSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Import Settings...") {
                            importSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    CompactDivider()

                    CompactRow("Migration") {
                        HStack(spacing: 8) {
                            Button("Import Bartender...") {
                                importBartenderSettings()
                            }
                            Button("Import Ice...") {
                                importIceSettings()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // 7. Troubleshooting
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
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
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
        if currentAuthEnabled, !profileAuthEnabled, !isAuthenticating {
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

    // MARK: - Export / Import

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SaneBar-settings.json"
        panel.title = "Export Settings"

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("📤 Export cancelled")
            return
        }

        let export = SettingsExport(version: 1, exportedAt: Date(), settings: menuBarManager.settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(export)
            try data.write(to: url)
            settingsLogger.log("📤 Exported settings to \(url.lastPathComponent, privacy: .public)")
        } catch {
            settingsLogger.error("📤 Export failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Export Failed", error: error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Settings"

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("📥 Import cancelled")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let export = try? decoder.decode(SettingsExport.self, from: data) {
                settingsLogger.log("📥 Importing wrapped settings from \(url.lastPathComponent, privacy: .public)")
                applyImportedSettings(export.settings)
            } else {
                settingsLogger.log("📥 Importing raw settings from \(url.lastPathComponent, privacy: .public)")
                let settings = try decoder.decode(SaneBarSettings.self, from: data)
                applyImportedSettings(settings)
            }
        } catch {
            settingsLogger.error("📥 Import failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Import Failed", error: error)
        }
    }

    private func applyImportedSettings(_ settings: SaneBarSettings) {
        let currentAuthEnabled = menuBarManager.settings.requireAuthToShowHiddenIcons
        let importedAuthEnabled = settings.requireAuthToShowHiddenIcons

        if currentAuthEnabled, !importedAuthEnabled, !isAuthenticating {
            isAuthenticating = true
            Task {
                let authenticated = await authenticateToDisable()
                await MainActor.run {
                    if authenticated {
                        menuBarManager.settings = settings
                        menuBarManager.saveSettings()
                        settingsLogger.log("📥 Imported settings applied after auth")
                    } else {
                        settingsLogger.log("📥 Import blocked by auth (no changes applied)")
                    }
                    isAuthenticating = false
                }
            }
        } else {
            menuBarManager.settings = settings
            menuBarManager.saveSettings()
            settingsLogger.log("📥 Imported settings applied")
        }
    }

    // MARK: - Bartender Import

    private func importBartenderSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Bartender Settings"
        panel.message = "Select your Bartender plist (usually com.surteesstudios.Bartender.plist in ~/Library/Preferences)"
        panel.prompt = "Import"
        if let prefsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences") {
            panel.directoryURL = prefsURL
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("🍸 Bartender import cancelled")
            return
        }

        Task { @MainActor in
            do {
                let summary = try await BartenderImportService.importSettings(from: url, menuBarManager: menuBarManager)
                showInfo(title: "Bartender Import Complete", message: summary.description)
            } catch {
                showError(title: "Bartender Import Failed", error: error)
            }
        }
    }

    // MARK: - Ice Import

    private func importIceSettings() {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.jordanbaird.Ice.plist")

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Ice Settings"
        panel.message = "Select your Ice plist (usually com.jordanbaird.Ice.plist in ~/Library/Preferences)"
        panel.prompt = "Import"
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            panel.directoryURL = defaultPath.deletingLastPathComponent()
            panel.nameFieldStringValue = defaultPath.lastPathComponent
        } else if let prefsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences") {
            panel.directoryURL = prefsURL
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("🧊 Ice import cancelled")
            return
        }

        do {
            let summary = try IceImportService.importSettings(from: url, menuBarManager: menuBarManager)
            showInfo(title: "Ice Import Complete", message: summary.description)
        } catch {
            showError(title: "Ice Import Failed", error: error)
        }
    }

    private func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
