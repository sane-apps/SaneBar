import SwiftUI
import AppKit

/// In-app issue reporting view with diagnostic log collection
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var issueTitle = ""
    @State private var issueDescription = ""
    @State private var isCollecting = false
    @State private var diagnosticReport: DiagnosticReport?
    @State private var showPreview = false

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

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Issue Title")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Brief description of the problem", text: $issueTitle)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Description field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happened?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $issueDescription)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // What will be included
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's included in the report:")
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
                        Text("Your report opens in your browser. Nothing is sent without your approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Preview Report") {
                    collectAndPreview()
                }
                .disabled(issueTitle.isEmpty || isCollecting)

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
                        Text("Open in GitHub")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(issueTitle.isEmpty || isCollecting)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .sheet(isPresented: $showPreview) {
            if let report = diagnosticReport {
                FeedbackPreviewView(
                    report: report,
                    title: issueTitle,
                    description: issueDescription,
                    onSubmit: { openInGitHub(report: report) },
                    onCancel: { showPreview = false }
                )
            }
        }
    }

    private func collectAndPreview() {
        isCollecting = true
        Task {
            let report = await DiagnosticsService.shared.collectDiagnostics()
            await MainActor.run {
                diagnosticReport = report
                isCollecting = false
                showPreview = true
            }
        }
    }

    private func submitReport() {
        isCollecting = true
        Task {
            let report = await DiagnosticsService.shared.collectDiagnostics()
            await MainActor.run {
                diagnosticReport = report
                isCollecting = false
                openInGitHub(report: report)
            }
        }
    }

    private func openInGitHub(report: DiagnosticReport) {
        let title = issueTitle.isEmpty ? "Bug Report" : issueTitle
        if let url = report.gitHubIssueURL(title: title, userDescription: issueDescription) {
            NSWorkspace.shared.open(url)
            dismiss()
        }
    }
}

/// Preview of what will be submitted
struct FeedbackPreviewView: View {
    let report: DiagnosticReport
    let title: String
    let description: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview Report")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                Text(report.toMarkdown(userDescription: description))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            HStack {
                Text("This will open in your browser")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Back") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Submit to GitHub") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
}

#Preview {
    FeedbackView()
}
