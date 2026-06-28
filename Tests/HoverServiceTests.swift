import AppKit
import Foundation
@testable import SaneBar
import Testing

// MARK: - HoverServiceTests

@Suite("HoverService Tests")
@MainActor
struct HoverServiceTests {
    // MARK: - Initialization Tests

    @Test("HoverService initializes with hover disabled by default")
    func defaultHoverDisabled() {
        let service = HoverService()

        #expect(service.isEnabled == false, "Hover should be disabled by default")
        #expect(service.scrollEnabled == false, "Scroll should be disabled by default")
        #expect(service.clickEnabled == false, "Click should be disabled by default")
    }

    @Test("HoverService initializes with default reveal delay of 2.0 seconds")
    func defaultHoverDelay() {
        let service = HoverService()

        // Default reveal dwell was raised 0.25s → 2.0s so incidental hover/scroll
        // across the menu bar no longer pops hidden icons instantly (#165 cluster).
        #expect(service.hoverDelay == 2.0, "Default reveal delay should be 2.0s")
    }

    // MARK: - Enable/Disable State Machine Tests

    @Test("Enabling hover when scroll is disabled should allow start")
    func enableHoverAlone() {
        let service = HoverService()
        service.isEnabled = true

        // Service should be enabled
        #expect(service.isEnabled == true)
        #expect(service.scrollEnabled == false)

        // Clean up
        service.stop()
    }

    @Test("Enabling scroll when hover is disabled should allow start")
    func enableScrollAlone() {
        let service = HoverService()
        service.scrollEnabled = true

        // Service should have scroll enabled
        #expect(service.scrollEnabled == true)
        #expect(service.isEnabled == false)

        // Clean up
        service.stop()
    }

    @Test("Disabling both hover and scroll stops monitoring")
    func disableBothStops() {
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
    func noOpOnSameValue() {
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
    func onTriggerCallback() {
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
    func onLeaveMenuBarCallback() {
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
    func customHoverDelay() {
        let service = HoverService()

        service.hoverDelay = 0.5
        #expect(service.hoverDelay == 0.5, "Delay should be 0.5s")

        service.hoverDelay = 0.05
        #expect(service.hoverDelay == 0.05, "Delay should be 0.05s")

        service.hoverDelay = 1.0
        #expect(service.hoverDelay == 1.0, "Delay should be 1.0s")
    }

    @Test("Hover delay of zero is allowed")
    func zeroDelay() {
        let service = HoverService()
        service.hoverDelay = 0.0

        #expect(service.hoverDelay == 0.0, "Zero delay should be valid")
    }

    // MARK: - Start/Stop API Tests

    @Test("start() does nothing when both hover and scroll are disabled")
    func startWithBothDisabled() {
        let service = HoverService()

        // Both disabled by default
        service.start()

        // Should not crash, service remains in disabled state
        #expect(service.isEnabled == false)
        #expect(service.scrollEnabled == false)
    }

    @Test("stop() resets internal mouse state")
    func stopResetsState() {
        let service = HoverService()
        service.isEnabled = true
        service.start()

        // Stop should clean up internal state
        service.stop()

        // Verify service is stopped (isEnabled remains true but monitoring stops)
        #expect(service.isEnabled == true, "isEnabled is a setting, not monitoring state")
    }

    @Test("Explicit status-item interaction marks mouse as active in menu bar")
    func explicitStatusItemInteractionMarksMenuBarActive() {
        let service = HoverService()

        service.noteExplicitStatusItemInteraction()

        #expect(service.isMouseInMenuBar == true)
    }

    // MARK: - TriggerReason Enum Tests

    @Test("TriggerReason has distinct cases")
    func triggerReasonCases() {
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

    // MARK: - Mock Tests

    @Test("HoverServiceProtocolMock tracks start/stop calls")
    func mockTracking() {
        let mock = HoverServiceProtocolMock()

        mock.start()
        mock.start()
        mock.stop()

        #expect(mock.startCallCount == 2, "Mock should track start calls")
        #expect(mock.stopCallCount == 1, "Mock should track stop calls")
    }

    @Test("HoverServiceProtocolMock allows setting isEnabled/scrollEnabled")
    func mockProperties() {
        let mock = HoverServiceProtocolMock()

        mock.isEnabled = true
        mock.scrollEnabled = true

        #expect(mock.isEnabled == true)
        #expect(mock.scrollEnabled == true)
    }

    // MARK: - Menu Bar Interaction Region Tests

    @Test("Menu bar interaction region includes the top menu strip")
    func interactionRegionIncludesMenuStrip() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = NSPoint(x: 100, y: 890)

        let result = HoverService.isPointInMenuBarInteractionRegion(
            point,
            screenFrames: [screen],
            detectionZoneHeight: 24,
            leaveThreshold: 200
        )

        #expect(result == true)
    }

    @Test("Menu bar interaction region includes the dropdown zone below menu bar")
    func interactionRegionIncludesDropdownZone() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = NSPoint(x: 100, y: 760) // 140px below menu bar top

        let result = HoverService.isPointInMenuBarInteractionRegion(
            point,
            screenFrames: [screen],
            detectionZoneHeight: 24,
            leaveThreshold: 200
        )

        #expect(result == true)
    }

    @Test("Menu bar interaction region excludes points far below threshold")
    func interactionRegionExcludesFarBelowThreshold() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = NSPoint(x: 100, y: 640) // 260px below menu bar top

        let result = HoverService.isPointInMenuBarInteractionRegion(
            point,
            screenFrames: [screen],
            detectionZoneHeight: 24,
            leaveThreshold: 200
        )

        #expect(result == false)
    }

    @Test("Menu bar strip helper includes only top strip")
    func menuBarStripHelperIncludesTopStrip() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = NSPoint(x: 100, y: 890)

        let result = HoverService.isPointInMenuBarStrip(
            point,
            screenFrames: [screen],
            detectionZoneHeight: 24
        )

        #expect(result == true)
    }

    @Test("Menu bar strip helper excludes dropdown zone below strip")
    func menuBarStripHelperExcludesDropdownZone() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let point = NSPoint(x: 100, y: 760) // 140px below menu bar top

        let result = HoverService.isPointInMenuBarStrip(
            point,
            screenFrames: [screen],
            detectionZoneHeight: 24
        )

        #expect(result == false)
    }

