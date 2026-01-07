import SwiftUI

struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case advanced = "Advanced"
        case about = "About"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 540, height: 540)
        .tint(.blue)
        .groupBoxStyle(GlassGroupBoxStyle())
    }
}

#Preview {
    SettingsView()
}
