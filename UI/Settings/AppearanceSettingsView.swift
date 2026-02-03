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

    // MARK: - User-Friendly Labels (instead of "pt" jargon)

    private var cornerRadiusLabel: String {
        let value = Int(menuBarManager.settings.menuBarAppearance.cornerRadius)
        switch value {
        case 4...6: return "Subtle"
        case 7...10: return "Soft"
        case 11...14: return "Round"
        case 15...17: return "Pill"
        default: return "Circle"
        }
    }

    private var spacingLabel: String {
        let value = spacingBinding.wrappedValue
        switch value {
        case 1...3: return "Tight"
        case 4...6: return "Normal"
        case 7...8: return "Roomy"
        default: return "Wide"
        }
    }

    private var clickAreaLabel: String {
        let value = paddingBinding.wrappedValue
        switch value {
        case 1...3: return "Small"
        case 4...6: return "Normal"
        case 7...8: return "Large"
        default: return "Extra"
        }
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
                        .help("Character shown between visible and hidden icons")
                    }

                    CompactDivider()

                    CompactRow("Extra Dividers") {
                        HStack {
                            Text("\(menuBarManager.settings.spacerCount)")
                                .monospacedDigit()
                            Stepper("", value: $menuBarManager.settings.spacerCount, in: 0...12)
                                .labelsHidden()
                                .help("Add more visual separators to organize your menu bar")
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
                            .help("Appearance of extra dividers")
                        }
                    }
                }

                // 2. Menu Bar Visuals
                CompactSection("Menu Bar Style") {
                    CompactToggle(label: "Custom Appearance", isOn: $menuBarManager.settings.menuBarAppearance.isEnabled)
                    .help("Apply custom colors and effects to the menu bar background")

                    if menuBarManager.settings.menuBarAppearance.isEnabled {
                        CompactDivider()

                        if MenuBarAppearanceSettings.supportsLiquidGlass {
                            CompactToggle(label: "Translucent Background", isOn: $menuBarManager.settings.menuBarAppearance.useLiquidGlass)
                            .help("Use macOS translucent glass effect")
                            CompactDivider()
                        }

                        CompactRow("Light Tint") {
                            HStack(spacing: 8) {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: menuBarManager.settings.menuBarAppearance.tintColor) },
                                    set: { menuBarManager.settings.menuBarAppearance.tintColor = $0.toHex() }
                                ), supportsOpacity: false)
                                .labelsHidden()
                                Text("\(Int(menuBarManager.settings.menuBarAppearance.tintOpacity * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 35, alignment: .trailing)
                                Slider(value: $menuBarManager.settings.menuBarAppearance.tintOpacity, in: 0.05...1.0, step: 0.05)
                                    .frame(width: 80)
                            }
                            .help("Tint color and intensity for light mode")
                        }

                        CompactDivider()

                        CompactRow("Dark Tint") {
                            HStack(spacing: 8) {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: menuBarManager.settings.menuBarAppearance.tintColorDark) },
                                    set: { menuBarManager.settings.menuBarAppearance.tintColorDark = $0.toHex() }
                                ), supportsOpacity: false)
                                .labelsHidden()
                                Text("\(Int(menuBarManager.settings.menuBarAppearance.tintOpacityDark * 100))%")
                                    .monospacedDigit()
                                    .frame(width: 35, alignment: .trailing)
                                Slider(value: $menuBarManager.settings.menuBarAppearance.tintOpacityDark, in: 0.05...1.0, step: 0.05)
                                    .frame(width: 80)
                            }
                            .help("Tint color and intensity for dark mode")
                        }

                        CompactDivider()
                        CompactToggle(label: "Shadow", isOn: $menuBarManager.settings.menuBarAppearance.hasShadow)
                        .help("Add subtle shadow below the menu bar")
                        CompactDivider()
                        CompactToggle(label: "Border", isOn: $menuBarManager.settings.menuBarAppearance.hasBorder)
                        .help("Add a thin border around the menu bar")
                        CompactDivider()
                        CompactToggle(label: "Rounded Corners", isOn: $menuBarManager.settings.menuBarAppearance.hasRoundedCorners)
                        .help("Round the corners of the menu bar background")

                        if menuBarManager.settings.menuBarAppearance.hasRoundedCorners {
                             CompactDivider()
                             CompactRow("Corner Radius") {
                                 HStack {
                                     Text(cornerRadiusLabel)
                                         .frame(width: 50, alignment: .trailing)
                                     Stepper("", value: $menuBarManager.settings.menuBarAppearance.cornerRadius, in: 4...20, step: 2)
                                         .labelsHidden()
                                         .help("How rounded the corners are")
                                 }
                             }
                        }
                    }
                }
                
                // 3. Menu Bar Layout
                CompactSection("Menu Bar Layout") {
                    CompactToggle(label: "Reduce space between icons", isOn: tighterSpacingEnabled)
                    .help("Make icons closer together (system-wide change, requires logout)")

                    if menuBarManager.settings.menuBarSpacing != nil {
                        CompactDivider()
                        CompactRow("Item Spacing") {
                            Stepper(spacingLabel, value: spacingBinding, in: 1...10)
                            .help("Distance between menu bar icons")
                        }
                        CompactDivider()
                        CompactRow("Click Area") {
                            Stepper(clickAreaLabel, value: paddingBinding, in: 1...10)
                            .help("Size of the clickable area around each icon")
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
