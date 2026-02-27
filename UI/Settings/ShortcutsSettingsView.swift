import AppKit
import KeyboardShortcuts
import SaneUI
import SwiftUI

struct ShortcutsSettingsView: View {
    private struct AutomationCommand: Identifiable {
        let id: String
        let title: String
        let command: String
    }

    @ObservedObject private var licenseService = LicenseService.shared
    @State private var proUpsellFeature: ProFeature?
    private let automationCommands: [AutomationCommand] = [
        .init(
            id: "toggle",
            title: "Toggle hidden icons",
            command: "open \"sanebar://toggle\""
        ),
        .init(
            id: "show",
            title: "Show hidden icons",
            command: "open \"sanebar://show\""
        ),
        .init(
            id: "hide",
            title: "Hide icons",
            command: "open \"sanebar://hide\""
        ),
        .init(
            id: "search",
            title: "Open search",
            command: "open \"sanebar://search\""
        ),
        .init(
            id: "settings",
            title: "Open settings",
            command: "open \"sanebar://settings\""
        ),
        .init(
            id: "applescript-toggle",
            title: "AppleScript toggle",
            command: "osascript -e 'tell application \"SaneBar\" to toggle'"
        )
    ]

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
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(automationCommands.enumerated()), id: \.element.id) { index, item in
                                CompactRow(item.title) {
                                    HStack {
                                        Text(item.command)
                                            .font(.system(size: 13, design: .monospaced))
                                            .textSelection(.enabled)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .help("Use this command in Alfred, scripts, or shell automation")

                                        Spacer()

                                        Button {
                                            copyToClipboard(item.command)
                                        } label: {
                                            Text("Copy")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Copy command to clipboard")
                                    }
                                }

                                if index < automationCommands.count - 1 {
                                    CompactDivider()
                                }
                            }
                        }
                        .padding(4)
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
                .foregroundStyle(Color.saneAccentSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.saneAccentDeep.opacity(0.32)))
            }
            .buttonStyle(.plain)
        }
    }

    private func copyToClipboard(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
