import SwiftUI
import SaneUI

struct GlassGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            configuration.content
        }
        .padding(16)
        .background(
            ChromeGlassRoundedBackground(
                cornerRadius: 12,
                tint: SaneBarChrome.panelTint,
                tintStrength: 0.12,
                shadowOpacity: 0.12,
                shadowRadius: 8,
                shadowY: 3
            )
        )
    }
}
