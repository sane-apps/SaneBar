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
        let data = oldJSON.data(using: .utf8)!
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
        let data = oldJSON.data(using: .utf8)!
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
        let data = oldJSON.data(using: .utf8)!
        let settings = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertFalse(settings.secondMenuBarShowAlwaysHidden)
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

        let profile = SaneBarProfile(
            name: "Test Profile",
            settings: settings,
            layoutSnapshot: SaneBarLayoutSnapshot(
                mainPosition: 420,
                separatorPosition: 390,
                alwaysHiddenSeparatorPosition: 10000,
                spacerPositions: [0: 360],
                calibratedScreenWidth: 1512,
                displayBackups: [
                    .init(widthBucket: 1512, mainPosition: 420, separatorPosition: 390)
                ]
            ),
            customIconSnapshot: SaneBarCustomIconSnapshot(pngData: Data([0x89, 0x50, 0x4E, 0x47]))
        )

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
        XCTAssertEqual(decoded.layoutSnapshot?.mainPosition, 420)
        XCTAssertEqual(decoded.layoutSnapshot?.spacerPositions[0], 360)
        XCTAssertEqual(decoded.customIconSnapshot?.pngData, Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testProfileGenerateNameAvoidsConflicts() throws {
        // Given: existing profile names
        let existing = ["Profile 1", "Profile 2", "Profile 3"]

        // When: generate a new name
        let newName = SaneBarProfile.generateName(basedOn: existing)

        // Then: name doesn't conflict
        XCTAssertEqual(newName, "Profile 4")
    }

    func testSettingsArchiveDecodesLegacyWrappedSettingsWithoutSnapshots() throws {
        let legacyJSON = """
        {
          "version": 1,
          "exportedAt": "2026-03-12T15:00:00Z",
          "settings": {
            "autoRehide": false,
            "spacerCount": 1
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(SaneBarSettingsArchive.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(archive.version, 1)
        XCTAssertFalse(archive.settings.autoRehide)
        XCTAssertEqual(archive.settings.spacerCount, 1)
        XCTAssertNil(archive.layoutSnapshot)
        XCTAssertNil(archive.customIconSnapshot)
        XCTAssertTrue(archive.savedProfiles.isEmpty)
    }

    func testSettingsArchiveV2RoundTripsSnapshotsAndProfiles() throws {
        var settings = SaneBarSettings()
        settings.autoRehide = false
        settings.spacerCount = 3
        settings.hideAllOtherMenuBarItems = true
        settings.hideAllOtherVisibleItemIds = ["com.apple.menuextra.wifi"]
        let profile = SaneBarProfile(
            name: "Portable",
            settings: settings,
            layoutSnapshot: SaneBarLayoutSnapshot(
                mainPosition: 440,
                separatorPosition: 390,
                alwaysHiddenSeparatorPosition: 10000,
                spacerPositions: [0: 330],
                calibratedScreenWidth: 1512,
                displayBackups: [
                    .init(widthBucket: 1512, mainPosition: 440, separatorPosition: 390),
                ]
            ),
            customIconSnapshot: SaneBarCustomIconSnapshot(pngData: Data([0x89, 0x50, 0x4E, 0x47, 0x02]))
        )
        let archive = SaneBarSettingsArchive(
            version: 2,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
            settings: settings,
            layoutSnapshot: profile.layoutSnapshot,
            customIconSnapshot: profile.customIconSnapshot,
            savedProfiles: [profile]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        let decoded = try decoder.decode(SaneBarSettingsArchive.self, from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertFalse(decoded.settings.autoRehide)
        XCTAssertTrue(decoded.settings.hideAllOtherMenuBarItems)
        XCTAssertEqual(decoded.settings.hideAllOtherVisibleItemIds, ["com.apple.menuextra.wifi"])
        XCTAssertEqual(decoded.layoutSnapshot?.displayBackups.first?.separatorPosition, 390)
        XCTAssertEqual(decoded.customIconSnapshot?.pngData, Data([0x89, 0x50, 0x4E, 0x47, 0x02]))
        XCTAssertEqual(decoded.savedProfiles.count, 1)
        XCTAssertEqual(decoded.savedProfiles.first?.layoutSnapshot?.spacerPositions[0], 330)
    }

    func testImportPayloadRejectsDamagedWrappedArchiveWithoutLegacyFallback() throws {
        let damagedArchiveJSON = """
        {
          "version": 2,
          "settings": {
            "autoRehide": "not a boolean"
          },
          "layoutSnapshot": {
            "mainPosition": 420
          }
        }
        """
        let decoder = JSONDecoder()

        XCTAssertThrowsError(
            try SaneBarSettingsArchive.decodeImportPayload(
                from: Data(damagedArchiveJSON.utf8),
                using: decoder
            )
        ) { error in
            guard case SaneBarSettingsImportError.invalidArchive = error else {
                XCTFail("Expected invalidArchive, got \(error)")
                return
            }
        }
    }

    func testImportPayloadStillAcceptsRawLegacySettings() throws {
        let rawSettingsJSON = """
        {
          "autoRehide": false,
          "spacerCount": 2
        }
        """
        let decoder = JSONDecoder()
        let payload = try SaneBarSettingsArchive.decodeImportPayload(
            from: Data(rawSettingsJSON.utf8),
            using: decoder
        )

        guard case let .legacySettings(settings) = payload else {
            XCTFail("Expected raw legacy settings payload")
            return
        }
        XCTAssertFalse(settings.autoRehide)
        XCTAssertEqual(settings.spacerCount, 2)
    }

    func testApplyCustomIconSnapshotWritesAndRemovesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        try persistence.applyCustomIconSnapshot(SaneBarCustomIconSnapshot(pngData: payload))
        XCTAssertEqual(persistence.loadCustomIconData(), payload)

        try persistence.applyCustomIconSnapshot(SaneBarCustomIconSnapshot(pngData: nil))
        XCTAssertNil(persistence.loadCustomIconData())
    }

    func testUpsertProfilesMergesImportedProfilesByIdentifier() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        let sharedID = UUID()
        let original = SaneBarProfile(id: sharedID, name: "Work", settings: SaneBarSettings())
        let untouched = SaneBarProfile(id: UUID(), name: "Home", settings: SaneBarSettings())
        try persistence.saveProfile(original)
        try persistence.saveProfile(untouched)

        var updatedSettings = SaneBarSettings()
        updatedSettings.autoRehide = false
        let imported = SaneBarProfile(id: sharedID, name: "Work Updated", settings: updatedSettings)

        try persistence.upsertProfiles([imported])

        let profiles = try persistence.listProfiles()
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.contains { $0.name == "Home" })
        XCTAssertTrue(profiles.contains { $0.id == sharedID && $0.name == "Work Updated" && $0.settings.autoRehide == false })
    }

    func testTriggerActionsAndLayoutModeDefaultsAreBackwardCompatible() throws {
        let oldJSON = """
        {
            "autoRehide": true,
            "rehideDelay": 3.0,
            "spacerCount": 0,
            "showOnAppLaunch": false,
            "triggerApps": []
        }
        """

        let decoder = JSONDecoder()
        let settings = try decoder.decode(SaneBarSettings.self, from: Data(oldJSON.utf8))

        XCTAssertEqual(settings.layoutMode, .stability)
        XCTAssertEqual(settings.appLaunchTriggerAction, .showIcons)
        XCTAssertNil(settings.appLaunchTriggerProfileId)
        XCTAssertEqual(settings.batteryTriggerAction, .showIcons)
        XCTAssertNil(settings.batteryTriggerProfileId)
        XCTAssertEqual(settings.networkTriggerAction, .showIcons)
        XCTAssertNil(settings.networkTriggerProfileId)
        XCTAssertEqual(settings.focusTriggerAction, .showIcons)
        XCTAssertNil(settings.focusTriggerProfileId)
        XCTAssertEqual(settings.scheduleTriggerAction, .showIcons)
        XCTAssertNil(settings.scheduleTriggerProfileId)
    }

    func testTriggerActionsAndLayoutModeRoundTrip() throws {
        let appLaunchProfileId = UUID()
        let batteryProfileId = UUID()
        let networkProfileId = UUID()
        let focusProfileId = UUID()
        let scheduleProfileId = UUID()
        var settings = SaneBarSettings()
        settings.layoutMode = .live
        settings.appLaunchTriggerAction = .applyProfile
        settings.appLaunchTriggerProfileId = appLaunchProfileId
        settings.batteryTriggerAction = .applyProfile
        settings.batteryTriggerProfileId = batteryProfileId
        settings.networkTriggerAction = .applyProfile
        settings.networkTriggerProfileId = networkProfileId
        settings.focusTriggerAction = .applyProfile
        settings.focusTriggerProfileId = focusProfileId
        settings.scheduleTriggerAction = .applyProfile
        settings.scheduleTriggerProfileId = scheduleProfileId

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        XCTAssertEqual(decoded.layoutMode, .live)
        XCTAssertEqual(decoded.appLaunchTriggerAction, .applyProfile)
        XCTAssertEqual(decoded.appLaunchTriggerProfileId, appLaunchProfileId)
        XCTAssertEqual(decoded.batteryTriggerAction, .applyProfile)
        XCTAssertEqual(decoded.batteryTriggerProfileId, batteryProfileId)
        XCTAssertEqual(decoded.networkTriggerAction, .applyProfile)
        XCTAssertEqual(decoded.networkTriggerProfileId, networkProfileId)
        XCTAssertEqual(decoded.focusTriggerAction, .applyProfile)
        XCTAssertEqual(decoded.focusTriggerProfileId, focusProfileId)
        XCTAssertEqual(decoded.scheduleTriggerAction, .applyProfile)
        XCTAssertEqual(decoded.scheduleTriggerProfileId, scheduleProfileId)
    }

    func testMenuBarIconStylesExposeAccurateSymbolOptions() throws {
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.filter.sfSymbolName, "line.3.horizontal.decrease")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.sliders.sfSymbolName, "slider.horizontal.3")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.dots.sfSymbolName, "ellipsis")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.lines.sfSymbolName, "line.3.horizontal")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.chevron.sfSymbolName, "chevron.up.chevron.down")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.coin.sfSymbolName, "circle.circle")
        XCTAssertNil(SaneBarSettings.MenuBarIconStyle.custom.sfSymbolName)
    }

    func testProfileTriggerApplicationPreservesAutomationSettings() throws {
        let appLaunchProfileId = UUID()
        let batteryProfileId = UUID()
        let networkProfileId = UUID()
        let focusProfileId = UUID()
        let scheduleProfileId = UUID()

        var current = SaneBarSettings()
        current.showOnAppLaunch = true
        current.triggerApps = ["com.apple.Safari"]
        current.appLaunchTriggerAction = .applyProfile
        current.appLaunchTriggerProfileId = appLaunchProfileId
        current.showOnLowBattery = true
        current.batteryThreshold = 35
        current.batteryTriggerAction = .applyProfile
        current.batteryTriggerProfileId = batteryProfileId
        current.showOnNetworkChange = true
        current.triggerNetworks = ["Office"]
        current.networkTriggerAction = .applyProfile
        current.networkTriggerProfileId = networkProfileId
        current.showOnFocusModeChange = true
        current.triggerFocusModes = ["Work", "(Focus Off)"]
        current.focusTriggerAction = .applyProfile
        current.focusTriggerProfileId = focusProfileId
        current.showOnSchedule = true
        current.scheduleWeekdays = [2, 3, 4]
        current.scheduleStartHour = 8
        current.scheduleStartMinute = 30
        current.scheduleEndHour = 18
        current.scheduleEndMinute = 15
        current.scheduleTriggerAction = .applyProfile
        current.scheduleTriggerProfileId = scheduleProfileId
        current.scriptTriggerEnabled = true
        current.scriptTriggerPath = "/tmp/sanebar-trigger.sh"
        current.scriptTriggerInterval = 7

        var profileSettings = SaneBarSettings()
        profileSettings.autoRehide = false
        profileSettings.spacerCount = 4
        profileSettings.layoutMode = .live
        profileSettings.showOnAppLaunch = false
        profileSettings.triggerApps = []
        profileSettings.batteryThreshold = 10
        profileSettings.triggerNetworks = []
        profileSettings.triggerFocusModes = []
        profileSettings.showOnSchedule = false
        profileSettings.scriptTriggerEnabled = false

        let applied = profileSettings.preservingAutomation(from: current)

        XCTAssertFalse(applied.autoRehide)
        XCTAssertEqual(applied.spacerCount, 4)
        XCTAssertEqual(applied.layoutMode, .live)
        XCTAssertTrue(applied.showOnAppLaunch)
        XCTAssertEqual(applied.triggerApps, ["com.apple.Safari"])
        XCTAssertEqual(applied.appLaunchTriggerAction, .applyProfile)
        XCTAssertEqual(applied.appLaunchTriggerProfileId, appLaunchProfileId)
        XCTAssertTrue(applied.showOnLowBattery)
        XCTAssertEqual(applied.batteryThreshold, 35)
        XCTAssertEqual(applied.batteryTriggerAction, .applyProfile)
        XCTAssertEqual(applied.batteryTriggerProfileId, batteryProfileId)
        XCTAssertTrue(applied.showOnNetworkChange)
        XCTAssertEqual(applied.triggerNetworks, ["Office"])
        XCTAssertEqual(applied.networkTriggerAction, .applyProfile)
        XCTAssertEqual(applied.networkTriggerProfileId, networkProfileId)
        XCTAssertTrue(applied.showOnFocusModeChange)
        XCTAssertEqual(applied.triggerFocusModes, ["Work", "(Focus Off)"])
        XCTAssertEqual(applied.focusTriggerAction, .applyProfile)
        XCTAssertEqual(applied.focusTriggerProfileId, focusProfileId)
        XCTAssertTrue(applied.showOnSchedule)
        XCTAssertEqual(applied.scheduleWeekdays, [2, 3, 4])
        XCTAssertEqual(applied.scheduleStartHour, 8)
        XCTAssertEqual(applied.scheduleStartMinute, 30)
        XCTAssertEqual(applied.scheduleEndHour, 18)
        XCTAssertEqual(applied.scheduleEndMinute, 15)
        XCTAssertEqual(applied.scheduleTriggerAction, .applyProfile)
        XCTAssertEqual(applied.scheduleTriggerProfileId, scheduleProfileId)
        XCTAssertTrue(applied.scriptTriggerEnabled)
        XCTAssertEqual(applied.scriptTriggerPath, "/tmp/sanebar-trigger.sh")
        XCTAssertEqual(applied.scriptTriggerInterval, 7)
    }

    func testProfileApplicationPreservesExistingTouchIDProtection() throws {
        var current = SaneBarSettings()
        current.requireAuthToShowHiddenIcons = true

        var profileSettings = SaneBarSettings()
        profileSettings.requireAuthToShowHiddenIcons = false

        let applied = profileSettings.preservingProtectedSettings(from: current)

        XCTAssertTrue(applied.requireAuthToShowHiddenIcons)
    }

    func testProfileApplicationCanEnableTouchIDProtection() throws {
        let current = SaneBarSettings()

        var profileSettings = SaneBarSettings()
        profileSettings.requireAuthToShowHiddenIcons = true

        let applied = profileSettings.preservingProtectedSettings(from: current)

        XCTAssertTrue(applied.requireAuthToShowHiddenIcons)
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
        let group = SaneBarSettings.IconGroup(name: "Mutable")
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

    func testHideApplicationMenusOnInlineRevealDefaultsToTrue() throws {
        let settings = SaneBarSettings()
        XCTAssertTrue(settings.hideApplicationMenusOnInlineReveal)
    }

    func testHideApplicationMenusOnInlineRevealPersistsInSettingsJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        var settings = SaneBarSettings()
        settings.hideApplicationMenusOnInlineReveal = false
        try persistence.saveSettings(settings)

        let savedData = try Data(contentsOf: tempDir.appendingPathComponent("settings.json"))
        let object = try JSONSerialization.jsonObject(with: savedData, options: [])
        let dict = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(dict["hideApplicationMenusOnInlineReveal"] as? Bool, false)

        let loaded = try persistence.loadSettings()
        XCTAssertFalse(loaded.hideApplicationMenusOnInlineReveal)
    }

    func testLegacySettingsWithoutOnboardingKeyMigrateToCompleted() throws {
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
          "rehideDelay": 5
        }
        """
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try legacyJSON.data(using: .utf8)!.write(to: settingsURL, options: .atomic)

        let loaded = try persistence.loadSettings()
        XCTAssertTrue(loaded.hasCompletedOnboarding, "Legacy installs should be treated as completed onboarding")
        XCTAssertTrue(loaded.hasCompletedHealthWizard, "Legacy installs should not be forced through first-run health wizard")

        let rewrittenData = try Data(contentsOf: settingsURL)
        let rewrittenObject = try JSONSerialization.jsonObject(with: rewrittenData, options: [])
        let rewrittenDict = try XCTUnwrap(rewrittenObject as? [String: Any])
        XCTAssertEqual(rewrittenDict["hasCompletedOnboarding"] as? Bool, true)
        XCTAssertEqual(rewrittenDict["hasCompletedHealthWizard"] as? Bool, true)
    }

    func testExplicitOnboardingFalseIsPreservedForRealFirstRun() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        let firstRunJSON = """
        {
          "autoRehide": true,
          "hasCompletedOnboarding": false
        }
        """
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try firstRunJSON.data(using: .utf8)!.write(to: settingsURL, options: .atomic)

        let loaded = try persistence.loadSettings()
        XCTAssertFalse(loaded.hasCompletedOnboarding, "Explicit onboarding=false should not be overridden")
        XCTAssertFalse(loaded.hasCompletedHealthWizard, "Real first runs should still receive the health wizard")
    }

    func testCompletedOnboardingWithoutHealthWizardKeyMigratesToCompletedWizard() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        let upgradeJSON = """
        {
          "autoRehide": true,
          "hasCompletedOnboarding": true
        }
        """
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try upgradeJSON.data(using: .utf8)!.write(to: settingsURL, options: .atomic)

        let loaded = try persistence.loadSettings()
        XCTAssertTrue(loaded.hasCompletedOnboarding)
        XCTAssertTrue(loaded.hasCompletedHealthWizard, "Existing users should not be surprised by a first-run wizard after upgrade")
    }

    func testHealthWizardAndLayoutRescueRestorePointRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistence = PersistenceService(
            fileManager: FileManager.default,
            appSupportDirectoryOverride: tempDir
        )

        let createdAt = Date(timeIntervalSinceReferenceDate: 100)
        var settings = SaneBarSettings()
        settings.hasCompletedHealthWizard = true
        settings.layoutRescueRestorePointCreatedAt = createdAt
        settings.layoutRescueRestorePoint = SaneBarLayoutSnapshot(
            mainPosition: 420,
            separatorPosition: 520,
            alwaysHiddenSeparatorPosition: 300,
            spacerPositions: [0: 480],
            calibratedScreenWidth: 1512,
            displayBackups: [
                .init(widthBucket: 1512, mainPosition: 420, separatorPosition: 520)
            ]
        )

        try persistence.saveSettings(settings)
        let loaded = try persistence.loadSettings()

        XCTAssertTrue(loaded.hasCompletedHealthWizard)
        XCTAssertEqual(loaded.layoutRescueRestorePointCreatedAt, createdAt)
        XCTAssertEqual(loaded.layoutRescueRestorePoint?.mainPosition, 420)
        XCTAssertEqual(loaded.layoutRescueRestorePoint?.separatorPosition, 520)
        XCTAssertEqual(loaded.layoutRescueRestorePoint?.alwaysHiddenSeparatorPosition, 300)
        XCTAssertEqual(loaded.layoutRescueRestorePoint?.spacerPositions[0], 480)
        XCTAssertEqual(loaded.layoutRescueRestorePoint?.displayBackups.first?.widthBucket, 1512)
    }
}
