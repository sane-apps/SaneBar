@testable import SaneBar
import XCTest

final class PersistenceSettingsCodableTests: XCTestCase {
    // MARK: - Icon Hotkeys

    func testIconHotkeysDefaultsToEmptyDictionary() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: iconHotkeys is empty
        XCTAssertTrue(settings.iconHotkeys.isEmpty)
    }

    func testIconHotkeysEncodesAndDecodes() throws {
        // Given: settings with icon hotkeys
        var settings = SaneBarSettings()
        settings.iconHotkeys = [
            "com.1password.1password": KeyboardShortcutData(keyCode: 18, modifiers: 1_572_864),
            "com.dropbox.client": KeyboardShortcutData(keyCode: 2, modifiers: 1_572_864),
        ]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: iconHotkeys is preserved
        XCTAssertEqual(decoded.iconHotkeys.count, 2)
        XCTAssertEqual(decoded.iconHotkeys["com.1password.1password"]?.keyCode, 18)
        XCTAssertEqual(decoded.iconHotkeys["com.dropbox.client"]?.keyCode, 2)
    }

    func testIconHotkeysBackwardsCompatibility() throws {
        // Given: JSON without iconHotkeys (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: iconHotkeys defaults to empty
        XCTAssertTrue(settings.iconHotkeys.isEmpty)
    }

    // MARK: - Always Hidden Pins (Experimental)

    func testAlwaysHiddenPinnedItemIdsDefaultsToEmptyArray() {
        let settings = SaneBarSettings()
        XCTAssertEqual(settings.alwaysHiddenPinnedItemIds, [])
    }

    func testAlwaysHiddenPinnedItemIdsEncodesAndDecodes() throws {
        var settings = SaneBarSettings()
        settings.alwaysHiddenPinnedItemIds = [
            "com.apple.menuextra.wifi",
            "com.dropbox.client",
            "com.foo.bar::axid:statusItem",
            "com.foo.bar::statusItem:1",
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertEqual(decoded.alwaysHiddenPinnedItemIds, settings.alwaysHiddenPinnedItemIds)
    }

    func testAlwaysHiddenPinnedItemIdsBackwardsCompatibility() throws {
        // Given: JSON without alwaysHiddenPinnedItemIds (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {}
        }
        """

        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertEqual(settings.alwaysHiddenPinnedItemIds, [])
    }

    func testHideAllOtherRuleDefaultsToDisabled() {
        let settings = SaneBarSettings()

        XCTAssertFalse(settings.hideAllOtherMenuBarItems)
        XCTAssertEqual(settings.hideAllOtherVisibleItemIds, [])
    }

    func testHideAllOtherRuleEncodesAndDecodes() throws {
        var settings = SaneBarSettings()
        settings.hideAllOtherMenuBarItems = true
        settings.hideAllOtherVisibleItemIds = [
            "com.apple.menuextra.wifi",
            "com.example.app::statusItem:0",
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertTrue(decoded.hideAllOtherMenuBarItems)
        XCTAssertEqual(decoded.hideAllOtherVisibleItemIds, settings.hideAllOtherVisibleItemIds)
    }

    func testHideAllOtherRuleBackwardsCompatibility() throws {
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {}
        }
        """

        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertFalse(settings.hideAllOtherMenuBarItems)
        XCTAssertEqual(settings.hideAllOtherVisibleItemIds, [])
    }

    func testSecondMenuBarShowVisibleDefaultsToTrue() {
        let settings = SaneBarSettings()
        XCTAssertTrue(settings.secondMenuBarShowVisible)
    }

    func testSecondMenuBarShowVisibleBackwardsCompatibility() throws {
        // Given: JSON without secondMenuBarShowVisible (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {}
        }
        """

        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertTrue(settings.secondMenuBarShowVisible)
    }

    func testSecondMenuBarShowAlwaysHiddenDefaultsToFalse() {
        let settings = SaneBarSettings()
        XCTAssertFalse(settings.secondMenuBarShowAlwaysHidden)
    }

    func testSecondMenuBarShowAlwaysHiddenEncodesAndDecodes() throws {
        var settings = SaneBarSettings()
        settings.secondMenuBarShowAlwaysHidden = false

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertFalse(decoded.secondMenuBarShowAlwaysHidden)
    }

    func testSecondMenuBarShowAlwaysHiddenBackwardsCompatibility() throws {
        // Given: JSON without secondMenuBarShowAlwaysHidden (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {}
        }
        """

        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertFalse(settings.secondMenuBarShowAlwaysHidden)
    }

    // MARK: - Low Battery Trigger

    func testShowOnLowBatteryDefaultsToFalse() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: showOnLowBattery is disabled by default
        XCTAssertFalse(settings.showOnLowBattery)
    }

    func testShowOnLowBatteryEncodesAndDecodes() throws {
        // Given: settings with battery trigger enabled
        var settings = SaneBarSettings()
        settings.showOnLowBattery = true

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: showOnLowBattery is preserved
        XCTAssertTrue(decoded.showOnLowBattery)
    }

    func testShowOnLowBatteryBackwardsCompatibility() throws {
        // Given: JSON without showOnLowBattery (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {}
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: showOnLowBattery defaults to false
        XCTAssertFalse(settings.showOnLowBattery)
    }

    // MARK: - Profiles
}
