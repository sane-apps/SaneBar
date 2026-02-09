import SwiftUI

struct MenuBarSearchAccessibilityPrompt: View {
    let loadCachedApps: () -> Void
    let refreshApps: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Accessibility Permission Needed")
                .font(.headline)

            Text("SaneBar needs Accessibility access to see menu bar icons.\n\nA system dialog should have appeared. Enable SaneBar in System Settings, then try again.")
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.7))
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("Try Again") {
                    loadCachedApps()
                    refreshApps(true)
                }
                .buttonStyle(.borderedProminent)
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
                .foregroundStyle(.primary.opacity(0.7))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.5))
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
                .foregroundStyle(.primary.opacity(0.4))

            Text("No matches for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.7))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
