import SwiftUI
import AppKit

/// In-app issue reporting view with diagnostic log collection
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var issueDescription = ""
    @State private var isCollecting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Report an Issue")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Form - single field
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happened?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $issueDescription)
                            .font(.body)
                            .frame(minHeight: 120)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // What gets attached automatically
                    VStack(alignment: .leading, spacing: 8) {
                        Text("We'll automatically attach:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Label("App version & macOS version", systemImage: "info.circle")
                            Label("Hardware info (Mac model)", systemImage: "desktopcomputer")
                            Label("Recent logs (last 5 minutes)", systemImage: "doc.text")
                            Label("Current settings (no personal data)", systemImage: "gearshape")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    // Privacy note
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.green)
                        Text("Opens in your browser. Nothing is sent without your approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Link("Email us instead", destination: URL(string: "mailto:hi@saneapps.com")!)
                    .font(.caption)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    submitReport()
                } label: {
                    if isCollecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Report Issue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(issueDescription.isEmpty || isCollecting)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }

    private func submitReport() {
        isCollecting = true
        Task {
            let report = await DiagnosticsService.shared.collectDiagnostics()
            await MainActor.run {
                isCollecting = false
                openInGitHub(report: report)
            }
        }
    }

    private func openInGitHub(report: DiagnosticReport) {
        // Auto-generate title from first line of description
        let firstLine = issueDescription.components(separatedBy: .newlines).first ?? ""
        let title = String(firstLine.prefix(60))
        if let url = report.gitHubIssueURL(title: title, userDescription: issueDescription) {
            NSWorkspace.shared.open(url)
            dismiss()
        }
    }
}

#Preview {
    FeedbackView()
}
