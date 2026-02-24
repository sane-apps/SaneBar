import SwiftUI

struct MenuBarSearchAccessibilityPrompt: View {
    let loadCachedApps: () -> Void
    let refreshApps: (Bool) -> Void
    private let accentStart = Color(red: 0.10, green: 0.38, blue: 0.56)
    private let accentEnd = Color(red: 0.13, green: 0.25, blue: 0.45)

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentStart, accentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(accentGradient)

            Text("Grant Access")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .foregroundStyle(accentGradient)
                        .frame(width: 20)
                    Text("No screen recording.")
                }
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(accentGradient)
                        .frame(width: 20)
                    Text("No screenshots.")
                }
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(accentGradient)
                        .frame(width: 20)
                    Text("No data collected.")
                }
            }
            .font(.callout)

            HStack(spacing: 12) {
                Button("Open Accessibility Settings") {
                    _ = AccessibilityService.shared.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentStart)

                Button("Try Again") {
                    loadCachedApps()
                    refreshApps(true)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
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
