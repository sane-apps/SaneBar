@testable import SaneBar
import XCTest

final class PersistenceAuthMigrationTests: XCTestCase {
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
        try legacyJSON.data(using: .utf8)?.write(to: tempDir.appendingPathComponent("settings.json"), options: .atomic)

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
        try jsonWithoutAuth.data(using: .utf8)?.write(to: tempDir.appendingPathComponent("settings.json"), options: .atomic)

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

    func testHideApplicationMenusOnInlineRevealDefaultsToTrue() {
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
        try legacyJSON.data(using: .utf8)?.write(to: settingsURL, options: .atomic)

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
        try firstRunJSON.data(using: .utf8)?.write(to: settingsURL, options: .atomic)

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
        try upgradeJSON.data(using: .utf8)?.write(to: settingsURL, options: .atomic)

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
                .init(widthBucket: 1512, mainPosition: 420, separatorPosition: 520),
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
