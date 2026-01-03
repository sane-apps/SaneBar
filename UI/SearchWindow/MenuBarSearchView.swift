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

            // Footer with instructions
            VStack(alignment: .leading, spacing: 4) {
                if let app = selectedApp {
                    HStack {
                        Text("Bundle ID:")
                            .foregroundStyle(.secondary)
                        Text(app.id)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(app.id, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Text("Select an app to see its bundle ID. Use bundle IDs in Settings > Advanced for Always Visible or App Triggers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
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
