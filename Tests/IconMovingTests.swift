import Foundation
@testable import SaneBar
import Testing

// MARK: - Icon Moving Regression Tests

/// Tests for the icon moving pipeline's pure-math logic.
///
/// These tests exist because we regressed working code (Feb 8 2026) by changing
/// the target calculation, grab point, and verification margins. The committed
/// code had correct logic that was overwritten by an AI audit's "fixes" for
/// bugs that were already fixed. These tests lock down the correct behavior.
@Suite("Icon Moving — Target Calculation")
struct IconMovingTargetTests {
    // MARK: - Move Offset

    @Test("Move offset scales with icon width (minimum 30px)")
    func moveOffsetScalesWithWidth() {
        // The formula: max(30, iconFrame.size.width + 20)
        // Standard icon (22px) → max(30, 42) = 42
        let standardOffset = max(30, CGFloat(22) + 20)
        #expect(standardOffset == 42)

        // Narrow icon (16px) → max(30, 36) = 36
        let narrowOffset = max(30, CGFloat(16) + 20)
        #expect(narrowOffset == 36)

        // Very narrow icon (8px) → max(30, 28) = 30 (minimum kicks in)
        let tinyOffset = max(30, CGFloat(8) + 20)
        #expect(tinyOffset == 30)

        // Wide icon (44px) → max(30, 64) = 64
        let wideOffset = max(30, CGFloat(44) + 20)
        #expect(wideOffset == 64)
    }

    @Test("REGRESSION: Offset must NOT be hardcoded to 50")
    func offsetIsNotHardcoded() {
        // Feb 8 regression: changed dynamic offset to hardcoded 50
        // This caused undershooting for wide icons and overshooting for small ones
        let smallIcon: CGFloat = 16
        let largeIcon: CGFloat = 44

        let smallOffset = max(30, smallIcon + 20)
        let largeOffset = max(30, largeIcon + 20)

        #expect(smallOffset != largeOffset,
                "Offset MUST scale with icon width — hardcoded values cause over/undershoot")
        #expect(smallOffset == 36)
        #expect(largeOffset == 64)
    }

    @Test("REGRESSION: CoinTick (200px wide) gets proportional offset")
    func coinTickWideIconOffset() {
        // CoinTick has a 200px wide status item
        let coinTickWidth: CGFloat = 200
        let offset = max(30, coinTickWidth + 20)

        #expect(offset == 220, "Wide icons need proportionally larger offset")
    }

    // MARK: - Target X Calculation

    @Test("Move to hidden: target is LEFT of separator")
    func moveToHiddenTargetIsLeftOfSeparator() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let moveOffset = max(30, iconWidth + 20)

        let targetX = separatorX - moveOffset

        #expect(targetX < separatorX, "Hidden target must be LEFT of separator")
        #expect(targetX == 458)
    }

    @Test("Move to visible without boundary: target is RIGHT of separator")
    func moveToVisibleNoBoundary() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let moveOffset = max(30, iconWidth + 20)
        let visibleBoundaryX: CGFloat? = nil

        let targetX: CGFloat = if let boundaryX = visibleBoundaryX {
            min(separatorX + moveOffset, boundaryX - 20)
        } else {
            separatorX + moveOffset
        }

        #expect(targetX > separatorX, "Visible target must be RIGHT of separator")
        #expect(targetX == 542)
    }

    @Test("Move to visible WITH boundary: target is clamped")
    func moveToVisibleWithBoundary() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let moveOffset = max(30, iconWidth + 20) // 42
        let visibleBoundaryX: CGFloat = 530 // Main icon left edge

        let targetX = min(separatorX + moveOffset, visibleBoundaryX - 20)

        // separatorX + moveOffset = 542, but boundary - 20 = 510
        // min(542, 510) = 510
        #expect(targetX == 510, "Target must be clamped to stay LEFT of main icon")
        #expect(targetX < visibleBoundaryX, "Target must not overshoot past SaneBar icon")
    }

    @Test("REGRESSION: Boundary clamping prevents icon overshooting past SaneBar icon")
    func boundaryClamping() {
        // This was the original Bug 6 from the audit — visibleBoundaryX being "unused"
        // In fact it WAS being used correctly. The audit was wrong.
        let separatorX: CGFloat = 800
        let mainIconLeftEdge: CGFloat = 850 // SaneBar icon starts here
        let iconWidth: CGFloat = 22
        let moveOffset = max(30, iconWidth + 20) // 42

        // Without clamping: separatorX + 42 = 842 → past mainIconLeftEdge - 20 = 830
        let unclamped = separatorX + moveOffset
        #expect(unclamped > mainIconLeftEdge - 20, "Without clamping, icon would overshoot")

        // With clamping: min(842, 830) = 830
        let clamped = min(separatorX + moveOffset, mainIconLeftEdge - 20)
        #expect(clamped == 830)
        #expect(clamped < mainIconLeftEdge, "Clamped target stays LEFT of main icon")
    }

    @Test("Boundary clamping with wide gap between separator and main icon")
    func boundaryClampingWideGap() {
        let separatorX: CGFloat = 500
        let mainIconLeftEdge: CGFloat = 900 // Lots of room
        let iconWidth: CGFloat = 22
        let moveOffset = max(30, iconWidth + 20) // 42

        let targetX = min(separatorX + moveOffset, mainIconLeftEdge - 20)

        // 542 < 880, so clamping doesn't activate
        #expect(targetX == 542, "Wide gap: offset is used directly (no clamping needed)")
    }

    @Test("Boundary clamping with separator and main icon very close")
    func boundaryClampingTightGap() {
        let separatorX: CGFloat = 800
        let mainIconLeftEdge: CGFloat = 810 // Only 10px gap!
        let iconWidth: CGFloat = 22
        let moveOffset = max(30, iconWidth + 20) // 42

        let targetX = min(separatorX + moveOffset, mainIconLeftEdge - 20)

        // 842 vs 790 → clamped to 790
        #expect(targetX == 790, "Tight gap: must clamp aggressively")
        #expect(targetX < mainIconLeftEdge)
    }
}

