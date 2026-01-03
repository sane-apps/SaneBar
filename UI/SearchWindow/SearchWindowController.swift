import AppKit
import SwiftUI

// MARK: - SearchWindowController

/// Controller for the floating menu bar search window
@MainActor
final class SearchWindowController {

    // MARK: - Singleton

    static let shared = SearchWindowController()

    // MARK: - Window

    private var window: NSWindow?

    // MARK: - Toggle

    /// Toggle the search window visibility
    func toggle() {
        if let window = window, window.isVisible {
            close()
        } else {
            show()
        }
    }

    /// Show the search window
    func show() {
        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Position near menu bar (top center of screen)
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let menuBarHeight: CGFloat = 24  // Standard menu bar height
            let windowWidth: CGFloat = 400
            let windowHeight: CGFloat = 300

            let xPos = (screenFrame.width - windowWidth) / 2
            let yPos = screenFrame.height - menuBarHeight - windowHeight - 8

            window.setFrame(NSRect(x: xPos, y: yPos, width: windowWidth, height: windowHeight), display: true)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the search window
    func close() {
        window?.orderOut(nil)
    }

    // MARK: - Window Creation

    private func createWindow() {
        let contentView = MenuBarSearchView(onDismiss: { [weak self] in
            self?.close()
        })

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Menu Bar Search"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.backgroundColor = NSColor.windowBackgroundColor

        // Close when losing focus
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }

        self.window = window
    }
}
