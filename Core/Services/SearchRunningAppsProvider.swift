import AppKit

enum SearchRunningAppsProvider {
    @MainActor
    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular ||
                    app.activationPolicy == .accessory
            }
            .filter { $0.bundleIdentifier != nil }
            .map { RunningApp(app: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}
