import Foundation
@testable import SaneBar
import Testing

/// #166 — external-display "dragging does nothing" regression lock.
///
/// Reproduced live on the Mini (external 1920 non-notched display, 2.1.86):
/// during active-space-changed churn, `MenuBarManager.restoreHiddenStateAfterHealthyValidationIfNeeded`
/// called `hidingService.applyCurrentStateToLiveItems()` unconditionally, forcing
/// the delimiter back to collapsed length (10000) while a concurrent move's own
/// `showAll()`/drag/`restoreFromShowAll()` shield had it expanded for the drag.
/// This raced move-target resolution: `move icon to hidden` hard-failed -2700
/// ("…wait a moment after wake or a display change") 3/3 rounds, and outbound
/// moves silently no-opped (icon frame BEFORE == AFTER) behind a false "Move
/// complete" log. Quiescent (no churn) moves on the same external display worked
/// fine both directions — this is specifically a move-vs-background-reapply race,
/// not a generic external-display geometry bug.
///
/// Fix: `MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery` now
/// defers (returns false) whenever `snapshot.hasActiveMoveTask` is true — the
/// caller's existing defer-and-retry path (`pendingRecoveryHideRestore = true`)
/// already handles this correctly; it simply waits for the move to finish before
/// reapplying the collapsed state.
struct HiddenStateReapplyMoveRaceTests {
    @Test("Background hidden-state reapply defers while a move is in flight")
    func reapplyDefersDuringActiveMove() {
        let liveSnapshot = MenuBarRuntimeSnapshot(
            structuralState: .ready,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
            startupItemsValid: true,
            hasActiveMoveTask: true
        )
        #expect(
            !MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: liveSnapshot
            )
        )

        let protectedCachedSnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            hasActiveMoveTask: true
        )
        #expect(
            !MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: protectedCachedSnapshot
            )
        )
    }

    @Test("Background hidden-state reapply proceeds once no move is in flight")
    func reapplyProceedsWithoutActiveMove() {
        // Same snapshot as the first case above, only hasActiveMoveTask flips to
        // false — proves the new guard changes behavior ONLY during an in-flight
        // move and the pre-existing healthy-reapply path is unchanged.
        let snapshot = MenuBarRuntimeSnapshot(
            structuralState: .ready,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
            startupItemsValid: true,
            hasActiveMoveTask: false
        )
        #expect(
            MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: snapshot
            )
        )
    }
}
