import SwiftUI

// MARK: - Sane Gradient Background

/// The standard SaneApps gradient background with glass morphism effect.
struct SaneGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [
                        Color.teal.opacity(0.08),
                        Color.blue.opacity(0.05),
                        Color.teal.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.98, blue: 0.99),
                        Color(red: 0.92, green: 0.96, blue: 0.98),
                        Color(red: 0.94, green: 0.97, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}
