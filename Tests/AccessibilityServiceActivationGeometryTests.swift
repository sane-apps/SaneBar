import ApplicationServices
import Testing
import AppKit
@testable import SaneBar

@Suite("AccessibilityService — Activation Geometry")
struct AccessibilityServiceActivationGeometryTests {
    @Test("Fresh visible-geometry recheck accepts a materially left-shifted separator")
    func testVisibleMoveFreshGeometryAcceptance() {
        let accepted = AccessibilityService.shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
            staleSeparatorX: 2344,
            staleFrame: CGRect(x: 2090, y: 0, width: 276, height: 24),
            freshSeparatorX: 2070,
            freshVisibleBoundaryX: 2346,
            refreshedFrame: CGRect(x: 2090, y: 0, width: 276, height: 24)
        )

        #expect(accepted)
    }

    @Test("Fresh visible-geometry recheck rejects tiny separator drift")
    func testVisibleMoveFreshGeometryRejectsTinyShift() {
        let accepted = AccessibilityService.shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
            staleSeparatorX: 1700,
            staleFrame: CGRect(x: 1660, y: 0, width: 24, height: 24),
            freshSeparatorX: 1692,
            freshVisibleBoundaryX: 1725,
            refreshedFrame: CGRect(x: 1660, y: 0, width: 24, height: 24)
        )

        #expect(accepted == false)
    }

    @Test("Fresh visible-geometry recheck rejects large unresolved shortfalls")
    func testVisibleMoveFreshGeometryRejectsHugeShortfall() {
        let accepted = AccessibilityService.shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
            staleSeparatorX: 2100,
            staleFrame: CGRect(x: 1820, y: 0, width: 40, height: 24),
            freshSeparatorX: 1960,
            freshVisibleBoundaryX: 2200,
            refreshedFrame: CGRect(x: 1820, y: 0, width: 40, height: 24)
        )

        #expect(accepted == false)
    }

    @Test("Raw spatial fallback is disabled for browse or reveal flows after frame polling fails")
    func testShouldUseRawSpatialFallbackRejectsStaleBrowseCenter() {
        #expect(
            !SearchServiceSupport.shouldUseRawSpatialFallback(
                allowImmediateFallbackCenter: false,
                isPointOnScreen: true
            )
        )
    }

    @Test("Raw spatial fallback requires an on-screen point")
    func testShouldUseRawSpatialFallbackRejectsOffscreenPoint() {
        #expect(
            !SearchServiceSupport.shouldUseRawSpatialFallback(
                allowImmediateFallbackCenter: true,
                isPointOnScreen: false
            )
        )
        #expect(
            SearchServiceSupport.shouldUseRawSpatialFallback(
                allowImmediateFallbackCenter: true,
                isPointOnScreen: true
            )
        )
    }

    @Test("Hardware-first click falls back to AX when verification is unavailable on-screen")
    func testShouldFallbackToAXAfterHardwareAttemptForUnavailableOnScreenResult() {
        #expect(
            AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: true,
                verificationSummary: "unavailable (no comparable AX reaction signals)",
                isItemOnScreen: true,
                isRightClick: false
            )
        )
    }

    @Test("Hardware-first click keeps verified on-screen result without AX fallback")
    func testShouldFallbackToAXAfterHardwareAttemptSkipsVerifiedResult() {
        #expect(
            !AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: true,
                verificationSummary: "verified (shownMenu)",
                isItemOnScreen: true,
                isRightClick: false
            )
        )
    }

    @Test("Hardware-first click does not fall back to AX for off-screen targets")
    func testShouldFallbackToAXAfterHardwareAttemptSkipsOffscreenTargets() {
        #expect(
            !AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: false,
                verificationSummary: "failed (no observable menu/panel reaction)",
                isItemOnScreen: false,
                isRightClick: false
            )
        )
    }

    @Test("Cmd-drag screen guard accepts display-local menu bar points")
    func testCGEventPointScreenGuardAcceptsDisplayLocalMenuBarPoint() {
        let screenFrames = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 0, y: 1117, width: 1728, height: 1117),
        ]

        #expect(
            AccessibilityService.isCGEventPointOnAnyScreen(
                CGPoint(x: 1199, y: 16.5),
                screenFrames: screenFrames,
                globalMaxY: 2234
            ),
            "Hidden-to-visible drag should not abort a display-local menu bar point as off-screen"
        )
    }

    @Test("Accessibility frame screen guard accepts negative-origin displays")
    func testAccessibilityPointScreenGuardAcceptsNegativeOriginDisplay() {
        let screenFrames = [
            CGRect(x: -1728, y: 0, width: 1728, height: 1117),
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
        ]

        #expect(
            AccessibilityService.isAccessibilityPointOnAnyScreen(
                CGPoint(x: -529, y: 16.5),
                screenFrames: screenFrames
            ),
            "Valid menu bar items on a left-side display should not be rejected by x >= 0 sentinels"
        )
    }

    @Test("Display-local accessibility points are rebased to the owning screen")
    func testDisplayLocalAccessibilityPointRebasesToOwningScreen() {
        let screenFrames = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 1728, y: 0, width: 1728, height: 1117),
        ]
        let rightScreen = screenFrames[1]

        let resolved = AccessibilityService.resolvedGlobalAccessibilityPoint(
            CGPoint(x: 1199, y: 16.5),
            screenFrames: screenFrames,
            preferredScreenFrame: rightScreen
        )

        #expect(resolved.x == 2927)
        #expect(resolved.y == 16.5)
    }

    @Test("Ambiguous accessibility points stay global without a screen preference")
    func testAmbiguousAccessibilityPointStaysGlobalWithoutScreenPreference() {
        let screenFrames = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 1728, y: 0, width: 1728, height: 1117),
        ]

        let resolved = AccessibilityService.resolvedGlobalAccessibilityPoint(
            CGPoint(x: 1199, y: 16.5),
            screenFrames: screenFrames
        )

        #expect(resolved.x == 1199)
        #expect(resolved.y == 16.5)
    }

    @Test("Hardware-first right click does not fall back to AX after a dispatched on-screen click")
    func testShouldFallbackToAXAfterHardwareAttemptSkipsRightClickFallback() {
        #expect(
            !AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: true,
                verificationSummary: "failed (no observable menu/panel reaction)",
                isItemOnScreen: true,
                isRightClick: true
            )
        )
    }

    @Test("Hardware-first reveal waits for hidden items to come on-screen")
    func testShouldWaitForRevealSettleWhenHardwareFirstItemStartsHidden() {
        #expect(
            SearchServiceSupport.shouldWaitForRevealSettle(
                preferHardwareFirst: true,
                xPosition: -3470
            )
        )
    }

    @Test("Hardware-first reveal skips extra wait for already visible items")
    func testShouldWaitForRevealSettleSkipsVisibleHardwareFirstItem() {
        #expect(
            !SearchServiceSupport.shouldWaitForRevealSettle(
                preferHardwareFirst: true,
                xPosition: 1621
            )
        )
    }

    @Test("Non-hardware-first reveal always waits for settle")
    func testShouldWaitForRevealSettleWhenNotHardwareFirst() {
        #expect(
            SearchServiceSupport.shouldWaitForRevealSettle(
                preferHardwareFirst: false,
                xPosition: 1621
            )
        )
    }

    @Test("Browse-panel left click uses hardware-first for on-screen targets")
    func testShouldPreferHardwareFirstKeepsBrowsePanelOnScreenLeftClickHardwareFirst() {
        let app = RunningApp(
            id: "com.apple.Spotlight",
            name: "Spotlight",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.spotlight",
            xPosition: 1344,
            width: 32
        )

        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: app
            )
        )
    }

    @Test("Browse-panel left click uses hardware-first when cached X is missing")
    func testShouldPreferHardwareFirstKeepsBrowsePanelLeftClickHardwareFirstWithoutCachedX() {
        let app = RunningApp(
            id: "com.apple.Spotlight",
            name: "Spotlight",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.spotlight",
            xPosition: nil,
            width: 32
        )

        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: app
            )
        )
    }

    @Test("Direct Spotlight activation still prefers hardware first")
    func testShouldPreferHardwareFirstKeepsDirectAppleMenuExtraBias() {
        let app = RunningApp(
            id: "com.apple.Spotlight",
            name: "Spotlight",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.spotlight",
            xPosition: 1344,
            width: 32
        )

        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .direct,
                isRightClick: false,
                app: app
            )
        )
    }

    @Test("Right-click browse activation keeps hardware-first behavior")
    func testShouldPreferHardwareFirstKeepsRightClickHardwareBias() {
        let app = RunningApp(
            id: "com.apple.controlcenter",
            name: "Wi-Fi",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.wifi",
            xPosition: 1548,
            width: 22
        )

        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: true,
                app: app
            )
        )
    }
}
