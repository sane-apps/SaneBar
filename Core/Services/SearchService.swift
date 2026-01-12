import AppKit
import Foundation

// MARK: - SearchServiceProtocol

/// @mockable
protocol SearchServiceProtocol: Sendable {
    /// Fetch all running apps suitable for menu bar interaction
    func getRunningApps() async -> [RunningApp]

    /// Fetch apps that currently own a menu bar icon (requires Accessibility permission)
    func getMenuBarApps() async -> [RunningApp]

    /// Fetch ONLY the menu bar apps that are currently HIDDEN by SaneBar
    func getHiddenMenuBarApps() async -> [RunningApp]

    /// Cached menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedMenuBarApps() -> [RunningApp]

    /// Cached hidden menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedHiddenMenuBarApps() -> [RunningApp]

    /// Cached shown (visible) menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedVisibleMenuBarApps() -> [RunningApp]

    /// Refresh menu bar apps in the background (may take time).
    func refreshMenuBarApps() async -> [RunningApp]

    /// Refresh hidden menu bar apps in the background (may take time).
    func refreshHiddenMenuBarApps() async -> [RunningApp]

    /// Refresh shown (visible) menu bar apps in the background (may take time).
    func refreshVisibleMenuBarApps() async -> [RunningApp]

    /// Activate an app, revealing hidden items and attempting virtual click
    @MainActor
    func activate(app: RunningApp) async
}

// MARK: - SearchService

final class SearchService: SearchServiceProtocol {
    static let shared = SearchService()

    func getRunningApps() async -> [RunningApp] {
        // Run on main actor because accessing NSWorkspace.runningApplications is main-thread bound
        await MainActor.run {
            let workspace = NSWorkspace.shared
            return workspace.runningApplications
                .filter { app in
                    // Include regular apps and background apps that might have status items
                    app.activationPolicy == .regular ||
                    app.activationPolicy == .accessory
                }
                .filter { $0.bundleIdentifier != nil }
                .map { RunningApp(app: $0) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    func getMenuBarApps() async -> [RunningApp] {
        await refreshMenuBarApps()
    }

    func getHiddenMenuBarApps() async -> [RunningApp] {
        await refreshHiddenMenuBarApps()
    }

    @MainActor
    func cachedMenuBarApps() -> [RunningApp] {
        AccessibilityService.shared.cachedMenuBarItemOwners()
    }

    @MainActor
    func cachedHiddenMenuBarApps() -> [RunningApp] {
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
        // Hidden icons are LEFT of the separator's left edge (lower X values)
        guard let separatorX = MenuBarManager.shared.getSeparatorOriginX() else {
            return []
        }
        return items
            .filter { $0.x < separatorX }
            .map { $0.app }
    }

    @MainActor
    func cachedVisibleMenuBarApps() -> [RunningApp] {
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
        // Visible icons are RIGHT of the separator's left edge (higher X values)
        guard let separatorX = MenuBarManager.shared.getSeparatorOriginX() else {
            return []
        }
        return items
            .filter { $0.x >= separatorX }
            .map { $0.app }
    }

    func refreshMenuBarApps() async -> [RunningApp] {
        await AccessibilityService.shared.refreshMenuBarItemOwners()
    }

    func refreshHiddenMenuBarApps() async -> [RunningApp] {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        // Hidden icons are LEFT of the separator's left edge (lower X values)
        let separatorX = await MainActor.run {
            MenuBarManager.shared.getSeparatorOriginX()
        }
        guard let separatorX else {
            return []
        }
        return items.filter { $0.x < separatorX }.map { $0.app }
    }

    func refreshVisibleMenuBarApps() async -> [RunningApp] {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        // Visible icons are RIGHT of the separator's left edge (higher X values)
        let separatorX = await MainActor.run {
            MenuBarManager.shared.getSeparatorOriginX()
        }
        guard let separatorX else {
            return []
        }
        return items.filter { $0.x >= separatorX }.map { $0.app }
    }

    @MainActor
    func activate(app: RunningApp) async {
        // 1. Show hidden menu bar items first
        let didReveal = await MenuBarManager.shared.showHiddenItemsNow(trigger: .search)

        // 2. Wait for menu bar animation to complete
        // When icons move from hidden (left of separator) to visible, macOS needs time
        if didReveal {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        // 3. Perform Virtual Click on the menu bar item
        let clickSuccess = AccessibilityService.shared.clickMenuBarItem(for: app.id)

        if !clickSuccess {
            // Fallback: Just activate the app normally (user can then click the now-visible icon)
            let workspace = NSWorkspace.shared
            if let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == app.id }) {
                runningApp.activate()
            }
        }

        // 4. ALWAYS auto-hide after Find Icon use (seamless experience)
        // Give user 5 seconds to interact with the menu, then hide
        if didReveal {
            MenuBarManager.shared.scheduleRehideFromSearch(after: 5.0)
        }
    }
}