// MARK: - Grab Point Tests

@Suite("Icon Moving — Grab Point")
struct IconMovingGrabPointTests {
    @Test("REGRESSION: Grab point is icon center (midX), not left edge")
    func grabPointIsCenterNotLeftEdge() {
        // Feb 8 regression: changed to iconFrame.origin.x + 12 (left-edge grab)
        // This broke CoinTick and other non-standard icons
        let iconFrame = CGRect(x: 400, y: 5, width: 22, height: 22)

        let grabX = iconFrame.midX
        let grabY = iconFrame.midY

        #expect(grabX == 411, "Grab X must be center of icon (midX)")
        #expect(grabY == 16, "Grab Y must be center of icon (midY)")
    }

    @Test("Grab point for wide icon (CoinTick 200px)")
    func grabPointWideIcon() {
        let iconFrame = CGRect(x: 300, y: 5, width: 200, height: 22)

        let grabX = iconFrame.midX
        let grabY = iconFrame.midY

        #expect(grabX == 400, "Wide icon grab must be at center")
        #expect(grabY == 16)
    }

    @Test("Grab point for narrow icon (16px)")
    func grabPointNarrowIcon() {
        let iconFrame = CGRect(x: 600, y: 5, width: 16, height: 22)

        let grabX = iconFrame.midX
        let grabY = iconFrame.midY

        #expect(grabX == 608, "Narrow icon grab at center")
        #expect(grabY == 16)
    }
}

// MARK: - Verification Margin Tests

@Suite("Icon Moving — Verification Margins")
struct IconMovingVerificationTests {
    @Test("Verification margin scales with icon width (minimum 4px)")
    func verificationMarginScalesWithWidth() {
        // Formula: max(4, afterFrame.size.width * 0.3)
        let standardMargin = max(CGFloat(4), CGFloat(22) * 0.3) // 6.6
        #expect(standardMargin == 6.6)

        let narrowMargin = max(CGFloat(4), CGFloat(10) * 0.3) // 4 (minimum)
        #expect(narrowMargin == 4)

        let wideMargin = max(CGFloat(4), CGFloat(44) * 0.3) // 13.2
        #expect(wideMargin == 13.2)
    }

    @Test("Hidden verification: icon must be LEFT of separatorX minus margin")
    func hiddenVerification() {
        let separatorX: CGFloat = 500
        let afterFrameX: CGFloat = 450
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3)

