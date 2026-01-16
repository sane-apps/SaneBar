import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var launchAtLogin = false

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.showDockIcon },
            set: { newValue in
                menuBarManager.settings.showDockIcon = newValue
                ActivationPolicyManager.applyPolicy(showDockIcon: newValue)
            }
        )
    }

    private var hideMainIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.hideMainIcon },
            set: { newValue in
                menuBarManager.settings.hideMainIcon = newValue
                menuBarManager.updateMainIconVisibility()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Startup
                CompactSection("Startup") {
                    CompactToggle(label: "Open SaneBar when I log in", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            setLaunchAtLogin(newValue)
                        }
                    ))
                    CompactDivider()
                    CompactToggle(label: "Show in Dock", isOn: showDockIconBinding)
                    CompactDivider()
                    CompactToggle(label: "Hide SaneBar icon (show divider only)", isOn: hideMainIconBinding)
                }

                // 2. Quick help
                CompactSection("Can't find an icon?") {
                    CompactRow("Actions") {
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
                            .controlSize(.small)
                            
                            Button {
                                Task { @MainActor in
                                    SearchWindowController.shared.toggle()
                                }
                            } label: {
                                Label("Find Icon…", systemImage: "magnifyingglass")
                            }
                            .controlSize(.small)
                        }
                    }
                    CompactDivider()
                    HStack {
                        Text("\"Find Icon\" shows all menu bar icons and lets you click any of them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                // 3. Behavior
                CompactSection("When I reveal hidden icons…") {
                    CompactToggle(label: "Auto-hide after a few seconds", isOn: $menuBarManager.settings.autoRehide)
                    if menuBarManager.settings.autoRehide {
                        CompactDivider()
                        CompactRow("Delay") {
                            HStack {
                                Text("Wait \(Int(menuBarManager.settings.rehideDelay))s")
                                Stepper("", value: $menuBarManager.settings.rehideDelay, in: 1...10, step: 1)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                // 4. Gesture triggers
                CompactSection("Gestures") {
                    CompactToggle(label: "Reveal when I hover near the top", isOn: $menuBarManager.settings.showOnHover)
                    if menuBarManager.settings.showOnHover {
                        CompactDivider()
                        CompactRow("Hover Delay") {
                            HStack {
                                Slider(value: $menuBarManager.settings.hoverDelay, in: 0.05...0.5, step: 0.05)
                                    .frame(width: 100)
                                Text("\(Int(menuBarManager.settings.hoverDelay * 1000))ms")
                                    .monospacedDigit()
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                    CompactDivider()
                    CompactToggle(label: "Reveal when I scroll up in the menu bar", isOn: $menuBarManager.settings.showOnScroll)
                }
                
                // 5. Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to organize")
                        .font(.headline)
                        .padding(.leading, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("**⌘+drag** icons to rearrange them", systemImage: "hand.draw")
                        Label("Icons left of **/** get hidden", systemImage: "eye.slash")
                        HStack(spacing: 4) {
                            Label("Icons between **/** and", systemImage: "eye")
                            Image(systemName: "line.3.horizontal.decrease")
                            Text("stay visible")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                }
            }
            .padding(20)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
            launchAtLogin = !launchAtLogin
        }
    }

    private func checkLaunchAtLogin() {
        do {
            let status = try SMAppService.mainApp.status
            launchAtLogin = (status == .enabled)
        } catch {
            launchAtLogin = false
        }
    }
}
