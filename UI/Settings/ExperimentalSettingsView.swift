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

                Text("Hey Sane crew!")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()
            }

            Text("Thank you for clicking on this tab.")
                .foregroundStyle(.secondary)

            Text("This exists because you all have many different configurations and setups, and I only have my MacBook Air. I'm going to need your help with experimental features and testing.")
                .foregroundStyle(.secondary)

            Text("If you find a bug, please report it.")
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("❤️")
                Text("Mr. Sane")
                    .fontWeight(.medium)
            }
            .padding(.top, 4)

            Divider()
                .padding(.vertical, 4)

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

    // MARK: - Experimental Features

    private var hasExperimentalFeatures: Bool {
        // Will be true once we add the second section feature
        false
    }

    @ViewBuilder
    private var experimentalFeaturesSection: some View {
        CompactSection("Features") {
            // Placeholder for second menu bar section
            // This will be enabled once the feature is implemented

            // CompactToggle(
            //     label: "Second always-visible section",
            //     isOn: $menuBarManager.settings.experimentalSecondSection
            // )
            // .help("Adds a second zone for icons you always want visible")

            Text("No experimental features available yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}
