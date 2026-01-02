import SwiftUI

// MARK: - WelcomeBanner

/// First-launch welcome - CLEAR text, BIG fonts, GENEROUS padding
struct WelcomeBanner: View {
    @Binding var isVisible: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Text("Welcome to SaneBar")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // What it does - simple text explanation
            Text("Organize your menu bar icons into two groups:")
                .font(.body)
                .foregroundStyle(.secondary)

            // The two groups - clear labels
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Visible")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Always in your menu bar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 12, height: 12)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hidden")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("Click our icon to reveal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)

            // How to use - multiple methods
            VStack(alignment: .leading, spacing: 8) {
                Text("How to organize:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(.blue)
                    Text("Click the section icons on each item")
                        .font(.callout)
                }

                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.blue)
                    Text("Or drag items between sections")
                        .font(.callout)
                }
            }

            // Button
            Button {
                dismiss()
            } label: {
                Text("Got It")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
        .padding(16)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        onDismiss()
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    private static let hasSeenWelcomeKey = "SaneBar.hasSeenWelcome"

    var hasSeenWelcome: Bool {
        get { bool(forKey: Self.hasSeenWelcomeKey) }
        set { set(newValue, forKey: Self.hasSeenWelcomeKey) }
    }
}

// MARK: - Preview

#Preview("Welcome Banner") {
    VStack {
        WelcomeBanner(isVisible: .constant(true)) {}
        Spacer()
    }
    .frame(width: 340, height: 500)
    .background(Color(NSColor.windowBackgroundColor))
}
