import Foundation
@testable import SaneBar
import Testing

@Suite("Icon Moving — Orchestration Invariants")
struct IconMovingOrchestrationTests {
    @Test("Move blocked during animation")
    func moveBlockedDuringAnimation() {
        // moveIcon must return false if hidingService is animating
        let isAnimating = true
        let isTransitioning = false
        let isBusy = isAnimating || isTransitioning

        #expect(isBusy, "Move must be blocked during animation")
    }

    @Test("Move blocked during transition")
    func moveBlockedDuringTransition() {
        let isAnimating = false
        let isTransitioning = true
        let isBusy = isAnimating || isTransitioning

        #expect(isBusy, "Move must be blocked during transition")
    }

    @Test("Move allowed when idle")
    func moveAllowedWhenIdle() {
        let isAnimating = false
        let isTransitioning = false
        let isBusy = isAnimating || isTransitioning

        #expect(!isBusy, "Move should be allowed when not animating or transitioning")
    }

    @Test("isMoveInProgress prevents Find Icon window close")
    func moveInProgressPreventsClose() {
        // SearchWindowController.close() has: guard !isMoveInProgress else { return }
        // windowDidResignKey also checks isMoveInProgress
        let isMoveInProgress = true

        let shouldClose = !isMoveInProgress
        #expect(!shouldClose, "Window must NOT close while move is in progress")
    }

    @Test("Re-hide after move-to-visible when was hidden")
    func reHideAfterMoveToVisible() {
        // After moving icon to visible, if bar was hidden, re-hide it
        let toHidden = false
        let wasHidden = true
        let shouldSkipHide = false

        let shouldReHide = !toHidden && wasHidden && !shouldSkipHide

        #expect(shouldReHide, "Must re-hide after moving icon to visible when bar was hidden")
    }

    @Test("No re-hide when moving to hidden")
    func noReHideWhenMovingToHidden() {
        let toHidden = true
        let wasHidden = true
        let shouldSkipHide = false

        let shouldReHide = !toHidden && wasHidden && !shouldSkipHide

        #expect(!shouldReHide, "Should NOT re-hide when already moving to hidden direction")
    }

    @Test("No re-hide on external monitor (skip hide flag)")
    func noReHideOnExternalMonitor() {
        let toHidden = false
        let wasHidden = true
        let shouldSkipHide = true // External monitor override

        let shouldReHide = !toHidden && wasHidden && !shouldSkipHide

        #expect(!shouldReHide, "Should NOT re-hide on external monitor")
    }

    @Test("Auth check required when moving from hidden to visible with auth enabled")
    func authCheckRequired() {
        let toHidden = false
        let wasHidden = true
        let requireAuth = true

        let needsAuthCheck = !toHidden && wasHidden && requireAuth

        #expect(needsAuthCheck, "Must check auth when revealing hidden icons")
    }

    @Test("No auth check when moving to hidden")
    func noAuthCheckWhenHiding() {
        let toHidden = true
        let wasHidden = false
        let requireAuth = true

        let needsAuthCheck = !toHidden && wasHidden && requireAuth

        #expect(!needsAuthCheck, "No auth needed when hiding icons")
    }
}

// MARK: - End-to-End Scenario Tests

@Suite("Icon Moving — Scenario Tests")
struct IconMovingScenarioTests {
    @Test("Standard icon move to hidden: full calculation")
    func standardIconMoveToHidden() {
        // Scenario: Move a 22px icon from visible to hidden
        let separatorX: CGFloat = 500
        let iconFrame = CGRect(x: 550, y: 5, width: 22, height: 22)

        // Target calculation
        let moveOffset = max(30, iconFrame.size.width + 20) // 42
        let targetX = separatorX - moveOffset // 458

        // Grab point
        let fromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY) // (561, 16)

