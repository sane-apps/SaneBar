import XCTest
@testable import SaneBar

@MainActor
final class RuntimeGuardXCTests: XCTestCase {
    func testNormalizedEventYKeepsAlreadyFlippedMenuBarY() {
        let y = AccessibilityService.normalizedEventY(rawY: 15, globalMaxY: 1440, anchorY: 15)
        XCTAssertEqual(y, 15, accuracy: 0.001)
    }

    func testNormalizedEventYFlipsUnflippedMenuBarY() {
        let y = AccessibilityService.normalizedEventY(rawY: 1425, globalMaxY: 1440, anchorY: 15)
        XCTAssertEqual(y, 15, accuracy: 0.001)
    }

    func testNormalizedEventYClampsOutOfRangeValues() {
        let y = AccessibilityService.normalizedEventY(rawY: 1451, globalMaxY: 1440, anchorY: 30)
        XCTAssertEqual(y, 1, accuracy: 0.001)
    }

    func testShouldSkipHideForExternalMonitorPolicy() {
        XCTAssertTrue(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: false, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: false))
    }
}
