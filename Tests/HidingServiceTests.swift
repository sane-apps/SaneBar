import Foundation
@testable import SaneBar
import Testing

// MARK: - Recording Mock (tracks length changes in order)

@MainActor
private class RecordingMockStatusItem: StatusItemProtocol {
    var length: CGFloat = 20.0 {
        didSet { lengthHistory.append(length) }
    }

    var lengthHistory: [CGFloat] = []
}

// MARK: - HidingServiceTests

@Suite("HidingService Tests")
struct HidingServiceTests {
    // MARK: - State Tests

    @Test("Initial state is expanded for safe position validation")
    @MainActor
    func initialStateIsExpanded() {
        let service = HidingService()

        // Start expanded to allow position validation before hiding
        // MenuBarManager will hide after validating separator is in correct position
        #expect(service.state == .expanded,
                "Should start in expanded state for safe position validation")
    }

    @Test("HidingState enum cases are correct")
    func hidingStateEnumCases() {
        // Verify the enum values exist and can be compared
        let hidden = HidingState.hidden
        let expanded = HidingState.expanded

        #expect(hidden == .hidden,
                "Hidden state should equal .hidden")
        #expect(expanded == .expanded,
                "Expanded state should equal .expanded")
        #expect(hidden != expanded,
                "States should not be equal")
    }

    // MARK: - Rehide Tests

    @Test("Schedule rehide can be cancelled")
    @MainActor
    func scheduleRehideCanBeCancelled() async throws {
        let service = HidingService()

        // Note: Without a real NSStatusItem, show() will return early
        // This tests the cancel logic in isolation
        service.scheduleRehide(after: 1.0)
        service.cancelRehide()

        // Should not crash
        #expect(true, "Should cancel rehide without error")
    }

    @Test("Cancel rehide is no-op when nothing scheduled")
    @MainActor
    func cancelRehideWhenNothingScheduled() {
        let service = HidingService()

        // Should not crash when no rehide is scheduled
        service.cancelRehide()

        #expect(service.state == .expanded,
                "State should remain unchanged")
    }

    // MARK: - Nil Delimiter Tests (Crash Prevention)

    @Test("Toggle with nil delimiter does not crash")
    @MainActor
    func toggleWithNilDelimiterDoesNotCrash() async {
        let service = HidingService()
        // Deliberately NOT calling configure() - delimiterItem is nil

        // Should return early without crashing
        await service.toggle()

        #expect(service.state == .expanded,
                "State should remain expanded when delimiter is nil")
    }

    @Test("Show with nil delimiter does not crash")
    @MainActor
    func showWithNilDelimiterDoesNotCrash() async {
        let service = HidingService()
        // Deliberately NOT calling configure() - delimiterItem is nil

        // Should return early (no delimiter) - state stays expanded
        await service.show()

        #expect(service.state == .expanded,
                "State should remain expanded when show fails gracefully")
    }

    @Test("Hide with nil delimiter does not crash")
    @MainActor
    func hideWithNilDelimiterDoesNotCrash() async {
        let service = HidingService()
        // Deliberately NOT calling configure() - delimiterItem is nil

        // Should return early without crashing
        await service.hide()

        #expect(service.state == .expanded,
                "State should remain expanded when hide fails gracefully")
    }
}

// MARK: - Always-Hidden Regression Tests

// Root cause: AH separator seeded at position 200, which placed it in the middle
// of real menu bar items (WiFi:299, Bluetooth:405, Siri:437). Items to AH's left
// got pushed off-screen during show(). Fix: seed at 10000.

@Suite("Always-Hidden Section Regression Tests")
struct AlwaysHiddenRegressionTests {
    // MARK: - Configure

