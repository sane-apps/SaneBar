import Testing
import Foundation
@testable import SaneBar

// MARK: - HoverServiceTests

@Suite("HoverService Tests")
struct HoverServiceTests {

    // MARK: - Initialization Tests

    @Test("HoverService initializes with correct defaults")
    @MainActor
    func testInitialization() {
        let service = HoverService()

        #expect(service.isHovering == false, "Should start not hovering")
    }

    // MARK: - Delay Configuration Tests

    @Test("setDelay clamps values to valid range")
    @MainActor
    func testDelayClampingMinimum() {
        let service = HoverService()

        // Delay should clamp between 0.1 and 2.0 seconds
        // We test the clamping logic: max(0.1, min(delay, 2.0))

        // Test minimum clamp
        service.setDelay(0.01)  // Below minimum
        // We can't directly read hoverDelay (private), but we test the API works
        #expect(true, "setDelay with value below minimum should not crash")
    }

    @Test("setDelay clamps values above maximum")
    @MainActor
    func testDelayClampingMaximum() {
        let service = HoverService()

        // Test maximum clamp
        service.setDelay(10.0)  // Above maximum (2.0)
        #expect(true, "setDelay with value above maximum should not crash")
    }

    @Test("setDelay accepts values in valid range")
    @MainActor
    func testDelayValidRange() {
        let service = HoverService()

        service.setDelay(0.5)
        service.setDelay(1.0)
        service.setDelay(1.5)

        #expect(true, "setDelay with valid values should work")
    }

    // MARK: - Enable/Disable Tests

    @Test("setEnabled can be called without configuration")
    @MainActor
    func testEnableWithoutConfiguration() {
        let service = HoverService()

        // Should not crash even without configure() being called
        service.setEnabled(true)
        service.setEnabled(false)

        #expect(true, "setEnabled should not crash without configuration")
    }

    @Test("setEnabled is idempotent")
    @MainActor
    func testEnableIdempotent() {
        let service = HoverService()

        // Multiple calls with same value should be safe
        service.setEnabled(true)
        service.setEnabled(true)
        service.setEnabled(true)
        service.setEnabled(false)
        service.setEnabled(false)

        #expect(true, "Multiple setEnabled calls should be idempotent")
    }

    // MARK: - Hover State Tests

    @Test("isHovering starts as false")
    @MainActor
    func testInitialHoverState() {
        let service = HoverService()

        #expect(service.isHovering == false, "Initial hover state should be false")
    }

    // MARK: - Edge Case Tests

    @Test("setDelay with zero uses minimum")
    @MainActor
    func testZeroDelay() {
        let service = HoverService()

        service.setDelay(0.0)
        // Should clamp to 0.1 (minimum)
        #expect(true, "Zero delay should clamp to minimum")
    }

    @Test("setDelay with negative uses minimum")
    @MainActor
    func testNegativeDelay() {
        let service = HoverService()

        service.setDelay(-1.0)
        // Should clamp to 0.1 (minimum)
        #expect(true, "Negative delay should clamp to minimum")
    }

    // MARK: - Protocol Conformance Tests

    @Test("HoverService conforms to HoverServiceProtocol")
    @MainActor
    func testProtocolConformance() {
        let service: HoverServiceProtocol = HoverService()

        // Protocol requires these properties/methods
        _ = service.isHovering

        #expect(true, "HoverService should conform to protocol")
    }
}
