@testable import SaneBar
import XCTest

final class GeneralSettingsSimplificationXCTests: XCTestCase {
    func testLeftClickModeOpenBrowseIconsTitle() {
        let title = GeneralSettingsView.BrowseLeftClickMode.openBrowseIcons.title
        XCTAssertEqual(title, "Open Browse")
    }

    func testLeftClickModeToggleHiddenTitle() {
        let title = GeneralSettingsView.BrowseLeftClickMode.toggleHidden.title
        XCTAssertEqual(title, "Toggle Hidden")
    }

    func testSecondMenuBarPresetResolveMinimal() {
        let preset = GeneralSettingsView.SecondMenuBarPreset.resolve(
            showVisible: false,
            showAlwaysHidden: false
        )
        XCTAssertEqual(preset, .minimal)
    }

    func testSecondMenuBarPresetTitlesUsePlainLanguage() {
        XCTAssertEqual(GeneralSettingsView.SecondMenuBarPreset.minimal.title, "Hidden Row")
        XCTAssertEqual(GeneralSettingsView.SecondMenuBarPreset.balanced.title, "Hidden + Visible")
        XCTAssertEqual(GeneralSettingsView.SecondMenuBarPreset.power.title, "All Rows")
    }

    func testSecondMenuBarPresetResolveBalanced() {
        let preset = GeneralSettingsView.SecondMenuBarPreset.resolve(
            showVisible: true,
            showAlwaysHidden: false
        )
        XCTAssertEqual(preset, .balanced)
    }

    func testSecondMenuBarPresetResolvePower() {
        let preset = GeneralSettingsView.SecondMenuBarPreset.resolve(
            showVisible: true,
            showAlwaysHidden: true
        )
        XCTAssertEqual(preset, .power)
    }

    func testSecondMenuBarPresetResolvePowerFromAlwaysHiddenOnly() {
        let preset = GeneralSettingsView.SecondMenuBarPreset.resolve(
            showVisible: false,
            showAlwaysHidden: true
        )
        XCTAssertEqual(preset, .power)
    }

