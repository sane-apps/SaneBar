import SwiftUI
import AppKit

/// In-app issue reporting view with diagnostic log collection
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var issueDescription = ""

    private enum CollectingAction {
        case report
        case copy
    }

    @State private var collectingAction: CollectingAction?
    @State private var didCopyDiagnostics = false

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
                            Label("Menu bar state snapshot (separator positions & counts)", systemImage: "menubar.rectangle")
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
                    copyDiagnostics()
                } label: {
                    if collectingAction == .copy {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text(didCopyDiagnostics ? "Copied" : "Copy Diagnostics")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(collectingAction != nil)

                Button {
                    submitReport()
                } label: {
                    if collectingAction == .report {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Report Issue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(issueDescription.isEmpty || collectingAction != nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }

    private func copyDiagnostics() {
        collectingAction = .copy
        Task {
            let report = await DiagnosticsService.shared.collectDiagnostics()
            let description = issueDescription.isEmpty ? "<describe what happened here>" : issueDescription
            let markdown = report.toMarkdown(userDescription: description)

            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
                collectingAction = nil
                didCopyDiagnostics = true
            }

            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                didCopyDiagnostics = false
            }
        }
    }

    private func submitReport() {
        collectingAction = .report
        Task {
            let report = await DiagnosticsService.shared.collectDiagnostics()
            await MainActor.run {
                collectingAction = nil
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
