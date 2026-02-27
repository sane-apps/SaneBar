import SwiftUI

struct MenuBarSearchAccessibilityPrompt: View {
    let loadCachedApps: () -> Void
    let refreshApps: (Bool) -> Void
    private let accentStart = Color(red: 0.62, green: 0.97, blue: 0.95)
    private let accentEnd = Color(red: 0.35, green: 0.83, blue: 0.90)

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentStart, accentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(accentGradient)

            Text("Grant Access")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.97))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.93))
                        .frame(width: 20)
                    Text("No screen recording.")
                        .foregroundStyle(.white.opacity(0.92))
                }
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.93))
                        .frame(width: 20)
                    Text("No screenshots.")
                        .foregroundStyle(.white.opacity(0.92))
                }
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.93))
                        .frame(width: 20)
                    Text("No data collected.")
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .font(.system(size: 17, weight: .medium))
            .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button("Open Accessibility Settings") {
                    _ = AccessibilityService.shared.openAccessibilitySettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                )
                .shadow(color: Color(red: 0.10, green: 0.28, blue: 0.48).opacity(0.35), radius: 8, x: 0, y: 3)

                Button("Try Again") {
                    loadCachedApps()
                    refreshApps(true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MenuBarSearchEmptyState: View {
    let mode: String

    private var title: String {
        switch mode {
        case "hidden": "No hidden icons"
        case "visible": "No visible icons"
        default: "No menu bar icons"
        }
    }

    private var subtitle: String {
        switch mode {
        case "hidden":
            "All your menu bar icons are visible.\nUse ⌘-drag to hide icons left of the separator."
        case "visible":
            "All your menu bar icons are hidden.\nUse ⌘-drag to show icons right of the separator."
        default:
            "Try Refresh, or grant Accessibility permission."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MenuBarSearchNoMatchState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.9))

            Text("No matches for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
