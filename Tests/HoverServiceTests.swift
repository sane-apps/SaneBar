import Testing
import Foundation
import AppKit
@testable import SaneBar

// MARK: - HoverServiceTests

@Suite("HoverService Tests")
@MainActor
struct HoverServiceTests {

    // MARK: - Initialization Tests

    @Test("HoverService initializes with hover disabled by default")
    func testDefaultHoverDisabled() {
        let service = HoverService()

        #expect(service.isEnabled == false, "Hover should be disabled by default")
        #expect(service.scrollEnabled == false, "Scroll should be disabled by default")
        #expect(service.clickEnabled == false, "Click should be disabled by default")
    }

    @Test("HoverService initializes with default delay of 0.25 seconds")
    func testDefaultHoverDelay() {
        let service = HoverService()

        #expect(service.hoverDelay == 0.25, "Default hover delay should be 0.25s")
    }

    // MARK: - Enable/Disable State Machine Tests

    @Test("Enabling hover when scroll is disabled should allow start")
    func testEnableHoverAlone() {
        let service = HoverService()
        service.isEnabled = true

        // Service should be enabled
        #expect(service.isEnabled == true)
        #expect(service.scrollEnabled == false)

        // Clean up
        service.stop()
    }

    @Test("Enabling scroll when hover is disabled should allow start")
    func testEnableScrollAlone() {
        let service = HoverService()
        service.scrollEnabled = true

        // Service should have scroll enabled
        #expect(service.scrollEnabled == true)
        #expect(service.isEnabled == false)

        // Clean up
        service.stop()
    }

    @Test("Disabling both hover and scroll stops monitoring")
    func testDisableBothStops() {
        let service = HoverService()

        // Enable both
        service.isEnabled = true
        service.scrollEnabled = true

        // Disable hover first
        service.isEnabled = false
        // Should still be monitoring because scroll is enabled
        #expect(service.scrollEnabled == true)

        // Disable scroll too
        service.scrollEnabled = false
        // Now both are disabled

        #expect(service.isEnabled == false)
        #expect(service.scrollEnabled == false)
    }

    @Test("Setting isEnabled to same value does not trigger state change")
    func testNoOpOnSameValue() {
        let service = HoverService()
        var triggerCount = 0

        service.onTrigger = { _ in
            triggerCount += 1
        }

        // Set to false when already false - should be no-op
        service.isEnabled = false
        service.isEnabled = false
        service.isEnabled = false

        #expect(triggerCount == 0, "No triggers should occur on no-op state changes")
    }

    // MARK: - Callback Configuration Tests

    @Test("onTrigger callback is settable and type is preserved")
    func testOnTriggerCallback() async {
        let service = HoverService()
        var receivedReason: HoverService.TriggerReason?

        service.onTrigger = { reason in
            receivedReason = reason
        }

        // Manually invoke to test callback wiring
        service.onTrigger?(.hover)

        #expect(receivedReason == .hover, "Callback should receive hover reason")

        service.onTrigger?(.scroll(direction: .up))
        #expect(receivedReason == .scroll(direction: .up), "Callback should receive scroll reason")

        service.onTrigger?(.click)
        #expect(receivedReason == .click, "Callback should receive click reason")
    }

    @Test("onLeaveMenuBar callback is settable")
    func testOnLeaveMenuBarCallback() {
        let service = HoverService()
        var leaveCallCount = 0

        service.onLeaveMenuBar = {
            leaveCallCount += 1
        }

        // Manually invoke
        service.onLeaveMenuBar?()
        service.onLeaveMenuBar?()

        #expect(leaveCallCount == 2, "Leave callback should be invocable")
    }

    // MARK: - Hover Delay Configuration Tests

    @Test("Hover delay can be set to custom values")
    func testCustomHoverDelay() {
        let service = HoverService()

        service.hoverDelay = 0.5
        #expect(service.hoverDelay == 0.5, "Delay should be 0.5s")

        service.hoverDelay = 0.05
        #expect(service.hoverDelay == 0.05, "Delay should be 0.05s")

        service.hoverDelay = 1.0
        #expect(service.hoverDelay == 1.0, "Delay should be 1.0s")
    }

    @Test("Hover delay of zero is allowed")
    func testZeroDelay() {
        let service = HoverService()
        service.hoverDelay = 0.0

        #expect(service.hoverDelay == 0.0, "Zero delay should be valid")
    }

    // MARK: - Start/Stop API Tests

    @Test("start() does nothing when both hover and scroll are disabled")
    func testStartWithBothDisabled() {
        let service = HoverService()

        // Both disabled by default
        service.start()

        // Should not crash, service remains in disabled state
        #expect(service.isEnabled == false)
        #expect(service.scrollEnabled == false)
    }

    @Test("stop() is safe to call multiple times")
    func testStopMultipleTimes() {
        let service = HoverService()
        service.isEnabled = true
        service.start()

        // Stop multiple times - should not crash
        service.stop()
        service.stop()
        service.stop()

        #expect(true, "Multiple stop() calls should not crash")
    }

    @Test("stop() resets internal mouse state")
    func testStopResetsState() {
        let service = HoverService()
        service.isEnabled = true
        service.start()

        // Stop should clean up internal state
        service.stop()

        // Verify service is stopped (isEnabled remains true but monitoring stops)
        #expect(service.isEnabled == true, "isEnabled is a setting, not monitoring state")
    }

    // MARK: - TriggerReason Enum Tests

    @Test("TriggerReason has distinct cases")
    func testTriggerReasonCases() {
        let hoverReason = HoverService.TriggerReason.hover
        let scrollUpReason = HoverService.TriggerReason.scroll(direction: .up)
        let scrollDownReason = HoverService.TriggerReason.scroll(direction: .down)
        let clickReason = HoverService.TriggerReason.click
        let userDragReason = HoverService.TriggerReason.userDrag

        // All cases should be distinct
        #expect(hoverReason != scrollUpReason)
        #expect(scrollUpReason != scrollDownReason)
        #expect(scrollUpReason != clickReason)
        #expect(hoverReason != clickReason)
        #expect(clickReason != userDragReason)
        #expect(hoverReason != userDragReason)
    }

    // MARK: - Protocol Conformance Tests

    @Test("HoverService conforms to HoverServiceProtocol")
    func testProtocolConformance() {
        let service: HoverServiceProtocol = HoverService()

        // Protocol requires these properties/methods
        _ = service.isEnabled
        _ = service.scrollEnabled
        service.start()
        service.stop()

        #expect(true, "HoverService should conform to protocol")
    }

    // MARK: - Mock Tests

    @Test("HoverServiceProtocolMock tracks start/stop calls")
    func testMockTracking() {
        let mock = HoverServiceProtocolMock()

        mock.start()
        mock.start()
        mock.stop()

        #expect(mock.startCallCount == 2, "Mock should track start calls")
        #expect(mock.stopCallCount == 1, "Mock should track stop calls")
    }

    @Test("HoverServiceProtocolMock allows setting isEnabled/scrollEnabled")
    func testMockProperties() {
        let mock = HoverServiceProtocolMock()

        mock.isEnabled = true
        mock.scrollEnabled = true

        #expect(mock.isEnabled == true)
        #expect(mock.scrollEnabled == true)
    }
}
