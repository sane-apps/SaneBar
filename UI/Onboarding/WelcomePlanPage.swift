import AppKit
import SaneUI
import SwiftUI

// MARK: - Page 7: Plan / Upgrade

struct FreeVsProPage: View {
    @ObservedObject private var licenseService: LicenseService
    @State private var outboundActionInFlight = false

    init(selectedTier _: Binding<Tier>, licenseService: LicenseService = .shared) {
        self.licenseService = licenseService
    }

    var body: some View {
        VStack(spacing: 10) {
            supportAppealView(title: licenseService.hasLegacyPaidUnlock ? "Thank You for Supporting SaneBar" : "SaneBar is Open Source")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Open Source Support

    private func supportAppealView(title: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 2)

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(saneAccentGradient)

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            if licenseService.hasLegacyPaidUnlock {
                VStack(spacing: 8) {
                    Text("You already supported SaneBar with a paid license.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("SaneBar is now fully open source and free for everyone. No donation is needed from you.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    Text("Thank you for helping make SaneApps possible.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
            } else {
                VStack(spacing: 8) {
                    Text("Mr. Sane here. I need to share an insane stat with you all.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Across SaneApps Mac apps, there have been over 100,000 downloads in the last 180 days. Fewer than 0.5% resulted in a purchase.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    Text("Despite the many kind reviews and steady downloads, that is not sustainable.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)

                    VStack(spacing: 2) {
                        Text("\"The worker is worthy of his wages.\"")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .italic()

                        Text("1 Timothy 5:18")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("SaneBar is fully open source and free to use. If you love what I do and believe in privacy-first Mac apps, here's how you can help.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    Text("Sincerely,\nMr. Sane")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
            }

            if !licenseService.hasLegacyPaidUnlock {
                Button {
                    runSingleOutboundAction {
                        NSWorkspace.shared.open(LicenseService.donationURL())
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.pink)
                        Text("Donate")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 10, horizontalPadding: 18, verticalPadding: 9))
                .disabled(outboundActionInFlight)
            }

            Text("This does not lock SaneBar. The app remains free.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 2)
        }
    }

    private func runSingleOutboundAction(_ action: @escaping () -> Void) {
        guard !outboundActionInFlight else { return }
        outboundActionInFlight = true
        action()
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                outboundActionInFlight = false
            }
        }
    }
}
