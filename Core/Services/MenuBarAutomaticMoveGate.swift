import Foundation

final class MenuBarAutomaticMoveGate: @unchecked Sendable {
    static let maxAutomaticMovesPerWindow = 6
    static let maxAutomaticMovesPerArm = 24
    static let rateWindowSeconds: TimeInterval = 60
    static let defaultArmDurationSeconds: TimeInterval = 30

    private let lock = NSLock()
    private var armedUntil: Date?
    private var armedMoveBudget = maxAutomaticMovesPerWindow
    private var recentAutomaticMoves: [Date] = []

    nonisolated static func automaticMoveDecision(
        origin: MenuBarPhysicalMoveOrigin,
        armedUntil: Date?,
        recentAutomaticMoveCount: Int,
        moveBudget: Int = MenuBarAutomaticMoveGate.maxAutomaticMovesPerWindow,
        now: Date
    ) -> Bool {
        switch origin {
        case .explicitUserAction, .appleScriptUserAction:
            return true
        case .systemWakeRecovery:
            guard let armedUntil, now <= armedUntil else { return false }
            return recentAutomaticMoveCount < moveBudget
        }
    }

    nonisolated static func automaticMoveBudget(forCandidateItemCount candidateItemCount: Int) -> Int {
        let requestedBudget = max(maxAutomaticMovesPerWindow, candidateItemCount * 2)
        return min(requestedBudget, maxAutomaticMovesPerArm)
    }

    func arm(
        for duration: TimeInterval = MenuBarAutomaticMoveGate.defaultArmDurationSeconds,
        moveBudget: Int = MenuBarAutomaticMoveGate.maxAutomaticMovesPerWindow,
        now: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        armedUntil = now.addingTimeInterval(duration)
        armedMoveBudget = min(max(0, moveBudget), Self.maxAutomaticMovesPerArm)
        recentAutomaticMoves.removeAll(keepingCapacity: true)
    }

    func disarm() {
        lock.lock()
        defer { lock.unlock() }
        armedUntil = nil
        armedMoveBudget = Self.maxAutomaticMovesPerWindow
    }

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
                moveBudget: armedMoveBudget,
                now: now
            )
            return allowed
        }
    }

    func recordPostedMove(origin: MenuBarPhysicalMoveOrigin, now: Date = Date()) {
        guard origin == .systemWakeRecovery else { return }
        lock.lock()
        defer { lock.unlock() }
        recentAutomaticMoves.removeAll { now.timeIntervalSince($0) > Self.rateWindowSeconds }
        recentAutomaticMoves.append(now)
    }
}
