import SwiftUI

// MARK: - Page 3: Choose Your Style

/// Interactive preset chooser + icon style picker.
/// Replaces static "Power Features" page with actionable configuration.
struct SetupStylePage: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var selectedPreset: Preset?

    enum Preset: String, CaseIterable {
        case minimal, smart, presenter

        var title: String {
            switch self {
            case .minimal: "Minimal"
            case .smart: "Smart"
            case .presenter: "Presenter"
            }
        }

        var icon: String {
            switch self {
            case .minimal: "minus.circle"
            case .smart: "wand.and.stars"
            case .presenter: "lock.shield"
            }
        }

        var color: Color {
            switch self {
            case .minimal: .blue
            case .smart: .purple
            case .presenter: .orange
            }
        }

        var description: String {
            switch self {
            case .minimal: "Click to hide/show.\nNo automation, no gestures."
            case .smart: "Auto-hide after 5s.\nHover and scroll to reveal."
            case .presenter: "Touch ID to reveal.\nAlways-hidden section on."
            }
        }

        var recommended: Bool { self == .smart }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Your Style")
                .font(.system(size: 26, weight: .bold))

            Text("Pick a starting point — customize everything later in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.7))

            // Preset cards
            HStack(spacing: 12) {
                ForEach(Preset.allCases, id: \.self) { preset in
                    presetCard(preset)
                }
            }
            .padding(.horizontal, 24)

            Divider()
                .padding(.horizontal, 60)

            // Icon style picker
            VStack(spacing: 10) {
                Text("Menu Bar Icon")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))

                HStack(spacing: 14) {
                    ForEach(iconStyles, id: \.self) { style in
                        if let sfName = style.sfSymbolName {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    menuBarManager.settings.menuBarIconStyle = style
                                    menuBarManager.saveSettings()
                                }
                            } label: {
                                Image(systemName: sfName)
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSelected(style) ? .white : .primary)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected(style) ? Color.accentColor : Color.primary.opacity(0.06))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected(style) ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    // MARK: - Preset Card

    private func presetCard(_ preset: Preset) -> some View {
        let isActive = selectedPreset == preset

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPreset = preset
                applyPreset(preset)
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: preset.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isActive ? .white : preset.color)

                Text(preset.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .primary)

                if preset.recommended {
                    Text("Recommended")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? .white.opacity(0.8) : .primary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isActive ? Color.white.opacity(0.2) : preset.color.opacity(0.15))
                        )
                }

                Text(preset.description)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? .white.opacity(0.9) : .primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? preset.color : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color.clear : preset.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var iconStyles: [SaneBarSettings.MenuBarIconStyle] {
        SaneBarSettings.MenuBarIconStyle.allCases.filter { $0 != .custom }
    }

    private func isSelected(_ style: SaneBarSettings.MenuBarIconStyle) -> Bool {
        menuBarManager.settings.menuBarIconStyle == style
    }

    private func applyPreset(_ preset: Preset) {
        switch preset {
        case .minimal:
            menuBarManager.settings.autoRehide = false
            menuBarManager.settings.showOnHover = false
            menuBarManager.settings.showOnScroll = false
            menuBarManager.settings.showOnClick = false
        case .smart:
            menuBarManager.settings.autoRehide = true
            menuBarManager.settings.rehideDelay = 5.0
            menuBarManager.settings.showOnHover = true
            menuBarManager.settings.showOnScroll = true
        case .presenter:
            menuBarManager.settings.autoRehide = true
            menuBarManager.settings.requireAuthToShowHiddenIcons = true
        }
        menuBarManager.saveSettings()
    }
}
