import AppKit
import SwiftUI

// MARK: - SearchWindowController

/// Controller for the floating menu bar search window.
///
/// **Performance Optimization**: Reuses the window instance to prevent lag
/// when opening. Re-creating NSWindow + NSHostingView is expensive.
@MainActor
final class SearchWindowController: NSObject, NSWindowDelegate {
    // MARK: - Singleton

    static let shared = SearchWindowController()

    // MARK: - Window

    private var window: NSWindow?

    /// Prevents auto-close during icon moves (CGEvent causes resignKey)
    private(set) var isMoveInProgress = false

    // MARK: - Toggle

    /// Toggle the search window visibility
    func toggle() {
        if let window, window.isVisible {
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
    func show(prefill searchText: String? = nil) {
        // Create window lazily if needed
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        if let searchText, !searchText.isEmpty {
            NotificationCenter.default.post(name: MenuBarSearchView.setSearchTextNotification, object: searchText)
        } else {
            // Notify view to reset search text and focus field
            NotificationCenter.default.post(name: MenuBarSearchView.resetSearchNotification, object: nil)
        }

        // Suspend hover/click triggers while search is open
        MenuBarManager.shared.hoverService.isSuspended = true

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

    /// Set move-in-progress flag to prevent auto-close during CGEvent Cmd+drag
    func setMoveInProgress(_ inProgress: Bool) {
        isMoveInProgress = inProgress
    }

    /// Close the search window
    func close() {
        // Don't close while a move is in progress — CGEvent mouse
        // simulation causes resignKey which would break the move.
        guard !isMoveInProgress else { return }
        window?.orderOut(nil)
        // Resume hover/click triggers
        MenuBarManager.shared.hoverService.isSuspended = false
        // Do NOT set window to nil, we reuse it for performance
    }

    // MARK: - Window Creation

    private func createWindow() {
        let contentView = MenuBarSearchView(onDismiss: { [weak self] in
            self?.close()
        })

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Find Icon"
        window.titlebarSeparatorStyle = .line
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.level = .floating

        // Ensure window stays in memory for reuse but doesn't block termination
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Add shadow
        window.hasShadow = true

        self.window = window
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_: Notification) {
        // Skip auto-close during moves — CGEvent Cmd+drag steals key status
        guard !isMoveInProgress else { return }
        close()
    }

    func windowWillClose(_: Notification) {
        // If user explicitly closes, we can either keep it or nil it.
        // Keeping it is better for performance.
    }
}
