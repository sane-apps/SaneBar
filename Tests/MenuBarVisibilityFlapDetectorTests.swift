import Foundation
@testable import SaneBar
import Testing

struct MenuBarVisibilityFlapDetectorTests {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test("Stable health never reports flapping")
    func stableHealthNeverFlaps() {
        var detector = MenuBarVisibilityFlapDetector()
        for i in 0 ..< 20 {
            detector.record(itemsHealthy: true, at: date(Double(i)))
        }
        #expect(detector.isFlapping(now: date(20)) == false)
    }

    @Test("A single recovery transition does not report flapping")
    func singleTransitionDoesNotFlap() {
        var detector = MenuBarVisibilityFlapDetector()
        detector.record(itemsHealthy: false, at: date(0))
        detector.record(itemsHealthy: false, at: date(1))
        detector.record(itemsHealthy: true, at: date(2))
        detector.record(itemsHealthy: true, at: date(3))
        #expect(detector.isFlapping(now: date(3)) == false)
    }

    @Test("Rapid health alternation reports flapping")
    func rapidAlternationFlaps() {
        var detector = MenuBarVisibilityFlapDetector()
        // The Tahoe signature: OS flips item health every ~0.5s.
        var healthy = true
        for i in 0 ..< 6 {
            detector.record(itemsHealthy: healthy, at: date(Double(i) * 0.5))
            healthy.toggle()
        }
        #expect(detector.isFlapping(now: date(3)))
    }

    @Test("Old transitions age out of the flap window")
    func transitionsAgeOut() {
        var detector = MenuBarVisibilityFlapDetector()
        var healthy = true
        for i in 0 ..< 6 {
            detector.record(itemsHealthy: healthy, at: date(Double(i) * 0.5))
            healthy.toggle()
        }
        #expect(detector.isFlapping(now: date(60)) == false)
    }

    @Test("Reset clears flap history")
    func resetClearsHistory() {
        var detector = MenuBarVisibilityFlapDetector()
        var healthy = true
        for i in 0 ..< 6 {
            detector.record(itemsHealthy: healthy, at: date(Double(i) * 0.5))
            healthy.toggle()
        }
        #expect(detector.isFlapping(now: date(3)))
        detector.reset()
        #expect(detector.isFlapping(now: date(3)) == false)
    }
}
