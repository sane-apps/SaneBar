import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Hotkeys
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
                    }
                    .padding(4)
                }

                // 2. Automation
                CompactSection("Automation") {
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
                }
            }
            .padding(20)
        }
    }
}