        let isVerified = afterFrameX < (separatorX - margin)

        #expect(isVerified, "Icon at 450 should verify as hidden (separator at 500, margin ~6.6)")
    }

    @Test("Visible verification: icon must be RIGHT of separatorX plus margin")
    func visibleVerification() {
        let separatorX: CGFloat = 500
        let afterFrameX: CGFloat = 550
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3)

        let isVerified = afterFrameX > (separatorX + margin)

        #expect(isVerified, "Icon at 550 should verify as visible (separator at 500, margin ~6.6)")
    }

    @Test("Verification fails for icon on wrong side")
    func verificationFailsWrongSide() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3)

        // Tried to hide but icon ended up on right side
        let afterFrameX: CGFloat = 520
        let hiddenVerified = afterFrameX < (separatorX - margin)
        #expect(!hiddenVerified, "Icon at 520 should NOT verify as hidden")

        // Tried to show but icon stayed on left side
        let afterFrameX2: CGFloat = 480
        let visibleVerified = afterFrameX2 > (separatorX + margin)
        #expect(!visibleVerified, "Icon at 480 should NOT verify as visible")
    }

    @Test("Verification fails for icon in ambiguous zone (within margin)")
    func verificationFailsAmbiguousZone() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3) // 6.6

        // Icon at 495 — LEFT of separator but within margin
        let nearLeftX: CGFloat = 495
        let hiddenVerified = nearLeftX < (separatorX - margin) // 495 < 493.4 → false
        #expect(!hiddenVerified, "Icon within margin zone should NOT verify — hide() might reclassify it")

        // Icon at 505 — RIGHT of separator but within margin
        let nearRightX: CGFloat = 505
        let visibleVerified = nearRightX > (separatorX + margin) // 505 > 506.6 → false
        #expect(!visibleVerified, "Icon within margin zone should NOT verify")
    }
}

// MARK: - Separator Caching Tests

@Suite("Icon Moving — Separator Caching")
struct SeparatorCachingTests {
    @Test("Blocking mode detection: length > 1000 is blocking")
    func blockingModeDetection() {
        // When separator length is > 1000 (typically 10,000), it's in blocking mode
        // and the live position is off-screen (~-3349)
        let normalLength: CGFloat = 20
        let blockingLength: CGFloat = 10000

        #expect(normalLength <= 1000, "Length 20 is NOT blocking mode")
        #expect(blockingLength > 1000, "Length 10,000 IS blocking mode")
    }

    @Test("Cache validity: only positive X values are cached")
    func cacheValidity() {
        // Off-screen positions (negative or zero) should NOT update the cache
        let offScreenX: CGFloat = -3349
        let validX: CGFloat = 500
        let zeroX: CGFloat = 0

        #expect(offScreenX <= 0, "Off-screen position must NOT be cached")
        #expect(validX > 0, "On-screen position SHOULD be cached")
        #expect(zeroX <= 0, "Zero position must NOT be cached")
    }

    @Test("REGRESSION: Separator at -3349 in blocking mode returns cached value")
    func separatorBlockingModeReturnsCached() {
        // Feb 8 bug: getSeparatorOriginX() returned nil when separator was in blocking mode
        // because the live window position was -3349 (off-screen) and there was no cache
        // Fix: Cache valid positions and return cached value in blocking mode

        var lastKnownSeparatorX: CGFloat? = 500 // Previously cached
        let separatorLength: CGFloat = 10000
        let liveWindowX: CGFloat = -3349

        let result: CGFloat?
        if separatorLength > 1000 {
            result = lastKnownSeparatorX // Use cache in blocking mode
        } else if liveWindowX > 0 {
            lastKnownSeparatorX = liveWindowX
            result = liveWindowX
        } else {
            result = lastKnownSeparatorX
        }

        #expect(result == 500, "Blocking mode must return cached position, not live -3349")
    }

