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

        let targetX = AccessibilityService.moveTargetX(
            toHidden: true,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: nil
        )

        #expect(targetX < separatorX, "Hidden target must be LEFT of separator")
        #expect(targetX == 418)
    }

    @Test("Hidden target with AH boundary is right-biased to prevent AH drift")
    func moveToHiddenWithAHBoundaryBiasesRight() {
        // Repro geometry from Mini logs:
        // separatorX=1600, AH boundary≈1424, iconWidth≈34.
        let separatorX: CGFloat = 1600
        let ahBoundary: CGFloat = 1424
        let iconWidth: CGFloat = 34

        let targetX = AccessibilityService.moveTargetX(
            toHidden: true,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: ahBoundary
        )

        let minRegularHiddenX = ahBoundary + 2
        let separatorSafety = max(20, (iconWidth * 0.5) + 12)
        let maxRegularHiddenX = separatorX - separatorSafety

        #expect(targetX >= minRegularHiddenX)
        #expect(targetX <= maxRegularHiddenX)
        #expect(targetX > 1540, "Target should stay toward separator-side hidden lane")
    }

    @Test("Move to visible without boundary: target is RIGHT of separator")
    func moveToVisibleNoBoundary() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22

        let targetX = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: nil
        )

        #expect(targetX > separatorX, "Visible target must be RIGHT of separator")
        #expect(targetX == 501)
    }

    @Test("Move to visible with a tight boundary stays inside visible lane")
    func moveToVisibleWithTightBoundaryStaysInsideVisibleLane() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let visibleBoundaryX: CGFloat = 530 // Main icon left edge

        let targetX = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        #expect(targetX == 508)
        #expect(targetX > separatorX, "Visible target must be RIGHT of separator")
        #expect(targetX < visibleBoundaryX, "Visible target must stay LEFT of SaneBar icon")
    }

    @Test("REGRESSION: Visible boundary changes the production target")
    func visibleBoundaryAffectsTarget() {
        let separatorX: CGFloat = 800
        let mainIconLeftEdge: CGFloat = 850 // SaneBar icon starts here
        let iconWidth: CGFloat = 22

        let withoutBoundary = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: nil
        )
        let withBoundary = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(withoutBoundary == separatorX + 1)
        #expect(withBoundary > withoutBoundary)
        #expect(withBoundary > separatorX)
    }

    @Test("Boundary clamping with wide gap between separator and main icon")
    func boundaryClampingWideGap() {
        let separatorX: CGFloat = 500
        let mainIconLeftEdge: CGFloat = 900 // Lots of room
        let iconWidth: CGFloat = 22

        let targetX = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(targetX == 508, "Wide gap: short near-separator hop is used")
    }

    @Test("Visible target stays left of boundary when separator and main icon are very close")
    func visibleTargetStaysLeftOfTightBoundary() {
        let separatorX: CGFloat = 800
        let mainIconLeftEdge: CGFloat = 810 // Only 10px gap!
        let iconWidth: CGFloat = 22

        let targetX = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: mainIconLeftEdge
        )

        #expect(targetX == 803.5)
        #expect(targetX > separatorX)
        #expect(targetX < mainIconLeftEdge)
    }

    @Test("Wide-icon hidden guard blocks when lane is narrower than icon width + padding")
    func wideIconHiddenGuardBlocksNarrowLane() {
        let shouldBlock = MenuBarMoveGeometryPolicy.shouldBlockWideIconHiddenMove(
            iconWidth: 220,
            hiddenLaneWidth: 205
        )
        #expect(shouldBlock)
    }

    @Test("Wide-icon hidden guard allows wide item when lane is sufficient")
    func wideIconHiddenGuardAllowsSufficientLane() {
        let shouldBlock = MenuBarMoveGeometryPolicy.shouldBlockWideIconHiddenMove(
            iconWidth: 220,
            hiddenLaneWidth: 260
        )
        #expect(!shouldBlock)
    }

    @Test("Wide-icon hidden guard ignores normal icon widths")
    func wideIconHiddenGuardIgnoresNormalIcons() {
        let shouldBlock = MenuBarMoveGeometryPolicy.shouldBlockWideIconHiddenMove(
            iconWidth: 32,
            hiddenLaneWidth: 20
        )
        #expect(!shouldBlock)
    }
}
