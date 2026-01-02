import Testing
import Foundation
@testable import SaneBar

// MARK: - SuggestionsService Tests

@Suite("SuggestionsService Tests")
struct SuggestionsServiceTests {

    // MARK: - Helper Methods

    /// Creates test items with enough spread to trigger percentile-based suggestions.
    /// With 5 used items [1, 10, 25, 50, 100], lowThreshold=10, highThreshold=50.
    /// - lowUsage (1) < lowThreshold (10) → suggest hide
    /// - hiddenHigh (100) > highThreshold (50) → suggest move to visible
    private func createTestItems() -> [StatusItemModel] {
        [
            // Very high usage visible item - establishes upper bound
            StatusItemModel(
                bundleIdentifier: "com.test.veryHigh",
                title: "Very High",
                position: 0,
                section: .alwaysVisible,
                clickCount: 100
            ),
            // High usage visible item
            StatusItemModel(
                bundleIdentifier: "com.test.highUsage",
                title: "High Usage",
                position: 1,
                section: .alwaysVisible,
                clickCount: 50
            ),
            // Medium usage visible item
            StatusItemModel(
                bundleIdentifier: "com.test.mediumUsage",
                title: "Medium Usage",
                position: 2,
                section: .alwaysVisible,
                clickCount: 25
            ),
            // Low-medium usage visible item
            StatusItemModel(
                bundleIdentifier: "com.test.lowMedium",
                title: "Low Medium",
                position: 3,
                section: .alwaysVisible,
                clickCount: 10
            ),
            // Low usage visible item (should suggest hiding: 1 < lowThreshold of 10)
            StatusItemModel(
                bundleIdentifier: "com.test.lowUsage",
                title: "Low Usage",
                position: 4,
                section: .alwaysVisible,
                clickCount: 1
            ),
            // Very high usage hidden item (should suggest showing: 100 > highThreshold of 50)
            StatusItemModel(
                bundleIdentifier: "com.test.hiddenHigh",
                title: "Hidden High",
                position: 5,
                section: .hidden,
                clickCount: 100
            ),
            // Never accessed hidden item (has lastShownDate for analytics, so not skipped)
            StatusItemModel(
                bundleIdentifier: "com.test.neverUsed",
                title: "Never Used",
                position: 6,
                section: .hidden,
                clickCount: 0,
                lastShownDate: Date().addingTimeInterval(-86400) // Shown yesterday but never clicked
            )
        ]
    }

    // MARK: - Basic Tests

    @Test("Service is singleton")
    func isSingleton() {
        let instance1 = SuggestionsService.shared
        let instance2 = SuggestionsService.shared
        #expect(instance1 === instance2)
    }

    @Test("Empty items returns no suggestions")
    func emptyItems() {
        let service = SuggestionsService.shared
        let suggestions = service.generateSuggestions(for: [])
        #expect(suggestions.isEmpty)
    }

    // MARK: - Suggestion Generation Tests

    @Test("Generates suggestions for test items")
    func generatesSuggestions() {
        let service = SuggestionsService.shared
        let items = createTestItems()
        let suggestions = service.generateSuggestions(for: items)

        // Should have at least one suggestion
        #expect(!suggestions.isEmpty)
    }

    @Test("Suggests hiding low-usage visible items")
    func suggestsHidingLowUsage() {
        let service = SuggestionsService.shared
        let items = createTestItems()
        let suggestions = service.generateSuggestions(for: items)

        let hideSuggestions = suggestions.filter { $0.type == .hideItem }
        #expect(!hideSuggestions.isEmpty)
    }

    @Test("Suggests showing high-usage hidden items")
    func suggestsShowingHighUsage() {
        let service = SuggestionsService.shared
        let items = createTestItems()
        let suggestions = service.generateSuggestions(for: items)

        let showSuggestions = suggestions.filter { $0.type == .moveToVisible }
        #expect(!showSuggestions.isEmpty)
    }

    @Test("Suggestions are sorted by priority")
    func sortedByPriority() {
        let service = SuggestionsService.shared
        let items = createTestItems()
        let suggestions = service.generateSuggestions(for: items)

        guard suggestions.count >= 2 else { return }

        for i in 0..<(suggestions.count - 1) {
            #expect(suggestions[i].priority >= suggestions[i + 1].priority)
        }
    }

    // MARK: - Suggestion Model Tests

    @Test("Suggestion title contains item name")
    func suggestionTitle() {
        let item = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "TestApp",
            position: 0,
            section: .alwaysVisible,
            clickCount: 1
        )

        let suggestion = Suggestion(
            item: item,
            type: .hideItem,
            reason: "Test",
            priority: 1
        )

        #expect(suggestion.title.contains("TestApp"))
    }

    @Test("Suggestion types have correct icons")
    func suggestionIcons() {
        let item = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "Test",
            position: 0
        )

        let hideItem = Suggestion(item: item, type: .hideItem, reason: "", priority: 1)
        let showItem = Suggestion(item: item, type: .showItem, reason: "", priority: 1)
        let moveToVisible = Suggestion(item: item, type: .moveToVisible, reason: "", priority: 1)
        let moveToCollapsed = Suggestion(item: item, type: .moveToCollapsed, reason: "", priority: 1)

        #expect(hideItem.systemImage == "eye.slash")
        #expect(showItem.systemImage == "eye")
        #expect(moveToVisible.systemImage == "star")
        #expect(moveToCollapsed.systemImage == "archivebox")
    }

    // MARK: - Configuration Tests

    @Test("Day threshold is configurable")
    func dayThresholdConfigurable() {
        let service = SuggestionsService.shared
        let original = service.daysSinceLastUseSuggestionThreshold

        service.daysSinceLastUseSuggestionThreshold = 14
        #expect(service.daysSinceLastUseSuggestionThreshold == 14)

        service.daysSinceLastUseSuggestionThreshold = original
    }

    @Test("Percentile thresholds are configurable")
    func percentileThresholdConfigurable() {
        let service = SuggestionsService.shared

        service.lowUsagePercentile = 0.10
        service.highUsagePercentile = 0.90

        #expect(service.lowUsagePercentile == 0.10)
        #expect(service.highUsagePercentile == 0.90)

        // Reset to defaults
        service.lowUsagePercentile = 0.25
        service.highUsagePercentile = 0.75
    }

    // MARK: - SuggestionType Tests

    @Test("SuggestionType is Codable")
    func suggestionTypeCodable() throws {
        let types: [SuggestionType] = [.hideItem, .showItem, .moveToVisible, .moveToCollapsed]

        for type in types {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(SuggestionType.self, from: encoded)
            #expect(decoded == type)
        }
    }
}
