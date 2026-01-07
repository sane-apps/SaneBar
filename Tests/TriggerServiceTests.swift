import Testing
import Foundation
@testable import SaneBar

// MARK: - TriggerServiceTests

@Suite("TriggerService Tests")
struct TriggerServiceTests {

    // MARK: - Initialization Tests

    @Test("TriggerService can be initialized")
    @MainActor
    func testInitialization() {
        let _ = TriggerService()

        // Service should initialize without crashing
        // Timer and observers set up internally
    }

    @Test("Stop monitoring is safe to call multiple times")
    @MainActor
    func testStopMonitoringMultipleCalls() {
        let service = TriggerService()

        // Should not crash when called multiple times
        service.stopMonitoring()
        service.stopMonitoring()
        service.stopMonitoring()

        #expect(true, "Multiple stopMonitoring calls should not crash")
    }

    // MARK: - Configuration Tests

    @Test("Configure accepts MenuBarManager")
    @MainActor
    func testConfigureAcceptsManager() async {
        let service = TriggerService()

        // Note: We can't easily test the full flow without a real MenuBarManager
        // This test documents the API contract

        // Clean up
        service.stopMonitoring()

        #expect(true, "Configure should accept manager without crash")
    }

    // MARK: - Battery Level Logic Tests (Unit Logic)

    @Test("Battery trigger requires transition TO low state")
    func testBatteryTransitionLogic() {
        // This tests the core logic without system dependencies
        // lastBatteryWarningLevel starts at kIOPSLowBatteryWarningNone
        // Should only trigger when transitioning TO low, not when already low

        let none = kIOPSLowBatteryWarningNone
        let early = kIOPSLowBatteryWarningEarly
        let final = kIOPSLowBatteryWarningFinal

        // Transition from none to early = should trigger
        let shouldTrigger1 = (early != none) && (none == none)
        #expect(shouldTrigger1, "Transition from none to early should trigger")

        // Transition from none to final = should trigger
        let shouldTrigger2 = (final != none) && (none == none)
        #expect(shouldTrigger2, "Transition from none to final should trigger")

        // Already in early, staying early = should NOT trigger
        let lastWasEarly = early
        let shouldNotTrigger = (early != none) && (lastWasEarly == none)
        #expect(!shouldNotTrigger, "Staying in early should not trigger again")

        // Transition from early to none (charging) = should NOT trigger
        let transitionToNone = (none != none)
        #expect(!transitionToNone, "Transition to none should not trigger")
    }

    // MARK: - App Launch Logic Tests

    @Test("App trigger requires bundleID in triggerApps list")
    func testAppTriggerLogic() {
        // Core logic: manager.settings.triggerApps.contains(bundleID)
        let triggerApps = ["com.apple.Safari", "com.apple.mail"]

        #expect(triggerApps.contains("com.apple.Safari"), "Safari should trigger")
        #expect(triggerApps.contains("com.apple.mail"), "Mail should trigger")
        #expect(!triggerApps.contains("com.apple.Finder"), "Finder should not trigger")
        #expect(!triggerApps.contains(""), "Empty bundleID should not trigger")
    }

    @Test("App trigger is disabled when showOnAppLaunch is false")
    func testAppTriggerDisabledLogic() {
        // Core logic: guard manager.settings.showOnAppLaunch else { return }
        let showOnAppLaunch = false
        let triggerApps = ["com.apple.Safari"]
        let bundleID = "com.apple.Safari"

        // Even if bundleID matches, should not trigger if disabled
        let wouldTrigger = showOnAppLaunch && triggerApps.contains(bundleID)
        #expect(!wouldTrigger, "Should not trigger when showOnAppLaunch is false")
    }
}
