import SaneUI
import SwiftUI

struct GeneralSettingsBrowseSection: View {
    @ObservedObject var menuBarManager: MenuBarManager
    @ObservedObject var licenseService: LicenseService
    @Binding var showBrowseRowCustomization: Bool
    let leftClickMode: Binding<GeneralSettingsBrowseLeftClickMode>
    let secondMenuBarPreset: Binding<GeneralSettingsSecondMenuBarPreset>
    let applyBrowseIconsViewSelection: (Bool) -> Void
    let showProUpsell: (ProFeature) -> Void

    private var browseDestinationLabel: String {
        menuBarManager.settings.useSecondMenuBar ? "Second Menu Bar" : "Icon Panel"
    }

    private var isBasicSecondMenuBar: Bool {
        !licenseService.isPro && menuBarManager.settings.useSecondMenuBar
    }

    private var browseOpenActionLabel: String {
        menuBarManager.settings.useSecondMenuBar ? "Open Second Menu Bar" : "Open Icon Panel"
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

    var body: some View {
        CompactSection("Browse Icons") {
            CompactRow("Browse Icons view") {
                HStack(spacing: 6) {
                    segmentedChoiceButton("Icon Panel", isSelected: !menuBarManager.settings.useSecondMenuBar) {
                        applyBrowseIconsViewSelection(false)
                    }
                    .help(browseIconsViewOptionHelp(useSecondMenuBar: false))

                    segmentedChoiceButton("Second Menu Bar", isSelected: menuBarManager.settings.useSecondMenuBar) {
                        applyBrowseIconsViewSelection(true)
                    }
                    .help(browseIconsViewOptionHelp(useSecondMenuBar: true))
                }
                .frame(width: 260)
            }

            if licenseService.isPro, menuBarManager.settings.useSecondMenuBar {
                proSecondMenuBarRows
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
            leftClickRows
        }
    }

    private var proSecondMenuBarRows: some View {
        Group {
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
                    ForEach(GeneralSettingsSecondMenuBarPreset.allCases) { preset in
                        segmentedChoiceButton(preset.title, isSelected: secondMenuBarPreset.wrappedValue == preset) {
                            secondMenuBarPreset.wrappedValue = preset
                        }
                        .help(secondMenuBarPresetHelp(preset))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if secondMenuBarPreset.wrappedValue == .power {
                powerRows
            }
        }
    }

    private var powerRows: some View {
        Group {
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
                CompactToggle(label: "Show Visible row", isOn: $menuBarManager.settings.secondMenuBarShowVisible)
                    .help("Show the Visible destination row in the Second Menu Bar.")

                CompactDivider()
                CompactToggle(label: "Show Always Hidden row", isOn: $menuBarManager.settings.secondMenuBarShowAlwaysHidden)
                    .help("Show the Always Hidden destination row in the Second Menu Bar.")
            }
        }
    }

    private var leftClickRows: some View {
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
                ForEach(GeneralSettingsBrowseLeftClickMode.allCases) { mode in
                    segmentedChoiceButton(leftClickModeTitle(mode), isSelected: leftClickMode.wrappedValue == mode) {
                        leftClickMode.wrappedValue = mode
                    }
                    .help(leftClickModeHelp(mode))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func segmentedChoiceButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ChromeSegmentedChoiceButton(title: title, isSelected: isSelected, action: action)
    }

    private func proGatedRow(feature: ProFeature, label: String) -> some View {
        CompactRow(label) {
            Button {
                showProUpsell(feature)
            } label: {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func leftClickModeTitle(_ mode: GeneralSettingsBrowseLeftClickMode) -> String {
        switch mode {
        case .toggleHidden:
            "Toggle Hidden"
        case .openBrowseIcons:
            browseOpenActionLabel
        }
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

    private func secondMenuBarPresetHelp(_ preset: GeneralSettingsSecondMenuBarPreset) -> String {
        switch preset {
        case .minimal:
            "Show only the Hidden row in the Second Menu Bar."
        case .balanced:
            "Show Hidden and Visible rows in the Second Menu Bar."
        case .power:
            "Show Hidden, Visible, and Always Hidden rows in the Second Menu Bar."
        }
    }

    private func leftClickModeHelp(_ mode: GeneralSettingsBrowseLeftClickMode) -> String {
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
}
