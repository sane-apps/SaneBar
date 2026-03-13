import SwiftUI
import SaneUI

enum SaneBarChrome {
    static let accentStart = Color(red: 0.22, green: 0.45, blue: 1.00)
    static let accentEnd = Color(red: 0.10, green: 0.24, blue: 0.78)
    static let accentHighlight = Color(red: 0.57, green: 0.76, blue: 1.00)
    static let accentTeal = Color(red: 0.32, green: 0.88, blue: 0.94)
    static let controlNavy = Color(red: 0.11, green: 0.20, blue: 0.46)
    static let controlNavyDeep = Color(red: 0.07, green: 0.14, blue: 0.32)
    static let panelTint = Color(red: 0.14, green: 0.26, blue: 0.56)
    static let panelTintSoft = Color(red: 0.08, green: 0.15, blue: 0.32)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentTeal, accentStart],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let activeControlFill = accentStart
    static let idleControlFill = controlNavy
    static let utilityFill = controlNavyDeep
    static let softSurfaceFill = panelTint.opacity(0.10)
    static let targetControlFill = accentTeal
    static let controlStroke = Color.white.opacity(0.20)
    static let mutedStroke = Color.white.opacity(0.10)
    static let selectedStroke = accentHighlight.opacity(0.52)
    static let rowStroke = Color.white.opacity(0.12)
    static let controlShadow = Color.black.opacity(0.20)
    static let panelShadow = Color.black.opacity(0.16)
}

struct ChromeGlassRoundedBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    var tint: Color = SaneBarChrome.accentStart
    var edgeTint: Color?
    var tintStrength: Double = 0.14
    var glowOpacity: Double = 0.0
    var interactive = false
    var shadowOpacity: Double = 0.16
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 4

    var body: some View {
        ZStack {
            glassBase

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(colorScheme == .dark ? tintStrength : tintStrength * 0.65),
                            SaneBarChrome.accentEnd.opacity(colorScheme == .dark ? tintStrength * 0.42 : tintStrength * 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.14),
                            resolvedEdgeTint.opacity(colorScheme == .dark ? 0.40 : 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? shadowOpacity : shadowOpacity * 0.55),
            radius: shadowRadius,
            x: 0,
            y: shadowY
        )
        .shadow(
            color: resolvedEdgeTint.opacity(colorScheme == .dark ? glowOpacity : glowOpacity * 0.45),
            radius: shadowRadius,
            x: 0,
            y: 1
        )
    }

    @ViewBuilder
    private var glassBase: some View {
        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                if interactive {
                    Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
            } else {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(colorScheme == .dark ? 0.88 : 0.74)
            }
        #else
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(colorScheme == .dark ? 0.88 : 0.74)
        #endif
    }

    private var resolvedEdgeTint: Color { edgeTint ?? tint }
}

struct ChromeGlassCapsuleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var tint: Color = SaneBarChrome.accentStart
    var edgeTint: Color?
    var tintStrength: Double = 0.26
    var glowOpacity: Double = 0.0
    var interactive = true
    var shadowOpacity: Double = 0.18
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 3

    var body: some View {
        ZStack {
            glassBase

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.18 : 0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(colorScheme == .dark ? tintStrength : tintStrength * 0.70),
                            SaneBarChrome.accentEnd.opacity(colorScheme == .dark ? tintStrength * 0.48 : tintStrength * 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.32 : 0.18),
                            resolvedEdgeTint.opacity(colorScheme == .dark ? 0.50 : 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? shadowOpacity : shadowOpacity * 0.55),
            radius: shadowRadius,
            x: 0,
            y: shadowY
        )
        .shadow(
            color: resolvedEdgeTint.opacity(colorScheme == .dark ? glowOpacity : glowOpacity * 0.45),
            radius: shadowRadius,
            x: 0,
            y: 1
        )
    }

    @ViewBuilder
    private var glassBase: some View {
        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                if interactive {
                    Color.clear.glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Color.clear.glassEffect(.regular, in: .capsule)
                }
            } else {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(colorScheme == .dark ? 0.90 : 0.76)
            }
        #else
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(colorScheme == .dark ? 0.90 : 0.76)
        #endif
    }

    private var resolvedEdgeTint: Color { edgeTint ?? tint }
}

struct ChromeGlassCircleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var tint: Color = SaneBarChrome.accentStart
    var edgeTint: Color?
    var tintStrength: Double = 0.24
    var glowOpacity: Double = 0.0
    var interactive = true

    var body: some View {
        ZStack {
            glassBase

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.18 : 0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(colorScheme == .dark ? tintStrength : tintStrength * 0.70),
                            SaneBarChrome.accentEnd.opacity(colorScheme == .dark ? tintStrength * 0.42 : tintStrength * 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.30 : 0.18),
                            resolvedEdgeTint.opacity(colorScheme == .dark ? 0.48 : 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08),
            radius: 7,
            x: 0,
            y: 3
        )
        .shadow(
            color: resolvedEdgeTint.opacity(colorScheme == .dark ? glowOpacity : glowOpacity * 0.45),
            radius: 7,
            x: 0,
            y: 1
        )
    }

    @ViewBuilder
    private var glassBase: some View {
        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                if interactive {
                    Color.clear.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 999))
                } else {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 999))
                }
            } else {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(colorScheme == .dark ? 0.90 : 0.76)
            }
        #else
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(colorScheme == .dark ? 0.90 : 0.76)
        #endif
    }

    private var resolvedEdgeTint: Color { edgeTint ?? tint }
}

