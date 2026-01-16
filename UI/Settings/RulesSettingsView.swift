import SwiftUI
import AppKit

struct RulesSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Behavior (Hiding)
                CompactSection("Hiding Behavior") {
                    CompactToggle(label: "Hide icons automatically", isOn: $menuBarManager.settings.autoRehide)
                    
                    if menuBarManager.settings.autoRehide {
                        CompactDivider()
                        CompactRow("Wait before hiding") {
                            HStack {
                                Text("\(Int(menuBarManager.settings.rehideDelay))s")
                                    .monospacedDigit()
                                Stepper("", value: $menuBarManager.settings.rehideDelay, in: 1...60, step: 1)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                // 2. Gestures (Revealing)
                CompactSection("Revealing") {
                    CompactToggle(label: "Show when mouse hovers top edge", isOn: $menuBarManager.settings.showOnHover)
                    
                    if menuBarManager.settings.showOnHover {
                        CompactDivider()
                        CompactRow("Hover Delay") {
                            HStack {
                                Slider(value: $menuBarManager.settings.hoverDelay, in: 0.05...1.0, step: 0.05)
                                    .frame(width: 80)
                                Text("\(Int(menuBarManager.settings.hoverDelay * 1000))ms")
                                    .monospacedDigit()
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                    
                    CompactDivider()
                    CompactToggle(label: "Show when scrolling on menu bar", isOn: $menuBarManager.settings.showOnScroll)
                }

                // 3. Triggers (Automation)
                CompactSection("Automatic Triggers") {
                    // Battery
                    CompactToggle(label: "Show on Low Battery", isOn: $menuBarManager.settings.showOnLowBattery)
                    
                    CompactDivider()
                    
                    // App Launch
                    CompactToggle(label: "Show when specific apps open", isOn: $menuBarManager.settings.showOnAppLaunch)
                    
                    if menuBarManager.settings.showOnAppLaunch {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If these apps open:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            
                            AppPickerView(
                                selectedBundleIDs: $menuBarManager.settings.triggerApps,
                                title: "Select Apps"
                            )
                            .padding(.horizontal, 4)
                        }
                        .padding(.vertical, 8)
                    }

                    CompactDivider()

                    // Network
                    CompactToggle(label: "Show on Wi-Fi Change", isOn: $menuBarManager.settings.showOnNetworkChange)
                    
                    if menuBarManager.settings.showOnNetworkChange {
                        VStack(alignment: .leading, spacing: 8) {
                            if let ssid = menuBarManager.networkTriggerService.currentSSID {
                                Button {
                                    if !menuBarManager.settings.triggerNetworks.contains(ssid) {
                                        menuBarManager.settings.triggerNetworks.append(ssid)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "wifi")
                                        Text("Add current: \(ssid)")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            ForEach(menuBarManager.settings.triggerNetworks, id: \.self) { network in
                                HStack {
                                    Text(network)
                                    Spacer()
                                    Button {
                                        menuBarManager.settings.triggerNetworks.removeAll { $0 == network }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(20)
        }
    }
}
