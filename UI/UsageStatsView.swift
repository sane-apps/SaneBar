import SwiftUI

// MARK: - UsageStatsView

/// Displays usage analytics for menu bar items
struct UsageStatsView: View {
    @ObservedObject var menuBarManager: MenuBarManager

    /// Items sorted by click count (most used first)
    private var sortedItems: [StatusItemModel] {
        menuBarManager.statusItems.sorted { $0.clickCount > $1.clickCount }
    }

    /// Total clicks across all items
    private var totalClicks: Int {
        menuBarManager.statusItems.reduce(0) { $0 + $1.clickCount }
    }

    /// Items with at least one click
    private var usedItems: [StatusItemModel] {
        sortedItems.filter { $0.clickCount > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary cards
                summarySection

                Divider()

                // Smart suggestions
                SuggestionsView(menuBarManager: menuBarManager)

                Divider()

                // Most used items
                if !usedItems.isEmpty {
                    mostUsedSection
                } else {
                    emptyState
                }
            }
            .padding()
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage Summary")
                .font(.headline)

            HStack(spacing: 20) {
                StatCard(
                    title: "Total Items",
                    value: "\(menuBarManager.statusItems.count)",
                    icon: "square.grid.2x2"
                )

                StatCard(
                    title: "Total Clicks",
                    value: "\(totalClicks)",
                    icon: "hand.tap"
                )

                StatCard(
                    title: "Items Used",
                    value: "\(usedItems.count)",
                    icon: "checkmark.circle"
                )
            }
        }
    }

    // MARK: - Most Used Section

    private var mostUsedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Used Items")
                .font(.headline)

            ForEach(usedItems.prefix(10)) { item in
                UsageItemRow(item: item, totalClicks: totalClicks)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No usage data yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Click on menu bar items to start tracking usage")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - UsageItemRow

private struct UsageItemRow: View {
    let item: StatusItemModel
    let totalClicks: Int
    private let iconService = IconService.shared

    /// Click percentage of total
    private var percentage: Double {
        guard totalClicks > 0 else { return 0 }
        return Double(item.clickCount) / Double(totalClicks) * 100
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let nsImage = iconService.icon(forBundleIdentifier: item.bundleIdentifier, size: 20) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.badge")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * (percentage / 100))
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.clickCount)")
                    .font(.headline)

                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Last used
            if let lastClick = item.lastClickDate {
                Text(lastClick, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    UsageStatsView(menuBarManager: MenuBarManager.shared)
        .frame(width: 500, height: 400)
}
