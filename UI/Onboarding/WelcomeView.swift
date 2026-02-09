import AppKit
import SwiftUI

/// Welcome onboarding view shown on first launch
/// Structure: Welcome → How It Works → Your Style → Permissions → Sane Promise
public struct WelcomeView: View {
    @State private var currentPage = 0
    @State private var navigateForward = true
    let onComplete: () -> Void
    private let totalPages = 5

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Animated page content
            ZStack {
                Group {
                    switch currentPage {
                    case 0: WelcomeActionPage()
                    case 1: ArrangeIconsPage()
                    case 2: SetupStylePage()
                    case 3: PermissionsPage()
                    case 4: SanePromisePage()
                    default: WelcomeActionPage()
                    }
                }
                .id(currentPage)
                .transition(.asymmetric(
                    insertion: .move(edge: navigateForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: navigateForward ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Progress bar
            HStack(spacing: 4) {
                ForEach(0 ..< totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentPage ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 16)

            // Bottom Controls
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        navigateForward = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.7))
                    .font(.system(size: 14))
                }

                Spacer()

                if currentPage < totalPages - 1 {
                    Button("Next") {
                        navigateForward = true
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
    }
}

// MARK: - Background

private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.indigo.opacity(0.05),
                    Color.blue.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Page 1: Welcome + Import Detection

private struct WelcomeActionPage: View {
    @State private var isHidden = false
    @State private var detectedCompetitor: String?
    @State private var importResult: String?

    var body: some View {
        VStack(spacing: 28) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 90, height: 90)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            }

            Text("Welcome to SaneBar")
                .font(.system(size: 32, weight: .bold))

            Text("One click to hide. One click to reveal.")
                .font(.system(size: 18))
                .foregroundStyle(.primary.opacity(0.7))

            // Menu bar simulation
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Text("🔐  💬  🎵  ☁️")
                            .font(.system(size: 18))

                        Text("/")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .opacity(isHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: isHidden)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { isHidden.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 15, weight: .semibold))
                            Text("try it")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Text("⏱")
                        .font(.system(size: 18))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.9))
                )

                Text(isHidden ? "Hidden! Tap again to reveal." : " ")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(height: 18)
            }

            // Import detection banner
            if let competitor = detectedCompetitor {
                importBanner(competitor)
            }
        }
        .padding(36)
        .onAppear { detectCompetitor() }
    }

    @ViewBuilder
    private func importBanner(_ competitor: String) -> some View {
        if let result = importResult {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(result)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 20)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.arrow.left.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Switching from \(competitor)?")
                    .font(.system(size: 13))
                Button("Import Settings") {
                    performImport(competitor)
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 20)
        }
    }

    private func detectCompetitor() {
        let fm = FileManager.default
        let prefs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let bartenderPlists = [
            "com.surteesstudios.Bartender-setapp.plist",
            "com.surteesstudios.Bartender-4.plist",
            "com.surteesstudios.Bartender.plist"
        ]
        for plist in bartenderPlists {
            if fm.fileExists(atPath: prefs.appendingPathComponent(plist).path) {
                detectedCompetitor = "Bartender"
                return
            }
        }
        if fm.fileExists(atPath: prefs.appendingPathComponent("com.jordanbaird.Ice.plist").path) {
            detectedCompetitor = "Ice"
        }
    }

    private func performImport(_ competitor: String) {
        let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let manager = MenuBarManager.shared

        if competitor == "Ice" {
            let url = prefs.appendingPathComponent("com.jordanbaird.Ice.plist")
            do {
                let summary = try IceImportService.importSettings(from: url, menuBarManager: manager)
                importResult = "Imported \(summary.applied.count) settings from Ice"
            } catch {
                importResult = "Import available in Settings → General → Data"
            }
        } else {
            // Bartender import is async — just point to settings
            importResult = "Import available in Settings → General → Data"
        }
    }
}

// MARK: - Page 2: How It Works

