import AppKit

extension SearchWindowController {
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

    static func shouldForceAlwaysHiddenForIconPanel(
        mode: SearchWindowMode,
        isPro: Bool,
        useSecondMenuBar: Bool,
        alwaysHiddenEnabled: Bool
    ) -> Bool {
        // Icon Panel is the primary browse workflow. Keep always-hidden enabled for Pro there.
        mode == .findIcon && isPro && !useSecondMenuBar && !alwaysHiddenEnabled
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

    nonisolated static func clampedSecondMenuBarSize(
        currentWindowSize: CGSize,
        fittingSize: CGSize?,
        visibleFrame: CGRect,
        useContentFittingSize: Bool
    ) -> CGSize {
        let baseSize = if useContentFittingSize, let fittingSize {
            fittingSize
        } else {
            currentWindowSize
        }

        return CGSize(
            width: min(max(baseSize.width, 200), min(visibleFrame.width - 20, 800)),
            height: min(max(baseSize.height, 80), 500)
        )
    }
}
