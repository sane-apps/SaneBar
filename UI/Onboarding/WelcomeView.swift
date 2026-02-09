import AppKit
import SwiftUI

/// Welcome onboarding view shown on first launch
/// Structure: Welcome → How It Works → Power Features → Permissions → Sane Promise
/// Reference: SaneApps-Brand-Guidelines.md
public struct WelcomeView: View {
    @State private var currentPage = 0
    let onComplete: () -> Void
    private let totalPages = 5

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0:
                    WelcomeActionPage()
                case 1:
                    ArrangeIconsPage()
                case 2:
                    PowerFeaturesPage()
                case 3:
                    PermissionsPage()
                case 4:
                    SanePromisePage()
                default:
                    WelcomeActionPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Page indicators
            HStack(spacing: 8) {
                ForEach(0 ..< totalPages, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.accentColor : Color.primary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 20)

            // Bottom Controls
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .font(.system(size: 15))
                }

                Spacer()

                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation {
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

// MARK: - Page 1: Welcome + The Action

private struct WelcomeActionPage: View {
    @State private var isHidden = false

    var body: some View {
        VStack(spacing: 32) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            }

            Text("Welcome to SaneBar")
                .font(.system(size: 32, weight: .bold))

            Text("One click to hide. One click to reveal.")
                .font(.system(size: 20))

            // Menu bar simulation
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Hidden icons (fade out together)
                    HStack(spacing: 12) {
                        Text("🔐  💬  🎵  ☁️")
                            .font(.system(size: 20))

                        Text("/")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .opacity(isHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: isHidden)

                    // SaneBar button - HIGHLIGHTED so it's obvious
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { isHidden.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 16, weight: .semibold))
                            Text("👈 tap")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // ONE icon to the right (Control Center style)
                    Text("⏱")
                        .font(.system(size: 20))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.9))
                )

                // Status below
                Text(isHidden ? "✅ Hidden! Tap again to reveal." : "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(height: 20)
            }
            .padding(.top, 8)
        }
        .padding(40)
    }
}

// MARK: - Page 2: How It Works

private struct ArrangeIconsPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("How It Works")
                .font(.system(size: 26, weight: .bold))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("/")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Separator")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Everything to the LEFT of this hides when you click.")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("The SaneBar Icon")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Click to hide/reveal. Everything to the RIGHT stays visible.")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.purple.opacity(0.6))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always-Hidden Section")
                            .font(.system(size: 15, weight: .semibold))
                        Text("A second separator for icons that stay hidden even when you reveal the rest.")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.6))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rearrange Anytime")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Hold ⌘ and drag any icon to move it between zones.")
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("In your menu bar:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Always hidden")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(5)

                    Text("/")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Hidden")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.3))
                        .cornerRadius(5)

                    Text("/")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Visible")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(5)

                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.accentColor)
                        .cornerRadius(4)

                    Text("Visible")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(5)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }
}

// MARK: - Page 3: Power Features

private struct PowerFeaturesPage: View {
    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)

            Text("Power Features")
                .font(.system(size: 28, weight: .bold))

            VStack(spacing: 20) {
                FeatureCard(
                    icon: "magnifyingglass",
                    color: .blue,
                    title: "⌘+Shift+Space",
                    subtitle: "Power Search",
                    description: "Find any icon instantly — even ones hidden behind the notch"
                )

                FeatureCard(
                    icon: "touchid",
                    color: .pink,
                    title: "Touch ID Lock",
                    subtitle: "Biometric Security",
                    description: "Lock your hidden icons behind Touch ID for presentations"
                )

                FeatureCard(
                    icon: "cursorarrow.click.2",
                    color: .purple,
                    title: "Right-Click Menu",
                    subtitle: "Quick Actions",
                    description: "Right-click any icon to move it between zones instantly"
                )
            }
        }
        .padding(32)
    }
}

private struct FeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                }
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
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
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                GestureToggleRow(
                    icon: "scroll",
                    title: "Scroll to Show",
                    description: "Scroll up on the menu bar to reveal icons.",
                    isOn: $menuBarManager.settings.showOnScroll
                )

                GestureToggleRow(
                    icon: "hand.point.up.left",
                    title: "Hover to Show",
                    description: "Hover over the menu bar to reveal icons.",
                    isOn: $menuBarManager.settings.showOnHover
                )
            }
            .padding(.horizontal, 40)

            VStack(spacing: 10) {
                Text("These gestures and the Find Icon feature need Accessibility permission.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

                if accessibilityService.isGranted {
                    Label("Permission Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14, weight: .medium))
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
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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

// MARK: - Page 5: Our Sane Promise

private struct SanePromisePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Our Sane Philosophy")
                .font(.system(size: 32, weight: .bold))

            VStack(spacing: 8) {
                Text("\"For God has not given us a spirit of fear,")
                    .font(.system(size: 17))
                    .italic()
                Text("but of power and of love and of a sound mind.\"")
                    .font(.system(size: 17))
                    .italic()
                Text("— 2 Timothy 1:7")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
            }

            HStack(spacing: 20) {
                PillarCard(
                    icon: "bolt.fill",
                    color: .yellow,
                    title: "Power",
                    description: "Your data stays on your device. No cloud, no tracking."
                )

                PillarCard(
                    icon: "heart.fill",
                    color: .pink,
                    title: "Love",
                    description: "Built to serve you. No dark patterns or manipulation."
                )

                PillarCard(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "Sound Mind",
                    description: "Calm, focused design. No clutter or anxiety."
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .padding(32)
    }
}

// MARK: - Helper Views

private struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            Text(LocalizedStringKey(text))
                .font(.system(size: 15))
        }
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
