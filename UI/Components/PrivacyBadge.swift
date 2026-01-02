import SwiftUI

// MARK: - PrivacyBadge

/// Privacy indicator - PROMINENT, not subtle
/// This is our #1 differentiator vs Bartender (they track users, we don't)
struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.body)
                .foregroundStyle(.green)

            Text("100% On-Device")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.green.opacity(0.15), in: Capsule())
        .help("Your data never leaves your Mac. No cloud, no tracking, no telemetry.")
    }
}

// MARK: - CompactPrivacyBadge

/// Smaller variant for tight spaces - still visible
struct CompactPrivacyBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text("On-Device")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
        .help("100% on-device - your data never leaves your Mac")
    }
}

// MARK: - Preview

#Preview("Privacy Badges") {
    VStack(spacing: 20) {
        PrivacyBadge()
        CompactPrivacyBadge()
    }
    .padding()
    .background(Color(NSColor.windowBackgroundColor))
}
