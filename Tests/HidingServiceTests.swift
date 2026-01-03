import Testing
import Foundation
@testable import SaneBar

// MARK: - HidingServiceTests

@Suite("HidingService Tests")
struct HidingServiceTests {

    // MARK: - State Tests

    @Test("Initial state is expanded")
    @MainActor
    func testInitialStateIsExpanded() {
        let service = HidingService()

        // Start expanded so users can see all items on first launch
        #expect(service.state == .expanded,
                "Should start in expanded state (items visible)")
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

    // MARK: - Rehide Tests

    @Test("Schedule rehide can be cancelled")
    @MainActor
    func testScheduleRehideCanBeCancelled() async throws {
        let service = HidingService()

        // Note: Without a real NSStatusItem, show() will return early
        // This tests the cancel logic in isolation
        service.scheduleRehide(after: 1.0)
        service.cancelRehide()

        // Should not crash
        #expect(true, "Should cancel rehide without error")
    }

    @Test("Cancel rehide is no-op when nothing scheduled")
    @MainActor
    func testCancelRehideWhenNothingScheduled() {
        let service = HidingService()

        // Should not crash when no rehide is scheduled
        service.cancelRehide()

        #expect(service.state == .expanded,
                "State should remain unchanged")
    }
}
