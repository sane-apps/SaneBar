import SwiftUI

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
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark
                                ? .ultraThinMaterial
                                : .regularMaterial)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.teal.opacity(0.15),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark
                    ? .black.opacity(0.15)
                    : .teal.opacity(0.08),
                radius: colorScheme == .dark ? 6 : 4,
                x: 0, y: 2
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
