import SwiftUI

struct AccessibilityPermissionView: View {
    @ObservedObject var accessibilityService = AccessibilityService.shared

    var body: some View {
        VStack(spacing: 16) {
            // Status Indicator
            HStack(spacing: 12) {
                Circle()
                    .fill(accessibilityService.isGranted ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .shadow(color: (accessibilityService.isGranted ? Color.green : Color.red).opacity(0.5), radius: 4, x: 0, y: 0)

                Text(accessibilityService.isGranted ? "Accessibility Access Granted" : "Accessibility Access Required")
                    .font(.headline)
                    .foregroundStyle(.primary.opacity(accessibilityService.isGranted ? 1.0 : 0.7))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(accessibilityService.isGranted ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
            )

            if !accessibilityService.isGranted {
                VStack(spacing: 12) {
                    Text("SaneBar needs accessibility permission to control your menu bar icons.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal)

                    Button {
                        openAccessibilitySettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("System Settings > Privacy & Security > Accessibility")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You're all set!")
                        .font(.subheadline)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy, value: accessibilityService.isGranted)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        )
    }

    private func openAccessibilitySettings() {
        // Deep link to Accessibility pane
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    VStack {
        AccessibilityPermissionView()
            .padding()
    }
    .frame(width: 400, height: 300)
}
