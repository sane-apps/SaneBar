import SwiftUI

// MARK: - Sane Brand Colors

/// Navy + teal palette — the Sane identity.
/// Original SaneUI values for comparison.
private enum SanePalette {
    // Dark mode: deep ocean tones
    static let navyDeep = Color(red: 0.02, green: 0.04, blue: 0.12)
    static let navy = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let navyMid = Color(red: 0.03, green: 0.06, blue: 0.16)
    static let navyTeal = Color(red: 0.04, green: 0.12, blue: 0.22)
    static let tealGlow = Color(red: 0.06, green: 0.22, blue: 0.30)
    static let tealBright = Color(red: 0.08, green: 0.28, blue: 0.34)
    static let tealDeep = Color(red: 0.03, green: 0.14, blue: 0.20)
    static let cyanHint = Color(red: 0.05, green: 0.18, blue: 0.25)

    // Light mode: soft teal-blue wash
    static let lightWash = Color(red: 0.94, green: 0.97, blue: 0.99)
    static let lightTeal = Color(red: 0.89, green: 0.95, blue: 0.97)
    static let lightNavy = Color(red: 0.91, green: 0.94, blue: 0.98)
    static let lightGlow = Color(red: 0.86, green: 0.94, blue: 0.97)
    static let lightBright = Color(red: 0.84, green: 0.93, blue: 0.96)
    static let lightCool = Color(red: 0.93, green: 0.96, blue: 0.99)
    static let lightSoft = Color(red: 0.92, green: 0.96, blue: 0.98)
    static let lightWarm = Color(red: 0.90, green: 0.95, blue: 0.98)
}

// MARK: - Sane Gradient Background

/// Static mesh gradient background with navy + teal.
struct SaneGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            }

            staticMesh.opacity(0.7)
        }
        .ignoresSafeArea()
    }

    // MARK: - Static Mesh

    private var staticMesh: some View {
        MeshGradient(
            width: 4, height: 4,
            points: [
                [0.0, 0.0], [0.33, 0.0], [0.66, 0.0], [1.0, 0.0],
                [0.0, 0.33], [0.35, 0.30], [0.68, 0.32], [1.0, 0.33],
                [0.0, 0.66], [0.32, 0.65], [0.65, 0.68], [1.0, 0.66],
                [0.0, 1.0], [0.33, 1.0], [0.66, 1.0], [1.0, 1.0]
            ],
            colors: meshColors
        )
    }

    // MARK: - Shared Colors

    private var meshColors: [Color] {
        colorScheme == .dark ? [
            // Row 0: navy edge
            SanePalette.navyDeep, SanePalette.navy, SanePalette.navyMid, SanePalette.navyDeep,
            // Row 1: teal warmth emerges
            SanePalette.navy, SanePalette.tealGlow, SanePalette.cyanHint, SanePalette.navyTeal,
            // Row 2: deep teal band
            SanePalette.navyTeal, SanePalette.cyanHint, SanePalette.tealBright, SanePalette.tealDeep,
            // Row 3: fade back to navy
            SanePalette.navyDeep, SanePalette.navyMid, SanePalette.tealDeep, SanePalette.navyDeep
        ] : [
            // Row 0: clean top
            SanePalette.lightWash, SanePalette.lightCool, SanePalette.lightNavy, SanePalette.lightWash,
            // Row 1: teal glow area
            SanePalette.lightNavy, SanePalette.lightGlow, SanePalette.lightBright, SanePalette.lightSoft,
            // Row 2: warm teal band
            SanePalette.lightSoft, SanePalette.lightBright, SanePalette.lightTeal, SanePalette.lightWarm,
            // Row 3: cool bottom
            SanePalette.lightCool, SanePalette.lightNavy, SanePalette.lightWarm, SanePalette.lightWash
        ]
    }
}
