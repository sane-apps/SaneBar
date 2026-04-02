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
            case .toggleHidden: SaneBarSettingsCopy.toggleHiddenModeTitle
            case .openBrowseIcons: SaneBarSettingsCopy.openBrowseModeTitle
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
            case .minimal: SaneBarSettingsCopy.hiddenRowOnlyTitle
            case .balanced: SaneBarSettingsCopy.rowsShownInSecondMenuBarSummary
            case .power: SaneBarSettingsCopy.allRowsTitle
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
        SaneBarSettingsCopy.browseDestinationLabel(useSecondMenuBar: menuBarManager.settings.useSecondMenuBar)
    }

    private var isBasicSecondMenuBar: Bool {
        !licenseService.isPro && menuBarManager.settings.useSecondMenuBar
    }

    private var browseOpenActionLabel: String {
        SaneBarSettingsCopy.browseOpenActionLabel(useSecondMenuBar: menuBarManager.settings.useSecondMenuBar)
    }

    private func leftClickModeTitle(_ mode: BrowseLeftClickMode) -> String {
        switch mode {
        case .toggleHidden:
            SaneBarSettingsCopy.toggleHiddenModeTitle
        case .openBrowseIcons:
            browseOpenActionLabel
        }
    }

    private var secondMenuBarRowsSummary: String {
        var rows = [SaneBarSettingsCopy.hiddenRowTitle]
        if menuBarManager.settings.secondMenuBarShowVisible {
            rows.append(SaneBarSettingsCopy.visibleRowTitle)
        }
        if menuBarManager.settings.secondMenuBarShowAlwaysHidden {
            rows.append(SaneBarSettingsCopy.alwaysHiddenRowTitle)
        }
        return rows.joined(separator: " + ")
    }

    private func browseIconsViewOptionHelp(useSecondMenuBar: Bool) -> String {
        if useSecondMenuBar {
            if licenseService.isPro {
                return SaneBarSettingsCopy.secondMenuBarViewHelp
            }
            return SaneBarSettingsCopy.secondMenuBarViewHelpBasic
        }

        if licenseService.isPro {
            return SaneBarSettingsCopy.browseIconsViewHelp
        }
        return SaneBarSettingsCopy.browseIconsViewHelpBasic
    }

    private func secondMenuBarPresetHelp(_ preset: SecondMenuBarPreset) -> String {
        switch preset {
        case .minimal:
            String(localized: "sanebar.settings.help.second_menu_bar_minimal", defaultValue: "Show only the Hidden row in the Second Menu Bar.")
        case .balanced:
            String(localized: "sanebar.settings.help.second_menu_bar_balanced", defaultValue: "Show Hidden and Visible rows in the Second Menu Bar.")
        case .power:
            String(localized: "sanebar.settings.help.second_menu_bar_power", defaultValue: "Show Hidden, Visible, and Always Hidden rows in the Second Menu Bar.")
        }
    }

    private func leftClickModeHelp(_ mode: BrowseLeftClickMode) -> String {
        switch mode {
        case .toggleHidden:
            return String(localized: "sanebar.settings.help.left_click_toggle_hidden", defaultValue: "Left-click the SaneBar icon to show or hide icons.")
        case .openBrowseIcons:
            if licenseService.isPro {
                return String(localized: "sanebar.settings.help.left_click_open_destination", defaultValue: "Left-click the SaneBar icon to open %@.")
                    .replacingOccurrences(of: "%@", with: browseDestinationLabel)
            }
            return String(localized: "sanebar.settings.help.left_click_open_destination_basic", defaultValue: "Left-click the SaneBar icon to open %@ for browsing and clicking icons.")
                .replacingOccurrences(of: "%@", with: browseDestinationLabel)
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
        context.localizedCancelTitle = SaneBarSettingsCopy.cancelTitle

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: SaneBarSettingsCopy.authReasonDisableHiddenIcons) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Browse Icons
                CompactSection(SaneBarSettingsCopy.browseIconsSectionTitle) {
                    CompactRow(SaneBarSettingsCopy.browseIconsViewLabel) {
                        HStack(spacing: 6) {
                            segmentedChoiceButton(
                                SaneBarSettingsCopy.iconPanelTitle,
                                isSelected: !menuBarManager.settings.useSecondMenuBar
                            ) {
                                applyBrowseIconsViewSelection(false)
                            }
                            .help(browseIconsViewOptionHelp(useSecondMenuBar: false))

                            segmentedChoiceButton(
                                SaneBarSettingsCopy.secondMenuBarTitle,
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
                                Text(SaneBarSettingsCopy.rowsShownInSecondMenuBarLabel)
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
                            CompactRow(SaneBarSettingsCopy.customRowsLabel) {
                                Button(showBrowseRowCustomization ? SaneBarSettingsCopy.hideButtonTitle : SaneBarSettingsCopy.showHideButtonTitle) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showBrowseRowCustomization.toggle()
                                    }
                                }
                                .buttonStyle(ChromeActionButtonStyle())
                                .help(SaneBarSettingsCopy.showOrHideRowOptionsHelp)
                            }

                            if showBrowseRowCustomization {
                                CompactDivider()
                                CompactToggle(
                                    label: SaneBarSettingsCopy.showVisibleRowLabel,
                                    isOn: $menuBarManager.settings.secondMenuBarShowVisible
                                )
                                .help(SaneBarSettingsCopy.visibleRowHelp)

                                CompactDivider()
                                CompactToggle(
                                    label: SaneBarSettingsCopy.showAlwaysHiddenRowLabel,
                                    isOn: $menuBarManager.settings.secondMenuBarShowAlwaysHidden
                                )
                                .help(SaneBarSettingsCopy.alwaysHiddenRowHelp)
                            }
                        }
                    } else if isBasicSecondMenuBar {
                        CompactDivider()
                        CompactRow(SaneBarSettingsCopy.rowsShownInSecondMenuBarLabel) {
                                Text(SaneBarSettingsCopy.rowsShownInSecondMenuBarSummary)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.94))
                        }
                        CompactDivider()
                        proGatedRow(feature: .alwaysHidden, label: SaneBarSettingsCopy.alwaysHiddenRowTitle)
                    } else if !licenseService.isPro {
                        CompactDivider()
                        proGatedRow(feature: .zoneMoves, label: SaneBarSettingsCopy.moveIconsUpsellLabel)
                    }
                    CompactDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 5) {
                                Text(SaneBarSettingsCopy.leftClickIconLabel)
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SaneBarChrome.accentHighlight.opacity(0.86))
                                    .help(SaneBarSettingsCopy.rightClickIconHelp)
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
                CompactSection(SaneBarSettingsCopy.securitySectionTitle) {
                    if licenseService.isPro {
                        CompactToggle(label: SaneBarSettingsCopy.touchIDLabel, isOn: requireAuthBinding)
                            .help(SaneBarSettingsCopy.touchIDHelp)
                    } else {
                        proGatedRow(feature: .touchIDProtection, label: SaneBarSettingsCopy.touchIDLabel)
                    }
                }

                // 3. Startup Status
                CompactSection(SaneBarSettingsCopy.startupSectionTitle) {
                    SaneLoginItemToggle()
                    CompactDivider()
                    SaneDockIconToggle(showDockIcon: showDockIconBinding)
                }

                // 4. Updates
                softwareUpdatesSection

                // 5. Profiles — Pro
                CompactSection(SaneBarSettingsCopy.savedProfilesSectionTitle) {
                    if licenseService.isPro {
                        if savedProfiles.isEmpty {
                            CompactRow(SaneBarSettingsCopy.savedProfilesSectionTitle) {
                                Text(SaneBarSettingsCopy.savedProfilesEmptyState)
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        } else {
                            ForEach(savedProfiles) { profile in
                                CompactRow(profile.name) {
                                    HStack {
                                        Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white.opacity(0.92))

                                        Button(SaneBarSettingsCopy.loadButtonTitle) { loadProfile(profile) }
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

                        CompactRow(SaneBarSettingsCopy.currentSettingsLabel) {
                            Button(SaneBarSettingsCopy.saveAsProfileButtonTitle) {
                                newProfileName = SaneBarProfile.generateName(basedOn: savedProfiles.map(\.name))
                                showingSaveProfileAlert = true
                            }
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)
                            .help(SaneBarSettingsCopy.saveAsProfileHelp)
                        }
                    } else {
                        proGatedRow(feature: .settingsProfiles, label: SaneBarSettingsCopy.saveAndLoadConfigurationsUpsellLabel)
                    }
                }

                // 6. Data — Pro
                CompactSection(SaneBarSettingsCopy.dataSectionTitle) {
                    if licenseService.isPro {
                        CompactRow(SaneBarSettingsCopy.settingsLabel) {
                            Button(SaneBarSettingsCopy.exportSettingsButtonTitle) {
                                exportSettings()
                            }
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)

                            Button(SaneBarSettingsCopy.importSettingsButtonTitle) {
                                importSettings()
                            }
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)
                        }

                        CompactDivider()

                        CompactRow(SaneBarSettingsCopy.migrationLabel) {
                            HStack(spacing: 8) {
                                Button(SaneBarSettingsCopy.importBartenderButtonTitle) {
                                    importBartenderSettings()
                                }
                                Button(SaneBarSettingsCopy.importIceButtonTitle) {
                                    importIceSettings()
                                }
                            }
                            .buttonStyle(ChromeActionButtonStyle())
                            .controlSize(.small)
                        }
                    } else {
                        proGatedRow(feature: .exportImport, label: SaneBarSettingsCopy.exportImportUpsellLabel)
                    }
                }

                // 7. Pro License
                CompactSection(SaneBarSettingsCopy.licenseSectionTitle) {
                    if licenseService.isPro {
                        CompactRow(SaneBarSettingsCopy.statusLabel) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(SaneBarChrome.accentHighlight)
                                Text(SaneBarSettingsCopy.proLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SaneBarChrome.accentHighlight)
                            }
                        }
                        if let email = licenseService.licenseEmail {
                            CompactDivider()
                            CompactRow(SaneBarSettingsCopy.licensedToLabel) {
                                Text(email)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        CompactDivider()
                        CompactRow(SaneBarSettingsCopy.actionsLabel) {
                            if licenseService.usesAppStorePurchase {
                                Button(SaneBarSettingsCopy.restorePurchasesButtonTitle) {
                                    Task { await licenseService.restorePurchases() }
                                }
                                .buttonStyle(ChromeActionButtonStyle())
                                .controlSize(.small)
                                .disabled(licenseService.isPurchasing)
                            } else if licenseService.usesSetappDistribution {
                                Text(SaneBarSettingsCopy.managedBySetappLabel)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                            } else {
                                Button(LicenseService.deactivateLicenseLabel()) {
                                    licenseService.deactivate()
                                }
                                .buttonStyle(ChromeActionButtonStyle(destructive: true))
                                .controlSize(.small)
                            }
                        }
                    } else {
                        CompactRow(SaneBarSettingsCopy.statusLabel) {
                            HStack(spacing: 6) {
                                Text(SaneBarSettingsCopy.basicLabel)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                        CompactDivider()
                        CompactRow(SaneBarSettingsCopy.actionsLabel) {
                            if licenseService.usesAppStorePurchase {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Button(SaneBarSettingsCopy.unlockProButtonTitle(price: licenseService.appStoreDisplayPrice ?? "$6.99")) {
                                            Task { await licenseService.purchasePro() }
                                        }
                                        .buttonStyle(ChromeActionButtonStyle(prominent: true))
                                        .controlSize(.small)
                                        .disabled(licenseService.isPurchasing)

                                        Button(SaneBarSettingsCopy.restorePurchasesButtonTitle) {
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
                                Text(SaneBarSettingsCopy.managedBySetappLabel)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                            } else {
                                HStack(spacing: 8) {
                                    Button(SaneBarSettingsCopy.unlockProDefaultButtonTitle(price: "$6.99")) {
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
                CompactSection(SaneBarSettingsCopy.resetAppSectionTitle) {
                    CompactRow(SaneBarSettingsCopy.resetAppLabel) {
                        Button(SaneBarSettingsCopy.resetToDefaultsButtonTitle) {
                            showingResetAlert = true
                        }
                        .buttonStyle(ChromeActionButtonStyle(destructive: true))
                        .controlSize(.small)
                        .help(SaneBarSettingsCopy.resetAppHelp)
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
        .alert(SaneBarSettingsCopy.saveProfileAlertTitle, isPresented: $showingSaveProfileAlert) {
            TextField(SaneBarSettingsCopy.saveProfileNamePlaceholder, text: $newProfileName)
            Button(SaneBarSettingsCopy.saveButtonTitle) { saveCurrentProfile() }
            Button(SaneBarSettingsCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(SaneBarSettingsCopy.saveProfileAlertMessage)
        }
        .alert(SaneBarSettingsCopy.resetSettingsAlertTitle, isPresented: $showingResetAlert) {
            Button(SaneBarSettingsCopy.cancelButtonTitle, role: .cancel) {}
            Button(SaneBarSettingsCopy.resetButtonTitle, role: .destructive) {
                menuBarManager.resetToDefaults()
            }
        } message: {
            Text(SaneBarSettingsCopy.resetSettingsAlertMessage)
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
        .sheet(isPresented: $showingLicenseEntry) {
            LicenseEntryView()
        }
    }

    // MARK: - Pro Gating Helper

    @ViewBuilder
    private var softwareUpdatesSection: some View {
        CompactSection(SaneBarSettingsCopy.updatesSectionTitle) {
            if licenseService.distributionChannel.supportsInAppUpdates {
                CompactToggle(
                    label: SaneBarSettingsCopy.checkForUpdatesAutomaticallyLabel,
                    isOn: $menuBarManager.settings.checkForUpdatesAutomatically
                )
                .help(SaneBarSettingsCopy.checkForUpdatesAutomaticallyHelp)

                CompactDivider()

                CompactRow(SaneBarSettingsCopy.checkFrequencyLabel) {
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
                .help(SaneBarSettingsCopy.checkFrequencyHelp)

                CompactDivider()

                CompactRow(SaneBarSettingsCopy.actionsLabel) {
                    Button(isCheckingForUpdates ? SaneBarSettingsCopy.checkingButtonTitle : SaneBarSettingsCopy.checkNowButtonTitle) {
                        triggerManualUpdateCheck()
                    }
                    .buttonStyle(ChromeActionButtonStyle())
                    .controlSize(.small)
                    .disabled(isCheckingForUpdates)
                    .help(SaneBarSettingsCopy.checkNowHelp)
                }
            } else {
                CompactRow(SaneBarSettingsCopy.statusLabel) {
                    Text(licenseService.distributionChannel.managementLabel ?? SaneBarSettingsCopy.managedExternallyLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
    }

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
                ChromeBadge(title: SaneBarSettingsCopy.proBadgeTitle, systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func triggerManualUpdateCheck() {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        menuBarManager.userDidClickCheckForUpdates()

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
        panel.title = SaneBarSettingsCopy.exportPanelTitle

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
            showError(title: SaneBarSettingsCopy.exportFailedTitle, error: error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = SaneBarSettingsCopy.importPanelTitle

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
            showError(title: SaneBarSettingsCopy.importFailedTitle, error: error)
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
            showError(title: SaneBarSettingsCopy.importFailedTitle, error: error)
        }
    }

    // MARK: - Bartender Import

    private func importBartenderSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = SaneBarSettingsCopy.bartenderImportPanelTitle
        panel.message = SaneBarSettingsCopy.bartenderImportPanelMessage
        panel.prompt = SaneBarSettingsCopy.bartenderImportPrompt
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
                showInfo(title: SaneBarSettingsCopy.bartenderImportCompleteTitle, message: summary.description)
            } catch {
                showError(title: SaneBarSettingsCopy.bartenderImportFailedTitle, error: error)
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
        panel.title = SaneBarSettingsCopy.iceImportPanelTitle
        panel.message = SaneBarSettingsCopy.iceImportPanelMessage
        panel.prompt = SaneBarSettingsCopy.iceImportPrompt
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
            showInfo(title: SaneBarSettingsCopy.iceImportCompleteTitle, message: summary.description)
        } catch {
            showError(title: SaneBarSettingsCopy.iceImportFailedTitle, error: error)
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
