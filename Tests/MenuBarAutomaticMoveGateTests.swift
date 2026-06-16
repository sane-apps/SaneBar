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

    @Test("Gate instance arms, counts, and disarms")
    func gateInstanceLifecycle() {
        let gate = MenuBarAutomaticMoveGate()
        let now = Date(timeIntervalSinceReferenceDate: 1000)

        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now) == false)

        gate.arm(for: 30, now: now)
        for i in 0 ..< MenuBarAutomaticMoveGate.maxAutomaticMovesPerWindow {
            #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(Double(i))))
        }
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(8)) == false)

        gate.disarm()
        #expect(gate.allowsMove(origin: .systemWakeRecovery, now: now.addingTimeInterval(9)) == false)
        #expect(gate.allowsMove(origin: .explicitUserAction, now: now.addingTimeInterval(9)))
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

    @Test("Startup reconciliation uses physical moves only on trustworthy geometry")
    func startupReconciliationRequiresTrustworthyGeometry() {
        // Live and provenance-pure cached geometry allow physical restoration
        // of standing intent right after launch.
        for confidence in [MenuBarGeometryConfidence.live, .cached] {
            let startup = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "healthy-validation-startup-follow-up",
                geometryConfidence: confidence,
                hidingState: .expanded
            )
            #expect(startup.mode == .repairWithPhysicalMoves)
            #expect(startup.physicalMoveOrigin == .systemWakeRecovery)
        }

        for confidence in [MenuBarGeometryConfidence.shielded, .stale, .missing] {
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
