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
