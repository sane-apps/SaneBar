import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @State private var showLicenses = false
    @State private var showSupport = false
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App identity
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)

            VStack(spacing: 8) {
                Text("SaneBar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }

            // Trust info (Capsule style)
            HStack(spacing: 0) {
                Text("Made with ❤️ in 🇺🇸")
                    .fontWeight(.medium)
                Text(" · ")
                Text("100% On-Device")
                Text(" · ")
                Text("No Analytics")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.top, 4)

            // Links
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/sane-apps/SaneBar")!) {
                        Label("GitHub", systemImage: "link")
                    }

                    Button {
                        showLicenses = true
                    } label: {
                        Label("Licenses", systemImage: "doc.text")
                    }

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
                }

                HStack(spacing: 12) {
                    Button {
                        showFeedback = true
                    } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                    }

                    Link(destination: URL(string: "mailto:hi@saneapps.com")!) {
                        Label("Email Us", systemImage: "envelope")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 12)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // BUG-025 Fix: Use popover instead of sheet to allow tab switching
        // Sheets are modal and block interaction with parent view (including tab bar)
        .popover(isPresented: $showLicenses, arrowEdge: .bottom) {
            licensesSheet
        }
        .popover(isPresented: $showSupport, arrowEdge: .bottom) {
            supportSheet
        }
        .popover(isPresented: $showFeedback, arrowEdge: .bottom) {
            FeedbackView()
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
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Link("Sparkle", destination: URL(string: "https://sparkle-project.org")!)
                                .font(.headline)

                            Text("""
                            Copyright (c) 2006-2013 Andy Matuschak.
                            Copyright (c) 2009-2013 Elgato Systems GmbH.
                            Copyright (c) 2011-2014 Kornel Lesiński.
                            Copyright (c) 2015-2017 Mayur Pawashe.
                            Copyright (c) 2014 C.W. Betts.
                            Copyright (c) 2014 Petroules Corporation.
                            Copyright (c) 2014 Big Nerd Ranch.
                            All rights reserved.

                            Permission is hereby granted, free of charge, to any person obtaining a copy of
                            this software and associated documentation files (the "Software"), to deal in
                            the Software without restriction, including without limitation the rights to
                            use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
                            of the Software, and to permit persons to whom the Software is furnished to do
                            so, subject to the following conditions:

                            The above copyright notice and this permission notice shall be included in all
                            copies or substantial portions of the Software.

                            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
                            FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
                            COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
                            IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
                            CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                            """)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
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
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.top, 8)

                    // Personal message
                    Text("I need your help to keep SaneBar alive. Your support — whether one-time or monthly — makes this possible. Thank you.")
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("— Mr. Sane")
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)

                    Divider()
                        .padding(.horizontal, 40)

                    // GitHub Sponsors
                    Link(destination: URL(string: "https://github.com/sponsors/sane-apps")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                            Text("Sponsor on GitHub")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.pink.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    // Crypto addresses
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Or send crypto:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.blue)
                .frame(width: 36, alignment: .leading)

            Text(address)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
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
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copied ? .green : .white.opacity(0.9))
        }
    }
}
