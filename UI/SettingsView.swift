import SwiftUI
import SaneUI

struct SettingsView: View {
    enum SettingsTab: String, SaneSettingsTab {
        case general = "General"
        case rules = "Rules"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case license = "License"
        case about = "About"

        var icon: String {
            switch self {
            case .general: "gear"
            case .rules: "wand.and.stars"
            case .appearance: "paintpalette"
            case .shortcuts: "keyboard"
            case .license: "key.fill"
            case .about: "questionmark.circle"
            }
        }

        var iconColor: Color {
            switch self {
            case .general:
                SaneSettingsIconSemantic.general.color
            case .rules:
                SaneSettingsIconSemantic.rules.color
            case .appearance:
                SaneSettingsIconSemantic.appearance.color
            case .shortcuts:
                SaneSettingsIconSemantic.shortcuts.color
            case .license:
                SaneSettingsIconSemantic.license.color
            case .about:
                SaneSettingsIconSemantic.about.color
            }
        }
    }

    var body: some View {
        SaneSettingsContainer(defaultTab: SettingsTab.general) { tab in
            switch tab {
            case .general:
                GeneralSettingsView()
                    .navigationTitle("General")
            case .rules:
                RulesSettingsView()
                    .navigationTitle("Rules")
            case .appearance:
                AppearanceSettingsView()
                    .navigationTitle("Appearance")
            case .shortcuts:
                ShortcutsSettingsView()
                    .navigationTitle("Shortcuts")
            case .license:
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        LicenseSettingsView<SaneBarLicenseSettingsAdapter>(
                            licenseService: SaneBarLicenseSettingsAdapter.shared,
                            style: .panel
                        )
                            .frame(maxWidth: 420, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("License")
            case .about:
                AboutSettingsView()
                    .navigationTitle("About")
            }
        }
    }
}

#Preview {
    SettingsView()
}
