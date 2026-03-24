import AppKit
import os.log

// swiftlint:disable file_length

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.IconMoving")

extension MenuBarManager {
    @MainActor
    private enum AlwaysHiddenQueuedMutation {
        case pin(bundleID: String, menuExtraId: String?, statusItemIndex: Int?)
        case unpin(bundleID: String, menuExtraId: String?, statusItemIndex: Int?)
    }

    // MARK: - Icon Moving

    enum ZoneMoveRequest: Sendable {
        case visibleToHidden
        case hiddenToVisible
        case visibleToAlwaysHidden
        case hiddenToAlwaysHidden
        case alwaysHiddenToVisible
        case alwaysHiddenToHidden
    }

    nonisolated static let separatorVisualWidth: CGFloat = 20
    nonisolated static let visibleLaneCrowdingNotification = Notification.Name(
        "MenuBarManager.visibleLaneCrowdingNotification"
    )
    nonisolated static let visibleLaneCrowdingBundleIDKey = "bundleID"
    nonisolated static let visibleLaneCrowdingMenuExtraIDKey = "menuExtraID"
    nonisolated static let visibleLaneCrowdingStatusItemIndexKey = "statusItemIndex"
    nonisolated static let visibleLaneCrowdingSeparatorRightEdgeKey = "separatorRightEdgeX"
    nonisolated static let visibleLaneCrowdingVisibleBoundaryKey = "visibleBoundaryX"

    nonisolated static func separatorFrameLooksLive(originX: CGFloat, width: CGFloat) -> Bool {
        originX > 0 && width > 0 && width < 1000
    }

    /// Normalize stale/misaligned separator right-edge cache using origin cache,
    /// main-icon estimate, and visible boundary guardrails.
    nonisolated static func normalizedSeparatorRightEdge(
        cachedRightEdge: CGFloat?,
        cachedOrigin: CGFloat?,
        estimatedRightEdge: CGFloat?,
        mainLeftEdge: CGFloat?
    ) -> CGFloat? {
        var candidate = cachedRightEdge

        if let origin = cachedOrigin, origin > 0 {
            // Repair missing, inverted, or implausibly distant right-edge caches.
            if candidate == nil || (candidate ?? 0) <= origin || (candidate ?? 0) > (origin + 250) {
                candidate = origin + separatorVisualWidth
            }
        }

        if candidate == nil {
            candidate = estimatedRightEdge
        }

        if let mainLeftEdge, mainLeftEdge > 0, let edge = candidate, edge >= mainLeftEdge {
            candidate = max(1, mainLeftEdge - 2)
        }

        if let origin = cachedOrigin, origin > 0, let edge = candidate, edge <= origin {
            candidate = origin + 1
        }

        guard let resolved = candidate, resolved > 0 else { return nil }
        return resolved
    }

    /// Normalize always-hidden separator boundary against its origin cache and the
    /// main separator boundary. Returns nil when the candidate is stale/inverted.
    nonisolated static func normalizedAlwaysHiddenBoundary(
        cachedRightEdge: CGFloat?,
        cachedOrigin: CGFloat?,
        separatorX: CGFloat?,
        minimumGap: CGFloat = 8
    ) -> CGFloat? {
        var candidate = cachedRightEdge

        if let origin = cachedOrigin, origin > 0 {
            if candidate == nil || (candidate ?? 0) <= origin || (candidate ?? 0) > (origin + 250) {
                candidate = origin + separatorVisualWidth
            }
        }

        guard let resolvedSeparatorX = separatorX,
              resolvedSeparatorX.isFinite,
              resolvedSeparatorX > 0,
              let boundary = candidate,
              boundary.isFinite,
              boundary > 0 else {
            return nil
        }

        let maxAllowed = resolvedSeparatorX - max(1, minimumGap)
        guard maxAllowed > 0 else { return nil }
        guard boundary < maxAllowed else { return nil }
        return boundary
    }

    nonisolated static func hasPreciseMoveIdentity(
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> Bool {
        if let menuExtraId, !menuExtraId.isEmpty {
            return true
        }
        if let statusItemIndex, statusItemIndex >= 0 {
            return true
        }
        return false
    }

    nonisolated static func shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
        visibleBoundaryX: CGFloat?,
        sourceFrameIsOnScreen: Bool,
        hasPreciseIdentity: Bool
    ) -> Bool {
        guard let visibleBoundaryX, visibleBoundaryX > 0 else { return false }
        guard sourceFrameIsOnScreen else { return false }
        return hasPreciseIdentity
    }

    private func resolvedSeparatorRightEdgeFromCaches() -> CGFloat? {
        let normalized = Self.normalizedSeparatorRightEdge(
            cachedRightEdge: lastKnownSeparatorRightEdgeX,
            cachedOrigin: lastKnownSeparatorX,
            estimatedRightEdge: estimatedSeparatorEdgesFromMainIcon()?.rightEdgeX,
            mainLeftEdge: getMainStatusItemLeftEdgeX()
        )

        if let normalized {
            lastKnownSeparatorRightEdgeX = normalized
        }

        return normalized
    }

    /// Fallback estimate for separator edges when WindowServer reports stale/off-screen
    /// frames and no cache is available yet. We derive this from the main icon edge,
    /// because the separator is placed immediately to its left at visual width.
    private func estimatedSeparatorEdgesFromMainIcon() -> (originX: CGFloat, rightEdgeX: CGFloat)? {
        guard let mainLeftEdgeX = getMainStatusItemLeftEdgeX(), mainLeftEdgeX > 0 else { return nil }

        // Separator visual width in normal (non-blocking) mode.
        let visualWidth: CGFloat = Self.separatorVisualWidth
        let originX = max(1, mainLeftEdgeX - visualWidth)
        let rightEdgeX = originX + visualWidth
        return (originX, rightEdgeX)
    }

    private func currentLiveSeparatorFrame() -> CGRect? {
        guard let separatorItem, separatorItem.length <= 1000,
              let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window else {
            return nil
        }

        let frame = separatorWindow.frame
        guard Self.separatorFrameLooksLive(originX: frame.origin.x, width: frame.width) else {
            return nil
        }
        return frame
    }

    private func currentLiveAlwaysHiddenSeparatorFrame() -> CGRect? {
        guard let alwaysHiddenSeparatorItem, alwaysHiddenSeparatorItem.length <= 1000,
              let separatorButton = alwaysHiddenSeparatorItem.button,
              let separatorWindow = separatorButton.window else {
            return nil
        }

        let frame = separatorWindow.frame
        guard Self.separatorFrameLooksLive(originX: frame.origin.x, width: frame.width) else {
            return nil
        }
        return frame
    }

