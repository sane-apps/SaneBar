import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.IconMoving")

extension MenuBarManager {
    // MARK: - Icon Moving

    /// Fallback estimate for separator edges when WindowServer reports stale/off-screen
    /// frames and no cache is available yet. We derive this from the main icon edge,
    /// because the separator is placed immediately to its left at visual width.
    private func estimatedSeparatorEdgesFromMainIcon() -> (originX: CGFloat, rightEdgeX: CGFloat)? {
        guard let mainLeftEdgeX = getMainStatusItemLeftEdgeX(), mainLeftEdgeX > 0 else { return nil }

        // Separator visual width is 20 in normal state.
        let visualWidth: CGFloat = 20
        let originX = max(1, mainLeftEdgeX - visualWidth)
        let rightEdgeX = originX + visualWidth
        return (originX, rightEdgeX)
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
                logger.debug("🔧 getSeparatorOriginX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
                return cachedX
            }

            if let estimated = estimatedSeparatorEdgesFromMainIcon() {
                lastKnownSeparatorX = estimated.originX
                if lastKnownSeparatorRightEdgeX == nil {
                    lastKnownSeparatorRightEdgeX = estimated.rightEdgeX
                }
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
        let x = separatorWindow.frame.origin.x
        // Cache valid on-screen positions for use during blocking mode
        if x > 0 {
            lastKnownSeparatorX = x
            if separatorWindow.frame.width > 0, separatorWindow.frame.width < 1000 {
                lastKnownSeparatorRightEdgeX = separatorWindow.frame.origin.x + separatorWindow.frame.width
            }
            return x
        }

        if let cachedX = lastKnownSeparatorX {
            return cachedX
        }

        if let estimated = estimatedSeparatorEdgesFromMainIcon() {
            lastKnownSeparatorX = estimated.originX
            if lastKnownSeparatorRightEdgeX == nil {
                lastKnownSeparatorRightEdgeX = estimated.rightEdgeX
            }
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

        // If in blocking mode (length > 1000), use cached position
        if item.length > 1000 {
            return lastKnownAlwaysHiddenSeparatorX
        }

        guard let separatorButton = item.button,
              let separatorWindow = separatorButton.window
        else {
            return lastKnownAlwaysHiddenSeparatorX
        }
        let x = separatorWindow.frame.origin.x
        // Cache valid on-screen positions for use during blocking mode
        if x > 0 {
            lastKnownAlwaysHiddenSeparatorX = x
        }
        return x
    }

    /// Get the separator's right edge X position (for moving icons)
    /// NOTE: This value changes based on expanded/collapsed state!
    /// Returns nil if separator position can't be determined
    func getSeparatorRightEdgeX() -> CGFloat? {
        guard let separatorItem else {
            logger.error("🔧 getSeparatorRightEdgeX: separatorItem is nil")
            return lastKnownSeparatorRightEdgeX
        }

        // If in blocking mode (length > 1000), live position is off-screen — use cache.
        // This mirrors getSeparatorOriginX() which already has this check.
        if separatorItem.length > 1000 {
            let cachedX = lastKnownSeparatorRightEdgeX ?? -1
            logger.debug("🔧 getSeparatorRightEdgeX: blocking mode (length=\(separatorItem.length)), using cached \(cachedX)")
            return lastKnownSeparatorRightEdgeX
        }

        guard let separatorButton = separatorItem.button,
              let separatorWindow = separatorButton.window
        else {
            logger.error("🔧 getSeparatorRightEdgeX: button or window is nil")
            return lastKnownSeparatorRightEdgeX
        }
        let frame = separatorWindow.frame
        logger.info("🔧 getSeparatorRightEdgeX: window.frame = \(String(describing: frame))")
        guard frame.width > 0 else {
            logger.error("🔧 getSeparatorRightEdgeX: frame.width is 0")
            return lastKnownSeparatorRightEdgeX
        }

        // If window frame looks stale (width > 1000 or origin off-screen),
        // WindowServer hasn't finished relayout after showAll() — use cache.
        // showAll() sets length=20 immediately but the window frame lags behind.
        if frame.width > 1000 || frame.origin.x < 0 {
            if let cachedX = lastKnownSeparatorRightEdgeX {
                logger.warning("🔧 getSeparatorRightEdgeX: stale frame (w=\(frame.width), x=\(frame.origin.x)), using cached \(cachedX)")
                return cachedX
            }

            if let estimated = estimatedSeparatorEdgesFromMainIcon() {
                lastKnownSeparatorX = estimated.originX
                lastKnownSeparatorRightEdgeX = estimated.rightEdgeX
                logger.warning("🔧 getSeparatorRightEdgeX: stale frame with empty cache, using estimated \(estimated.rightEdgeX)")
                return estimated.rightEdgeX
            }

            logger.warning("🔧 getSeparatorRightEdgeX: stale frame and no fallback available")
            return nil
        }

        // Cache both origin and right edge when separator is at visual size.
        // These caches are used during blocking mode or stale frame fallback.
        lastKnownSeparatorX = frame.origin.x
        lastKnownSeparatorRightEdgeX = frame.origin.x + frame.width

        let rightEdge = frame.origin.x + frame.width
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
            let separatorOrigin = getSeparatorOriginX()
            let separatorRightEdge = getSeparatorRightEdgeX()
            _ = getAlwaysHiddenSeparatorOriginX()

            if let separatorOrigin, let separatorRightEdge,
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
    private func computeMoveTargets(
        toHidden: Bool,
        separatorOverrideX: CGFloat?
    ) -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        if toHidden {
            let separatorX = separatorOverrideX ?? getSeparatorOriginX()
            var alwaysHiddenRightEdgeX: CGFloat?
            if separatorOverrideX == nil,
               let ahItem = alwaysHiddenSeparatorItem,
               let ahButton = ahItem.button,
               let ahWindow = ahButton.window,
               ahWindow.frame.width > 0, ahWindow.frame.width < 1000 {
                alwaysHiddenRightEdgeX = ahWindow.frame.origin.x + ahWindow.frame.width
                logger.info("🔧 AH separator right edge: \(alwaysHiddenRightEdgeX!)")
            }
            return (separatorX, alwaysHiddenRightEdgeX)
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
            let targets = await MainActor.run {
                self.computeMoveTargets(toHidden: toHidden, separatorOverrideX: separatorOverrideX)
            }
            lastTargets = targets

            if let separatorX = targets.separatorX, separatorX > 0 {
                if attempt > 1 {
                    logger.info("🔧 Resolved separator target after \(attempt * 50)ms")
                }
                return targets
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return lastTargets
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
        if let sepX = getSeparatorRightEdgeX() {
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

        let wasHidden = hidingState == .hidden
        logger.info("🔧 wasHidden: \(wasHidden)")

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
                    await MainActor.run { hidingService.cancelRehide() }
                }
                await hidingService.showAll()
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                // Tiny settle delay so status item window frames are stable.
                try? await Task.sleep(for: .milliseconds(50))
            }

            logger.info("🔧 Getting separator position for move...")
            let (separatorX, visibleBoundaryX) = await self.resolveMoveTargetsWithRetries(
                toHidden: toHidden,
                separatorOverrideX: separatorOverrideX
            )

            guard let separatorX else {
                logger.error("🔧 Cannot get separator position - ABORTING")
                return false
            }
            logger.info("🔧 Separator for move: X=\(separatorX), visibleBoundary=\(visibleBoundaryX ?? -1)")

            let accessibilityService = await MainActor.run { AccessibilityService.shared }

            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                toHidden: toHidden,
                separatorX: separatorX,
                visibleBoundaryX: visibleBoundaryX,
                originalMouseLocation: originalCGPoint
            )
            logger.info("🔧 moveMenuBarIcon returned: \(success, privacy: .public)")

            // One retry if verification failed — icon may have partially moved
            // or AX position hadn't settled yet on slower Macs.
            if !success {
                logger.info("🔧 Retrying move once...")
                try? await Task.sleep(for: .milliseconds(200))
                success = accessibilityService.moveMenuBarIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    toHidden: toHidden,
                    separatorX: separatorX,
                    visibleBoundaryX: visibleBoundaryX,
                    originalMouseLocation: originalCGPoint
                )
                logger.info("🔧 Retry returned: \(success, privacy: .public)")
            }

            // Restore shield pattern and re-hide if we expanded.
            // This MUST complete before refreshing — otherwise the AX scan
            // sees items mid-transition and returns stale positions.
            let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
            if wasHidden {
                logger.info("🔧 Restoring from showAll shield pattern...")
                await hidingService.restoreFromShowAll()
                if !shouldSkipHide {
                    logger.info("🔧 Move complete - re-hiding items...")
                    await hidingService.hide()
                }
            }

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

        let wasHidden = hidingState == .hidden
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
                    return (self.getAlwaysHiddenSeparatorOriginX(), nil)
                }
                let sep = self.getSeparatorRightEdgeX()
                let mainLeft = self.getMainStatusItemLeftEdgeX()
                return (sep, mainLeft)
            }

