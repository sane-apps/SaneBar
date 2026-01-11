import SwiftUI
import LaunchAtLogin

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.showDockIcon },
            set: { newValue in
                menuBarManager.settings.showDockIcon = newValue
                ActivationPolicyManager.applyPolicy(showDockIcon: newValue)
            }
        )
    }

    var body: some View {
        Form {
            // 1. Startup - most users want this
            Section {
                LaunchAtLogin.Toggle {
                    Text("Open SaneBar when I log in")
                }
                Toggle("Show in Dock", isOn: showDockIconBinding)
            } header: {
                Text("Startup")
            }

            // 2. Quick help - always useful
            Section {
                HStack {
                    Button {
                        if menuBarManager.hidingState == .hidden {
                            menuBarManager.showHiddenItems()
                        } else {
                            menuBarManager.hideHiddenItems()
                        }
                    } label: {
                        Label(menuBarManager.hidingState == .hidden ? "Reveal All" : "Hide All",
                              systemImage: menuBarManager.hidingState == .hidden ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { @MainActor in
                            SearchWindowController.shared.toggle()
                        }
                    } label: {
                        Label("Find Icon…", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Can't find an icon?")
            } footer: {
                Text("\"Find Icon\" shows all menu bar icons and lets you click any of them.")
            }

            // 3. Behavior - next most common
            Section {
                Toggle("Auto-hide after a few seconds", isOn: $menuBarManager.settings.autoRehide)
                if menuBarManager.settings.autoRehide {
                    Stepper("Wait \(Int(menuBarManager.settings.rehideDelay)) seconds",
                            value: $menuBarManager.settings.rehideDelay,
                            in: 1...10, step: 1)
                }
            } header: {
                Text("When I reveal hidden icons…")
            }

            // 4. Gesture triggers
            Section {
                Toggle("Reveal when I hover near the top", isOn: $menuBarManager.settings.showOnHover)
                if menuBarManager.settings.showOnHover {
                    HStack {
                        Text("Delay")
                        Slider(value: $menuBarManager.settings.hoverDelay, in: 0.05...0.5, step: 0.05)
                        Text("\(Int(menuBarManager.settings.hoverDelay * 1000))ms")
                            .foregroundStyle(.secondary)
                            .frame(width: 50)
                    }
                }
                Toggle("Reveal when I scroll up in the menu bar", isOn: $menuBarManager.settings.showOnScroll)
            } header: {
                Text("Gestures")
            } footer: {
                Text("These gestures work anywhere along the menu bar.")
            }

            // 5. How it works - bottom, collapsible info
            Section {
                DisclosureGroup("How to organize your menu bar") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("**⌘+drag** icons to rearrange them", systemImage: "hand.draw")
                        Label("Icons **left of the separator** get hidden", systemImage: "eye.slash")
                        Label("Icons **right of SaneBar** stay visible", systemImage: "eye")
                        Label("**Click SaneBar** to show/hide", systemImage: "cursorarrow.click.2")
                        if menuBarManager.hasNotch {
                            Label("You have a notch — keep important icons on the right", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: menuBarManager.settings) { _, _ in
            menuBarManager.saveSettings()
        }
    }
}
