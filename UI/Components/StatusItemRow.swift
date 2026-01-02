import SwiftUI

// MARK: - StatusItemRow

/// A row displaying a single menu bar status item
struct StatusItemRow: View {
    let item: StatusItemModel
    var onSectionChange: ((StatusItemModel.ItemSection) -> Void)?

    private let iconService = IconService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Real app icon or fallback
            appIcon
                .frame(width: 24, height: 24)

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

            // Section controls - visible buttons for discoverability
            sectionControls
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

    @ViewBuilder
    private var appIcon: some View {
        if let bundleId = item.bundleIdentifier,
           let nsImage = iconService.icon(forBundleIdentifier: bundleId, size: 24) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to SF Symbol based on known bundle IDs
            Image(systemName: fallbackIconName)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var fallbackIconName: String {
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

    /// Segmented control for section selection - clear text labels instead of confusing icons
    private var sectionControls: some View {
        Picker("Section", selection: sectionBinding) {
            Text("Show").tag(StatusItemModel.ItemSection.alwaysVisible)
            Text("Hide").tag(StatusItemModel.ItemSection.hidden)
            Text("Bury").tag(StatusItemModel.ItemSection.collapsed)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
    }

    /// Binding that bridges the item's section to the onSectionChange callback
    private var sectionBinding: Binding<StatusItemModel.ItemSection> {
        Binding(
            get: { item.section },
            set: { newSection in
                onSectionChange?(newSection)
            }
        )
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
