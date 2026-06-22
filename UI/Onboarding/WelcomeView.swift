import AppKit
import SaneUI
import SwiftUI

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
                    Button(finalButtonLabel) {
                        if selectedTier == .pro,
                           !LicenseService.shared.isPro,
                           !LicenseService.shared.hasExpiredProTrial {
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

    private var finalButtonLabel: String {
        if !LicenseService.shared.isPro, LicenseService.shared.hasExpiredProTrial {
            return "Continue with Basic"
        }
        return "Get Started"
    }
}
