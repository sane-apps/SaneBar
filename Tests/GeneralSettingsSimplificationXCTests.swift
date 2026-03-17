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
        let normalized = MenuBarManager.normalizedLeftClickOpensBrowseIcons(
            isPro: false,
            useSecondMenuBar: true,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertTrue(normalized)
    }

    func testProSecondMenuBarKeepsLeftClickOpenBrowse() {
        let normalized = MenuBarManager.normalizedLeftClickOpensBrowseIcons(
            isPro: true,
            useSecondMenuBar: true,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertTrue(normalized)
    }

    func testFreeIconPanelCanKeepLeftClickOpenBrowse() {
        let normalized = MenuBarManager.normalizedLeftClickOpensBrowseIcons(
            isPro: false,
            useSecondMenuBar: false,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertTrue(normalized)
    }

    func testFreeModeNormalizesSecondMenuBarRowsToVisibleAndHidden() {
        let normalized = MenuBarManager.normalizedSecondMenuBarRows(
            isPro: false,
            showVisible: false,
            showAlwaysHidden: true
        )
        XCTAssertTrue(normalized.showVisible)
        XCTAssertFalse(normalized.showAlwaysHidden)
    }

    func testProModeKeepsSecondMenuBarRows() {
        let normalized = MenuBarManager.normalizedSecondMenuBarRows(
            isPro: true,
            showVisible: true,
            showAlwaysHidden: false
        )
        XCTAssertTrue(normalized.showVisible)
        XCTAssertFalse(normalized.showAlwaysHidden)
    }

    func testFreeModeDisablesAlwaysHiddenSectionEffectively() {
        XCTAssertFalse(
            MenuBarManager.effectiveAlwaysHiddenSectionEnabled(
                isPro: false,
                alwaysHiddenSectionEnabled: true
            )
        )
    }

    func testProModeKeepsAlwaysHiddenSectionWhenEnabled() {
        XCTAssertTrue(
            MenuBarManager.effectiveAlwaysHiddenSectionEnabled(
                isPro: true,
                alwaysHiddenSectionEnabled: true
            )
        )
    }

    @MainActor
    func testLaunchTimeFreeModeNormalizationPersistsRowsBeforeObserversExist() {
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

        manager.normalizeLicenseDependentDefaults()

        XCTAssertTrue(manager.settings.secondMenuBarShowVisible)
        XCTAssertFalse(manager.settings.secondMenuBarShowAlwaysHidden)
        XCTAssertTrue(manager.settings.leftClickOpensBrowseIcons)
        XCTAssertEqual(persistence.saveSettingsCallCount, 1)
        XCTAssertTrue(persistence.saveSettingsArgValues.last?.secondMenuBarShowVisible ?? false)
        XCTAssertFalse(persistence.saveSettingsArgValues.last?.secondMenuBarShowAlwaysHidden ?? true)
        XCTAssertTrue(persistence.saveSettingsArgValues.last?.leftClickOpensBrowseIcons ?? false)
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
            MenuBarManager.updateUnavailableTooltip(for: .direct),
            "Updates are available from the installed /Applications/SaneBar.app build."
        )
        XCTAssertEqual(
            MenuBarManager.updateUnavailableTooltip(for: .appStore),
            "Updates are managed by the App Store."
        )
        XCTAssertEqual(
            MenuBarManager.updateUnavailableTooltip(for: .setapp),
            "Updates are managed by Setapp."
        )
    }
}
