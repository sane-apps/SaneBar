import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Find any icon", name: .searchMenuBar)
                KeyboardShortcuts.Recorder("Show/hide icons", name: .toggleHiddenItems)
                KeyboardShortcuts.Recorder("Show icons", name: .showHiddenItems)
                KeyboardShortcuts.Recorder("Hide icons", name: .hideItems)
                KeyboardShortcuts.Recorder("Open settings", name: .openSettings)
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Find any icon works for hidden icons AND icons behind the notch. Or Option-click the SaneBar icon.")
            }

            Section {
                HStack {
                    Text("osascript -e 'tell app \"SaneBar\" to toggle'")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("osascript -e 'tell app \"SaneBar\" to toggle'", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("Commands: toggle, show hidden, hide items")
            }
        }
        .formStyle(.grouped)
    }
}
