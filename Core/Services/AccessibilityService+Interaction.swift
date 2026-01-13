import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Interaction")

extension AccessibilityService {
    
    // MARK: - Actions

    /// Perform a "Virtual Click" on a menu bar item
    func clickMenuBarItem(for bundleID: String) -> Bool {
        logger.info("Attempting to click menu bar item for: \(bundleID)")

        guard isTrusted else {
            logger.error("Accessibility permission not granted")
            return false
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return false
        }

        return clickSystemWideItem(for: app.processIdentifier)
    }
    
    private func clickSystemWideItem(for targetPID: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(targetPID)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

        guard result == .success, let bar = extrasBar else {
            logger.debug("App \(targetPID) has no AXExtrasMenuBar")
            return false
        }

        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement
        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            logger.debug("No items in app's Extras Menu Bar")
            return false
        }

        logger.info("Found \(items.count) status item(s) for PID \(targetPID)")
        return performPress(on: items[0])
    }

    // MARK: - Interaction

    private func performPress(on element: AXUIElement) -> Bool {
        // Try AXPress - the standard action for buttons/menu items
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        if error == .success {
            logger.info("AXPress successful")
            return true
        }

        logger.debug("AXPress failed with error: \(error.rawValue)")

        // Try AXShowMenu as fallback (some apps use this instead)
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success,
           let names = actionNames as? [String],
           names.contains("AXShowMenu") {
            let menuError = AXUIElementPerformAction(element, "AXShowMenu" as CFString)
            if menuError == .success {
                logger.info("AXShowMenu successful")
                return true
            }
        }

        return false
    }

    // MARK: - Icon Moving (CGEvent-based)

    /// Move a menu bar icon to visible or hidden position using CGEvent Cmd+drag
    func moveMenuBarIcon(bundleID: String, menuExtraId: String? = nil, toHidden: Bool, separatorX: CGFloat, mainIconX: CGFloat? = nil) -> Bool {
        logger.error("🔧 moveMenuBarIcon: bundleID=\(bundleID), menuExtraId=\(menuExtraId ?? "nil"), toHidden=\(toHidden), separatorX=\(separatorX), mainIconX=\(mainIconX ?? -1)")

        guard isTrusted else {
            logger.error("🔧 Accessibility permission not granted")
            return false
        }

        // Find the icon's current position
        guard let iconPosition = getMenuBarIconPosition(bundleID: bundleID, menuExtraId: menuExtraId) else {
            logger.error("🔧 Could not find icon position for \(bundleID) (menuExtraId: \(menuExtraId ?? "nil"))")
            return false
        }

        logger.error("🔧 Icon position: x=\(iconPosition.x), width=\(iconPosition.width)")

        let targetX: CGFloat
        if toHidden {
            // Move to hidden zone - left of separator
            targetX = separatorX - 100
        } else if let mainX = mainIconX {
            // Move to visible zone - between separator and main SaneBar icon
            // Target the midpoint of the visible zone for best placement
            let visibleZoneWidth = mainX - separatorX
            if visibleZoneWidth > 50 {
                // Place icon 30px to the right of separator (near the separator end of visible zone)
                targetX = separatorX + 30
            } else {
                // Very narrow visible zone - place in the middle
                targetX = separatorX + (visibleZoneWidth / 2)
            }
            logger.error("🔧 Visible zone: separator=\(separatorX), mainIcon=\(mainX), width=\(visibleZoneWidth)")
        } else {
            // Fallback if mainIconX not provided - just use separator + 100
            targetX = separatorX + 100
            logger.error("🔧 Warning: mainIconX not provided, using fallback targetX=\(targetX)")
        }

        logger.error("🔧 Target X: \(targetX) (toHidden=\(toHidden), separator=\(separatorX), mainIcon=\(mainIconX ?? -1))")

        // CGEvent uses top-left screen coordinates (Quartz coordinate system)
        // Menu bar is at y=0 to y≈24, middle is around y=12
        let menuBarY: CGFloat = 12

        // The icon's X position from AX API is already in screen coordinates
        let fromPoint = CGPoint(x: iconPosition.x + iconPosition.width / 2, y: menuBarY)
        let toPoint = CGPoint(x: targetX, y: menuBarY)

        logger.error("🔧 CGEvent drag from (\(fromPoint.x), \(fromPoint.y)) to (\(toPoint.x), \(toPoint.y))")

        // Perform Cmd+drag using CGEvent
        return performCmdDrag(from: fromPoint, to: toPoint)
    }

    /// Get the position and size of a menu bar icon
    private func getMenuBarIconPosition(bundleID: String, menuExtraId: String? = nil) -> (x: CGFloat, width: CGFloat)? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        guard result == .success, let bar = extrasBar else { return nil }
        guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else { return nil }

        // Find the correct item - either by menuExtraId or just take the first one
        var targetItem: AXUIElement?

        if let extraId = menuExtraId {
            // For Control Center items, find the specific one by AXIdentifier
            for item in items {
                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                if let identifier = identifierValue as? String, identifier == extraId {
                    targetItem = item
                    logger.debug("🔧 Found Control Center item with identifier: \(extraId)")
                    break
                }
            }
            if targetItem == nil {
                logger.error("🔧 Could not find Control Center item with identifier: \(extraId)")
                return nil
            }
        } else {
            // For regular apps, take the first item
            targetItem = items[0]
        }

        guard let item = targetItem else { return nil }

        // Get position
        var positionValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
        guard posResult == .success, let posValue = positionValue else { return nil }
        guard CFGetTypeID(posValue) == AXValueGetTypeID() else { return nil }

        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point) else { return nil }

        // Get size
        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
        var width: CGFloat = 22  // Default width
        if sizeResult == .success, let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            var size = CGSize.zero
            // swiftlint:disable:next force_cast
            if AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) {
                width = size.width
            }
        }

        return (x: point.x, width: width)
    }

    /// Perform a Cmd+drag operation using CGEvent (runs on background thread)
    private func performCmdDrag(from: CGPoint, to: CGPoint) -> Bool {
        // Capture current mouse position BEFORE dispatching to background thread
        // NSEvent.mouseLocation uses bottom-left origin, CGEvent uses top-left
        let currentMouseLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let savedPosition = CGPoint(
            x: currentMouseLocation.x,
            y: screenHeight - currentMouseLocation.y
        )

        // Run CGEvent posting on a background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Create mouse down event with Cmd modifier
            guard let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: from,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse down event")
                return
            }
            mouseDown.flags = .maskCommand  // Hold Cmd key

            // Create drag event
            guard let mouseDrag = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: to,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse drag event")
                return
            }
            mouseDrag.flags = .maskCommand

            // Create mouse up event
            guard let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: to,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse up event")
                return
            }

            // Post events with minimal delays for reliability
            mouseDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)

            mouseDrag.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)

            mouseUp.post(tap: .cghidEventTap)

            // Restore cursor to original position after a brief delay
            Thread.sleep(forTimeInterval: 0.05)
            CGWarpMouseCursorPosition(savedPosition)

            // Invalidate cache on main thread
            DispatchQueue.main.async {
                self.invalidateMenuBarItemCache()
            }
        }

        return true  // Return immediately, operation happens async
    }
}