    @MainActor
    private func postVisibleLaneCrowdingHintCandidate(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        separatorRightEdgeX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) {
        var userInfo: [String: Any] = [
            Self.visibleLaneCrowdingBundleIDKey: bundleID,
            Self.visibleLaneCrowdingSeparatorRightEdgeKey: Double(separatorRightEdgeX)
        ]
        if let menuExtraId {
            userInfo[Self.visibleLaneCrowdingMenuExtraIDKey] = menuExtraId
        }
        if let statusItemIndex {
            userInfo[Self.visibleLaneCrowdingStatusItemIndexKey] = statusItemIndex
        }
        if let visibleBoundaryX {
            userInfo[Self.visibleLaneCrowdingVisibleBoundaryKey] = Double(visibleBoundaryX)
        }

        NotificationCenter.default.post(
            name: Self.visibleLaneCrowdingNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    /// Get the separator's LEFT edge X position (for hidden/visible icon classification)
    /// Icons to the LEFT of this position (lower X) are HIDDEN
    /// Icons to the RIGHT of this position (higher X) are VISIBLE
    /// Returns nil if separator position can't be determined
    func getSeparatorOriginX() -> CGFloat? {
        guard let separatorItem else { return lastKnownSeparatorX }

        // If in blocking mode (length > 1000), live position is off-screen — use cache
        if separatorItem.length > 1000 {
            if let cachedX = lastKnownSeparatorX {
                _ = resolvedSeparatorRightEdgeFromCaches()
                logger.debug("🔧 getSeparatorOriginX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
                return cachedX
            }

            if let estimated = estimatedSeparatorEdgesFromMainIcon() {
                lastKnownSeparatorX = estimated.originX
                lastKnownSeparatorRightEdgeX = estimated.rightEdgeX
                logger.warning("🔧 getSeparatorOriginX: blocking mode with empty cache, using estimated \(estimated.originX)")
                return estimated.originX
            }

            let cachedX = lastKnownSeparatorX ?? -1
            logger.debug("🔧 getSeparatorOriginX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
            return lastKnownSeparatorX
        }

        guard let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            return lastKnownSeparatorX
        }
        let frame = separatorWindow.frame
        let x = frame.origin.x
        // Cache valid on-screen positions for use during blocking mode
        if Self.separatorFrameLooksLive(originX: x, width: frame.width) {
            lastKnownSeparatorX = x
            lastKnownSeparatorRightEdgeX = frame.origin.x + frame.width
            return x
        }

        if let cachedX = lastKnownSeparatorX {
            return cachedX
        }

        if let estimated = estimatedSeparatorEdgesFromMainIcon() {
            logger.warning("🔧 getSeparatorOriginX: stale/off-screen frame with empty cache, using estimated \(estimated.originX)")
            return estimated.originX
        }

        return nil
    }

    /// Get the always-hidden separator's LEFT edge X position (for classification/moves).
    /// When the separator is in blocking mode (10,000 length), returns the cached position
    /// from when it was last at visual size, since the live position is off-screen.
    func getAlwaysHiddenSeparatorOriginX() -> CGFloat? {
        guard let item = alwaysHiddenSeparatorItem else { return nil }

        // If in blocking mode (length > 1000), the live frame is off-screen.
        // Return only a valid cached on-screen coordinate.
        if item.length > 1000 {
            if let cachedX = lastKnownAlwaysHiddenSeparatorX, cachedX > 0 {
                return cachedX
            }
            return nil
        }

        guard let separatorButton = item.button,
              let separatorWindow = separatorButton.window
        else {
            if let cachedX = lastKnownAlwaysHiddenSeparatorX, cachedX > 0 {
                return cachedX
            }
            return nil
        }
        let x = separatorWindow.frame.origin.x
        // Cache valid on-screen positions for use during blocking mode.
        if x > 0 {
            lastKnownAlwaysHiddenSeparatorX = x
            if separatorWindow.frame.width > 0, separatorWindow.frame.width < 1000 {
                lastKnownAlwaysHiddenSeparatorRightEdgeX = separatorWindow.frame.origin.x + separatorWindow.frame.width
            }
            return x
        }

        // Live frame can transiently report stale/off-screen coordinates after relayout.
        // Never return a negative/zero origin for drag targeting.
        if let cachedX = lastKnownAlwaysHiddenSeparatorX, cachedX > 0 {
            return cachedX
        }

        return nil
    }

    /// Boundary X used for always-hidden zone checks and move verification.
    /// Unlike origin-X, this uses the separator's right edge, which matches where
    /// icons can realistically settle after Cmd+drag near the AH divider.
    func getAlwaysHiddenSeparatorBoundaryX() -> CGFloat? {
        let separatorX = getSeparatorRightEdgeX() ?? getSeparatorOriginX()

        guard let item = alwaysHiddenSeparatorItem else {
            let normalized = Self.normalizedAlwaysHiddenBoundary(
                cachedRightEdge: lastKnownAlwaysHiddenSeparatorRightEdgeX,
                cachedOrigin: lastKnownAlwaysHiddenSeparatorX,
                separatorX: separatorX
            )
            if let normalized {
                lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
                return normalized
            }
            return nil
        }

        if item.length > 1000 {
            let normalized = Self.normalizedAlwaysHiddenBoundary(
                cachedRightEdge: lastKnownAlwaysHiddenSeparatorRightEdgeX,
                cachedOrigin: lastKnownAlwaysHiddenSeparatorX ?? getAlwaysHiddenSeparatorOriginX(),
                separatorX: separatorX
            )
            if let normalized {
                lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
                return normalized
            }
            return nil
        }

        if let button = item.button,
           let window = button.window {
            let frame = window.frame
            if frame.origin.x > 0, frame.width > 0, frame.width < 1000 {
                let normalized = Self.normalizedAlwaysHiddenBoundary(
                    cachedRightEdge: frame.origin.x + frame.width,
                    cachedOrigin: frame.origin.x,
                    separatorX: separatorX
                )
                lastKnownAlwaysHiddenSeparatorX = frame.origin.x
                if let normalized {
                    lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
                    return normalized
                }
            }
        }

        let normalized = Self.normalizedAlwaysHiddenBoundary(
            cachedRightEdge: lastKnownAlwaysHiddenSeparatorRightEdgeX,
            cachedOrigin: lastKnownAlwaysHiddenSeparatorX ?? getAlwaysHiddenSeparatorOriginX(),
            separatorX: separatorX
        )
        if let normalized {
            lastKnownAlwaysHiddenSeparatorRightEdgeX = normalized
            return normalized
        }

        return nil
    }

    /// Get the separator's right edge X position (for moving icons)
    /// NOTE: This value changes based on expanded/collapsed state!
    /// Returns nil if separator position can't be determined
    func getSeparatorRightEdgeX() -> CGFloat? {
        guard let separatorItem else {
            logger.error("🔧 getSeparatorRightEdgeX: separatorItem is nil")
            return resolvedSeparatorRightEdgeFromCaches()
        }

        // If in blocking mode (length > 1000), live position is off-screen — use cache.
        // This mirrors getSeparatorOriginX() which already has this check.
        if separatorItem.length > 1000 {
            let cachedX = resolvedSeparatorRightEdgeFromCaches() ?? -1
            logger.debug("🔧 getSeparatorRightEdgeX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
            return cachedX > 0 ? cachedX : nil
        }

        guard let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            logger.error("🔧 getSeparatorRightEdgeX: button or window is nil")
            return resolvedSeparatorRightEdgeFromCaches()
        }
        let frame = separatorWindow.frame
        logger.debug("🔧 getSeparatorRightEdgeX: window.frame = \(String(describing: frame))")
        guard frame.width > 0 else {
            logger.error("🔧 getSeparatorRightEdgeX: frame.width is 0")
            return resolvedSeparatorRightEdgeFromCaches()
        }

        // If window frame looks stale (width > 1000 or origin off-screen),
        // WindowServer hasn't finished relayout after showAll() — use cache.
        // showAll() sets length=20 immediately but the window frame lags behind.
        if !Self.separatorFrameLooksLive(originX: frame.origin.x, width: frame.width) {
            if let cachedX = resolvedSeparatorRightEdgeFromCaches() {
                logger.warning("🔧 getSeparatorRightEdgeX: stale frame (w=\(frame.width), x=\(frame.origin.x)), using cached \(cachedX)")
                return cachedX
            }

            if let estimated = estimatedSeparatorEdgesFromMainIcon() {
                logger.warning("🔧 getSeparatorRightEdgeX: stale frame with empty cache, using estimated \(estimated.rightEdgeX)")
                return estimated.rightEdgeX
            }

            logger.warning("🔧 getSeparatorRightEdgeX: stale frame and no fallback available")
            return nil
        }

        // Cache both origin and right edge when separator is at visual size.
        // These caches are used during blocking mode or stale frame fallback.
        lastKnownSeparatorX = frame.origin.x
        let rightEdge = Self.normalizedSeparatorRightEdge(
            cachedRightEdge: frame.origin.x + frame.width,
            cachedOrigin: frame.origin.x,
            estimatedRightEdge: nil,
            mainLeftEdge: getMainStatusItemLeftEdgeX()
        ) ?? (frame.origin.x + frame.width)
        lastKnownSeparatorRightEdgeX = rightEdge
        logger.debug("🔧 getSeparatorRightEdgeX: returning \(rightEdge)")
        return rightEdge
    }

    /// Get the main status item (SaneBar icon) left edge X position
    /// This is the RIGHT boundary of the visible zone
    func getMainStatusItemLeftEdgeX() -> CGFloat? {
        guard let mainButton = mainStatusItem?.button,
              let mainWindow = mainButton.window
        else {
            logger.error("🔧 getMainStatusItemLeftEdgeX: mainStatusItem or window is nil")
            return nil
        }
        let frame = mainWindow.frame
        logger.debug("🔧 getMainStatusItemLeftEdgeX: window.frame = \(String(describing: frame))")
        return frame.origin.x
    }

    @MainActor
    func warmSeparatorPositionCache(maxAttempts: Int = 12) async {
        for attempt in 1 ... maxAttempts {
            if let frame = currentLiveSeparatorFrame() {
                lastKnownSeparatorX = frame.origin.x
                lastKnownSeparatorRightEdgeX = frame.origin.x + frame.width
                _ = getAlwaysHiddenSeparatorOriginX()
                if attempt > 1 {
                    logger.info("🔧 Warmed separator cache after \(attempt) attempts")
                }
                return
            }

            _ = getAlwaysHiddenSeparatorOriginX()

            // Do not treat estimated fallback as "warmed" cache.
            // We only accept live WindowServer coordinates here.
            if let separatorOrigin = lastKnownSeparatorX,
               let separatorRightEdge = lastKnownSeparatorRightEdgeX,
               separatorOrigin > 0, separatorRightEdge > separatorOrigin {
                if attempt > 1 {
                    logger.info("🔧 Warmed separator cache after \(attempt) attempts")
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.debug("🔧 Unable to warm separator cache before hide (will use runtime fallbacks)")
    }

    @MainActor
    func warmAlwaysHiddenSeparatorPositionCache(maxAttempts: Int = 12) async {
        for attempt in 1 ... maxAttempts {
            if let frame = currentLiveAlwaysHiddenSeparatorFrame() {
                lastKnownAlwaysHiddenSeparatorX = frame.origin.x
                lastKnownAlwaysHiddenSeparatorRightEdgeX = frame.origin.x + frame.width
                if attempt > 1 {
                    logger.info("🔧 Warmed always-hidden separator cache after \(attempt) attempts")
                }
                return
            }

            if let separatorOrigin = lastKnownAlwaysHiddenSeparatorX,
               let separatorRightEdge = lastKnownAlwaysHiddenSeparatorRightEdgeX,
               separatorOrigin > 0, separatorRightEdge > separatorOrigin {
                if attempt > 1 {
                    logger.info("🔧 Warmed always-hidden separator cache after \(attempt) attempts")
                }
                return
            }

            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.debug("🔧 Unable to warm always-hidden separator cache before move")
    }

    /// Refresh cached separator boundaries after a drag mutation while separators
    /// are still at visual size. This prevents post-move zone classification from
    /// using stale hidden-mode cache values.
    @MainActor
    func refreshSeparatorCacheAfterMove() async {
        await warmSeparatorPositionCache(maxAttempts: 16)
        await warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
        _ = getSeparatorOriginX()
        _ = getSeparatorRightEdgeX()
        _ = getAlwaysHiddenSeparatorOriginX()
        _ = getAlwaysHiddenSeparatorBoundaryX()
    }

    @MainActor
    private func computeMoveTargets(
        toHidden: Bool,
        separatorOverrideX: CGFloat?
    ) -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        if toHidden {
            let separatorX: CGFloat?
            if let separatorOverrideX {
                separatorX = separatorOverrideX
            } else {
                let origin = getSeparatorOriginX()
                let derivedFromRightEdge: CGFloat? = {
                    guard let rightEdge = getSeparatorRightEdgeX(), rightEdge > 0 else { return nil }
                    return max(1, rightEdge - Self.separatorVisualWidth)
                }()

                if let origin, let derivedFromRightEdge {
                    // Origin can be stale right after hide/show transitions.
                    // Prefer the right-edge-derived origin when origin is implausibly left.
                    if origin + 40 < derivedFromRightEdge {
                        logger.warning(
                            "🔧 Hidden move target corrected from stale origin \(origin) to right-edge-derived \(derivedFromRightEdge)"
                        )
                        separatorX = derivedFromRightEdge
                    } else {
                        separatorX = origin
                    }
                } else {
                    separatorX = origin ?? derivedFromRightEdge
                }
            }

            var alwaysHiddenBoundaryX: CGFloat?
            if separatorOverrideX == nil,
               let resolvedSeparatorX = separatorX,
               let candidateBoundaryX = getAlwaysHiddenSeparatorBoundaryX(),
               candidateBoundaryX > 0 {
                if candidateBoundaryX < (resolvedSeparatorX - 4) {
                    alwaysHiddenBoundaryX = candidateBoundaryX
                    logger.info("🔧 AH separator boundary for hidden target: \(candidateBoundaryX)")
                } else {
                    logger.warning(
                        "🔧 Ignoring AH boundary >= separator during hidden move target resolution (ah=\(candidateBoundaryX), sep=\(resolvedSeparatorX))"
                    )
                }
            }
            return (separatorX, alwaysHiddenBoundaryX)
        }

        let separatorX = getSeparatorRightEdgeX()
        let mainLeftEdge = getMainStatusItemLeftEdgeX()
        return (separatorX, mainLeftEdge)
    }

    private func sourceFrameIsOnScreenForMove(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        preferredCenterX: CGFloat?
    ) -> Bool {
        guard let frame = AccessibilityService.shared.getMenuBarIconFrame(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        ) else {
            return false
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(center) }
    }

    private func resolveMoveTargetsWithRetries(
        toHidden: Bool,
        sourceIdentity: MoveSourceIdentity,
        separatorOverrideX: CGFloat?,
        maxAttempts: Int = 20
    ) async -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        var lastTargets: (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) = (nil, nil)

        for attempt in 1 ... maxAttempts {
            let (targets, liveSeparatorReady, sourceFrameIsOnScreen) = await MainActor.run {
                let targets = self.computeMoveTargets(toHidden: toHidden, separatorOverrideX: separatorOverrideX)
                let liveSeparatorReady = separatorOverrideX != nil || self.currentLiveSeparatorFrame() != nil
                let sourceFrameIsOnScreen = !toHidden && self.sourceFrameIsOnScreenForMove(
                    bundleID: sourceIdentity.bundleID,
                    menuExtraId: sourceIdentity.menuExtraId,
                    statusItemIndex: sourceIdentity.statusItemIndex,
                    preferredCenterX: sourceIdentity.preferredCenterX
                )
                return (targets, liveSeparatorReady, sourceFrameIsOnScreen)
            }
            lastTargets = targets

            if let separatorX = targets.separatorX, separatorX > 0 {
                if toHidden || (targets.visibleBoundaryX != nil && (targets.visibleBoundaryX ?? 0) > 0) {
                    let canUseCachedVisibleTarget = !toHidden && Self.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
                        visibleBoundaryX: targets.visibleBoundaryX,
                        sourceFrameIsOnScreen: sourceFrameIsOnScreen,
                        hasPreciseIdentity: Self.hasPreciseMoveIdentity(
                            menuExtraId: sourceIdentity.menuExtraId,
                            statusItemIndex: sourceIdentity.statusItemIndex
                        )
                    )

                    if liveSeparatorReady || canUseCachedVisibleTarget || attempt == maxAttempts {
                        if attempt > 1 {
                            logger.info("🔧 Resolved separator target after \(attempt * 50)ms")
                        }
                        if canUseCachedVisibleTarget {
                            logger.info("🔧 Accepting cached visible move target because source icon is already on-screen with a precise identity")
                        }
                        return targets
                    }

                    if attempt == 1 || attempt % 5 == 0 {
                        logger.debug("🔧 Cached separator target available after \(attempt * 50)ms but live frame is still stale")
                        logger.debug("🔧 Waiting for live separator frame or an on-screen precise source icon before accepting cached move target")
                    }
                }
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return lastTargets
    }

    private func resolveAlwaysHiddenMoveTargetsWithRetries(
        toAlwaysHidden: Bool,
        maxAttempts: Int = 20
    ) async -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        var lastTargets: (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) = (nil, nil)

        for attempt in 1 ... maxAttempts {
            let (targets, liveAHSeparatorReady, liveMainSeparatorReady) = await MainActor.run {
                if toAlwaysHidden {
                    return (
                        (self.getAlwaysHiddenSeparatorBoundaryX(), nil as CGFloat?),
                        self.currentLiveAlwaysHiddenSeparatorFrame() != nil,
                        true
                    )
                }

                return (
                    (self.getSeparatorRightEdgeX(), self.getMainStatusItemLeftEdgeX()),
                    self.currentLiveAlwaysHiddenSeparatorFrame() != nil,
                    self.currentLiveSeparatorFrame() != nil
                )
            }
            lastTargets = targets

            if let separatorX = targets.0,
               separatorX > 0,
               toAlwaysHidden || (targets.1 != nil && (targets.1 ?? 0) > 0) {
                let liveGeometryReady = toAlwaysHidden ? liveAHSeparatorReady : liveAHSeparatorReady && liveMainSeparatorReady
                if liveGeometryReady || attempt == maxAttempts {
                    if attempt > 1 {
                        logger.info("🔧 Resolved always-hidden move targets after \(attempt * 50)ms")
                    }
                    return targets
                }

                if attempt == 1 || attempt % 5 == 0 {
                    logger.debug("🔧 Waiting for live always-hidden separator geometry before move target acceptance")
                }
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return lastTargets
    }

    nonisolated static func shouldBlockWideIconHiddenMove(
        iconWidth: CGFloat,
        hiddenLaneWidth: CGFloat
    ) -> Bool {
        guard iconWidth.isFinite, hiddenLaneWidth.isFinite else { return false }
        guard iconWidth > 0, hiddenLaneWidth > 0 else { return false }

        // Extremely wide status items can straddle AH + hidden boundaries and
        // get misclassified after drag. Guard only that edge case.
        let wideIconThreshold: CGFloat = 120
        guard iconWidth >= wideIconThreshold else { return false }

        let lanePadding: CGFloat = 18
        return hiddenLaneWidth < (iconWidth + lanePadding)
    }

    private enum MoveExpectedZone {
        case visible
        case hidden
        case alwaysHidden
    }

    private struct MoveSourceIdentity {
        let bundleID: String
        let menuExtraId: String?
        let statusItemIndex: Int?
        let preferredCenterX: CGFloat?
    }

    private func moveVerificationMatchesTarget(
        app: RunningApp,
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> Bool {
        guard app.bundleId == bundleID else { return false }
        if let menuExtraId, app.menuExtraIdentifier != menuExtraId { return false }
        if let statusItemIndex, app.statusItemIndex != statusItemIndex { return false }
        return true
    }

    private func verifyMoveByClassifiedZone(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        expectedZone: MoveExpectedZone,
        attempts: Int = 4
    ) async -> Bool {
        for attempt in 1 ... attempts {
            let classified = await SearchService.shared.refreshClassifiedApps()
            let matcher: (RunningApp) -> Bool = { app in
                self.moveVerificationMatchesTarget(
                    app: app,
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex
                )
            }

            let matched: Bool = switch expectedZone {
            case .visible:
                classified.visible.contains(where: matcher)
            case .hidden:
                classified.hidden.contains(where: matcher)
            case .alwaysHidden:
                classified.alwaysHidden.contains(where: matcher)
            }

            if matched {
                return true
            }

            if attempt < attempts {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        return false
    }

    private func verifyVisibleMoveWithFreshGeometry(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        preferredCenterX: CGFloat?,
        staleSeparatorX: CGFloat,
        allowsGeometryRecheck: Bool
    ) async -> Bool {
        guard allowsGeometryRecheck else { return false }
        guard staleSeparatorX.isFinite, staleSeparatorX > 0 else { return false }

        let accessibilityService = AccessibilityService.shared
        guard let staleFrame = accessibilityService.getMenuBarIconFrame(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        ) else {
            return false
        }

        let staleShortfall = staleSeparatorX - staleFrame.midX
        guard staleShortfall > 0, staleShortfall <= 48 else { return false }

        try? await Task.sleep(for: .milliseconds(120))
        await warmSeparatorPositionCache(maxAttempts: 8)

        guard let freshSeparatorX = getSeparatorRightEdgeX(),
              freshSeparatorX > 0,
              freshSeparatorX + 2 < staleSeparatorX else {
            return false
        }
        guard let freshVisibleBoundaryX = getMainStatusItemLeftEdgeX(),
              freshVisibleBoundaryX > 0 else {
            return false
        }
        guard let refreshedFrame = accessibilityService.getMenuBarIconFrame(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        ) else {
            return false
        }

        guard AccessibilityService.frameIsInTargetZone(
            afterFrame: refreshedFrame,
            separatorX: freshSeparatorX,
            toHidden: false
        ) else {
            return false
        }

        logger.info(
            "🔧 Visible move accepted after fresh geometry recheck (staleSeparatorX=\(staleSeparatorX, privacy: .public), freshSeparatorX=\(freshSeparatorX, privacy: .public), freshVisibleBoundaryX=\(freshVisibleBoundaryX, privacy: .public), afterMidX=\(refreshedFrame.midX, privacy: .public))"
        )
        return true
    }

    @MainActor
    private func currentMoveRuntimeSnapshot(
        identityPrecision: MenuBarIdentityPrecision
    ) -> MenuBarRuntimeSnapshot {
        var snapshot = currentRuntimeSnapshot(identityPrecision: identityPrecision)
        if snapshot.visibilityPhase == .hidden {
            switch snapshot.geometryConfidence {
            case .live, .cached:
                snapshot.geometryConfidence = .shielded
            case .shielded, .stale, .missing:
                break
            }
        }
        return snapshot
    }

    @MainActor
    private func canQueueInteractiveMove(
        operationName: String,
        requiresAlwaysHiddenSeparator: Bool,
        identityPrecision: MenuBarIdentityPrecision
    ) -> Bool {
        switch MenuBarOperationCoordinator.moveQueueDecision(
            snapshot: currentMoveRuntimeSnapshot(identityPrecision: identityPrecision),
            requiresAlwaysHiddenSeparator: requiresAlwaysHiddenSeparator
        ) {
        case .ready:
            return true
        case .rejectBusy:
            logger.warning("🔧 \(operationName, privacy: .public) skipped — hiding service busy")
            return false
        case .rejectMoveAlreadyInFlight:
            logger.warning("⚠️ \(operationName, privacy: .public) rejected: another move is in progress")
            return false
        case .rejectMissingAlwaysHiddenSeparator:
            logger.error("🔧 \(operationName, privacy: .public): always-hidden separator unavailable")
            return false
        case .rejectMissingScreenGeometry:
            logger.error("🔧 \(operationName, privacy: .public): no screens available — aborting")
            return false
        }
    }

    private func prepareAlwaysHiddenMoveQueue(
        operationName: String,
        identityPrecision: MenuBarIdentityPrecision,
        shouldEnableSection: Bool
    ) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                _ = ensureAlwaysHiddenSeparatorReady(
                    operationName: operationName,
                    shouldEnableSection: shouldEnableSection
                )
                return canQueueInteractiveMove(
                    operationName: operationName,
                    requiresAlwaysHiddenSeparator: true,
                    identityPrecision: identityPrecision
                )
            }
        }

        var canQueue = false
        DispatchQueue.main.sync {
            _ = self.ensureAlwaysHiddenSeparatorReady(
                operationName: operationName,
                shouldEnableSection: shouldEnableSection
            )
            canQueue = self.canQueueInteractiveMove(
                operationName: operationName,
                requiresAlwaysHiddenSeparator: true,
                identityPrecision: identityPrecision
            )
        }
        return canQueue
    }

    @MainActor
    private func ensureAlwaysHiddenSeparatorReady(
        operationName: String,
        shouldEnableSection: Bool,
        maxAttempts: Int = 12
    ) -> Bool {
        if shouldEnableSection, !settings.alwaysHiddenSectionEnabled {
            settings.alwaysHiddenSectionEnabled = true
            saveSettings()
        }

        let featureEnabled = Self.effectiveAlwaysHiddenSectionEnabled(
            isPro: LicenseService.shared.isPro,
            alwaysHiddenSectionEnabled: settings.alwaysHiddenSectionEnabled
        )
        guard featureEnabled else {
            logger.error(
                "🔧 \(operationName, privacy: .public): always-hidden feature unavailable (isPro=\(LicenseService.shared.isPro, privacy: .public) requested=\(self.settings.alwaysHiddenSectionEnabled, privacy: .public))"
            )
            return false
        }

        for attempt in 1 ... maxAttempts {
            updateAlwaysHiddenSeparatorIfReady(forceRecreateIfMissing: attempt >= 4)
            if alwaysHiddenSeparatorItem != nil {
                if attempt > 1 {
                    logger.info("🔧 \(operationName, privacy: .public): always-hidden separator became ready after \(attempt) attempts")
                }
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        logger.error("🔧 \(operationName, privacy: .public): always-hidden separator unavailable after wait")
        return false
    }

    /// Move an icon to hidden or visible position
    /// - Parameters:
    ///   - bundleID: The bundle ID of the app to move
    ///   - menuExtraId: For Control Center items, the specific menu extra identifier
    ///   - toHidden: True to hide, false to show
    /// - Returns: True when the move task was queued; final success is async.
    func moveIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        separatorOverrideX: CGFloat? = nil
    ) -> Bool {
        let identityPrecision: MenuBarIdentityPrecision = Self.hasPreciseMoveIdentity(
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        ) ? .exact : .coarse
        guard canQueueInteractiveMove(
            operationName: "moveIcon",
            requiresAlwaysHiddenSeparator: false,
            identityPrecision: identityPrecision
        ) else {
            return false
        }

        logger.debug("🔧 ========== MOVE ICON START ==========")
        logger.debug("🔧 moveIcon: bundleID=\(bundleID, privacy: .private), menuExtraId=\(menuExtraId ?? "nil", privacy: .private), toHidden=\(toHidden, privacy: .public)")
        let currentHidingState = hidingState
        logger.debug("🔧 Current hidingState: \(String(describing: currentHidingState))")

        // Log current positions BEFORE any action
        let preMoveSeparatorRightEdge = getSeparatorRightEdgeX()
        if let sepX = preMoveSeparatorRightEdge {
            logger.debug("🔧 Separator right edge BEFORE: \(sepX)")
        }
        if let mainX = getMainStatusItemLeftEdgeX() {
            logger.debug("🔧 Main icon left edge BEFORE: \(mainX)")
        }

        // IMPORTANT:
        // When the bar is hidden, the separator's *right edge* becomes extremely large
        // (because the separator length expands). Using that value for "Move to Hidden"
        // produces a target X far to the right, so the move appears to do nothing.
        //
        // Fix: for moves INTO the hidden zone, use the separator's LEFT edge.
        // For moves INTO the visible zone, ensure we're expanded, then use the RIGHT edge.

        let wasHidden = hidingService.state == .hidden
        logger.debug("🔧 wasHidden: \(wasHidden)")

        // Prevent always-hidden pin enforcement from kicking off mid-move and
        // perturbing separator geometry while targets are being resolved.
        alwaysHiddenPinEnforcementTask?.cancel()
        alwaysHiddenPinEnforcementTask = nil

        // Defensive pre-clear: only for move-to-visible paths.
        // For move-to-hidden we defer unpin until AFTER a successful drag to avoid
        // settings/enforcement churn right before separator target resolution.
        if !toHidden {
            var removedPin = unpinAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
            if !removedPin, !bundleID.hasPrefix("com.apple.controlcenter") {
                // Status-item indices and AX identifiers can drift across relayouts.
                // Fallback to bundle-level unpin for non-Control Center extras so a
                // stale pin cannot immediately yank the icon back into always-hidden.
                removedPin = unpinAlwaysHidden(bundleID: bundleID)
            }
            if removedPin {
                logger.info("🔧 Cleared stale always-hidden pin before move-to-visible")
            }
        }

        // SECURITY: If moving from hidden to visible, use auth-protected reveal path
        let needsAuthCheck = !toHidden && wasHidden && settings.requireAuthToShowHiddenIcons

        // Capture original mouse position on MainActor to restore it later accurately.
        // Cocoa coordinates (bottom-left) → CGEvent coordinates (top-left)
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)
        // Important: avoid blocking the MainActor while simulating Cmd+drag.
        // Any UI stalls here can make the Find Icon window appear to "collapse".
        return queueDetachedMoveTask(operationName: "moveIcon") { manager in
            var usedShowAllShield = false
            let restoreShieldIfNeeded = { () async in
                guard usedShowAllShield else { return }
                let shouldSkipHide = wasHidden
                    ? await MainActor.run { manager.shouldSkipHideForExternalMonitor }
                    : false

                if wasHidden, !shouldSkipHide {
                    logger.info("🔧 Move complete - direct hide from showAll state")
                    await manager.hidingService.hide()
                    return
                }

                logger.info("🔧 Restoring from showAll shield pattern...")
                await manager.hidingService.restoreFromShowAll()
            }

            // When the bar is hidden, the separator is 10000px wide. It physically
            // blocks icon movement in BOTH directions. We must expand to visual size
            // (showAll) before any Cmd+drag, whether moving to hidden or to visible.
            if wasHidden {
                logger.info("🔧 Expanding ALL icons via shield pattern for move...")
                // SECURITY: Auth check if moving from hidden to visible with auth enabled
                if needsAuthCheck {
                    let revealed = await manager.showHiddenItemsNow(trigger: .findIcon)
                    guard revealed else {
                        logger.info("🔧 Auth failed or cancelled - aborting icon move")
                        return false
                    }
                }
                await manager.hidingService.showAll()
                usedShowAllShield = true
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                // Tiny settle delay so status item window frames are stable.
                try? await Task.sleep(for: .milliseconds(50))
            }

            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            let sourceIdentity = MoveSourceIdentity(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
            let actionableMoveSafety = accessibilityService.actionableMoveResolutionSafety(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
            if !actionableMoveSafety.canExecuteMove {
                logger.warning("🔧 Refusing ambiguous move target for \(bundleID, privacy: .private); exact identity could not be proven")
                await restoreShieldIfNeeded()
                return false
            }
            logger.debug("🔧 Getting separator position for move...")
            var (separatorX, visibleBoundaryX) = await manager.resolveMoveTargetsWithRetries(
                toHidden: toHidden,
                sourceIdentity: sourceIdentity,
                separatorOverrideX: separatorOverrideX
            )

            // Drift guard is for regular hidden-zone moves that rely on the main
            // separator geometry. Always-hidden enforcement passes an explicit
            // separator override farther left, so applying this guard there
            // would incorrectly flag valid AH targets as drift.
            if toHidden,
               separatorOverrideX == nil,
               !usedShowAllShield,
               let baselineRightEdge = preMoveSeparatorRightEdge,
               let resolvedSeparatorX = separatorX {
                let resolvedRightEdge = resolvedSeparatorX + Self.separatorVisualWidth
                if resolvedRightEdge + 140 < baselineRightEdge {
                    logger.warning(
                        "🔧 Hidden move target drifted too far left (baselineRight=\(baselineRightEdge), resolvedRight=\(resolvedRightEdge)) — forcing shield re-resolve"
                    )
                    await manager.hidingService.showAll()
                    usedShowAllShield = true
                    try? await Task.sleep(for: .milliseconds(300))
                    (separatorX, visibleBoundaryX) = await manager.resolveMoveTargetsWithRetries(
                        toHidden: toHidden,
                        sourceIdentity: sourceIdentity,
                        separatorOverrideX: separatorOverrideX
                    )
                }
            }

            guard let resolvedSeparatorX = separatorX else {
                logger.error("🔧 Cannot get separator position - ABORTING")
                await restoreShieldIfNeeded()
                return false
            }
            var activeSeparatorX = resolvedSeparatorX
            var activeVisibleBoundaryX = visibleBoundaryX
            if !toHidden {
                guard let activeVisibleBoundaryX, activeVisibleBoundaryX > 0 else {
                    logger.error("🔧 Missing visible boundary for move-to-visible - ABORTING")
                    await restoreShieldIfNeeded()
                    return false
                }
            }
            logger.debug("🔧 Separator for move: X=\(activeSeparatorX), visibleBoundary=\(activeVisibleBoundaryX ?? -1)")

            if toHidden,
               let hiddenLaneLeftBoundaryX = activeVisibleBoundaryX,
               let iconWidth = accessibilityService.currentMenuBarIconWidth(
                   bundleID: bundleID,
                   menuExtraId: menuExtraId,
                   statusItemIndex: statusItemIndex
               ) {
                let hiddenLaneWidth = activeSeparatorX - hiddenLaneLeftBoundaryX
                if Self.shouldBlockWideIconHiddenMove(iconWidth: iconWidth, hiddenLaneWidth: hiddenLaneWidth) {
                    logger.warning(
                        "🔧 Hidden move blocked for wide icon edge case (iconWidth=\(iconWidth, privacy: .public), hiddenLaneWidth=\(hiddenLaneWidth, privacy: .public)); keeping current zone"
                    )
                    await restoreShieldIfNeeded()
                    return false
                }
            }

            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: toHidden,
                separatorX: activeSeparatorX,
                visibleBoundaryX: activeVisibleBoundaryX,
                originalMouseLocation: originalCGPoint
            )
            logger.debug("🔧 moveMenuBarIcon returned: \(success, privacy: .public)")

            if !success, !toHidden {
                success = await manager.verifyVisibleMoveWithFreshGeometry(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    staleSeparatorX: activeSeparatorX,
                    allowsGeometryRecheck: actionableMoveSafety.allowsClassifiedZoneFallback
                )
            }

            // One retry if verification failed — icon may have partially moved
            // or AX position hadn't settled yet on slower Macs.
            if !success {
                logger.info("🔧 Retrying move once with session tap...")
                try? await Task.sleep(for: .milliseconds(200))

                let retryTargets = await manager.resolveMoveTargetsWithRetries(
                    toHidden: toHidden,
                    sourceIdentity: sourceIdentity,
                    separatorOverrideX: separatorOverrideX
                )
                if let retrySeparatorX = retryTargets.separatorX {
                    activeSeparatorX = retrySeparatorX
                    activeVisibleBoundaryX = retryTargets.visibleBoundaryX
                    let retryLabel = toHidden ? "hidden" : "visible"
                    logger.debug("🔧 Re-resolved \(retryLabel) move targets for retry: separator=\(activeSeparatorX), visibleBoundary=\(activeVisibleBoundaryX ?? -1)")
                }

                success = accessibilityService.moveMenuBarIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    toHidden: toHidden,
                    separatorX: activeSeparatorX,
                    visibleBoundaryX: activeVisibleBoundaryX,
                    eventTap: .cgSessionEventTap,
                    originalMouseLocation: originalCGPoint
                )
                logger.debug("🔧 Retry returned: \(success, privacy: .public)")
            }

            let shouldAttemptShieldFallback = !success && (toHidden ? !usedShowAllShield : true)
            if shouldAttemptShieldFallback {
                if !usedShowAllShield {
                    let fallbackLabel = toHidden ? "Hidden" : "Visible"
                    logger.warning("🔧 \(fallbackLabel, privacy: .public) move still failed after standard retry — forcing showAll shield fallback")
                    await manager.hidingService.showAll()
                    usedShowAllShield = true
                    try? await Task.sleep(for: .milliseconds(300))
                } else {
                    logger.warning("🔧 Visible move still failed after standard retry while already using showAll shield — refreshing move targets once more")
                }

                await MainActor.run {
                    AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
                }

                let (fallbackSeparatorX, fallbackVisibleBoundaryX) = await manager.resolveMoveTargetsWithRetries(
                    toHidden: toHidden,
                    sourceIdentity: sourceIdentity,
                    separatorOverrideX: separatorOverrideX
                )

                if let fallbackSeparatorX {
                    if !toHidden,
                       (fallbackVisibleBoundaryX ?? 0) <= 0 {
                        logger.error("🔧 Shield fallback could not resolve visible boundary - keeping failure")
                    } else {
                        success = accessibilityService.moveMenuBarIcon(
                            bundleID: bundleID,
                            menuExtraId: menuExtraId,
                            statusItemIndex: statusItemIndex,
                            preferredCenterX: preferredCenterX,
                            toHidden: toHidden,
                            separatorX: fallbackSeparatorX,
                            visibleBoundaryX: fallbackVisibleBoundaryX,
                            eventTap: .cgSessionEventTap,
                            originalMouseLocation: originalCGPoint
                        )
                        logger.info("🔧 Shield fallback returned: \(success, privacy: .public)")
                    }
                } else {
                    logger.error("🔧 Shield fallback could not resolve separator - keeping failure")
                }
            }

            if !success {
                if actionableMoveSafety.allowsClassifiedZoneFallback {
                    let expectedZone: MoveExpectedZone = toHidden ? .hidden : .visible
                    let classifiedMatch = await manager.verifyMoveByClassifiedZone(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        expectedZone: expectedZone
                    )
                    if classifiedMatch {
                        logger.info("🔧 Move accepted after classification verification (\(toHidden ? "hidden" : "visible"))")
                        success = true
                    }
                } else {
                    logger.info("🔧 Skipping classified-zone move fallback for ambiguous multi-item identity")
                }
            }

            if success, toHidden {
                let removedAfterHiddenMove: Bool = await MainActor.run {
                    var removed = manager.unpinAlwaysHidden(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex
                    )
                    if !removed, !bundleID.hasPrefix("com.apple.controlcenter") {
                        removed = manager.unpinAlwaysHidden(bundleID: bundleID)
                    }
                    return removed
                }
                if removedAfterHiddenMove {
                    logger.info("🔧 Cleared stale always-hidden pin after successful move-to-hidden")
                }
            }

            if success, !toHidden {
                await MainActor.run {
                    manager.postVisibleLaneCrowdingHintCandidate(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        separatorRightEdgeX: activeSeparatorX,
                        visibleBoundaryX: activeVisibleBoundaryX
                    )
                }
            }

            // Update cached separator boundaries to the post-drag geometry before
            // any hide transition pushes separators off-screen.
            await manager.refreshSeparatorCacheAfterMove()

            // Restore shield pattern and re-hide (only when the original state was hidden).
            // This MUST complete before refreshing — otherwise the AX scan
            // sees items mid-transition and returns stale positions.
            await restoreShieldIfNeeded()

            // Allow positions to settle after re-hide, then refresh.
            try? await Task.sleep(for: .milliseconds(300))

            await MainActor.run {
                logger.debug("🔧 Triggering post-move refresh...")
                AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            logger.debug("🔧 ========== MOVE ICON END ==========")
            return success
        }
    }

    // MARK: - Always-Hidden Moves

    /// Move an icon to or from the always-hidden zone.
    /// Uses HidingService's shield pattern (showAll/restoreFromShowAll) to safely
    /// reveal all items without the invariant violation that causes position corruption.
    func moveIconAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toAlwaysHidden: Bool
    ) -> Bool {
        let identityPrecision: MenuBarIdentityPrecision = Self.hasPreciseMoveIdentity(
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        ) ? .exact : .coarse
        guard prepareAlwaysHiddenMoveQueue(
            operationName: "moveIconAlwaysHidden",
            identityPrecision: identityPrecision,
            shouldEnableSection: toAlwaysHidden
        ) else {
            return false
        }

        let wasHidden = hidingService.state == .hidden
        let needsAuthCheck = !toAlwaysHidden && wasHidden && settings.requireAuthToShowHiddenIcons
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)
        let optimisticAlwaysHiddenMutation: AlwaysHiddenQueuedMutation =
            toAlwaysHidden
                ? .pin(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex)
                : .unpin(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex)

        return queueDetachedMoveTask(
            operationName: "moveIconAlwaysHidden",
            optimisticAlwaysHiddenMutation: optimisticAlwaysHiddenMutation
        ) { manager in
            // 1. Auth check if moving FROM always-hidden and auth is required
            if needsAuthCheck {
                let revealed = await manager.showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
            }

            // 2. Reveal ALL items using the shield pattern
            //    (main→10000, ah→14, main→20 — safe transition from any state)
            await manager.hidingService.showAll()
            try? await Task.sleep(for: .milliseconds(300))

            // 3. Resolve target position (both separators at visual size now)
            let (separatorX, visibleBoundaryX) = await manager.resolveAlwaysHiddenMoveTargetsWithRetries(
                toAlwaysHidden: toAlwaysHidden
            )

            guard let resolvedSeparatorX = separatorX else {
                logger.error("🔧 Cannot resolve separator position for always-hidden move")
                await manager.hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await manager.hidingService.hide() }
                return false
            }
            var activeSeparatorX = resolvedSeparatorX
            var activeVisibleBoundaryX = visibleBoundaryX

            // 4. Cmd+drag (icon and separator are both on-screen)
            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            let actionableMoveSafety = accessibilityService.actionableMoveResolutionSafety(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
            if !actionableMoveSafety.canExecuteMove {
                logger.warning("🔧 Refusing ambiguous always-hidden move target for \(bundleID, privacy: .private); exact identity could not be proven")
                await manager.hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await manager.hidingService.hide() }
                return false
            }
            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: toAlwaysHidden,
                targetLane: toAlwaysHidden ? .alwaysHidden : .visible,
                separatorX: activeSeparatorX,
                visibleBoundaryX: activeVisibleBoundaryX,
                originalMouseLocation: originalCGPoint
            )

            if !success, !toAlwaysHidden {
                success = await manager.verifyVisibleMoveWithFreshGeometry(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    staleSeparatorX: activeSeparatorX,
                    allowsGeometryRecheck: actionableMoveSafety.allowsClassifiedZoneFallback
                )
            }

            // One retry if verification failed
            if !success {
                logger.info("🔧 Always-hidden move retry with session tap...")
                try? await Task.sleep(for: .milliseconds(200))
                let retryTargets = await manager.resolveAlwaysHiddenMoveTargetsWithRetries(
                    toAlwaysHidden: toAlwaysHidden,
                    maxAttempts: 10
                )
                if let retrySeparatorX = retryTargets.0 {
                    activeSeparatorX = retrySeparatorX
                    activeVisibleBoundaryX = retryTargets.1
                    logger.info("🔧 Re-resolved always-hidden move targets for retry: separator=\(activeSeparatorX), visibleBoundary=\(activeVisibleBoundaryX ?? -1)")
                }
                success = accessibilityService.moveMenuBarIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    toHidden: toAlwaysHidden,
                    targetLane: toAlwaysHidden ? .alwaysHidden : .visible,
                    separatorX: activeSeparatorX,
                    visibleBoundaryX: activeVisibleBoundaryX,
                    eventTap: .cgSessionEventTap,
                    originalMouseLocation: originalCGPoint
                )
                logger.info("🔧 Always-hidden retry returned: \(success, privacy: .public)")
            }

            if !success {
                if actionableMoveSafety.allowsClassifiedZoneFallback {
                    let expectedZone: MoveExpectedZone = toAlwaysHidden ? .alwaysHidden : .visible
                    let classifiedMatch = await manager.verifyMoveByClassifiedZone(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        expectedZone: expectedZone
                    )
                    if classifiedMatch {
                        logger.info("🔧 Always-hidden move accepted after classification verification (\(toAlwaysHidden ? "alwaysHidden" : "visible"))")
                        success = true
                    }
                } else {
                    logger.info("🔧 Skipping always-hidden classified-zone fallback for ambiguous multi-item identity")
                }
            }

            if success, !toAlwaysHidden {
                await MainActor.run {
                    manager.postVisibleLaneCrowdingHintCandidate(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        separatorRightEdgeX: activeSeparatorX,
                        visibleBoundaryX: activeVisibleBoundaryX
                    )
                }
            }

            // Keep classification boundary caches aligned with the new layout.
            await manager.refreshSeparatorCacheAfterMove()

            // 5. Restore: re-block always-hidden items (shield pattern)
            await manager.hidingService.restoreFromShowAll()

            // 6. Re-hide if needed (BEFORE refresh so AX sees final positions)
            let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
            if wasHidden, !shouldSkipHide {
                await manager.hidingService.hide()
            }

            // 7. Refresh after positions settle
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            return success
        }
    }

    /// Move an icon into the always-hidden zone (if enabled).
    func moveIconToAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> Bool {
        moveIconAlwaysHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toAlwaysHidden: true
        )
    }

    /// Move an icon out of the always-hidden zone to the visible zone.
    func moveIconFromAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> Bool {
        moveIconAlwaysHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toAlwaysHidden: false
        )
    }

    /// Move an icon from the always-hidden zone to the regular hidden zone.
    /// Uses the AH separator as the reference (move right of it) and the main
    /// separator's left edge as the boundary (stay left of it).
    func moveIconFromAlwaysHiddenToHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> Bool {
        let identityPrecision: MenuBarIdentityPrecision = Self.hasPreciseMoveIdentity(
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        ) ? .exact : .coarse
        guard canQueueInteractiveMove(
            operationName: "moveIconFromAlwaysHiddenToHidden",
            requiresAlwaysHiddenSeparator: true,
            identityPrecision: identityPrecision
        ) else {
            return false
        }

        let wasHidden = hidingService.state == .hidden
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)

        return queueDetachedMoveTask(
            operationName: "moveIconFromAlwaysHiddenToHidden",
            optimisticAlwaysHiddenMutation: .unpin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        ) { manager in
            // 1. Reveal ALL items (both separators at visual size)
            await manager.hidingService.showAll()
            try? await Task.sleep(for: .milliseconds(300))

            // 2. Get AH separator right edge (move right of it) and
            //    main separator left edge (don't overshoot into visible zone)
            let (ahSepRightEdge, mainSepOriginX): (CGFloat?, CGFloat?) = await MainActor.run {
                guard let ahItem = manager.alwaysHiddenSeparatorItem,
                      let ahButton = ahItem.button,
                      let ahWindow = ahButton.window
                else { return (nil, nil) }
                let ahFrame = ahWindow.frame
                guard ahFrame.width > 0 else { return (nil, nil) }
                let ahRight = ahFrame.origin.x + ahFrame.width
                let mainLeft = manager.getSeparatorOriginX()
                return (ahRight, mainLeft)
            }

            guard let resolvedAHSepRightEdge = ahSepRightEdge else {
                logger.error("🔧 Cannot resolve AH separator position for AH-to-Hidden move")
                await manager.hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await manager.hidingService.hide() }
                return false
            }
            var activeAHSepRightEdge = resolvedAHSepRightEdge
            var activeMainSepOriginX = mainSepOriginX

            // 3. Cmd+drag: move RIGHT of AH separator, clamped LEFT of main separator
            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            let actionableMoveSafety = accessibilityService.actionableMoveResolutionSafety(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
            if !actionableMoveSafety.canExecuteMove {
                logger.warning("🔧 Refusing ambiguous AH-to-Hidden move target for \(bundleID, privacy: .private); exact identity could not be proven")
                await manager.hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await manager.hidingService.hide() }
                return false
            }
            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: false, // Move RIGHT of the AH separator (into hidden zone)
                separatorX: activeAHSepRightEdge,
                visibleBoundaryX: activeMainSepOriginX, // Clamp: stay LEFT of main separator
                originalMouseLocation: originalCGPoint
            )

