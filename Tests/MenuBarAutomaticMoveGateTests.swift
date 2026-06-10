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

    @Test("Replay mode requires live geometry for physical moves")
    func replayModeRequiresLiveGeometry() {
        let live = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "wake-resume-attempt-1",
            geometryConfidence: .live
        )
        #expect(live.mode == .repairWithPhysicalMoves)
        #expect(live.physicalMoveOrigin == .systemWakeRecovery)

        for confidence in [MenuBarGeometryConfidence.cached, .shielded, .stale, .missing] {
            let degraded = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
                reason: "wake-resume-attempt-1",
                geometryConfidence: confidence
            )
            #expect(degraded.mode == .auditOnly)
            #expect(degraded.physicalMoveOrigin == nil)
        }

        let nonWake = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: "healthy-validation-startup-follow-up",
            geometryConfidence: .live
        )
        #expect(nonWake.mode == .auditOnly)
    }
}