    func testFreeSecondMenuBarCanKeepLeftClickOpenBrowse() {
        let normalized = MenuBarActionWorkflow.normalizedLeftClickOpensBrowseIcons(
            isPro: false,
            useSecondMenuBar: true,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertTrue(normalized)
    }

    func testProSecondMenuBarKeepsLeftClickOpenBrowse() {
        let normalized = MenuBarActionWorkflow.normalizedLeftClickOpensBrowseIcons(
            isPro: true,
            useSecondMenuBar: true,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertTrue(normalized)
    }

    func testFreeIconPanelCanKeepLeftClickOpenBrowse() {
        let normalized = MenuBarActionWorkflow.normalizedLeftClickOpensBrowseIcons(
            isPro: false,
            useSecondMenuBar: false,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertTrue(normalized)
    }

    func testFreeModeNormalizesSecondMenuBarRowsToVisibleAndHidden() {
        let normalized = MenuBarActionWorkflow.normalizedSecondMenuBarRows(
            isPro: false,
            showVisible: false,
            showAlwaysHidden: true
        )
        XCTAssertTrue(normalized.showVisible)
        XCTAssertFalse(normalized.showAlwaysHidden)
    }

    func testProModeKeepsSecondMenuBarRows() {
        let normalized = MenuBarActionWorkflow.normalizedSecondMenuBarRows(
            isPro: true,
            showVisible: true,
            showAlwaysHidden: false
        )
        XCTAssertTrue(normalized.showVisible)
        XCTAssertFalse(normalized.showAlwaysHidden)
    }

    func testFreeModeDisablesAlwaysHiddenSectionEffectively() {
        XCTAssertFalse(
            MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
                isPro: false,
                alwaysHiddenSectionEnabled: true
            )
        )
    }

    func testProModeKeepsAlwaysHiddenSectionWhenEnabled() {
        XCTAssertTrue(
            MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
                isPro: true,
                alwaysHiddenSectionEnabled: true
            )
        )
    }

    @MainActor
    func testLaunchTimeProTrialDoesNotNormalizeRowsBeforeObserversExist() {
        LicenseService.shared.deactivate()

        let persistence = PersistenceServiceProtocolMock()
        let manager = MenuBarManager(
            persistenceService: persistence,
            settingsController: SettingsController(persistence: persistence)
        )
        manager.settings.useSecondMenuBar = true
        manager.settings.secondMenuBarShowVisible = false
        manager.settings.secondMenuBarShowAlwaysHidden = true
        manager.settings.leftClickOpensBrowseIcons = true

        manager.actionWorkflow.normalizeLicenseDependentDefaults()

        XCTAssertFalse(manager.settings.secondMenuBarShowVisible)
        XCTAssertTrue(manager.settings.secondMenuBarShowAlwaysHidden)
        XCTAssertTrue(manager.settings.leftClickOpensBrowseIcons)
        XCTAssertEqual(persistence.saveSettingsCallCount, 0)
    }

    func testSparkleUpdatesAllowedForReleaseBundleIdentifier() {
        XCTAssertTrue(UpdateService.supportsSparkleUpdates(bundleIdentifier: "com.sanebar.app"))
    }

    func testSparkleUpdatesRejectedForDevBundleIdentifier() {
        XCTAssertFalse(UpdateService.supportsSparkleUpdates(bundleIdentifier: "com.sanebar.dev"))
    }

    func testSparkleUpdatesRejectedWhenBundleIdentifierMissing() {
        XCTAssertFalse(UpdateService.supportsSparkleUpdates(bundleIdentifier: nil))
    }

    func testScheduledUpdateReminderNotificationIdentifierIsStable() {
        XCTAssertEqual(UpdateService.scheduledUpdateReminderNotificationID, "com.sanebar.app.sparkle.scheduled-update")
    }

    func testScheduledUpdateReminderDockBadgeFollowsDockSetting() {
        XCTAssertTrue(UpdateService.shouldShowScheduledUpdateDockBadge(showDockIcon: true))
        XCTAssertFalse(UpdateService.shouldShowScheduledUpdateDockBadge(showDockIcon: false))
    }

    func testUpdateUnavailableTooltipMatchesDistributionChannel() {
        XCTAssertEqual(
            MenuBarActionWorkflow.updateUnavailableTooltip(for: .direct),
            "Updates are available from the installed /Applications/SaneBar.app build."
        )
        XCTAssertEqual(
            MenuBarActionWorkflow.updateUnavailableTooltip(for: .appStore),
            "Updates are managed by the App Store."
        )
        XCTAssertEqual(
            MenuBarActionWorkflow.updateUnavailableTooltip(for: .setapp),
            "Updates are managed by Setapp."
        )
    }

    func testSetappBuildDoesNotRenderGeneralSettingsUpdateSection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("UI/Settings/GeneralSettingsView.swift"))

        XCTAssertTrue(source.contains("if licenseService.distributionChannel.supportsInAppUpdates {\n                    softwareUpdatesSection\n                }"))
        XCTAssertFalse(source.contains("distributionChannel.managementLabel"))
    }

    func testSetappBuildDisablesScreenCaptureKitDiagnostics() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(contentsOf: root.appendingPathComponent("SaneBarApp.swift"))
        let projectSource = try String(contentsOf: root.appendingPathComponent("project.yml"))

        XCTAssertTrue(appSource.contains("#if !SETAPP\n    @preconcurrency import ScreenCaptureKit\n#endif"))
        XCTAssertTrue(appSource.contains("#if SETAPP\n            _ = window\n            return nil\n        #else"))
        XCTAssertTrue(projectSource.contains("Delete :NSScreenCaptureUsageDescription"))
    }

    func testSetappBuildDeclaresUniversalMacArchitectures() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectSource = try String(contentsOf: root.appendingPathComponent("project.yml"))

        XCTAssertTrue(projectSource.contains("VALID_ARCHS: \"arm64 x86_64\""))
        XCTAssertTrue(projectSource.contains("Add :MPSupportedArchitectures:0 string arm64"))
        XCTAssertTrue(projectSource.contains("Add :MPSupportedArchitectures:1 string x86_64"))
    }
}
