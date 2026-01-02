import SwiftUI

// MARK: - PermissionRequestView

/// View for requesting accessibility permission
struct PermissionRequestView: View {
    @ObservedObject var permissionService: PermissionService
    var onGranted: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            // Title
            Text("Accessibility Permission Required")
                .font(.title2)
                .fontWeight(.semibold)

            // Description
            Text("SaneBar needs Accessibility permission to detect and manage your menu bar items.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            // Status indicator
            statusIndicator

            // Instructions
            instructionsView

            // Action buttons
            actionButtons
        }
        .padding(32)
        .frame(width: 400)
        .onChange(of: permissionService.permissionState) { _, newValue in
            if newValue == .granted {
                onGranted?()
            }
        }
    }

    // MARK: - Subviews

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: permissionService.permissionState.systemImage)
                .foregroundStyle(statusColor)

            Text(permissionService.permissionState.displayName)
                .foregroundStyle(statusColor)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch permissionService.permissionState {
        case .unknown: return .gray
        case .notGranted: return .orange
        case .granted: return .green
        }
    }

    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            instructionStep(number: 1, text: "Click \"Open System Settings\" below")
            instructionStep(number: 2, text: "Find SaneBar in the list")
            instructionStep(number: 3, text: "Toggle the switch to enable access")
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))

            Text(text)
                .font(.subheadline)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                permissionService.openAccessibilitySettings()
            } label: {
                Label("Open System Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if permissionService.permissionState == .granted {
                Button("Continue") {
                    onGranted?()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Preview

#Preview("Permission Not Granted") {
    PermissionRequestView(
        permissionService: {
            let service = PermissionService()
            return service
        }()
    )
}
