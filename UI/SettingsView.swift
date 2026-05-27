import AppKit
import SaneUI
import SwiftUI

struct SettingsView: View {
    enum SettingsTab: String, SaneSettingsTab {
        case control = "Control"
        case rules = "Rules"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case health = "Health"
        case license = "License"
        case about = "About"

        var icon: String {
            switch self {
            case .control: "switch.2"
            case .rules: "wand.and.stars"
            case .appearance: "paintpalette"
            case .shortcuts: "keyboard"
            case .health: "stethoscope"
            case .license: "key.fill"
            case .about: "questionmark.circle"
            }
        }

        var iconColor: Color {
            switch self {
            case .control:
                SaneSettingsIconSemantic.general.color
            case .rules:
                SaneSettingsIconSemantic.rules.color
            case .appearance:
                SaneSettingsIconSemantic.appearance.color
            case .shortcuts:
                SaneSettingsIconSemantic.shortcuts.color
            case .health:
                .green
            case .license:
                SaneSettingsIconSemantic.license.color
            case .about:
                SaneSettingsIconSemantic.about.color
            }
        }
    }

    var defaultTab: SettingsTab = .control

    var body: some View {
        SaneSettingsContainer(defaultTab: defaultTab, windowSizing: .embedded) { tab in
            switch tab {
            case .control:
                GeneralSettingsView()
                    .navigationTitle("Control")
            case .rules:
                RulesSettingsView()
                    .navigationTitle("Rules")
            case .appearance:
                AppearanceSettingsView()
                    .navigationTitle("Appearance")
            case .shortcuts:
                ShortcutsSettingsView()
                    .navigationTitle("Shortcuts")
            case .health:
                HealthSettingsView()
                    .navigationTitle("Health")
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
        .overlay(alignment: .bottomTrailing) {
            SaneSettingsResizeGrip()
                .frame(width: 22, height: 22)
                .padding(.trailing, 7)
                .padding(.bottom, 7)
                .saneHelp("Drag the corner to resize Settings.")
        }
    }
}

#Preview {
    SettingsView()
}
