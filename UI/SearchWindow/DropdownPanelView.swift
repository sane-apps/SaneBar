import AppKit
import SwiftUI

// MARK: - Dropdown Panel View

/// A polished floating panel showing hidden menu bar icons.
///
/// Designed to feel native — like macOS Control Center meets the menu bar.
/// Features: vibrancy background, hover effects, ESC dismissal, auto-sizing.
struct DropdownPanelView: View {
    let apps: [RunningApp]
    let alwaysHiddenApps: [RunningApp]
    let hasAccessibility: Bool
    let isRefreshing: Bool
    let onDismiss: () -> Void
    let onActivate: (RunningApp, Bool) -> Void
    let onRetry: () -> Void

    @ObservedObject private var menuBarManager = MenuBarManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader

            Divider().opacity(0.2)

            // Content
            if !hasAccessibility {
                accessibilityPrompt
            } else if apps.isEmpty, alwaysHiddenApps.isEmpty {
                emptyState
            } else {
                iconContent
            }
        }
        .frame(minWidth: 200)
        .background {
            VisualEffectBackground(material: .menu, blendingMode: .behindWindow)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onExitCommand { onDismiss() }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            Text("Hidden Icons")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            let total = apps.count + alwaysHiddenApps.count
            if total > 0 {
                Text("\(total)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            Spacer()

            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Icon Content

    private var iconContent: some View {
        VStack(spacing: 0) {
            // Hidden icons section
            if !apps.isEmpty {
                iconRow(apps: apps)
            }

            // Always-hidden section (if enabled and has items)
            if menuBarManager.settings.alwaysHiddenSectionEnabled, !alwaysHiddenApps.isEmpty {
                sectionDivider(label: "Always Hidden")
                iconRow(apps: alwaysHiddenApps)
            }
        }
    }

    private func iconRow(apps: [RunningApp]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(apps) { app in
                    PanelIconTile(
                        app: app,
                        onActivate: { isRightClick in onActivate(app, isRightClick) }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func sectionDivider(label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .fixedSize()

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning menu bar...")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("No hidden icons")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Drag icons past the separator to hide them")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }

    // MARK: - Accessibility Prompt

    private var accessibilityPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Needed")
                    .font(.system(size: 13, weight: .medium))
                Text("Required to detect menu bar icons")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant Access") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)

            Button { onRetry() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(14)
    }
}

// MARK: - Panel Icon Tile

/// Individual icon tile for the dropdown panel with hover effects.
private struct PanelIconTile: View {
    let app: RunningApp
    let onActivate: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        Button { onActivate(false) } label: {
            VStack(spacing: 4) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isHovering ? Color.accentColor.opacity(0.12) : Color.clear)

                    iconImage
                        .frame(width: 26, height: 26)
                }
                .frame(width: 42, height: 42)

                // Name
                Text(app.name)
                    .font(.system(size: 10))
                    .foregroundStyle(isHovering ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 58)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.name)
        .contextMenu {
            Button("Left-Click (Open)") { onActivate(false) }
            Button("Right-Click") { onActivate(true) }
        }
        .accessibilityLabel(Text(app.name))
    }

    @ViewBuilder
    private var iconImage: some View {
        if let icon = app.iconThumbnail ?? app.icon {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(icon.isTemplate ? .template : .original)
                .foregroundStyle(icon.isTemplate ? .secondary : .primary)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .aspectRatio(contentMode: .fit)
        }
    }
}