    @Test("Menu bar interaction region uses the screen containing the pointer")
    func interactionRegionUsesContainingScreen() {
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let point = NSPoint(x: 1800, y: 1430)

        let result = HoverService.isPointInMenuBarInteractionRegion(
            point,
            screenFrames: [builtIn, external],
            detectionZoneHeight: 24,
            leaveThreshold: 200
        )

        #expect(result == true)
    }

    @Test("Menu bar distance uses the containing screen instead of NSScreen.main assumptions")
    func distanceFromMenuBarTopUsesContainingScreen() {
        let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let point = NSPoint(x: 2000, y: 1410)

        let distance = HoverService.distanceFromMenuBarTop(
            point,
            screenFrames: [builtIn, external]
        )

        #expect(distance == 30)
    }

    // MARK: - Main status-item hover dwell (#160/#161)

    /// The always-visible main icon installs its own NSTrackingArea because the global
    /// mouse monitor never sees the cursor over our own status-item button. That path
    /// must DWELL like the strip-hover path, not reveal instantly — otherwise a cursor
    /// brushing the SaneBar icon pops the hidden icons "every few minutes" (#160/#161).
    /// This fails on the pre-fix path, which called showHiddenItemsNow synchronously.
    @Test("Main status-item hover schedules a dwell instead of revealing instantly (#160/#161)")
    func mainStatusItemHoverDwellsInsteadOfRevealingInstantly() {
        let service = HoverService()
        service.isEnabled = true
        var fired = 0
        service.onTrigger = { _ in fired += 1 }

        service.beginMainStatusItemHoverDwell()

        #expect(
            fired == 0,
            "Icon hover must not reveal instantly; it must wait for the Reveal delay (#160/#161)"
        )

        // Leaving the icon before the dwell elapses cancels the pending reveal.
        service.cancelMainStatusItemHoverDwell()
        #expect(fired == 0)
    }

    /// While suspended (e.g. the Find Icon window is open) an icon hover must not even
    /// arm a reveal — the old immediate path ignored isSuspended entirely.
    @Test("Suspended hover service ignores main status-item hover")
    func suspendedIgnoresMainStatusItemHover() {
        let service = HoverService()
        service.isEnabled = true
        service.isSuspended = true
        var fired = 0
        service.onTrigger = { _ in fired += 1 }

        service.beginMainStatusItemHoverDwell()

        #expect(fired == 0, "A suspended hover service must not arm or fire an icon-hover reveal")
    }
}
