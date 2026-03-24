import SwiftUI
import SaneUI

struct SettingsView: View {
    enum SettingsTab: String, SaneSettingsTab {
        case general = "General"
        case rules = "Rules"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case about = "About"

        var icon: String {
            switch self {
            case .general: "gear"
            case .rules: "wand.and.stars"
            case .appearance: "paintpalette"
            case .shortcuts: "keyboard"
            case .about: "questionmark.circle"
            }
        }

        var iconColor: Color {
            switch self {
            case .general:
                SaneBarChrome.accentHighlight
            case .rules:
                SaneBarChrome.accentTeal
            case .appearance:
                Color(red: 0.66, green: 0.82, blue: 1.00)
            case .shortcuts:
                Color(red: 0.50, green: 0.74, blue: 1.00)
            case .about:
                Color(red: 0.76, green: 0.88, blue: 1.00)
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
