import SwiftUI

// MARK: - Smart Group Tab (with icon)

struct SmartGroupTab: View {
    let title: String
    let icon: String
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
                    Capsule()
                        .fill(isSelected ? .white.opacity(0.15) : .clear)
                )
        }
        .buttonStyle(.plain)
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
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.25) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
