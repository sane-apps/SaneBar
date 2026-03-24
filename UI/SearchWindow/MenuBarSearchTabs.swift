import SwiftUI

// MARK: - Smart Group Tab (with icon)

struct SmartGroupTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    ChromeGlassCapsuleBackground(
                        tint: isSelected ? SaneBarChrome.accentTeal : SaneBarChrome.controlNavyDeep,
                        edgeTint: isSelected ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal,
                        tintStrength: isSelected ? 0.62 : 0.10,
                        glowOpacity: isSelected ? 0.22 : 0.06,
                        shadowOpacity: isSelected ? 0.18 : 0.12,
                        shadowRadius: isSelected ? 8 : 6,
                        shadowY: 3
                    )
                )
        }
        .buttonStyle(ChromePressablePlainStyle())
    }
}

// MARK: - Group Tab Button (custom groups)

struct GroupTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    ChromeGlassCapsuleBackground(
                        tint: isSelected ? SaneBarChrome.accentTeal : SaneBarChrome.controlNavyDeep,
                        edgeTint: isSelected ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal,
                        tintStrength: isSelected ? 0.62 : 0.10,
                        glowOpacity: isSelected ? 0.22 : 0.06,
                        shadowOpacity: isSelected ? 0.18 : 0.12,
                        shadowRadius: isSelected ? 8 : 6,
                        shadowY: 3
                    )
                )
        }
        .buttonStyle(ChromePressablePlainStyle())
    }
}
