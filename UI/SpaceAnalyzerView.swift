import SwiftUI

struct SpaceAnalyzerView: View {
    @StateObject private var accessibilityService = AccessibilityService.shared
    @State private var menuBarItems: [(app: RunningApp, x: CGFloat, width: CGFloat)] = []
    @State private var totalWidth: CGFloat = 0
    @State private var usedWidth: CGFloat = 0
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                VStack {
                    ProgressView()
                        .padding(.bottom, 10)
                    Text("Analyzing Menu Bar Space...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Menu Bar Space Usage")
                        .font(.headline)
                    
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            let visibleItems = menuBarItems.filter { $0.x >= 0 }
                            let hiddenItems = menuBarItems.filter { $0.x < 0 }
                            
                            let vWidth = visibleItems.reduce(0) { $0 + $1.width }
                            let hWidth = hiddenItems.reduce(0) { $0 + $1.width }
                            
                            if vWidth > 0 {
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: max(0, (vWidth / totalWidth) * geo.size.width))
                                    .overlay(
                                        Text("Visible")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .opacity(vWidth / totalWidth > 0.1 ? 1 : 0),
                                        alignment: .center
                                    )
                            }
                            
                            if hWidth > 0 {
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: max(0, (hWidth / totalWidth) * geo.size.width))
                                    .overlay(
                                        Text("Hidden")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .opacity(hWidth / totalWidth > 0.1 ? 1 : 0),
                                        alignment: .center
                                    )
                            }
                            
                            Rectangle()
                                .fill(Color.gray.opacity(0.2)) // Free Space
                        }
                        .cornerRadius(6)
                    }
                    .frame(height: 32)
                    
                    HStack {
                        Label("Visible: \(Int(visibleWidth))px", systemImage: "circle.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Label("Hidden: \(Int(hiddenWidth))px", systemImage: "circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Label("Free: \(Int(max(0, totalWidth - (visibleWidth + hiddenWidth))))px", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Top Consumers List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Top Space Consumers")
                            .font(.headline)
                        Spacer()
                        Button(action: refreshData) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh Analysis")
                    }
                    .padding(.horizontal)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(menuBarItems.sorted(by: { $0.width > $1.width }).prefix(15), id: \.app.uniqueId) { item in
                                HStack {
                                    if let icon = item.app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Image(systemName: "app.dashed")
                                            .frame(width: 16, height: 16)
                                    }
                                    
                                    Text(item.app.name)
                                        .lineLimit(1)
                                    
                                    if item.x < 0 {
                                        Image(systemName: "eye.slash")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(Int(item.width))px")
                                        .foregroundStyle(.secondary)
                                        .font(.monospacedDigit(.body)())
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                                
                                Divider()
                                    .padding(.leading, 40)
                            }
                        }
                    }
                    .frame(height: 240)
                }
            }
        }
        .padding(.vertical)
        .frame(width: 400)
        .onAppear(perform: refreshData)
    }
    
    private var visibleWidth: CGFloat {
        menuBarItems.filter { $0.x >= 0 }.reduce(0) { $0 + $1.width }
    }
    
    private var hiddenWidth: CGFloat {
        menuBarItems.filter { $0.x < 0 }.reduce(0) { $0 + $1.width }
    }

    private func refreshData() {
        isLoading = true
        Task {
            // Screen width from main screen
            let width: CGFloat
            if let screen = NSScreen.main {
                width = screen.frame.width
            } else {
                width = 1920
            }
            
            // Perform scan on main actor
            let items = await MainActor.run {
                accessibilityService.listMenuBarItemsWithPositions()
            }
            
            await MainActor.run {
                self.totalWidth = width
                self.menuBarItems = items
                self.usedWidth = items.reduce(0) { $0 + $1.width }
                self.isLoading = false
            }
        }
    }
}
