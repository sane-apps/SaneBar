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

    func resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: Bool = true) -> CGFloat? {
        let normalized = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: cache.lastKnownSeparatorRightEdgeX,
            cachedOrigin: cache.lastKnownSeparatorX,
            estimatedRightEdge: allowEstimatedFallback ? estimatedSeparatorEdgesFromMainIcon()?.rightEdgeX : nil,
            mainLeftEdge: mainStatusItemLeftEdgeX()
        )

        if let normalized {
            cache.lastKnownSeparatorRightEdgeX = normalized
        }

        return normalized
    }

    func estimatedSeparatorEdgesFromMainIcon() -> (originX: CGFloat, rightEdgeX: CGFloat)? {
        guard let mainLeftEdgeX = mainStatusItemLeftEdgeX(), mainLeftEdgeX > 0 else { return nil }

        let visualWidth: CGFloat = MenuBarMoveGeometryPolicy.separatorVisualWidth
        let originX = max(1, mainLeftEdgeX - visualWidth)
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

        let estimated = MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
            separatorIsPresentInVisualMode: true,
            separatorRightEdge: cache.lastKnownSeparatorRightEdgeX,
            separatorOrigin: cache.lastKnownSeparatorX
        )
        if let estimated {
            cache.lastKnownSeparatorRightEdgeX = estimated
        }
        return estimated
    }

    func currentLiveSeparatorFrame() -> CGRect? {
        guard let separatorItem = manager.separatorItem, separatorItem.length <= 1000,
              let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            return nil
        }

        let frame = separatorWindow.frame
        guard MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: frame.origin.x, width: frame.width) else {
            return nil
        }
        return frame
    }

    func currentLiveAlwaysHiddenSeparatorFrame() -> CGRect? {
        guard let alwaysHiddenSeparatorItem = manager.alwaysHiddenSeparatorItem,
              alwaysHiddenSeparatorItem.length <= 1000,
              let separatorButton = alwaysHiddenSeparatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            return nil
        }

        let frame = separatorWindow.frame
        guard MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: frame.origin.x, width: frame.width) else {
            return nil
        }
        return frame
    }

    func currentLiveAlwaysHiddenSeparatorBoundaryX() -> CGFloat? {
        guard let alwaysHiddenFrame = currentLiveAlwaysHiddenSeparatorFrame(),
              let separatorFrame = currentLiveSeparatorFrame()
        else {
            return nil
        }

        let separatorBoundaryX = separatorFrame.origin.x + separatorFrame.width
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
        if MenuBarMoveGeometryPolicy.mainStatusItemFrameLooksLive(originX: frame.origin.x, width: frame.width) {
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
                _ = resolvedSeparatorRightEdgeFromCaches()
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
        if MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: x, width: frame.width) {
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
            if let cachedX = cache.lastKnownAlwaysHiddenSeparatorX, cachedX > 0 {
                return cachedX
            }
            return nil
        }

        guard let separatorButton = item.button,
              let separatorWindow = separatorButton.window
        else {
            if let cachedX = cache.lastKnownAlwaysHiddenSeparatorX, cachedX > 0 {
                return cachedX
            }
            return nil
        }
        let x = separatorWindow.frame.origin.x
        if x > 0 {
            cache.lastKnownAlwaysHiddenSeparatorX = x
            if separatorWindow.frame.width > 0, separatorWindow.frame.width < 1000 {
                cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = separatorWindow.frame.origin.x + separatorWindow.frame.width
            }
            return x
        }

        if let cachedX = cache.lastKnownAlwaysHiddenSeparatorX, cachedX > 0 {
            return cachedX
        }

        return nil
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
            if frame.origin.x > 0, frame.width > 0, frame.width < 1000 {
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
            let cachedX = resolvedSeparatorRightEdgeFromCaches(allowEstimatedFallback: allowEstimatedFallback) ?? -1
            logger.debug("getSeparatorRightEdgeX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
            return cachedX > 0 ? cachedX : nil
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

        if !MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: frame.origin.x, width: frame.width) {
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
        if MenuBarMoveGeometryPolicy.mainStatusItemFrameLooksLive(originX: frame.origin.x, width: frame.width) {
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
               separatorOrigin > 0, separatorRightEdge > separatorOrigin {
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
               separatorOrigin > 0, separatorRightEdge > separatorOrigin {
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
