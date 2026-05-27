import AppKit
import SaneUI
import SwiftUI

// MARK: - Page 5: Sane Philosophy

struct SanePromisePage: View {
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

struct PillarCard: View {
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
