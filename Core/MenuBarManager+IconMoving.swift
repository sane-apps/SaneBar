import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.IconMoving")

extension MenuBarManager {
    // MARK: - Icon Moving

    /// Get the separator's LEFT edge X position (for hidden/visible icon classification)
    /// Icons to the LEFT of this position (lower X) are HIDDEN
    /// Icons to the RIGHT of this position (higher X) are VISIBLE
    /// Returns nil if separator position can't be determined
    func getSeparatorOriginX() -> CGFloat? {
        guard let separatorButton = separatorItem?.button,
              let separatorWindow = separatorButton.window
        else {
            return nil
        }
        let frame = separatorWindow.frame
        return frame.origin.x
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
        guard let separatorButton = separatorItem?.button,
              let separatorWindow = separatorButton.window
        else {
            logger.error("🔧 getSeparatorRightEdgeX: separatorItem or window is nil")
            return nil
        }
        let frame = separatorWindow.frame
        logger.info("🔧 getSeparatorRightEdgeX: window.frame = \(String(describing: frame))")
        guard frame.width > 0 else {
            logger.error("🔧 getSeparatorRightEdgeX: frame.width is 0")
            return nil
        }
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
        let screenHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: screenHeight - originalLocation.y)
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

            defer {
                Task { @MainActor [weak self] in
                    self?.activeMoveTask = nil
                }
            }

            // If moving FROM hidden TO visible, expand first so icon is draggable.
            if !toHidden, wasHidden {
                logger.info("🔧 Expanding hidden icons first...")
                // SECURITY: Use auth-guarded path instead of direct hidingService.show()
                if needsAuthCheck {
                    let revealed = await showHiddenItemsNow(trigger: .findIcon)
                    guard revealed else {
                        logger.info("🔧 Auth failed or cancelled - aborting icon move")
                        return false
                    }
                } else {
                    await hidingService.show()
                }
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                // Tiny settle delay so status item window frames are stable.
                try? await Task.sleep(for: .milliseconds(50))
            }

            logger.info("🔧 Getting separator position for move...")
            let (separatorX, visibleBoundaryX): (CGFloat?, CGFloat?) = await MainActor.run {
                if toHidden {
                    let sep = separatorOverrideX ?? self.getSeparatorOriginX()
                    return (sep, nil)
                }
                let sep = self.getSeparatorRightEdgeX()
                let mainLeft = self.getMainStatusItemLeftEdgeX()
                return (sep, mainLeft)
            }

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

            // Allow Cmd+drag to complete before refreshing.
            try? await Task.sleep(for: .milliseconds(250))

            await MainActor.run {
                logger.info("🔧 Triggering post-move refresh...")
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            // If we auto-expanded to facilitate a move, re-hide now.
            // Check external monitor setting on MainActor
            let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
            if !toHidden, wasHidden, !shouldSkipHide {
                logger.info("🔧 Move complete - re-hiding items...")
                await hidingService.hide()
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
        let screenHeight = NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: screenHeight - originalLocation.y)
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

            defer {
                Task { @MainActor [weak self] in
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
            try? await Task.sleep(for: .milliseconds(250))
            await hidingService.restoreFromShowAll()

            // 6. Refresh
            await MainActor.run {
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            // 7. Re-hide if needed
            let shouldSkipHide = await MainActor.run { self.shouldSkipHideForExternalMonitor }
            if wasHidden, !shouldSkipHide {
                await hidingService.hide()
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
