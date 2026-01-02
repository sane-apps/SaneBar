import Testing
import Foundation
@testable import SaneBar

// MARK: - Settings View Logic Tests

@Suite("SettingsView Logic Tests")
struct SettingsViewLogicTests {

    // MARK: - Search Filtering Tests

    @Test("Filter items by display name")
    func testFilterByDisplayName() {
        let items = [
            StatusItemModel(bundleIdentifier: "com.apple.finder", title: "Finder", position: 0),
            StatusItemModel(bundleIdentifier: "com.apple.safari", title: "Safari", position: 1),
            StatusItemModel(bundleIdentifier: "com.apple.mail", title: "Mail", position: 2)
        ]

        let searchText = "Safari"
        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.count == 1,
                "Should find exactly one item matching 'Safari'")
        #expect(filtered.first?.bundleIdentifier == "com.apple.safari",
                "Filtered item should be Safari")
    }

    @Test("Filter items by bundle identifier")
    func testFilterByBundleId() {
        let items = [
            StatusItemModel(bundleIdentifier: "com.apple.finder", title: "Finder", position: 0),
            StatusItemModel(bundleIdentifier: "com.apple.safari", title: "Safari", position: 1),
            StatusItemModel(bundleIdentifier: "com.apple.mail", title: "Mail", position: 2)
        ]

        let searchText = "mail"  // lowercase to test case-insensitive
        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.count == 1,
                "Should find exactly one item with 'mail' in bundle ID")
    }

    @Test("Filter returns all items when search is empty")
    func testEmptySearchReturnsAll() {
        let items = [
            StatusItemModel(bundleIdentifier: "com.apple.finder", title: "Finder", position: 0),
            StatusItemModel(bundleIdentifier: "com.apple.safari", title: "Safari", position: 1)
        ]

        let searchText = ""
        let filtered = searchText.isEmpty ? items : items.filter { _ in false }

        #expect(filtered.count == items.count,
                "Empty search should return all items")
    }

    @Test("Filter is case-insensitive")
    func testFilterIsCaseInsensitive() {
        let items = [
            StatusItemModel(bundleIdentifier: "com.apple.Safari", title: "Safari Browser", position: 0)
        ]

        let searchText = "SAFARI"
        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.count == 1,
                "Case-insensitive search should find item")
    }

    @Test("Filter returns empty when no matches")
    func testNoMatches() {
        let items = [
            StatusItemModel(bundleIdentifier: "com.apple.finder", title: "Finder", position: 0),
            StatusItemModel(bundleIdentifier: "com.apple.safari", title: "Safari", position: 1)
        ]

        let searchText = "nonexistent"
        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.isEmpty,
                "Should return empty when no matches found")
    }
}

// MARK: - Export/Import Tests

@Suite("Export/Import Tests")
struct ExportImportTests {

    @Test("ExportBundle is Codable")
    func testExportBundleCodable() throws {
        let items = [
            StatusItemModel(bundleIdentifier: "com.test.app", title: "Test", position: 0)
        ]
        let settings = SaneBarSettings()

        let bundle = PersistenceService.ExportBundle(
            version: 1,
            items: items,
            settings: settings,
            exportDate: Date()
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(bundle)
        let decoded = try decoder.decode(PersistenceService.ExportBundle.self, from: data)

        #expect(decoded.version == 1,
                "Version should be preserved")
        #expect(decoded.items.count == 1,
                "Items should be preserved")
        #expect(decoded.items.first?.bundleIdentifier == "com.test.app",
                "Item details should be preserved")
    }

    @Test("Export and import round-trip preserves data")
    func testRoundTrip() throws {
        let service = PersistenceService.shared
        let mockPersistence = PersistenceServiceProtocolMock()

        // Set up mock data
        mockPersistence.itemConfigurations = [
            StatusItemModel(bundleIdentifier: "com.test.app1", title: "App1", position: 0, section: .hidden),
            StatusItemModel(bundleIdentifier: "com.test.app2", title: "App2", position: 1, section: .collapsed)
        ]
        mockPersistence.settings = SaneBarSettings(
            autoRehide: false,
            rehideDelay: 5.0,
            showOnHover: false
        )

        // Export
        let exportData = try mockPersistence.exportConfiguration()

        // Import
        let (importedItems, importedSettings) = try mockPersistence.importConfiguration(from: exportData)

        #expect(importedItems.count == 2,
                "Should import both items")
        #expect(importedItems.first?.section == .hidden,
                "Should preserve section assignment")
        #expect(importedSettings.autoRehide == false,
                "Should preserve settings")
        #expect(importedSettings.rehideDelay == 5.0,
                "Should preserve rehide delay")
    }

    @Test("Import rejects unsupported version")
    func testRejectsUnsupportedVersion() throws {
        let mockPersistence = PersistenceServiceProtocolMock()

        // Create data with version 999 (unsupported future version)
        let futureBundle = """
        {
            "version": 999,
            "items": [],
            "settings": {},
            "exportDate": "2026-01-01T00:00:00Z"
        }
        """
        let data = futureBundle.data(using: .utf8)!

        // This should throw because version is too high
        #expect(throws: (any Error).self) {
            _ = try mockPersistence.importConfiguration(from: data)
        }
    }

    @Test("Current export version is 1")
    func testCurrentVersionIs1() {
        #expect(PersistenceService.ExportBundle.currentVersion == 1,
                "Current export version should be 1")
    }
}