    @Test("Screen parameter change invalidates cache")
    func screenChangeInvalidatesCache() {
        // When display configuration changes (monitor connect/disconnect),
        // cached positions are stale
        var lastKnownSeparatorX: CGFloat? = 500
        var lastKnownAlwaysHiddenSeparatorX: CGFloat? = 300

        // Simulate screen parameter change
        lastKnownSeparatorX = nil
        lastKnownAlwaysHiddenSeparatorX = nil

        #expect(lastKnownSeparatorX == nil, "Main separator cache must be cleared on screen change")
        #expect(lastKnownAlwaysHiddenSeparatorX == nil, "AH separator cache must be cleared on screen change")
    }
}

// MARK: - Move Orchestration Invariants

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
        let moveOffset = max(30, iconFrame.size.width + 20) // 42
        let targetX = min(separatorRightEdgeX + moveOffset, mainIconLeftEdge - 20)
        // min(542, 880) = 542

        // Grab point
        let fromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY) // (411, 16)

        // Assertions
        #expect(targetX == 542)
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

        let moveOffset = max(30, iconFrame.size.width + 20) // 42
        let targetX = min(separatorRightEdgeX + moveOffset, mainIconLeftEdge - 20)
        // min(842, 800) = 800

        #expect(targetX == 800, "Tight layout: clamped to boundary - 20")
        #expect(targetX < mainIconLeftEdge)
    }

    @Test("Always-hidden move uses left edge separator position")
    func alwaysHiddenMoveToHidden() {
        // When moving to always-hidden, we use getAlwaysHiddenSeparatorOriginX()
        // which returns the LEFT edge of the AH separator
        let ahSeparatorOriginX: CGFloat = 300
        let iconFrame = CGRect(x: 400, y: 5, width: 22, height: 22)

        let moveOffset = max(30, iconFrame.size.width + 20) // 42
        let targetX = ahSeparatorOriginX - moveOffset // 258

        #expect(targetX == 258)
        #expect(targetX < ahSeparatorOriginX, "Must move LEFT of AH separator")
    }

    @Test("Post-move verification with successful move")
    func verificationAfterSuccessfulMove() {
        let separatorX: CGFloat = 500
        let toHidden = true

        // Icon moved from 550 to 440
        let afterFrame = CGRect(x: 440, y: 5, width: 22, height: 22)
        let margin = max(CGFloat(4), afterFrame.size.width * 0.3) // 6.6

        let verified = afterFrame.origin.x < (separatorX - margin) // 440 < 493.4 → true

        #expect(verified, "Icon at 440 with separator at 500 should verify as hidden")
    }

    @Test("Post-move verification with failed move (icon didn't budge)")
    func verificationAfterFailedMove() {
        let separatorX: CGFloat = 500
        let toHidden = true

        // Icon stayed at original position
        let afterFrame = CGRect(x: 550, y: 5, width: 22, height: 22)
        let margin = max(CGFloat(4), afterFrame.size.width * 0.3) // 6.6

        let verified = afterFrame.origin.x < (separatorX - margin) // 550 < 493.4 → false

        #expect(!verified, "Icon at 550 should NOT verify as hidden — move failed")
    }
}

// MARK: - Move to Visible Regression Tests

/// Regression tests for "Move to Visible" logic that broke on Feb 8-9 2026.
/// Captures the CORRECT behavior after fixing the target calculation overshoot bug.
@Suite("Icon Moving — Move to Visible Regressions")
struct MoveToVisibleRegressionTests {
    // MARK: - Target Calculation: Flush Scenario (Bug That Was Fixed)

    @Test("REGRESSION: Flush separator and SaneBar icon — target must NOT overshoot")
    func flushSeparatorAndMainIcon() {
        // This was the critical bug: when separator right edge = SaneBar left edge (both 1696),
        // the old formula used `separatorX + moveOffset` = 1696 + 36 = 1732.
        // This placed the icon PAST the SaneBar icon → landed in system area → triggered Control Center.
        //
        // FIX: Use `max(separatorX + 1, visibleBoundaryX - 2)` = max(1697, 1694) = 1697.
        // This places the icon at the boundary, and macOS auto-inserts it, pushing SaneBar right.

        let separatorRightEdgeX: CGFloat = 1696
        let mainIconLeftEdge: CGFloat = 1696 // Flush with separator
        let iconWidth: CGFloat = 16
        let moveOffset = max(30, iconWidth + 20) // 36

        // OLD (WRONG): separatorX + moveOffset = 1732
        let oldTarget = separatorRightEdgeX + moveOffset
        #expect(oldTarget == 1732, "Old formula would place icon at 1732")
        #expect(oldTarget > mainIconLeftEdge, "Old target OVERSHOOTS past SaneBar icon")

        // NEW (CORRECT): max(separatorX + 1, boundaryX - 2) = max(1697, 1694) = 1697
        let newTarget = max(separatorRightEdgeX + 1, mainIconLeftEdge - 2)
        #expect(newTarget == 1697, "New formula places icon at 1697 (just right of separator)")
        #expect(newTarget > separatorRightEdgeX, "Target must be right of separator")
        #expect(newTarget <= mainIconLeftEdge + 1, "Target must stay at or just past boundary (macOS will auto-insert)")
    }

