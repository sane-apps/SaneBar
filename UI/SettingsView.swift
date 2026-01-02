import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("SaneBar Settings")
                .font(.headline)

            Text("Drag items here to hide them... (Coming Soon)")
                .foregroundColor(.secondary)

            Button("Quit SaneBar") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
