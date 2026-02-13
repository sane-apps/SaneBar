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

/// Living mesh gradient background with navy + teal.
/// Animates by default. Respects Reduce Motion.
struct SaneGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isWindowVisible = true

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
            }

            if reduceMotion || !isWindowVisible {
                staticMesh.opacity(0.7)
            } else {
                livingMesh.opacity(0.7)
            }
        }
        .ignoresSafeArea()
        .onAppear { isWindowVisible = true }
        .onDisappear { isWindowVisible = false }
    }

    // MARK: - Living Mesh (Animated)

    private var livingMesh: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isWindowVisible)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            // Multiple independent drift cycles (different speeds = organic)
            let slow = Float(sin(t / 14.0)) // 14s cycle — main breathing
            let medium = Float(sin(t / 9.0)) // 9s cycle — secondary drift
            let fast = Float(cos(t / 7.0)) // 7s cycle — subtle counter-movement

            // Drift amplitudes (subtle — don't want seasickness)
            let d1 = slow * 0.035
            let d2 = medium * 0.025
            let d3 = fast * 0.02

            MeshGradient(
                width: 4, height: 4,
                points: [
                    // Row 0: top edge (fixed)
                    [0.0, 0.0], [0.33, 0.0], [0.66, 0.0], [1.0, 0.0],
                    // Row 1: upper — drifts create rolling motion
                    [0.0, 0.33], [0.35 + d1, 0.30 - d2], [0.68 - d2, 0.32 + d3], [1.0, 0.33],
                    // Row 2: lower — counter-drift for depth
                    [0.0, 0.66], [0.32 - d3, 0.65 + d1], [0.65 + d2, 0.68 - d1], [1.0, 0.66],
                    // Row 3: bottom edge (fixed)
                    [0.0, 1.0], [0.33, 1.0], [0.66, 1.0], [1.0, 1.0]
                ],
                colors: meshColors
            )
        }
    }

    // MARK: - Static Mesh (Reduce Motion)

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
