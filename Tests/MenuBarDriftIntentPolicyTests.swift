import CoreGraphics
@testable import SaneBar
import Testing

struct MenuBarDriftIntentPolicyTests {
    @Test("Hard invariant violation always triggers recovery")
    func hardInvariantAlwaysTriggers() {
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: 1612,
            mainX: 1576,
            mainRightGap: 948,
            screenWidth: 2560,
            persistedMainDistanceFromRight: 180
        ))
    }

    @Test("Live position matching persisted intent is healthy even far from Control Center")
    func intentMatchedWideLayoutIsHealthy() {
        // User keeps icons right of the SaneBar toggle: 600pt gap is intentional
        // (persisted intent agrees), so no recovery fires.
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: 1900,
            mainX: 1960,
            mainRightGap: 600,
            screenWidth: 2560,
            persistedMainDistanceFromRight: 580
        ) == false)
    }

    @Test("Large deviation from persisted intent triggers recovery")
    func intentDeviationTriggers() {
        // The #136 signature: persisted intent near Control Center (180pt) but
        // the live toggle drifted 948pt from the right edge.
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: 1576,
            mainX: 1612,
            mainRightGap: 948,
            screenWidth: 2560,
            persistedMainDistanceFromRight: 180
        ))
    }

    @Test("Falls back to absolute zone checks when persisted intent is unknown")
    func absoluteFallbackWithoutIntent() {
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: 1576,
            mainX: 1612,
            mainRightGap: 948,
            screenWidth: 2560,
            persistedMainDistanceFromRight: nil
        ))
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: 2300,
            mainX: 2380,
            mainRightGap: 180,
            screenWidth: 2560,
            persistedMainDistanceFromRight: nil
        ) == false)
    }

    @Test("Ordinal-like persisted values do not suppress absolute checks")
    func ordinalPersistedValueFallsBack() {
        // A 10000 ordinal seed is not pixel-like; the policy must fall back to
        // absolute checks rather than comparing against it.
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: 1576,
            mainX: 1612,
            mainRightGap: 948,
            screenWidth: 2560,
            persistedMainDistanceFromRight: 10000
        ))
    }

    @Test("Negative-X coordinates on left-arranged displays are evaluated, not ignored")
    func negativeCoordinatesEvaluated() {
        // Hard invariant violation expressed in negative global coordinates.
        #expect(MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: -1100,
            mainX: -1140,
            mainRightGap: 500,
            screenWidth: 2560,
            persistedMainDistanceFromRight: 180
        ))
    }
}
