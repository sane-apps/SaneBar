import Testing
import Foundation
import AppKit
@testable import SaneBar

// MARK: - HoverService Tests

@Suite("HoverService Tests")
struct HoverServiceTests {

    // MARK: - Initialization

    @Test("Service starts with isHovering false")
    @MainActor
    func initialStateNotHovering() {
        let service = HoverService()
        #expect(service.isHovering == false)
    }

    @Test("Service starts with isEnabled true")
    @MainActor
    func initialStateEnabled() {
        let service = HoverService()
        #expect(service.isEnabled == true)
    }

    @Test("Default hover delay is 0.3 seconds")
    @MainActor
    func defaultHoverDelay() {
        let service = HoverService()
        #expect(service.hoverDelay == 0.3)
    }

    @Test("Default hide delay is 0.5 seconds")
    @MainActor
    func defaultHideDelay() {
        let service = HoverService()
        #expect(service.hideDelay == 0.5)
    }

    // MARK: - Configuration

    @Test("Can configure hover delay")
    @MainActor
    func configureHoverDelay() {
        let service = HoverService()
        service.hoverDelay = 1.0
        #expect(service.hoverDelay == 1.0)
    }

    @Test("Can configure hide delay")
    @MainActor
    func configureHideDelay() {
        let service = HoverService()
        service.hideDelay = 2.0
        #expect(service.hideDelay == 2.0)
    }

    @Test("Can set hover region")
    @MainActor
    func setHoverRegion() {
        let service = HoverService()
        let region = NSRect(x: 100, y: 100, width: 200, height: 50)
        service.setHoverRegion(region)
        // Region is private, but setting it shouldn't crash
        #expect(true)
    }

    @Test("Can disable service")
    @MainActor
    func disableService() {
        let service = HoverService()
        service.isEnabled = false
        #expect(service.isEnabled == false)
    }

    // MARK: - Monitoring

    @Test("Start monitoring doesn't crash when enabled")
    @MainActor
    func startMonitoringWhenEnabled() {
        let service = HoverService()
        service.isEnabled = true
        service.startMonitoring()
        // Should not crash
        service.stopMonitoring()
        #expect(true)
    }

    @Test("Start monitoring is no-op when disabled")
    @MainActor
    func startMonitoringWhenDisabled() {
        let service = HoverService()
        service.isEnabled = false
        service.startMonitoring()
        // Should do nothing without crashing
        service.stopMonitoring()
        #expect(true)
    }

    @Test("Stop monitoring is idempotent")
    @MainActor
    func stopMonitoringIdempotent() {
        let service = HoverService()
        service.stopMonitoring()
        service.stopMonitoring()
        // Multiple stops should not crash
        #expect(true)
    }

    // MARK: - Protocol Conformance

    @Test("Conforms to HoverServiceProtocol")
    @MainActor
    func conformsToProtocol() {
        let service: HoverServiceProtocol = HoverService()
        #expect(service.isHovering == false)
        #expect(service.isEnabled == true)
    }
}

// MARK: - Menu Bar Region Helper Tests

@Suite("HoverService Region Helper Tests")
struct HoverServiceRegionHelperTests {

    @Test("Menu bar hover region has correct height")
    @MainActor
    func menuBarRegionHeight() {
        let region = HoverService.menuBarHoverRegion()
        #expect(region.height == 24) // Standard menu bar height
    }

    @Test("Menu bar hover region spans screen width")
    @MainActor
    func menuBarRegionWidth() {
        guard let screen = NSScreen.main else {
            Issue.record("No main screen available")
            return
        }
        let region = HoverService.menuBarHoverRegion(screen: screen)
        #expect(region.width == screen.frame.width)
    }

    @Test("Menu bar hover region is at top of screen")
    @MainActor
    func menuBarRegionPosition() {
        guard let screen = NSScreen.main else {
            Issue.record("No main screen available")
            return
        }
        let region = HoverService.menuBarHoverRegion(screen: screen)
        let expectedY = screen.frame.maxY - 24
        #expect(region.origin.y == expectedY)
    }

    @Test("Custom X range hover region works")
    @MainActor
    func customRangeRegion() {
        let region = HoverService.menuBarHoverRegion(fromX: 100, toX: 300)
        #expect(region.origin.x == 100)
        #expect(region.width == 200)
        #expect(region.height == 24)
    }

    @Test("Custom X range handles reversed values")
    @MainActor
    func reversedRangeRegion() {
        let region = HoverService.menuBarHoverRegion(fromX: 300, toX: 100)
        #expect(region.origin.x == 100)
        #expect(region.width == 200)
    }
}
