@testable import SaneBar
import Testing

@Suite("Menu Bar Operation — Suppressed-Heuristic Stand-Down (#160)")
struct MenuBarOperationSuppressedStandDownTests {
    /// Runtime-confirmed 2026-06-29 on a single notched display (and matches the
    /// multi-monitor reporter): the hidden separator parked off-screen (length
    /// 10000) trips the suppression heuristic (likelySystemSuppressedStatusItems
    /// == true). That branch recreated the layout — the visible flash on every
    /// Space / app switch — BEFORE the live-main stand-down could run. A genuinely
    /// live main proves the items are NOT actually suppressed, so the stand-down
    /// must win over the suppressed branch.
    private func suppressedButMainLive() -> MenuBarRuntimeSnapshot {
        MenuBarRuntimeSnapshot(
            structuralState: .unattachedWindows,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live,
            startupItemsValid: false,
            likelySystemSuppressedStatusItems: true,
            separatorX: nil,
            mainX: 1242,
            mainRightGap: 221,
            screenWidth: 1470
        )
    }

    @Test("Live main + suppression heuristic stands down on active-space-changed")
    func standsDownOnActiveSpaceChanged() {
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: suppressedButMainLive(),
                context: .positionValidation(.activeSpaceChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .stop(.invalidStatusItems)
        )
    }

    @Test("Live main + suppression heuristic stands down on wake and screen-params too")
    func standsDownOnWakeAndScreenParams() {
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: suppressedButMainLive(),
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .stop(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: suppressedButMainLive(),
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .stop(.invalidStatusItems)
        )
    }

    @Test("Genuine main suppression (main not live) still recovers — #152 preserved")
    func genuineMainSuppressionStillRecovers() {
        let suppressedMainNotLive = MenuBarRuntimeSnapshot(
            structuralState: .unattachedWindows,
            separatorAnchorSource: .missing,
            mainAnchorSource: .missing,
            startupItemsValid: false,
            likelySystemSuppressedStatusItems: true,
            mainX: 1242,
            screenWidth: 1470
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: suppressedMainNotLive,
                context: .positionValidation(.activeSpaceChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
    }
}
