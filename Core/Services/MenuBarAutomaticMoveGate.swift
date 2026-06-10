import Foundation

/// Consent gate for synthetic Cmd+drag input.
///
/// User-initiated moves (explicit UI action, AppleScript command the user ran)
/// always pass. Automatic replay moves (`.systemWakeRecovery`) only pass while
/// the MainActor side has armed the gate after confirming live geometry, and
/// are rate-limited. Replay drags fired on stale geometry are how users saw
/// their cursor "hijacked" and items moved they never asked to move (#151,
/// #154); this gate makes that class structurally impossible.
final class MenuBarAutomaticMoveGate: @unchecked Sendable {
    static let maxAutomaticMovesPerWindow = 6
    static let rateWindowSeconds: TimeInterval = 60
    static let defaultArmDurationSeconds: TimeInterval = 30

    private let lock = NSLock()
    private var armedUntil: Date?
    private var recentAutomaticMoves: [Date] = []

    /// Pure decision core, testable without time or locking.
    nonisolated static func automaticMoveDecision(
        origin: MenuBarPhysicalMoveOrigin,
        armedUntil: Date?,
        recentAutomaticMoveCount: Int,
        now: Date
    ) -> Bool {
        switch origin {
        case .explicitUserAction, .appleScriptUserAction:
            return true
        case .systemWakeRecovery:
            guard let armedUntil, now <= armedUntil else { return false }
            return recentAutomaticMoveCount < maxAutomaticMovesPerWindow
        }
    }

    /// Arm automatic moves for a bounded window. Callers must only arm after
    /// confirming the runtime snapshot reports live geometry.
    func arm(for duration: TimeInterval = MenuBarAutomaticMoveGate.defaultArmDurationSeconds, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        armedUntil = now.addingTimeInterval(duration)
    }

    func disarm() {
        lock.lock()
        defer { lock.unlock() }
        armedUntil = nil
    }

    /// Returns true when a physical move with this origin may proceed.
    /// Counts allowed automatic moves against the rate window.
    func allowsMove(origin: MenuBarPhysicalMoveOrigin, now: Date = Date()) -> Bool {
        switch origin {
        case .explicitUserAction, .appleScriptUserAction:
            return true
        case .systemWakeRecovery:
            lock.lock()
            defer { lock.unlock() }
            recentAutomaticMoves.removeAll { now.timeIntervalSince($0) > Self.rateWindowSeconds }
            let allowed = Self.automaticMoveDecision(
                origin: origin,
                armedUntil: armedUntil,
                recentAutomaticMoveCount: recentAutomaticMoves.count,
                now: now
            )
            if allowed {
                recentAutomaticMoves.append(now)
            }
            return allowed
        }
    }
}