            if !success {
                logger.info("🔧 AH-to-Hidden move retry with session tap...")
                try? await Task.sleep(for: .milliseconds(200))
                let retryTargets: (CGFloat?, CGFloat?) = await MainActor.run {
                    guard let ahItem = manager.alwaysHiddenSeparatorItem,
                      let ahButton = ahItem.button,
                      let ahWindow = ahButton.window
                else { return (nil, nil) }
                let ahFrame = ahWindow.frame
                guard ahFrame.width > 0 else { return (nil, nil) }
                let ahRight = ahFrame.origin.x + ahFrame.width
                let mainLeft = manager.getSeparatorOriginX()
                return (ahRight, mainLeft)
            }
                if let retryAHSepRightEdge = retryTargets.0 {
                    activeAHSepRightEdge = retryAHSepRightEdge
                    activeMainSepOriginX = retryTargets.1
                    logger.info("🔧 Re-resolved AH-to-Hidden targets for retry: ahRight=\(activeAHSepRightEdge), mainSepOrigin=\(activeMainSepOriginX ?? -1)")
                }
                success = accessibilityService.moveMenuBarIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    toHidden: false,
                    separatorX: activeAHSepRightEdge,
                    visibleBoundaryX: activeMainSepOriginX,
                    eventTap: .cgSessionEventTap,
                    originalMouseLocation: originalCGPoint
                )
            }

            if !success {
                if actionableMoveSafety.allowsClassifiedZoneFallback {
                    let classifiedMatch = await manager.verifyMoveByClassifiedZone(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        expectedZone: .hidden
                    )
                    if classifiedMatch {
                        logger.info("🔧 AH-to-Hidden move accepted after classification verification")
                        success = true
                    }
                } else {
                    logger.info("🔧 Skipping AH-to-Hidden classified-zone fallback for ambiguous multi-item identity")
                }
            }

            // Keep classification boundary caches aligned with the new layout.
            await manager.refreshSeparatorCacheAfterMove()

            // 4. Restore shield and re-hide (BEFORE refresh)
            await manager.hidingService.restoreFromShowAll()

            let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
            if wasHidden, !shouldSkipHide {
                await manager.hidingService.hide()
            }

            // 5. Refresh after positions settle
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            return success
        }
    }

    /// Reorder one menu bar icon relative to another using Cmd+drag.
    /// Returns true when the reorder task starts (actual success is async).
    func reorderIcon(
        sourceBundleID: String,
        sourceMenuExtraID: String? = nil,
        sourceStatusItemIndex: Int? = nil,
        targetBundleID: String,
        targetMenuExtraID: String? = nil,
        targetStatusItemIndex: Int? = nil,
        placeAfterTarget: Bool
    ) -> Bool {
        let preciseSourceIdentity = Self.hasPreciseMoveIdentity(
            menuExtraId: sourceMenuExtraID,
            statusItemIndex: sourceStatusItemIndex
        )
        let preciseTargetIdentity = Self.hasPreciseMoveIdentity(
            menuExtraId: targetMenuExtraID,
            statusItemIndex: targetStatusItemIndex
        )
        guard canQueueInteractiveMove(
            operationName: "reorderIcon",
            requiresAlwaysHiddenSeparator: false,
            identityPrecision: preciseSourceIdentity && preciseTargetIdentity ? .exact : .coarse
        ) else {
            return false
        }

        let wasHidden = hidingService.state == .hidden
        let requiresAuth = wasHidden && settings.requireAuthToShowHiddenIcons
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)

        return queueDetachedMoveTask(operationName: "reorderIcon") { manager in
            if requiresAuth {
                let revealed = await manager.showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
            }

            if wasHidden {
                await manager.hidingService.showAll()
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                try? await Task.sleep(for: .milliseconds(50))
            }

            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            var success = accessibilityService.reorderMenuBarIcon(
                sourceBundleID: sourceBundleID,
                sourceMenuExtraID: sourceMenuExtraID,
                sourceStatusItemIndex: sourceStatusItemIndex,
                targetBundleID: targetBundleID,
                targetMenuExtraID: targetMenuExtraID,
                targetStatusItemIndex: targetStatusItemIndex,
                placeAfterTarget: placeAfterTarget,
                originalMouseLocation: originalCGPoint
            )

            if !success {
                logger.info("🔧 reorderIcon retry...")
                try? await Task.sleep(for: .milliseconds(200))
                success = accessibilityService.reorderMenuBarIcon(
                    sourceBundleID: sourceBundleID,
                    sourceMenuExtraID: sourceMenuExtraID,
                    sourceStatusItemIndex: sourceStatusItemIndex,
                    targetBundleID: targetBundleID,
                    targetMenuExtraID: targetMenuExtraID,
                    targetStatusItemIndex: targetStatusItemIndex,
                    placeAfterTarget: placeAfterTarget,
                    originalMouseLocation: originalCGPoint
                )
            }

            // Keep classification boundary caches aligned with the new layout.
            await manager.refreshSeparatorCacheAfterMove()

            let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
            if wasHidden {
                await manager.hidingService.restoreFromShowAll()
                if !shouldSkipHide {
                    await manager.hidingService.hide()
                }
            }

            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            return success
        }
    }

    @MainActor
    private func queueDetachedMoveTask(
        operationName: String,
        optimisticAlwaysHiddenMutation: AlwaysHiddenQueuedMutation? = nil,
        _ operation: @escaping @Sendable (MenuBarManager) async -> Bool
    ) -> Bool {
        applyQueuedAlwaysHiddenMutation(optimisticAlwaysHiddenMutation)
        activeMoveTask = Task.detached(priority: .userInitiated) { [weak self] () async -> Bool in
            guard let self else { return false }

            await MainActor.run {
                SearchWindowController.shared.setMoveInProgress(true)
                self.hidingService.cancelRehide()
                AccessibilityService.shared.beginMenuBarCacheWarmupSuppression()
            }
            defer {
                Task { @MainActor [weak self] in
                    SearchWindowController.shared.setMoveInProgress(false)
                    AccessibilityService.shared.endMenuBarCacheWarmupSuppression()
                    self?.activeMoveTask = nil
                }
            }

            logger.info("🔧 \(operationName, privacy: .public) task started")
            let success = await operation(self)
            if !success {
                await MainActor.run {
                    self.rollbackQueuedAlwaysHiddenMutation(optimisticAlwaysHiddenMutation)
                }
            }
            return success
        }

        return true
    }

    @MainActor
    private func applyQueuedAlwaysHiddenMutation(_ mutation: AlwaysHiddenQueuedMutation?) {
        guard let mutation else { return }
        switch mutation {
        case let .pin(bundleID, menuExtraId, statusItemIndex):
            _ = pinAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        case let .unpin(bundleID, menuExtraId, statusItemIndex):
            _ = removeQueuedAlwaysHiddenPin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }
    }

    @MainActor
    private func rollbackQueuedAlwaysHiddenMutation(_ mutation: AlwaysHiddenQueuedMutation?) {
        guard let mutation else { return }
        switch mutation {
        case let .pin(bundleID, menuExtraId, statusItemIndex):
            _ = removeQueuedAlwaysHiddenPin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        case let .unpin(bundleID, menuExtraId, statusItemIndex):
            _ = pinAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }
    }

    @MainActor
    private func removeQueuedAlwaysHiddenPin(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> Bool {
        unpinAlwaysHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        ) || (!bundleID.hasPrefix("com.apple.controlcenter") && unpinAlwaysHidden(bundleID: bundleID))
    }

    @MainActor
    private func queuedMoveTaskIfStarted(_ started: Bool) -> Task<Bool, Never>? {
        guard started, let task = activeMoveTask else { return nil }
        return task
    }

    @MainActor
    private func waitForActiveMoveTaskIfNeeded() async {
        if let task = activeMoveTask {
            _ = await task.value
        }
    }

    @MainActor
    func queueZoneMove(
        app: RunningApp,
        request: ZoneMoveRequest
    ) -> Task<Bool, Never>? {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex
        let preferredCenterX = app.preferredCenterX

        let startedTask: Task<Bool, Never>?
        switch request {
        case .visibleToHidden:
            startedTask = queueMoveIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: true
            )
        case .hiddenToVisible:
            startedTask = queueMoveIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: false
            )
        case .visibleToAlwaysHidden, .hiddenToAlwaysHidden:
            startedTask = queueMoveIconToAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
        case .alwaysHiddenToVisible:
            startedTask = queueMoveIconFromAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
        case .alwaysHiddenToHidden:
            startedTask = queueMoveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
        }

        return startedTask
    }

    @MainActor
    func queueMoveIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        separatorOverrideX: CGFloat? = nil
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            moveIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: toHidden,
                separatorOverrideX: separatorOverrideX
            )
        )
    }

    @MainActor
    func queueMoveIconToAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            moveIconToAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
        )
    }

    @MainActor
    func queueMoveIconFromAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            moveIconFromAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
        )
    }

    @MainActor
    func queueMoveIconFromAlwaysHiddenToHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            moveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
        )
    }

    @MainActor
    func queueReorderIcon(
        sourceBundleID: String,
        sourceMenuExtraID: String? = nil,
        sourceStatusItemIndex: Int? = nil,
        targetBundleID: String,
        targetMenuExtraID: String? = nil,
        targetStatusItemIndex: Int? = nil,
        placeAfterTarget: Bool
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            reorderIcon(
                sourceBundleID: sourceBundleID,
                sourceMenuExtraID: sourceMenuExtraID,
                sourceStatusItemIndex: sourceStatusItemIndex,
                targetBundleID: targetBundleID,
                targetMenuExtraID: targetMenuExtraID,
                targetStatusItemIndex: targetStatusItemIndex,
                placeAfterTarget: placeAfterTarget
            )
        )
    }

    @MainActor
    func moveIconAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        separatorOverrideX: CGFloat? = nil
    ) async -> Bool {
        await waitForActiveMoveTaskIfNeeded()

        guard let task = queueMoveIcon(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toHidden: toHidden,
            separatorOverrideX: separatorOverrideX
        ) else { return false }
        return await task.value
    }

    @MainActor
    func moveIconAlwaysHiddenAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toAlwaysHidden: Bool
    ) async -> Bool {
        await waitForActiveMoveTaskIfNeeded()

        guard let task = queuedMoveTaskIfStarted(
            moveIconAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toAlwaysHidden: toAlwaysHidden
            )
        ) else { return false }
        return await task.value
    }

    @MainActor
    func moveIconFromAlwaysHiddenToHiddenAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) async -> Bool {
        await waitForActiveMoveTaskIfNeeded()

        guard let task = queueMoveIconFromAlwaysHiddenToHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        ) else { return false }
        return await task.value
    }
}

// swiftlint:enable file_length
