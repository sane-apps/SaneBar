import Testing
import Foundation
@testable import SaneBar

// MARK: - PersistenceServiceTests

@Suite("PersistenceService Tests")
struct PersistenceServiceTests {

    // MARK: - Settings Tests

    @Test("Default settings have sensible values")
    func testDefaultSettings() {
        let settings = SaneBarSettings()

        #expect(settings.autoRehide == true,
                "Should default to auto-rehide enabled")
        #expect(settings.rehideDelay == 3.0,
                "Should default to 3 second rehide delay")
        #expect(settings.showOnHover == true,
                "Should default to show on hover")
        #expect(settings.hoverDelay == 0.3,
                "Should default to 0.3 second hover delay")
        #expect(settings.analyticsEnabled == true,
                "Should default to analytics enabled")
        #expect(settings.smartSuggestionsEnabled == true,
                "Should default to smart suggestions enabled")
    }

    @Test("Settings are Codable")
    func testSettingsCodable() throws {
        var settings = SaneBarSettings()
        settings.autoRehide = false
        settings.rehideDelay = 5.0
        settings.toggleShortcut = KeyboardShortcutData(keyCode: 11, modifiers: 256)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(settings)
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        #expect(decoded.autoRehide == false,
                "Should decode autoRehide")
        #expect(decoded.rehideDelay == 5.0,
                "Should decode rehideDelay")
        #expect(decoded.toggleShortcut?.keyCode == 11,
                "Should decode toggleShortcut keyCode")
    }

    // MARK: - Profile Tests

    @Test("Profile initializes with defaults")
    func testProfileDefaults() {
        let profile = Profile(name: "Test")

        #expect(profile.name == "Test",
                "Should have correct name")
        #expect(profile.itemSections.isEmpty,
                "Should start with empty item sections")
        #expect(profile.isTimeBasedProfile == false,
                "Should default to not time-based")
        #expect(profile.activeDays.isEmpty,
                "Should have no active days by default")
    }

    @Test("Profile is Codable")
    func testProfileCodable() throws {
        var profile = Profile(name: "Work")
        profile.itemSections["com.test.app-Test"] = .hidden
        profile.isTimeBasedProfile = true
        profile.activeDays = [1, 2, 3, 4, 5] // Mon-Fri

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(Profile.self, from: data)

        #expect(decoded.name == "Work",
                "Should decode name")
        #expect(decoded.itemSections["com.test.app-Test"] == .hidden,
                "Should decode item sections")
        #expect(decoded.isTimeBasedProfile == true,
                "Should decode time-based flag")
        #expect(decoded.activeDays == [1, 2, 3, 4, 5],
                "Should decode active days")
    }

    // MARK: - KeyboardShortcutData Tests

    @Test("KeyboardShortcutData is Hashable")
    func testKeyboardShortcutHashable() {
        let shortcut1 = KeyboardShortcutData(keyCode: 11, modifiers: 256)
        let shortcut2 = KeyboardShortcutData(keyCode: 11, modifiers: 256)
        let shortcut3 = KeyboardShortcutData(keyCode: 12, modifiers: 256)

        #expect(shortcut1 == shortcut2,
                "Equal shortcuts should be equal")
        #expect(shortcut1 != shortcut3,
                "Different shortcuts should not be equal")

        // Test hashability by using in Set
        let set: Set<KeyboardShortcutData> = [shortcut1, shortcut2, shortcut3]
        #expect(set.count == 2,
                "Set should deduplicate equal shortcuts")
    }

    // MARK: - Merge Tests

    @Test("Merge preserves user section assignments")
    func testMergePreservesUserAssignments() {
        let persistence = PersistenceService.shared

        // Saved items with user-configured sections
        let savedItems = [
            StatusItemModel(
                bundleIdentifier: "com.test.app1",
                title: "App1",
                position: 0,
                section: .hidden,  // User moved to hidden
                isVisible: false
            ),
            StatusItemModel(
                bundleIdentifier: "com.test.app2",
                title: "App2",
                position: 1,
                section: .collapsed,  // User moved to collapsed
                isVisible: false
            )
        ]

        // Freshly scanned items (all default to alwaysVisible)
        let scannedItems = [
            StatusItemModel(
                bundleIdentifier: "com.test.app1",
                title: "App1",
                position: 2,  // Position changed
                section: .alwaysVisible,
                isVisible: true
            ),
            StatusItemModel(
                bundleIdentifier: "com.test.app2",
                title: "App2",
                position: 3,
                section: .alwaysVisible,
                isVisible: true
            ),
            StatusItemModel(
                bundleIdentifier: "com.test.app3",
                title: "App3",  // New app
                position: 4,
                section: .alwaysVisible,
                isVisible: true
            )
        ]

        let merged = persistence.mergeWithSaved(scannedItems: scannedItems, savedItems: savedItems)

        // Find items by bundle ID
        let app1 = merged.first { $0.bundleIdentifier == "com.test.app1" }
        let app2 = merged.first { $0.bundleIdentifier == "com.test.app2" }
        let app3 = merged.first { $0.bundleIdentifier == "com.test.app3" }

        #expect(app1?.section == .hidden,
                "Should preserve user's hidden assignment")
        #expect(app2?.section == .collapsed,
                "Should preserve user's collapsed assignment")
        #expect(app3?.section == .alwaysVisible,
                "New items should use scanned section")
    }

    @Test("Merge preserves analytics data")
    func testMergePreservesAnalytics() {
        let persistence = PersistenceService.shared
        let testDate = Date()

        var savedItem = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "Test",
            position: 0,
            section: .alwaysVisible,
            isVisible: true
        )
        savedItem.clickCount = 42
        savedItem.lastClickDate = testDate

        let scannedItem = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "Test",
            position: 1,
            section: .alwaysVisible,
            isVisible: true
        )

        let merged = persistence.mergeWithSaved(
            scannedItems: [scannedItem],
            savedItems: [savedItem]
        )

        #expect(merged.first?.clickCount == 42,
                "Should preserve click count")
        #expect(merged.first?.lastClickDate == testDate,
                "Should preserve last click date")
    }

    // MARK: - Mock Tests

    @Test("Mock persistence saves and loads correctly")
    func testMockPersistence() throws {
        let mock = PersistenceServiceProtocolMock()

        // Save items
        let items = [
            StatusItemModel(bundleIdentifier: "com.test", title: "Test", position: 0, section: .hidden, isVisible: false)
        ]
        try mock.saveItemConfigurations(items)

        // Load and verify
        let loaded = try mock.loadItemConfigurations()
        #expect(loaded.count == 1,
                "Should load saved items")
        #expect(loaded.first?.section == .hidden,
                "Should preserve section")

        // Save settings
        var settings = SaneBarSettings()
        settings.autoRehide = false
        try mock.saveSettings(settings)

        // Load and verify
        let loadedSettings = try mock.loadSettings()
        #expect(loadedSettings.autoRehide == false,
                "Should load saved settings")

        // Clear all
        try mock.clearAll()
        let afterClear = try mock.loadItemConfigurations()
        #expect(afterClear.isEmpty,
                "Should be empty after clear")
    }
}
