import Foundation

struct MenuBarVisibilityFlapDetector {
    static let defaultFlapWindowSeconds: TimeInterval = 10
    static let defaultFlapTransitionThreshold = 4
    static let defaultDormancySeconds: TimeInterval = 300

    private(set) var transitionTimestamps: [Date] = []
    private var lastObservedHealthy: Bool?

    mutating func record(itemsHealthy: Bool, at date: Date) {
        defer { lastObservedHealthy = itemsHealthy }
        guard let lastObservedHealthy, lastObservedHealthy != itemsHealthy else { return }
        transitionTimestamps.append(date)
    }

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
