import SwiftUI
import SaneUI

struct GlassGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            configuration.content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark
                            ? .ultraThinMaterial
                            : .regularMaterial)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.1)
                        : Color.saneAccent.opacity(0.16),
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark
                ? .black.opacity(0.15)
                : .saneAccentDeep.opacity(0.10),
            radius: 4, y: 2
        )
    }
}
