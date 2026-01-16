import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Hotkeys
                CompactSection("Global Hotkeys") {
                    VStack(alignment: .leading, spacing: 12) {
                         HStack {
                             Text("Find any icon")
                             Spacer()
                             KeyboardShortcuts.Recorder(for: .searchMenuBar)
                         }
                         CompactDivider()
                         HStack {
                             Text("Show/Hide icons")
                             Spacer()
                             KeyboardShortcuts.Recorder(for: .toggleHiddenItems)
                         }
                         CompactDivider()
                         HStack {
                             Text("Show icons")
                             Spacer()
                             KeyboardShortcuts.Recorder(for: .showHiddenItems)
                         }
                         CompactDivider()
                         HStack {
                             Text("Hide icons")
                             Spacer()
                             KeyboardShortcuts.Recorder(for: .hideItems)
                         }
                         CompactDivider()
                         HStack {
                             Text("Open Settings")
                             Spacer()
                             KeyboardShortcuts.Recorder(for: .openSettings)
                         }
                    }
                    .padding(4)
                }

                // 2. Automation
                CompactSection("Automation") {
                    CompactRow("AppleScript Toggle") {
                        HStack {
                            Text("osascript -e 'tell app \"SaneBar\" to toggle'")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("osascript -e 'tell app \"SaneBar\" to toggle'", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}
