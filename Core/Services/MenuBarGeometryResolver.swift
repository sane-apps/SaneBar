import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarGeometryResolver")

@MainActor
final class MenuBarGeometryResolver {
    private unowned let manager: MenuBarManager
    private let cache: MenuBarGeometryCache

    init(manager: MenuBarManager) {
        self.manager = manager
        cache = manager.geometryCache
    }

    /// Screen-relative liveness for a status-item window's TRUE frame that
    /// tolerates AppKit returning a nil `NSWindow.screen`. When `window.screen` is
    /// populated we judge against it exactly as before; when it is nil (off-edge
    /// hidden separator, external-display topology churn) we recover the
    /// screen-relative judgement by testing the frame against the known candidate
    /// screens. Off-screen frames match no band and stay rejected — this only
    /// fixes the false-negative where a live frame lost its `.screen` attachment
    /// and was wrongly demoted to `.stale`/`.missing`, stranding recovery.
    private func windowFrameIsLive(_ window: NSWindow) -> Bool {
        let resolvedScreenFrame = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: window.frame,
            attachedScreenFrame: window.screen?.frame,
            candidateScreenFrames: candidateScreenFramesForLiveness()
        )
        return MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
            frame: window.frame,
            screenFrame: resolvedScreenFrame
        )
    }

    /// Screens the status items could legitimately live on, most-likely first.
    /// The recovery reference screen (the display that currently owns SaneBar's
    /// items) leads so the common single/active-display case resolves immediately;
    /// the remaining screens cover multi-display setups. No synthetic screens.
    private func candidateScreenFramesForLiveness() -> [CGRect] {
        var frames: [CGRect] = []
        if let referenceFrame = manager.currentRecoveryReferenceScreen()?.frame {
            frames.append(referenceFrame)
        }
        for screen in NSScreen.screens where !frames.contains(screen.frame) {
            frames.append(screen.frame)
        }
        return frames
    }

    func resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: Bool = true) -> CGFloat? {
        // Never write the normalized result back to the cache: it can be
        // estimate-derived, and laundering estimates into "cached" status is
        // how stale geometry gained trust in the #136 drift family.
        MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: cache.lastKnownSeparatorRightEdgeX,
            cachedOrigin: cache.lastKnownSeparatorX,
            estimatedRightEdge: allowEstimatedFallback ? estimatedSeparatorEdgesFromMainIcon()?.rightEdgeX : nil,
            mainLeftEdge: mainStatusItemLeftEdgeX()
        )
    }

    func estimatedSeparatorEdgesFromMainIcon() -> (originX: CGFloat, rightEdgeX: CGFloat)? {
        guard let mainLeftEdgeX = mainStatusItemLeftEdgeX(), mainLeftEdgeX.isFinite else { return nil }

        let visualWidth: CGFloat = MenuBarMoveGeometryPolicy.separatorVisualWidth
        let originX = mainLeftEdgeX - visualWidth
        let rightEdgeX = originX + visualWidth
        return (originX, rightEdgeX)
    }

    func estimatedMainStatusItemLeftEdgeFromSeparator() -> CGFloat? {
        guard let separatorItem = manager.separatorItem, separatorItem.length <= 1000 else { return nil }

        if let frame = currentLiveSeparatorFrame() {
            cache.lastKnownSeparatorX = frame.origin.x
            let rightEdge = MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
                separatorIsPresentInVisualMode: true,
                separatorRightEdge: frame.origin.x + frame.width,
                separatorOrigin: frame.origin.x
            ) ?? (frame.origin.x + frame.width)
            cache.lastKnownSeparatorRightEdgeX = rightEdge
            return rightEdge
        }

        // Estimated values are returned to the caller but never cached.
        return MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
            separatorIsPresentInVisualMode: true,
            separatorRightEdge: cache.lastKnownSeparatorRightEdgeX,
            separatorOrigin: cache.lastKnownSeparatorX
        )
    }

    func currentLiveSeparatorFrame() -> CGRect? {
        guard let separatorItem = manager.separatorItem, separatorItem.length <= 1000,
              let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            return nil
        }

        let frame = separatorWindow.frame
        guard windowFrameIsLive(separatorWindow) else {
            return nil
        }
        return frame
    }

    func currentLiveAlwaysHiddenSeparatorFrame() -> CGRect? {
        // Liveness is judged SOLELY by the screen-relative window-frame check.
        // The previous `length <= 1000` clause was redundant with (and weaker
        // than) `statusItemWindowFrameIsReadableLive`: a hidden AH separator uses
        // length 10000 to push items off-screen, but its own window may still sit
        // live in the menu-bar band (and outbound moves contract it back to a
        // small visual length first). The length cap therefore could never return
        // live for a hidden separator and silently blocked outbound Always-Hidden
        // moves (#155/#156/#166). Off-screen rejection is preserved by the
        // window-frame band check, which is independent of `length`.
        guard let alwaysHiddenSeparatorItem = manager.alwaysHiddenSeparatorItem,
              let separatorButton = alwaysHiddenSeparatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            return nil
        }

        let frame = separatorWindow.frame
        // `windowFrameIsLive` IS the screen-relative readable-live decision
        // (statusItemWindowFrameIsReadableLive delegates to statusItemFrameLooksLive),
        // now with the nil-`window.screen` recovery applied.
        guard windowFrameIsLive(separatorWindow) else {
            return nil
        }
        return frame
    }

    func currentLiveAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: Bool = false) -> CGFloat? {
        guard let alwaysHiddenFrame = currentLiveAlwaysHiddenSeparatorFrame() else {
            return nil
        }

        let separatorBoundaryX: CGFloat? = if let separatorFrame = currentLiveSeparatorFrame() {
            separatorFrame.origin.x + separatorFrame.width
        } else if allowCachedMainSeparator {
            separatorRightEdgeX(allowEstimatedFallback: false)
        } else {
            nil
        }

        let normalized = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
            cachedRightEdge: alwaysHiddenFrame.origin.x + alwaysHiddenFrame.width,
            cachedOrigin: alwaysHiddenFrame.origin.x,
            separatorX: separatorBoundaryX
        )
        if let normalized {
            cache.lastKnownAlwaysHiddenSeparatorX = alwaysHiddenFrame.origin.x
            cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
        }
        return normalized
    }

    func inboundAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: Bool = false) -> CGFloat? {
        if let liveBoundary = currentLiveAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: allowCachedMainSeparator) {
            let notchRightSafeMinX = manager.currentRecoveryReferenceScreen()?.auxiliaryTopRightArea?.minX
            if !StatusBarPositionStore.alwaysHiddenSeparatorNeedsNotchSafeRepair(
                alwaysHiddenSeparatorRightEdgeX: liveBoundary,
                notchRightSafeMinX: notchRightSafeMinX
            ) {
                return liveBoundary
            }
            logger.warning("Rejecting live AH separator boundary \(liveBoundary, privacy: .public) for inbound move because it still needs notch-safe repair")
        }

        guard let alwaysHiddenSeparatorItem = manager.alwaysHiddenSeparatorItem else {
            logger.warning("Cannot seed inbound AH separator boundary: AH separator item is missing")
            return nil
        }
        guard let referenceScreen = manager.currentRecoveryReferenceScreen() else {
            logger.warning("Cannot seed inbound AH separator boundary: reference screen is missing")
            return nil
        }

        let preferredPosition = StatusBarPositionDefaultsStore.resolvedPreferredPosition(
            forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName
        ) ?? StatusBarPositionStore.alwaysHiddenPreferredPosition(referenceScreen: referenceScreen)
        guard preferredPosition.isFinite,
              preferredPosition < 9000
        else {
            logger.warning("Cannot seed inbound AH separator boundary: preferred position \(preferredPosition, privacy: .public) is not a finite screen-relative position")
            return nil
        }

        let separatorBoundaryX: CGFloat? = if let separatorFrame = currentLiveSeparatorFrame() {
            separatorFrame.origin.x + separatorFrame.width
        } else if allowCachedMainSeparator {
            separatorRightEdgeX(allowEstimatedFallback: false)
        } else {
            nil
        }

        let seededBoundaryX = referenceScreen.frame.maxX - CGFloat(preferredPosition)
        let normalized: CGFloat?
        if let separatorBoundaryX {
            let separatorRelativeBoundary = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
                cachedRightEdge: seededBoundaryX,
                cachedOrigin: seededBoundaryX - MenuBarMoveGeometryPolicy.separatorVisualWidth,
                separatorX: separatorBoundaryX
            )
            if let separatorRelativeBoundary {
                normalized = separatorRelativeBoundary
            } else if allowCachedMainSeparator, seededBoundaryX.isFinite {
                normalized = seededBoundaryX
                logger.warning("Using seeded AH separator boundary after rejecting stale main separator boundary \(separatorBoundaryX, privacy: .public) for inbound move")
            } else {
                normalized = nil
            }
        } else if allowCachedMainSeparator, seededBoundaryX.isFinite {
            normalized = seededBoundaryX
            logger.warning("Using seeded AH separator boundary without a live/cached main separator boundary for inbound move")
        } else {
            normalized = nil
        }
        if let normalized {
            cache.lastKnownAlwaysHiddenSeparatorX = normalized - MenuBarMoveGeometryPolicy.separatorVisualWidth
            cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
            logger.warning("Using seeded AH separator boundary \(normalized, privacy: .public) for inbound move while live AH frame is unavailable; item length \(alwaysHiddenSeparatorItem.length, privacy: .public)")
        }
        return normalized
    }

    func currentSeparatorAnchorSource() -> MenuBarAnchorSource {
        guard let separatorItem = manager.separatorItem else {
            if cache.lastKnownSeparatorX != nil { return .cached }
            if estimatedSeparatorEdgesFromMainIcon() != nil { return .estimated }
            return .missing
        }

        if separatorItem.length > 1000 {
            if cache.lastKnownSeparatorX != nil { return .cached }
            if estimatedSeparatorEdgesFromMainIcon() != nil { return .estimated }
            return .missing
        }

        if let frame = currentLiveSeparatorFrame() {
            cache.lastKnownSeparatorX = frame.origin.x
            cache.lastKnownSeparatorRightEdgeX = frame.origin.x + frame.width
            return .live
        }

        if cache.lastKnownSeparatorX != nil { return .cached }
        if estimatedSeparatorEdgesFromMainIcon() != nil { return .estimated }
        return .missing
    }

    func currentMainStatusItemAnchorSource() -> MenuBarAnchorSource {
        guard let mainButton = manager.mainStatusItem?.button,
              let mainWindow = mainButton.window
        else {
            if cache.lastKnownMainStatusItemX != nil { return .cached }
            if estimatedMainStatusItemLeftEdgeFromSeparator() != nil { return .estimated }
            return .missing
        }

        let frame = mainWindow.frame
        if windowFrameIsLive(mainWindow) {
            cache.lastKnownMainStatusItemX = frame.origin.x
            return .live
        }

        if cache.lastKnownMainStatusItemX != nil { return .cached }
        if estimatedMainStatusItemLeftEdgeFromSeparator() != nil { return .estimated }
        return .missing
    }

    func separatorOriginX(allowEstimatedFallback: Bool = true) -> CGFloat? {
        guard let separatorItem = manager.separatorItem else { return cache.lastKnownSeparatorX }

        if separatorItem.length > 1000 {
            if let cachedX = cache.lastKnownSeparatorX {
                logger.debug("getSeparatorOriginX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
                return cachedX
            }

            if allowEstimatedFallback, let estimated = estimatedSeparatorEdgesFromMainIcon() {
                logger.warning("getSeparatorOriginX: blocking mode with empty cache, using estimated \(estimated.originX)")
                return estimated.originX
            }

            let cachedX = cache.lastKnownSeparatorX ?? -1
            logger.debug("getSeparatorOriginX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
            return cache.lastKnownSeparatorX
        }

        guard let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            return cache.lastKnownSeparatorX
        }
        let frame = separatorWindow.frame
        let x = frame.origin.x
        if windowFrameIsLive(separatorWindow) {
            cache.lastKnownSeparatorX = x
            cache.lastKnownSeparatorRightEdgeX = frame.origin.x + frame.width
            return x
        }

        if let cachedX = cache.lastKnownSeparatorX {
            return cachedX
        }

        if allowEstimatedFallback, let estimated = estimatedSeparatorEdgesFromMainIcon() {
            logger.warning("getSeparatorOriginX: stale/off-screen frame with empty cache, using estimated \(estimated.originX)")
            return estimated.originX
        }

        return nil
    }

    func alwaysHiddenSeparatorOriginX() -> CGFloat? {
        guard let item = manager.alwaysHiddenSeparatorItem else { return nil }

        if item.length > 1000 {
            return cache.lastKnownAlwaysHiddenSeparatorX
        }

        guard let separatorButton = item.button,
              let separatorWindow = separatorButton.window
        else {
            return cache.lastKnownAlwaysHiddenSeparatorX
        }
        let frame = separatorWindow.frame
        if windowFrameIsLive(separatorWindow) {
            cache.lastKnownAlwaysHiddenSeparatorX = frame.origin.x
            cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = frame.origin.x + frame.width
            return frame.origin.x
        }

        return cache.lastKnownAlwaysHiddenSeparatorX
    }

    func alwaysHiddenSeparatorBoundaryX() -> CGFloat? {
        let separatorX = separatorRightEdgeX() ?? separatorOriginX()

        guard let item = manager.alwaysHiddenSeparatorItem else {
            let normalized = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
                cachedRightEdge: cache.lastKnownAlwaysHiddenSeparatorRightEdgeX,
                cachedOrigin: cache.lastKnownAlwaysHiddenSeparatorX,
                separatorX: separatorX
            )
            if let normalized {
                cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
                return normalized
            }
            return nil
        }

        if item.length > 1000 {
            let normalized = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
                cachedRightEdge: cache.lastKnownAlwaysHiddenSeparatorRightEdgeX,
                cachedOrigin: cache.lastKnownAlwaysHiddenSeparatorX ?? alwaysHiddenSeparatorOriginX(),
                separatorX: separatorX
            )
            if let normalized {
                cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
                return normalized
            }
            return nil
        }

        if let button = item.button,
           let window = button.window {
            let frame = window.frame
            if windowFrameIsLive(window) {
                let normalized = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
                    cachedRightEdge: frame.origin.x + frame.width,
                    cachedOrigin: frame.origin.x,
                    separatorX: separatorX
                )
                cache.lastKnownAlwaysHiddenSeparatorX = frame.origin.x
                if let normalized {
                    cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
                    return normalized
                }
            }
        }

        let normalized = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
            cachedRightEdge: cache.lastKnownAlwaysHiddenSeparatorRightEdgeX,
            cachedOrigin: cache.lastKnownAlwaysHiddenSeparatorX ?? alwaysHiddenSeparatorOriginX(),
            separatorX: separatorX
        )
        if let normalized {
            cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
            return normalized
        }

        return nil
    }

    func separatorRightEdgeX(allowEstimatedFallback: Bool = true) -> CGFloat? {
        guard let separatorItem = manager.separatorItem else {
            logger.error("getSeparatorRightEdgeX: separatorItem is nil")
            return resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: allowEstimatedFallback)
        }

        if separatorItem.length > 1000 {
            guard let cachedX = resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: allowEstimatedFallback),
                  cachedX.isFinite
            else {
                logger.debug("getSeparatorRightEdgeX: blocking mode (length=\(separatorItem.length)), no cached right edge available")
                return nil
            }
            logger.debug("getSeparatorRightEdgeX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
            return cachedX
        }

        guard let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            logger.error("getSeparatorRightEdgeX: button or window is nil")
            return resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: allowEstimatedFallback)
        }
        let frame = separatorWindow.frame
        logger.debug("getSeparatorRightEdgeX: window.frame = \(String(describing: frame))")
        guard frame.width > 0 else {
            logger.error("getSeparatorRightEdgeX: frame.width is 0")
            return resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: allowEstimatedFallback)
        }

        if !windowFrameIsLive(separatorWindow) {
            if let cachedX = resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: allowEstimatedFallback) {
                if !cache.hasLoggedStaleSeparatorRightEdgeFallback {
                    logger.warning("getSeparatorRightEdgeX: stale frame (w=\(frame.width), x=\(frame.origin.x)), using cached \(cachedX)")
                    cache.hasLoggedStaleSeparatorRightEdgeFallback = true
                }
                return cachedX
            }

            if allowEstimatedFallback, let estimated = estimatedSeparatorEdgesFromMainIcon() {
                if !cache.hasLoggedStaleSeparatorRightEdgeFallback {
                    logger.warning("getSeparatorRightEdgeX: stale frame with empty cache, using estimated \(estimated.rightEdgeX)")
                    cache.hasLoggedStaleSeparatorRightEdgeFallback = true
                }
                return estimated.rightEdgeX
            }

            if !cache.hasLoggedStaleSeparatorRightEdgeFallback {
                logger.warning("getSeparatorRightEdgeX: stale frame and no fallback available")
                cache.hasLoggedStaleSeparatorRightEdgeFallback = true
            }
            return nil
        }

        cache.hasLoggedStaleSeparatorRightEdgeFallback = false
        cache.lastKnownSeparatorX = frame.origin.x
        let rightEdge = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: frame.origin.x + frame.width,
            cachedOrigin: frame.origin.x,
            estimatedRightEdge: nil,
            mainLeftEdge: mainStatusItemLeftEdgeX()
        ) ?? (frame.origin.x + frame.width)
        cache.lastKnownSeparatorRightEdgeX = rightEdge
        logger.debug("getSeparatorRightEdgeX: returning \(rightEdge)")
        return rightEdge
    }

    func mainStatusItemLeftEdgeX() -> CGFloat? {
        guard let mainButton = manager.mainStatusItem?.button,
              let mainWindow = mainButton.window
        else {
            if let cachedX = cache.lastKnownMainStatusItemX {
                logger.error("getMainStatusItemLeftEdgeX: mainStatusItem or window is nil, using cached \(cachedX)")
                return cachedX
            }

            if let estimated = estimatedMainStatusItemLeftEdgeFromSeparator() {
                logger.warning("getMainStatusItemLeftEdgeX: mainStatusItem or window is nil, using separator fallback \(estimated)")
                return estimated
            }

            logger.error("getMainStatusItemLeftEdgeX: mainStatusItem or window is nil")
            return nil
        }
        let frame = mainWindow.frame
        logger.debug("getMainStatusItemLeftEdgeX: window.frame = \(String(describing: frame))")
        if windowFrameIsLive(mainWindow) {
            cache.hasLoggedStaleMainStatusItemFallback = false
            cache.lastKnownMainStatusItemX = frame.origin.x
            return frame.origin.x
        }

        if let cachedX = cache.lastKnownMainStatusItemX {
            if !cache.hasLoggedStaleMainStatusItemFallback {
                logger.warning("getMainStatusItemLeftEdgeX: stale frame (w=\(frame.width), x=\(frame.origin.x)), using cached \(cachedX)")
                cache.hasLoggedStaleMainStatusItemFallback = true
            }
            return cachedX
        }

        if let estimated = estimatedMainStatusItemLeftEdgeFromSeparator() {
            if !cache.hasLoggedStaleMainStatusItemFallback {
                logger.warning("getMainStatusItemLeftEdgeX: stale frame (w=\(frame.width), x=\(frame.origin.x)), using separator fallback \(estimated)")
                cache.hasLoggedStaleMainStatusItemFallback = true
            }
            return estimated
        }

        if !cache.hasLoggedStaleMainStatusItemFallback {
            logger.warning("getMainStatusItemLeftEdgeX: stale frame and no fallback available")
            cache.hasLoggedStaleMainStatusItemFallback = true
        }
        return nil
    }

    func warmSeparatorPositionCache(maxAttempts: Int = 12) async {
        for attempt in 1 ... maxAttempts {
            if let frame = currentLiveSeparatorFrame() {
                cache.lastKnownSeparatorX = frame.origin.x
                cache.lastKnownSeparatorRightEdgeX = frame.origin.x + frame.width
                _ = alwaysHiddenSeparatorOriginX()
                if attempt > 1 {
                    logger.info("Warmed separator cache after \(attempt) attempts")
                }
                return
            }

            _ = alwaysHiddenSeparatorOriginX()

            if let separatorOrigin = cache.lastKnownSeparatorX,
               let separatorRightEdge = cache.lastKnownSeparatorRightEdgeX,
               separatorRightEdge > separatorOrigin {
                if attempt > 1 {
                    logger.info("Warmed separator cache after \(attempt) attempts")
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.debug("Unable to warm separator cache before hide (will use runtime fallbacks)")
    }

    func warmAlwaysHiddenSeparatorPositionCache(maxAttempts: Int = 12) async {
        for attempt in 1 ... maxAttempts {
            if let frame = currentLiveAlwaysHiddenSeparatorFrame() {
                cache.lastKnownAlwaysHiddenSeparatorX = frame.origin.x
                cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = frame.origin.x + frame.width
                if attempt > 1 {
                    logger.info("Warmed always-hidden separator cache after \(attempt) attempts")
                }
                return
            }

            if let separatorOrigin = cache.lastKnownAlwaysHiddenSeparatorX,
               let separatorRightEdge = cache.lastKnownAlwaysHiddenSeparatorRightEdgeX,
               separatorRightEdge > separatorOrigin {
                if attempt > 1 {
                    logger.info("Warmed always-hidden separator cache after \(attempt) attempts")
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.debug("Unable to warm always-hidden separator cache before move")
    }

    func refreshSeparatorCacheAfterMove() async {
        await warmSeparatorPositionCache(maxAttempts: 16)
        await warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
        _ = separatorOriginX()
        _ = separatorRightEdgeX()
        _ = alwaysHiddenSeparatorOriginX()
        _ = alwaysHiddenSeparatorBoundaryX()
    }
}
