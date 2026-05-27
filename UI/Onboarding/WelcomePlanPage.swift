import AppKit
import SaneUI
import SwiftUI

// MARK: - Page 7: Plan / Upgrade

struct FreeVsProPage: View {
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
            LicenseEntryView(licenseService: SaneBarLicenseSettingsAdapter.shared)
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
                                Task { await licenseService.purchasePro() }
                            } label: {
                                Text(licenseService.isPurchasing ? "Processing..." : "Unlock Pro — \(licenseService.displayPriceLabel)")
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
                                Text("Unlock Pro — \(licenseService.displayPriceLabel)")
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
