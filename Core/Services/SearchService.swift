import AppKit
import Foundation

// MARK: - SearchServiceProtocol

/// @mockable
protocol SearchServiceProtocol: Sendable {
    /// Fetch all running apps suitable for menu bar interaction
    func getRunningApps() async -> [RunningApp]

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

    @MainActor
    func activate(app: RunningApp) {
        // 1. Show hidden menu bar items first (in case it's hidden)
        MenuBarManager.shared.showHiddenItems()

        // 2. Perform Virtual Click on the menu bar item
        let clickSuccess = AccessibilityService.shared.clickMenuBarItem(for: app.id)

        if !clickSuccess {
            // Fallback: Just activate the app normally
            let workspace = NSWorkspace.shared
            if let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == app.id }) {
                runningApp.activate()
            }
        }
    }
}
