import Foundation
@testable import SaneBar
import Testing

struct MenuBarAutomaticMoveGateTests {
    @Test("User-initiated moves always pass the gate")
    func userInitiatedMovesAlwaysPass() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .explicitUserAction, armedUntil: nil, recentAutomaticMoveCount: 0, now: now
        ))
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .appleScriptUserAction, armedUntil: nil, recentAutomaticMoveCount: 99, now: now
        ))
    }

    @Test("Automatic moves are blocked while the gate is not armed")
    func automaticMovesBlockedWhenUnarmed() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .systemWakeRecovery, armedUntil: nil, recentAutomaticMoveCount: 0, now: now
        ) == false)
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .systemWakeRecovery,
            armedUntil: now.addingTimeInterval(-1),
            recentAutomaticMoveCount: 0,
            now: now
        ) == false)
    }

    @Test("Automatic moves pass while armed and under the rate limit")
    func automaticMovesPassWhileArmed() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .systemWakeRecovery,
            armedUntil: now.addingTimeInterval(10),
            recentAutomaticMoveCount: MenuBarAutomaticMoveGate.maxAutomaticMovesPerWindow - 1,
            now: now
        ))
    }

    @Test("Automatic moves are rate-limited even while armed")
    func automaticMovesRateLimitedWhileArmed() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .systemWakeRecovery,
            armedUntil: now.addingTimeInterval(10),
            recentAutomaticMoveCount: MenuBarAutomaticMoveGate.maxAutomaticMovesPerWindow,
            now: now
        ) == false)
    }

    @Test("Automatic move batches can arm a larger bounded budget")
    func automaticMoveBatchesCanArmLargerBoundedBudget() {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .systemWakeRecovery,
            armedUntil: now.addingTimeInterval(10),
            recentAutomaticMoveCount: 11,
            moveBudget: 12,
            now: now
        ))
        #expect(MenuBarAutomaticMoveGate.automaticMoveDecision(
            origin: .systemWakeRecovery,
            armedUntil: now.addingTimeInterval(10),
            recentAutomaticMoveCount: 12,
            moveBudget: 12,
            now: now
        ) == false)

        #expect(MenuBarAutomaticMoveGate.automaticMoveBudget(forCandidateItemCount: 2) == 6)
        #expect(MenuBarAutomaticMoveGate.automaticMoveBudget(forCandidateItemCount: 9) == 18)
        #expect(MenuBarAutomaticMoveGate.automaticMoveBudget(forCandidateItemCount: 40) == 24)
    }

    @Test("Gate instance arms, records posted moves, and disarms")
    func gateInstanceLifecycle() {
        let gate = MenuBarAutomaticMoveGate()
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now) == false)

        gate.arm(for: 30, now: now)
        for i in 0 ..< MenuBarAutomaticMoveGate.maxAutomaticMovesPerWindow {
            let sampleTime = now.addingTimeInterval(Double(i))
            #expect(gate.allowsMove(origin: .systemWakeRecovery, now: sampleTime))
            gate.recordPostedMove(origin: .systemWakeRecovery, now: sampleTime)
        }
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(8)) == false)

        gate.disarm()
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(9)) == false)
        #expect(gate.allowsMove(origin: .explicitUserAction, now: now.addingTimeInterval(9)))
    }

    @Test("Gate instance honors the armed batch budget")
    func gateInstanceHonorsArmedBatchBudget() {
        let gate = MenuBarAutomaticMoveGate()
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        gate.arm(for: 30, moveBudget: 12, now: now)
        for i in 0 ..< 12 {
            let sampleTime = now.addingTimeInterval(Double(i))
            #expect(gate.allowsMove(origin: .systemWakeRecovery, now: sampleTime))
            gate.recordPostedMove(origin: .systemWakeRecovery, now: sampleTime)
        }
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(12)) == false)
    }

    @Test("Failed preconditions do not spend automatic move budget")
    func failedPreconditionsDoNotSpendAutomaticMoveBudget() {
        let gate = MenuBarAutomaticMoveGate()
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        gate.arm(for: 30, moveBudget: 6, now: now)
        for i in 0 ..< 20 {
            #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(Double(i))))
        }
    }

    @Test("Rearming starts a fresh bounded automatic move batch")
    func rearmingStartsFreshBoundedBatch() {
        let gate = MenuBarAutomaticMoveGate()
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        gate.arm(for: 30, moveBudget: 6, now: now)
        for i in 0 ..< 6 {
            let sampleTime = now.addingTimeInterval(Double(i))
            #expect(gate.allowsMove(origin: .systemWakeRecovery, now: sampleTime))
            gate.recordPostedMove(origin: .systemWakeRecovery, now: sampleTime)
        }
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(7)) == false)

        gate.arm(for: 30, moveBudget: 6, now: now.addingTimeInterval(8))
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(9)))
    }

    @Test("Immediate wake replays stay passive until healthy validation")
    func immediateWakeReplaysStayPassive() {
        // The wake probe enforces a zero-cursor-movement contract for passive
        // wake (#151, #154): raw wake notifications run before geometry and
        // third-party dynamic items have settled.
        for confidence in [MenuBarGeometryConfidence.live, .cached, .shielded, .stale, .missing] {
            let wake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "wake-resume-attempt-1",
                geometryConfidence: confidence,
                hidingState: .hidden
            )
            #expect(wake.mode == .auditOnly)
            #expect(wake.physicalMoveOrigin == nil)
        }
    }

    @Test("Post-wake healthy validation stays passive on trustworthy geometry")
    func postWakeHealthyValidationStaysPassive() {
        for confidence in [MenuBarGeometryConfidence.live, .cached] {
            let postWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "healthy-validation-wake-resume-attempt-1",
                geometryConfidence: confidence,
                hidingState: .hidden
            )
            #expect(postWake.mode == .auditOnly)
            #expect(postWake.physicalMoveOrigin == nil)

            let expandedPostWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "healthy-validation-wake-resume-attempt-1",
                geometryConfidence: confidence,
                hidingState: .expanded
            )
            #expect(expandedPostWake.mode == .auditOnly)
            #expect(expandedPostWake.physicalMoveOrigin == nil)
        }

        for confidence in [MenuBarGeometryConfidence.shielded, .stale, .missing] {
            let degradedPostWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "healthy-validation-wake-resume-attempt-1",
                geometryConfidence: confidence,
                hidingState: .hidden
            )
            #expect(degradedPostWake.mode == .auditOnly)
            #expect(degradedPostWake.physicalMoveOrigin == nil)
        }
    }

    @Test("Post-wake visible allow-list repair requires pending live healthy geometry")
    func postWakeVisibleAllowListRepairRequiresPendingLiveHealthyGeometry() {
        let livePostWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "healthy-validation-wake-resume-attempt-1",
            geometryConfidence: .live,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: true
        )
        #expect(livePostWake.mode == .repairWithPhysicalMoves)
        #expect(livePostWake.physicalMoveOrigin == .systemWakeRecovery)

        let noPendingLivePostWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "healthy-validation-wake-resume-attempt-1",
            geometryConfidence: .live,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: false
        )
        #expect(noPendingLivePostWake.mode == .auditOnly)
        #expect(noPendingLivePostWake.physicalMoveOrigin == nil)

        for confidence in [MenuBarGeometryConfidence.cached, .shielded, .stale, .missing] {
            let degradedPostWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "healthy-validation-wake-resume-attempt-1",
                geometryConfidence: confidence,
                hidingState: .hidden,
                hasVisibleAllowList: true,
                hasPendingWakeVisibleAllowListReplay: true
            )
            #expect(degradedPostWake.mode == .auditOnly)
            #expect(degradedPostWake.physicalMoveOrigin == nil)
        }

        #expect(
            MenuBarVisibilityPolicy.shouldDeferHiddenStateForWakeVisibleAllowList(
                reason: "healthy-validation-wake-resume",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldDeferHiddenStateForWakeVisibleAllowList(
                reason: "healthy-validation-startup-follow-up",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldDeferHiddenStateForWakeVisibleAllowList(
                reason: "healthy-validation-wake-resume",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: false
            )
        )
    }

    @Test("Immediate wake auto-rehide waits for pending visible allow-list replay")
    func immediateWakeAutoRehideWaitsForPendingVisibleAllowListReplay() {
        #expect(
            MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
                reason: "wakeResume",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
                reason: "wake-resume",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
                reason: "healthy-validation-wake-resume-attempt-1",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
                reason: "wakeResume",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: false
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
                reason: "wakeResume",
                hideAllOtherMenuBarItems: false,
                visibleAllowListIds: ["com.ameba.SwiftBar::statusItem:0"],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
                reason: "wakeResume",
                hideAllOtherMenuBarItems: true,
                visibleAllowListIds: [],
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
    }

    @Test("Pending wake visible allow-list replay can repair protected hidden cached geometry")
    func pendingWakeVisibleAllowListReplayRepairsProtectedHiddenCachedGeometry() {
        let protectedHiddenCached = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            mainItemVisible: true,
            separatorItemVisible: true,
            separatorX: 1680,
            mainX: 1700,
            mainRightGap: 220,
            screenWidth: 1920
        )

        #expect(
            MenuBarVisibilityPolicy.shouldRunVisibilityIntentEnforcement(
                reason: "healthy-validation-wake-resume-attempt-1",
                snapshot: protectedHiddenCached,
                hasVisibleAllowList: true,
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldRunVisibilityIntentEnforcement(
                reason: "healthy-validation-active-space-changed-attempt-1",
                snapshot: protectedHiddenCached,
                hasVisibleAllowList: true,
                hasPendingWakeVisibleAllowListReplay: true
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldRunVisibilityIntentEnforcement(
                reason: "healthy-validation-wake-resume-attempt-1",
                snapshot: protectedHiddenCached,
                hasVisibleAllowList: true,
                hasPendingWakeVisibleAllowListReplay: false
            )
        )

        let replay = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "healthy-validation-wake-resume-attempt-1",
            geometryConfidence: .cached,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: true,
            canRepairHiddenWakeVisibleAllowList: true
        )
        #expect(replay.mode == .repairWithPhysicalMoves)
        #expect(replay.physicalMoveOrigin == .systemWakeRecovery)

        let unrelatedReplay = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "healthy-validation-active-space-changed-attempt-1",
            geometryConfidence: .cached,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: true,
            canRepairHiddenWakeVisibleAllowList: true
        )
        #expect(unrelatedReplay.mode == .auditOnly)
        #expect(unrelatedReplay.physicalMoveOrigin == nil)

        let immediateWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "wake-resume-attempt-1",
            geometryConfidence: .cached,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: true,
            canRepairHiddenWakeVisibleAllowList: true
        )
        #expect(immediateWake.mode == .auditOnly)
        #expect(immediateWake.physicalMoveOrigin == nil)
    }

    @Test("Status item recreation can finish a pending wake visible allow-list repair")
    func statusItemRecreateWakeResumeCanRepairPendingVisibleAllowList() {
        let recreatedWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "status-item-recreate-wake-resume-attempt-1",
            geometryConfidence: .live,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: true
        )
        #expect(recreatedWake.mode == .repairWithPhysicalMoves)
        #expect(recreatedWake.physicalMoveOrigin == .systemWakeRecovery)

        let recreatedWakeWithoutPending = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "status-item-recreate-wake-resume-attempt-1",
            geometryConfidence: .live,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: false
        )
        #expect(recreatedWakeWithoutPending.mode == .auditOnly)
        #expect(recreatedWakeWithoutPending.physicalMoveOrigin == nil)

        let plainRecreate = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "status-item-recreate-attempt-1",
            geometryConfidence: .live,
            hidingState: .hidden,
            hasVisibleAllowList: true,
            hasPendingWakeVisibleAllowListReplay: true
        )
        #expect(plainRecreate.mode == .auditOnly)
        #expect(plainRecreate.physicalMoveOrigin == nil)
    }

    @Test("Pending wake visible allow-list replay preserves wake repair through screen-parameter validation")
    func pendingWakeVisibleAllowListReplayPreservesWakeReasonThroughScreenValidation() {
        let rewritten = MenuBarVisibilityPolicy.visibilityIntentReplayReason(
            reason: "healthy-validation-screen-parameters-changed",
            hasPendingWakeVisibleAllowListReplay: true
        )
        #expect(rewritten == "healthy-validation-wake-resume-healthy-validation-screen-parameters-changed")
        #expect(MenuBarVisibilityPolicy.isPostWakeVisibleAllowListReplayReason(rewritten))

        let attempted = MenuBarVisibilityPolicy.visibilityIntentReplayReason(
            reason: "healthy-validation-screen-parameters-changed-attempt-1",
            hasPendingWakeVisibleAllowListReplay: true
        )
        #expect(attempted == "healthy-validation-wake-resume-healthy-validation-screen-parameters-changed-attempt-1")
        #expect(MenuBarVisibilityPolicy.isPostWakeVisibleAllowListReplayReason(attempted))

        let plainScreenChange = MenuBarVisibilityPolicy.visibilityIntentReplayReason(
            reason: "healthy-validation-screen-parameters-changed",
            hasPendingWakeVisibleAllowListReplay: false
        )
        #expect(plainScreenChange == "healthy-validation-screen-parameters-changed")

        let activeSpace = MenuBarVisibilityPolicy.visibilityIntentReplayReason(
            reason: "healthy-validation-active-space-changed",
            hasPendingWakeVisibleAllowListReplay: true
        )
        #expect(activeSpace == "healthy-validation-active-space-changed")
    }

    @Test("Non-wake lifecycle healthy validation stays audit-only on live geometry")
    func nonWakeLifecycleHealthyValidationStaysAuditOnlyOnLiveGeometry() {
        let nonWakeReasons = [
            "healthy-validation-active-space-changed-attempt-1",
            "healthy-validation-screen-parameters-changed-attempt-1"
        ]

        for reason in nonWakeReasons {
            let replay = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: reason,
                geometryConfidence: .live,
                hidingState: .hidden,
                hasVisibleAllowList: true,
                hasPendingWakeVisibleAllowListReplay: true,
                canRepairHiddenWakeVisibleAllowList: true
            )
            #expect(replay.mode == .auditOnly)
            #expect(replay.physicalMoveOrigin == nil)
        }
    }

    @Test("Startup reconciliation uses physical moves only on live geometry")
    func startupReconciliationRequiresLiveGeometry() {
        let liveStartup = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "healthy-validation-startup-follow-up",
            geometryConfidence: .live,
            hidingState: .expanded
        )
        #expect(liveStartup.mode == .repairWithPhysicalMoves)
        #expect(liveStartup.physicalMoveOrigin == .systemWakeRecovery)

        for confidence in [MenuBarGeometryConfidence.cached, .shielded, .stale, .missing] {
            let degraded = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "healthy-validation-startup-follow-up",
                geometryConfidence: confidence,
                hidingState: .hidden
            )
            #expect(degraded.mode == .auditOnly)
            #expect(degraded.physicalMoveOrigin == nil)
        }

        let unrelatedReason = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "settings-change",
            geometryConfidence: .live,
            hidingState: .hidden
        )
        #expect(unrelatedReason.mode == .auditOnly)
    }
}
