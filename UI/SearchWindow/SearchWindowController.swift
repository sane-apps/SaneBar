import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "SearchWindowController")

// MARK: - SearchWindowMode

enum SearchWindowMode {
    /// Standard Find Icon window (titled, closable, resizable, centered)
    case findIcon
    /// Second menu bar panel showing hidden icons below the menu bar
    case secondMenuBar
}

// MARK: - KeyablePanel

/// Panel subclass that accepts key status for borderless panels.
/// Needed for keyboard focus + shortcuts on borderless second-menu-bar panel.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
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

    /// Posted when the search window is shown (so the SwiftUI view can reload on re-show)
    static let windowDidShowNotification = Notification.Name("SearchWindowController.windowDidShow")

    // MARK: - Window

    private var window: NSWindow?

    /// The mode this window was created for (nil if no window exists)
    private var currentMode: SearchWindowMode?

    /// Idle-close timer for browse panels (keeps panel interaction intentional).
    private var panelIdleCloseTask: Task<Void, Never>?
    private var panelIdleCloseGeneration: Int = 0

    /// Prevents explicit closes during icon moves (CGEvent can flip key status)
    private(set) var isMoveInProgress = false

    /// The active mode based on user settings
    var activeMode: SearchWindowMode {
        MenuBarManager.shared.settings.useSecondMenuBar ? .secondMenuBar : .findIcon
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    // MARK: - Toggle

    /// Toggle the search window visibility.
    /// - Parameter mode: Force a specific mode (nil = use `activeMode` from settings).
    func toggle(mode: SearchWindowMode? = nil) {
        if let window, window.isVisible, currentMode == (mode ?? activeMode) {
            close()
        } else if MenuBarManager.shared.settings.requireAuthToShowHiddenIcons {
            // Auth required — must be async
            Task {
                let authorized = await MenuBarManager.shared.authenticate(reason: "Unlock hidden icons")
                guard authorized else { return }
                show(mode: mode)
            }
        } else {
            // No auth — show immediately (no async delay)
            show(mode: mode)
        }
    }

    /// Show the search window.
    /// - Parameter mode: Force a specific mode (nil = use `activeMode` from settings).
    func show(mode: SearchWindowMode? = nil, prefill searchText: String? = nil) {
        let desiredMode = mode ?? activeMode
        normalizeBrowseModeSettings(for: desiredMode)
        let manager = MenuBarManager.shared
        logger.info("show requested mode=\(String(describing: desiredMode), privacy: .public) currentMode=\(String(describing: self.currentMode), privacy: .public)")

        // If mode changed, recreate the window
        if currentMode != nil, currentMode != desiredMode {
            resetWindow()
        }

        // Create window lazily if needed
        if window == nil {
            createWindow(mode: desiredMode)
        }

        guard let window else { return }
        applyDarkAppearance(to: window)

        if desiredMode == .findIcon {
            if let searchText, !searchText.isEmpty {
                NotificationCenter.default.post(name: MenuBarSearchView.setSearchTextNotification, object: searchText)
            } else {
                NotificationCenter.default.post(name: MenuBarSearchView.resetSearchNotification, object: nil)
            }
        }

        // Suspend hover/click triggers while search is open
        manager.hoverService.isSuspended = true

        if desiredMode == .secondMenuBar {
            // Keep auto-rehide behavior active in second-menu-bar mode so
            // expanded bars do not remain stuck open while the panel is visible.
            if manager.hidingService.state == .expanded,
               manager.settings.autoRehide,
               !manager.shouldSkipHideForExternalMonitor {
                manager.hidingService.scheduleRehide(after: manager.settings.findIconRehideDelay)
                logger.info("second-menu-bar show scheduled rehide after \(manager.settings.findIconRehideDelay, privacy: .public)s")
            } else {
                manager.hidingService.cancelRehide()
            }
        }

        positionWindow(window, mode: desiredMode)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Notify the SwiftUI view to reload (window is reused, onAppear won't fire again)
        NotificationCenter.default.post(name: Self.windowDidShowNotification, object: nil)

        // Keep panel sessions intentional: auto-close + quick rehide after idle.
        schedulePanelIdleCloseIfNeeded(for: desiredMode)
    }

    private func normalizeBrowseModeSettings(for mode: SearchWindowMode) {
        let manager = MenuBarManager.shared
        if Self.shouldForceAlwaysHiddenForIconPanel(
            mode: mode,
            isPro: LicenseService.shared.isPro,
            useSecondMenuBar: manager.settings.useSecondMenuBar,
            alwaysHiddenEnabled: manager.settings.alwaysHiddenSectionEnabled
        ) {
            manager.settings.alwaysHiddenSectionEnabled = true
        }
    }

    static func shouldForceAlwaysHiddenForIconPanel(
        mode: SearchWindowMode,
        isPro: Bool,
        useSecondMenuBar: Bool,
        alwaysHiddenEnabled: Bool
    ) -> Bool {
        // Icon Panel is the primary browse workflow. Keep always-hidden enabled for Pro there.
        mode == .findIcon && isPro && !useSecondMenuBar && !alwaysHiddenEnabled
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
        handleBrowseDismissal(reason: "close")
    }

    private func handleBrowseDismissal(reason: String) {
        let manager = MenuBarManager.shared
        panelIdleCloseTask?.cancel()
        panelIdleCloseTask = nil

        // Resume hover/click triggers and refresh pointer state before scheduling rehide.
        // Use strict menu-strip bounds on panel dismiss so the nearby panel area
        // doesn't keep rehide blocked as "menu interaction."
        manager.hoverService.isSuspended = false
        manager.hoverService.refreshMouseInMenuBarStateForBrowseDismissal()

        if manager.hidingService.state == .expanded,
           !manager.shouldSkipHideForExternalMonitor {
            manager.hidingService.scheduleRehide(after: manager.settings.findIconRehideDelay)
            logger.info("\(reason, privacy: .public) scheduled rehide after \(manager.settings.findIconRehideDelay, privacy: .public)s")
        }

        // Do NOT set window to nil, we reuse it for performance
        logger.info("\(reason, privacy: .public) completed (window hidden, cache retained)")
    }

    private func schedulePanelIdleCloseIfNeeded(for mode: SearchWindowMode) {
        panelIdleCloseTask?.cancel()
        panelIdleCloseTask = nil

        let manager = MenuBarManager.shared
        guard manager.settings.autoRehide, !manager.shouldSkipHideForExternalMonitor else { return }

        let idleDelaySeconds: TimeInterval = (mode == .findIcon) ? 10 : 20
        panelIdleCloseGeneration += 1
        let generation = panelIdleCloseGeneration

        panelIdleCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(idleDelaySeconds))
            await MainActor.run {
                guard let self else { return }
                guard self.panelIdleCloseGeneration == generation else { return }
                guard self.window?.isVisible == true, self.currentMode == mode, !self.isMoveInProgress else { return }

                // If the pointer is still inside the panel when the timer fires,
                // defer closure and give the user another full interaction window.
                if let window = self.window, window.frame.contains(NSEvent.mouseLocation) {
                    logger.debug("panel idle timeout deferred (\(idleDelaySeconds, privacy: .public)s): pointer still in panel")
                    self.schedulePanelIdleCloseIfNeeded(for: mode)
                    return
                }

                logger.info("panel idle timeout fired (\(idleDelaySeconds, privacy: .public)s): closing panel")
                self.close()

                // Idle close should feel immediate; override close() delay with a short rehide.
                if manager.hidingService.state == .expanded,
                   !manager.shouldSkipHideForExternalMonitor {
                    manager.hidingService.scheduleRehide(after: 0.2)
                    logger.info("panel idle timeout forced quick rehide")
                }
            }
        }
    }

    /// Destroy the cached window so it's recreated with the correct mode next time
    func resetWindow() {
        let wasVisible = window?.isVisible == true
        window?.orderOut(nil)
        window = nil
        currentMode = nil
        logger.info("resetWindow invoked (wasVisible=\(wasVisible, privacy: .public))")

        guard wasVisible else { return }

        // Match close() teardown semantics when a visible panel is force-reset
        // (for example, switching browse mode in Settings).
        handleBrowseDismissal(reason: "resetWindow")
    }

    /// Transition between browse panel modes while preserving "panel stays open" UX.
    /// Used when settings switch between Second Menu Bar and Icon Panel mid-session.
    func transition(to mode: SearchWindowMode) {
        let wasVisible = window?.isVisible == true
        window?.orderOut(nil)
        window = nil
        currentMode = nil
        logger.info("transition requested to mode=\(String(describing: mode), privacy: .public) fromVisible=\(wasVisible, privacy: .public)")

        guard wasVisible else { return }
        show(mode: mode)
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
            let panelHeight = min(max(fittingSize.height, 80), 500)

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
        .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "Icon Panel"
        window.titlebarSeparatorStyle = .line
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.hasShadow = true
        applyDarkAppearance(to: window)

        self.window = window
    }

    private func createSecondMenuBarWindow() {
        let contentView = MenuBarSearchView(
            isSecondMenuBar: true,
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: contentView)
        // Let SwiftUI drive the intrinsic size
        hostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 180, height: 80)
        panel.maxSize = NSSize(width: 800, height: 500)

        // Enable mouse tracking so SwiftUI .help() tooltips work on borderless panel
        panel.acceptsMouseMovedEvents = true

        // Shadow for depth
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
            contentView.layer?.shadowOpacity = 1
            contentView.layer?.shadowRadius = 12
            contentView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        }
        applyDarkAppearance(to: panel)

        window = panel
    }

    private func applyDarkAppearance(to window: NSWindow) {
        let dark = NSAppearance(named: .darkAqua)
        window.appearance = dark
        window.contentView?.appearance = dark
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_: Notification) {
        // Keep both panels open on focus loss. Auto-close on resign caused
        // click-triggered dismissals while launching icons/popovers.
        guard !isMoveInProgress else { return }
    }

    func windowDidBecomeKey(_: Notification) {}

    func windowWillClose(_: Notification) {
        guard !isMoveInProgress else { return }

        // Ensure titlebar/command close paths apply the same teardown as close().
        handleBrowseDismissal(reason: "windowWillClose")
    }

}
