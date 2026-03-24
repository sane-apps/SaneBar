// swiftlint:disable file_length
import AppKit
import SaneUI
import SwiftUI

// Onboarding palette: softened SaneUI teal accents + navy cards
private let cardBg = Color(red: 0.08, green: 0.10, blue: 0.18)
private let navyBg = Color(red: 0.06, green: 0.08, blue: 0.16)
private let saneAccentDeep = Color.saneAccentDeep
private let saneAccent = Color.saneAccent
private let saneAccentSoft = Color.saneAccentSoft
private let saneAccentGradient = LinearGradient(
    colors: [saneAccentSoft, saneAccent],
    startPoint: .leading,
    endPoint: .trailing
)
private let saneButtonGradient = LinearGradient(
    colors: [saneAccentSoft.opacity(0.98), saneAccent.opacity(0.98)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
private enum Tier { case free, pro }

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(cornerRadius: CGFloat = 9, horizontalPadding: CGFloat = 16, verticalPadding: CGFloat = 8) {
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(saneButtonGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
            )
            .shadow(
                color: saneAccentDeep.opacity(configuration.isPressed ? 0.20 : 0.30),
                radius: configuration.isPressed ? 3 : 8,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Welcome onboarding view shown on first launch.
/// Canonical structure: Welcome → Don't Skip → Core Workflow → Advanced Workflow →
/// Sane Philosophy → Permissions → Plan / Upgrade
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
                    case 3: ZoneGuidePage()
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
                        .fill(index <= currentPage ? saneAccent : Color.white.opacity(0.15))
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
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } else {
                    Button("Get Started") {
                        if selectedTier == .pro, !LicenseService.shared.isPro {
                            if LicenseService.shared.usesAppStorePurchase {
                                Task { await LicenseService.shared.purchasePro() }
                            } else if LicenseService.shared.usesSetappDistribution {
                                onComplete()
                                return
                            } else {
                                NSWorkspace.shared.open(LicenseService.checkoutURL())
                            }
                        }
                        onComplete()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 10, horizontalPadding: 20, verticalPadding: 9))
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
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow, isEmphasized: true)

            // Radial glow (matches website hero)
            RadialGradient(
                colors: [saneAccentDeep.opacity(0.14), Color.clear],
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
    @State private var detectedCompetitorPlistURL: URL?
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

            (Text("One click to ") + Text("hide").foregroundColor(saneAccentSoft) + Text(". One click to ") + Text("reveal").foregroundColor(saneAccentSoft) + Text("."))
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
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(saneAccentSoft)
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
                        Text("Tip").foregroundColor(saneAccentSoft).bold() + Text(": ⌘ + drag icons in your menu bar to rearrange").foregroundColor(.white)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.arrow.left.circle.fill")
                        .foregroundStyle(saneAccent)
                    Text("Switching from \(competitor)?")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                    Button(competitor == "Bartender" ? "Import Layout" : "Import Settings") {
                        performImport(competitor)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(saneAccent)
                    .controlSize(.small)
                }

                if competitor == "Ice" {
                    Text("SaneBar can import your Ice settings here, but Ice does not store icon positions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("SaneBar can import your Bartender layout and matching settings from the detected plist.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(saneAccentDeep.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(saneAccent.opacity(0.28), lineWidth: 1)
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
            detectedCompetitorPlistURL = prefs.appendingPathComponent(plist)
            return
        }
        if fm.fileExists(atPath: prefs.appendingPathComponent("com.jordanbaird.Ice.plist").path) {
            detectedCompetitor = "Ice"
            detectedCompetitorPlistURL = prefs.appendingPathComponent("com.jordanbaird.Ice.plist")
        }
    }

    private func performImport(_ competitor: String) {
        let manager = MenuBarManager.shared

        if competitor == "Ice" {
            guard let url = detectedCompetitorPlistURL else {
                importResult = "Import available in Settings → General → Data"
                return
            }
            do {
                let summary = try IceImportService.importSettings(from: url, menuBarManager: manager)
                importResult = "Imported \(summary.applied.count) settings from Ice"
            } catch {
                importResult = "Import available in Settings → General → Data"
            }
        } else {
            guard let url = detectedCompetitorPlistURL else {
                importResult = "Import available in Settings → General → Data"
                return
            }
            Task { @MainActor in
                do {
                    let summary = try await BartenderImportService.importSettings(from: url, menuBarManager: manager)
                    importResult = "Imported Bartender layout (\(summary.totalMoved) icons moved)"
                } catch {
                    importResult = "Import available in Settings → General → Data"
                }
            }
        }
    }
}

// MARK: - Page 2: Don't Skip

private struct DontSkipPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.wave.fill")
                .font(.system(size: 48))
                .foregroundStyle(saneAccent)

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

// MARK: - Page 3: Core Workflow

private struct BrowseIconsPage: View {
    var body: some View {
        VStack(spacing: 13) {
            (Text("Core ").foregroundStyle(.white) + Text("Workflow").foregroundStyle(saneAccentGradient))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            Text("Open with ⌘⇧Space, then browse icons in either layout.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 18) {
                // Icon Panel
                VStack(spacing: 6) {
                    Text("Icon Panel")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Image("OnboardingIconPanel")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    Text("Grid view for browsing and organizing icons.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                // Second Menu Bar
                VStack(spacing: 6) {
                    Text("Second Menu Bar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Image("OnboardingSecondMenuBar")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                    Text("Compact strip below the menu bar for quick organization.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Page 4: Advanced Workflow

private struct ZoneGuidePage: View {
    private struct ZoneRow {
        let title: String
        let detail: String
        let icon: String
        let accent: Color
    }

    private let rows: [ZoneRow] = [
        ZoneRow(
            title: "Visible",
            detail: "Stays shown in your menu bar.",
            icon: "checkmark.circle.fill",
            accent: saneAccentSoft
        ),
        ZoneRow(
            title: "Hidden",
            detail: "Shows when SaneBar is active.",
            icon: "eye.slash.fill",
            accent: .yellow.opacity(0.9)
        ),
        ZoneRow(
            title: "Always Hidden",
            detail: "Stays hidden even while revealing hidden icons.",
            icon: "lock.fill",
            accent: .orange.opacity(0.92)
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            (Text("Advanced ").foregroundStyle(.white) + Text("Workflow").foregroundStyle(saneAccentGradient))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Move icons between Visible, Hidden, and Always Hidden, and pick the browse style you like.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("• Icon Panel: browse and click icons. Pro lets you drag an icon onto the Visible, Hidden, or Always Hidden tab.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("• Second Menu Bar: browse and click icons in the Hidden and Visible rows. Pro lets you move icons between the Visible, Hidden, and Always Hidden rows.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("• In the macOS menu bar itself, rearranging uses ⌘ + drag.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("• Basic includes browsing and clicking. Pro adds icon moves, reordering, and Always Hidden.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Browse style")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Settings → General → Browse Icons. You can switch between Icon Panel and Second Menu Bar anytime.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)

                Image("OnboardingBrowseSettings")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.3), radius: 7, x: 0, y: 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: row.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(row.accent)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(row.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 16)
    }
}
// MARK: - Page 6: Permissions

private struct PermissionPage: View {
    @ObservedObject private var accessibilityService = AccessibilityService.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(saneAccent)

            Text("Grant Access")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(saneAccent)
                        .frame(width: 28)
                    Text("No screen recording.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(saneAccent)
                        .frame(width: 28)
                    Text("No screenshots.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(saneAccent)
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
                    _ = accessibilityService.openAccessibilitySettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 14))
                        Text("Open Accessibility Settings")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 10, horizontalPadding: 18, verticalPadding: 10))

                Text("Toggle SaneBar on in the list that appears")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Page 7: Plan / Upgrade

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
            .foregroundStyle(saneAccent)

        Text("Welcome Back!")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        Text("Thank you for being an early adopter.\nYou have lifetime Pro access — on me.")
            .font(.system(size: 15))
            .foregroundStyle(.white.opacity(0.92))
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
                    Text("sponsoring me").foregroundColor(saneAccentSoft).underline())
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(saneAccent.opacity(0.34), lineWidth: 1)
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
            .foregroundStyle(.white.opacity(0.92))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        Text("— Mr. Sane")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, 2)

        Spacer()
    }

    // MARK: - Basic vs Pro Selection (new users)

    @ViewBuilder
    private func selectionView() -> some View {
        (Text("Choose").foregroundStyle(saneAccentGradient) + Text(" Your Plan"))
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        // Selectable tier cards — Pro first (left), Basic second (right)
        HStack(alignment: .top, spacing: 14) {
            selectableTierCard(
                tier: .pro,
                title: licenseService.usesSetappDistribution ? "Pro — Setapp" : "Pro — $6.99",
                price: licenseService.usesSetappDistribution ? "Included with your Setapp install" : "One-time — yours forever",
                features: [
                    ("checkmark", "Everything in Basic, plus:"),
                    ("cursorarrow.click", "Activate & move icons"),
                    ("lock.fill", "Always Hidden"),
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
                        if licenseService.usesAppStorePurchase {
                            Button {
                                Task { await licenseService.purchasePro() }
                            } label: {
                                Text(licenseService.isPurchasing ? "Processing..." : "Unlock Pro")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 9, horizontalPadding: 14, verticalPadding: 7))
                            .disabled(licenseService.isPurchasing)

                            Button("Restore Purchases") {
                                Task { await licenseService.restorePurchases() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(.system(size: 13))
                            .disabled(licenseService.isPurchasing)
                        } else if licenseService.usesSetappDistribution {
                            Text("Managed by Setapp")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.82))
                        } else {
                            Button {
                                NSWorkspace.shared.open(LicenseService.checkoutURL())
                            } label: {
                                Text("Unlock Pro")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 9, horizontalPadding: 14, verticalPadding: 7))

                            Button(LicenseService.existingCustomerButtonLabel()) {
                                showingLicenseEntry = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(.system(size: 13))
                        }

                        if let purchaseError = licenseService.purchaseError {
                            Text(purchaseError)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    })
                }
            )

            selectableTierCard(
                tier: .free,
                title: "Basic",
                price: "$0 forever",
                features: [
                    ("line.3.horizontal.decrease", "Click to hide / show"),
                    ("cursorarrow.click", "Left-click to open icons"),
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
                        .foregroundStyle(isPro ? saneAccentSoft : .white)
                    if let price {
                        Text(price)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? (isPro ? saneAccentSoft : .white) : .white.opacity(0.9))
            }

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(features, id: \.1) { icon, text in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundStyle(isPro ? saneAccentSoft : .white)
                            .frame(width: 14)
                        Text(text)
                            .font(.system(size: 13))
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
                .shadow(color: isSelected ? saneAccent.opacity(0.18) : .clear, radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected
                        ? (isPro ? saneAccentSoft : Color.white.opacity(0.8))
                        : saneAccent.opacity(0.2),
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

// MARK: - Page 5: Sane Philosophy

private struct SanePromisePage: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Our Sane Philosophy")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text("\"For God has not given us a spirit of fear,")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.white)
                Text("but of power and of love and of a sound mind.\"")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.white)
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
                    lines: ["Built to serve you.", "Pay once, yours forever.", "No subscriptions. No ads."]
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.green)
                            .frame(width: 12)
                            .padding(.top, 2)
                        Text(line)
                            .font(.system(size: 13))
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
                        .stroke(saneAccent.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: saneAccentDeep.opacity(0.16), radius: 8, x: 0, y: 3)
        )
    }
}

#Preview("Page 0 - Welcome") {
    WelcomeView(onComplete: {})
}

#Preview("Page 3 - Core Workflow") {
    BrowseIconsPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 4 - Advanced Workflow") {
    ZoneGuidePage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 5 - Sane Philosophy") {
    SanePromisePage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 6 - Permissions") {
    PermissionPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 7 - Plan / Upgrade") {
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
// swiftlint:enable file_length
