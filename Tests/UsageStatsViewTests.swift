import Testing
import Foundation
@testable import SaneBar

// MARK: - UsageStatsView Logic Tests

@Suite("UsageStatsView Logic Tests")
struct UsageStatsViewLogicTests {

    private func createTestItems() -> [StatusItemModel] {
        [
            StatusItemModel(
                bundleIdentifier: "com.test.app1",
                title: "App 1",
                position: 0,
                section: .alwaysVisible,
                clickCount: 10
            ),
            StatusItemModel(
                bundleIdentifier: "com.test.app2",
                title: "App 2",
                position: 1,
                section: .hidden,
                clickCount: 5
            ),
            StatusItemModel(
                bundleIdentifier: "com.test.app3",
                title: "App 3",
                position: 2,
                section: .collapsed,
                clickCount: 0
            )
        ]
    }

    @Test("Sort by click count descending")
    func sortByClickCount() {
        let items = createTestItems()
        let sorted = items.sorted { $0.clickCount > $1.clickCount }

        #expect(sorted.first?.clickCount == 10)
        #expect(sorted.last?.clickCount == 0)
    }

    @Test("Total clicks is sum of all items")
    func totalClicks() {
        let items = createTestItems()
        let total = items.reduce(0) { $0 + $1.clickCount }

        #expect(total == 15)
    }

    @Test("Used items filter excludes zero-click items")
    func usedItemsFilter() {
        let items = createTestItems()
        let used = items.filter { $0.clickCount > 0 }

        #expect(used.count == 2)
    }

    @Test("Empty items returns zero total")
    func emptyItemsZeroTotal() {
        let items: [StatusItemModel] = []
        let total = items.reduce(0) { $0 + $1.clickCount }

        #expect(total == 0)
    }

    @Test("Percentage calculation")
    func percentageCalculation() {
        let items = createTestItems()
        let totalClicks = items.reduce(0) { $0 + $1.clickCount }
        let item = items.first!

        let percentage = Double(item.clickCount) / Double(totalClicks) * 100

        #expect(percentage > 66.0)
        #expect(percentage < 67.0)
    }

    @Test("Zero total prevents division by zero")
    func zeroDivisionPrevention() {
        let items: [StatusItemModel] = []
        let totalClicks = items.reduce(0) { $0 + $1.clickCount }

        let percentage: Double
        if totalClicks > 0 {
            percentage = 100.0 / Double(totalClicks) * 100
        } else {
            percentage = 0
        }

        #expect(percentage == 0)
    }
}

// MARK: - Click Tracking Tests

@Suite("Click Tracking Tests")
struct ClickTrackingTests {

    @Test("Click count increments")
    func clickCountIncrements() {
        var item = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "Test",
            position: 0
        )

        #expect(item.clickCount == 0)

        item.clickCount += 1
        #expect(item.clickCount == 1)

        item.clickCount += 1
        #expect(item.clickCount == 2)
    }

    @Test("Last click date is set")
    func lastClickDateSet() {
        var item = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "Test",
            position: 0
        )

        #expect(item.lastClickDate == nil)

        let now = Date()
        item.lastClickDate = now

        #expect(item.lastClickDate == now)
    }

    @Test("Analytics data persists through coding")
    func analyticsDataPersists() throws {
        var item = StatusItemModel(
            bundleIdentifier: "com.test.app",
            title: "Test",
            position: 0,
            clickCount: 42
        )
        item.lastClickDate = Date()

        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(StatusItemModel.self, from: encoded)

        #expect(decoded.clickCount == 42)
        #expect(decoded.lastClickDate != nil)
    }
}
