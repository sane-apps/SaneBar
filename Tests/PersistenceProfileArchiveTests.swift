@testable import SaneBar
import XCTest

final class PersistenceProfileArchiveTests: XCTestCase {
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
                    .init(widthBucket: 1512, mainPosition: 420, separatorPosition: 390),
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

    func testProfileGenerateNameAvoidsConflicts() {
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

    func testMenuBarIconStylesExposeAccurateSymbolOptions() {
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.filter.sfSymbolName, "line.3.horizontal.decrease")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.sliders.sfSymbolName, "slider.horizontal.3")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.dots.sfSymbolName, "ellipsis")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.lines.sfSymbolName, "line.3.horizontal")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.chevron.sfSymbolName, "chevron.up.chevron.down")
        XCTAssertEqual(SaneBarSettings.MenuBarIconStyle.coin.sfSymbolName, "circle.circle")
        XCTAssertNil(SaneBarSettings.MenuBarIconStyle.custom.sfSymbolName)
    }

    func testProfileTriggerApplicationPreservesAutomationSettings() {
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

    func testSaneBarImportPreviewSurfacesScriptTrigger() {
        var settings = SaneBarSettings()
        settings.scriptTriggerEnabled = true
        settings.scriptTriggerPath = "/tmp/sanebar-trigger.sh"

        let legacyPlan = SaneBarSettingsImportPayload.legacySettings(settings)
            .previewPlan(fileName: "settings.json")

        XCTAssertTrue(
            legacyPlan.behavioralSettings.contains("Script trigger: /tmp/sanebar-trigger.sh")
        )

        let archive = SaneBarSettingsArchive(
            version: 2,
            exportedAt: Date(),
            settings: settings,
            layoutSnapshot: nil,
            customIconSnapshot: nil,
            savedProfiles: []
        )
        let archivePlan = SaneBarSettingsImportPayload.archive(archive)
            .previewPlan(fileName: "archive.json")

        XCTAssertTrue(
            archivePlan.behavioralSettings.contains("Script trigger: /tmp/sanebar-trigger.sh")
        )
    }

    func testProfileApplicationPreservesExistingTouchIDProtection() {
        var current = SaneBarSettings()
        current.requireAuthToShowHiddenIcons = true

        var profileSettings = SaneBarSettings()
        profileSettings.requireAuthToShowHiddenIcons = false

        let applied = profileSettings.preservingProtectedSettings(from: current)

        XCTAssertTrue(applied.requireAuthToShowHiddenIcons)
    }

    func testProfileApplicationCanEnableTouchIDProtection() {
        let current = SaneBarSettings()

        var profileSettings = SaneBarSettings()
        profileSettings.requireAuthToShowHiddenIcons = true

        let applied = profileSettings.preservingProtectedSettings(from: current)

        XCTAssertTrue(applied.requireAuthToShowHiddenIcons)
    }

    // MARK: - Hover Settings

    // MARK: - Menu Bar Appearance Settings
}
