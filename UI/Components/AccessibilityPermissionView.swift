import SaneUI
import SwiftUI

struct AccessibilityPermissionView: View {
    @ObservedObject var accessibilityService = AccessibilityService.shared
    private let brightTeal = Color(red: 0.55, green: 0.96, blue: 0.93)

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
                    .foregroundStyle(.white.opacity(accessibilityService.isGranted ? 1.0 : 0.92))
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "video.slash.fill")
                                .foregroundStyle(brightTeal)
                                .frame(width: 20)
                            Text("No screen recording.")
                                .font(.subheadline)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .foregroundStyle(brightTeal)
                                .frame(width: 20)
                            Text("No screenshots.")
                                .font(.subheadline)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.slash")
                                .foregroundStyle(brightTeal)
                                .frame(width: 20)
                            Text("No data collected.")
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal)

                    Button {
                        openAccessibilitySettings()
                    } label: {
                        Label("Open Accessibility Settings", systemImage: "lock.open.fill")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.saneAccentSoft.opacity(0.98), Color.saneAccent.opacity(0.98)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                            )
                            .shadow(color: Color.saneAccentDeep.opacity(0.28), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)

                    Text("Toggle SaneBar on in the list that appears")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
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
        _ = AccessibilityService.shared.openAccessibilitySettings()
    }
}

#Preview {
    VStack {
        AccessibilityPermissionView()
            .padding()
    }
    .frame(width: 400, height: 300)
}
