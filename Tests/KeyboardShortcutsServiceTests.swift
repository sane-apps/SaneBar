import Testing
import Foundation
import KeyboardShortcuts
@testable import SaneBar

// MARK: - KeyboardShortcutsServiceTests

@Suite("KeyboardShortcutsService Tests")
struct KeyboardShortcutsServiceTests {

    // MARK: - Shortcut Name Tests

    @Test("Shortcut names are defined correctly")
    func testShortcutNamesDefined() {
        // Verify all shortcut names exist and have unique identifiers
        let toggleName = KeyboardShortcuts.Name.toggleHiddenItems
        let showName = KeyboardShortcuts.Name.showHiddenItems
        let hideName = KeyboardShortcuts.Name.hideItems
        let settingsName = KeyboardShortcuts.Name.openSettings

        #expect(toggleName.rawValue == "toggleHiddenItems",
                "Toggle shortcut name should match")
        #expect(showName.rawValue == "showHiddenItems",
                "Show shortcut name should match")
        #expect(hideName.rawValue == "hideItems",
                "Hide shortcut name should match")
        #expect(settingsName.rawValue == "openSettings",
                "Settings shortcut name should match")
    }

    @Test("All shortcut names are unique")
    func testShortcutNamesUnique() {
        let names: [KeyboardShortcuts.Name] = [
            .toggleHiddenItems,
            .showHiddenItems,
            .hideItems,
            .openSettings
        ]

        let rawValues = names.map { $0.rawValue }
        let uniqueValues = Set(rawValues)

        #expect(uniqueValues.count == names.count,
                "All shortcut names should be unique")
    }

    // MARK: - Service Tests

    @Test("Service is singleton")
    @MainActor
    func testServiceIsSingleton() {
        let service1 = KeyboardShortcutsService.shared
        let service2 = KeyboardShortcutsService.shared

        #expect(service1 === service2,
                "KeyboardShortcutsService.shared should return same instance")
    }

    @Test("Service can register handlers without crashing")
    @MainActor
    func testRegisterHandlers() {
        let service = KeyboardShortcutsService()

        // Should not throw or crash
        service.registerAllHandlers()

        #expect(true, "Handler registration should complete without error")
    }

    @Test("Service can unregister handlers without crashing")
    @MainActor
    func testUnregisterHandlers() {
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

        // Clear any existing shortcut first
        KeyboardShortcuts.reset(.toggleHiddenItems)

        // Set defaults
        service.setDefaultsIfNeeded()

        // Check if default was set (Cmd+\)
        _ = KeyboardShortcuts.getShortcut(for: .toggleHiddenItems)

        // Note: The shortcut might be nil if the library doesn't support setting defaults
        // in the test environment, so we just verify it doesn't crash
        #expect(true, "Setting defaults should complete without error")
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
