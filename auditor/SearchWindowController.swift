import AppKit
import SwiftUI

// MARK: - SearchWindowController

/// Controller for the floating menu bar search window
@MainActor
final class SearchWindowController: NSObject, NSWindowDelegate {

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
            // Check auth if required
            Task {
                if MenuBarManager.shared.settings.requireAuthToShowHiddenIcons {
                    let authorized = await MenuBarManager.shared.authenticate(reason: "Unlock hidden icons")
                    guard authorized else { return }
                }
                show()
            }
        }
    }

    /// Show the search window
    func show() {
        // Always create a fresh window to reset state
        createWindow()

        guard let window = window else { return }

        // Position centered below menu bar
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size

            let xPos = screenFrame.midX - (windowSize.width / 2)
            let yPos = screenFrame.maxY - windowSize.height - 20

            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the search window
    func close() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Window Creation

    private func createWindow() {
        // Close existing window if any
        window?.orderOut(nil)

        let contentView = MenuBarSearchView(onDismiss: { [weak self] in
            self?.close()
        })

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Find Icon"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        // Clear background for ultraThinMaterial to show through
        // Fallback: on older macOS, the material degrades gracefully to translucent
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Add shadow and rounded corners
        window.hasShadow = true

        self.window = window
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
