import AppKit
import SwiftUI

// MARK: - SearchWindowMode

enum SearchWindowMode {
    /// Standard Find Icon window (titled, closable, resizable, centered)
    case findIcon
    /// Second menu bar panel showing hidden icons below the menu bar
    case secondMenuBar
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
        MenuBarManager.shared.settings.useSecondMenuBar ? .secondMenuBar : .findIcon
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

        if desiredMode == .secondMenuBar {
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

        case .secondMenuBar:
            // Position below menu bar, right-aligned to the SaneBar status item
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y

            // Intrinsic content size — let SwiftUI determine width from icon count
            window.contentView?.layoutSubtreeIfNeeded()
            let fittingSize = window.contentView?.fittingSize ?? NSSize(width: 400, height: 140)
            let panelWidth = min(max(fittingSize.width, 200), visibleFrame.width - 20)
            let panelHeight = min(max(fittingSize.height, 80), 300)

            // Right-align to SaneBar's main status item (or fall back to right edge)
            let rightEdge: CGFloat = if let button = MenuBarManager.shared.mainStatusItem?.button,
                                        let buttonWindow = button.window {
                buttonWindow.frame.maxX
            } else {
                visibleFrame.maxX - 10
            }
            let xPos = max(visibleFrame.origin.x + 10, rightEdge - panelWidth)
            let yPos = screenFrame.maxY - menuBarHeight - panelHeight - 4 // 4pt gap below menu bar

            window.setFrame(
                NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight),
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
        case .secondMenuBar:
            createSecondMenuBarWindow()
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

    private func createSecondMenuBarWindow() {
        let contentView = MenuBarSearchView(
            isSecondMenuBar: true,
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        // Let SwiftUI drive the intrinsic size
        hostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        // Shadow for depth
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
            contentView.layer?.shadowOpacity = 1
            contentView.layer?.shadowRadius = 12
            contentView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        }

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
