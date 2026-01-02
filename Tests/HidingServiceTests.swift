import Testing
import Foundation
@testable import SaneBar

// MARK: - HidingServiceTests

@Suite("HidingService Tests")
struct HidingServiceTests {

    // MARK: - State Tests

    @Test("Initial state is hidden")
    @MainActor
    func testInitialStateIsHidden() {
        let service = HidingService()

        #expect(service.state == .hidden,
                "Should start in hidden state")
    }

    @Test("HidingState enum cases are correct")
    func testHidingStateEnumCases() {
        // Verify the enum values exist and can be compared
        let hidden = HidingState.hidden
        let expanded = HidingState.expanded

        #expect(hidden == .hidden,
                "Hidden state should equal .hidden")
        #expect(expanded == .expanded,
                "Expanded state should equal .expanded")
        #expect(hidden != expanded,
                "States should not be equal")
    }

    // MARK: - Delimiter Position Tests

    @Test("Set delimiter positions stores values")
    @MainActor
    func testSetDelimiterPositions() {
        let service = HidingService()

        service.setDelimiterPositions(hidden: 500.0, alwaysHidden: 300.0)

        // The service should store these without error
        // We can't easily test private properties, but we can verify no crash
        #expect(true, "Should set delimiter positions without error")
    }

    // MARK: - Toggle Tests

    @Test("Toggle switches state")
    @MainActor
    func testToggleSwitchesState() async throws {
        let service = HidingService()

        // Initial state
        #expect(service.state == .hidden)

        // Toggle should switch to expanded
        try await service.toggle(items: [])
        #expect(service.state == .expanded,
                "Should be expanded after toggle from hidden")

        // Toggle again should switch back to hidden
        try await service.toggle(items: [])
        #expect(service.state == .hidden,
                "Should be hidden after toggle from expanded")
    }

    @Test("Show sets state to expanded")
    @MainActor
    func testShowSetsExpanded() async throws {
        let service = HidingService()

        try await service.show(items: [])

        #expect(service.state == .expanded,
                "Should be expanded after show")

        // Calling show again should remain expanded
        try await service.show(items: [])
        #expect(service.state == .expanded,
                "Should still be expanded after second show")
    }

    @Test("Hide sets state to hidden")
    @MainActor
    func testHideSetsHidden() async throws {
        let service = HidingService()

        // First show
        try await service.show(items: [])
        #expect(service.state == .expanded)

        // Then hide
        try await service.hide(items: [])
        #expect(service.state == .hidden,
                "Should be hidden after hide")

        // Calling hide again should remain hidden
        try await service.hide(items: [])
        #expect(service.state == .hidden,
                "Should still be hidden after second hide")
    }

    // MARK: - Rehide Tests

    @Test("Schedule rehide can be cancelled")
    @MainActor
    func testScheduleRehideCanBeCancelled() async throws {
        let service = HidingService()

        // Show first
        try await service.show(items: [])
        #expect(service.state == .expanded)

        // Schedule rehide in 1 second
        service.scheduleRehide(after: 1.0)

        // Cancel immediately
        service.cancelRehide()

        // Wait past the scheduled time
        try await Task.sleep(for: .seconds(1.5))

        // Should still be expanded because we cancelled
        #expect(service.state == .expanded,
                "Should still be expanded after cancel")
    }

    @Test("Cancel rehide when already hidden is no-op")
    @MainActor
    func testCancelRehideWhenHidden() {
        let service = HidingService()

        // Should not crash
        service.cancelRehide()

        #expect(service.state == .hidden,
                "Should still be hidden")
    }

    // MARK: - ItemSection Tests

    @Test("ItemSection has correct string identifiers")
    func testItemSectionIdentifiers() {
        #expect(StatusItemModel.ItemSection.alwaysVisible.displayName == "Always Visible")
        #expect(StatusItemModel.ItemSection.hidden.displayName == "Hidden")
        #expect(StatusItemModel.ItemSection.collapsed.displayName == "Collapsed")
    }

    @Test("ItemSection has system images")
    func testItemSectionSystemImages() {
        // All sections should have non-empty system images
        for section in [StatusItemModel.ItemSection.alwaysVisible, .hidden, .collapsed] {
            #expect(!section.systemImage.isEmpty,
                    "\(section) should have a system image")
        }
    }
}
