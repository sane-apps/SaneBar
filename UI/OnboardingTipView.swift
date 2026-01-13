import SwiftUI
import AppKit

// MARK: - OnboardingTipView

/// First-launch onboarding popover content
struct OnboardingTipView: View {
    let onDismiss: () -> Void

    @State private var currentStep = 0
    @State private var hasAccessibility = false
    @State private var permissionRequested = false
    @State private var permissionMonitorTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<2) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Content
            Group {
                if currentStep == 0 {
                    welcomeStep
                } else {
                    permissionStep
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 340)
        .onAppear {
            hasAccessibility = AccessibilityService.shared.isGranted
            startPermissionMonitoring()
        }
        .onDisappear {
            permissionMonitorTask?.cancel()
        }
    }

    /// Monitor for permission changes in real-time
    /// When user grants permission in System Settings, UI updates immediately
    private func startPermissionMonitoring() {
        permissionMonitorTask = Task { @MainActor in
            for await granted in AccessibilityService.shared.permissionStream(includeInitial: false) {
                hasAccessibility = granted
                if granted {
                    // Auto-advance or show success when permission granted
                    permissionRequested = true
                }
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hand.wave.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Welcome to SaneBar!")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 10) {
                tipRow(icon: "hand.draw", text: "**⌘+drag** icons to arrange them")
                tipRow(icon: "line.diagonal", text: "Icons left of **/** get hidden")
                tipRow(icon: "cursorarrow.click", text: "Click **SaneBar** to reveal hidden icons")
                tipRow(icon: "magnifyingglass", text: "**⌘+Shift+Space** to search icons")
            }
            .font(.callout)

            Button {
                withAnimation {
                    currentStep = 1
                }
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: permissionRequested || hasAccessibility ? "checkmark.shield.fill" : "shield.fill")
                    .font(.title)
                    .foregroundStyle(permissionRequested || hasAccessibility ? .green : .orange)
                Text(permissionRequested || hasAccessibility ? "You're All Set!" : "One More Thing")
                    .font(.headline)
            }

            if permissionRequested || hasAccessibility {
                Text("SaneBar is ready to use! If the \"Find Icon\" search doesn't work, check that SaneBar is enabled in **System Settings → Privacy → Accessibility**.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("For the **Find Icon** feature to work, SaneBar needs Accessibility permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    // Actually open System Settings to the Accessibility pane
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                    permissionRequested = true
                } label: {
                    Label("Open System Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Toggle **SaneBar** ON in the list, then come back here.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                if !permissionRequested && !hasAccessibility {
                    Button("Back") {
                        withAnimation {
                            currentStep = 0
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Helpers

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(text))
        }
    }
}

#Preview("Welcome") {
    OnboardingTipView(onDismiss: {})
}

#Preview("Permission") {
    OnboardingTipView(onDismiss: {})
}
