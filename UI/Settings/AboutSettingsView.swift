import SwiftUI
import AppKit

struct AboutSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showResetConfirmation = false
    @State private var showLicenses = false
    @State private var showSupport = false
    @State private var isCheckingForUpdates = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App identity
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text("SaneBar")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .foregroundStyle(.secondary)
                }
            }

            // Privacy - simple inline
            HStack(spacing: 4) {
                Label("Privacy First", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("No analytics. No telemetry. Your data stays on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Update section - clean and simple
            VStack(spacing: 8) {
                HStack {
                    Button {
                        checkForUpdates()
                    } label: {
                        if isCheckingForUpdates {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isCheckingForUpdates)

                    if let lastCheck = menuBarManager.settings.lastUpdateCheck {
                        Text("Last checked: \(lastCheck, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Toggle("Check automatically on launch", isOn: $menuBarManager.settings.checkForUpdatesAutomatically)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: menuBarManager.settings.checkForUpdatesAutomatically) { _, _ in
                        menuBarManager.saveSettings()
                    }
            }
            .padding(.vertical, 8)

            // Links row
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/stephanjoseph/SaneBar")!) {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)

                Button {
                    showLicenses = true
                } label: {
                    Label("Licenses", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Button {
                    showSupport = true
                } label: {
                    Label {
                        Text("Support")
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 13))

            Spacer()

            // Reset - subtle at bottom
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Text("Reset to Defaults")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding()
        .sheet(isPresented: $showLicenses) {
            licensesSheet
        }
        .sheet(isPresented: $showSupport) {
            supportSheet
        }
        .alert("Reset Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                menuBarManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their defaults. This cannot be undone.")
        }
    }

    // MARK: - Update Check

    private func checkForUpdates() {
        isCheckingForUpdates = true
        Task {
            let result = await menuBarManager.updateService.checkForUpdates()
            menuBarManager.settings.lastUpdateCheck = Date()
            menuBarManager.saveSettings()

            await MainActor.run {
                isCheckingForUpdates = false
                showUpdateResult(result)
            }
        }
    }

    private func showUpdateResult(_ result: UpdateResult) {
        let alert = NSAlert()

        switch result {
        case .upToDate:
            alert.messageText = "You're up to date!"
            alert.informativeText = "SaneBar is running the latest version."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")

        case .updateAvailable(let version, let releaseURL):
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            alert.messageText = "Update Available"
            alert.informativeText = "SaneBar \(version) is available. You're currently running \(currentVersion)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
            return

        case .error(let message):
            alert.messageText = "Update Check Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
        }

        alert.runModal()
    }

    // MARK: - Licenses Sheet

    private var licensesSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open Source Licenses")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showLicenses = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Link("KeyboardShortcuts", destination: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!)
                                .font(.headline)

                            Text("""
                            MIT License

                            Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

                            Permission is hereby granted, free of charge, to any person obtaining a copy \
                            of this software and associated documentation files (the "Software"), to deal \
                            in the Software without restriction, including without limitation the rights \
                            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
                            copies of the Software, and to permit persons to whom the Software is \
                            furnished to do so, subject to the following conditions:

                            The above copyright notice and this permission notice shall be included in all \
                            copies or substantial portions of the Software.

                            THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
                            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
                            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
                            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
                            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
                            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
                            SOFTWARE.
                            """)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Support Sheet

    private var supportSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Support SaneBar")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showSupport = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Quote
                    VStack(spacing: 4) {
                        Text("\"The worker is worthy of his wages.\"")
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .italic()
                        Text("— 1 Timothy 5:18")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Personal message
                    Text("This app is free because I hate corporations, not because I'm a filthy commie. If it's worth something to you, please donate so I can make a living.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Much love,\n— Mr. Sane")
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)

                    Divider()
                        .padding(.horizontal, 40)

                    // Crypto addresses
                    VStack(alignment: .leading, spacing: 12) {
                        CryptoAddressRow(label: "BTC", address: "3Go9nJu3dj2qaa4EAYXrTsTf5AnhcrPQke")
                        CryptoAddressRow(label: "SOL", address: "FBvU83GUmwEYk3HMwZh3GBorGvrVVWSPb8VLCKeLiWZZ")
                        CryptoAddressRow(label: "ZEC", address: "t1PaQ7LSoRDVvXLaQTWmy5tKUAiKxuE9hBN")
                    }
                    .padding()
                    .background(.fill.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
        }
        .frame(width: 420, height: 360)
    }
}

// MARK: - Crypto Address Row

private struct CryptoAddressRow: View {
    let label: String
    let address: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.blue)
                .frame(width: 32, alignment: .leading)

            Text(address)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copied ? .green : .secondary)
        }
    }
}
