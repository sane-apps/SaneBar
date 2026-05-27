@testable import SaneBar
import XCTest

final class PersistenceIconGroupTests: XCTestCase {
    func testIconGroupsDefaultsToEmptyArray() {
        // Given: default settings
        let settings = SaneBarSettings()

        // Then: iconGroups is empty by default
        XCTAssertTrue(settings.iconGroups.isEmpty)
    }

    func testIconGroupStructHasRequiredProperties() {
        // Given: a new icon group
        let group = SaneBarSettings.IconGroup(name: "Work Apps")

        // Then: group has expected defaults
        XCTAssertFalse(group.id.uuidString.isEmpty)
        XCTAssertEqual(group.name, "Work Apps")
        XCTAssertTrue(group.appBundleIds.isEmpty)
    }

    func testIconGroupInitWithApps() {
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
        let data = try XCTUnwrap(oldJSON.data(using: .utf8))
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

    func testIconGroupIsEquatable() {
        // Given: two groups with same content but different IDs
        let group1 = SaneBarSettings.IconGroup(name: "Test", appBundleIds: ["com.test.app"])
        let group2 = SaneBarSettings.IconGroup(name: "Test", appBundleIds: ["com.test.app"])

        // Then: they are NOT equal (different IDs)
        XCTAssertNotEqual(group1, group2)

        // And: same group equals itself
        XCTAssertEqual(group1, group1)
    }

    func testIconGroupIsIdentifiable() {
        // Given: a group
        let group = SaneBarSettings.IconGroup(name: "Test")

        // Then: it conforms to Identifiable (required for SwiftUI ForEach)
        let identifier: UUID = group.id
        XCTAssertFalse(identifier.uuidString.isEmpty)
    }

    func testIconGroupsCanBeMutated() {
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

}
