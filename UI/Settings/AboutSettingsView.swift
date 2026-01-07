import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showResetConfirmation = false
    @State private var showLicenses = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

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

            GroupBox {
                VStack(spacing: 8) {
                    Label("100% On-Device", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)

                    Text("No analytics. No telemetry. No network requests. Everything stays on your Mac.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 40)

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
            }
            .font(.system(size: 13))

            Spacer()

            // Reset button separated - destructive action
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Text("Reset to Defaults")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showLicenses) {
            licensesSheet
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
}
