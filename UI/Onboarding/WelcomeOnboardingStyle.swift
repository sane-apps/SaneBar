import AppKit
import SaneUI
import SwiftUI

// Onboarding palette: softened SaneUI teal accents + navy cards
let cardBg = Color(red: 0.08, green: 0.10, blue: 0.18)
let navyBg = Color(red: 0.06, green: 0.08, blue: 0.16)
let saneAccentDeep = Color.saneAccentDeep
let saneAccent = Color.saneAccent
let saneAccentSoft = Color.saneAccentSoft
let saneAccentGradient = LinearGradient(
    colors: [saneAccentSoft, saneAccent],
    startPoint: .leading,
    endPoint: .trailing
)
let saneButtonGradient = LinearGradient(
    colors: [saneAccentSoft.opacity(0.98), saneAccent.opacity(0.98)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
enum Tier { case free, pro }

struct OnboardingPrimaryButtonStyle: ButtonStyle {
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

struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.9)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - Background

struct OnboardingBackground: View {
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
