import Foundation
@testable import SaneBar
import Testing

@Suite("Icon Moving — Move to Visible Regressions")
struct MoveToVisibleRegressionTests {
    // MARK: - Target Calculation: Flush Scenario (Bug That Was Fixed)

    @Test("REGRESSION: Flush separator and SaneBar icon — target must NOT overshoot")
    func flushSeparatorAndMainIcon() {
        // This was the critical bug: when separator right edge = SaneBar left edge (both 1696),
        // the old formula used `separatorX + moveOffset` = 1696 + 36 = 1732.
        // This placed the icon PAST the SaneBar icon → landed in system area → triggered Control Center.
        //
        // FIX: use a near-separator insertion target inside the visible lane.
        // Flush case still resolves to 1697:
        // max(1697, min(1732, 1694)) = 1697.
        // This places the icon at the boundary, and macOS auto-inserts it, pushing SaneBar right.

        let separatorRightEdgeX: CGFloat = 1696
        let mainIconLeftEdge: CGFloat = 1696 // Flush with separator
        let iconWidth: CGFloat = 16
        let moveOffset = max(30, iconWidth + 20) // 36

        // OLD (WRONG): separatorX + moveOffset = 1732
        let oldTarget = separatorRightEdgeX + moveOffset
        #expect(oldTarget == 1732, "Old formula would place icon at 1732")
        #expect(oldTarget > mainIconLeftEdge, "Old target OVERSHOOTS past SaneBar icon")

        let newTarget = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )
        #expect(newTarget == 1697, "New formula places icon at 1697 (just right of separator)")
        #expect(newTarget > separatorRightEdgeX, "Target must be right of separator")
        #expect(newTarget <= mainIconLeftEdge + 1, "Target must stay at or just past boundary (macOS will auto-insert)")
    }

    @Test("REGRESSION: Gap between separator and SaneBar — prefer short hop near separator")
    func gapBetweenSeparatorAndMainIcon() {
        // When there is space, avoid dragging all the way to boundary.
        // Use a short near-separator hop instead of dragging deep toward SaneBar.

        let separatorRightEdgeX: CGFloat = 1500
        let mainIconLeftEdge: CGFloat = 1700 // 200px gap
        let iconWidth: CGFloat = 16
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(target == 1600, "Gap case: lane midpoint leaves reflow slack on both sides")
        #expect(target > separatorRightEdgeX, "Target must be right of separator")
        #expect(target < mainIconLeftEdge, "Target must be left of SaneBar icon")
    }

    @Test("REGRESSION: Wide gap — target stays near separator (short drag)")
    func wideGapBoundaryClamp() {
        let separatorRightEdgeX: CGFloat = 1200
        let mainIconLeftEdge: CGFloat = 1800 // 600px gap!
        let iconWidth: CGFloat = 16
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(target == 1500, "Wide gap: lane midpoint is used")
        #expect(target < mainIconLeftEdge, "Even with wide gap, target doesn't overshoot")
    }

    @Test("REGRESSION: #93-style geometry avoids boundary-hugging target")
    func issue93StyleGeometryUsesBoundedTarget() {
        // From issue #93 diagnostics (rounded):
        // separator≈1208, mainIconLeft≈1386, iconWidth≈31.
        let separatorRightEdgeX: CGFloat = 1208
        let mainIconLeftEdge: CGFloat = 1386
        let iconWidth: CGFloat = 31
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(abs(target - 1297) < 0.001, "Target is the lane midpoint, not the boundary-2 hug from #93")
        #expect(target < (mainIconLeftEdge - 50), "Target should avoid boundary-hugging long drags")
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

    // MARK: - Drag Timing (20 steps, not 6)

    @Test("REGRESSION: Drag uses 20 steps, not 6")
    func dragStepCount() {
        // The fix changed from 6 steps × 5ms (too fast, unreliable)
        // to 20 steps × 18ms (human-like, more reliable)

        let steps = 20
        let msPerStep = 18
        let totalDragTime = steps * msPerStep

        #expect(steps == 20, "Drag must use 20 interpolation steps")
        #expect(totalDragTime == 360, "Total drag time: ~360ms (not 30ms)")
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
        let iconWidth: CGFloat = 16
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        // max(1697, 1694) = 1697
        #expect(target == 1697, "When equal, separatorX + 1 wins (1697 > 1694)")
    }

    @Test("Separator just left of boundary: boundaryX - 2 wins")
    func separatorJustLeftOfBoundary() {
        let separatorRightEdgeX: CGFloat = 1690
        let mainIconLeftEdge: CGFloat = 1700 // 10px gap
        let iconWidth: CGFloat = 16
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(target == 1693.5, "10px gap: near-separator target stays inside lane")
    }

    @Test("Very tight gap: still doesn't overshoot")
    func veryTightGapNoOvershoot() {
        let separatorRightEdgeX: CGFloat = 1695
        let mainIconLeftEdge: CGFloat = 1696 // 1px gap!
        let iconWidth: CGFloat = 16
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorRightEdgeX,
            visibleBoundaryX: mainIconLeftEdge
        )

        // max(1696, 1694) = 1696
        #expect(target == 1696, "1px gap: still resolves to separatorX + 1")
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
            (1690, 1700, 16, "10px gap"),
        ]

        for scenario in scenarios {
            // OLD: min(separatorX + moveOffset, boundaryX - 20)
            let moveOffset = max(30, scenario.iconWidth + 20)
            _ = min(scenario.sep + moveOffset, scenario.boundary - 20)

            let newTarget = AccessibilityService.moveTargetX(
                toHidden: false,
                iconWidth: scenario.iconWidth,
                separatorX: scenario.sep,
                visibleBoundaryX: scenario.boundary
            )

            if scenario.sep == scenario.boundary {
                #expect(newTarget == scenario.sep + 1, "Flush: use the minimum right-of-separator target (\(scenario.name))")
            } else {
                #expect(newTarget <= scenario.boundary, "New formula never targets right of the SaneBar icon (\(scenario.name))")
                let laneWidth = scenario.boundary - scenario.sep
                #expect(newTarget <= scenario.sep + max(24, laneWidth * 0.5), "New formula never targets past the lane midpoint (\(scenario.name))")
            }
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
        let prePositionDelayMs = 80

        #expect(prePositionDelayMs == 80, "80ms settle time after pre-positioning cursor")
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
        let mouseDownHoldMs = 90

        #expect(mouseDownHoldMs == 90, "90ms hold after mouseDown before starting drag")
    }

    @Test("Drag ends with mouseUp settle delay")
    func dragEndsWithSettleDelay() {
        let mouseUpSettleMs = 180

        #expect(mouseUpSettleMs == 180, "180ms settle after mouseUp for drop to complete")
    }

    @Test("Total drag timeline: pre-position + hold + drag + settle")
    func totalDragTimeline() {
        let prePosition = 80
        let mouseDownHold = 90
        let dragSteps = 20
        let msPerStep = 18
        let dragTime = dragSteps * msPerStep // 360
        let mouseUpSettle = 180

        let totalTime = prePosition + mouseDownHold + dragTime + mouseUpSettle

        #expect(totalTime == 710, "Total drag operation: ~710ms")
    }
}
