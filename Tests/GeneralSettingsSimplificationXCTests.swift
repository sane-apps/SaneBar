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

    func testFreeSecondMenuBarForcesLeftClickToggleHidden() {
        let normalized = MenuBarManager.normalizedLeftClickOpensBrowseIcons(
            isPro: false,
            useSecondMenuBar: true,
            leftClickOpensBrowseIcons: true
        )
        XCTAssertFalse(normalized)
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

    func testFreeModeNormalizesSecondMenuBarRowsToMinimal() {
        let normalized = MenuBarManager.normalizedSecondMenuBarRows(
            isPro: false,
            showVisible: true,
            showAlwaysHidden: true
        )
        XCTAssertFalse(normalized.showVisible)
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
}
