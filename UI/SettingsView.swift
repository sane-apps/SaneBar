import SwiftUI

struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var selectedTab: SettingsTab? = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case rules = "Rules"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case about = "About"
        
        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label {
                        Text(tab.rawValue)
                    } icon: {
                        Image(systemName: icon(for: tab))
                            .foregroundStyle(iconColor(for: tab))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedTab {
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
            case .none:
                GeneralSettingsView()
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
        .frame(minWidth: 700, minHeight: 450)
    }
    
    // MARK: - Icons
    
    private func icon(for tab: SettingsTab) -> String {
        switch tab {
        case .general: return "gear"
        case .rules: return "wand.and.stars"
        case .appearance: return "paintpalette"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
    
    private func iconColor(for tab: SettingsTab) -> Color {
        switch tab {
        case .general: return .gray
        case .rules: return .purple
        case .appearance: return .blue
        case .shortcuts: return .orange
        case .about: return .secondary
        }
    }
}

#Preview {
    SettingsView()
}