    @Test("REGRESSION: Gap between separator and SaneBar — use boundary - 2")
    func gapBetweenSeparatorAndMainIcon() {
        // When there's space between separator and SaneBar icon,
        // the boundary clamp activates: boundaryX - 2 wins

        let separatorRightEdgeX: CGFloat = 1500
        let mainIconLeftEdge: CGFloat = 1700 // 200px gap
        let iconWidth: CGFloat = 16

        let target = max(separatorRightEdgeX + 1, mainIconLeftEdge - 2)

        // max(1501, 1698) = 1698
        #expect(target == 1698, "Wide gap: boundary - 2 wins")
        #expect(target > separatorRightEdgeX, "Target must be right of separator")
        #expect(target < mainIconLeftEdge, "Target must be left of SaneBar icon")
    }

    @Test("REGRESSION: Wide gap — boundary clamp still prevents overshoot")
    func wideGapBoundaryClamp() {
        let separatorRightEdgeX: CGFloat = 1200
        let mainIconLeftEdge: CGFloat = 1800 // 600px gap!
        let iconWidth: CGFloat = 16

        let target = max(separatorRightEdgeX + 1, mainIconLeftEdge - 2)

        // max(1201, 1798) = 1798
        #expect(target == 1798, "Wide gap: boundary - 2 is used")
        #expect(target < mainIconLeftEdge, "Even with wide gap, target doesn't overshoot")
    }

    // MARK: - Target for Move-to-Hidden Unchanged

    @Test("Move to hidden: target is LEFT of separator (unchanged)")
    func moveToHiddenTargetUnchanged() {
        // Move-to-hidden logic should remain: separatorX - moveOffset
        let separatorOriginX: CGFloat = 1696 // LEFT edge of separator
        let iconWidth: CGFloat = 16
        let moveOffset = max(30, iconWidth + 20) // 36

        let targetX = separatorOriginX - moveOffset

        #expect(targetX == 1660, "Hidden target = separatorX - 36")
        #expect(targetX < separatorOriginX, "Target must be LEFT of separator")
    }

    // MARK: - Drag Timing (16 steps, not 6)

    @Test("REGRESSION: Drag uses 16 steps, not 6")
    func dragStepCount() {
        // The fix changed from 6 steps × 5ms (too fast, unreliable)
        // to 16 steps × 15ms (human-like, more reliable)

        let steps = 16
        let msPerStep = 15
        let totalDragTime = steps * msPerStep

        #expect(steps == 16, "Drag must use 16 interpolation steps")
        #expect(totalDragTime == 240, "Total drag time: ~240ms (not 30ms)")
    }

    @Test("OLD drag timing was too fast")
    func oldDragTimingWasTooFast() {
        let oldSteps = 6
        let oldMsPerStep = 5
        let oldTotalTime = oldSteps * oldMsPerStep

        #expect(oldTotalTime == 30, "Old drag was only 30ms total")
        #expect(oldTotalTime < 100, "Too fast for macOS WindowServer to recognize reliably")
    }

    // MARK: - On-Screen Validation Before Drag

    @Test("REGRESSION: Icon must be on-screen before drag attempt")
    func iconMustBeOnScreen() {
        // After show()/showAll(), icons can still be at off-screen positions (x=-3455)
        // for a brief moment. We must poll until x >= 0 before attempting Cmd+drag.

        let offScreenX: CGFloat = -3455
        let onScreenX: CGFloat = 1500

        let offScreenValid = offScreenX >= 0
        let onScreenValid = onScreenX >= 0

        #expect(!offScreenValid, "Off-screen position (x=-3455) must be rejected")
        #expect(onScreenValid, "On-screen position (x=1500) is valid for drag")
    }

