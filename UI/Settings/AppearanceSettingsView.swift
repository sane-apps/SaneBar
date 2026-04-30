import AppKit
import SaneUI
import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var licenseService = LicenseService.shared
    @State private var proUpsellFeature: ProFeature?

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
        case 4 ... 6: return "Subtle"
        case 7 ... 10: return "Soft"
        case 11 ... 14: return "Round"
        case 15 ... 17: return "Pill"
        default: return "Circle"
        }
    }

    private var spacingLabel: String {
        let value = spacingBinding.wrappedValue
        switch value {
        case 1 ... 3: return "Tight"
        case 4 ... 6: return "Normal"
        case 7 ... 8: return "Roomy"
        default: return "Wide"
        }
    }

    private var clickAreaLabel: String {
        let value = paddingBinding.wrappedValue
        switch value {
        case 1 ... 3: return "Small"
        case 4 ... 6: return "Normal"
        case 7 ... 8: return "Large"
        default: return "Extra"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 0. Icon Style
                CompactSection("Menu Bar Icon") {
                    CompactRow("Icon") {
                        Menu {
                            ForEach(SaneBarSettings.MenuBarIconStyle.allCases, id: \.self) { style in
                                Button {
                                    selectMenuBarIconStyle(style)
                                } label: {
                                    iconMenuOptionLabel(style)
                                }
                            }
                        } label: {
                            selectedIconMenuLabel(menuBarManager.settings.menuBarIconStyle)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .frame(width: 160)
                        .help("Choose the SaneBar menu bar icon style")
                    }

                    if menuBarManager.settings.menuBarIconStyle == .custom {
                        CompactDivider()
                        CompactRow("Image") {
                            HStack(spacing: 8) {
                                if let icon = PersistenceService.shared.loadCustomIcon() {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                }
                                Button("Choose...") {
                                    showCustomIconPicker()
                                }
                                .buttonStyle(ChromeActionButtonStyle())
                            }
                        }
                    }
                }

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

                    if licenseService.isPro {
                        CompactRow("Extra Dividers") {
                            HStack {
                                Text("\(menuBarManager.settings.spacerCount)")
                                    .monospacedDigit()
                                Stepper("", value: $menuBarManager.settings.spacerCount, in: 0 ... 12)
                                    .labelsHidden()
                                    .help("Add more visual separators to organize your menu bar")
                            }
                        }

                        if menuBarManager.settings.spacerCount > 0 {
                            CompactDivider()
                            CompactRow("Extra Style") {
                                HStack(spacing: 6) {
                                    ChromeSegmentedChoiceButton(
                                        title: "Line",
                                        isSelected: menuBarManager.settings.spacerStyle == .line
                                    ) {
                                        menuBarManager.settings.spacerStyle = .line
                                    }

                                    ChromeSegmentedChoiceButton(
                                        title: "Dot",
                                        isSelected: menuBarManager.settings.spacerStyle == .dot
                                    ) {
                                        menuBarManager.settings.spacerStyle = .dot
                                    }
                                }
                                .frame(width: 120)
                                .help("Appearance of extra dividers")
                            }
                        }
                    } else {
                        proGatedRow(feature: .spacersConfig, label: "Extra Dividers")
                    }
                }

                // 2. Menu Bar Visuals — Pro
                CompactSection("Menu Bar Style") {
                    if !licenseService.isPro {
                        proGatedRow(feature: .menuBarAppearance, label: "Custom Appearance")
                        CompactDivider()
                        proGatedRow(feature: .menuBarAppearance, label: "Translucent Background")
                        CompactDivider()
                        proGatedRow(feature: .menuBarAppearance, label: "Light Tint")
                        CompactDivider()
                        proGatedRow(feature: .menuBarAppearance, label: "Dark Tint")
                        CompactDivider()
                        proGatedRow(feature: .menuBarAppearance, label: "Shadow")
                        CompactDivider()
                        proGatedRow(feature: .menuBarAppearance, label: "Border")
                        CompactDivider()
                        proGatedRow(feature: .menuBarAppearance, label: "Rounded Corners")
                    } else {
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
                                    Slider(value: $menuBarManager.settings.menuBarAppearance.tintOpacity, in: 0.05 ... 1.0, step: 0.05)
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
                                    Slider(value: $menuBarManager.settings.menuBarAppearance.tintOpacityDark, in: 0.05 ... 1.0, step: 0.05)
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
                                        Stepper("", value: $menuBarManager.settings.menuBarAppearance.cornerRadius, in: 4 ... 20, step: 2)
                                            .labelsHidden()
                                            .help("How rounded the corners are")
                                    }
                                }
                            }
                        }
                    } // end isPro else
                }

                // 3. Menu Bar Layout — Pro
                CompactSection("Menu Bar Layout") {
                    if licenseService.isPro {
                        CompactToggle(label: "Reduce space between icons", isOn: tighterSpacingEnabled)
                            .help("Make icons closer together (system-wide change, requires logout)")

                        if menuBarManager.settings.menuBarSpacing != nil {
                            CompactDivider()
                            CompactRow("Item Spacing") {
                                Stepper(spacingLabel, value: spacingBinding, in: 1 ... 10)
                                    .help("Distance between menu bar icons")
                            }
                            CompactDivider()
                            CompactRow("Click Area") {
                                Stepper(clickAreaLabel, value: paddingBinding, in: 1 ... 10)
                                    .help("Size of the clickable area around each icon")
                            }

                            CompactDivider()
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Log out to verify changes.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                        }
                    } else {
                        proGatedRow(feature: .iconSpacing, label: "Reduce space between icons")
                        CompactDivider()
                        proGatedRow(feature: .iconSpacing, label: "Item Spacing")
                        CompactDivider()
                        proGatedRow(feature: .iconSpacing, label: "Click Area")
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
    }

    // MARK: - Pro Gating Helper

    private func proGatedRow(feature: ProFeature, label: String) -> some View {
        CompactRow(label) {
            Button {
                proUpsellFeature = feature
            } label: {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
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

    private func showCustomIconPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Menu Bar Icon"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            // User cancelled — revert to filter if no custom icon exists
            if PersistenceService.shared.loadCustomIcon() == nil {
                menuBarManager.settings.menuBarIconStyle = .filter
            }
            return
        }

        guard let image = NSImage(contentsOf: url) else { return }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)

        do {
            try PersistenceService.shared.saveCustomIcon(image)
        } catch {
            print("[SaneBar] Failed to save custom icon: \(error)")
        }

        // Trigger icon update by re-setting the style
        menuBarManager.settings.menuBarIconStyle = .custom
    }

    private func selectMenuBarIconStyle(_ style: SaneBarSettings.MenuBarIconStyle) {
        if style == .custom {
            guard licenseService.isPro else {
                menuBarManager.settings.menuBarIconStyle = .filter
                proUpsellFeature = .customIcon
                return
            }
            menuBarManager.settings.menuBarIconStyle = .custom
            showCustomIconPicker()
            return
        }

        menuBarManager.settings.menuBarIconStyle = style
    }

    private func iconMenuOptionLabel(_ style: SaneBarSettings.MenuBarIconStyle) -> some View {
        HStack(spacing: 7) {
            Image(systemName: menuSymbolName(for: style))
                .frame(width: 16)

            Text(menuTitle(for: style))

            if menuBarManager.settings.menuBarIconStyle == style {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private func selectedIconMenuLabel(_ style: SaneBarSettings.MenuBarIconStyle) -> some View {
        HStack(spacing: 7) {
            if let image = selectedIconImage(for: style) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .foregroundStyle(Color.white)
                    .frame(width: 16, height: 14)
            }

            Text(menuTitle(for: style))
                .foregroundStyle(Color.white)

            Spacer()

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    private func selectedIconImage(for style: SaneBarSettings.MenuBarIconStyle) -> NSImage? {
        StatusBarController.makeSymbolImage(name: menuSymbolName(for: style))
    }

    private func menuSymbolName(for style: SaneBarSettings.MenuBarIconStyle) -> String {
        style.sfSymbolName ?? "photo"
    }

    private func menuTitle(for style: SaneBarSettings.MenuBarIconStyle) -> String {
        switch style {
        case .filter: "Filter"
        case .sliders: "Sliders"
        case .dots: "Dots"
        case .lines: "Lines"
        case .chevron: "Chevron"
        case .coin: "Circle"
        case .custom: "Custom Image..."
        }
    }
}
