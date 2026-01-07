import SwiftUI

// MARK: - OnboardingTipView

/// First-launch onboarding popover content
struct OnboardingTipView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hand.wave.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Welcome to SaneBar!")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "hand.draw", text: "Cmd+drag icons to arrange them")

                HStack(spacing: 4) {
                    Image(systemName: "line.diagonal")
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("This is the separator icon")
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "line.diagonal")
                        .padding(4)
                        .background(.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                tipRow(icon: "arrow.left.circle", text: "Icons LEFT of it can be hidden")
                tipRow(icon: "arrow.right.circle", text: "Icons RIGHT of it stay visible")
                tipRow(icon: "cursorarrow.click", text: "Click SaneBar icon to show/hide")
            }
            .font(.callout)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Pro Tip: Search")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                tipRow(icon: "magnifyingglass", text: "Lost an icon behind the Notch?")
                tipRow(icon: "keyboard", text: "Press Cmd+Shift+Space to search & click it")
            }
            .font(.callout)

            Button("Got it!") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
        }
    }
}

#Preview {
    OnboardingTipView(onDismiss: {})
        .frame(width: 320)
}
