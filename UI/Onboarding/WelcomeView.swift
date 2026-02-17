import AppKit
import SwiftUI

// Onboarding palette: teal accent, navy cards
private let cardBg = Color(red: 0.08, green: 0.10, blue: 0.18)
private let navyBg = Color(red: 0.06, green: 0.08, blue: 0.16)
private enum Tier { case free, pro }

/// Welcome onboarding view shown on first launch
/// Structure: Welcome → Browse Icons → Sane Promise → Permission → Free vs Pro
public struct WelcomeView: View {
    @State private var currentPage = 0
    @State private var navigateForward = true
    @State private var selectedTier: Tier = .pro
    let onComplete: () -> Void
    private let totalPages = 7

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
                    case 1: DontSkipPage()
                    case 2: BrowseIconsPage()
                    case 3: ChooseViewPage()
                    case 4: SanePromisePage()
                    case 5: PermissionPage()
                    case 6: FreeVsProPage(selectedTier: $selectedTier)
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
                        .fill(index <= currentPage ? Color.teal : Color.white.opacity(0.15))
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
                    .foregroundStyle(.white.opacity(0.9))
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
                    .tint(Color.teal)
                } else {
                    Button("Get Started") {
                        if selectedTier == .pro, !LicenseService.shared.isPro {
                            NSWorkspace.shared.open(LicenseService.checkoutURL)
                        }
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.teal)
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

            // Radial glow (matches website hero)
            RadialGradient(
                colors: [Color.teal.opacity(0.12), Color.clear],
                center: .top,
                startRadius: 50,
                endRadius: 400
            )

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.06),
                    Color.indigo.opacity(0.04),
                    Color.clear
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
        VStack(spacing: 20) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            }

            Text("Welcome to SaneBar")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            (Text("One click to ") + Text("hide").foregroundColor(.teal) + Text(". One click to ") + Text("reveal").foregroundColor(.teal) + Text("."))
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.9))

            // Menu bar simulation — bar stays same size, icons fade in/out
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Icons + divider — fade only, no size change
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                        Image(systemName: "bubble.left.fill")
                        Image(systemName: "headphones")
                        Image(systemName: "cloud.fill")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .opacity(isHidden ? 0 : 1)

                    Text("/")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .opacity(isHidden ? 0 : 1)

                    // SaneBar button — always visible
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { isHidden.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 14, weight: .semibold))
                            Text("CLICK!")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.teal)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(navyBg)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Control Center — always visible
                    Image(systemName: "switch.2")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                .animation(.easeInOut(duration: 0.3), value: isHidden)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.85))
                )

                Group {
                    if isHidden {
                        Text("Hidden! Click again to reveal.")
                            .foregroundStyle(.white)
                    } else {
                        Text("Tip").foregroundColor(.teal).bold() + Text(": ⌘ + drag icons in your menu bar to rearrange").foregroundColor(.white)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .frame(height: 18)
            }

            // Import detection banner
            if let competitor = detectedCompetitor {
                importBanner(competitor)
            }
        }
        .padding(32)
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
                    .foregroundStyle(Color.teal)
                Text("Switching from \(competitor)?")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                Button("Import Settings") {
                    performImport(competitor)
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(Color.teal)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.teal.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.teal.opacity(0.2), lineWidth: 1)
                    )
            )
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
        for plist in bartenderPlists where fm.fileExists(atPath: prefs.appendingPathComponent(plist).path) {
            detectedCompetitor = "Bartender"
            return
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

// MARK: - Page 1: Don't Skip

private struct DontSkipPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.wave.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.teal)

            Text("Don't skip this.")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            Text("It's only a few screens and you'll be\nconfused if you rush through.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("— Mr. Sane")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.9))

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Page 2: Browse Icons

private struct BrowseIconsPage: View {
    var body: some View {
        VStack(spacing: 10) {
            (Text("Browse").foregroundColor(.teal) + Text(" Your Icons — Two Options"))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            Text("Open with ⌘ Shift Space or right-click the SaneBar icon")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))

            HStack(alignment: .center, spacing: 16) {
                // Icon Panel
                VStack(spacing: 4) {
                    Text("Icon Panel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Image("OnboardingIconPanel")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    Text("Grid view with search")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)

                // Second Menu Bar
                VStack(spacing: 4) {
                    Text("Second Menu Bar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Image("OnboardingSecondMenuBar")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    Text("Compact strip below menu bar")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 220)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Page 3: Choose Your View

private struct ChooseViewPage: View {
    var body: some View {
        VStack(spacing: 10) {
            (Text("Choose").foregroundColor(.teal) + Text(" Your View"))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            Text("Settings → General → Browse Icons")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Image("OnboardingBrowseSettings")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - Page 4: Permission

private struct PermissionPage: View {
    @ObservedObject private var accessibilityService = AccessibilityService.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.teal)

            Text("Grant Access")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.teal)
                        .frame(width: 28)
                    Text("No screen recording.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.teal)
                        .frame(width: 28)
                    Text("No screenshots.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.teal)
                        .frame(width: 28)
                    Text("No data collected.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            if accessibilityService.isGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Permission granted — you're all set!")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .padding(.top, 8)
            } else {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 14))
                        Text("Grant Accessibility")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.teal)
                .controlSize(.large)

                Text("Toggle SaneBar on in the list that appears")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Page 5: Free vs Pro

private struct FreeVsProPage: View {
    @ObservedObject private var licenseService = LicenseService.shared
    @Binding var selectedTier: Tier
    @State private var showingLicenseEntry = false

    var body: some View {
        VStack(spacing: 10) {
            if licenseService.isEarlyAdopter {
                earlyAdopterView()
            } else if licenseService.isPro {
                proActivatedView()
            } else {
                selectionView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingLicenseEntry) {
            LicenseEntryView()
        }
    }

    // MARK: - Early Adopter (upgrade from pre-Pro version)

    @ViewBuilder
    private func earlyAdopterView() -> some View {
        Spacer()

        Image(systemName: "gift.fill")
            .font(.system(size: 44))
            .foregroundStyle(Color.teal)

        Text("Welcome Back!")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        Text("Thank you for being an early adopter.\nYou have lifetime Pro access — on me.")
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("Pro Activated")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
        }
        .padding(.top, 8)

        Text("All features unlocked.")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.9))

        Button {
            NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/MrSaneApps")!)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                (Text("If you love it, consider ").foregroundColor(.white) +
                    Text("sponsoring me").foregroundColor(.teal).underline())
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.teal.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 12)

        Spacer()
    }

    // MARK: - Already Pro (purchased or activated)

    @ViewBuilder
    private func proActivatedView() -> some View {
        Spacer()

        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 44))
            .foregroundStyle(.green)

        Text("Pro Activated")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        Text("All features unlocked.\nI couldn't do this without you.")
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        Text("— Mr. Sane")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 2)

        Spacer()
    }

    // MARK: - Free vs Pro Selection (new users)

    @ViewBuilder
    private func selectionView() -> some View {
        (Text("Choose").foregroundColor(.teal) + Text(" Your Plan"))
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        // Selectable tier cards — Pro first (left), Free second (right)
        HStack(alignment: .top, spacing: 14) {
            selectableTierCard(
                tier: .pro,
                title: "Pro — $6.99",
                price: "One-time — yours forever",
                features: [
                    ("checkmark", "Everything in Free, plus:"),
                    ("cursorarrow.click", "Activate & move icons"),
                    ("lock.fill", "Always Hidden zone"),
                    ("touchid", "Touch ID / password lock"),
                    ("hand.point.up", "Gestures: hover & scroll"),
                    ("paintpalette.fill", "Custom icon & appearance"),
                    ("ruler", "Icon spacing control"),
                    ("bolt.fill", "Triggers & profiles"),
                    ("arrow.down.doc", "Import from Bartender / Ice"),
                    ("applescript", "AppleScript automation"),
                    ("keyboard", "Per-icon hotkeys & shortcuts")
                ],
                actions: {
                    AnyView(VStack(spacing: 6) {
                        Button {
                            NSWorkspace.shared.open(LicenseService.checkoutURL)
                        } label: {
                            Text("Unlock Pro")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.teal)
                        .controlSize(.regular)

                        Button("I Have a Key") {
                            showingLicenseEntry = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 12))
                    })
                }
            )

            selectableTierCard(
                tier: .free,
                title: "Basic",
                price: "Free, forever",
                features: [
                    ("line.3.horizontal.decrease", "Click to hide / show"),
                    ("arrow.left.arrow.right", "⌘ + drag to rearrange"),
                    ("magnifyingglass", "Browse & search icons"),
                    ("timer", "Auto-rehide"),
                    ("keyboard", "Toggle & search shortcuts")
                ]
            )
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Selectable Tier Card

    @ViewBuilder
    private func selectableTierCard(tier: Tier, title: String, price: String? = nil, features: [(String, String)], actions: (() -> AnyView)? = nil) -> some View {
        let isSelected = selectedTier == tier
        let isPro = tier == .pro

        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isPro ? Color.teal : .white)
                    if let price {
                        Text(price)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? (isPro ? Color.teal : .white) : .white.opacity(0.9))
            }

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(features, id: \.1) { icon, text in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(isPro ? Color.teal : .white)
                            .frame(width: 14)
                        Text(text)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let actions {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.top, 4)

                actions()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBg)
                .shadow(color: isSelected ? Color.teal.opacity(0.15) : .clear, radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected
                        ? (isPro ? Color.teal : Color.white.opacity(0.8))
                        : Color.teal.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTier = tier
            }
        }
    }
}

