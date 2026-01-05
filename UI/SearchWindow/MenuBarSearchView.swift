import SwiftUI
import AppKit

// MARK: - RunningApp Model

/// Represents a running app that might have a menu bar icon
struct RunningApp: Identifiable, Hashable {
    let id: String  // bundleIdentifier
    let name: String
    let icon: NSImage?

    init(app: NSRunningApplication) {
        self.id = app.bundleIdentifier ?? UUID().uuidString
        self.name = app.localizedName ?? "Unknown"
        self.icon = app.icon
    }
}

// MARK: - MenuBarSearchView

/// SwiftUI view for searching and finding menu bar apps
struct MenuBarSearchView: View {
    @State private var searchText = ""
    @State private var selectedApp: RunningApp?
    @State private var runningApps: [RunningApp] = []

    let onDismiss: () -> Void

    var filteredApps: [RunningApp] {
        if searchText.isEmpty {
            return runningApps
        }
        return runningApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // App list
            if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No matching apps")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps, selection: $selectedApp) { app in
                    AppRow(app: app)
                        .tag(app)
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer with actions
            VStack(alignment: .leading, spacing: 8) {
                if let app = selectedApp {
                    HStack(spacing: 12) {
                        // Activate button - shows hidden items and activates app
                        Button(action: { activateApp(app) }) {
                            Label("Activate", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .keyboardShortcut(.return, modifiers: [])

                        // Copy bundle ID
                        Button(action: { copyBundleID(app) }) {
                            Label("Copy ID", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Spacer()

                        // Bundle ID display
                        Text(app.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text("Select an app and press Return to activate it. This will reveal hidden items and bring the app forward.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 400, height: 300)
        .onAppear {
            loadRunningApps()
        }
        .onExitCommand {
            onDismiss()
        }
    }

    private func loadRunningApps() {
        // Get all running apps, filter to those likely to have status items
        let workspace = NSWorkspace.shared
        runningApps = workspace.runningApplications
            .filter { app in
                // Include regular apps and background apps that might have status items
                app.activationPolicy == .regular ||
                app.activationPolicy == .accessory
            }
            .filter { $0.bundleIdentifier != nil }
            .map { RunningApp(app: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func activateApp(_ app: RunningApp) {
        // Show hidden menu bar items first
        MenuBarManager.shared.showHiddenItems()

        // Find and activate the app
        let workspace = NSWorkspace.shared
        if let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == app.id }) {
            // Use modern activation API (macOS 14+) with fallback
            runningApp.activate()
        }

        // Dismiss the search window
        onDismiss()
    }

    private func copyBundleID(_ app: RunningApp) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.id, forType: .string)
    }
}

// MARK: - AppRow

/// Row view for a single app
private struct AppRow: View {
    let app: RunningApp

    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                Text(app.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MenuBarSearchView(onDismiss: {})
}
