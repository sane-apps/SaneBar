import Testing
import Foundation
import AppKit
@testable import SaneBar

// MARK: - SearchWindowController Tests

@Suite("SearchWindowController Tests")
struct SearchWindowControllerTests {

    // MARK: - Singleton

    @Test("Shared instance is singleton")
    @MainActor
    func sharedIsSingleton() {
        let instance1 = SearchWindowController.shared
        let instance2 = SearchWindowController.shared
        #expect(instance1 === instance2)
    }

    // MARK: - Initial State

    @Test("Initially not visible")
    @MainActor
    func initiallyNotVisible() {
        let controller = SearchWindowController.shared
        // Reset state
        controller.hide()
        #expect(controller.isVisible == false)
    }

    // MARK: - Show/Hide

    @Test("Show sets isVisible to true")
    @MainActor
    func showSetsVisible() {
        let controller = SearchWindowController.shared
        controller.show()
        #expect(controller.isVisible == true)
        // Cleanup
        controller.hide()
    }

    @Test("Hide sets isVisible to false")
    @MainActor
    func hideSetsNotVisible() {
        let controller = SearchWindowController.shared
        controller.show()
        controller.hide()
        #expect(controller.isVisible == false)
    }

    @Test("Toggle from hidden shows window")
    @MainActor
    func toggleFromHiddenShows() {
        let controller = SearchWindowController.shared
        controller.hide()
        controller.toggle()
        #expect(controller.isVisible == true)
        // Cleanup
        controller.hide()
    }

    @Test("Toggle from visible hides window")
    @MainActor
    func toggleFromVisibleHides() {
        let controller = SearchWindowController.shared
        controller.show()
        controller.toggle()
        #expect(controller.isVisible == false)
    }

    @Test("Multiple show calls are idempotent")
    @MainActor
    func multipleShowsIdempotent() {
        let controller = SearchWindowController.shared
        controller.show()
        controller.show()
        controller.show()
        #expect(controller.isVisible == true)
        // Cleanup
        controller.hide()
    }

    @Test("Multiple hide calls are idempotent")
    @MainActor
    func multipleHidesIdempotent() {
        let controller = SearchWindowController.shared
        controller.hide()
        controller.hide()
        controller.hide()
        #expect(controller.isVisible == false)
    }
}

// MARK: - MenuBarSearchView Filter Tests

@Suite("MenuBarSearchView Filter Tests")
struct MenuBarSearchFilterTests {

    private func createTestItems() -> [StatusItemModel] {
        [
            StatusItemModel(
                bundleIdentifier: "com.dropbox.DropboxMacUpdate",
                title: "Dropbox",
                position: 0,
                section: .alwaysVisible
            ),
            StatusItemModel(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                title: "Slack",
                position: 1,
                section: .hidden
            ),
            StatusItemModel(
                bundleIdentifier: "com.apple.controlcenter",
                title: nil,
                position: 2,
                section: .alwaysVisible
            )
        ]
    }

    @Test("Filter by display name matches")
    func filterByDisplayName() {
        let items = createTestItems()
        let searchText = "Drop"

        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.count == 1)
        #expect(filtered.first?.displayName == "Dropbox")
    }

    @Test("Filter by bundle identifier matches")
    func filterByBundleId() {
        let items = createTestItems()
        let searchText = "tinyspeck"

        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.count == 1)
        #expect(filtered.first?.bundleIdentifier == "com.tinyspeck.slackmacgap")
    }

    @Test("Empty search returns all items")
    func emptySearchReturnsAll() {
        let items = createTestItems()
        let searchText = ""

        let filtered: [StatusItemModel]
        if searchText.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                item.displayName.localizedCaseInsensitiveContains(searchText) ||
                (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        #expect(filtered.count == 3)
    }

    @Test("Search is case-insensitive")
    func caseInsensitiveSearch() {
        let items = createTestItems()
        let searchText = "SLACK"

        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.count == 1)
        #expect(filtered.first?.displayName == "Slack")
    }

    @Test("No matches returns empty")
    func noMatchesReturnsEmpty() {
        let items = createTestItems()
        let searchText = "nonexistent"

        let filtered = items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        #expect(filtered.isEmpty)
    }

    @Test("Item with nil title uses fallback displayName")
    func nilTitleUsesFallback() {
        let items = createTestItems()
        let controlCenter = items.first { $0.bundleIdentifier == "com.apple.controlcenter" }

        #expect(controlCenter != nil)
        #expect(controlCenter?.title == nil)
        // displayName should return something, not empty
        #expect(!controlCenter!.displayName.isEmpty)
    }
}
