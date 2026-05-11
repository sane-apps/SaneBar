import AppKit
import SwiftUI

// MARK: - MenuBarOverlayViewModel

/// Observable model to share settings between service and view
@Observable
@MainActor
final class MenuBarOverlayViewModel {
    var settings = MenuBarAppearanceSettings()
    var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    var isDarkAppearance = MenuBarAppearanceService.isDarkAppearance(NSApp.effectiveAppearance)
}

// MARK: - MenuBarOverlayView

/// SwiftUI view that renders the menu bar overlay with tint, shadow, border effects
struct MenuBarOverlayView: View {
    var viewModel: MenuBarOverlayViewModel

    /// Active tint color based on the overlay window appearance.
    private var activeTintColor: String {
        viewModel.isDarkAppearance ? viewModel.settings.tintColorDark : viewModel.settings.tintColor
    }

    /// Active tint opacity based on the overlay window appearance.
    /// When Reduce Transparency is enabled, the menu bar background becomes a solid opaque fill
    /// instead of blur — low-opacity tints are invisible on solid backgrounds. Use at least 50%
    /// opacity to ensure the tint is perceptible while not completely obscuring icons.
    private var activeTintOpacity: Double {
        let baseOpacity = viewModel.isDarkAppearance
            ? viewModel.settings.tintOpacityDark
            : viewModel.settings.tintOpacity
        if viewModel.reduceTransparency {
            return max(baseOpacity, 0.5)
        }
        return baseOpacity
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottom) {
                // Main appearance layer
                mainAppearanceLayer

                // Border layer
                if viewModel.settings.hasBorder {
                    Rectangle()
                        .fill(Color(hex: viewModel.settings.borderColor))
                        .frame(height: viewModel.settings.borderWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(overlayShape)
            .shadow(
                color: viewModel.settings.hasShadow ? .black.opacity(viewModel.settings.shadowOpacity) : .clear,
                radius: viewModel.settings.hasShadow ? 4 : 0,
                y: viewModel.settings.hasShadow ? 2 : 0
            )
        }
        .allowsHitTesting(false) // Ensure clicks pass through
    }

    @ViewBuilder
    private var mainAppearanceLayer: some View {
        if viewModel.reduceTransparency {
            // When Reduce Transparency is on, Glass effects are meaningless — use solid tint
            fallbackTintLayer
        } else if viewModel.settings.useLiquidGlass, MenuBarAppearanceSettings.supportsLiquidGlass {
            liquidGlassLayer
        } else {
            fallbackTintLayer
        }
    }

    @ViewBuilder
    private var liquidGlassLayer: some View {
        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(Glass.regular)
                    // Ensure chosen tint color/strength is always applied.
                    // (Glass.tint() doesn't reliably reflect custom colors in all cases.)
                    .overlay(
                        Color(hex: activeTintColor)
                            .opacity(activeTintOpacity)
                    )
            } else {
                fallbackTintLayer
            }
        #else
            // Glass APIs require Swift 6.2+ SDK (Xcode 26+)
            fallbackTintLayer
        #endif
    }

    private var fallbackTintLayer: some View {
        Rectangle()
            .fill(Color(hex: activeTintColor).opacity(activeTintOpacity))
    }

    private var overlayShape: some Shape {
        if viewModel.settings.hasRoundedCorners {
            AnyShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: viewModel.settings.cornerRadius,
                    bottomTrailingRadius: viewModel.settings.cornerRadius
                )
            )
        } else {
            AnyShape(Rectangle())
        }
    }
}

// MARK: - AnyShape

/// Type-erased shape for conditional shape rendering
struct AnyShape: Shape, @unchecked Sendable {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init(_ shape: some Shape) {
        // Capture shape value, not reference
        let shapeCopy = shape
        pathBuilder = { rect in
            shapeCopy.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert Color to hex string (e.g., "#FF5500")
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return "#000000"
        }

        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
