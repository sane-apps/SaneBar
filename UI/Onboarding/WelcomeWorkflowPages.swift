import AppKit
import SaneUI
import SwiftUI

// MARK: - Page 2: Don't Skip

struct DontSkipPage: View {
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

struct BrowseIconsPage: View {
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

struct ZoneGuidePage: View {
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
        VStack(alignment: .leading, spacing: 12) {
            (Text("Advanced ").foregroundStyle(.white) + Text("Workflow").foregroundStyle(saneAccentGradient))
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Choose your browse style, then organize icons across Visible, Hidden, and Always Hidden.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                browseStyleCard
                    .frame(maxWidth: .infinity, alignment: .leading)

                zoneSummaryCard
                    .frame(width: 222, alignment: .topLeading)
            }

            workflowTipsCard

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 16)
    }

    private var browseStyleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse style")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("Settings → General → Browse Icons. Switch between Icon Panel and Second Menu Bar anytime.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Image("OnboardingBrowseSettings")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 142, alignment: .topLeading)
                .clipped()
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.3), radius: 7, x: 0, y: 4)
        }
        .padding(10)
        .background(onboardingCardBackground)
    }

    private var zoneSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zones")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(row.accent)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)

                        Text(row.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
            }
        }
        .padding(10)
        .background(onboardingCardBackground)
    }

    private var workflowTipsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            workflowTipRow(
                icon: "cursorarrow.click.2",
                text: "Basic lets you browse and click icons in either layout."
            )
            workflowTipRow(
                icon: "arrow.left.arrow.right.circle",
                text: "Pro adds icon moves, reordering, and Always Hidden."
            )
            workflowTipRow(
                icon: "command",
                text: "In the macOS menu bar itself, rearranging uses ⌘ + drag."
            )
        }
        .padding(12)
        .background(onboardingCardBackground)
    }

    private var onboardingCardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func workflowTipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(saneAccentSoft)
                .frame(width: 18, alignment: .center)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
