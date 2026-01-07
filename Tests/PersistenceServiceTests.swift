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

    // MARK: - Hover Settings

    func testShowOnHoverDefaultsToFalse() throws {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: showOnHover is disabled by default
        XCTAssertFalse(settings.showOnHover)
    }

    func testHoverDelayDefaultsToPointThree() throws {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: hoverDelay defaults to 0.3 seconds
        XCTAssertEqual(settings.hoverDelay, 0.3, accuracy: 0.001)
    }

    func testShowOnHoverEncodesAndDecodes() throws {
        // Given: settings with hover enabled
        var settings = SaneBarSettings()
        settings.showOnHover = true
        settings.hoverDelay = 0.5

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: hover settings are preserved
        XCTAssertTrue(decoded.showOnHover)
        XCTAssertEqual(decoded.hoverDelay, 0.5, accuracy: 0.001)
    }

    func testShowOnHoverBackwardsCompatibility() throws {
        // Given: JSON without hover settings (old format)
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": [],
            "alwaysVisibleApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: hover settings default correctly
        XCTAssertFalse(settings.showOnHover)
        XCTAssertEqual(settings.hoverDelay, 0.3, accuracy: 0.001)
    }

    // MARK: - Menu Bar Appearance Settings

    func testMenuBarAppearanceDefaultsToDisabled() throws {
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
            "alwaysVisibleApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false,
            "showOnHover": false,
            "hoverDelay": 0.3
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: appearance defaults correctly
        XCTAssertFalse(settings.menuBarAppearance.isEnabled)
        XCTAssertEqual(settings.menuBarAppearance.tintColor, "#000000")
    }

    // MARK: - Network Trigger Settings

    func testShowOnNetworkChangeDefaultsToFalse() throws {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: network trigger is disabled by default
        XCTAssertFalse(settings.showOnNetworkChange)
    }

    func testTriggerNetworksDefaultsToEmptyArray() throws {
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
            "alwaysVisibleApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false,
            "showOnHover": false,
            "hoverDelay": 0.3
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: network trigger settings default correctly
        XCTAssertFalse(settings.showOnNetworkChange)
        XCTAssertEqual(settings.triggerNetworks, [])
    }

    // MARK: - Dock Icon Visibility Settings

    func testShowDockIconDefaultsToFalse() throws {
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
            "alwaysVisibleApps": [],
            "iconHotkeys": {},
            "showOnLowBattery": false,
            "showOnHover": false,
            "hoverDelay": 0.3,
            "showOnNetworkChange": false,
            "triggerNetworks": []
        }
        """

        // When: decode
        let decoder = JSONDecoder()
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: showDockIcon defaults to false (backward compatibility)
        XCTAssertFalse(settings.showDockIcon)
    }
}
