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
    func moveIcon(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil, toHidden: Bool) -> Bool {
        logger.info("🔧 ========== MOVE ICON START ==========")
        logger.info("🔧 moveIcon: bundleID=\(bundleID, privacy: .public), menuExtraId=\(menuExtraId ?? "nil", privacy: .public), toHidden=\(toHidden, privacy: .public)")
        logger.info("🔧 Current hidingState: \(String(describing: self.hidingState))")

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
        // Cocoa coordinates (bottom-left)
        let originalLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: screenHeight - originalLocation.y)

        // Important: avoid blocking the MainActor while simulating Cmd+drag.
        // Any UI stalls here can make the Find Icon window appear to "collapse".
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // If moving FROM hidden TO visible, expand first so icon is draggable.
            if !toHidden && wasHidden {
                logger.info("🔧 Expanding hidden icons first...")
                // SECURITY: Use auth-guarded path instead of direct hidingService.show()
                if needsAuthCheck {
                    let revealed = await self.showHiddenItemsNow(trigger: .findIcon)
                    guard revealed else {
                        logger.info("🔧 Auth failed or cancelled - aborting icon move")
                        return
                    }
                } else {
                    await self.hidingService.show()
                }
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                // Tiny settle delay so status item window frames are stable.
                try? await Task.sleep(for: .milliseconds(50))
            }

            logger.info("🔧 Getting separator position for move...")
            let separatorX: CGFloat? = await MainActor.run {
                if toHidden {
                    return self.getSeparatorOriginX()
                }
                return self.getSeparatorRightEdgeX()
            }

            guard let separatorX else {
                logger.error("🔧 Cannot get separator position - ABORTING")
                return
            }
            logger.info("🔧 Separator for move: X=\(separatorX)")

            let accessibilityService = await MainActor.run { AccessibilityService.shared }

            let success = accessibilityService.moveMenuBarIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                toHidden: toHidden,
                separatorX: separatorX,
                originalMouseLocation: originalCGPoint
            )
            logger.info("🔧 moveMenuBarIcon returned: \(success, privacy: .public)")

            // Allow Cmd+drag to complete before refreshing.
            try? await Task.sleep(for: .milliseconds(250))

            await MainActor.run {
                logger.info("🔧 Triggering post-move refresh...")
                AccessibilityService.shared.invalidateMenuBarItemCache()
                NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
            }

            // If we auto-expanded to facilitate a move, re-hide now.
            if !toHidden && wasHidden {
                logger.info("🔧 Move complete - re-hiding items...")
                await self.hidingService.hide()
            }

            logger.info("🔧 ========== MOVE ICON END ==========")
        }

        return true
    }
}
