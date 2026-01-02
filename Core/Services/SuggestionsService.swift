import Foundation

// MARK: - SuggestionType

/// Types of suggestions the service can make
enum SuggestionType: String, Codable {
    case hideItem       // Suggest hiding rarely-used item
    case showItem       // Suggest showing frequently-used item
    case moveToVisible  // Suggest moving to always-visible
    case moveToCollapsed // Suggest collapsing always-hidden
}

// MARK: - Suggestion

/// A suggestion for menu bar item organization
struct Suggestion: Identifiable {
    let id = UUID()
    let item: StatusItemModel
    let type: SuggestionType
    let reason: String
    let priority: Int // Higher = more important

    var title: String {
        switch type {
        case .hideItem:
            return "Hide \(item.displayName)"
        case .showItem:
            return "Show \(item.displayName)"
        case .moveToVisible:
            return "Keep \(item.displayName) visible"
        case .moveToCollapsed:
            return "Collapse \(item.displayName)"
        }
    }

    var systemImage: String {
        switch type {
        case .hideItem: return "eye.slash"
        case .showItem: return "eye"
        case .moveToVisible: return "star"
        case .moveToCollapsed: return "archivebox"
        }
    }
}

// MARK: - SuggestionsServiceProtocol

/// @mockable
protocol SuggestionsServiceProtocol: Sendable {
    func generateSuggestions(for items: [StatusItemModel]) -> [Suggestion]
}

// MARK: - SuggestionsService

/// Service for generating smart suggestions based on usage patterns
final class SuggestionsService: SuggestionsServiceProtocol, @unchecked Sendable {

    // MARK: - Singleton

    static let shared = SuggestionsService()

    // MARK: - Configuration

    /// Minimum days since last use to suggest hiding
    var daysSinceLastUseSuggestionThreshold: Int = 7

    /// Click count percentile below which to suggest hiding
    var lowUsagePercentile: Double = 0.25

    /// Click count percentile above which to suggest visibility
    var highUsagePercentile: Double = 0.75

    // MARK: - Initialization

    private init() {}

    // MARK: - Suggestion Generation

    /// Generate suggestions based on usage patterns
    func generateSuggestions(for items: [StatusItemModel]) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        let usedItems = items.filter { $0.clickCount > 0 }
        guard !usedItems.isEmpty else { return suggestions }

        // Calculate usage statistics
        let totalClicks = usedItems.reduce(0) { $0 + $1.clickCount }
        let clickCounts = usedItems.map { $0.clickCount }.sorted()
        let lowThreshold = percentile(clickCounts, percentile: lowUsagePercentile)
        let highThreshold = percentile(clickCounts, percentile: highUsagePercentile)

        for item in items {
            if let suggestion = analyzItem(
                item,
                totalClicks: totalClicks,
                lowThreshold: lowThreshold,
                highThreshold: highThreshold
            ) {
                suggestions.append(suggestion)
            }
        }

        // Sort by priority (highest first)
        return suggestions.sorted { $0.priority > $1.priority }
    }

    // MARK: - Item Analysis

    private func analyzItem(
        _ item: StatusItemModel,
        totalClicks: Int,
        lowThreshold: Int,
        highThreshold: Int
    ) -> Suggestion? {
        // Skip items with no analytics data
        guard item.clickCount > 0 || item.lastClickDate != nil || item.lastShownDate != nil else {
            return nil
        }

        // Check for rarely-used visible items
        if item.section == .alwaysVisible && item.clickCount < lowThreshold {
            return Suggestion(
                item: item,
                type: .hideItem,
                reason: "Rarely used (\(item.clickCount) clicks)",
                priority: 3
            )
        }

        // Check for frequently-used hidden items
        if item.section == .hidden && item.clickCount > highThreshold {
            return Suggestion(
                item: item,
                type: .moveToVisible,
                reason: "Frequently used (\(item.clickCount) clicks)",
                priority: 5
            )
        }

        // Check for stale items (not used in a while)
        if let lastClick = item.lastClickDate {
            let daysSinceLastClick = Calendar.current.dateComponents(
                [.day],
                from: lastClick,
                to: Date()
            ).day ?? 0

            if daysSinceLastClick >= daysSinceLastUseSuggestionThreshold {
                if item.section == .alwaysVisible {
                    return Suggestion(
                        item: item,
                        type: .hideItem,
                        reason: "Not used in \(daysSinceLastClick) days",
                        priority: 4
                    )
                }
            }
        }

        // Check for never-shown hidden items (suggest collapsing)
        if item.section == .hidden && item.lastShownDate == nil && item.clickCount == 0 {
            return Suggestion(
                item: item,
                type: .moveToCollapsed,
                reason: "Never accessed",
                priority: 2
            )
        }

        return nil
    }

    // MARK: - Helpers

    /// Calculate percentile value from sorted array
    private func percentile(_ sorted: [Int], percentile: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }

        let index = Int(Double(sorted.count - 1) * percentile)
        return sorted[min(index, sorted.count - 1)]
    }
}
