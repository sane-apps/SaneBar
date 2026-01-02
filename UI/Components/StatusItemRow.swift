import SwiftUI

// MARK: - StatusItemRow

/// A row displaying a single menu bar status item
struct StatusItemRow: View {
    let item: StatusItemModel
    var onSectionChange: ((StatusItemModel.ItemSection) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Icon placeholder
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)

                if let bundleId = item.bundleIdentifier {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Section indicator
            sectionBadge
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.isVisible ? Color.clear : Color.secondary.opacity(0.1))
        )
        .contextMenu {
            sectionMenu
        }
    }

    // MARK: - Subviews

    private var iconName: String {
        // Use different icons based on known bundle IDs
        switch item.bundleIdentifier {
        case "com.apple.controlcenter":
            return "switch.2"
        case "com.apple.Spotlight":
            return "magnifyingglass"
        case "com.apple.battery":
            return "battery.100"
        case "com.apple.wifi":
            return "wifi"
        case "com.apple.bluetooth":
            return "bluetooth"
        default:
            return "app.badge"
        }
    }

    private var sectionBadge: some View {
        Label(item.section.displayName, systemImage: item.section.systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch item.section {
        case .alwaysVisible: return .green
        case .hidden: return .orange
        case .collapsed: return .red
        }
    }

    @ViewBuilder
    private var sectionMenu: some View {
        ForEach(StatusItemModel.ItemSection.allCases, id: \.self) { section in
            Button {
                onSectionChange?(section)
            } label: {
                Label(section.displayName, systemImage: section.systemImage)
            }
            .disabled(item.section == section)
        }
    }
}

// MARK: - Preview

#Preview("Status Item Rows") {
    VStack(spacing: 8) {
        ForEach(StatusItemModel.sampleItems) { item in
            StatusItemRow(item: item)
        }
    }
    .padding()
    .frame(width: 350)
}

#Preview("Single Row") {
    StatusItemRow(
        item: StatusItemModel(
            bundleIdentifier: "com.example.app",
            title: "Example App",
            position: 0,
            section: .hidden
        )
    )
    .padding()
}
