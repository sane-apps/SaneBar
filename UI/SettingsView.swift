import SwiftUI

struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var selectedTab: SettingsTab? = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case rules = "Rules"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case experimental = "Advanced"
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
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
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
            case .experimental:
                ExperimentalSettingsView()
                    .navigationTitle("Advanced")
            case .about:
                AboutSettingsView()
                    .navigationTitle("About")
            case .none:
                GeneralSettingsView()
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
        .frame(minWidth: 700, minHeight: 450)
        .background(SaneGradientBackground())
    }

    // MARK: - Icons

    private func icon(for tab: SettingsTab) -> String {
        switch tab {
        case .general: "gear"
        case .rules: "wand.and.stars"
        case .appearance: "paintpalette"
        case .shortcuts: "keyboard"
        case .experimental: "flask"
        case .about: "info.circle"
        }
    }

    private func iconColor(for tab: SettingsTab) -> Color {
        switch tab {
        case .general: .gray
        case .rules: .purple
        case .appearance: .blue
        case .shortcuts: .orange
        case .experimental: .orange
        case .about: .secondary
        }
    }
}

#Preview {
    SettingsView()
}