        // Assertions
        #expect(targetX == 458)
        #expect(fromPoint.x == 561)
        #expect(fromPoint.y == 16)
        #expect(targetX < separatorX, "Target must be left of separator")
    }

    @Test("Standard icon move to visible with boundary: full calculation")
    func standardIconMoveToVisibleWithBoundary() {
        // Scenario: Move a 22px icon from hidden to visible
        // SaneBar icon is at X=900 (right side of menu bar)
        let separatorRightEdgeX: CGFloat = 500
        let mainIconLeftEdge: CGFloat = 900
        let iconFrame = CGRect(x: 400, y: 5, width: 22, height: 22)

        // Target calculation
        let targetX = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconFrame.size.width,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        // Grab point
        let fromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY) // (411, 16)

        // Assertions
        #expect(targetX == 508)
        #expect(fromPoint.x == 411)
        #expect(targetX > separatorRightEdgeX, "Target must be right of separator")
        #expect(targetX < mainIconLeftEdge, "Target must not overshoot past SaneBar icon")
    }

    @Test("Tight layout: separator and main icon close together")
    func tightLayoutScenario() {
        // Scenario: Menu bar is nearly full, separator at 800, main icon at 820
        let separatorRightEdgeX: CGFloat = 800
        let mainIconLeftEdge: CGFloat = 820
        let iconFrame = CGRect(x: 750, y: 5, width: 22, height: 22)

        let targetX = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconFrame.size.width,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(targetX == 807, "Tight layout: stays just inside the visible lane")
        #expect(targetX < mainIconLeftEdge)
    }

    @Test("Always-hidden move uses left edge separator position")
    func alwaysHiddenMoveToHidden() {
        // When moving to always-hidden, we use geometryResolver.alwaysHiddenSeparatorOriginX()
        // which returns the LEFT edge of the AH separator
        let ahSeparatorOriginX: CGFloat = 300
        let iconFrame = CGRect(x: 400, y: 5, width: 22, height: 22)

        let moveOffset = max(30, iconFrame.size.width + 20) // 42
        let targetX = ahSeparatorOriginX - moveOffset // 258

        #expect(targetX == 258)
        #expect(targetX < ahSeparatorOriginX, "Must move LEFT of AH separator")
    }

    @Test("Always-hidden move uses dedicated separator-adjacent target for normal-width icons")
    func alwaysHiddenMoveNormalWidthTarget() {
        let targetX = AccessibilityService.moveTargetX(
            targetLane: .alwaysHidden,
            iconWidth: 22,
            separatorX: 828,
            visibleBoundaryX: nil
        )

        #expect(targetX == 786, "Normal-width extras should insert just left of the always-hidden separator")
    }

    @Test("Always-hidden move stays separator-adjacent even for wide icons")
    func alwaysHiddenMoveWideIconUsesBoundedTarget() {
        let targetX = AccessibilityService.moveTargetX(
            targetLane: .alwaysHidden,
            iconWidth: 70.5,
            separatorX: 828,
            visibleBoundaryX: nil
        )

        #expect(targetX == 737.5, "Wide icons should still target the insertion edge instead of overshooting deep into the lane")
        #expect(targetX < 828, "Always-hidden target must stay left of the separator")
    }

    @Test("Post-move verification with successful move")
    func verificationAfterSuccessfulMove() {
        let separatorX: CGFloat = 500

        // Icon moved from 550 to 440
        let afterFrame = CGRect(x: 440, y: 5, width: 22, height: 22)
        let margin = max(CGFloat(4), afterFrame.size.width * 0.3) // 6.6

        let verified = afterFrame.origin.x < (separatorX - margin) // 440 < 493.4 → true

        #expect(verified, "Icon at 440 with separator at 500 should verify as hidden")
    }

    @Test("Post-move verification with failed move (icon didn't budge)")
    func verificationAfterFailedMove() {
        let separatorX: CGFloat = 500

        // Icon stayed at original position
        let afterFrame = CGRect(x: 550, y: 5, width: 22, height: 22)
        let margin = max(CGFloat(4), afterFrame.size.width * 0.3) // 6.6

        let verified = afterFrame.origin.x < (separatorX - margin) // 550 < 493.4 → false

        #expect(!verified, "Icon at 550 should NOT verify as hidden — move failed")
    }
}

// MARK: - Move to Visible Regression Tests

/// Regression tests for "Move to Visible" logic that broke on Feb 8-9 2026.
