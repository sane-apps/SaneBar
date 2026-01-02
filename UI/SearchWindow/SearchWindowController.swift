import AppKit
import SwiftUI

// MARK: - SearchWindowController

/// Controller for the floating search window
@MainActor
final class SearchWindowController {

    // MARK: - Singleton

    static let shared = SearchWindowController()

    // MARK: - Window

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    // MARK: - State

    @Published var isVisible = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Show/Hide

    /// Show the search window
    func show() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        // Position at center-top of screen (like Spotlight)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 400
            let windowHeight: CGFloat = 300

            let x = screenFrame.midX - (windowWidth / 2)
            let y = screenFrame.maxY - windowHeight - 100 // Below menu bar

            window.setFrame(
                NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                display: true
            )
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    /// Hide the search window
    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    /// Toggle search window visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Window Creation

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Create the SwiftUI view with binding to visibility
        let searchView = MenuBarSearchView(
            menuBarManager: MenuBarManager.shared,
            isPresented: Binding(
                get: { [weak self] in self?.isVisible ?? false },
                set: { [weak self] newValue in
                    if !newValue {
                        self?.hide()
                    }
                }
            )
        )

        let hostingView = NSHostingView(rootView: AnyView(searchView))
        window.contentView = hostingView

        self.window = window
        self.hostingView = hostingView

        // Close window when it loses focus
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }
}
