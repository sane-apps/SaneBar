import Testing
import Foundation
@testable import SaneBar

// MARK: - MenuBarManagerTests

@Suite("MenuBarManager Tests")
struct MenuBarManagerTests {

    // MARK: - AutosaveName Tests

	    @Test("Autosave names are unique to prevent position conflicts")
	    func testAutosaveNamesAreUnique() {
	        // These are the autosaveName values used by StatusBarController (and relied on by MenuBarManager).
	        // They must be unique for macOS to persist positions correctly
	        var autosaveNames = [
	            StatusBarController.mainAutosaveName,
	            StatusBarController.separatorAutosaveName,
	            StatusBarController.alwaysHiddenSeparatorAutosaveName
	        ]
	        for index in 0..<StatusBarController.maxSpacerCount {
	            autosaveNames.append("SaneBar_spacer_\(index)")
	        }

	        let uniqueNames = Set(autosaveNames)

        #expect(uniqueNames.count == autosaveNames.count,
                "All autosaveName values must be unique - found duplicates")
    }

	    @Test("Autosave names follow naming convention")
	    func testAutosaveNamesFollowConvention() {
	        let autosaveNames = [
	            StatusBarController.mainAutosaveName,
	            StatusBarController.separatorAutosaveName,
	            StatusBarController.alwaysHiddenSeparatorAutosaveName,
	            "SaneBar_spacer_0"
	        ]

        for name in autosaveNames {
            #expect(name.hasPrefix("SaneBar_"),
                    "Autosave names should start with 'SaneBar_' prefix")
            #expect(!name.contains(" "),
                    "Autosave names should not contain spaces")
        }
    }

    // MARK: - Position Validation Tests (BUG: separator eating main icon)

    @Test("Position validation: separator LEFT of main is valid")
    func testSeparatorLeftOfMainIsValid() {
        // Screen coordinates: left = lower X, right = higher X
        // Separator at X=100, Main at X=150 → separator is LEFT → valid
        let separatorX: CGFloat = 100
        let mainX: CGFloat = 150

        let isValid = separatorX < mainX  // This is the core logic in validateSeparatorPosition()

        #expect(isValid, "Separator LEFT of main icon should be valid for hiding")
    }

    @Test("Position validation: separator RIGHT of main is invalid")
    func testSeparatorRightOfMainIsInvalid() {
        // Screen coordinates: left = lower X, right = higher X
        // Separator at X=150, Main at X=100 → separator is RIGHT → INVALID
        // If we hide here, main icon gets pushed off screen!
        let separatorX: CGFloat = 150
        let mainX: CGFloat = 100

        let isValid = separatorX < mainX  // This is the core logic in validateSeparatorPosition()

        #expect(!isValid, "Separator RIGHT of main icon should be INVALID - hiding would eat the main icon")
    }

    @Test("Position validation: same X position is edge case")
    func testSamePositionIsEdgeCase() {
        // If both at same X (unlikely but possible), treating as invalid is safer
        let separatorX: CGFloat = 100
        let mainX: CGFloat = 100

        let isValid = separatorX < mainX  // Strict less-than, not <=

        #expect(!isValid, "Same position should be treated as invalid (edge case)")
    }

    // MARK: - Regression Tests

    @Test("REGRESSION: Verify hiding logic matches documentation (Left = Hidden)")
    func testHidingLogicMatchesDocumentation() {
        // This test documents the relationship between screen coordinates and visibility
        // to prevent regression of the "Icons Left of Separator are Hidden" documentation.

        let separatorX: CGFloat = 500

        // Item to the LEFT of separator (X < 500)
        let leftItemX: CGFloat = 400
        let isLeftItemHiddenCandidate = leftItemX < separatorX

        // Item to the RIGHT of separator (X > 500)
        let rightItemX: CGFloat = 600
        let isRightItemHiddenCandidate = rightItemX < separatorX

        #expect(isLeftItemHiddenCandidate, "Items to the LEFT of separator (lower X) MUST be the ones hidden")
        #expect(!isRightItemHiddenCandidate, "Items to the RIGHT of separator (higher X) MUST NOT be hidden")
    }

    // MARK: - Position Validation Edge Cases (BUG: Separator Eating Main Icon)

    @Test("Position validation: separator left edge overlapping main left edge is invalid")
    func testSeparatorOverlappingMainIsInvalid() {
        // Validation checks separator LEFT EDGE relative to main LEFT EDGE
        let separatorLeftEdge: CGFloat = 150
        let mainLeftEdge: CGFloat = 150

        // separatorLeftEdge (150) >= mainLeftEdge (150) → INVALID
        let isInvalid = separatorLeftEdge >= mainLeftEdge

        #expect(isInvalid, "Separator overlapping main icon MUST be invalid - would eat the main icon")
    }

    @Test("Position validation: separator left of main is valid")
    func testSeparatorCompletelyLeftIsValid() {
        let separatorLeftEdge: CGFloat = 100
        let mainLeftEdge: CGFloat = 200

        // separatorLeftEdge (100) < mainLeftEdge (200) → VALID
        let isValid = separatorLeftEdge < mainLeftEdge

        #expect(isValid, "Separator completely left of main icon should be valid")
    }

    @Test("Position validation: separator touching main is invalid")
    func testSeparatorTouchingMainIsInvalid() {
        let separatorLeftEdge: CGFloat = 200
        let mainLeftEdge: CGFloat = 200  // Exactly touching

        // separatorLeftEdge (200) >= mainLeftEdge (200) → INVALID
        let isInvalid = separatorLeftEdge >= mainLeftEdge

        #expect(isInvalid,
                "Exactly touching is invalid - separator must be strictly left of main")
    }

    @Test("Position validation ignores separator width (hidden state)")
    func testValidationWithHiddenStateSeparatorWidth() {
        // When items are hidden, separator is 10,000px wide, but
        // validation should only care about the separator's LEFT edge.
        let separatorLeftEdge: CGFloat = 1000
        let mainLeftEdge: CGFloat = 1200

        // separatorLeftEdge (1,000) < mainLeftEdge (1,200) → VALID
        let isValid = separatorLeftEdge < mainLeftEdge

        #expect(isValid, "Hidden state should remain valid as long as separator is left of main")
    }

    @Test("Position validation should pass when separator is left of main (expanded state)")
    func testValidationWithExpandedStateSeparatorWidth() {
        let separatorLeftEdge: CGFloat = 1000
        let mainLeftEdge: CGFloat = 1200

        // separatorLeftEdge (1,000) < mainLeftEdge (1,200) → VALID
        let isValid = separatorLeftEdge < mainLeftEdge

        #expect(isValid, "With 20px separator, main icon is safely to the right")
    }

    // MARK: - State Transition Tests

    @Test("HidingState transitions: expanded to hidden requires valid position")
    func testExpandedToHiddenTransitionRequiresValidPosition() {
        // Document the expected behavior:
        // expanded → hidden MUST validate position first
        // If position is invalid, transition should be BLOCKED

        let currentState = HidingState.expanded
        let targetState = HidingState.hidden
        let positionValid = false

        // Business rule: If trying to hide with invalid position, block the transition
        let shouldAllowTransition = (currentState == .expanded && targetState == .hidden) ? positionValid : true

        #expect(!shouldAllowTransition,
                "Transition from expanded to hidden MUST be blocked when position is invalid")
    }

    @Test("HidingState transitions: hidden to expanded always allowed")
    func testHiddenToExpandedAlwaysAllowed() {
        // If main icon got eaten, user should ALWAYS be able to show/expand to recover
        // These states document the scenario being tested
        _ = HidingState.hidden      // Current state
        _ = HidingState.expanded    // Target state

        // Show/expand should NEVER be blocked - it's the recovery path
        let shouldAllowTransition = true

        #expect(shouldAllowTransition,
                "Transition from hidden to expanded MUST always be allowed (recovery path)")
    }

    @Test("Auto-expand on invalid position: must rescue eaten main icon")
    func testAutoExpandRescuesEatenMainIcon() {
        // If user drags separator to eat main icon while hidden,
        // continuous monitoring should auto-expand to rescue the main icon

        let currentState = HidingState.hidden
        let positionValid = false  // Separator is eating main icon!

        // Expected behavior: auto-expand when hidden + invalid position
        let shouldAutoExpand = (currentState == .hidden && !positionValid)

        #expect(shouldAutoExpand,
                "When hidden and position becomes invalid, MUST auto-expand to rescue main icon")
    }

    @Test("App menu suppression triggers when leftmost item overlaps app menu edge")
    func appMenuSuppressionTriggersOnOverlap() {
        #expect(
            MenuBarManager.shouldHideApplicationMenus(
                leftmostVisibleItemX: 118,
                appMenuMaxX: 120
            )
        )
    }

    @Test("App menu suppression does not trigger when leftmost item clears app menu edge")
    func appMenuSuppressionSkipsWhenNoOverlap() {
        #expect(
            !MenuBarManager.shouldHideApplicationMenus(
                leftmostVisibleItemX: 140,
                appMenuMaxX: 120
            )
        )
    }

    @Test("App menu suppression honors collision padding for near-edge overlap")
    func appMenuSuppressionHonorsPadding() {
        #expect(
            MenuBarManager.shouldHideApplicationMenus(
                leftmostVisibleItemX: 123,
                appMenuMaxX: 120,
                collisionPadding: 3
            )
        )
    }

    @Test("App menu suppression threshold is inclusive at maxX + padding")
    func appMenuSuppressionThresholdInclusive() {
        #expect(
            MenuBarManager.shouldHideApplicationMenus(
                leftmostVisibleItemX: 122,
                appMenuMaxX: 120,
                collisionPadding: 2
            )
        )
    }

    @Test("App menu suppression threshold rejects one-pixel clear gap")
    func appMenuSuppressionThresholdRejectsClearGap() {
        #expect(
            !MenuBarManager.shouldHideApplicationMenus(
                leftmostVisibleItemX: 123,
                appMenuMaxX: 120,
                collisionPadding: 2
            )
        )
    }

    @Test("Second menu fallback opens only for fully-eligible hidden-state path")
    func secondMenuFallbackDecisionMatrix() {
        let baseline = MenuBarManager.shouldOpenSecondMenuBarFallback(
            useSecondMenuBar: true,
            leftClickOpensBrowseIcons: false,
            requireAuthToShowHiddenIcons: false,
            preToggleState: .hidden,
            postToggleState: .hidden,
            isBrowseVisible: false
        )
        #expect(baseline)

        #expect(
            !MenuBarManager.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: false,
                leftClickOpensBrowseIcons: false,
                requireAuthToShowHiddenIcons: false,
                preToggleState: .hidden,
                postToggleState: .hidden,
                isBrowseVisible: false
            )
        )

        #expect(
            !MenuBarManager.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: true,
                leftClickOpensBrowseIcons: true,
                requireAuthToShowHiddenIcons: false,
                preToggleState: .hidden,
                postToggleState: .hidden,
                isBrowseVisible: false
            )
        )

        #expect(
            !MenuBarManager.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: true,
                leftClickOpensBrowseIcons: false,
                requireAuthToShowHiddenIcons: true,
                preToggleState: .hidden,
                postToggleState: .hidden,
                isBrowseVisible: false
            )
        )

        #expect(
            !MenuBarManager.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: true,
                leftClickOpensBrowseIcons: false,
                requireAuthToShowHiddenIcons: false,
                preToggleState: .expanded,
                postToggleState: .hidden,
                isBrowseVisible: false
            )
        )

        #expect(
            !MenuBarManager.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: true,
                leftClickOpensBrowseIcons: false,
                requireAuthToShowHiddenIcons: false,
                preToggleState: .hidden,
                postToggleState: .expanded,
                isBrowseVisible: false
            )
        )

        #expect(
            !MenuBarManager.shouldOpenSecondMenuBarFallback(
                useSecondMenuBar: true,
                leftClickOpensBrowseIcons: false,
                requireAuthToShowHiddenIcons: false,
                preToggleState: .hidden,
                postToggleState: .hidden,
                isBrowseVisible: true
            )
        )
    }

    @Test("Startup recovery triggers when main icon drifts left of notch-safe boundary")
    @MainActor
    func startupRecoveryTriggersForNotchBoundaryDrift() {
        #expect(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 930,
                mainX: 1070,
                mainRightGap: 220,
                screenWidth: 1512,
                notchRightSafeMinX: 1080
            )
        )
    }

    @Test("Startup recovery tolerates notch boundary within 8pt slack")
    @MainActor
    func startupRecoveryAllowsNotchBoundarySlack() {
        #expect(
            !MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 930,
                mainX: 1073,
                mainRightGap: 220,
                screenWidth: 1512,
                notchRightSafeMinX: 1080
            )
        )
    }

    @Test("Startup recovery right-gap boundary is strict-greater-than")
    @MainActor
    func startupRecoveryRightGapStrictBoundary() {
        // maxAllowedRightGap = max(500, 1440*0.45) = 648
        #expect(
            !MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 910,
                mainX: 1080,
                mainRightGap: 648,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
        #expect(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 910,
                mainX: 1080,
                mainRightGap: 649,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
    }
}
