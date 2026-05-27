@testable import SaneBar
import XCTest

final class PersistenceTriggerSettingsTests: XCTestCase {
    func testMenuBarAppearanceDefaultsToDisabled() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: appearance is disabled by default
        XCTAssertFalse(settings.menuBarAppearance.isEnabled)
        XCTAssertEqual(settings.menuBarAppearance.tintOpacity, 0.15, accuracy: 0.001)
    }

    func testMenuBarAppearanceEncodesAndDecodes() throws {
        // Given: settings with appearance enabled
        var settings = SaneBarSettings()
        settings.menuBarAppearance.isEnabled = true
        settings.menuBarAppearance.tintColor = "#FF5500"
        settings.menuBarAppearance.tintOpacity = 0.25
        settings.menuBarAppearance.tintColorDark = "#224466"
        settings.menuBarAppearance.tintOpacityDark = 0.65
        settings.menuBarAppearance.hasShadow = true
        settings.menuBarAppearance.hasBorder = true
        settings.menuBarAppearance.hasRoundedCorners = true
        settings.menuBarAppearance.cornerRadius = 12.0

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: appearance settings are preserved
        XCTAssertTrue(decoded.menuBarAppearance.isEnabled)
        XCTAssertEqual(decoded.menuBarAppearance.tintColor, "#FF5500")
        XCTAssertEqual(decoded.menuBarAppearance.tintOpacity, 0.25, accuracy: 0.001)
        XCTAssertEqual(decoded.menuBarAppearance.tintColorDark, "#224466")
        XCTAssertEqual(decoded.menuBarAppearance.tintOpacityDark, 0.65, accuracy: 0.001)
        XCTAssertTrue(decoded.menuBarAppearance.hasShadow)
        XCTAssertTrue(decoded.menuBarAppearance.hasBorder)
        XCTAssertTrue(decoded.menuBarAppearance.hasRoundedCorners)
        XCTAssertEqual(decoded.menuBarAppearance.cornerRadius, 12.0, accuracy: 0.001)
    }

    func testMenuBarAppearanceBackwardsCompatibility() throws {
        // Given: JSON without appearance settings (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: appearance defaults correctly
        XCTAssertFalse(settings.menuBarAppearance.isEnabled)
        XCTAssertEqual(settings.menuBarAppearance.tintColor, "#000000")
        XCTAssertEqual(settings.menuBarAppearance.tintColorDark, "#FFFFFF")
    }

    // MARK: - Network Trigger Settings

    func testShowOnNetworkChangeDefaultsToFalse() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: network trigger is disabled by default
        XCTAssertFalse(settings.showOnNetworkChange)
    }

    func testTriggerNetworksDefaultsToEmptyArray() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: trigger networks is empty
        XCTAssertEqual(settings.triggerNetworks, [])
    }

    func testNetworkTriggerSettingsEncodeAndDecode() throws {
        // Given: settings with network trigger configured
        var settings = SaneBarSettings()
        settings.showOnNetworkChange = true
        settings.triggerNetworks = ["Home WiFi", "Work Network"]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: network trigger settings are preserved
        XCTAssertTrue(decoded.showOnNetworkChange)
        XCTAssertEqual(decoded.triggerNetworks, ["Home WiFi", "Work Network"])
    }

    func testNetworkTriggerBackwardsCompatibility() throws {
        // Given: JSON without network trigger settings (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: network trigger settings default correctly
        XCTAssertFalse(settings.showOnNetworkChange)
        XCTAssertEqual(settings.triggerNetworks, [])
    }

    // MARK: - Schedule Trigger Settings

    func testScheduleTriggerDefaults() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: schedule trigger defaults are sensible for weekday work hours
        XCTAssertFalse(settings.showOnSchedule)
        XCTAssertEqual(settings.scheduleWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(settings.scheduleStartHour, 9)
        XCTAssertEqual(settings.scheduleStartMinute, 0)
        XCTAssertEqual(settings.scheduleEndHour, 17)
        XCTAssertEqual(settings.scheduleEndMinute, 0)
    }

    func testScheduleTriggerEncodesAndDecodes() throws {
        // Given: custom schedule settings
        var settings = SaneBarSettings()
        settings.showOnSchedule = true
        settings.scheduleWeekdays = [1, 7]
        settings.scheduleStartHour = 22
        settings.scheduleStartMinute = 30
        settings.scheduleEndHour = 6
        settings.scheduleEndMinute = 15

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: schedule values are preserved
        XCTAssertTrue(decoded.showOnSchedule)
        XCTAssertEqual(decoded.scheduleWeekdays, [1, 7])
        XCTAssertEqual(decoded.scheduleStartHour, 22)
        XCTAssertEqual(decoded.scheduleStartMinute, 30)
        XCTAssertEqual(decoded.scheduleEndHour, 6)
        XCTAssertEqual(decoded.scheduleEndMinute, 15)
    }

    func testScheduleTriggerBackwardsCompatibility() throws {
        // Given: JSON without schedule keys (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: schedule defaults are applied
        XCTAssertFalse(settings.showOnSchedule)
        XCTAssertEqual(settings.scheduleWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(settings.scheduleStartHour, 9)
        XCTAssertEqual(settings.scheduleStartMinute, 0)
        XCTAssertEqual(settings.scheduleEndHour, 17)
        XCTAssertEqual(settings.scheduleEndMinute, 0)
    }

    // MARK: - Dock Icon Visibility Settings

    func testShowDockIconDefaultsToFalse() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: Dock icon is hidden by default (backward compatibility)
        XCTAssertFalse(settings.showDockIcon)
    }

    func testShowDockIconEncodesAndDecodes() throws {
        // Given: settings with Dock icon enabled
        var settings = SaneBarSettings()
        settings.showDockIcon = true

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: showDockIcon is preserved
        XCTAssertTrue(decoded.showDockIcon)
    }

    func testShowDockIconBackwardsCompatibility() throws {
        // Given: JSON without showDockIcon (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false,
            "showOnNetworkChange": false,
            "triggerNetworks": []
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: showDockIcon defaults to false (backward compatibility)
        XCTAssertFalse(settings.showDockIcon)
    }

    // MARK: - Menu Bar Spacing

    func testMenuBarSpacingDefaultsToNil() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: spacing values are nil (system default)
        XCTAssertNil(settings.menuBarSpacing)
        XCTAssertNil(settings.menuBarSelectionPadding)
    }

    func testMenuBarSpacingEncodesAndDecodes() throws {
        // Given: settings with spacing values
        var settings = SaneBarSettings()
        settings.menuBarSpacing = 6
        settings.menuBarSelectionPadding = 8

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: spacing values are preserved
        XCTAssertEqual(decoded.menuBarSpacing, 6)
        XCTAssertEqual(decoded.menuBarSelectionPadding, 8)
    }

    func testMenuBarSpacingBackwardsCompatibility() throws {
        // Given: JSON without spacing keys (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: spacing defaults to nil (backward compatibility)
        XCTAssertNil(settings.menuBarSpacing)
        XCTAssertNil(settings.menuBarSelectionPadding)
    }

    // MARK: - Icon Groups
}
