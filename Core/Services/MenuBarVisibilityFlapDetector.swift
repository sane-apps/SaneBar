import Foundation

/// Detects macOS flapping our status items between healthy and unhealthy.
///
/// On macOS 26 the system itself can repeatedly toggle status-item visibility
/// (cf. the NSStatusItemChangeVisibilityAction loop reported against other
/// menu bar apps). Fighting that loop with recreate/reset recovery churns
/// autosave state and never wins; the correct response is to go dormant and
/// point the user at System Settings.
struct MenuBarVisibilityFlapDetector {
    static let defaultFlapWindowSeconds: TimeInterval = 10
    static let defaultFlapTransitionThreshold = 4
    static let defaultDormancySeconds: TimeInterval = 300

    private(set) var transitionTimestamps: [Date] = []
    private var lastObservedHealthy: Bool?

    /// Record one observation of structural item health.
    mutating func record(itemsHealthy: Bool, at date: Date) {
        defer { lastObservedHealthy = itemsHealthy }
        guard let lastObservedHealthy, lastObservedHealthy != itemsHealthy else { return }
        transitionTimestamps.append(date)
    }

    /// True when health flipped at least `threshold` times inside `window`.
    func isFlapping(
        now: Date,
        window: TimeInterval = MenuBarVisibilityFlapDetector.defaultFlapWindowSeconds,
        threshold: Int = MenuBarVisibilityFlapDetector.defaultFlapTransitionThreshold
    ) -> Bool {
        let recent = transitionTimestamps.filter { now.timeIntervalSince($0) <= window }
        return recent.count >= threshold
    }

    mutating func reset() {
        transitionTimestamps.removeAll()
        lastObservedHealthy = nil
    }
}
