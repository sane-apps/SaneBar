import AppKit
import SaneUI
import SwiftUI

// MARK: - Page 7: Plan / Upgrade

struct FreeVsProPage: View {
    @ObservedObject private var licenseService: LicenseService
    @Binding var selectedTier: Tier
    @State private var showingLicenseEntry = false
    @State private var outboundActionInFlight = false

    init(selectedTier: Binding<Tier>, licenseService: LicenseService = .shared) {
        _selectedTier = selectedTier
        self.licenseService = licenseService
    }

    private struct CompanionApp: Identifiable {
        let name: String
        let detail: String
        let url: URL

        var id: String { name }
    }

    var body: some View {
        VStack(spacing: 10) {
            if licenseService.isPro {
                proActivatedView()
            } else if licenseService.hasExpiredProTrial {
                expiredTrialView()
            } else {
                selectionView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingLicenseEntry) {
            LicenseEntryView(licenseService: SaneBarLicenseSettingsAdapter.shared)
        }
    }

    // MARK: - Already Pro (trial, purchased, or activated)

    @ViewBuilder
    private func proActivatedView() -> some View {
        Spacer()

        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 44))
            .foregroundStyle(.green)

        Text(licenseService.isProTrialActive ? "Enjoy Your Pro Trial" : "Pro Activated")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        Text(proActivatedMessage)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        if licenseService.isProTrialActive {
            Button("Keep Pro — \(licenseService.displayPriceLabel)") {
                runSingleOutboundAction {
                    NSWorkspace.shared.open(LicenseService.checkoutURL())
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 10, horizontalPadding: 18, verticalPadding: 9))
            .disabled(outboundActionInFlight)
            .padding(.top, 4)

            if shouldShowCompanionApps {
                companionAppsView
                    .padding(.top, 6)
            }
        } else {
            Text("— Mr. Sane")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, 2)
        }

        Spacer()
    }

    private var proActivatedMessage: String {
        if let days = licenseService.proTrialDaysRemaining {
            let dayText = days == 1 ? "1 day" : "\(days) days"
            return "\(dayText) of Pro is unlocked. No credit card required.\nBasic remains free after the trial."
        }
        return "All features unlocked.\nI couldn't do this without you."
    }

    @ViewBuilder
    private func expiredTrialView() -> some View {
        Spacer()

        Image(systemName: "clock.badge.exclamationmark.fill")
            .font(.system(size: 42))
            .foregroundStyle(saneAccentGradient)

        Text("Your Pro Trial Ended")
            .font(.system(size: 28, weight: .bold, design: .serif))
            .foregroundStyle(.white)

        Text("Basic is still free. Unlock Pro to keep the advanced tools you tried.")
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        HStack(alignment: .top, spacing: 12) {
            trialOutcomeCard(
                title: "Keep Pro",
                subtitle: "One-time — yours forever",
                features: [
                    ("cursorarrow.click", "Activate & move icons"),
                    ("lock.fill", "Always Hidden"),
                    ("touchid", "Touch ID / password lock"),
                    ("bolt.fill", "Triggers & profiles"),
                    ("keyboard", "Per-icon hotkeys & shortcuts")
                ],
                isHighlighted: true
            )

            trialOutcomeCard(
                title: "Continue with Basic",
                subtitle: "$0 forever",
                features: [
                    ("line.3.horizontal.decrease", "Click to hide / show"),
                    ("cursorarrow.click", "Left-click to open icons"),
                    ("magnifyingglass", "Browse & search icons"),
                    ("timer", "Auto-rehide")
                ],
                isHighlighted: false
            )
        }
        .padding(.horizontal, 20)

        if !licenseService.usesSetappDistribution {
            Button("Unlock Pro — \(licenseService.displayPriceLabel)") {
                runSingleOutboundAction {
                    if licenseService.usesAppStorePurchase {
                        Task { await licenseService.purchasePro() }
                    } else {
                        NSWorkspace.shared.open(LicenseService.checkoutURL())
                    }
                }
            }
            .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 10, horizontalPadding: 18, verticalPadding: 9))
            .disabled(licenseService.isPurchasing || outboundActionInFlight)
        }

        Spacer()
    }

    private func trialOutcomeCard(
        title: String,
        subtitle: String,
        features: [(String, String)],
        isHighlighted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isHighlighted ? saneAccentSoft : .white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(features, id: \.1) { icon, text in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(isHighlighted ? saneAccentSoft : .white)
                            .frame(width: 14)
                        Text(text)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBg)
                .shadow(color: isHighlighted ? saneAccent.opacity(0.18) : .clear, radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHighlighted ? saneAccentSoft : saneAccent.opacity(0.2), lineWidth: isHighlighted ? 2 : 1)
        )
    }

    private var shouldShowCompanionApps: Bool {
        !licenseService.usesAppStorePurchase && !licenseService.usesSetappDistribution
    }

    private var companionApps: [CompanionApp] {
        [
            CompanionApp(name: "SaneClip", detail: "Save clipboard history privately", url: URL(string: "https://saneclip.com?ref=sanebar-app")!),
            CompanionApp(name: "SaneClick", detail: "Add useful right-click actions", url: URL(string: "https://saneclick.com?ref=sanebar-app")!),
            CompanionApp(name: "SaneHosts", detail: "Block ads and trackers across your Mac", url: URL(string: "https://sanehosts.com?ref=sanebar-app")!)
        ]
    }

    private var companionAppsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Also useful")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                ForEach(companionApps) { app in
                    Button {
                        runSingleOutboundAction {
                            NSWorkspace.shared.open(app.url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(app.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .disabled(outboundActionInFlight)
                }
            }
        }
        .frame(maxWidth: 520)
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
                title: licenseService.usesSetappDistribution ? "Pro — Setapp" : "Pro — \(licenseService.displayPriceLabel)",
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
                                runSingleOutboundAction {
                                    Task { await licenseService.purchasePro() }
                                }
                            } label: {
                                Text(licenseService.isPurchasing ? "Processing..." : "Unlock Pro — \(licenseService.displayPriceLabel)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 9, horizontalPadding: 14, verticalPadding: 7))
                            .disabled(licenseService.isPurchasing || outboundActionInFlight)

                            Button("Restore Purchases") {
                                Task { await licenseService.restorePurchases() }
                            }
                            .buttonStyle(OnboardingSecondaryButtonStyle())
                            .font(.system(size: 13))
                            .disabled(licenseService.isPurchasing)
                        } else if licenseService.usesSetappDistribution {
                            Text("Managed by Setapp")
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                        } else {
                            Button {
                                runSingleOutboundAction {
                                    NSWorkspace.shared.open(LicenseService.checkoutURL())
                                }
                            } label: {
                                Text("Unlock Pro — \(licenseService.displayPriceLabel)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OnboardingPrimaryButtonStyle(cornerRadius: 9, horizontalPadding: 14, verticalPadding: 7))
                            .disabled(outboundActionInFlight)

                            Button(LicenseService.existingCustomerButtonLabel()) {
                                showingLicenseEntry = true
                            }
                            .buttonStyle(OnboardingSecondaryButtonStyle())
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
