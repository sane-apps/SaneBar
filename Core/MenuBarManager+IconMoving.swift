import AppKit
import os.log

// swiftlint:disable file_length

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.IconMoving")

extension MenuBarManager {
    // MARK: - Icon Moving

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
        logger.info("🔧 getSeparatorRightEdgeX: window.frame = \(String(describing: frame))")
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
        logger.info("🔧 getSeparatorRightEdgeX: returning \(rightEdge)")
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
        logger.info("🔧 getMainStatusItemLeftEdgeX: window.frame = \(String(describing: frame))")
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

    /// Refresh cached separator boundaries after a drag mutation while separators
    /// are still at visual size. This prevents post-move zone classification from
    /// using stale hidden-mode cache values.
    @MainActor
    func refreshSeparatorCacheAfterMove() async {
        await warmSeparatorPositionCache(maxAttempts: 16)
        _ = getSeparatorOriginX()
        _ = getSeparatorRightEdgeX()
        _ = getAlwaysHiddenSeparatorOriginX()
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

    private func resolveMoveTargetsWithRetries(
        toHidden: Bool,
        separatorOverrideX: CGFloat?,
        maxAttempts: Int = 20
    ) async -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        var lastTargets: (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) = (nil, nil)

        for attempt in 1 ... maxAttempts {
            let (targets, liveSeparatorReady) = await MainActor.run {
                let targets = self.computeMoveTargets(toHidden: toHidden, separatorOverrideX: separatorOverrideX)
                let liveSeparatorReady = separatorOverrideX != nil || self.currentLiveSeparatorFrame() != nil
                return (targets, liveSeparatorReady)
            }
            lastTargets = targets

            if let separatorX = targets.separatorX, separatorX > 0 {
                if toHidden || (targets.visibleBoundaryX != nil && (targets.visibleBoundaryX ?? 0) > 0) {
                    if liveSeparatorReady || attempt == maxAttempts {
                        if attempt > 1 {
                            logger.info("🔧 Resolved separator target after \(attempt * 50)ms")
                        }
                        return targets
                    }

                    if attempt == 1 || attempt % 5 == 0 {
                        logger.debug("🔧 Cached separator target available after \(attempt * 50)ms but live frame is still stale")
                        logger.debug("🔧 Waiting for live separator frame before accepting cached move target")
                    }
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

    /// Move an icon to hidden or visible position
    /// - Parameters:
    ///   - bundleID: The bundle ID of the app to move
    ///   - menuExtraId: For Control Center items, the specific menu extra identifier
    ///   - toHidden: True to hide, false to show
    /// - Returns: True if successful
    func moveIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        separatorOverrideX: CGFloat? = nil
    ) -> Bool {
        // Block moves during hide/show or shield transitions
        let isBusy = hidingService.isAnimating || hidingService.isTransitioning
        guard !isBusy else {
            logger.warning("🔧 moveIcon skipped — hiding service busy")
            return false
        }

        logger.info("🔧 ========== MOVE ICON START ==========")
        logger.info("🔧 moveIcon: bundleID=\(bundleID, privacy: .private), menuExtraId=\(menuExtraId ?? "nil", privacy: .private), toHidden=\(toHidden, privacy: .public)")
        let currentHidingState = hidingState
        logger.info("🔧 Current hidingState: \(String(describing: currentHidingState))")

        // Log current positions BEFORE any action
        let preMoveSeparatorRightEdge = getSeparatorRightEdgeX()
        if let sepX = preMoveSeparatorRightEdge {
            logger.info("🔧 Separator right edge BEFORE: \(sepX)")
        }
        if let mainX = getMainStatusItemLeftEdgeX() {
            logger.info("🔧 Main icon left edge BEFORE: \(mainX)")
        }

        // IMPORTANT:
        // When the bar is hidden, the separator's *right edge* becomes extremely large
        // (because the separator length expands). Using that value for "Move to Hidden"
        // produces a target X far to the right, so the move appears to do nothing.
        //
        // Fix: for moves INTO the hidden zone, use the separator's LEFT edge.
        // For moves INTO the visible zone, ensure we're expanded, then use the RIGHT edge.

        let wasHidden = hidingService.state == .hidden
        logger.info("🔧 wasHidden: \(wasHidden)")

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
        guard !NSScreen.screens.isEmpty else {
            logger.error("🔧 moveIcon: No screens available — aborting")
            return false
        }

        // Reject if a move is already in progress — cancelling mid-drag
        // leaves mouse state corrupted (button stuck down, cursor teleported).
        if let existing = activeMoveTask, !existing.isCancelled {
            logger.warning("⚠️ Move rejected: another move is in progress")
            return false
        }

        // Important: avoid blocking the MainActor while simulating Cmd+drag.
        // Any UI stalls here can make the Find Icon window appear to "collapse".
        activeMoveTask = Task.detached(priority: .userInitiated) { [weak self] () async -> Bool in
            guard let self else { return false }

            // Prevent Find Icon window from auto-closing during CGEvent simulation
            await MainActor.run { SearchWindowController.shared.setMoveInProgress(true) }
            defer {
                Task { @MainActor [weak self] in
                    SearchWindowController.shared.setMoveInProgress(false)
                    self?.activeMoveTask = nil
                }
            }

            // Prevent any stale rehide timer from firing mid-drag.
            await MainActor.run { self.hidingService.cancelRehide() }

            var usedShowAllShield = false
            let restoreShieldIfNeeded = { () async in
                guard usedShowAllShield else { return }
                let shouldSkipHide = wasHidden
                    ? await MainActor.run { self.shouldSkipHideForExternalMonitor }
                    : false

                if wasHidden, !shouldSkipHide {
                    logger.info("🔧 Move complete - direct hide from showAll state")
                    await self.hidingService.hide()
                    return
                }

                logger.info("🔧 Restoring from showAll shield pattern...")
                await self.hidingService.restoreFromShowAll()
            }

            // When the bar is hidden, the separator is 10000px wide. It physically
            // blocks icon movement in BOTH directions. We must expand to visual size
            // (showAll) before any Cmd+drag, whether moving to hidden or to visible.
            if wasHidden {
                logger.info("🔧 Expanding ALL icons via shield pattern for move...")
                // SECURITY: Auth check if moving from hidden to visible with auth enabled
                if needsAuthCheck {
                    let revealed = await showHiddenItemsNow(trigger: .findIcon)
                    guard revealed else {
                        logger.info("🔧 Auth failed or cancelled - aborting icon move")
                        return false
                    }
                }
                await hidingService.showAll()
                usedShowAllShield = true
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                // Tiny settle delay so status item window frames are stable.
                try? await Task.sleep(for: .milliseconds(50))
            }

            logger.info("🔧 Getting separator position for move...")
            var (separatorX, visibleBoundaryX) = await self.resolveMoveTargetsWithRetries(
                toHidden: toHidden,
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
                    await hidingService.showAll()
                    usedShowAllShield = true
                    try? await Task.sleep(for: .milliseconds(300))
                    (separatorX, visibleBoundaryX) = await self.resolveMoveTargetsWithRetries(
                        toHidden: toHidden,
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
            logger.info("🔧 Separator for move: X=\(activeSeparatorX), visibleBoundary=\(activeVisibleBoundaryX ?? -1)")

            let accessibilityService = await MainActor.run { AccessibilityService.shared }

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
            logger.info("🔧 moveMenuBarIcon returned: \(success, privacy: .public)")

            // One retry if verification failed — icon may have partially moved
            // or AX position hadn't settled yet on slower Macs.
            if !success {
                logger.info("🔧 Retrying move once with session tap...")
                try? await Task.sleep(for: .milliseconds(200))

                let retryTargets = await self.resolveMoveTargetsWithRetries(
                    toHidden: toHidden,
                    separatorOverrideX: separatorOverrideX
                )
                if let retrySeparatorX = retryTargets.separatorX {
                    activeSeparatorX = retrySeparatorX
                    activeVisibleBoundaryX = retryTargets.visibleBoundaryX
                    let retryLabel = toHidden ? "hidden" : "visible"
                    logger.info("🔧 Re-resolved \(retryLabel) move targets for retry: separator=\(activeSeparatorX), visibleBoundary=\(activeVisibleBoundaryX ?? -1)")
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
                logger.info("🔧 Retry returned: \(success, privacy: .public)")
            }

            if !success && toHidden && !usedShowAllShield {
                logger.warning("🔧 Hidden move still failed after standard retry — forcing showAll shield fallback")
                await hidingService.showAll()
                usedShowAllShield = true
                try? await Task.sleep(for: .milliseconds(300))

                let (fallbackSeparatorX, fallbackVisibleBoundaryX) = await self.resolveMoveTargetsWithRetries(
                    toHidden: toHidden,
                    separatorOverrideX: separatorOverrideX
                )

                if let fallbackSeparatorX {
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
                } else {
                    logger.error("🔧 Shield fallback could not resolve separator - keeping failure")
                }
            }

            if !success {
                let expectedZone: MoveExpectedZone = toHidden ? .hidden : .visible
                let classifiedMatch = await self.verifyMoveByClassifiedZone(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    expectedZone: expectedZone
                )
                if classifiedMatch {
                    logger.info("🔧 Move accepted after classification verification (\(toHidden ? "hidden" : "visible"))")
                    success = true
                }
            }

            if success, toHidden {
                let removedAfterHiddenMove: Bool = await MainActor.run {
                    var removed = self.unpinAlwaysHidden(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex
                    )
                    if !removed, !bundleID.hasPrefix("com.apple.controlcenter") {
                        removed = self.unpinAlwaysHidden(bundleID: bundleID)
                    }
                    return removed
                }
                if removedAfterHiddenMove {
                    logger.info("🔧 Cleared stale always-hidden pin after successful move-to-hidden")
                }
            }

            if success, !toHidden {
                await MainActor.run {
                    self.postVisibleLaneCrowdingHintCandidate(
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
            await self.refreshSeparatorCacheAfterMove()

            // Restore shield pattern and re-hide (only when the original state was hidden).
            // This MUST complete before refreshing — otherwise the AX scan
            // sees items mid-transition and returns stale positions.
            await restoreShieldIfNeeded()

            // Allow positions to settle after re-hide, then refresh.
            try? await Task.sleep(for: .milliseconds(300))

            await MainActor.run {
                logger.info("🔧 Triggering post-move refresh...")
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            logger.info("🔧 ========== MOVE ICON END ==========")
            return success
        }

        return true
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
        // Block moves during hide/show or shield transitions
        guard !hidingService.isAnimating, !hidingService.isTransitioning else {
            logger.warning("🔧 moveIconAlwaysHidden skipped — hiding service busy")
            return false
        }
        guard alwaysHiddenSeparatorItem != nil else {
            logger.error("🔧 Always-hidden separator unavailable")
            return false
        }

        let wasHidden = hidingService.state == .hidden
        let needsAuthCheck = !toAlwaysHidden && wasHidden && settings.requireAuthToShowHiddenIcons
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)
        guard !NSScreen.screens.isEmpty else {
            logger.error("🔧 moveIconAlwaysHidden: No screens available — aborting")
            return false
        }

        if let existing = activeMoveTask, !existing.isCancelled {
            logger.warning("⚠️ Always-hidden move rejected: another move is in progress")
            return false
        }

        activeMoveTask = Task.detached(priority: .userInitiated) { [weak self] () async -> Bool in
            guard let self else { return false }

            await MainActor.run { SearchWindowController.shared.setMoveInProgress(true) }
            defer {
                Task { @MainActor [weak self] in
                    SearchWindowController.shared.setMoveInProgress(false)
                    self?.activeMoveTask = nil
                }
            }

            // Prevent any stale rehide timer from firing mid-drag.
            await MainActor.run { self.hidingService.cancelRehide() }

            // 1. Auth check if moving FROM always-hidden and auth is required
            if needsAuthCheck {
                let revealed = await showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
            }

            // 2. Reveal ALL items using the shield pattern
            //    (main→10000, ah→14, main→20 — safe transition from any state)
            await hidingService.showAll()
            try? await Task.sleep(for: .milliseconds(300))

            // 3. Resolve target position (both separators at visual size now)
            let (separatorX, visibleBoundaryX): (CGFloat?, CGFloat?) = await MainActor.run {
                if toAlwaysHidden {
                    return (self.getAlwaysHiddenSeparatorBoundaryX(), nil)
                }
                let sep = self.getSeparatorRightEdgeX()
                let mainLeft = self.getMainStatusItemLeftEdgeX()
                return (sep, mainLeft)
            }

            guard let resolvedSeparatorX = separatorX else {
                logger.error("🔧 Cannot resolve separator position for always-hidden move")
                await hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await hidingService.hide() }
                return false
            }
            var activeSeparatorX = resolvedSeparatorX
            var activeVisibleBoundaryX = visibleBoundaryX

            // 4. Cmd+drag (icon and separator are both on-screen)
            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: toAlwaysHidden,
                separatorX: activeSeparatorX,
                visibleBoundaryX: activeVisibleBoundaryX,
                originalMouseLocation: originalCGPoint
            )

            // One retry if verification failed
            if !success {
                logger.info("🔧 Always-hidden move retry with session tap...")
                try? await Task.sleep(for: .milliseconds(200))
                let retryTargets: (CGFloat?, CGFloat?) = await MainActor.run {
                    if toAlwaysHidden {
                        return (self.getAlwaysHiddenSeparatorBoundaryX(), nil)
                    }
                    return (self.getSeparatorRightEdgeX(), self.getMainStatusItemLeftEdgeX())
                }
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
                    separatorX: activeSeparatorX,
                    visibleBoundaryX: activeVisibleBoundaryX,
                    eventTap: .cgSessionEventTap,
                    originalMouseLocation: originalCGPoint
                )
                logger.info("🔧 Always-hidden retry returned: \(success, privacy: .public)")
            }

            if !success {
                let expectedZone: MoveExpectedZone = toAlwaysHidden ? .alwaysHidden : .visible
                let classifiedMatch = await self.verifyMoveByClassifiedZone(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    expectedZone: expectedZone
                )
                if classifiedMatch {
                    logger.info("🔧 Always-hidden move accepted after classification verification (\(toAlwaysHidden ? "alwaysHidden" : "visible"))")
                    success = true
                }
            }

            if success, !toAlwaysHidden {
                await MainActor.run {
                    self.postVisibleLaneCrowdingHintCandidate(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        separatorRightEdgeX: activeSeparatorX,
                        visibleBoundaryX: activeVisibleBoundaryX
                    )
                }
            }

            // Keep classification boundary caches aligned with the new layout.
            await self.refreshSeparatorCacheAfterMove()

            // 5. Restore: re-block always-hidden items (shield pattern)
            await hidingService.restoreFromShowAll()

            // 6. Re-hide if needed (BEFORE refresh so AX sees final positions)
            let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
            if wasHidden, !shouldSkipHide {
                await hidingService.hide()
            }

            // 7. Refresh after positions settle
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            return success
        }

        return true
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
        guard !hidingService.isAnimating, !hidingService.isTransitioning else {
            logger.warning("🔧 moveIconFromAlwaysHiddenToHidden skipped — hiding service busy")
            return false
        }
        guard alwaysHiddenSeparatorItem != nil else {
            logger.error("🔧 Always-hidden separator unavailable")
            return false
        }

        let wasHidden = hidingService.state == .hidden
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)
        guard !NSScreen.screens.isEmpty else { return false }

        if let existing = activeMoveTask, !existing.isCancelled {
            logger.warning("⚠️ AH-to-Hidden move rejected: another move is in progress")
            return false
        }

        activeMoveTask = Task.detached(priority: .userInitiated) { [weak self] () async -> Bool in
            guard let self else { return false }

            await MainActor.run { SearchWindowController.shared.setMoveInProgress(true) }
            defer {
                Task { @MainActor [weak self] in
                    SearchWindowController.shared.setMoveInProgress(false)
                    self?.activeMoveTask = nil
                }
            }

            // Prevent any stale rehide timer from firing mid-drag.
            await MainActor.run { self.hidingService.cancelRehide() }

            // 1. Reveal ALL items (both separators at visual size)
            await hidingService.showAll()
            try? await Task.sleep(for: .milliseconds(300))

            // 2. Get AH separator right edge (move right of it) and
            //    main separator left edge (don't overshoot into visible zone)
            let (ahSepRightEdge, mainSepOriginX): (CGFloat?, CGFloat?) = await MainActor.run {
                guard let ahItem = self.alwaysHiddenSeparatorItem,
                      let ahButton = ahItem.button,
                      let ahWindow = ahButton.window
                else { return (nil, nil) }
                let ahFrame = ahWindow.frame
                guard ahFrame.width > 0 else { return (nil, nil) }
                let ahRight = ahFrame.origin.x + ahFrame.width
                let mainLeft = self.getSeparatorOriginX()
                return (ahRight, mainLeft)
            }

            guard let resolvedAHSepRightEdge = ahSepRightEdge else {
                logger.error("🔧 Cannot resolve AH separator position for AH-to-Hidden move")
                await hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await hidingService.hide() }
                return false
            }
            var activeAHSepRightEdge = resolvedAHSepRightEdge
            var activeMainSepOriginX = mainSepOriginX

            // 3. Cmd+drag: move RIGHT of AH separator, clamped LEFT of main separator
            let accessibilityService = await MainActor.run { AccessibilityService.shared }
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
                    guard let ahItem = self.alwaysHiddenSeparatorItem,
                          let ahButton = ahItem.button,
                          let ahWindow = ahButton.window
                    else { return (nil, nil) }
                    let ahFrame = ahWindow.frame
                    guard ahFrame.width > 0 else { return (nil, nil) }
                    let ahRight = ahFrame.origin.x + ahFrame.width
                    let mainLeft = self.getSeparatorOriginX()
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
                let classifiedMatch = await self.verifyMoveByClassifiedZone(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    expectedZone: .hidden
                )
                if classifiedMatch {
                    logger.info("🔧 AH-to-Hidden move accepted after classification verification")
                    success = true
                }
            }

            // Keep classification boundary caches aligned with the new layout.
            await self.refreshSeparatorCacheAfterMove()

            // 4. Restore shield and re-hide (BEFORE refresh)
            await hidingService.restoreFromShowAll()

            let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
            if wasHidden, !shouldSkipHide {
                await hidingService.hide()
            }

            // 5. Refresh after positions settle
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            return success
        }

        return true
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
        guard !hidingService.isAnimating, !hidingService.isTransitioning else {
            logger.warning("🔧 reorderIcon skipped — hiding service busy")
            return false
        }

        let wasHidden = hidingService.state == .hidden
        let requiresAuth = wasHidden && settings.requireAuthToShowHiddenIcons
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)
        guard !NSScreen.screens.isEmpty else { return false }

        if let existing = activeMoveTask, !existing.isCancelled {
            logger.warning("⚠️ Reorder rejected: another move is in progress")
            return false
        }

        activeMoveTask = Task.detached(priority: .userInitiated) { [weak self] () async -> Bool in
            guard let self else { return false }

            await MainActor.run { SearchWindowController.shared.setMoveInProgress(true) }
            defer {
                Task { @MainActor [weak self] in
                    SearchWindowController.shared.setMoveInProgress(false)
                    self?.activeMoveTask = nil
                }
            }

            // Prevent any stale rehide timer from firing mid-drag.
            await MainActor.run { self.hidingService.cancelRehide() }

            if requiresAuth {
                let revealed = await showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
            }

            if wasHidden {
                await hidingService.showAll()
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
            await self.refreshSeparatorCacheAfterMove()

            let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
            if wasHidden {
                await hidingService.restoreFromShowAll()
                if !shouldSkipHide {
                    await hidingService.hide()
                }
            }

            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            return success
        }

        return true
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
        if let task = activeMoveTask {
            _ = await task.value
        }

        let started = moveIcon(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toHidden: toHidden,
            separatorOverrideX: separatorOverrideX
        )

        guard let task = activeMoveTask else { return false }
        let success = await task.value
        return started && success
    }

    @MainActor
    func moveIconAlwaysHiddenAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toAlwaysHidden: Bool
    ) async -> Bool {
        if let task = activeMoveTask {
            _ = await task.value
        }

        let started = moveIconAlwaysHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toAlwaysHidden: toAlwaysHidden
        )

        guard let task = activeMoveTask else { return false }
        let success = await task.value
        return started && success
    }

    @MainActor
    func moveIconFromAlwaysHiddenToHiddenAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) async -> Bool {
        if let task = activeMoveTask {
            _ = await task.value
        }

        let started = moveIconFromAlwaysHiddenToHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        )

        guard let task = activeMoveTask else { return false }
        let success = await task.value
        return started && success
    }
}

// swiftlint:enable file_length
