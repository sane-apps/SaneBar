import Foundation
import KeyboardShortcuts
@testable import SaneBar
import Testing

// MARK: - KeyboardShortcutsServiceTests

@Suite("KeyboardShortcutsService Tests")
struct KeyboardShortcutsServiceTests {
    // MARK: - Shortcut Name Tests

    @Test("Shortcut names are defined correctly")
    func shortcutNamesDefined() {
        // Verify all shortcut names exist and have unique identifiers
        let toggleName = KeyboardShortcuts.Name.toggleHiddenItems
        let showName = KeyboardShortcuts.Name.showHiddenItems
        let hideName = KeyboardShortcuts.Name.hideItems
        let settingsName = KeyboardShortcuts.Name.openSettings
        let searchName = KeyboardShortcuts.Name.searchMenuBar

        #expect(toggleName.rawValue == "toggleHiddenItems",
                "Toggle shortcut name should match")
        #expect(showName.rawValue == "showHiddenItems",
                "Show shortcut name should match")
        #expect(hideName.rawValue == "hideItems",
                "Hide shortcut name should match")
        #expect(settingsName.rawValue == "openSettings",
                "Settings shortcut name should match")
        #expect(searchName.rawValue == "searchMenuBar",
                "Search shortcut name should match")
    }

    @Test("All shortcut names are unique")
    func shortcutNamesUnique() {
        let names: [KeyboardShortcuts.Name] = [
            .toggleHiddenItems,
            .showHiddenItems,
            .hideItems,
            .openSettings,
            .searchMenuBar,
        ]

        let rawValues = names.map(\.rawValue)
        let uniqueValues = Set(rawValues)

        #expect(uniqueValues.count == names.count,
                "All shortcut names should be unique")
    }

    // MARK: - Default Shortcut Tests

    @Test("Default shortcuts can be set")
    @MainActor
    func testSetDefaultsIfNeeded() {
        let service = KeyboardShortcutsService()

        // Clear the initialization flag so defaults can be set
        UserDefaults.standard.removeObject(forKey: "KeyboardShortcutsDefaultsInitialized")
        defer { UserDefaults.standard.removeObject(forKey: "KeyboardShortcutsDefaultsInitialized") }

        // Clear any existing shortcut first
        KeyboardShortcuts.reset(.toggleHiddenItems)

        // Set defaults
        service.setDefaultsIfNeeded()

        // Verify the flag was set
        #expect(UserDefaults.standard.bool(forKey: "KeyboardShortcutsDefaultsInitialized"),
                "Initialization flag should be set after first run")
    }

    @Test("Defaults are not re-applied after user clears shortcuts")
    @MainActor
    func defaultsNotReappliedAfterClear() {
        let service = KeyboardShortcutsService()

        // Simulate first run
        UserDefaults.standard.removeObject(forKey: "KeyboardShortcutsDefaultsInitialized")
        defer { UserDefaults.standard.removeObject(forKey: "KeyboardShortcutsDefaultsInitialized") }
        service.setDefaultsIfNeeded()

        // User clears a shortcut
        KeyboardShortcuts.reset(.toggleHiddenItems)

        // Simulate app restart — setDefaultsIfNeeded called again
        service.setDefaultsIfNeeded()

        // Shortcut should still be nil (not re-applied)
        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleHiddenItems)
        #expect(shortcut == nil, "Cleared shortcut should not be re-applied on restart")
    }
}
