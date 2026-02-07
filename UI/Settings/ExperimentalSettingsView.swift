import SwiftUI

struct ExperimentalSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showingFeedback = false

    var body: some View {
        VStack(spacing: 20) {
            // Welcome message with buttons
            honestExplanationSection

            // Experimental features (when available)
            if hasExperimentalFeatures {
                experimentalFeaturesSection
            }

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

    // MARK: - Advanced Features

    private var hasExperimentalFeatures: Bool {
        true
    }

    @ViewBuilder
    private var experimentalFeaturesSection: some View {
        CompactSection("Features") {
            CompactToggle(
                label: "Always-hidden section",
                isOn: $menuBarManager.settings.alwaysHiddenSectionEnabled
            )
            .help("Adds a second separator — icons between the two separators stay hidden even when you reveal the rest.")

            CompactDivider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Adds a second separator to your menu bar. Icons placed between the two separators stay permanently hidden — they won't appear even when you click to reveal.")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.7))

                Text("Uses Accessibility to enforce hiding. Requires a restart to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}
