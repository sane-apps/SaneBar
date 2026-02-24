@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardXCTests: XCTestCase {
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root
    }

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

    func testFrameInTargetZoneTreatsNearBoundaryVisibleAsVisible() {
        let frame = CGRect(x: 101, y: 0, width: 22, height: 22) // midX=112
        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: frame,
                separatorX: 100,
                toHidden: false
            )
        )
    }

    func testFrameInTargetZoneTreatsLeftSideAsHidden() {
        let frame = CGRect(x: 60, y: 0, width: 22, height: 22) // midX=71
        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: frame,
                separatorX: 100,
                toHidden: true
            )
        )
    }

    func testShouldSkipHideForExternalMonitorPolicy() {
        XCTAssertTrue(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: false, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: false))
    }

    func testManualHideRequestsAreNotSuppressedByExternalMonitorPolicy() {
        XCTAssertFalse(
            MenuBarManager.shouldIgnoreHideRequest(
                disableOnExternalMonitor: true,
                isOnExternalMonitor: true,
                origin: .manual
            )
        )
    }

    func testAutomaticHideRequestsAreSuppressedByExternalMonitorPolicy() {
        XCTAssertTrue(
            MenuBarManager.shouldIgnoreHideRequest(
                disableOnExternalMonitor: true,
                isOnExternalMonitor: true,
                origin: .automatic
            )
        )
    }

    func testStartupRecoveryTriggersWhenSeparatorIsRightOfMain() {
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 1200,
                mainX: 1100
            )
        )
    }

    func testStartupRecoveryDoesNotTriggerForHealthyOrdering() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100
            )
        )
    }

    func testStartupRecoveryTriggersWhenMainIconIsTooFarFromRightEdge() {
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 900,
                screenWidth: 1440
            )
        )
    }

    func testStartupRecoveryAllowsReasonableRightEdgeGap() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 300,
                screenWidth: 1440
            )
        )
    }

    func testStartupRecoveryDoesNotTriggerWithMissingCoordinates() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: nil,
                mainX: 1100
            )
        )
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: nil
            )
        )
    }

    func testSearchServiceRefreshesTargetAfterReveal() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("await waitForIconOnScreen(app: app)"),
            "SearchService.activate should wait for icon re-layout after reveal (#102)"
        )
        XCTAssertTrue(
            source.contains("resolveLatestClickTarget(for: app, forceRefresh: didReveal)"),
            "SearchService.activate should force-refresh click target identity after reveal (#102)"
        )
    }

    func testSearchServiceDebouncesBackToBackActivationRequests() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("activationDebounceInterval: TimeInterval = 0.45"),
            "SearchService.activate should debounce rapid duplicate requests to prevent panel lockups on double-click"
        )
        XCTAssertTrue(
            source.contains("beginActivationIfAllowed(for: app.uniqueId"),
            "SearchService.activate should pass through shared activation guard logic"
        )
    }

    func testSearchServiceSkipsActivationWhenAnotherActivationIsInFlight() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if let inFlight = activationInFlightAppID"),
            "SearchService.activate should reject overlapping activation workflows while one request is in progress"
        )
    }

    func testAccessibilityClickSkipsAXPressForOffscreenItems() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !isElementOnScreen(item)"),
            "clickMenuBarItem should gate AXPress behind on-screen checks (#102)"
        )
        XCTAssertTrue(
            source.contains("Target item off-screen; skipping AXPress, using hardware click"),
            "Off-screen targets should route to hardware fallback (#102)"
        )
    }

    func testSearchWindowForcesDarkColorSchemeAtSwiftUIBoundary() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(".preferredColorScheme(.dark)"),
            "Search windows should force dark color scheme so Icon Panel text stays readable in light mode (#85)"
        )
    }

    func testSearchWindowReappliesDarkAppearanceWhenShown() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("applyDarkAppearance(to: window)"),
            "Search window show() should reapply dark appearance before display to avoid washed-out panel state (#85)"
        )
        XCTAssertTrue(
            source.contains("window.contentView?.appearance = dark"),
            "Dark appearance must propagate to the hosted content view to keep SwiftUI/AppKit in sync (#85)"
        )
    }

    func testSearchWindowSuppressesResignAutoCloseAfterActivation() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func suppressAutoCloseForActivation"),
            "SearchWindowController should expose shared activation suppression to keep panels open on app click"
        )
        XCTAssertTrue(
            source.contains("if shouldSuppressResignAutoClose() { return }"),
            "windowDidResignKey should skip auto-close while activation suppression is active"
        )
    }

    func testMenuBarSearchActivationUsesSharedCloseSuppression() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView+Navigation.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("SearchWindowController.shared.suppressAutoCloseForActivation()"),
            "Both Icon Panel and Second Menu Bar activation should use unified close suppression backend"
        )
    }

    func testStartupExternalMonitorPolicyRunsBeforeAlwaysHiddenEnforcement() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        guard let skipIndex = source.range(of: "if self.shouldSkipHideForExternalMonitor"),
              let enforceIndex = source.range(of: "await self.enforceAlwaysHiddenPinnedItems(reason: \"startup\")")
        else {
            XCTFail("Startup external-monitor or always-hidden enforcement blocks not found")
            return
        }

        XCTAssertLessThan(
            skipIndex.lowerBound.utf16Offset(in: source),
            enforceIndex.lowerBound.utf16Offset(in: source),
            "Startup should skip under external-monitor policy before always-hidden automation runs"
        )
    }
}
