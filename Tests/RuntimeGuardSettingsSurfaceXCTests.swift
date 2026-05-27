@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardSettingsSurfaceXCTests: RuntimeGuardTestCase {
    func testBrowsePanelsKeepTierGatesAligned() throws {
        let secondMenuBarSource = try secondMenuBarSource()
        let gridURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowseAppGridView.swift")
        let gridSource = try String(contentsOf: gridURL, encoding: .utf8)
        let modelsURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelModels.swift")
        let modelsSource = try String(contentsOf: modelsURL, encoding: .utf8)

        XCTAssertTrue(
            modelsSource.contains("enum BrowsePanelRestrictedAction"),
            "Browse panel restrictions should stay centralized so icon panel and second menu bar gates stay aligned"
        )
        XCTAssertTrue(
            gridSource.contains("BrowsePanelRestrictedAction.upsellFeature(for: .rightClick, isPro: isPro)"),
            "Icon panel should keep right-click gating on the shared browse-panel restriction map"
        )
        XCTAssertTrue(
            gridSource.contains("BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: isPro)"),
            "Icon panel should keep move actions gated through the shared browse-panel restriction map"
        )
        XCTAssertTrue(
            gridSource.contains("BrowsePanelRestrictedAction.upsellFeature(for: .perIconHotkey, isPro: isPro)"),
            "Icon panel should keep per-icon hotkey gating on the shared browse-panel restriction map"
        )

        XCTAssertTrue(
            secondMenuBarSource.contains("BrowsePanelRestrictedAction.upsellFeature(for: .rightClick, isPro: licenseService.isPro)"),
            "Second menu bar should keep right-click gating on the shared browse-panel restriction map"
        )
        XCTAssertTrue(
            secondMenuBarSource.contains("BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: licenseService.isPro)"),
            "Second menu bar should surface the shared zone-move upsell instead of attempting restricted moves"
        )
    }

    func testSettingsSurfacesKeepExplicitProUpsells() throws {
        let generalSource = try generalSettingsSource()
        let appearanceURL = projectRootURL().appendingPathComponent("UI/Settings/AppearanceSettingsView.swift")
        let appearanceSource = try String(contentsOf: appearanceURL, encoding: .utf8)
        let rulesURL = projectRootURL().appendingPathComponent("UI/Settings/RulesSettingsView.swift")
        let rulesSource = try String(contentsOf: rulesURL, encoding: .utf8)
        let shortcutsURL = projectRootURL().appendingPathComponent("UI/Settings/ShortcutsSettingsView.swift")
        let shortcutsSource = try String(contentsOf: shortcutsURL, encoding: .utf8)

        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .zoneMoves, label: \"Move icons between Visible, Hidden, and Always Hidden\")"),
            "General settings should keep the Basic plan on an explicit zone-moves upsell instead of a dead-end row"
        )
        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .touchIDProtection, label: \"Touch ID to unlock hidden icons\")"),
            "General settings should keep Touch ID protection behind an explicit upsell row"
        )
        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .settingsProfiles, label: \"Save and load configurations\")"),
            "General settings should keep saved profiles behind an explicit upsell row"
        )
        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .exportImport, label: \"Export, import, and migrate settings\")"),
            "General settings should keep data import/export behind an explicit upsell row"
        )
        XCTAssertTrue(
            generalSource.contains(".sheet(item: $proUpsellFeature) { feature in"),
            "General settings should still present a Pro upsell sheet for gated rows"
        )

        XCTAssertTrue(
            appearanceSource.contains("proUpsellFeature = .customIcon"),
            "Appearance settings should route custom icon selection to the Pro upsell instead of silently resetting"
        )
        XCTAssertTrue(
            appearanceSource.contains("proGatedRow(feature: .spacersConfig, label: \"Extra Dividers\")"),
            "Appearance settings should keep extra dividers behind an explicit upsell row"
        )
        XCTAssertTrue(
            appearanceSource.contains("Movable visual dividers") &&
                appearanceSource.contains("Command-drag them into place") &&
                appearanceSource.contains("do not create extra hidden sections"),
            "Extra Dividers copy should explain that the setting adds movable visual separators, not hidden-section layers"
        )
        XCTAssertTrue(
            appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Custom Appearance\")") &&
                appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Translucent Background\")") &&
                appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Light Tint\")") &&
                appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Dark Tint\")") &&
                appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Shadow\")") &&
                appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Border\")") &&
                appearanceSource.contains("proGatedRow(feature: .menuBarAppearance, label: \"Rounded Corners\")"),
            "Appearance settings should show individual Basic-visible locked rows for menu bar styling value"
        )
        XCTAssertTrue(
            appearanceSource.contains("proGatedRow(feature: .iconSpacing, label: \"Reduce space between icons\")") &&
                appearanceSource.contains("proGatedRow(feature: .iconSpacing, label: \"Item Spacing\")") &&
                appearanceSource.contains("proGatedRow(feature: .iconSpacing, label: \"Click Area\")"),
            "Appearance settings should show individual Basic-visible locked rows for menu bar layout value"
        )
        XCTAssertTrue(
            appearanceSource.contains(".sheet(item: $proUpsellFeature) { feature in"),
            "Appearance settings should still present a Pro upsell sheet for gated rows"
        )

        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .autoRehideCustomization, label: \"Customize auto-hide timing\")"),
            "Control settings should keep auto-rehide tuning behind an explicit upsell row"
        )
        XCTAssertTrue(
            generalSource.contains("Reveal hidden icons on hover") &&
                generalSource.contains("Click the SaneBar icon to open or toggle manually"),
            "Hover settings should say they reveal hidden icons inline instead of implying they open Browse Icons"
        )
        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .autoRehideCustomization, label: \"Always show on external monitors\")"),
            "Control settings should keep external-monitor behavior behind an explicit upsell row"
        )
        XCTAssertTrue(
            generalSource.contains("proGatedRow(feature: .gestureCustomization, label: \"Customize gesture behavior\")"),
            "Control settings should keep gesture customization behind an explicit upsell row"
        )
        XCTAssertFalse(
            rulesSource.contains("Battery, schedule, Wi-Fi, Focus, app, and script triggers"),
            "Rules settings should not hide all trigger value behind one generic Pro row"
        )
        XCTAssertTrue(
            rulesSource.contains("proTriggerRow(") &&
                rulesSource.contains("label: \"Show on Low Battery\"") &&
                rulesSource.contains("label: \"Show when specific apps open\"") &&
                rulesSource.contains("label: \"Show on Schedule\"") &&
                rulesSource.contains("label: \"Show on Wi-Fi Change\"") &&
                rulesSource.contains("label: \"Show on Focus Mode Change\"") &&
                rulesSource.contains("label: \"Let a script control visibility\""),
            "Rules settings should show each advanced trigger as its own Basic-visible locked row"
        )
        XCTAssertTrue(
            rulesSource.contains("proUpsellFeature = .advancedTriggers"),
            "Each locked trigger row should open the contextual advanced-trigger upsell"
        )
        XCTAssertTrue(
            rulesSource.contains(".sheet(item: $proUpsellFeature) { feature in"),
            "Rules settings should still present a Pro upsell sheet for gated rows"
        )

        XCTAssertTrue(
            shortcutsSource.contains("proLockedRow(feature: .additionalShortcuts, label: \"Show icons\")") &&
                shortcutsSource.contains("proLockedRow(feature: .additionalShortcuts, label: \"Hide icons\")") &&
                shortcutsSource.contains("proLockedRow(feature: .additionalShortcuts, label: \"Open Settings\")"),
            "Shortcuts settings should show each Pro hotkey as an individual Basic-visible locked row"
        )
        XCTAssertTrue(
            shortcutsSource.contains("proAutomationCommandRow(item)") &&
                shortcutsSource.contains("Unlock Pro to copy and use this automation command"),
            "Shortcuts settings should show each Pro automation command as an individual Basic-visible locked row"
        )
        XCTAssertTrue(
            shortcutsSource.contains("proLockedRow(feature: .appleScript, label: \"Toggle action\")") &&
                shortcutsSource.contains("proLockedRow(feature: .appleScript, label: \"Profiles actions\")") &&
                shortcutsSource.contains("proLockedRow(feature: .appleScript, label: \"Search action\")"),
            "Shortcuts settings should show App Shortcuts actions individually in Basic"
        )
        XCTAssertTrue(
            shortcutsSource.contains(".sheet(item: $proUpsellFeature) { feature in"),
            "Shortcuts settings should still present a Pro upsell sheet for gated rows"
        )
    }

    func testSettingsHoverHelpExplainsHealthAndLayoutActions() throws {
        let healthURL = projectRootURL().appendingPathComponent("UI/Settings/HealthSettingsView.swift")
        let healthSource = try String(contentsOf: healthURL, encoding: .utf8)
        let generalSource = try generalSettingsSource()

        XCTAssertTrue(
            healthSource.contains("import SaneUI") &&
                generalSource.contains("import SaneUI") &&
                healthSource.contains(".saneHelp(") &&
                healthSource.contains("SaneInlineHelp(") &&
                !healthSource.contains("overlay(alignment: .bottomTrailing)") &&
                !healthSource.contains("QuickActionHelpModifier"),
            "Settings should use the shared SaneUI native Apple hover-help standard instead of fragile app-local overlays"
        )
        XCTAssertTrue(
            healthSource.contains(".saneHelp(accessibilityHelp)") &&
                healthSource.contains(".saneHelp(geometryHelp)") &&
                healthSource.contains(".saneHelp(structureHelp)") &&
                healthSource.contains("SaneInlineHelp(layoutModeHelp)") &&
                healthSource.contains("if !accessibilityService.isGranted") &&
                healthSource.contains("openAccessibilitySettings()") &&
                healthSource.contains(".accessibilityLabel(\"Open Accessibility settings\")") &&
                healthSource.contains("if needsGeometryAction") &&
                healthSource.contains("runRepair(reason: \"health-geometry-fix\"") &&
                healthSource.contains("repairMenuBarHealth(reason: reason)") &&
                healthSource.contains("repairInProgress") &&
                healthSource.contains(".accessibilityLabel(\"Fix menu bar geometry\")") &&
                healthSource.contains("if needsStructureAction") &&
                healthSource.contains("runRepair(reason: \"health-items-fix\"") &&
                healthSource.contains(".accessibilityLabel(\"Fix SaneBar items\")") &&
                healthSource.contains("menuBarManager.profileWorkflow.setLayoutMode(mode, reason: \"health\")") &&
                healthSource.contains("Button(\"Stability\")") &&
                healthSource.contains("Button(\"Live\")") &&
                healthSource.contains("func setLayoutMode(_ mode: SaneBarSettings.LayoutMode)"),
            "Health should explain status rows, provide one-click repair actions for warning states, and expose clickable Stability/Live layout mode choices"
        )
        XCTAssertTrue(
            healthSource.contains("Copies a support report with current permissions, layout state, item counts, and recent diagnostics"),
            "Health support actions should say exactly what clicking them does"
        )
        XCTAssertTrue(
            generalSource.contains("layoutModeDescription") &&
                generalSource.contains("liveLayoutChecksBinding") &&
                generalSource.contains("menuBarManager.profileWorkflow.setLayoutMode(enabled ? .live : .stability, reason: \"control\")") &&
                generalSource.contains("menuBarManager.profileWorkflow.repairMenuBarHealth(reason: \"control\")") &&
                generalSource.contains("Live checks after wake/display changes") &&
                generalSource.contains("Layout Repair") &&
                generalSource.contains("Repair after wake or display changes") &&
                generalSource.contains("SaneInlineHelp(layoutModeDescription)") &&
                generalSource.contains("Stability repairs only at startup"),
            "Layout Stability should expose Live mode as a plain switch with visible and hover copy instead of a confusing one-option mode selector"
        )
    }

    func testAppearanceIconMenuUsesRuntimeSymbolsInsteadOfApproximateGlyphs() throws {
        let appearanceURL = projectRootURL().appendingPathComponent("UI/Settings/AppearanceSettingsView.swift")
        let appearanceSource = try String(contentsOf: appearanceURL, encoding: .utf8)

        XCTAssertTrue(
            appearanceSource.contains("menuSymbolName(for style: SaneBarSettings.MenuBarIconStyle)") &&
                appearanceSource.contains("selectedIconImage(for style: SaneBarSettings.MenuBarIconStyle)") &&
                appearanceSource.contains("StatusBarController.makeSymbolImage(name: menuSymbolName(for: style))") &&
                appearanceSource.contains("Image(systemName: menuSymbolName(for: style))"),
            "Menu Bar Icon options should render the same SF Symbols as the actual status item instead of approximate glyphs"
        )
        XCTAssertFalse(
            appearanceSource.contains("pickerIconOptionLabel(\"Filter\", glyph:"),
            "Menu Bar Icon picker rows should not approximate the actual Filter status icon with text glyphs"
        )
    }

    func testAppearanceIconMenuUsesEnabledMenuButtonsAndRuntimeSymbols() throws {
        let appearanceURL = projectRootURL().appendingPathComponent("UI/Settings/AppearanceSettingsView.swift")
        let appearanceSource = try String(contentsOf: appearanceURL, encoding: .utf8)
        let settingsURL = projectRootURL().appendingPathComponent("Core/Services/PersistenceService.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)

        XCTAssertTrue(
            appearanceSource.contains("Menu {") &&
                appearanceSource.contains("Button {") &&
                appearanceSource.contains("selectMenuBarIconStyle(style)") &&
                appearanceSource.contains("selectedIconMenuLabel"),
            "Icon style selection should use real Menu button actions instead of custom Picker rows that can render as disabled gray"
        )
        XCTAssertFalse(
            appearanceSource.contains("Picker(\"\", selection: $menuBarManager.settings.menuBarIconStyle)"),
            "Icon style selection should not return to the custom Picker presentation that made enabled options look disabled"
        )
        XCTAssertTrue(
            settingsSource.contains("case .filter: \"line.3.horizontal.decrease\"") &&
                appearanceSource.contains("style.sfSymbolName ?? \"photo\""),
            "Icon style menu rows should use the same symbols as the runtime status item, with Filter matching the actual menu bar icon"
        )
    }

    func testSettingsWindowIsResizableWithSaneBarOwnedSizing() throws {
        let appURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let settingsURL = projectRootURL().appendingPathComponent("UI/SettingsView.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)

        XCTAssertTrue(
            appSource.contains("let window = SaneSettingsWindow(") &&
                appSource.contains("styleMask: [.titled, .closable, .resizable, .miniaturizable]") &&
                appSource.contains("window.contentViewController = hostingController") &&
                appSource.contains("SaneSettingsWindowDefaults.minWidth") &&
                appSource.contains("SaneBarSettingsWindowMetrics.idealHeight") &&
                settingsSource.contains("SaneSettingsContainer(defaultTab: defaultTab, windowSizing: .embedded)") &&
                settingsSource.contains("SaneSettingsResizeGrip()") &&
                !settingsSource.contains("struct SettingsResizeGrip") &&
                !settingsSource.contains("class SettingsResizeGripView") &&
                !settingsSource.contains("NSEvent.mouseLocation") &&
                !settingsSource.contains("window.setFrame(frame, display: true, animate: false)") &&
                !settingsSource.contains("DragGesture(minimumDistance: 1)") &&
                !settingsSource.contains("RoundedRectangle(cornerRadius: 6"),
            "Settings should stay resizable through the SaneBar-owned NSWindow and shared SaneUI resize grip, without app-local resize chrome"
        )
    }

    func testDirectLicenseEntryCopyStaysAlignedWithSupportInstructions() throws {
        let licenseServiceURL = projectRootURL().appendingPathComponent("Core/Services/LicenseService.swift")
        let licenseServiceSource = try String(contentsOf: licenseServiceURL, encoding: .utf8)
        let settingsURL = projectRootURL().appendingPathComponent("UI/SettingsView.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)
        let upsellURL = projectRootURL().appendingPathComponent("UI/Pro/ProUpsellView.swift")
        let upsellSource = try String(contentsOf: upsellURL, encoding: .utf8)

        XCTAssertTrue(
            licenseServiceSource.contains("[\"I Have\", \"a License Key\"].joined(separator: \" \")"),
            "Direct builds should keep the existing-customer CTA wording stable for support instructions"
        )
        XCTAssertTrue(
            licenseServiceSource.contains("[\"Enter\", \"License\", \"Key\"].joined(separator: \" \")"),
            "Direct builds should keep the shared license-entry button wording stable for support instructions"
        )
        XCTAssertTrue(
            licenseServiceSource.contains("Paste the\", licenseKeyLabel().lowercased(), \"from your purchase confirmation email."),
            "Direct builds should keep the license-entry helper copy aligned with purchase-email instructions"
        )
        XCTAssertTrue(
            settingsSource.contains("case license = \"License\""),
            "Settings should keep the dedicated License tab available for direct activation guidance"
        )
        XCTAssertTrue(
            settingsSource.contains("LicenseSettingsView<SaneBarLicenseSettingsAdapter>("),
            "Settings should keep activation flowing through the shared License tab surface"
        )
        XCTAssertTrue(
            upsellSource.contains("Button(LicenseService.existingCustomerButtonLabel())"),
            "Upsell windows should keep the existing-customer escape hatch visible"
        )
        XCTAssertTrue(
            upsellSource.contains("LicenseEntryView(licenseService: SaneBarLicenseSettingsAdapter.shared)") &&
                upsellSource.contains(".sheet(isPresented: $showingLicenseEntry)") &&
                upsellSource.contains("import SaneUI"),
            "The direct license-entry sheet should still expose an explicit Activate action"
        )
    }

    func testSettingsOpenerRetargetsExistingWindowForDeepLinks() throws {
        let appURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if let existingWindow = settingsWindow") &&
                source.contains("existingWindow.contentViewController = NSHostingController(rootView: SettingsView(defaultTab: tab))") &&
                source.contains("enforceUsableWindowSize(existingWindow, preferIdealSize: false)") &&
                source.contains("enforceUsableWindowSize(window, preferIdealSize: true)") &&
                source.contains("width: max(contentSize.width, minimumSize.width)") &&
                source.contains("height: max(contentSize.height, minimumSize.height)"),
            "SettingsOpener should switch an already-open settings window when Health/Repair deep links request a specific tab without collapsing below the shared settings window minimum"
        )
    }

    func testSecondMenuBarRowControlsStayAsTopToggleChips() throws {
        let source = try secondMenuBarSource()

        XCTAssertTrue(
            source.contains("ScrollView(.horizontal, showsIndicators: false)"),
            "Row toggles should stay in a compact horizontal strip above the actual rows"
        )
        XCTAssertTrue(
            source.contains("Text(SecondMenuBarLayout.rowStateLabel(isOn: isOn))"),
            "Top row toggles should keep a small inline On/Off state instead of a second row-like control"
        )
        XCTAssertTrue(
            source.contains("SaneBarChrome.activeControlFill") &&
                source.contains("SaneBarChrome.utilityFill") &&
                source.contains(".padding(.vertical, 4)"),
            "Top row toggles should keep compact capsule sizing while using the shared solid control fills"
        )
        XCTAssertFalse(
            source.contains("Color.green.opacity"),
            "Top row toggles should not fall back to a bright green status color that overwhelms the panel"
        )
        XCTAssertFalse(
            source.contains("Text(isTargeted ? \"Drop here\" : \"Drag icons here\")") ||
                source.contains(".scaleEffect(isTargeted ?"),
            "Second menu bar drop targets should not change text or size while dragging over Hidden, Visible, or Always Hidden"
        )
    }

    func testBrowseIconGroupTabsConstrainLongLabels() throws {
        let tabURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchTabs.swift")
        let source = try String(contentsOf: tabURL, encoding: .utf8)
        guard let groupTabBody = source.components(separatedBy: "struct GroupTabButton: View").last else {
            XCTFail("GroupTabButton should remain the dedicated custom group tab view")
            return
        }

        XCTAssertTrue(
            groupTabBody.contains(".lineLimit(1)") &&
                groupTabBody.contains(".truncationMode(.tail)") &&
                groupTabBody.contains(".frame(maxWidth: 148)"),
            "Browse Icons tabs should keep long QA/custom group names from overflowing or clipping neighboring controls"
        )
        let smartTabBody = source
            .components(separatedBy: "struct GroupTabButton: View")
            .first ?? source
        XCTAssertFalse(
            smartTabBody.contains(".frame(maxWidth: 148)"),
            "Built-in Browse Icons tabs and the + Custom button should keep their natural width"
        )
    }

    func testSaneBarUsesSharedPanelBackgroundsFromSaneUI() throws {
        let settingsSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/SettingsView.swift"),
            encoding: .utf8
        )
        let iconPanelSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/SearchWindow/BrowseFindIconPanelView.swift"),
            encoding: .utf8
        )
        let secondMenuBarSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/SearchWindow/SecondMenuBarView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            settingsSource.contains("import SaneUI") &&
                iconPanelSource.contains("import SaneUI") &&
                secondMenuBarSource.contains("import SaneUI"),
            "SaneBar surfaces should import SaneUI directly instead of relying on a local background copy"
        )
        XCTAssertTrue(
            settingsSource.contains("SaneSettingsContainer(defaultTab: defaultTab") &&
                iconPanelSource.contains("SaneGradientBackground(style: .panel)") &&
                secondMenuBarSource.contains("SaneGradientBackground(style: .panel)"),
            "Settings should use the shared SaneUI container, and both browse surfaces should use the calmer shared panel background"
        )
        XCTAssertTrue(
            settingsSource.contains("case license = \"License\"") &&
                settingsSource.contains("LicenseSettingsView<SaneBarLicenseSettingsAdapter>("),
            "SaneBar settings should expose a dedicated shared License tab instead of keeping an app-local inline license block"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: projectRootURL().appendingPathComponent("UI/Components/Backgrounds.swift").path
            ),
            "SaneBar should not keep a local gradient background clone once SaneUI owns the shared panel background"
        )
        XCTAssertTrue(
            settingsSource.contains("SaneSettingsContainer(defaultTab: defaultTab") &&
                settingsSource.contains("var defaultTab: SettingsTab = .control") &&
                settingsSource.contains("SaneSettingsResizeGrip()"),
            "Settings shell should come from the pinned SaneUI package so shared settings chrome stays unified across apps"
        )
        XCTAssertFalse(
            settingsSource.contains("struct SettingsResizeGrip") ||
                settingsSource.contains("class SettingsResizeGripView"),
            "SaneBar should not keep local resize-grip chrome in settings"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: projectRootURL().appendingPathComponent("UI/Settings/GlassGroupBoxStyle.swift").path
            ),
            "SaneBar should not keep a local GroupBoxStyle clone once SaneUI owns the shared glass group box styling"
        )
    }

    func testSaneBarChromeComponentsAreTypealiasesToSaneUI() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/Components/CompactSettingsComponents.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("typealias ChromeGlassRoundedBackground = SaneUI.SaneGlassRoundedBackground") &&
                source.contains("typealias ChromeActionButtonStyle = SaneUI.SaneActionButtonStyle") &&
                source.contains("typealias ChromeBadge = SaneUI.SaneAccentBadge"),
            "SaneBar should reuse SaneUI chrome components instead of carrying local glass/button/badge implementations"
        )
        XCTAssertFalse(
            source.contains("struct ChromeGlassRoundedBackground") ||
                source.contains("struct ChromeActionButtonStyle") ||
                source.contains("struct CompactSection<") ||
                source.contains("struct CompactRow<") ||
                source.contains("struct CompactToggle") ||
                source.contains("struct CompactDivider"),
            "SaneBar should not keep local implementations of the shared settings chrome primitives"
        )
    }

}
