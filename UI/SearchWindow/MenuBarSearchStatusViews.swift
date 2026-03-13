import SwiftUI

struct MenuBarSearchAccessibilityPrompt: View {
    let loadCachedApps: () -> Void
    let refreshApps: (Bool) -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(SaneBarChrome.accentGradient)

            Text("Grant Access")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.97))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .foregroundStyle(SaneBarChrome.accentHighlight)
                        .frame(width: 20)
                    Text("No screen recording.")
                        .foregroundStyle(.white.opacity(0.92))
                }
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(SaneBarChrome.accentHighlight)
                        .frame(width: 20)
                    Text("No screenshots.")
                        .foregroundStyle(.white.opacity(0.92))
                }
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(SaneBarChrome.accentHighlight)
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
                .buttonStyle(ChromeActionButtonStyle(prominent: true))

                Button("Try Again") {
                    loadCachedApps()
                    refreshApps(true)
                }
                .buttonStyle(ChromeActionButtonStyle())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SaneBarChrome.softSurfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SaneBarChrome.rowStroke, lineWidth: 0.8)
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
                .foregroundStyle(SaneBarChrome.accentHighlight)

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
