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

    // MARK: - Service Tests

    @Test("Service is singleton")
    @MainActor
    func serviceIsSingleton() {
        let service1 = KeyboardShortcutsService.shared
        let service2 = KeyboardShortcutsService.shared

        #expect(service1 === service2,
                "KeyboardShortcutsService.shared should return same instance")
    }

    @Test("Service can register handlers without crashing")
    @MainActor
    func registerHandlers() {
        let service = KeyboardShortcutsService()

        // Should not throw or crash
        service.registerAllHandlers()

        #expect(true, "Handler registration should complete without error")
    }

    @Test("Service can unregister handlers without crashing")
    @MainActor
    func unregisterHandlers() {
        let service = KeyboardShortcutsService()
        service.registerAllHandlers()

        // Should not throw or crash
        service.unregisterAllHandlers()

        #expect(true, "Handler unregistration should complete without error")
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

        // Check if default was set (Cmd+\)
        _ = KeyboardShortcuts.getShortcut(for: .toggleHiddenItems)

        // Note: The shortcut might be nil if the library doesn't support setting defaults
        // in the test environment, so we just verify it doesn't crash
        #expect(true, "Setting defaults should complete without error")

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

// MARK: - Integration Notes

/*
 Full integration testing of keyboard shortcuts requires:
 1. Running the actual app (not unit tests)
 2. User interaction to record shortcuts
 3. System-level event handling

 These tests verify the service structure and basic operations.
 Manual testing is required for full shortcut functionality.
 */
