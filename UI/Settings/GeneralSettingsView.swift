import SwiftUI
import LaunchAtLogin

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared

    // MARK: - Computed Properties

    /// Binding for Dock icon visibility that applies the activation policy when changed
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Startup - FIRST (most important)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        LaunchAtLogin.Toggle {
                            Text("Start SaneBar when you log in")
                        }

                        Toggle("Show Dock icon", isOn: showDockIconBinding)

                        if !menuBarManager.settings.showDockIcon {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text("SaneBar will run in the menu bar only (no Dock icon)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Startup", systemImage: "power")
                }

                // Auto-hide
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Auto-hide after showing", isOn: $menuBarManager.settings.autoRehide)

                        if menuBarManager.settings.autoRehide {
                            HStack {
                                Text("Delay:")
                                Slider(value: $menuBarManager.settings.rehideDelay, in: 1...10, step: 1)
                                Text("\(Int(menuBarManager.settings.rehideDelay)) seconds")
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Auto-hide", systemImage: "eye.slash")
                }

                // How it works - clear step-by-step
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        // Step 1: The icons
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your menu bar icons:").fontWeight(.medium)
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("SaneBar Icon")
                                    Text("SaneBar")
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "line.diagonal")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("Separator Icon")
                                    Text("Separator")
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Step 2: How to organize
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.draw")
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                                Text("**⌘+drag** icons to organize them")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("• Left of separator = can be hidden")
                                Text("• Right of separator = always visible")
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 28)
                        }

                        Divider()

                        // Step 3: Toggle
                        HStack(spacing: 8) {
                            Image(systemName: "cursorarrow.click.2")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text("**Click SaneBar icon** to show/hide")
                        }

                        if menuBarManager.hasNotch {
                            Divider()
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("**Notch detected** — keep important icons to the right of SaneBar")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("How it works", systemImage: "questionmark.circle")
                }
            }
            .padding()
        }
        .onChange(of: menuBarManager.settings) { _, _ in
            menuBarManager.saveSettings()
        }
    }
}
