import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - MenuBarSearchView

/// SwiftUI view for searching and finding menu bar apps
struct MenuBarSearchView: View {
    @State private var searchText = ""
    @State private var selectedApp: RunningApp?
    @State private var runningApps: [RunningApp] = []

    let service: SearchServiceProtocol
    let onDismiss: () -> Void

    init(service: SearchServiceProtocol = SearchService.shared, onDismiss: @escaping () -> Void) {
        self.service = service
        self.onDismiss = onDismiss
    }

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
                    Button(
                        action: { searchText = "" },
                        label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    )
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
                    // Row 1: Buttons
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await service.activate(app: app)
                                onDismiss()
                            }
                        } label: {
                            Label("Activate", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])

                        Button { copyBundleID(app) } label: {
                            Label("Copy ID", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text("Hotkey:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        KeyboardShortcuts.Recorder(
                            for: IconHotkeysService.shortcutName(for: app.id)
                        ) { shortcut in
                            Task { @MainActor in
                                if let shortcut = shortcut, let key = shortcut.key {
                                    let data = KeyboardShortcutData(
                                        keyCode: UInt16(key.rawValue),
                                        modifiers: UInt(shortcut.modifiers.rawValue)
                                    )
                                    MenuBarManager.shared.settings.iconHotkeys[app.id] = data
                                } else {
                                    MenuBarManager.shared.settings.iconHotkeys.removeValue(forKey: app.id)
                                }
                                MenuBarManager.shared.saveSettings()
                            }
                        }
                    }

                    // Row 2: Bundle ID
                    Text(app.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                } else {
                    Text("Select an app and press Return to activate it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 400, height: 300)
        .onAppear {
            Task {
                runningApps = await service.getRunningApps()
            }
        }
        .onExitCommand {
            onDismiss()
        }
    }

    private func copyBundleID(_ app: RunningApp) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.id, forType: .string)
    }
}

// MARK: - AppRow

/// Row view for a single app
struct AppRow: View {
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
