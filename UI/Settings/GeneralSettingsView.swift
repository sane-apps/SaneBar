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
    @State private var isAuthenticating = false // Prevent duplicate auth prompts
    @State private var proUpsellFeature: ProFeature?

    // Profiles Logic
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingResetAlert = false
    @State private var showingLicenseEntry = false
    @State private var showBrowseRowCustomization = false

    enum BrowseLeftClickMode: String, CaseIterable, Identifiable {
        case toggleHidden
        case openBrowseIcons

        var id: String { rawValue }
        var title: String {
            switch self {
            case .toggleHidden: "Toggle Hidden"
            case .openBrowseIcons: "Open Browse"
            }
        }
    }

    enum SecondMenuBarPreset: String, CaseIterable, Identifiable {
        case minimal
        case balanced
        case power

        var id: String { rawValue }
        var title: String {
            switch self {
            case .minimal: "Minimal"
            case .balanced: "Balanced"
            case .power: "Power"
            }
        }
    }

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

    private var browseDestinationLabel: String {
        menuBarManager.settings.useSecondMenuBar ? "Second Menu Bar" : "Icon Panel"
    }

    private var browseOpenActionLabel: String {
        menuBarManager.settings.useSecondMenuBar ? "Open Second Menu Bar" : "Open Icon Panel"
    }

    private func leftClickModeTitle(_ mode: BrowseLeftClickMode) -> String {
        switch mode {
        case .toggleHidden:
            "Toggle Hidden"
        case .openBrowseIcons:
            browseOpenActionLabel
        }
    }

    private var secondMenuBarRowsSummary: String {
        var rows = ["Hidden"]
        if menuBarManager.settings.secondMenuBarShowVisible {
            rows.append("Visible")
        }
        if menuBarManager.settings.secondMenuBarShowAlwaysHidden {
            rows.append("Always Hidden")
        }
        return rows.joined(separator: " + ")
    }

    private func browseIconsViewOptionHelp(useSecondMenuBar: Bool) -> String {
        useSecondMenuBar
            ? "Open the Second Menu Bar strip under the menu bar."
            : "Open the Icon Panel window with search and actions."
    }

    private func secondMenuBarPresetHelp(_ preset: SecondMenuBarPreset) -> String {
        switch preset {
        case .minimal:
            "Show only the Hidden row."
        case .balanced:
            "Show Hidden and Visible rows."
        case .power:
            "Show Hidden, Visible, and Always Hidden rows."
        }
    }

    private func leftClickModeHelp(_ mode: BrowseLeftClickMode) -> String {
        switch mode {
        case .toggleHidden:
            "Left-click the SaneBar icon to show or hide icons."
        case .openBrowseIcons:
            "Left-click the SaneBar icon to open \(browseDestinationLabel)."
        }
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
                // 1. Browse Icons
                CompactSection("Browse Icons") {
                    CompactRow("Browse Icons view") {
                        HStack(spacing: 6) {
                            segmentedChoiceButton(
                                "Icon Panel",
                                isSelected: !menuBarManager.settings.useSecondMenuBar
                            ) {
                                applyBrowseIconsViewSelection(false)
                            }
                            .help(browseIconsViewOptionHelp(useSecondMenuBar: false))

                            segmentedChoiceButton(
                                "Second Menu Bar",
                                isSelected: menuBarManager.settings.useSecondMenuBar
                            ) {
                                applyBrowseIconsViewSelection(true)
                            }
                            .help(browseIconsViewOptionHelp(useSecondMenuBar: true))
                        }
                        .frame(width: 260)
                    }

                    if licenseService.isPro, menuBarManager.settings.useSecondMenuBar {
                        CompactDivider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text("Visible rows")
                                    .foregroundStyle(.white.opacity(0.94))

                                Spacer(minLength: 0)

                                HStack(spacing: 6) {
                                    ForEach(SecondMenuBarPreset.allCases) { preset in
                                        segmentedChoiceButton(
                                            preset.title,
                                            isSelected: secondMenuBarPresetBinding.wrappedValue == preset
                                        ) {
                                            secondMenuBarPresetBinding.wrappedValue = preset
                                        }
                                        .help(secondMenuBarPresetHelp(preset))
                                    }
                                }
                                .frame(width: 260)
                            }

                            Text(secondMenuBarRowsSummary)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(secondMenuBarRowsSummary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if secondMenuBarPresetBinding.wrappedValue == .power {
                            CompactDivider()
                            CompactRow("Customize rows") {
                                Button(showBrowseRowCustomization ? "Hide" : "Show") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showBrowseRowCustomization.toggle()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Show or hide row-level options.")
                            }

                            if showBrowseRowCustomization {
                                CompactDivider()
                                CompactToggle(
                                    label: "Include visible icons",
                                    isOn: $menuBarManager.settings.secondMenuBarShowVisible
                                )
                                .help("Show visible (non-hidden) icons in the Second Menu Bar.")

                                CompactDivider()
                                CompactToggle(
                                    label: "Include always-hidden icons",
                                    isOn: $menuBarManager.settings.secondMenuBarShowAlwaysHidden
                                )
                                .help("Show always-hidden icons in the Second Menu Bar.")
                            }
                        }
                    } else if !licenseService.isPro {
                        CompactDivider()
                        proGatedRow(feature: .alwaysHidden, label: "Second Menu Bar zone controls")
                    }
                    CompactDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Left-click SaneBar icon")
                            Spacer()
                        }
                        .foregroundStyle(.white.opacity(0.94))
                        HStack(spacing: 6) {
                            ForEach(BrowseLeftClickMode.allCases) { mode in
                                segmentedChoiceButton(
                                    leftClickModeTitle(mode),
                                    isSelected: leftClickModeBinding.wrappedValue == mode
                                ) {
                                    leftClickModeBinding.wrappedValue = mode
                                }
                                .help(leftClickModeHelp(mode))
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Text("Tip: Right-click the SaneBar icon to open the app menu.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                // 2. Security — Pro
                CompactSection("Security") {
                    if licenseService.isPro {
                        CompactToggle(label: "Touch ID to unlock hidden icons", isOn: requireAuthBinding)
                            .help("Require Touch ID (or password on Macs without Touch ID) to reveal hidden menu bar icons")
                    } else {
                        proGatedRow(feature: .touchIDProtection, label: "Touch ID to unlock hidden icons")
                    }
                }

                // 3. Startup Status
                CompactSection("Startup") {
                    SaneLoginItemToggle()
                    CompactDivider()
                    SaneDockIconToggle(showDockIcon: showDockIconBinding)
                }

                // 4. Updates
                CompactSection("Software Updates") {
                    SaneSparkleRow(
                        automaticallyChecks: $menuBarManager.settings.checkForUpdatesAutomatically,
                        onCheckNow: { menuBarManager.userDidClickCheckForUpdates() }
                    )
                }

                // 5. Profiles — Pro
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
                                            .buttonStyle(.bordered)
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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Save all current settings as a named profile")
                        }
                    } else {
                        proGatedRow(feature: .settingsProfiles, label: "Save and load configurations")
                    }
                }

                // 6. Data — Pro
                CompactSection("Data") {
                    if licenseService.isPro {
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
                    } else {
                        proGatedRow(feature: .exportImport, label: "Export, import, and migrate settings")
                    }
                }

                // 7. Pro License
                CompactSection("Pro License") {
                    if licenseService.isPro {
                        CompactRow("Status") {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Pro")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        if let email = licenseService.licenseEmail {
                            CompactDivider()
                            CompactRow("Licensed to") {
                                Text(email)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        CompactDivider()
                        CompactRow("Actions") {
                            Button("Deactivate License") {
                                licenseService.deactivate()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        CompactRow("Status") {
                            HStack(spacing: 6) {
                                Text("Basic")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        CompactDivider()
                        CompactRow("Upgrade") {
                            HStack(spacing: 8) {
                                Button("Unlock Pro — $6.99") {
                                    NSWorkspace.shared.open(LicenseService.checkoutURL)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.saneAccent)
                                .controlSize(.small)

                                Button("Enter Key") {
                                    showingLicenseEntry = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // 8. Troubleshooting
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
            normalizeBrowseModeSettingsForCurrentPlan()
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
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
        .sheet(isPresented: $showingLicenseEntry) {
            LicenseEntryView()
        }
    }

    // MARK: - Pro Gating Helper

    private func segmentedChoiceButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [.saneAccentDeep.opacity(0.96), .saneAccent.opacity(0.96)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func applyBrowseIconsViewSelection(_ useSecondMenuBar: Bool) {
        menuBarManager.settings.useSecondMenuBar = useSecondMenuBar
        // Icon Panel is the primary browse workflow. Keep always-hidden available there.
        if !useSecondMenuBar, licenseService.isPro, !menuBarManager.settings.alwaysHiddenSectionEnabled {
            menuBarManager.settings.alwaysHiddenSectionEnabled = true
        }
        normalizeBrowseModeSettingsForCurrentPlan()
        SearchWindowController.shared.resetWindow()
    }

    private func normalizeBrowseModeSettingsForCurrentPlan() {
        let normalizedLeftClick = MenuBarManager.normalizedLeftClickOpensBrowseIcons(
            isPro: licenseService.isPro,
            useSecondMenuBar: menuBarManager.settings.useSecondMenuBar,
            leftClickOpensBrowseIcons: menuBarManager.settings.leftClickOpensBrowseIcons
        )
        if normalizedLeftClick != menuBarManager.settings.leftClickOpensBrowseIcons {
            menuBarManager.settings.leftClickOpensBrowseIcons = normalizedLeftClick
        }

        let normalizedRows = MenuBarManager.normalizedSecondMenuBarRows(
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
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("Pro")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.saneAccentSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.saneAccentDeep.opacity(0.32)))
            }
            .buttonStyle(.plain)
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

extension GeneralSettingsView.SecondMenuBarPreset {
    static func resolve(showVisible: Bool, showAlwaysHidden: Bool) -> Self {
        switch (showVisible, showAlwaysHidden) {
        case (false, false):
            .minimal
        case (true, false):
            .balanced
        case (true, true), (false, true):
            .power
        }
    }
}
