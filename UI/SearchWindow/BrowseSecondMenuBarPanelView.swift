import SwiftUI

struct BrowseSecondMenuBarPanelView: View {
    let visibleApps: [RunningApp]
    let hiddenApps: [RunningApp]
    let alwaysHiddenApps: [RunningApp]
    let searchText: String
    let hasAccessibility: Bool
    let isRefreshing: Bool
    let onDismiss: () -> Void
    let onActivate: (RunningApp, Bool) -> Void
    let onRetry: () -> Void
    @Binding var searchTextBinding: String

    var body: some View {
        SecondMenuBarView(
            visibleApps: filteredVisible,
            apps: filteredHidden,
            alwaysHiddenApps: filteredAlwaysHidden,
            hasAccessibility: hasAccessibility,
            isRefreshing: isRefreshing,
            onDismiss: onDismiss,
            onActivate: onActivate,
            onRetry: onRetry,
            // Moves already emit .menuBarIconsDidChange after cache invalidation.
            // Avoid a second forced refresh path here to reduce scan latency/races.
            onIconMoved: nil,
            searchText: $searchTextBinding
        )
    }

    private var filteredVisible: [RunningApp] {
        guard !searchText.isEmpty else { return visibleApps }
        return visibleApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredAlwaysHidden: [RunningApp] {
        guard !searchText.isEmpty else { return alwaysHiddenApps }
        return alwaysHiddenApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredHidden: [RunningApp] {
        hiddenApps
    }
}