private struct ArrangeIconsPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("How It Works")
                .font(.system(size: 26, weight: .bold))

            VStack(alignment: .leading, spacing: 14) {
                iconRow("/", bg: Color.primary.opacity(0.1), title: "The Separator",
                        desc: "Everything to the LEFT of this hides when you click.")

                iconRow("line.3.horizontal.decrease", bg: Color.accentColor, title: "The SaneBar Icon",
                        desc: "Click to hide/reveal. Everything to the RIGHT stays visible.", isSF: true)

                iconRow("eye.slash", bg: Color.purple.opacity(0.6), title: "Always-Hidden Section",
                        desc: "A second separator for icons that stay hidden even when you reveal the rest.", isSF: true)

                iconRow("command", bg: Color.orange.opacity(0.6), title: "Rearrange Anytime",
                        desc: "Hold ⌘ and drag any icon to move it between zones.", isSF: true)
            }
            .padding(.horizontal, 40)

            // Zone diagram
            HStack(spacing: 4) {
                zonePill("Always hidden", Color.red.opacity(0.2))
                Text("/").font(.system(size: 14, weight: .medium)).foregroundStyle(.primary.opacity(0.7))
                zonePill("Hidden", Color.orange.opacity(0.3))
                Text("/").font(.system(size: 14, weight: .medium)).foregroundStyle(.primary.opacity(0.7))
                zonePill("Visible", Color.green.opacity(0.3))
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white).padding(4)
                    .background(Color.accentColor).cornerRadius(4)
                zonePill("Visible", Color.green.opacity(0.3))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private func iconRow(_ symbol: String, bg: Color, title: String, desc: String, isSF: Bool = false) -> some View {
        HStack(spacing: 12) {
            Group {
                if isSF {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text(symbol)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(bg)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(desc).font(.system(size: 13)).foregroundStyle(.primary)
            }
        }
    }

    private func zonePill(_ label: String, _ bg: Color) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(bg).cornerRadius(5)
    }
}

// MARK: - Page 4: Permissions & Gestures

private struct PermissionsPage: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var accessibilityService = AccessibilityService.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Smart Gestures")
                    .font(.system(size: 28, weight: .bold))
                Text("Optional ways to reveal your icons.")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.7))
            }

            VStack(spacing: 14) {
                GestureToggleRow(
                    icon: "scroll", title: "Scroll to Show",
                    description: "Scroll up on the menu bar to reveal icons.",
                    isOn: $menuBarManager.settings.showOnScroll
                )
                GestureToggleRow(
                    icon: "hand.point.up.left", title: "Hover to Show",
                    description: "Hover over the menu bar to reveal icons.",
                    isOn: $menuBarManager.settings.showOnHover
                )
            }
            .padding(.horizontal, 40)

            VStack(spacing: 10) {
                Text("These gestures and Find Icon need Accessibility permission.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

                if accessibilityService.isGranted {
                    Label("Permission Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14, weight: .medium))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button("Enable Accessibility Access") {
                        accessibilityService.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
    }
}

private struct GestureToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(description).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.7))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Page 5: Sane Promise

private struct SanePromisePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Our Sane Philosophy")
                .font(.system(size: 32, weight: .bold))

            VStack(spacing: 8) {
                Text("\"For God has not given us a spirit of fear,")
                    .font(.system(size: 17)).italic()
                Text("but of power and of love and of a sound mind.\"")
                    .font(.system(size: 17)).italic()
                Text("— 2 Timothy 1:7")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
            }

            HStack(spacing: 20) {
                PillarCard(icon: "bolt.fill", color: .yellow, title: "Power",
                           description: "Your data stays on your device. No cloud, no tracking.")
                PillarCard(icon: "heart.fill", color: .pink, title: "Love",
                           description: "Built to serve you. No dark patterns or manipulation.")
                PillarCard(icon: "brain.head.profile", color: .purple, title: "Sound Mind",
                           description: "Calm, focused design. No clutter or anxiety.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .padding(32)
    }
}

private struct PillarCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(12)
    }
}

#Preview {
    WelcomeView(onComplete: {})
}
