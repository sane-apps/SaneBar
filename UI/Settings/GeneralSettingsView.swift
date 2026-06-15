import AppKit
import LocalAuthentication
import os.log
import SaneUI
import ServiceManagement
import SwiftUI

private let settingsLogger = Logger(subsystem: "com.sanebar.app", category: "Settings")

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var licenseService = LicenseService.shared
    @State private var updateCheckFrequency: UpdateCheckFrequency = .daily
    @State private var isCheckingForUpdates = false
    @State private var isAuthenticating = false // Prevent duplicate auth prompts
    @State private var proUpsellFeature: ProFeature?

    // Profiles Logic
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingResetAlert = false
    @State private var showBrowseRowCustomization = false
    @State private var pendingImport: PendingImport?

    private enum PendingImport: Identifiable {
        case saneBar(SaneBarSettingsImportPayload, SaneBarImportPreviewPlan)
        case bartender(URL, SaneBarImportPreviewPlan)

        var id: UUID {
            preview.id
        }

        var preview: SaneBarImportPreviewPlan {
            switch self {
            case let .saneBar(_, preview), let .bartender(_, preview):
                preview
            }
        }
    }

    typealias BrowseLeftClickMode = GeneralSettingsBrowseLeftClickMode
    typealias SecondMenuBarPreset = GeneralSettingsSecondMenuBarPreset

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.showDockIcon },
            set: { newValue in
                menuBarManager.settings.showDockIcon = newValue
                SaneActivationPolicy.applyPolicy(showDockIcon: newValue)
            }
        )
    }

    private var leftClickModeBinding: Binding<BrowseLeftClickMode> {
        Binding(
            get: { menuBarManager.settings.leftClickOpensBrowseIcons ? .openBrowseIcons : .toggleHidden },
            set: { mode in
                menuBarManager.settings.leftClickOpensBrowseIcons = (mode == .openBrowseIcons)
                normalizeBrowseModeSettingsForCurrentPlan()
            }
        )
    }

    private var secondMenuBarPresetBinding: Binding<SecondMenuBarPreset> {
        Binding(
            get: {
                SecondMenuBarPreset.resolve(
                    showVisible: menuBarManager.settings.secondMenuBarShowVisible,
                    showAlwaysHidden: menuBarManager.settings.secondMenuBarShowAlwaysHidden
                )
            },
            set: { preset in
                applySecondMenuBarPreset(preset)
            }
        )
    }

    private var liveLayoutChecksBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.layoutMode == .live },
            set: { enabled in
                Task { @MainActor in
                    _ = await menuBarManager.profileWorkflow.setLayoutMode(enabled ? .live : .stability, reason: "control")
                }
            }
        )
    }

    private var layoutModeDescription: String {
        layoutModeHelp(menuBarManager.settings.layoutMode)
    }

    private func layoutModeHelp(_ mode: SaneBarSettings.LayoutMode) -> String {
        switch mode {
        case .stability:
            "Stability repairs only at startup or when you click Arrange Now. This is the calm default."
        case .live:
            "Live checks after wake and display changes if your icons drift."
        }
    }

    /// Custom binding that requires auth to disable the security setting.
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
                // 1. Browse Icons
                GeneralSettingsBrowseSection(
                    menuBarManager: menuBarManager,
                    licenseService: licenseService,
                    showBrowseRowCustomization: $showBrowseRowCustomization,
                    leftClickMode: leftClickModeBinding,
                    secondMenuBarPreset: secondMenuBarPresetBinding,
                    applyBrowseIconsViewSelection: applyBrowseIconsViewSelection,
                    showProUpsell: { proUpsellFeature = $0 }
                )

                // 2. Everyday Hiding
                GeneralSettingsHidingSection(
                    menuBarManager: menuBarManager,
                    licenseService: licenseService,
                    showProUpsell: { proUpsellFeature = $0 }
                )

                // 3. Profiles                // 3. Profiles — Pro
                CompactSection("Saved Profiles") {
                    if licenseService.isPro {
                        if savedProfiles.isEmpty {
                            CompactRow("Saved") {
                                Text("No saved profiles")
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        } else {
                            ForEach(savedProfiles) { profile in
                                CompactRow(profile.name) {
                                    HStack {
                                        Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.92))

                                        Button("Load") { loadProfile(profile) }
                                            .buttonStyle(ChromeActionButtonStyle())
                                            .controlSize(.small)

                                        Button {
                                            deleteProfile(profile)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.white.opacity(0.9))
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
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)
                            .help("Save your current settings, layout, and custom icon as a named profile")
                        }
                    } else {
                        proGatedRow(feature: .settingsProfiles, label: "Save and load configurations")
                    }
                }

                // 4. Layout Repair
                CompactSection("Layout Repair") {
                    CompactToggle(
                        label: "Repair after wake or display changes",
                        isOn: liveLayoutChecksBinding
                    )
                    .saneHelp("Live checks after wake/display changes. Turn it on if icons drift after wake, monitor changes, or fast user switching. Leave it off for the calmer default Stability mode.")
                    CompactDivider()
                    CompactRow("Repair Mode") {
                        StatusBadge(menuBarManager.settings.layoutMode.rawValue, color: .cyan, icon: "slider.horizontal.3")
                            .saneHelp(layoutModeDescription)
                    }
                    SaneInlineHelp(layoutModeDescription)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                    CompactDivider()
                    CompactRow("Arrange Now") {
                        Button("Run") {
                            Task { @MainActor in
                                _ = await menuBarManager.profileWorkflow.repairMenuBarHealth(reason: "control")
                            }
                        }
                        .buttonStyle(ChromeActionButtonStyle())
                        .controlSize(.small)
                        .saneHelp("Runs an immediate layout check, refreshes menu bar anchor positions, and repairs SaneBar's visible, hidden, and always-hidden groups if needed.")
                    }
                }

                // 5. Security — Pro
                CompactSection("Security") {
                    if licenseService.isPro {
                        CompactToggle(label: "Touch ID to unlock hidden icons", isOn: requireAuthBinding)
                            .help("Require Touch ID (or password on Macs without Touch ID) to reveal hidden menu bar icons")
                    } else {
                        proGatedRow(feature: .touchIDProtection, label: "Touch ID to unlock hidden icons")
                    }
                }

                // 6. Startup Status
                CompactSection("Startup") {
                    SaneLoginItemToggle()
                    CompactDivider()
                    SaneDockIconToggle(showDockIcon: showDockIconBinding)
                }

                // 7. Updates
                if licenseService.distributionChannel.supportsInAppUpdates {
                    softwareUpdatesSection
                }

                // 8. Data — Pro
                CompactSection("Data") {
                    if licenseService.isPro {
                        CompactRow("Settings") {
                            Button("Export Settings...") {
                                exportSettings()
                            }
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)

                            Button("Import Settings...") {
                                importSettings()
                            }
                            .buttonStyle(ChromeActionButtonStyle())
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
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)
                        }
                    } else {
                        proGatedRow(feature: .exportImport, label: "Export, import, and migrate settings")
                    }
                }

                // 9. Troubleshooting
                CompactSection("Maintenance") {
                    CompactRow("Reset App") {
                        Button("Reset to Defaults…") {
                            showingResetAlert = true
                        }
                        .buttonStyle(ChromeActionButtonStyle(destructive: true))
                        .controlSize(.small)
                        .help("Reset all settings to factory defaults")
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            normalizeBrowseModeSettingsForCurrentPlan()
            loadProfiles()
            updateCheckFrequency = menuBarManager.updateService.updateCheckFrequency
        }
        .onChange(of: updateCheckFrequency) { _, newValue in
            menuBarManager.updateService.updateCheckFrequency = newValue
        }
        .alert("Save Profile", isPresented: $showingSaveProfileAlert) {
            TextField("Name", text: $newProfileName)
            Button("Save") { saveCurrentProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your current settings, layout, and icon to restore later.")
        }
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                menuBarManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their defaults. This cannot be undone.")
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
        .sheet(item: $pendingImport) { pending in
            ImportPreviewSheet(
                plan: pending.preview,
                onCancel: { pendingImport = nil },
                onImport: { applyPendingImport(pending) }
            )
        }
    }

    // MARK: - Pro Gating Helper

    private var softwareUpdatesSection: some View {
        CompactSection("Software Updates") {
            CompactToggle(
                label: "Check for updates automatically",
                isOn: $menuBarManager.settings.checkForUpdatesAutomatically
            )
            .help("Periodically check for new versions")

            CompactDivider()

            CompactRow("Check frequency") {
                HStack(spacing: 6) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        ChromeSegmentedChoiceButton(
                            title: frequency.title,
                            isSelected: updateCheckFrequency == frequency
                        ) {
                            updateCheckFrequency = frequency
                        }
                    }
                }
                .frame(width: 170)
                .opacity(menuBarManager.settings.checkForUpdatesAutomatically ? 1 : 0.55)
                .disabled(!menuBarManager.settings.checkForUpdatesAutomatically)
            }
            .help("Choose how often automatic update checks run")

            CompactDivider()

            CompactRow("Actions") {
                Button(isCheckingForUpdates ? "Checking…" : "Check Now") {
                    triggerManualUpdateCheck()
                }
                .buttonStyle(ChromeActionButtonStyle())
                .controlSize(.small)
                .disabled(isCheckingForUpdates)
                .help("Check for updates right now")
            }
        }
    }

    private func applyBrowseIconsViewSelection(_ useSecondMenuBar: Bool) {
        let wasBrowseVisible = SearchWindowController.shared.isVisible
        menuBarManager.settings.useSecondMenuBar = useSecondMenuBar
        // Icon Panel is the primary browse workflow. Keep always-hidden available there.
        if !useSecondMenuBar, licenseService.isPro, !menuBarManager.settings.alwaysHiddenSectionEnabled {
            menuBarManager.settings.alwaysHiddenSectionEnabled = true
        }
        normalizeBrowseModeSettingsForCurrentPlan()

        let nextMode: SearchWindowMode = useSecondMenuBar ? .secondMenuBar : .findIcon
        if wasBrowseVisible {
            SearchWindowController.shared.transition(to: nextMode)
        } else {
            SearchWindowController.shared.resetWindow()
        }
    }

    private func normalizeBrowseModeSettingsForCurrentPlan() {
        let normalizedLeftClick = MenuBarActionWorkflow.normalizedLeftClickOpensBrowseIcons(
            isPro: licenseService.isPro,
            useSecondMenuBar: menuBarManager.settings.useSecondMenuBar,
            leftClickOpensBrowseIcons: menuBarManager.settings.leftClickOpensBrowseIcons
        )
        if normalizedLeftClick != menuBarManager.settings.leftClickOpensBrowseIcons {
            menuBarManager.settings.leftClickOpensBrowseIcons = normalizedLeftClick
        }

        let normalizedRows = MenuBarActionWorkflow.normalizedSecondMenuBarRows(
            isPro: licenseService.isPro,
            showVisible: menuBarManager.settings.secondMenuBarShowVisible,
            showAlwaysHidden: menuBarManager.settings.secondMenuBarShowAlwaysHidden
        )
        if normalizedRows.showVisible != menuBarManager.settings.secondMenuBarShowVisible {
            menuBarManager.settings.secondMenuBarShowVisible = normalizedRows.showVisible
        }
        if normalizedRows.showAlwaysHidden != menuBarManager.settings.secondMenuBarShowAlwaysHidden {
            menuBarManager.settings.secondMenuBarShowAlwaysHidden = normalizedRows.showAlwaysHidden
        }
    }

    private func applySecondMenuBarPreset(_ preset: SecondMenuBarPreset) {
        switch preset {
        case .minimal:
            menuBarManager.settings.secondMenuBarShowVisible = false
            menuBarManager.settings.secondMenuBarShowAlwaysHidden = false
            showBrowseRowCustomization = false
        case .balanced:
            menuBarManager.settings.secondMenuBarShowVisible = true
            menuBarManager.settings.secondMenuBarShowAlwaysHidden = false
            showBrowseRowCustomization = false
        case .power:
            menuBarManager.settings.secondMenuBarShowVisible = true
            menuBarManager.settings.secondMenuBarShowAlwaysHidden = true
            if !menuBarManager.settings.alwaysHiddenSectionEnabled {
                menuBarManager.settings.alwaysHiddenSectionEnabled = true
            }
        }
    }

    private func proGatedRow(feature: ProFeature, label: String) -> some View {
        CompactRow(label) {
            Button {
                proUpsellFeature = feature
            } label: {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func triggerManualUpdateCheck() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        menuBarManager.actionWorkflow.userDidClickCheckForUpdates()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            isCheckingForUpdates = false
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
        var profile = SaneBarProfile(
            name: newProfileName,
            settings: menuBarManager.settings,
            layoutSnapshot: StatusBarController.captureLayoutSnapshot(),
            customIconSnapshot: PersistenceService.shared.makeCustomIconSnapshot()
        )
        profile.modifiedAt = Date()
        do {
            try PersistenceService.shared.saveProfile(profile)
            loadProfiles()
        } catch {
            print("[SaneBar] Failed to save profile: \(error)")
        }
    }

    private func loadProfile(_ profile: SaneBarProfile) {
        menuBarManager.profileWorkflow.applyProfile(
            profile,
            preserveAutomation: false,
            preserveProtectedSettings: true,
            reason: "settings"
        )
        loadProfiles()
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

        let export = SaneBarSettingsArchive(
            version: 2,
            exportedAt: Date(),
            settings: menuBarManager.settings,
            layoutSnapshot: StatusBarController.captureLayoutSnapshot(),
            customIconSnapshot: PersistenceService.shared.makeCustomIconSnapshot(),
            savedProfiles: savedProfiles
        )
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

            switch try SaneBarSettingsArchive.decodeImportPayload(from: data, using: decoder) {
            case let .archive(export):
                settingsLogger.log("📥 Importing wrapped settings from \(url.lastPathComponent, privacy: .public)")
                let payload = SaneBarSettingsImportPayload.archive(export)
                pendingImport = .saneBar(payload, payload.previewPlan(fileName: url.lastPathComponent))
            case let .legacySettings(settings):
                settingsLogger.log("📥 Importing raw settings from \(url.lastPathComponent, privacy: .public)")
                let payload = SaneBarSettingsImportPayload.legacySettings(settings)
                pendingImport = .saneBar(payload, payload.previewPlan(fileName: url.lastPathComponent))
            }
        } catch {
            settingsLogger.error("📥 Import failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Import Failed", error: error)
        }
    }

    private func applyPendingImport(_ pending: PendingImport) {
        pendingImport = nil

        switch pending {
        case let .saneBar(payload, _):
            switch payload {
            case let .archive(export):
                applyConfiguration(
                    settings: export.settings,
                    layoutSnapshot: export.layoutSnapshot,
                    customIconSnapshot: export.customIconSnapshot,
                    importedProfiles: export.savedProfiles,
                    successLog: "📥 Imported archive applied"
                )
            case let .legacySettings(settings):
                applyConfiguration(
                    settings: settings,
                    layoutSnapshot: nil,
                    customIconSnapshot: nil,
                    importedProfiles: nil,
                    successLog: "📥 Imported legacy settings applied"
                )
            }

        case let .bartender(url, _):
            Task { @MainActor in
                do {
                    let summary = try await BartenderImportService.importSettings(from: url, menuBarManager: menuBarManager)
                    showInfo(title: "Bartender Import Complete", message: summary.description)
                } catch {
                    showError(title: "Bartender Import Failed", error: error)
                }
            }
        }
    }

    private func applyConfiguration(
        settings: SaneBarSettings,
        layoutSnapshot: SaneBarLayoutSnapshot?,
        customIconSnapshot: SaneBarCustomIconSnapshot?,
        importedProfiles: [SaneBarProfile]?,
        successLog: String
    ) {
        let currentAuthEnabled = menuBarManager.settings.requireAuthToShowHiddenIcons
        let importedAuthEnabled = settings.requireAuthToShowHiddenIcons

        if currentAuthEnabled, !importedAuthEnabled, !isAuthenticating {
            isAuthenticating = true
            Task {
                let authenticated = await authenticateToDisable()
                await MainActor.run {
                    if authenticated {
                        applyConfigurationAfterAuth(
                            settings: settings,
                            layoutSnapshot: layoutSnapshot,
                            customIconSnapshot: customIconSnapshot,
                            importedProfiles: importedProfiles,
                            successLog: successLog
                        )
                    } else {
                        settingsLogger.log("📥 Import blocked by auth (no changes applied)")
                    }
                    isAuthenticating = false
                }
            }
        } else {
            applyConfigurationAfterAuth(
                settings: settings,
                layoutSnapshot: layoutSnapshot,
                customIconSnapshot: customIconSnapshot,
                importedProfiles: importedProfiles,
                successLog: successLog
            )
        }
    }

    private func applyConfigurationAfterAuth(
        settings: SaneBarSettings,
        layoutSnapshot: SaneBarLayoutSnapshot?,
        customIconSnapshot: SaneBarCustomIconSnapshot?,
        importedProfiles: [SaneBarProfile]?,
        successLog: String
    ) {
        do {
            _ = menuBarManager.profileWorkflow.createLayoutRescueRestorePoint(reason: "pre-import")
            if let importedProfiles {
                try PersistenceService.shared.upsertProfiles(importedProfiles)
            }
            if let customIconSnapshot {
                try PersistenceService.shared.applyCustomIconSnapshot(customIconSnapshot)
            }
            if let layoutSnapshot {
                StatusBarController.applyLayoutSnapshot(layoutSnapshot)
            }

            menuBarManager.settings = settings.preservingLocalLifecycleState(from: menuBarManager.settings)
            try menuBarManager.saveSettingsStrict()
            menuBarManager.restoreStatusItemLayoutIfNeeded()
            loadProfiles()
            settingsLogger.log("\(successLog, privacy: .public)")
        } catch {
            settingsLogger.error("📥 Configuration apply failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Import Failed", error: error)
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
                let preview = try await BartenderImportPreviewPlanner.previewImport(from: url)
                pendingImport = .bartender(url, preview)
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
