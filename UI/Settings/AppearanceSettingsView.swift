import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    
    // Spacing Bindings (Copied from AdvancedSettingsView)
    private var tighterSpacingEnabled: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.menuBarSpacing != nil },
            set: { enabled in
                if enabled {
                    menuBarManager.settings.menuBarSpacing = 4
                    menuBarManager.settings.menuBarSelectionPadding = 4
                    applySpacingToSystem()
                } else {
                    resetSpacingToDefaults()
                }
            }
        )
    }

    private var spacingBinding: Binding<Int> {
        Binding(
            get: { menuBarManager.settings.menuBarSpacing ?? 6 },
            set: { newValue in
                menuBarManager.settings.menuBarSpacing = newValue
                applySpacingToSystem()
            }
        )
    }

    private var paddingBinding: Binding<Int> {
        Binding(
            get: { menuBarManager.settings.menuBarSelectionPadding ?? 8 },
            set: { newValue in
                menuBarManager.settings.menuBarSelectionPadding = newValue
                applySpacingToSystem()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Divider Style
                CompactSection("Divider Style") {
                    CompactRow("Style") {
                        Picker("", selection: $menuBarManager.settings.dividerStyle) {
                            Text("/  Slash").tag(SaneBarSettings.DividerStyle.slash)
                            Text("|  Pipe").tag(SaneBarSettings.DividerStyle.pipe)
                            Text("\\  Backslash").tag(SaneBarSettings.DividerStyle.backslash)
                            Text("❘  Thin Pipe").tag(SaneBarSettings.DividerStyle.pipeThin)
                            Text("•  Dot").tag(SaneBarSettings.DividerStyle.dot)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    
                    CompactDivider()
                    
                    CompactRow("Extra Dividers") {
                        HStack {
                            Text("\(menuBarManager.settings.spacerCount)")
                                .monospacedDigit()
                            Stepper("", value: $menuBarManager.settings.spacerCount, in: 0...12)
                                .labelsHidden()
                        }
                    }
                    
                    if menuBarManager.settings.spacerCount > 0 {
                        CompactDivider()
                        CompactRow("Extra Style") {
                            Picker("", selection: $menuBarManager.settings.spacerStyle) {
                                Text("Line").tag(SaneBarSettings.SpacerStyle.line)
                                Text("Dot").tag(SaneBarSettings.SpacerStyle.dot)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    }
                }

                // 2. Menu Bar Visuals
                CompactSection("Menu Bar Style") {
                    CompactToggle(label: "Custom Appearance", isOn: $menuBarManager.settings.menuBarAppearance.isEnabled)
                    
                    if menuBarManager.settings.menuBarAppearance.isEnabled {
                        CompactDivider()
                        
                        if MenuBarAppearanceSettings.supportsLiquidGlass {
                            CompactToggle(label: "Translucent Background", isOn: $menuBarManager.settings.menuBarAppearance.useLiquidGlass)
                            CompactDivider()
                        }
                        
                        CompactRow("Tint Color") {
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: menuBarManager.settings.menuBarAppearance.tintColor) },
                                set: { menuBarManager.settings.menuBarAppearance.tintColor = $0.toHex() }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }
                        
                        CompactDivider()
                        
                        CompactRow("Opacity") {
                            HStack {
                                Text("\(Int(menuBarManager.settings.menuBarAppearance.tintOpacity * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                Slider(value: $menuBarManager.settings.menuBarAppearance.tintOpacity, in: 0.05...1.0, step: 0.05)
                                    .frame(width: 100)
                            }
                        }
                        
                        CompactDivider()
                        CompactToggle(label: "Shadow", isOn: $menuBarManager.settings.menuBarAppearance.hasShadow)
                        CompactDivider()
                        CompactToggle(label: "Border", isOn: $menuBarManager.settings.menuBarAppearance.hasBorder)
                        CompactDivider()
                        CompactToggle(label: "Rounded Corners", isOn: $menuBarManager.settings.menuBarAppearance.hasRoundedCorners)
                        
                        if menuBarManager.settings.menuBarAppearance.hasRoundedCorners {
                             CompactDivider()
                             CompactRow("Corner Radius") {
                                 HStack {
                                     Text("\(Int(menuBarManager.settings.menuBarAppearance.cornerRadius))pt")
                                     Stepper("", value: $menuBarManager.settings.menuBarAppearance.cornerRadius, in: 4...20, step: 2)
                                         .labelsHidden()
                                 }
                             }
                        }
                    }
                }
                
                // 3. Menu Bar Layout
                CompactSection("Menu Bar Layout") {
                    CompactToggle(label: "Reduce space between icons", isOn: tighterSpacingEnabled)
                    
                    if menuBarManager.settings.menuBarSpacing != nil {
                        CompactDivider()
                        CompactRow("Item Spacing") {
                            Stepper("\(spacingBinding.wrappedValue)pt", value: spacingBinding, in: 1...20)
                        }
                        CompactDivider()
                        CompactRow("Click Area") {
                            Stepper("\(paddingBinding.wrappedValue)pt", value: paddingBinding, in: 1...20)
                        }
                        
                        CompactDivider()
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Log out to verify changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Helpers
    private func applySpacingToSystem() {
        let service = MenuBarSpacingService.shared
        do {
            try service.setSpacing(menuBarManager.settings.menuBarSpacing)
            try service.setSelectionPadding(menuBarManager.settings.menuBarSelectionPadding)
            service.attemptGracefulRefresh()
        } catch {
            print("[SaneBar] Failed to apply spacing: \(error)")
        }
    }

    private func resetSpacingToDefaults() {
        menuBarManager.settings.menuBarSpacing = nil
        menuBarManager.settings.menuBarSelectionPadding = nil
        do {
            try MenuBarSpacingService.shared.resetToDefaults()
            MenuBarSpacingService.shared.attemptGracefulRefresh()
        } catch {
            print("[SaneBar] Failed to reset spacing: \(error)")
        }
    }
}
