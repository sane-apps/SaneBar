import SwiftUI

struct ExperimentalSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var showingFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // The honest explanation
                honestExplanationSection

                // Experimental features
                if hasExperimentalFeatures {
                    experimentalFeaturesSection
                }

                // Easy bug reporting
                feedbackSection
            }
            .padding(20)
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackView()
        }
    }

    // MARK: - Honest Explanation

    private var honestExplanationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "flask")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Experimental Features")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Testing in progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Hi! I'm the developer behind SaneBar.")
                    .fontWeight(.medium)

                Text("""
                I build and test on a single MacBook Air. That means I can't test every monitor configuration, every app that puts icons in your menu bar, or every edge case that might happen on your setup.

                That's where you come in.

                Features in this section are new and need real-world testing. They work on my machine, but I need your help to make sure they work on yours too.
                """)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    Text("Your feedback genuinely helps. Thank you for being part of making SaneBar better.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
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

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        CompactSection("Help Improve SaneBar") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Found a bug? Something not working right?")
                    .font(.subheadline)

                Text("Reports include your Mac model, macOS version, and recent logs—no personal data. Everything opens in your browser so you can review before submitting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        showingFeedback = true
                    } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Spacer()

                    Link(destination: URL(string: "https://github.com/sane-apps/SaneBar/issues")!) {
                        Label("View All Issues", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
                .padding(.top, 4)
            }
        }
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}
