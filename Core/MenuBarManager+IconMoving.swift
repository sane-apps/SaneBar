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
              let separatorWindow = separatorButton.window else {
            return nil
        }
        let frame = separatorWindow.frame
        return frame.origin.x
    }

    /// Get the separator's right edge X position (for moving icons)
    /// NOTE: This value changes based on expanded/collapsed state!
    /// Returns nil if separator position can't be determined
    func getSeparatorRightEdgeX() -> CGFloat? {
        guard let separatorButton = separatorItem?.button,
              let separatorWindow = separatorButton.window else {
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
              let mainWindow = mainButton.window else {
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
    func moveIcon(bundleID: String, menuExtraId: String? = nil, toHidden: Bool) -> Bool {
        logger.info("🔧 ========== MOVE ICON START ==========")
        logger.info("🔧 moveIcon: bundleID=\(bundleID), menuExtraId=\(menuExtraId ?? "nil"), toHidden=\(toHidden)")
        logger.info("🔧 Current hidingState: \(String(describing: self.hidingState))")

        // Log current positions BEFORE any action
        if let sepX = getSeparatorRightEdgeX() {
            logger.info("🔧 Separator right edge BEFORE: \(sepX)")
        }
        if let mainX = getMainStatusItemLeftEdgeX() {
            logger.info("🔧 Main icon left edge BEFORE: \(mainX)")
        }

        // If moving FROM hidden TO visible, expand (show) first so icon is draggable
        let wasHidden = hidingState == .hidden
        logger.info("🔧 wasHidden: \(wasHidden)")
        if !toHidden && wasHidden {
            logger.info("🔧 Expanding hidden icons first...")
            Task { await hidingService.show() }
        }

        // Minimal delay only if we needed to expand
        let delay: TimeInterval = (!toHidden && wasHidden) ? 0.3 : 0.05
        logger.info("🔧 Using delay: \(delay)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            logger.info("🔧 After delay, getting separator position...")
            guard let separatorX = getSeparatorRightEdgeX() else {
                logger.error("🔧 Cannot get separator position - ABORTING")
                return
            }
            logger.info("🔧 Separator X for move: \(separatorX)")

            // Get main SaneBar icon position to define visible zone boundary
            let mainIconX = getMainStatusItemLeftEdgeX()
            logger.info("🔧 Main SaneBar icon X for move: \(mainIconX ?? -1)")

            let success = AccessibilityService.shared.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                toHidden: toHidden,
                separatorX: separatorX,
                mainIconX: mainIconX
            )
            logger.info("🔧 moveMenuBarIcon returned: \(success)")

            // Force refresh the search window data after move
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                logger.info("🔧 Triggering post-move refresh...")
                // Invalidate any cached icon positions
                AccessibilityService.shared.invalidateMenuBarItemCache()
                // Post notification that icons may have moved
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)

                // If we auto-expanded to facilitate a move, re-hide now
                if !toHidden && wasHidden {
                    logger.info("🔧 Move complete - re-hiding items...")
                    Task { await hidingService.hide() }
                }

                logger.info("🔧 ========== MOVE ICON END ==========")
            }
        }

        return true
    }
}