            guard let separatorX else {
                logger.error("🔧 Cannot resolve separator position for always-hidden move")
                await hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await hidingService.hide() }
                return false
            }

            // 4. Cmd+drag (icon and separator are both on-screen)
            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                toHidden: toAlwaysHidden,
                separatorX: separatorX,
                visibleBoundaryX: visibleBoundaryX,
                originalMouseLocation: originalCGPoint
            )

            // One retry if verification failed
            if !success {
                logger.info("🔧 Always-hidden move retry...")
                try? await Task.sleep(for: .milliseconds(200))
                success = accessibilityService.moveMenuBarIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    toHidden: toAlwaysHidden,
                    separatorX: separatorX,
                    visibleBoundaryX: visibleBoundaryX,
                    originalMouseLocation: originalCGPoint
                )
                logger.info("🔧 Always-hidden retry returned: \(success, privacy: .public)")
            }

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
        statusItemIndex: Int? = nil
    ) -> Bool {
        moveIconAlwaysHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            toAlwaysHidden: true
        )
    }

    /// Move an icon out of the always-hidden zone to the visible zone.
    func moveIconFromAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil
    ) -> Bool {
        moveIconAlwaysHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            toAlwaysHidden: false
        )
    }

    /// Move an icon from the always-hidden zone to the regular hidden zone.
    /// Uses the AH separator as the reference (move right of it) and the main
    /// separator's left edge as the boundary (stay left of it).
    func moveIconFromAlwaysHiddenToHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil
    ) -> Bool {
        guard !hidingService.isAnimating, !hidingService.isTransitioning else {
            logger.warning("🔧 moveIconFromAlwaysHiddenToHidden skipped — hiding service busy")
            return false
        }
        guard alwaysHiddenSeparatorItem != nil else {
            logger.error("🔧 Always-hidden separator unavailable")
            return false
        }

        let wasHidden = hidingState == .hidden
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

            guard let ahSepRightEdge else {
                logger.error("🔧 Cannot resolve AH separator position for AH-to-Hidden move")
                await hidingService.restoreFromShowAll()
                let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
                if wasHidden, !shouldSkipHide { await hidingService.hide() }
                return false
            }

            // 3. Cmd+drag: move RIGHT of AH separator, clamped LEFT of main separator
            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            var success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                toHidden: false, // Move RIGHT of the AH separator (into hidden zone)
                separatorX: ahSepRightEdge,
                visibleBoundaryX: mainSepOriginX, // Clamp: stay LEFT of main separator
                originalMouseLocation: originalCGPoint
            )

            if !success {
                logger.info("🔧 AH-to-Hidden move retry...")
                try? await Task.sleep(for: .milliseconds(200))
                success = accessibilityService.moveMenuBarIcon(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    toHidden: false,
                    separatorX: ahSepRightEdge,
                    visibleBoundaryX: mainSepOriginX,
                    originalMouseLocation: originalCGPoint
                )
            }

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

        let wasHidden = hidingState == .hidden
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

            if requiresAuth {
                let revealed = await showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
                await MainActor.run { hidingService.cancelRehide() }
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
            toHidden: toHidden,
            separatorOverrideX: separatorOverrideX
        )

        guard let task = activeMoveTask else { return false }
        let success = await task.value
        return started && success
    }
}
