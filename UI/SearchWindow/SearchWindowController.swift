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
    /// Posted when an icon-move pipeline completes (setMoveInProgress false).
    static let iconMoveDidFinishNotification = Notification.Name("SearchWindowController.iconMoveDidFinish")

    // MARK: - Window

    private var window: NSWindow?

    /// The mode this window was created for (nil if no window exists)
    private var currentMode: SearchWindowMode?

    /// Idle-close timer for browse panels (keeps panel interaction intentional).
    private var panelIdleCloseTask: Task<Void, Never>?
    private var panelIdleCloseGeneration: Int = 0
    private var postDismissForceHideTask: Task<Void, Never>?
    private var secondMenuBarRelayoutTask: Task<Void, Never>?
    private var browseActivationInFlightCount: Int = 0
    private var lastBrowseActivationFinishedAt: Date?
    private var lastSecondMenuBarDiagnostics = SecondMenuBarDiagnostics()

    /// Prevents explicit closes during icon moves (CGEvent can flip key status)
    private(set) var isMoveInProgress = false
    private(set) var isBrowseSessionActive = false

    struct SecondMenuBarDiagnostics: Sendable {
        var showRequestedAt: String = "never"
        var currentMode: String = "nil"
        var windowVisible: Bool = false
        var windowFrame: String = "nil"
        var refreshForced: Bool = false
        var visibleCount: Int = 0
        var hiddenCount: Int = 0
        var alwaysHiddenCount: Int = 0
        var relayoutPassCount: Int = 0
        var lastRelayoutAt: String = "never"
        var lastRelayoutReason: String = "none"

        func formattedSummary() -> String {
            """
            secondMenuBar:
              showRequestedAt: \(showRequestedAt)
              currentMode: \(currentMode)
              windowVisible: \(windowVisible)
              windowFrame: \(windowFrame)
              refreshForced: \(refreshForced)
              visibleCount: \(visibleCount)
              hiddenCount: \(hiddenCount)
              alwaysHiddenCount: \(alwaysHiddenCount)
              relayoutPassCount: \(relayoutPassCount)
              lastRelayoutAt: \(lastRelayoutAt)
              lastRelayoutReason: \(lastRelayoutReason)
            """
        }
    }

    func diagnosticsSnapshot() -> String {
        liveDiagnosticsSnapshot().formattedSummary()
    }

    private func liveDiagnosticsSnapshot() -> SecondMenuBarDiagnostics {
        var snapshot = lastSecondMenuBarDiagnostics
        snapshot.currentMode = Self.diagnosticsMode(currentMode)
        snapshot.windowVisible = window?.isVisible == true
        snapshot.windowFrame = Self.diagnosticsRect(window?.frame)
        return snapshot
    }

    func captureBrowsePanelSnapshotPNG(to path: String) -> Bool {
        guard let window, window.isVisible, let contentView = window.contentView else { return false }

        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let bounds = contentView.bounds.integral
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds),
              let outputURL = snapshotOutputURL(for: path) else {
            return false
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: outputURL, options: .atomic)
            return true
        } catch {
            logger.error("browse panel snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func snapshotOutputURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    private static func diagnosticsTimestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    private static func diagnosticsRect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "x=%.1f y=%.1f w=%.1f h=%.1f",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }

    private static func diagnosticsMode(_ mode: SearchWindowMode?) -> String {
        guard let mode else { return "nil" }
        return String(describing: mode)
    }

    nonisolated static func expectedWindowOrigin(
        windowFrame: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        mode: SearchWindowMode,
        statusItemRightEdge: CGFloat?
    ) -> CGPoint {
        switch mode {
        case .findIcon:
            let xPos = visibleFrame.midX - (windowFrame.width / 2)
            let yPos = visibleFrame.maxY - windowFrame.height - 20
            return CGPoint(x: xPos, y: yPos)
        case .secondMenuBar:
            let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
            let rightEdge = statusItemRightEdge ?? (visibleFrame.maxX - 10)
            let xPos = max(visibleFrame.origin.x + 10, rightEdge - windowFrame.width)
            let yPos = screenFrame.maxY - menuBarHeight - windowFrame.height - 4
            return CGPoint(x: xPos, y: yPos)
        }
    }

    nonisolated static func browseWindowAnchorDelta(
        windowFrame: CGRect?,
        screenFrame: CGRect?,
        visibleFrame: CGRect?,
        mode: SearchWindowMode?,
        statusItemRightEdge: CGFloat?
    ) -> CGPoint? {
        guard let windowFrame, let screenFrame, let visibleFrame, let mode else { return nil }
        let expectedOrigin = expectedWindowOrigin(
            windowFrame: windowFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            mode: mode,
            statusItemRightEdge: statusItemRightEdge
        )
        return CGPoint(
            x: windowFrame.origin.x - expectedOrigin.x,
            y: windowFrame.origin.y - expectedOrigin.y
        )
    }

    nonisolated static func isBrowseWindowAnchoredCorrectly(
        windowFrame: CGRect?,
        screenFrame: CGRect?,
        visibleFrame: CGRect?,
        mode: SearchWindowMode?,
        statusItemRightEdge: CGFloat?,
        tolerance: CGFloat = 12
    ) -> Bool {
        guard let delta = browseWindowAnchorDelta(
            windowFrame: windowFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            mode: mode,
            statusItemRightEdge: statusItemRightEdge
        ) else {
            return false
        }
        return abs(delta.x) <= tolerance && abs(delta.y) <= tolerance
    }

    func browseWindowPositionSnapshot() -> [String: Any] {
        let currentWindow = window
        let screen = currentWindow?.screen ?? NSScreen.main
        let frame = currentWindow?.frame
        let screenFrame = screen?.frame
        let visibleFrame = screen?.visibleFrame
        let rightEdge = MenuBarManager.shared.mainStatusItem?.button?.window?.frame.maxX
        let delta = Self.browseWindowAnchorDelta(
            windowFrame: frame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            mode: currentMode,
            statusItemRightEdge: rightEdge
        )

        func optionalDouble(_ value: CGFloat?) -> Any {
            value.map(Double.init) ?? NSNull()
        }

        return [
            "browseWindowMode": Self.diagnosticsMode(currentMode),
            "browseWindowFrame": Self.diagnosticsRect(frame),
            "browseWindowAnchorValid": Self.isBrowseWindowAnchoredCorrectly(
                windowFrame: frame,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                mode: currentMode,
                statusItemRightEdge: rightEdge
            ),
            "browseWindowAnchorDeltaX": optionalDouble(delta?.x),
            "browseWindowAnchorDeltaY": optionalDouble(delta?.y)
        ]
    }

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
        postDismissForceHideTask?.cancel()
        postDismissForceHideTask = nil
        secondMenuBarRelayoutTask?.cancel()
        secondMenuBarRelayoutTask = nil
        isBrowseSessionActive = true

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

        // Unified browse-panel policy:
        // While either panel is visible, suspend rehide timers so icon moves/clicks
        // are not racing with background hide transitions.
        manager.hidingService.cancelRehide()
        logger.info("browse panel show (\(String(describing: desiredMode), privacy: .public)) suspended rehide while panel is visible")

        positionWindow(window, mode: desiredMode)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastSecondMenuBarDiagnostics.showRequestedAt = Self.diagnosticsTimestamp(Date())
        lastSecondMenuBarDiagnostics.currentMode = Self.diagnosticsMode(desiredMode)
        lastSecondMenuBarDiagnostics.windowVisible = window.isVisible
        lastSecondMenuBarDiagnostics.windowFrame = Self.diagnosticsRect(window.frame)
        lastSecondMenuBarDiagnostics.lastRelayoutReason = "show"
        if desiredMode == .secondMenuBar {
            logger.info(
                "secondMenuBar show frame=\(Self.diagnosticsRect(window.frame), privacy: .public) visible=\(window.isVisible, privacy: .public)"
            )
            scheduleDeferredSecondMenuBarRelayoutIfNeeded()
        }

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
        let wasInProgress = isMoveInProgress
        isMoveInProgress = inProgress
        if wasInProgress, !inProgress {
            NotificationCenter.default.post(name: Self.iconMoveDidFinishNotification, object: nil)
        }
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
        postDismissForceHideTask?.cancel()
        postDismissForceHideTask = nil
        secondMenuBarRelayoutTask?.cancel()
        secondMenuBarRelayoutTask = nil
        isBrowseSessionActive = false
        lastSecondMenuBarDiagnostics.currentMode = Self.diagnosticsMode(currentMode)
        lastSecondMenuBarDiagnostics.windowVisible = false
        lastSecondMenuBarDiagnostics.windowFrame = Self.diagnosticsRect(window?.frame)
        lastSecondMenuBarDiagnostics.lastRelayoutAt = Self.diagnosticsTimestamp(Date())
        lastSecondMenuBarDiagnostics.lastRelayoutReason = reason

        // Resume hover/click triggers and refresh pointer state before scheduling rehide.
        // Use strict menu-strip bounds on panel dismiss so the nearby panel area
        // doesn't keep rehide blocked as "menu interaction."
        manager.hoverService.isSuspended = false
        manager.hoverService.refreshMouseInMenuBarStateForBrowseDismissal()
        Task { @MainActor [weak self] in
            // Window teardown and AppKit focus transitions can lag one runloop.
            // Re-sample once shortly after dismissal to avoid stale hover-blocked rehide.
            try? await Task.sleep(for: .milliseconds(160))
            guard let self else { return }
            guard !self.isBrowseSessionActive else { return }
            manager.hoverService.refreshMouseInMenuBarStateForBrowseDismissal()
        }

        if manager.hidingService.state == .expanded,
           !manager.shouldSkipHideForExternalMonitor {
            let dismissDelaySeconds = max(
                browseDismissRehideDelay(baseDelay: manager.settings.rehideDelay),
                remainingActivationGracePeriod(for: currentMode)
            )
            manager.hidingService.scheduleRehide(after: dismissDelaySeconds)
            logger.info("\(reason, privacy: .public) scheduled rehide after \(dismissDelaySeconds, privacy: .public)s")
            scheduleForceRehideAfterBrowseDismissal(mode: currentMode, baseDelay: dismissDelaySeconds, reason: reason)
        }

        // Do NOT set window to nil, we reuse it for performance
        logger.info("\(reason, privacy: .public) completed (window hidden, cache retained)")
    }

    private func scheduleForceRehideAfterBrowseDismissal(
        mode: SearchWindowMode?,
        baseDelay: TimeInterval,
        reason: String
    ) {
        let manager = MenuBarManager.shared
        let fallbackDelaySeconds = fallbackRehideDelay(for: mode, baseDelay: baseDelay)

        postDismissForceHideTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(fallbackDelaySeconds))
            guard !Task.isCancelled else { return }
            guard self.window?.isVisible != true else { return }
            guard !self.isMoveInProgress else { return }
            guard manager.hidingService.state == .expanded else { return }
            guard !manager.shouldSkipHideForExternalMonitor else { return }
            guard !manager.isMenuOpen else { return }

            logger.info(
                "\(reason, privacy: .public) forced rehide after \(fallbackDelaySeconds, privacy: .public)s fallback window"
            )
            await manager.hidingService.hide()
        }
    }

    private func browseDismissRehideDelay(baseDelay: TimeInterval) -> TimeInterval {
        max(1, baseDelay)
    }

    private func fallbackRehideDelay(for mode: SearchWindowMode?, baseDelay: TimeInterval) -> TimeInterval {
        let normalizedBase = max(1, baseDelay)
        switch mode {
        case .secondMenuBar:
            // Keep second menu bar more permissive while still bounded.
            return min(20, max(12, normalizedBase + 4))
        case .none, .findIcon:
            return min(12, max(8, normalizedBase + 2))
        }
    }

    static func panelIdleCloseActivationGracePeriod(for mode: SearchWindowMode) -> TimeInterval {
        switch mode {
        case .secondMenuBar:
            return 4
        case .findIcon:
            return 1.5
        }
    }

    static func shouldDeferPanelIdleClose(
        mode: SearchWindowMode,
        pointerInsidePanel: Bool,
        activationInFlight: Bool,
        secondsSinceLastActivation: TimeInterval?
    ) -> Bool {
        if pointerInsidePanel {
            return true
        }
        if mode != .secondMenuBar {
            return false
        }
        if activationInFlight {
            return true
        }
        guard let secondsSinceLastActivation else { return false }
        return secondsSinceLastActivation < panelIdleCloseActivationGracePeriod(for: mode)
    }

    private func remainingActivationGracePeriod(for mode: SearchWindowMode?, now: Date = Date()) -> TimeInterval {
        guard mode == .secondMenuBar else { return 0 }
        let grace = Self.panelIdleCloseActivationGracePeriod(for: .secondMenuBar)
        if browseActivationInFlightCount > 0 {
            return grace
        }
        guard let lastBrowseActivationFinishedAt else { return 0 }
        let elapsed = now.timeIntervalSince(lastBrowseActivationFinishedAt)
        return max(0, grace - elapsed)
    }

    func noteBrowseActivationStarted() {
        guard currentMode == .secondMenuBar else { return }
        browseActivationInFlightCount += 1
        if window?.isVisible == true {
            schedulePanelIdleCloseIfNeeded(for: .secondMenuBar)
        }
    }

    func noteBrowseActivationFinished() {
        guard currentMode == .secondMenuBar || browseActivationInFlightCount > 0 else { return }
        if browseActivationInFlightCount > 0 {
            browseActivationInFlightCount -= 1
        }
        lastBrowseActivationFinishedAt = Date()
        if window?.isVisible == true, currentMode == .secondMenuBar {
            schedulePanelIdleCloseIfNeeded(for: .secondMenuBar)
        }
    }

    func noteSecondMenuBarInteraction() {
        guard currentMode == .secondMenuBar, window?.isVisible == true else { return }
        schedulePanelIdleCloseIfNeeded(for: .secondMenuBar)
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
                let pointerInsidePanel = self.window?.frame.contains(NSEvent.mouseLocation) == true
                let secondsSinceLastActivation = self.lastBrowseActivationFinishedAt.map { Date().timeIntervalSince($0) }

                if Self.shouldDeferPanelIdleClose(
                    mode: mode,
                    pointerInsidePanel: pointerInsidePanel,
                    activationInFlight: self.browseActivationInFlightCount > 0,
                    secondsSinceLastActivation: secondsSinceLastActivation
                ) {
                    let deferReason: String
                    if pointerInsidePanel {
                        deferReason = "pointer still in panel"
                    } else if self.browseActivationInFlightCount > 0 {
                        deferReason = "browse activation still in flight"
                    } else {
                        deferReason = "recent second menu bar activation"
                    }
                    logger.debug("panel idle timeout deferred (\(idleDelaySeconds, privacy: .public)s): \(deferReason, privacy: .public)")
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

        guard wasVisible else {
            isBrowseSessionActive = false
            return
        }

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

    func refitSecondMenuBarWindowIfNeeded() {
        guard currentMode == .secondMenuBar, let window else { return }
        guard window.isVisible else { return }
        positionWindow(window, mode: .secondMenuBar)
        lastSecondMenuBarDiagnostics.windowVisible = window.isVisible
        lastSecondMenuBarDiagnostics.windowFrame = Self.diagnosticsRect(window.frame)
        lastSecondMenuBarDiagnostics.lastRelayoutAt = Self.diagnosticsTimestamp(Date())
        lastSecondMenuBarDiagnostics.lastRelayoutReason = "refit"
        lastSecondMenuBarDiagnostics.relayoutPassCount += 1
        logger.info(
            "secondMenuBar relayout pass=\(self.lastSecondMenuBarDiagnostics.relayoutPassCount, privacy: .public) frame=\(Self.diagnosticsRect(window.frame), privacy: .public)"
        )
    }

    private func scheduleDeferredSecondMenuBarRelayoutIfNeeded() {
        guard currentMode == .secondMenuBar else { return }

        secondMenuBarRelayoutTask?.cancel()
        secondMenuBarRelayoutTask = Task { [weak self] in
            for delay in [180, 520] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.refitSecondMenuBarWindowIfNeeded()
                }
            }
        }
    }

    func recordSecondMenuBarClassifiedCounts(
        visible: Int,
        hidden: Int,
        alwaysHidden: Int,
        forcedRefresh: Bool
    ) {
        lastSecondMenuBarDiagnostics.currentMode = Self.diagnosticsMode(currentMode)
        lastSecondMenuBarDiagnostics.refreshForced = forcedRefresh
        lastSecondMenuBarDiagnostics.visibleCount = visible
        lastSecondMenuBarDiagnostics.hiddenCount = hidden
        lastSecondMenuBarDiagnostics.alwaysHiddenCount = alwaysHidden
        lastSecondMenuBarDiagnostics.windowVisible = window?.isVisible == true
        lastSecondMenuBarDiagnostics.windowFrame = Self.diagnosticsRect(window?.frame)
        lastSecondMenuBarDiagnostics.lastRelayoutAt = Self.diagnosticsTimestamp(Date())
        lastSecondMenuBarDiagnostics.lastRelayoutReason = "classified-refresh"
        logger.info(
            "secondMenuBar refresh forced=\(forcedRefresh, privacy: .public) visible=\(visible, privacy: .public) hidden=\(hidden, privacy: .public) alwaysHidden=\(alwaysHidden, privacy: .public)"
        )
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
