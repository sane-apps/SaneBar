import AppKit
import SwiftUI

struct SpaceAnalyzerView: View {
    @State private var menuBarItems: [AccessibilityService.MenuBarItemPosition] = []
    @State private var totalWidth: CGFloat = 0
    @State private var usedWidth: CGFloat = 0
    @State private var isLoading = true

    private let accessibilityService = AccessibilityService.shared

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Menu Bar Health")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: refreshData) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding(.horizontal)

            if isLoading {
                ProgressView("Analyzing Menu Bar...")
                    .frame(height: 200)
            } else {
                // Visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Visualization")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.92))

                    // The Bar
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            // Visible (Left of delimiter, effectively)
                            // But actually, we just sum up widths.
                            // In SaneBar, hidden items are physically there but off-screen or zero-width?
                            // No, SaneBar pushes them off-screen.
                            // So "Visible" means x > 0.

                            let visibleItems = menuBarItems.filter { $0.x >= 0 }
                            let hiddenItems = menuBarItems.filter { $0.x < 0 }

                            let visibleWidth = visibleItems.reduce(0) { $0 + $1.width }
                            let hiddenWidth = hiddenItems.reduce(0) { $0 + $1.width }

                            // Color Key:
                            // Blue: Visible Apps
                            // Orange: Hidden Apps
                            // Gray: System/Control Center (approx)

                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: (visibleWidth / totalWidth) * geo.size.width)
                                .overlay(Text("Visible").font(.system(size: 13)).foregroundStyle(.white).lineLimit(1), alignment: .center)

                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: (hiddenWidth / totalWidth) * geo.size.width)
                                .overlay(Text("Hidden").font(.system(size: 13)).foregroundStyle(.white).lineLimit(1), alignment: .center)

                            Rectangle()
                                .fill(Color.gray.opacity(0.3)) // Free Space
                        }
                        .cornerRadius(6)
                    }
                    .frame(height: 30)

                    HStack {
                        Label("Visible: \(Int(menuBarItems.filter { $0.x >= 0 }.reduce(0) { $0 + $1.width }))px", systemImage: "circle.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Label("Hidden: \(Int(menuBarItems.filter { $0.x < 0 }.reduce(0) { $0 + $1.width }))px", systemImage: "circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Label("Free: \(Int(totalWidth - usedWidth))px", systemImage: "circle")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .font(.system(size: 13))
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)

                // Top Consumers List
                VStack(alignment: .leading) {
                    Text("Top Space Consumers")
                        .font(.headline)
                        .padding(.horizontal)

                    List {
                        ForEach(menuBarItems.sorted(by: { $0.width > $1.width }).prefix(10), id: \.app.uniqueId) { item in
                            HStack {
                                if let icon = item.app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "app.dashed")
                                }
                                Text(item.app.name)
                                Spacer()
                                Text("\(Int(item.width))px")
                                    .foregroundStyle(.white.opacity(0.92))
                                    .font(.monospacedDigit(.body)())
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 200)
                }
            }
        }
        .onAppear(perform: refreshData)
    }

    private func refreshData() {
        isLoading = true
        Task {
            // Get screen width
            if let screen = NSScreen.main {
                totalWidth = screen.frame.width
            } else {
                totalWidth = 1920 // Fallback
            }

            // Scan items
            let items = await accessibilityService.listMenuBarItemsWithPositions()
            menuBarItems = items
            usedWidth = items.reduce(0) { $0 + $1.width }
            isLoading = false
        }
    }
}
