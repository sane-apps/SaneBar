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
            case .minimal: "Hidden Row"
            case .balanced: "Hidden + Visible"
            case .power: "All Rows"
            }
        }
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

    private var isBasicSecondMenuBar: Bool {
        !licenseService.isPro && menuBarManager.settings.useSecondMenuBar
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
        if useSecondMenuBar {
            if licenseService.isPro {
                return "Open a row-based strip under the menu bar."
            }
            return "Open a row-based strip under the menu bar. Basic includes browsing and clicking there. Pro adds moving icons and Always Hidden."
        }

        if licenseService.isPro {
            return "Open the Icon Panel window with search and icon actions."
        }
        return "Open the Icon Panel window with search and icon clicking. Pro adds moving icons and Always Hidden."
    }

    private func secondMenuBarPresetHelp(_ preset: SecondMenuBarPreset) -> String {
        switch preset {
        case .minimal:
            "Show only the Hidden row in the Second Menu Bar."
        case .balanced:
            "Show Hidden and Visible rows in the Second Menu Bar."
        case .power:
            "Show Hidden, Visible, and Always Hidden rows in the Second Menu Bar."
        }
    }

    private func leftClickModeHelp(_ mode: BrowseLeftClickMode) -> String {
        switch mode {
        case .toggleHidden:
            return "Left-click the SaneBar icon to show or hide icons."
        case .openBrowseIcons:
            if licenseService.isPro {
                return "Left-click the SaneBar icon to open \(browseDestinationLabel)."
            }
            return "Left-click the SaneBar icon to open \(browseDestinationLabel) for browsing and clicking icons."
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
                            HStack(spacing: 5) {
                                Text("Rows shown in Second Menu Bar")
                                    .foregroundStyle(.white.opacity(0.94))

                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SaneBarChrome.accentHighlight.opacity(0.86))
                                    .help(secondMenuBarRowsSummary)
                            }

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 112), spacing: 6, alignment: .leading)],
                                alignment: .leading,
                                spacing: 6
                            ) {
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
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if secondMenuBarPresetBinding.wrappedValue == .power {
                            CompactDivider()
                            CompactRow("Custom rows") {
                                Button(showBrowseRowCustomization ? "Hide" : "Show") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showBrowseRowCustomization.toggle()
                                    }
                                }
                                .buttonStyle(ChromeActionButtonStyle())
                                .help("Show or hide row-level options.")
                            }

                            if showBrowseRowCustomization {
                                CompactDivider()
                                CompactToggle(
                                    label: "Show Visible row",
                                    isOn: $menuBarManager.settings.secondMenuBarShowVisible
                                )
                                .help("Show the Visible destination row in the Second Menu Bar.")

                                CompactDivider()
                                CompactToggle(
                                    label: "Show Always Hidden row",
                                    isOn: $menuBarManager.settings.secondMenuBarShowAlwaysHidden
                                )
                                .help("Show the Always Hidden destination row in the Second Menu Bar.")
                            }
                        }
                    } else if isBasicSecondMenuBar {
                        CompactDivider()
                        CompactRow("Rows shown in Second Menu Bar") {
                                Text("Hidden + Visible")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.94))
                        }
                        CompactDivider()
                        proGatedRow(feature: .alwaysHidden, label: "Always Hidden row")
                    } else if !licenseService.isPro {
                        CompactDivider()
                        proGatedRow(feature: .zoneMoves, label: "Move icons between Visible, Hidden, and Always Hidden")
                    }
                    CompactDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 5) {
                                Text("Left-click SaneBar icon")
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SaneBarChrome.accentHighlight.opacity(0.86))
                                    .help("Right-click the SaneBar icon to open the app menu.")
                            }
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
                    if licenseService.distributionChannel.supportsInAppUpdates {
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
                                guard !isCheckingForUpdates else { return }
                                isCheckingForUpdates = true
                                menuBarManager.userDidClickCheckForUpdates()

                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(5))
                                    isCheckingForUpdates = false
                                }
                            }
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)
                            .disabled(isCheckingForUpdates)
                            .help("Check for updates right now")
                        }
                    } else {
                        CompactRow("Status") {
                            Text(licenseService.distributionChannel.managementLabel ?? "Managed externally")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
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

                // 6. Data — Pro
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

                // 7. Pro License
                CompactSection("Pro License") {
                    if licenseService.isPro {
                        CompactRow("Status") {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(SaneBarChrome.accentHighlight)
                                Text("Pro")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SaneBarChrome.accentHighlight)
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
                            if let managementLabel = licenseService.distributionChannel.managementLabel {
                                HStack(spacing: 10) {
                                    Text(managementLabel)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.82))
                                    if licenseService.usesAppStorePurchase {
                                        Button("Restore Purchases") {
                                            Task { await licenseService.restorePurchases() }
                                        }
                                        .buttonStyle(ChromeActionButtonStyle())
                                        .controlSize(.small)
                                        .disabled(licenseService.isPurchasing)
                                    }
                                }
                            } else {
                                Button(LicenseService.deactivateLicenseLabel()) {
                                    licenseService.deactivate()
                                }
                                .buttonStyle(ChromeActionButtonStyle())
                                .controlSize(.small)
                            }
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
                            if licenseService.usesAppStorePurchase {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Button("Unlock Pro — \(licenseService.appStoreDisplayPrice ?? "$6.99")") {
                                            Task { await licenseService.purchasePro() }
                                        }
                                        .buttonStyle(ChromeActionButtonStyle(prominent: true))
                                        .controlSize(.small)
                                        .disabled(licenseService.isPurchasing)

                                        Button("Restore Purchases") {
                                            Task { await licenseService.restorePurchases() }
                                        }
                                        .buttonStyle(ChromeActionButtonStyle())
                                        .controlSize(.small)
                                        .disabled(licenseService.isPurchasing)
                                    }

                                    if let purchaseError = licenseService.purchaseError {
                                        Text(purchaseError)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.red)
                                    }
                                }
                            } else if licenseService.usesSetappDistribution {
                                Text("Included with Setapp")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                            } else {
                                HStack(spacing: 8) {
                                    Button("Unlock Pro — $6.99") {
                                        NSWorkspace.shared.open(LicenseService.checkoutURL())
                                    }
                                    .buttonStyle(ChromeActionButtonStyle(prominent: true))
                                    .controlSize(.small)

                                    Button(LicenseService.keyEntryButtonLabel()) {
                                        showingLicenseEntry = true
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                    .controlSize(.small)
                                }
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
            if licenseService.usesAppStorePurchase {
                Task { await licenseService.preloadAppStoreProduct() }
            }
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
        ChromeSegmentedChoiceButton(title: title, isSelected: isSelected, action: action)
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
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
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
        applyConfiguration(
            settings: profile.settings,
            layoutSnapshot: profile.layoutSnapshot,
            customIconSnapshot: profile.customIconSnapshot,
            importedProfiles: nil,
            successLog: "📁 Profile applied"
        )
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

            if let export = try? decoder.decode(SaneBarSettingsArchive.self, from: data) {
                settingsLogger.log("📥 Importing wrapped settings from \(url.lastPathComponent, privacy: .public)")
                applyConfiguration(
                    settings: export.settings,
                    layoutSnapshot: export.layoutSnapshot,
                    customIconSnapshot: export.customIconSnapshot,
                    importedProfiles: export.savedProfiles,
                    successLog: "📥 Imported archive applied"
                )
            } else {
                settingsLogger.log("📥 Importing raw settings from \(url.lastPathComponent, privacy: .public)")
                let settings = try decoder.decode(SaneBarSettings.self, from: data)
                applyConfiguration(
                    settings: settings,
                    layoutSnapshot: nil,
                    customIconSnapshot: nil,
                    importedProfiles: nil,
                    successLog: "📥 Imported legacy settings applied"
                )
            }
        } catch {
            settingsLogger.error("📥 Import failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Import Failed", error: error)
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
            if let importedProfiles {
                try PersistenceService.shared.upsertProfiles(importedProfiles)
            }
            if let customIconSnapshot {
                try PersistenceService.shared.applyCustomIconSnapshot(customIconSnapshot)
            }
            if let layoutSnapshot {
                StatusBarController.applyLayoutSnapshot(layoutSnapshot)
            }

            menuBarManager.settings = settings
            menuBarManager.saveSettings()
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
// swiftlint:enable file_length

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
