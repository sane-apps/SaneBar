import SwiftUI

struct ExperimentalSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showingFeedback = false

    var body: some View {
        VStack(spacing: 20) {
            // Welcome message with buttons
            honestExplanationSection

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingFeedback) {
            FeedbackView()
        }
    }

    // MARK: - Welcome Message

    private var honestExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flask")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)

                Text("Advanced Features")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()
            }

            Text("These features are newer and may not work perfectly on every setup. If something doesn't work right, let us know — it helps a lot.")
                .foregroundStyle(.primary.opacity(0.7))

            // Buttons inline
            HStack {
                Button {
                    showingFeedback = true
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Text("·")
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://github.com/sane-apps/SaneBar/issues")!) {
                    Label("View Issues", systemImage: "arrow.up.right.square")
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}
