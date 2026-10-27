import AppKit
import SwiftUI


@Observable
@MainActor
final class MenuBarOverlayViewModel {
    var settings = MenuBarAppearanceSettings()
    var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    var isDarkAppearance = MenuBarAppearanceService.isDarkAppearance(NSApp.effectiveAppearance)
}


struct MenuBarOverlayView: View {
    var viewModel: MenuBarOverlayViewModel

    private var activeTintColor: String {
        MenuBarAppearanceService.resolvedTintColorHex(
            settings: viewModel.settings,
            isDarkAppearance: viewModel.isDarkAppearance
        )
    }

    private var activeTintOpacity: Double {
        MenuBarAppearanceService.resolvedTintOpacity(
            settings: viewModel.settings,
            isDarkAppearance: viewModel.isDarkAppearance,
            reduceTransparency: viewModel.reduceTransparency
        )
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottom) {
                mainAppearanceLayer

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
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mainAppearanceLayer: some View {
        if viewModel.reduceTransparency {
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
                    .glassEffect(Glass.regular, in: overlayShape)
                    .overlay(
                        Color(hex: activeTintColor)
                            .opacity(activeTintOpacity)
                    )
            } else {
                fallbackTintLayer
            }
        #else
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


struct AnyShape: Shape, @unchecked Sendable {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init(_ shape: some Shape) {
        let shapeCopy = shape
        pathBuilder = { rect in
            shapeCopy.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
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
