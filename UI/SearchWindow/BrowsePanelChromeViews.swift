import SaneUI
import SwiftUI

struct BrowseSearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.9))
            TextField(
                "Filter by name…",
                text: $text,
                prompt: Text("Filter by name…").foregroundStyle(.white.opacity(0.9))
            )
            .textFieldStyle(.plain)
            .font(.body)
            .focused(isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(SaneBarChrome.utilityFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}

struct BrowseFooter: View {
    let isRefreshing: Bool
    let filteredCount: Int
    let mode: BrowsePanelMode
    @Binding var showingHelp: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(filteredCount) \(countLabel)")
                .foregroundStyle(.white.opacity(0.9))

            Spacer()
            Button {
                showingHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .help("How Browse Icons works")
            .accessibilityLabel("Browse actions help")
            .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                BrowseHelpPopover()
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05))
    }

    private var countLabel: String {
        switch mode {
        case .hidden: "hidden"
        case .visible: "visible"
        case .alwaysHidden: "always hidden"
        case .all: "icons"
        }
    }
}

struct BrowseHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Browse Icons works")
                .font(.system(size: 13, weight: .semibold))
            Text("1. Use the tabs to browse each row.")
            Text("2. Click an icon to open it.")
            Text("3. Drag an icon and drop it on a glowing tab to move it.")
            Text("4. Right-click an icon for more actions.")
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }
}

struct BrowseAccessibilityPrompt: View {
    let accentHighlight: Color
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            SaneBarChrome.accentHighlight,
                            SaneBarChrome.accentStart.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Grant Access")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.97))

            VStack(alignment: .leading, spacing: 10) {
                privacyRow(icon: "video.slash.fill", text: "No screen recording.")
                privacyRow(icon: "eye.slash.fill", text: "No screenshots.")
                privacyRow(icon: "icloud.slash", text: "No data collected.")
            }
            .font(.system(size: 17, weight: .medium))
            .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button("Open Accessibility Settings", action: openSettings)
                    .buttonStyle(ChromeActionButtonStyle(prominent: true))

                Button("Try Again", action: retry)
                    .buttonStyle(ChromeActionButtonStyle())
            }
        }
        .padding(20)
        .background(
            ChromeGlassRoundedBackground(
                cornerRadius: 14,
                tint: SaneBarChrome.panelTint,
                tintStrength: 0.14,
                shadowOpacity: 0.14,
                shadowRadius: 8,
                shadowY: 3
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SaneBarChrome.rowStroke, lineWidth: 0.8)
        )
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(accentHighlight)
                .frame(width: 20)
            Text(text)
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

struct BrowseScanningState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning menu bar icons…")
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BrowseEmptyState: View {
    let mode: BrowsePanelMode
    let accentHighlight: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(accentHighlight)

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

    private var title: String {
        switch mode {
        case .hidden: "No hidden icons"
        case .visible: "No visible icons"
        case .alwaysHidden: "No always hidden icons"
        case .all: "No menu bar icons"
        }
    }

    private var subtitle: String {
        switch mode {
        case .hidden:
            "All your menu bar icons are visible.\nUse ⌘-drag to hide icons left of the separator."
        case .visible:
            "All your menu bar icons are hidden.\nUse ⌘-drag to show icons right of the separator."
        case .alwaysHidden:
            "Nothing is in the always-hidden zone.\nDrag an icon onto the glowing Always Hidden tab or use the context menu."
        case .all:
            "Try Refresh, or grant Accessibility permission."
        }
    }
}

struct BrowseNoMatchState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.9))

            Text("No matches for \(searchText)")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BrowseCrowdedVisibleHintToast: View {
    let accentHighlight: Color
    let dismiss: () -> Void
    let enableSecondMenuBar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "rectangle.tophalf.inset.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentHighlight)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("The menu bar is getting crowded.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                    Text("Some Visible icons may still get squeezed off-screen. Second Menu Bar works better for crowded setups.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button("OK", action: dismiss)
                    .buttonStyle(ChromeActionButtonStyle())

                Button("Enable", action: enableSecondMenuBar)
                    .buttonStyle(ChromeActionButtonStyle(prominent: true))
            }
        }
        .padding(12)
        .background(
            ChromeGlassRoundedBackground(
                cornerRadius: 14,
                tint: SaneBarChrome.controlNavyDeep,
                edgeTint: SaneBarChrome.accentTeal,
                tintStrength: 0.18,
                glowOpacity: 0.10,
                shadowOpacity: 0.18,
                shadowRadius: 12,
                shadowY: 6
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SaneBarChrome.rowStroke, lineWidth: 0.9)
        )
    }
}
