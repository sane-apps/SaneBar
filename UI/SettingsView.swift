import SwiftUI

// MARK: - SettingsView

/// Main settings view for SaneBar
struct SettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared

    var body: some View {
        Group {
            if menuBarManager.permissionService.permissionState != .granted {
                permissionRequestContent
            } else {
                mainContent
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    // MARK: - Permission Request

    private var permissionRequestContent: some View {
        PermissionRequestView(
            permissionService: menuBarManager.permissionService
        ) {
            Task {
                await menuBarManager.scan()
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Item list or empty state
            if menuBarManager.statusItems.isEmpty {
                emptyStateView
            } else {
                itemListView
            }

            Divider()

            // Footer
            footerView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Items")
                    .font(.headline)

                Text("\(menuBarManager.statusItems.count) items discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await menuBarManager.scan()
                }
            } label: {
                if menuBarManager.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(menuBarManager.isScanning)
        }
        .padding()
    }

    // MARK: - Item List

    private var itemListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(StatusItemModel.ItemSection.allCases, id: \.self) { section in
                    sectionView(for: section)
                }
            }
            .padding()
        }
    }

    private func sectionView(for section: StatusItemModel.ItemSection) -> some View {
        let items = menuBarManager.statusItems.filter { $0.section == section }

        return Group {
            if !items.isEmpty || section == .alwaysVisible {
                VStack(alignment: .leading, spacing: 8) {
                    // Section header
                    HStack {
                        Image(systemName: section.systemImage)
                        Text(section.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(items.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)

                    // Items
                    if items.isEmpty {
                        Text("No items")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(items) { item in
                            StatusItemRow(item: item) { newSection in
                                menuBarManager.updateItem(item, section: newSection)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Menu Bar Items Found")
                .font(.headline)

            if let error = menuBarManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Click Refresh to scan for items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Scan Now") {
                Task {
                    await menuBarManager.scan()
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("Right-click items to change their section")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Quit SaneBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
