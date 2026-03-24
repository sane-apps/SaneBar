import SaneUI
import SwiftUI

struct ExperimentalSettingsView: View {
    @State private var showingFeedback = false

    var body: some View {
        VStack(spacing: 20) {
            // Welcome message with buttons
            honestExplanationSection

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $showingFeedback) {
            SaneFeedbackView(
                diagnosticsService: .shared,
                extraAttachments: [("menubar.rectangle", "Menu bar state snapshot (separator positions & counts)")]
            )
        }
    }

    // MARK: - Welcome Message

    private var honestExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flask")
                    .font(.system(size: 24))
                    .foregroundStyle(SaneBarChrome.accentHighlight)

                Text("Advanced Features")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()
            }

            Text("These features are newer and may not work perfectly on every setup. If something doesn't work right, let us know — it helps a lot.")
                .foregroundStyle(.white.opacity(0.92))

            // Buttons inline
            HStack {
                Button {
                    showingFeedback = true
                } label: {
                    Label("Report a Bug", systemImage: "ladybug")
                }
                .buttonStyle(ChromeActionButtonStyle(prominent: true))

                Text("·")
                    .foregroundStyle(.white.opacity(0.92))

                Link(destination: URL(string: "https://github.com/sane-apps/SaneBar/issues/new?template=bug_report.md")!) {
                    Label("View Issues", systemImage: "arrow.up.right.square")
                }
            }
        }
        .padding(16)
        .background(SaneBarChrome.softSurfaceFill)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SaneBarChrome.rowStroke, lineWidth: 1)
        )
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}
