@testable import SaneBar
import XCTest

final class PersistenceServiceTests: XCTestCase {
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
        let data = oldJSON.data(using: .utf8)!
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
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertEqual(settings.alwaysHiddenPinnedItemIds, [])
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
            "iconHotkeys": {},
            "showOnLowBattery": false
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
            "iconHotkeys": {},
            "showOnLowBattery": false
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

    // MARK: - Schedule Trigger Settings

    func testScheduleTriggerDefaults() throws {
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
        let data = oldJSON.data(using: .utf8)!
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
            "iconHotkeys": {},
            "showOnLowBattery": false,
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

    // MARK: - Menu Bar Spacing

    func testMenuBarSpacingDefaultsToNil() throws {
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
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: spacing defaults to nil (backward compatibility)
        XCTAssertNil(settings.menuBarSpacing)
        XCTAssertNil(settings.menuBarSelectionPadding)
    }

    // MARK: - Icon Groups

    func testIconGroupsDefaultsToEmptyArray() throws {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: iconGroups is empty by default
        XCTAssertTrue(settings.iconGroups.isEmpty)
    }

    func testIconGroupStructHasRequiredProperties() throws {
        // Given: a new icon group
        let group = SaneBarSettings.IconGroup(name: "Work Apps")

        // Then: group has expected defaults
        XCTAssertFalse(group.id.uuidString.isEmpty)
        XCTAssertEqual(group.name, "Work Apps")
        XCTAssertTrue(group.appBundleIds.isEmpty)
    }

    func testIconGroupInitWithApps() throws {
        // Given: creating a group with apps
        let bundleIds = ["com.apple.Safari", "com.apple.Mail", "com.slack.Slack"]
        let group = SaneBarSettings.IconGroup(name: "Daily", appBundleIds: bundleIds)

        // Then: apps are stored correctly
        XCTAssertEqual(group.name, "Daily")
        XCTAssertEqual(group.appBundleIds.count, 3)
        XCTAssertTrue(group.appBundleIds.contains("com.apple.Safari"))
        XCTAssertTrue(group.appBundleIds.contains("com.slack.Slack"))
    }

    func testIconGroupsEncodesAndDecodes() throws {
        // Given: settings with icon groups
        var settings = SaneBarSettings()
        let group1 = SaneBarSettings.IconGroup(
            name: "Work",
            appBundleIds: ["com.1password.1password", "com.slack.Slack"]
        )
        let group2 = SaneBarSettings.IconGroup(
            name: "Personal",
            appBundleIds: ["com.spotify.client"]
        )
        settings.iconGroups = [group1, group2]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: icon groups are preserved
        XCTAssertEqual(decoded.iconGroups.count, 2)
        XCTAssertEqual(decoded.iconGroups[0].name, "Work")
        XCTAssertEqual(decoded.iconGroups[0].appBundleIds.count, 2)
        XCTAssertTrue(decoded.iconGroups[0].appBundleIds.contains("com.1password.1password"))
        XCTAssertEqual(decoded.iconGroups[1].name, "Personal")
        XCTAssertEqual(decoded.iconGroups[1].appBundleIds, ["com.spotify.client"])
    }

    func testIconGroupsBackwardsCompatibility() throws {
        // Given: JSON without iconGroups (old format)
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
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: iconGroups defaults to empty array
        XCTAssertTrue(settings.iconGroups.isEmpty)
    }

    func testIconGroupIdIsPreservedThroughEncodeDecode() throws {
        // Given: a group with a specific ID
        let group = SaneBarSettings.IconGroup(name: "Test")
        let originalId = group.id

        var settings = SaneBarSettings()
        settings.iconGroups = [group]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: ID is preserved (critical for UI selection state)
        XCTAssertEqual(decoded.iconGroups.first?.id, originalId)
    }

    func testIconGroupIsEquatable() throws {
        // Given: two groups with same content but different IDs
        let group1 = SaneBarSettings.IconGroup(name: "Test", appBundleIds: ["com.test.app"])
        let group2 = SaneBarSettings.IconGroup(name: "Test", appBundleIds: ["com.test.app"])

        // Then: they are NOT equal (different IDs)
        XCTAssertNotEqual(group1, group2)

        // And: same group equals itself
        XCTAssertEqual(group1, group1)
    }

    func testIconGroupIsIdentifiable() throws {
        // Given: a group
        let group = SaneBarSettings.IconGroup(name: "Test")

        // Then: it conforms to Identifiable (required for SwiftUI ForEach)
        let identifier: UUID = group.id
        XCTAssertFalse(identifier.uuidString.isEmpty)
    }

    func testIconGroupsCanBeMutated() throws {
        // Given: settings with a group
        var settings = SaneBarSettings()
        var group = SaneBarSettings.IconGroup(name: "Mutable")
        settings.iconGroups = [group]

        // When: add app to group
        settings.iconGroups[0].appBundleIds.append("com.new.app")

        // Then: mutation works
        XCTAssertEqual(settings.iconGroups[0].appBundleIds, ["com.new.app"])

        // When: remove app from group
        settings.iconGroups[0].appBundleIds.removeAll { $0 == "com.new.app" }

        // Then: removal works
        XCTAssertTrue(settings.iconGroups[0].appBundleIds.isEmpty)
    }

    func testIconGroupsHandleEmptyName() throws {
        // Given: a group with empty name (edge case)
        let group = SaneBarSettings.IconGroup(name: "")

        var settings = SaneBarSettings()
        settings.iconGroups = [group]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: empty name is preserved (UI should validate, not persistence)
        XCTAssertEqual(decoded.iconGroups.first?.name, "")
    }

    func testIconGroupsHandleDuplicateBundleIds() throws {
        // Given: a group with duplicate bundle IDs (edge case)
        let group = SaneBarSettings.IconGroup(
            name: "Dupes",
            appBundleIds: ["com.test.app", "com.test.app", "com.test.app"]
        )

        var settings = SaneBarSettings()
        settings.iconGroups = [group]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: duplicates are preserved (deduplication is UI responsibility)
        XCTAssertEqual(decoded.iconGroups.first?.appBundleIds.count, 3)
    }

    func testIconGroupsHandleManyGroups() throws {
        // Given: settings with many groups
        var settings = SaneBarSettings()
        for i in 1 ... 20 {
            let group = SaneBarSettings.IconGroup(
                name: "Group \(i)",
                appBundleIds: ["com.app\(i).test"]
            )
            settings.iconGroups.append(group)
        }

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: all groups are preserved
        XCTAssertEqual(decoded.iconGroups.count, 20)
        XCTAssertEqual(decoded.iconGroups[19].name, "Group 20")
    }

    func testIconGroupsHandleSpecialCharactersInName() throws {
        // Given: a group with special characters
        let group = SaneBarSettings.IconGroup(
            name: "🎨 Creative Apps & Tools (2024)",
            appBundleIds: ["com.adobe.Photoshop"]
        )

        var settings = SaneBarSettings()
        settings.iconGroups = [group]

        // When: encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        // Then: special characters are preserved
        XCTAssertEqual(decoded.iconGroups.first?.name, "🎨 Creative Apps & Tools (2024)")
    }

    // MARK: - Auth Setting Persistence

    private final class InMemoryKeychainService: KeychainServiceProtocol, @unchecked Sendable {
        private var boolStore: [String: Bool] = [:]
        private var stringStore: [String: String] = [:]

        func bool(forKey key: String) throws -> Bool? {
            boolStore[key]
        }

        func set(_ value: Bool, forKey key: String) throws {
            boolStore[key] = value
        }

        func string(forKey key: String) throws -> String? {
            stringStore[key]
        }

        func set(_ value: String, forKey key: String) throws {
            stringStore[key] = value
        }

        func delete(_ key: String) throws {
            boolStore.removeValue(forKey: key)
            stringStore.removeValue(forKey: key)
        }
    }

    func testRequireAuthToShowHiddenIconsIsStoredInSettingsJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        var settings = SaneBarSettings()
        settings.requireAuthToShowHiddenIcons = true
        try persistence.saveSettings(settings)

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let savedData = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: savedData, options: [])
        let dict = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dict["requireAuthToShowHiddenIcons"] as? Bool, true)

        let loaded = try persistence.loadSettings()
        XCTAssertTrue(loaded.requireAuthToShowHiddenIcons)
    }

    func testRequireAuthToShowHiddenIconsLoadsFromLegacySettingsJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        let legacyJSON = """
        {
          "autoRehide": true,
          "requireAuthToShowHiddenIcons": true
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("settings.json"), options: .atomic)

        let loaded = try persistence.loadSettings()
        XCTAssertTrue(loaded.requireAuthToShowHiddenIcons)
    }

    func testRequireAuthToShowHiddenIconsMigratesFromLegacyKeychainWhenMissingFromJSON() throws {
        let keychain = InMemoryKeychainService()
        try keychain.set(true, forKey: "settings.requireAuthToShowHiddenIcons")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            keychain: keychain,
            appSupportDirectoryOverride: tempDir
        )

        let jsonWithoutAuth = """
        {
          "autoRehide": true
        }
        """
        try jsonWithoutAuth.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("settings.json"), options: .atomic)

        let loaded = try persistence.loadSettings()
        XCTAssertTrue(loaded.requireAuthToShowHiddenIcons)

        let rewrittenData = try Data(contentsOf: tempDir.appendingPathComponent("settings.json"))
        let rewrittenObject = try JSONSerialization.jsonObject(with: rewrittenData, options: [])
        let rewrittenDict = try XCTUnwrap(rewrittenObject as? [String: Any])
        XCTAssertEqual(rewrittenDict["requireAuthToShowHiddenIcons"] as? Bool, true)
        XCTAssertNil(try keychain.bool(forKey: "settings.requireAuthToShowHiddenIcons"))
    }

    func testRequireAuthToShowHiddenIconsPrefersJSONValueOverLegacyKeychain() throws {
        let keychain = InMemoryKeychainService()
        try keychain.set(true, forKey: "settings.requireAuthToShowHiddenIcons")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            keychain: keychain,
            appSupportDirectoryOverride: tempDir
        )

        var settings = SaneBarSettings()
        settings.requireAuthToShowHiddenIcons = false
        try persistence.saveSettings(settings)

        let loaded = try persistence.loadSettings()
        XCTAssertFalse(loaded.requireAuthToShowHiddenIcons)
        XCTAssertEqual(try keychain.bool(forKey: "settings.requireAuthToShowHiddenIcons"), true)
    }

    func testDisablingRequireAuthPersistsFalseInSettingsJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        var settings = SaneBarSettings()
        settings.requireAuthToShowHiddenIcons = true
        try persistence.saveSettings(settings)

        settings.requireAuthToShowHiddenIcons = false
        try persistence.saveSettings(settings)

        let savedData = try Data(contentsOf: tempDir.appendingPathComponent("settings.json"))
        let object = try JSONSerialization.jsonObject(with: savedData, options: [])
        let dict = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dict["requireAuthToShowHiddenIcons"] as? Bool, false)
    }
}
