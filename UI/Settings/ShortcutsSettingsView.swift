import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Click a field, then press your shortcut keys.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        KeyboardShortcuts.Recorder("Toggle visibility:", name: .toggleHiddenItems)
                        KeyboardShortcuts.Recorder("Show hidden:", name: .showHiddenItems)
                        KeyboardShortcuts.Recorder("Hide items:", name: .hideItems)
                        KeyboardShortcuts.Recorder("Search apps:", name: .searchMenuBar)
                        KeyboardShortcuts.Recorder("Open Settings:", name: .openSettings)
                    }
                    .tint(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Global Shortcuts", systemImage: "keyboard")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("osascript -e 'tell app \"SaneBar\" to toggle'")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("osascript -e 'tell app \"SaneBar\" to toggle'", forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)

                        Text("Commands: **toggle**, **show hidden**, **hide items**")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("AppleScript & Automation", systemImage: "applescript")
                }
            }
            .padding()
        }
    }
}
