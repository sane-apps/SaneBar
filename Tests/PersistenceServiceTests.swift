import XCTest
@testable import SaneBar

final class PersistenceServiceTests: XCTestCase {

    // MARK: - Always Visible Apps

    func testAlwaysVisibleAppsDefaultsToEmptyArray() throws {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: alwaysVisibleApps is empty
        XCTAssertEqual(settings.alwaysVisibleApps, [])
    }

    func testAlwaysVisibleAppsEncodesAndDecodes() throws {
        // Given: settings with always visible apps
        var settings = SaneBarSettings()
        settings.alwaysVisibleApps = ["com.1password.1password", "com.apple.controlcenter"]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: alwaysVisibleApps is preserved
        XCTAssertEqual(decoded.alwaysVisibleApps, ["com.1password.1password", "com.apple.controlcenter"])
    }

    func testAlwaysVisibleAppsBackwardsCompatibility() throws {
        // Given: JSON without alwaysVisibleApps (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 5.0,
            "spacerCount": 1,
            "showOnAppLaunch": false,
            "triggerApps": []
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: alwaysVisibleApps defaults to empty
        XCTAssertEqual(settings.alwaysVisibleApps, [])
        // And other settings are preserved
        XCTAssertEqual(settings.rehideDelay, 5.0)
        XCTAssertEqual(settings.spacerCount, 1)
    }

    // MARK: - Icon Hotkeys

    func testIconHotkeysDefaultsToEmptyDictionary() throws {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: iconHotkeys is empty
        XCTAssertTrue(settings.iconHotkeys.isEmpty)
    }

    func testIconHotkeysEncodesAndDecodes() throws {
        // Given: settings with icon hotkeys
        var settings = SaneBarSettings()
        settings.iconHotkeys = [
            "com.1password.1password": KeyboardShortcutData(keyCode: 18, modifiers: 1572864),
            "com.dropbox.client": KeyboardShortcutData(keyCode: 2, modifiers: 1572864)
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
            "alwaysVisibleApps": []
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: iconHotkeys defaults to empty
        XCTAssertTrue(settings.iconHotkeys.isEmpty)
    }

    // MARK: - Low Battery Trigger

    func testShowOnLowBatteryDefaultsToFalse() throws {
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
            "alwaysVisibleApps": [],
            "iconHotkeys": {}
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: showOnLowBattery defaults to false
        XCTAssertFalse(settings.showOnLowBattery)
    }

    // MARK: - Profiles

    func testProfileEncodesAndDecodes() throws {
        // Given: a profile with settings
        var settings = SaneBarSettings()
        settings.autoRehide = false
        settings.spacerCount = 2

        let profile = SaneBarProfile(name: "Test Profile", settings: settings)

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(SaneBarProfile.self, from: data)

        // Then: profile is preserved
        XCTAssertEqual(decoded.name, "Test Profile")
        XCTAssertEqual(decoded.settings.autoRehide, false)
        XCTAssertEqual(decoded.settings.spacerCount, 2)
        XCTAssertEqual(decoded.id, profile.id)
    }

    func testProfileGenerateNameAvoidsConflicts() throws {
        // Given: existing profile names
        let existing = ["Profile 1", "Profile 2", "Profile 3"]

        // When: generate a new name
        let newName = SaneBarProfile.generateName(basedOn: existing)

        // Then: name doesn't conflict
        XCTAssertEqual(newName, "Profile 4")
    }
}
