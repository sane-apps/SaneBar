import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "SearchWindowController")


enum SearchWindowMode {
    case findIcon
    case secondMenuBar
}


private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}


@MainActor
final class SearchWindowController: NSObject, NSWindowDelegate {

    static let shared = SearchWindowController()

    static let windowDidShowNotification = Notification.Name("SearchWindowController.windowDidShow")
    static let iconMoveDidFinishNotification = Notification.Name("SearchWindowController.iconMoveDidFinish")


    private var window: NSWindow?

    private var currentMode: SearchWindowMode?

    private var panelIdleCloseTask: Task<Void, Never>?
    private var panelIdleCloseGeneration: Int = 0
    private var postDismissForceHideTask: Task<Void, Never>?
    private var secondMenuBarRelayoutTask: Task<Void, Never>?
    private var browseActivationInFlightCount: Int = 0
    private var lastBrowseActivationFinishedAt: Date?
    private var lastSecondMenuBarDiagnostics = SecondMenuBarDiagnostics()

    private(set) var isMoveInProgress = false
    private(set) var isBrowseSessionActive = false

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

    func browseWindowPositionSnapshot() -> [String: Any] {
        let currentWindow = window
        let screen = currentWindow?.screen ?? NSScreen.main
        let frame = currentWindow?.frame
        let screenFrame = screen?.frame
        let visibleFrame = screen?.visibleFrame
        let rightEdge = MenuBarManager.shared.mainStatusItem?.button?.window?.frame.maxX
        let delta = SearchWindowLayoutPolicy.browseWindowAnchorDelta(
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
            "browseWindowAnchorValid": SearchWindowLayoutPolicy.isBrowseWindowAnchoredCorrectly(
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

    var activeMode: SearchWindowMode {
        MenuBarManager.shared.settings.useSecondMenuBar ? .secondMenuBar : .findIcon
    }

    var isVisible: Bool {
        window?.isVisible == true
    }


    func toggle(mode: SearchWindowMode? = nil) {
        if let window, window.isVisible, currentMode == (mode ?? activeMode) {
            close(ignoringBrowseActivationGrace: true)
        } else if MenuBarManager.shared.settings.requireAuthToShowHiddenIcons {
            Task {
                let authorized = await MenuBarManager.shared.visibilityWorkflow.authenticate(reason: "Unlock hidden icons")
                guard authorized else { return }
                show(mode: mode)
            }
        } else {
            show(mode: mode)
        }
    }

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

        if currentMode != nil, currentMode != desiredMode {
            resetWindow()
        }

        let didCreateWindow = window == nil

        if window == nil {
            createWindow(mode: desiredMode, prefill: searchText)
        }

        guard let window else { return }
        applyDarkAppearance(to: window)

        if desiredMode == .findIcon, !didCreateWindow {
            if let searchText, !searchText.isEmpty {
                NotificationCenter.default.post(name: MenuBarSearchView.setSearchTextNotification, object: searchText)
            } else {
                NotificationCenter.default.post(name: MenuBarSearchView.resetSearchNotification, object: nil)
            }
        }

        manager.hoverService.isSuspended = true

        manager.hidingService.cancelRehide()
        logger.info("browse panel show (\(String(describing: desiredMode), privacy: .public)) suspended rehide while panel is visible")

        positionWindow(
            window,
            mode: desiredMode,
            useContentFittingSize: desiredMode != .secondMenuBar
        )
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

        NotificationCenter.default.post(name: Self.windowDidShowNotification, object: nil)

        schedulePanelIdleCloseIfNeeded(for: desiredMode)
    }

    private func normalizeBrowseModeSettings(for mode: SearchWindowMode) {
        let manager = MenuBarManager.shared
        if SearchWindowLayoutPolicy.shouldForceAlwaysHiddenForIconPanel(
            mode: mode,
            isPro: LicenseService.shared.isPro,
            useSecondMenuBar: manager.settings.useSecondMenuBar,
            alwaysHiddenEnabled: manager.settings.alwaysHiddenSectionEnabled
        ) {
            manager.settings.alwaysHiddenSectionEnabled = true
        }
    }

    func setMoveInProgress(_ inProgress: Bool) {
        let wasInProgress = isMoveInProgress
        isMoveInProgress = inProgress
        if wasInProgress, !inProgress {
            NotificationCenter.default.post(name: Self.iconMoveDidFinishNotification, object: nil)
        }
    }

    func close(ignoringBrowseActivationGrace: Bool = false) {
        guard !isMoveInProgress else { return }

        guard ignoringBrowseActivationGrace || !shouldDeferCloseForBrowseActivation() else {
            logger.info("close deferred during recent second menu bar activation")
            schedulePanelIdleCloseIfNeeded(for: .secondMenuBar)
            return
        }

        window?.orderOut(nil)
        handleBrowseDismissal(reason: "close")
    }

    private func shouldDeferCloseForBrowseActivation(now: Date = Date()) -> Bool {
        guard currentMode == .secondMenuBar, window?.isVisible == true else { return false }

        let secondsSinceLastActivation = lastBrowseActivationFinishedAt.map { now.timeIntervalSince($0) }
        return SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
            mode: .secondMenuBar,
            pointerInsidePanel: false,
            activationInFlight: browseActivationInFlightCount > 0,
            secondsSinceLastActivation: secondsSinceLastActivation
        )
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

        manager.hoverService.isSuspended = false
        manager.hoverService.refreshMouseInMenuBarStateForBrowseDismissal()
        Task { @MainActor [weak self] in
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
            return min(20, max(12, normalizedBase + 4))
        case .none, .findIcon:
            return min(12, max(8, normalizedBase + 2))
        }
    }

    private func remainingActivationGracePeriod(for mode: SearchWindowMode?, now: Date = Date()) -> TimeInterval {
        guard mode == .secondMenuBar else { return 0 }
        let grace = SearchWindowLayoutPolicy.panelIdleCloseActivationGracePeriod(for: .secondMenuBar)
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

                if SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
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

                if manager.hidingService.state == .expanded,
                   !manager.shouldSkipHideForExternalMonitor {
                    manager.hidingService.scheduleRehide(after: 0.2)
                    logger.info("panel idle timeout forced quick rehide")
                }
            }
        }
    }

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

        handleBrowseDismissal(reason: "resetWindow")
    }

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
        positionWindow(window, mode: .secondMenuBar, useContentFittingSize: true)
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


    private func positionWindow(
        _ window: NSWindow,
        mode: SearchWindowMode,
        useContentFittingSize: Bool = true
    ) {
        guard let screen = NSScreen.main else { return }

        switch mode {
        case .findIcon:
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let xPos = screenFrame.midX - (windowSize.width / 2)
            let yPos = screenFrame.maxY - windowSize.height - 20
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))

        case .secondMenuBar:
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y

            if useContentFittingSize {
                window.contentView?.layoutSubtreeIfNeeded()
            }
            let panelSize = SearchWindowLayoutPolicy.clampedSecondMenuBarSize(
                currentWindowSize: window.frame.size,
                fittingSize: window.contentView?.fittingSize,
                visibleFrame: visibleFrame,
                useContentFittingSize: useContentFittingSize
            )

            let rightEdge: CGFloat = if let button = MenuBarManager.shared.mainStatusItem?.button,
                                        let buttonWindow = button.window {
                buttonWindow.frame.maxX
            } else {
                visibleFrame.maxX - 10
            }
            let xPos = max(visibleFrame.origin.x + 10, rightEdge - panelSize.width)
            let yPos = screenFrame.maxY - menuBarHeight - panelSize.height - 4

            window.setFrame(
                NSRect(x: xPos, y: yPos, width: panelSize.width, height: panelSize.height),
                display: true
            )
        }
    }


    private func createWindow(mode: SearchWindowMode, prefill searchText: String? = nil) {
        currentMode = mode

        switch mode {
        case .findIcon:
            createFindIconWindow(prefill: searchText)
        case .secondMenuBar:
            createSecondMenuBarWindow()
        }
    }

    private func createFindIconWindow(prefill searchText: String? = nil) {
        let contentView = MenuBarSearchView(
            initialSearchText: searchText,
            onDismiss: { [weak self] in
                self?.close(ignoringBrowseActivationGrace: true)
            }
        )
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
                self?.close(ignoringBrowseActivationGrace: true)
            }
        )
        .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: contentView)
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

        panel.acceptsMouseMovedEvents = true

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


    func windowDidResignKey(_: Notification) {
        guard !isMoveInProgress else { return }
    }

    func windowDidBecomeKey(_: Notification) {}

    func windowWillClose(_: Notification) {
        guard !isMoveInProgress else { return }

        handleBrowseDismissal(reason: "windowWillClose")
    }

}