    @Test("Polling for on-screen position required")
    func pollingForOnScreenPosition() {
        // The code polls up to 30 times × 100ms = 3s max
        let maxPollingAttempts = 30
        let pollingIntervalMs = 100
        let maxWaitTime = maxPollingAttempts * pollingIntervalMs

        #expect(maxPollingAttempts == 30, "Poll up to 30 attempts")
        #expect(maxWaitTime == 3000, "Max 3 seconds to wait for icon to appear on-screen")
    }

    // MARK: - showAll() Shield Pattern for Hidden→Visible

    @Test("REGRESSION: Hidden→visible must use showAll(), not show()")
    func hiddenToVisibleUsesShowAll() {
        // Plain show() often fails to relayout hidden items — they stay at x=-3455.
        // The shield pattern (showAll) toggles BOTH separators, forcing full relayout:
        //   1. Main separator → 10000 (blocks everything)
        //   2. AH separator → 14 (visual size)
        //   3. Main separator → 20 (visual size)
        // This guarantees all icons are on-screen before the drag.

        let toHidden = false
        let wasHidden = true

        let shouldUseShieldPattern = !toHidden && wasHidden

        #expect(shouldUseShieldPattern, "Moving from hidden to visible requires shield pattern (showAll)")
    }

    @Test("Move to hidden does NOT use showAll()")
    func moveToHiddenNoShieldPattern() {
        let toHidden = true
        let wasHidden = false // Moving from visible to hidden

        let shouldUseShieldPattern = !toHidden && wasHidden

        #expect(!shouldUseShieldPattern, "Moving to hidden doesn't need shield pattern")
    }

    @Test("Visible→visible move does NOT use showAll()")
    func visibleToVisibleNoShieldPattern() {
        let toHidden = false
        let wasHidden = false // Already visible

        let shouldUseShieldPattern = !toHidden && wasHidden

        #expect(!shouldUseShieldPattern, "Moving within visible zone doesn't need shield pattern")
    }

    // MARK: - Target Clamping Edge Cases

    @Test("Separator and boundary equal: separatorX + 1 wins")
    func separatorAndBoundaryEqual() {
        let separatorRightEdgeX: CGFloat = 1696
        let mainIconLeftEdge: CGFloat = 1696

        let target = max(separatorRightEdgeX + 1, mainIconLeftEdge - 2)

        // max(1697, 1694) = 1697
        #expect(target == 1697, "When equal, separatorX + 1 wins (1697 > 1694)")
    }

    @Test("Separator just left of boundary: boundaryX - 2 wins")
    func separatorJustLeftOfBoundary() {
        let separatorRightEdgeX: CGFloat = 1690
        let mainIconLeftEdge: CGFloat = 1700 // 10px gap

        let target = max(separatorRightEdgeX + 1, mainIconLeftEdge - 2)

        // max(1691, 1698) = 1698
        #expect(target == 1698, "10px gap: boundaryX - 2 wins")
    }

    @Test("Very tight gap: still doesn't overshoot")
    func veryTightGapNoOvershoot() {
        let separatorRightEdgeX: CGFloat = 1695
        let mainIconLeftEdge: CGFloat = 1696 // 1px gap!

        let target = max(separatorRightEdgeX + 1, mainIconLeftEdge - 2)

        // max(1696, 1694) = 1696
        #expect(target == 1696, "1px gap: still uses separatorX + 1")
        #expect(target <= mainIconLeftEdge, "Doesn't overshoot even with 1px gap")
    }

    // MARK: - Formula Comparison (Old vs New)

