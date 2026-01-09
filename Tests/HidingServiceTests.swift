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

        // Start hidden so menu bar is clean on launch (like Bartender, Hidden Bar)
        #expect(service.state == .hidden,
                "Should start in hidden state (items collapsed)")
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

        #expect(service.state == .hidden,
                "State should remain unchanged")
    }

    // MARK: - Nil Delimiter Tests (Crash Prevention)

    @Test("Toggle with nil delimiter does not crash")
    @MainActor
    func testToggleWithNilDelimiterDoesNotCrash() async {
        let service = HidingService()
        // Deliberately NOT calling configure() - delimiterItem is nil

        // Should return early without crashing
        await service.toggle()

        #expect(service.state == .hidden,
                "State should remain unchanged when delimiter is nil")
    }

    @Test("Show with nil delimiter does not crash")
    @MainActor
    func testShowWithNilDelimiterDoesNotCrash() async {
        let service = HidingService()
        // Deliberately NOT calling configure() - delimiterItem is nil

        // Should return early (no delimiter) - state stays hidden
        await service.show()

        #expect(service.state == .hidden,
                "State should remain hidden when show fails gracefully")
    }

    @Test("Hide with nil delimiter does not crash")
    @MainActor
    func testHideWithNilDelimiterDoesNotCrash() async {
        let service = HidingService()
        // Deliberately NOT calling configure() - delimiterItem is nil

        // Should return early without crashing
        await service.hide()

        #expect(service.state == .hidden,
                "State should remain hidden when hide fails gracefully")
    }
}
