import SwiftUI

// MARK: - SuggestionsView

/// Displays smart suggestions for menu bar organization
struct SuggestionsView: View {
    @ObservedObject var menuBarManager: MenuBarManager
    @State private var dismissedSuggestions: Set<UUID> = []

    private let suggestionsService = SuggestionsService.shared

    /// Active suggestions (not dismissed)
    private var suggestions: [Suggestion] {
        suggestionsService.generateSuggestions(for: menuBarManager.statusItems)
            .filter { !dismissedSuggestions.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if menuBarManager.settings.smartSuggestionsEnabled {
                if suggestions.isEmpty {
                    emptyState
                } else {
                    suggestionsList
                }
            } else {
                disabledState
            }
        }
        .padding()
    }

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Smart Suggestions")
                    .font(.headline)

                Spacer()

                Text("\(suggestions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }

            ForEach(suggestions.prefix(5)) { suggestion in
                SuggestionRow(suggestion: suggestion) {
                    applySuggestion(suggestion)
                } onDismiss: {
                    dismissSuggestion(suggestion)
                }
            }

            if suggestions.count > 5 {
                Text("+\(suggestions.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No suggestions")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Your menu bar looks well organized!")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Disabled State

    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Smart Suggestions Disabled")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Enable in Behavior settings to get personalized recommendations")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Actions

    private func applySuggestion(_ suggestion: Suggestion) {
        let newSection: StatusItemModel.ItemSection

        switch suggestion.type {
        case .hideItem:
            newSection = .hidden
        case .showItem, .moveToVisible:
            newSection = .alwaysVisible
        case .moveToCollapsed:
            newSection = .collapsed
        }

        menuBarManager.updateItem(suggestion.item, section: newSection)
        dismissedSuggestions.insert(suggestion.id)
    }

    private func dismissSuggestion(_ suggestion: Suggestion) {
        dismissedSuggestions.insert(suggestion.id)
    }
}

// MARK: - SuggestionRow

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let onApply: () -> Void
    let onDismiss: () -> Void

    private let iconService = IconService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Suggestion icon
            Image(systemName: suggestion.systemImage)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            // App icon
            if let nsImage = iconService.icon(forBundleIdentifier: suggestion.item.bundleIdentifier, size: 16) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.body)

                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button("Apply") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconColor: Color {
        switch suggestion.type {
        case .hideItem: return .orange
        case .showItem, .moveToVisible: return .green
        case .moveToCollapsed: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    SuggestionsView(menuBarManager: MenuBarManager.shared)
        .frame(width: 400)
}
