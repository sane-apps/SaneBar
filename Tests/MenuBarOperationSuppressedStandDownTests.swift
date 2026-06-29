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

    @Test("Live main + suppression heuristic stands down on screen-params too")
    func standsDownOnScreenParams() {
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: suppressedButMainLive(),
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .stop(.invalidStatusItems)
        )
    }

    /// Wake-drift regression caught by the wake layout probe (2026-06-29): the
    /// original #160 stand-down also fired on `.wakeResume`, so after a display
    /// sleep/wake the parked separator was never re-seated and a genuinely-visible
    /// icon drifted into the hidden zone and stayed there. A display sleep/wake is a
    /// real transition that needs bounded recovery (the #136 path), NOT a stand-down.
    /// So `.wakeResume` must perform one repair (recoveryCount 0), unlike the
    /// steady-state Space-switch / screen-params flicker triggers which stand down.
    @Test("Wake resume recovers (does NOT stand down) so the separator re-seats")
    func wakeResumeRecoversInsteadOfStandingDown() {
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: suppressedButMainLive(),
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
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