    @Test("configureAlwaysHiddenDelimiter starts at visual length")
    @MainActor
    func ahDelimiterStartsAtVisualLength() {
        let service = HidingService()
        let ahItem = RecordingMockStatusItem()

        service.configureAlwaysHiddenDelimiter(ahItem)

        #expect(ahItem.length == 14,
                "AH delimiter must start at visual length (14), not collapsed")
    }

    @Test("configureAlwaysHiddenDelimiter can be cleared with nil")
    @MainActor
    func ahDelimiterCanBeCleared() {
        let service = HidingService()
        let ahItem = RecordingMockStatusItem()

        service.configureAlwaysHiddenDelimiter(ahItem)
        service.configureAlwaysHiddenDelimiter(nil)

        // Should not crash, AH item was cleared
        #expect(ahItem.length == 14, "AH length unchanged after clearing")
    }

    // MARK: - Hide/Show Cycle with AH

    @Test("hide() restores AH to visual length")
    @MainActor
    func hideRestoresAHToVisualLength() async {
        let service = HidingService()
        let mainItem = RecordingMockStatusItem()
        let ahItem = RecordingMockStatusItem()

        service.configure(delimiterItem: mainItem)
        service.configureAlwaysHiddenDelimiter(ahItem)

        await service.hide()

        #expect(service.state == .hidden)
        #expect(mainItem.length == 10000,
                "Main delimiter must be collapsed (10000) when hidden")
        #expect(ahItem.length == 14,
                "AH must be at visual length (14) when hidden — main already shields everything")
    }

    @Test("show() sets AH to collapsed BEFORE revealing main")
    @MainActor
    func showSetsAHCollapsedBeforeMain() async {
        let service = HidingService()
        let mainItem = RecordingMockStatusItem()
        let ahItem = RecordingMockStatusItem()

        service.configure(delimiterItem: mainItem)
        service.configureAlwaysHiddenDelimiter(ahItem)

        // Get to hidden state first
        await service.hide()
        mainItem.lengthHistory.removeAll()
        ahItem.lengthHistory.removeAll()

        // Now show — the critical transition
        await service.show()

        #expect(service.state == .expanded)
        #expect(mainItem.length == 20,
                "Main must be expanded (20) after show")
        #expect(ahItem.length == 10000,
                "AH must be collapsed (10000) during show to block always-hidden items")

        // Verify ORDER: AH must go to 10000 BEFORE main goes to 20
        // This prevents always-hidden items from briefly appearing
        #expect(ahItem.lengthHistory.first == 10000,
                "AH must expand to 10000 first (shield always-hidden items)")
        #expect(mainItem.lengthHistory.first == 20,
                "Main contracts to 20 second (reveal hidden items)")
    }

    @Test("Full hide→show→hide cycle maintains correct AH lengths")
    @MainActor
    func fullCycleMaintainsAHLengths() async {
        let service = HidingService()
        let mainItem = RecordingMockStatusItem()
        let ahItem = RecordingMockStatusItem()

        service.configure(delimiterItem: mainItem)
        service.configureAlwaysHiddenDelimiter(ahItem)

        // Cycle 1: hide
        await service.hide()
        #expect(ahItem.length == 14, "AH visual after hide")
        #expect(mainItem.length == 10000, "Main collapsed after hide")

        // Cycle 1: show
        await service.show()
        #expect(ahItem.length == 10000, "AH blocks during show")
        #expect(mainItem.length == 20, "Main expanded after show")

        // Cycle 2: hide again
        await service.hide()
        #expect(ahItem.length == 14, "AH visual after second hide")
        #expect(mainItem.length == 10000, "Main collapsed after second hide")

        // Cycle 2: show again
        await service.show()
        #expect(ahItem.length == 10000, "AH blocks during second show")
        #expect(mainItem.length == 20, "Main expanded after second show")
    }

    // MARK: - ShowAll / RestoreFromShowAll (Shield Pattern)

    @Test("showAll() uses shield pattern: main→10000, AH→14, main→20")
    @MainActor
    func showAllUsesShieldPattern() async {
        let service = HidingService()
        let mainItem = RecordingMockStatusItem()
        let ahItem = RecordingMockStatusItem()

        service.configure(delimiterItem: mainItem)
        service.configureAlwaysHiddenDelimiter(ahItem)

        // Start hidden
        await service.hide()
        mainItem.lengthHistory.removeAll()
        ahItem.lengthHistory.removeAll()

        await service.showAll()

        #expect(service.state == .expanded)
        #expect(ahItem.length == 14,
                "AH at visual length after showAll — everything is revealed")
        #expect(mainItem.length == 20,
                "Main expanded after showAll")

        // Verify shield sequence: main went to 10000 first
        #expect(mainItem.lengthHistory.contains(10000),
                "Main must shield (10000) before AH contracts")
    }

    @Test("restoreFromShowAll() re-blocks AH using shield pattern")
    @MainActor
    func restoreFromShowAllReBlocksAH() async {
        let service = HidingService()
        let mainItem = RecordingMockStatusItem()
        let ahItem = RecordingMockStatusItem()

        service.configure(delimiterItem: mainItem)
        service.configureAlwaysHiddenDelimiter(ahItem)

        // Get to showAll state
        await service.hide()
        await service.showAll()
        mainItem.lengthHistory.removeAll()
        ahItem.lengthHistory.removeAll()

        await service.restoreFromShowAll()

        #expect(service.state == .expanded)
        #expect(ahItem.length == 10000,
                "AH must be re-blocked (10000) after restoreFromShowAll")
        #expect(mainItem.length == 20,
                "Main expanded after restoreFromShowAll")

        // Verify shield: main→10000 happened before AH→10000
        #expect(mainItem.lengthHistory.contains(10000),
                "Main must shield before AH re-blocks")
    }

    // MARK: - Position Seed Regression

    @Test("AH separator position seed must be 10000, not 200")
    @MainActor
    func ahPositionSeedIs10000() {
        // Regression: Position 200 placed AH in the middle of real menu bar items
        // (WiFi:299, Bluetooth:405, Siri:437), causing them to be pushed off-screen
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"

        // Clear any existing value to trigger fresh seed
        defaults.removeObject(forKey: key)

        // Trigger seeding
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()

        let position = defaults.double(forKey: key)
        #expect(position == 10000,
                "AH position must be 10000 (far left), not 200. 200 places AH in the middle of system items.")

        // Cleanup
        defaults.removeObject(forKey: key)
    }

    @Test("AH seed enforces 10000 even when key already exists")
    @MainActor
    func ahSeedEnforcesLatestValue() {
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"

        // Existing value should be overwritten by seeding so startup self-heals
        // from stale/corrupted values left by prior cmd-drag experiments.
        defaults.set(5000.0, forKey: key)
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
        #expect(defaults.double(forKey: key) == 10000,
                "Seed must enforce 10000 to recover from stale positions")

        // Cleanup
        defaults.removeObject(forKey: key)
    }

    @Test("AH seed writes 10000 when key is nil")
    @MainActor
    func ahSeedWrites10000WhenNil() {
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"

        // Clear so seed triggers
        defaults.removeObject(forKey: key)
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
        #expect(defaults.double(forKey: key) == 10000,
                "AH position must seed as 10000 (far left)")

        // Cleanup
        defaults.removeObject(forKey: key)
    }

    @Test("Toggle off clears AH position for clean re-seed")
    @MainActor
    func toggleOffClearsPosition() {
        // Simulates what ensureAlwaysHiddenSeparator(enabled: false) does:
        // removing the position key so re-enable seeds cleanly.
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"

        // Simulate: AH was enabled, macOS assigned pixel position
        defaults.set(549.0, forKey: key)

        // Simulate toggle off: position cleared
        defaults.removeObject(forKey: key)

        // Simulate toggle on: should reseed as 10000
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
        #expect(defaults.double(forKey: key) == 10000,
                "After toggle off+on, AH must reseed as 10000")

        // Cleanup
        defaults.removeObject(forKey: key)
    }
}