struct ChromeTinyIconBadge: View {
    var systemImage: String
    var selected = false
    var prominent = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            Image(systemName: systemImage)
                .font(.system(size: prominent ? 11.5 : 11, weight: .black))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.24), radius: 1, x: 0, y: 1)
        }
        .frame(width: prominent ? 20 : 18, height: prominent ? 18 : 16)
        .shadow(color: glowColor, radius: prominent ? 5 : 3, x: 0, y: 0)
    }

    private var backgroundColors: [Color] {
        if prominent || selected {
            return [SaneBarChrome.accentTeal.opacity(0.96), SaneBarChrome.accentStart.opacity(0.92)]
        }

        return [SaneBarChrome.controlNavy.opacity(0.98), SaneBarChrome.controlNavyDeep.opacity(0.96)]
    }

    private var borderColor: Color {
        if prominent || selected {
            return SaneBarChrome.accentHighlight.opacity(0.78)
        }

        return SaneBarChrome.accentTeal.opacity(0.44)
    }

    private var glowColor: Color {
        if prominent || selected {
            return SaneBarChrome.accentTeal.opacity(0.30)
        }

        return SaneBarChrome.accentTeal.opacity(0.10)
    }
}

struct ChromePressablePlainStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .saturation(configuration.isPressed ? 1.18 : 1)
            .contrast(configuration.isPressed ? 1.06 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

struct ChromeActionButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let tint: Color = if destructive {
            Color(red: 0.86, green: 0.28, blue: 0.30)
        } else if prominent {
            SaneBarChrome.accentTeal
        } else {
            SaneBarChrome.controlNavyDeep
        }

        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.94 : 0.98))
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 4 : 6)
            .background(
                ChromeGlassCapsuleBackground(
                    tint: tint,
                    edgeTint: destructive ? Color(red: 0.98, green: 0.60, blue: 0.62) : (prominent ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal),
                    tintStrength: destructive
                        ? (configuration.isPressed ? 0.28 : 0.24)
                        : prominent
                            ? (configuration.isPressed ? 0.48 : 0.58)
                            : (configuration.isPressed ? 0.10 : 0.14),
                    glowOpacity: destructive ? 0.10 : (prominent ? 0.22 : 0.08),
                    shadowOpacity: configuration.isPressed ? 0.12 : 0.18,
                    shadowRadius: configuration.isPressed ? 5 : 8,
                    shadowY: configuration.isPressed ? 2 : 3
                )
            )
            .overlay(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ChromeSegmentedChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    ChromeGlassRoundedBackground(
                        cornerRadius: 7,
                        tint: isSelected ? SaneBarChrome.accentTeal : SaneBarChrome.controlNavyDeep,
                        edgeTint: isSelected ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal,
                        tintStrength: isSelected ? 0.60 : 0.10,
                        glowOpacity: isSelected ? 0.22 : 0.06,
                        interactive: true,
                        shadowOpacity: isSelected ? 0.18 : 0.12,
                        shadowRadius: isSelected ? 7 : 5,
                        shadowY: 3
                    )
                )
        }
        .buttonStyle(ChromePressablePlainStyle())
    }
}

struct ChromeMenuButtonLabel: View {
    let title: String
    var systemImage: String?
    var prominent = false

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                ChromeTinyIconBadge(systemImage: systemImage, prominent: prominent)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.98))
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(prominent ? Color.white.opacity(0.98) : SaneBarChrome.accentHighlight.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ChromeGlassRoundedBackground(
                cornerRadius: 8,
                tint: prominent ? SaneBarChrome.accentTeal : SaneBarChrome.controlNavyDeep,
                edgeTint: prominent ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal,
                tintStrength: prominent ? 0.54 : 0.12,
                glowOpacity: prominent ? 0.24 : 0.08,
                interactive: true,
                shadowOpacity: prominent ? 0.18 : 0.14,
                shadowRadius: prominent ? 8 : 6,
                shadowY: 3
            )
        )
    }
}

struct ChromeBadge: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(SaneBarChrome.accentHighlight)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            ChromeGlassCapsuleBackground(
                tint: SaneBarChrome.accentTeal,
                edgeTint: SaneBarChrome.accentHighlight,
                tintStrength: 0.24,
                glowOpacity: 0.10,
                shadowOpacity: 0.10,
                shadowRadius: 5,
                shadowY: 2
            )
        )
    }
}

struct CompactSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                ChromeGlassRoundedBackground(
                    cornerRadius: 10,
                    tint: colorScheme == .dark ? SaneBarChrome.panelTint : SaneBarChrome.accentStart,
                    tintStrength: colorScheme == .dark ? 0.10 : 0.08,
                    shadowOpacity: colorScheme == .dark ? 0.12 : 0.06,
                    shadowRadius: colorScheme == .dark ? 8 : 4,
                    shadowY: colorScheme == .dark ? 3 : 2
                )
            )
            .padding(.horizontal, 2)
        }
    }
}

struct CompactRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct CompactToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(SaneBarChrome.accentStart)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct CompactDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}
