import SwiftUI

// MARK: - Smart Group Tab (with icon)

struct SmartGroupTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    private let accentStart = Color(red: 0.10, green: 0.38, blue: 0.56)
    private let accentEnd = Color(red: 0.13, green: 0.25, blue: 0.45)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [accentStart.opacity(0.20), accentEnd.opacity(0.14)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(.clear)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
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
    private let accentStart = Color(red: 0.10, green: 0.38, blue: 0.56)
    private let accentEnd = Color(red: 0.13, green: 0.25, blue: 0.45)

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [accentStart.opacity(0.24), accentEnd.opacity(0.17)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(.clear)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