// MARK: - Page 4: Sane Promise

private struct SanePromisePage: View {
    var body: some View {
        VStack(spacing: 20) {
            (Text("Why").foregroundColor(.teal) + Text(" SaneBar?"))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text("\"For God has not given us a spirit of fear,")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.white)
                (Text("but of ").foregroundColor(.white) +
                    Text("power").foregroundColor(.yellow) +
                    Text(" and of ").foregroundColor(.white) +
                    Text("love").foregroundColor(.red) +
                    Text(" and of a ").foregroundColor(.white) +
                    Text("sound mind").foregroundColor(.cyan) +
                    Text(".\"").foregroundColor(.white))
                    .font(.system(size: 15, design: .serif))
                Text("— 2 Timothy 1:7")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 14) {
                PillarCard(
                    icon: "bolt.fill", color: .yellow, title: "Power",
                    lines: ["Your data stays on your device.", "100% transparent code.", "Actively maintained."]
                )
                PillarCard(
                    icon: "heart.fill", color: .red, title: "Love",
                    lines: ["Built to serve you.", "Pay once, yours forever.", "No subscriptions."]
                )
                PillarCard(
                    icon: "brain.head.profile", color: .cyan, title: "Sound Mind",
                    lines: ["Calm and focused.", "Does one thing well.", "No clutter."]
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

private struct PillarCard: View {
    let icon: String
    let color: Color
    let title: String
    let lines: [String]

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(width: 12)
                            .padding(.top, 2)
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.teal.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.teal.opacity(0.1), radius: 8, x: 0, y: 3)
        )
    }
}

#Preview("Page 0 - Welcome") {
    WelcomeView(onComplete: {})
}

#Preview("Page 1 - Choose View") {
    ChooseViewPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 2 - Browse Icons") {
    BrowseIconsPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 3 - Philosophy") {
    SanePromisePage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 4 - Permission") {
    PermissionPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 5 - Free vs Pro") {
    FreeVsProPage(selectedTier: .constant(.pro))
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 5 - Early Adopter") {
    FreeVsProPage(selectedTier: .constant(.pro))
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
        .onAppear { LicenseService.shared.grantEarlyAdopterPro() }
}
