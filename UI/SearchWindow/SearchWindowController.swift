import AppKit
import SwiftUI

// MARK: - SearchWindowMode

enum SearchWindowMode {
    /// Standard Find Icon window (titled, closable, resizable, centered)
    case findIcon
    /// Dropdown panel showing hidden icons below the menu bar
    case dropdownPanel
}

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

    /// The mode this window was created for (nil if no window exists)
    private var currentMode: SearchWindowMode?

    /// Prevents auto-close during icon moves (CGEvent causes resignKey)
    private(set) var isMoveInProgress = false

    /// The active mode based on user settings
    var activeMode: SearchWindowMode {
        MenuBarManager.shared.settings.useDropdownPanel ? .dropdownPanel : .findIcon
    }

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
        let desiredMode = activeMode

        // If mode changed, recreate the window
        if currentMode != nil, currentMode != desiredMode {
            resetWindow()
        }

        // Create window lazily if needed
        if window == nil {
            createWindow(mode: desiredMode)
        }

        guard let window else { return }

        if desiredMode == .findIcon {
            if let searchText, !searchText.isEmpty {
                NotificationCenter.default.post(name: MenuBarSearchView.setSearchTextNotification, object: searchText)
            } else {
                NotificationCenter.default.post(name: MenuBarSearchView.resetSearchNotification, object: nil)
            }
        }

        // Suspend hover/click triggers while search is open
        MenuBarManager.shared.hoverService.isSuspended = true

        if desiredMode == .dropdownPanel {
            // Cancel rehide — panel mode replaces the expand/collapse paradigm
            MenuBarManager.shared.hidingService.cancelRehide()
        }

        positionWindow(window, mode: desiredMode)
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

    /// Destroy the cached window so it's recreated with the correct mode next time
    func resetWindow() {
        window?.orderOut(nil)
        window = nil
        currentMode = nil
    }

    // MARK: - Window Positioning

    private func positionWindow(_ window: NSWindow, mode: SearchWindowMode) {
        guard let screen = NSScreen.main else { return }

        switch mode {
        case .findIcon:
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let xPos = screenFrame.midX - (windowSize.width / 2)
            let yPos = screenFrame.maxY - windowSize.height - 20
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))

        case .dropdownPanel:
            // Flush below menu bar, full width of visible frame
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
            let panelHeight: CGFloat = 180
            let yPos = screenFrame.maxY - menuBarHeight - panelHeight
            window.setFrame(
                NSRect(x: visibleFrame.origin.x, y: yPos, width: visibleFrame.width, height: panelHeight),
                display: true
            )
        }
    }

    // MARK: - Window Creation

    private func createWindow(mode: SearchWindowMode) {
        currentMode = mode

        switch mode {
        case .findIcon:
            createFindIconWindow()
        case .dropdownPanel:
            createDropdownPanelWindow()
        }
    }

    private func createFindIconWindow() {
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
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.hasShadow = true

        self.window = window
    }

    private func createDropdownPanelWindow() {
        let contentView = MenuBarSearchView(
            isDropdownPanel: true,
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true
        panel.isMovable = false

        window = panel
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