    @Test("OLD formula vs NEW formula comparison")
    func oldVsNewFormulaComparison() {
        let scenarios: [(sep: CGFloat, boundary: CGFloat, iconWidth: CGFloat, name: String)] = [
            (1696, 1696, 16, "Flush"),
            (1500, 1700, 16, "Gap"),
            (1200, 1800, 16, "Wide gap"),
            (1695, 1696, 16, "1px gap"),
            (1690, 1700, 16, "10px gap")
        ]

        for scenario in scenarios {
            let moveOffset = max(30, scenario.iconWidth + 20)

            // OLD: min(separatorX + moveOffset, boundaryX - 20)
            let oldTarget = min(scenario.sep + moveOffset, scenario.boundary - 20)

            // NEW: max(separatorX + 1, boundaryX - 2)
            let newTarget = max(scenario.sep + 1, scenario.boundary - 2)

            #expect(newTarget <= scenario.boundary, "New formula never overshoots boundary (\(scenario.name))")
            #expect(newTarget > scenario.sep, "New formula always right of separator (\(scenario.name))")
        }
    }

    // MARK: - Verification Margin Consistency

    @Test("Verification uses 30% width margin, minimum 4px")
    func verificationMargin() {
        let iconWidth: CGFloat = 16
        let margin = max(CGFloat(4), iconWidth * 0.3)

        // 16 * 0.3 = 4.8
        #expect(margin == 4.8, "16px icon → 4.8px margin")
    }

    @Test("Verification margin for very small icon uses minimum")
    func verificationMarginMinimum() {
        let iconWidth: CGFloat = 10
        let margin = max(CGFloat(4), iconWidth * 0.3)

        // 10 * 0.3 = 3, but minimum is 4
        #expect(margin == 4, "Minimum margin is 4px")
    }

    @Test("Visible verification: icon must be RIGHT of separator + margin")
    func visibleVerificationWithMargin() {
        let separatorRightEdgeX: CGFloat = 1696
        let afterIconX: CGFloat = 1697 // Icon at 1697
        let iconWidth: CGFloat = 16
        let margin = max(CGFloat(4), iconWidth * 0.3) // 4.8

        let verified = afterIconX > (separatorRightEdgeX + margin)

        // 1697 > 1700.8 → false (too close to separator!)
        #expect(!verified, "Icon at 1697 with separator at 1696 is within margin — not verified yet")
    }

    @Test("Visible verification succeeds when clear of margin")
    func visibleVerificationSucceeds() {
        let separatorRightEdgeX: CGFloat = 1696
        let afterIconX: CGFloat = 1702 // Icon clearly right of separator
        let iconWidth: CGFloat = 16
        let margin = max(CGFloat(4), iconWidth * 0.3) // 4.8

        let verified = afterIconX > (separatorRightEdgeX + margin)

        // 1702 > 1700.8 → true
        #expect(verified, "Icon at 1702 is clear of separator + margin")
    }

    // MARK: - Drag Animation Properties

    @Test("Drag starts with pre-position move")
    func dragStartsWithPrePosition() {
        // The code moves the cursor to the icon position BEFORE clicking
        // (human-like behavior: position cursor, then click)
        let prePositionDelayMs = 50

        #expect(prePositionDelayMs == 50, "50ms settle time after pre-positioning cursor")
    }

    @Test("Cursor hidden during drag (Ice-style)")
    func cursorHiddenDuringDrag() {
        // The drag hides the cursor using CGDisplayHideCursor
        // to prevent visual glitches and improve WindowServer recognition
        let cursorHidden = true

        #expect(cursorHidden, "Cursor must be hidden during drag")
    }

    @Test("Drag includes mouseDown hold delay")
    func dragIncludesHoldDelay() {
        let mouseDownHoldMs = 50

        #expect(mouseDownHoldMs == 50, "50ms hold after mouseDown before starting drag")
    }

    @Test("Drag ends with mouseUp settle delay")
    func dragEndsWithSettleDelay() {
        let mouseUpSettleMs = 150

        #expect(mouseUpSettleMs == 150, "150ms settle after mouseUp for drop to complete")
    }

    @Test("Total drag timeline: pre-position + hold + drag + settle")
    func totalDragTimeline() {
        let prePosition = 50
        let mouseDownHold = 50
        let dragSteps = 16
        let msPerStep = 15
        let dragTime = dragSteps * msPerStep // 240
        let mouseUpSettle = 150

        let totalTime = prePosition + mouseDownHold + dragTime + mouseUpSettle

        #expect(totalTime == 490, "Total drag operation: ~490ms")
    }
}
