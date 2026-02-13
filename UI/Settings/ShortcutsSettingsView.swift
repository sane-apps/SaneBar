import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject private var licenseService = LicenseService.shared
    @State private var proUpsellFeature: ProFeature?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Free shortcuts
                CompactSection("Global Hotkeys") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Browse Icons")
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .searchMenuBar)
                                .help("Open the icon panel or second menu bar")
                        }
                        CompactDivider()
                        HStack {
                            Text("Show/Hide icons")
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .toggleHiddenItems)
                                .help("Toggle hidden icons visible or hidden")
                        }

                        // Additional shortcuts — Pro
                        if licenseService.isPro {
                            CompactDivider()
                            HStack {
                                Text("Show icons")
                                Spacer()
                                KeyboardShortcuts.Recorder(for: .showHiddenItems)
                                    .help("Reveal hidden menu bar icons")
                            }
                            CompactDivider()
                            HStack {
                                Text("Hide icons")
                                Spacer()
                                KeyboardShortcuts.Recorder(for: .hideItems)
                                    .help("Hide menu bar icons again")
                            }
                            CompactDivider()
                            HStack {
                                Text("Open Settings")
                                Spacer()
                                KeyboardShortcuts.Recorder(for: .openSettings)
                                    .help("Open the SaneBar settings window")
                            }
                        } else {
                            CompactDivider()
                            proGatedRow(feature: .additionalShortcuts, label: "Show, Hide, Open Settings shortcuts")
                        }
                    }
                    .padding(4)
                }

                // 2. Automation — Pro
                CompactSection("Automation") {
                    if licenseService.isPro {
                        CompactRow("AppleScript Toggle") {
                            HStack {
                                Text("osascript -e 'tell app \"SaneBar\" to toggle'")
                                    .font(.system(size: 13, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help("Use this command in scripts or automation tools")

                                Spacer()

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("osascript -e 'tell app \"SaneBar\" to toggle'", forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .help("Copy command to clipboard")
                            }
                        }
                    } else {
                        proGatedRow(feature: .appleScript, label: "AppleScript automation commands")
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
    }

    // MARK: - Pro Gating Helper

    private func proGatedRow(feature: ProFeature, label: String) -> some View {
        CompactRow(label) {
            Button {
                proUpsellFeature = feature
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("Pro")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.teal.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }
}
