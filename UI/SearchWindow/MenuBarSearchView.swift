import SwiftUI

// MARK: - MenuBarSearchView

/// Spotlight-style search for menu bar items
struct MenuBarSearchView: View {
    @ObservedObject var menuBarManager: MenuBarManager
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0

    private let iconService = IconService.shared

    /// Filtered items matching search
    private var filteredItems: [StatusItemModel] {
        if searchText.isEmpty {
            return menuBarManager.statusItems
        }
        return menuBarManager.statusItems.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Divider()

            // Results list
            if filteredItems.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: 400, height: 300)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredItems.isEmpty {
                selectItem(at: selectedIndex)
            }
            return .handled
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Search menu bar items...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit {
                    if !filteredItems.isEmpty {
                        selectItem(at: selectedIndex)
                    }
                }
        }
        .padding()
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        SearchResultRow(
                            item: item,
                            isSelected: index == selectedIndex,
                            iconService: iconService
                        )
                        .id(index)
                        .onTapGesture {
                            selectItem(at: index)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No matching items")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func selectItem(at index: Int) {
        guard index < filteredItems.count else { return }
        let item = filteredItems[index]

        // Show the item if it's hidden
        if item.section != .alwaysVisible {
            Task {
                try? await menuBarManager.hidingService.show()
            }
        }

        // Record click for analytics
        menuBarManager.recordItemClick(item)

        // Close the search window
        isPresented = false
    }
}

// MARK: - SearchResultRow

private struct SearchResultRow: View {
    let item: StatusItemModel
    let isSelected: Bool
    let iconService: IconService

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let nsImage = iconService.icon(forBundleIdentifier: item.bundleIdentifier, size: 24) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.badge")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)

                if let bundleId = item.bundleIdentifier {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Section indicator
            sectionBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var sectionBadge: some View {
        Text(item.section.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview

#Preview {
    MenuBarSearchView(
        menuBarManager: MenuBarManager.shared,
        isPresented: .constant(true)
    )
}
