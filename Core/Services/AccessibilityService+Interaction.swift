import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Interaction")

extension AccessibilityService {
    // MARK: - Actions

    func clickMenuBarItem(for bundleID: String) -> Bool {
        clickMenuBarItem(bundleID: bundleID, menuExtraId: nil)
    }

    /// Perform a "Virtual Click" on a specific menu bar item.
    func clickMenuBarItem(bundleID: String, menuExtraId: String?, statusItemIndex: Int? = nil, isRightClick: Bool = false) -> Bool {
        let menuExtraIdString = menuExtraId ?? "nil"
        let statusItemIndexString = statusItemIndex.map(String.init) ?? "nil"
        logger.info("Attempting to click menu bar item for: \(bundleID) (menuExtraId: \(menuExtraIdString), statusItemIndex: \(statusItemIndexString), rightClick: \(isRightClick))")

        guard isTrusted else {
            logger.error("Accessibility permission not granted")
            return false
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return false
        }

        return clickSystemWideItem(for: app.processIdentifier, bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex, isRightClick: isRightClick)
    }

    private func clickSystemWideItem(for targetPID: pid_t, bundleID: String, menuExtraId: String?, statusItemIndex: Int?, isRightClick: Bool) -> Bool {
        let appElement = AXUIElementCreateApplication(targetPID)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

        guard result == .success, let bar = extrasBar else {
            logger.debug("App \(targetPID) has no AXExtrasMenuBar")
            // Fallback: If AX fails to find the bar, we try to get the frame directly and hardware-click
            return hardwareClickAsFallback(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex, isRightClick: isRightClick)
        }

        guard let barElement = safeAXUIElement(bar) else { return false }

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            logger.debug("No items in app's Extras Menu Bar")
            return hardwareClickAsFallback(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex, isRightClick: isRightClick)
        }

        logger.info("Found \(items.count) status item(s) for PID \(targetPID)")

        let targetItem: AXUIElement?
        if let extraId = menuExtraId {
            var match: AXUIElement?
            for item in items {
                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                if let identifier = identifierValue as? String, identifier == extraId {
                    match = item
                    break
                }
            }
            targetItem = match
        } else if let statusItemIndex, items.indices.contains(statusItemIndex) {
            targetItem = items[statusItemIndex]
        } else {
            targetItem = items[0]
        }

        guard let item = targetItem else {
            logger.warning("Could not find target status item for click")
            return hardwareClickAsFallback(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex, isRightClick: isRightClick)
        }

        // Try AX first
        if performSmartPress(on: item, isRightClick: isRightClick) {
            return true
        }

        // Fallback to hardware event
        return hardwareClickAsFallback(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex, isRightClick: isRightClick)
    }

    private func hardwareClickAsFallback(bundleID: String, menuExtraId: String?, statusItemIndex: Int?, isRightClick: Bool) -> Bool {
        logger.info("Performing hardware click fallback for \(bundleID)")
        guard let frame = getMenuBarIconFrame(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex) else {
            logger.error("Hardware click failed: could not find icon frame")
            return false
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return simulateHardwareClick(at: center, isRightClick: isRightClick)
    }

    // MARK: - Interaction

    private func performSmartPress(on element: AXUIElement, isRightClick: Bool) -> Bool {
        // AX doesn't have a native "right-click" action for most items,
        // so we usually fallback to hardware click for that.
        if isRightClick { return false }

        // Some apps (Antinote, BetterDisplay) have nested clickable elements.
        // We look for any child that supports AXPress if the top-level doesn't.
        if performPress(on: element) { return true }

        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childItems = children as? [AXUIElement] {
            for child in childItems where performPress(on: child) {
                return true
            }
        }

        return false
    }

    private func performPress(on element: AXUIElement) -> Bool {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        if error == .success {
            logger.info("AXPress successful")
            return true
        }

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

    private func simulateHardwareClick(at point: CGPoint, isRightClick: Bool) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)

        let mouseDownType: CGEventType = isRightClick ? .rightMouseDown : .leftMouseDown
        let mouseUpType: CGEventType = isRightClick ? .rightMouseUp : .leftMouseUp
        let mouseButton: CGMouseButton = isRightClick ? .right : .left

        guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: mouseDownType, mouseCursorPosition: point, mouseButton: mouseButton),
              let mouseUp = CGEvent(mouseEventSource: source, mouseType: mouseUpType, mouseCursorPosition: point, mouseButton: mouseButton)
        else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        mouseUp.post(tap: .cghidEventTap)

        logger.info("Simulated hardware click at \(point.x), \(point.y)")
        return true
    }

    // MARK: - Icon Moving (CGEvent-based)

    /// Move a menu bar icon to visible or hidden position using CGEvent Cmd+drag.
    /// Returns `true` only if post-move verification indicates the icon crossed the separator.
    /// - Parameter visibleBoundaryX: The left edge of SaneBar's main icon. When moving to visible,
    ///   the target is clamped to stay LEFT of this position so icons don't overshoot past our icon.
    nonisolated func moveMenuBarIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        toHidden: Bool,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat? = nil,
        originalMouseLocation: CGPoint
    ) -> Bool {
        logger.info("🔧 moveMenuBarIcon: bundleID=\(bundleID, privacy: .private), menuExtraId=\(menuExtraId ?? "nil", privacy: .private), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public), toHidden=\(toHidden, privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public)")

        guard isTrusted else {
            logger.error("🔧 Accessibility permission not granted")
            return false
        }

        // Poll until icon is on-screen. After show()/showAll(), macOS WindowServer
        // re-layouts menu bar items asynchronously. Icons may still be at off-screen
        // positions (e.g. x=-3455) when the caller's sleep completes. We must wait
        // for the icon to reach a valid on-screen position before attempting the drag.
        var iconFrame: CGRect?
        for attempt in 1 ... 30 { // 30 × 100ms = 3s max
            guard let frame = getMenuBarIconFrame(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex) else {
                break // icon not found at all
            }
            if frame.origin.x >= 0 {
                iconFrame = frame
                if attempt > 1 {
                    logger.info("🔧 Icon moved on-screen after \(attempt * 100)ms polling (x=\(frame.origin.x, privacy: .public))")
                }
                break
            }
            logger.debug("🔧 Icon still off-screen (x=\(frame.origin.x, privacy: .public)), polling attempt \(attempt)...")
            Thread.sleep(forTimeInterval: 0.1)
        }

        guard let iconFrame else {
            logger.error("🔧 Could not find on-screen icon frame for \(bundleID, privacy: .private) (menuExtraId: \(menuExtraId ?? "nil", privacy: .private))")
            return false
        }

        logger.info("🔧 Icon frame BEFORE: x=\(iconFrame.origin.x, privacy: .public), y=\(iconFrame.origin.y, privacy: .public), w=\(iconFrame.size.width, privacy: .public), h=\(iconFrame.size.height, privacy: .public)")

        // Calculate target position
        // Hidden: LEFT of separator (into hidden zone) — need enough offset to clearly cross.
        // Visible: just LEFT of the SaneBar icon — macOS auto-inserts the icon there.
        //          Never overshoot past SaneBar or the icon lands in the system area.
        let moveOffset = max(30, iconFrame.size.width + 20)
        let targetX: CGFloat = if toHidden, let ahBoundary = visibleBoundaryX {
            // Clamp: stay right of AH separator so we land in hidden zone, not AH zone
            max(separatorX - moveOffset, ahBoundary + 2)
        } else if toHidden {
            // No clamp = enforcement or direct AH targeting. Drag farther left
            // to decisively cross the separator (macOS has snap-back resistance).
            separatorX - max(80, iconFrame.size.width + 60)
        } else if let boundary = visibleBoundaryX {
            // Target just left of SaneBar icon, but always right of separator.
            // When they're flush (both 1696), this gives separatorX + 1 — right of separator,
            // at the SaneBar icon boundary. macOS auto-inserts and pushes SaneBar right.
            max(separatorX + 1, boundary - 2)
        } else {
            // Fallback if no boundary — just past separator
            separatorX + 1
        }

        logger.info("🔧 Target X: \(targetX, privacy: .public)")

        // Apple docs: kAXPositionAttribute returns GLOBAL screen coordinates.
        // CGEvent also uses global screen coordinates.
        // Use the icon's actual AX Y position instead of hardcoding Y=12,
        // which breaks with accessibility zoom, enlarged text, or non-standard menu bar heights.
        let menuBarY = iconFrame.midY
        let fromPoint = CGPoint(x: iconFrame.midX, y: menuBarY)
        let toPoint = CGPoint(x: targetX, y: menuBarY)

        logger.info("🔧 CGEvent drag from (\(fromPoint.x, privacy: .public), \(fromPoint.y, privacy: .public)) to (\(toPoint.x, privacy: .public), \(toPoint.y, privacy: .public))")

        let didPostEvents = performCmdDrag(from: fromPoint, to: toPoint, restoreTo: originalMouseLocation)
        guard didPostEvents else {
            logger.error("🔧 Cmd+drag failed: could not post events")
            return false
        }

        // Poll for AX position stability instead of fixed wait.
        // On slow Macs, 250ms isn't enough; on fast Macs, we finish sooner.
        var afterFrame: CGRect?
        var previousFrame: CGRect?
        let maxAttempts = 20 // 20 × 50ms = 1s max
        for attempt in 1 ... maxAttempts {
            Thread.sleep(forTimeInterval: 0.05)
            let currentFrame = getMenuBarIconFrame(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex)
            if let current = currentFrame, let previous = previousFrame, current.origin.x == previous.origin.x {
                afterFrame = current
                logger.info("🔧 AX position stabilized after \(attempt * 50)ms")
                break
            }
            previousFrame = currentFrame
            afterFrame = currentFrame
        }

        guard let afterFrame else {
            logger.error("🔧 Icon position AFTER: unable to re-locate icon")
            return false
        }

        logger.info("🔧 Icon frame AFTER: x=\(afterFrame.origin.x, privacy: .public), y=\(afterFrame.origin.y, privacy: .public), w=\(afterFrame.size.width, privacy: .public), h=\(afterFrame.size.height, privacy: .public)")

        // Verify icon landed on the expected side of the separator.
        // For hidden: icon's left edge must be LEFT of separatorX.
        // For visible: icon's left edge must be clearly RIGHT of separatorX.
        // "Visible" uses a margin to avoid boundary ambiguity; "hidden" uses a
        // tight check because the separator will physically block icons in place
        // once it re-expands (even icons just 1px across the line are trapped).
        let visibleMargin = max(4, afterFrame.size.width * 0.3)
        let movedToExpectedSide: Bool = if toHidden {
            afterFrame.origin.x < separatorX
        } else {
            afterFrame.origin.x > (separatorX + visibleMargin)
        }

        if !movedToExpectedSide {
            logger.error("🔧 Move verification failed: expected toHidden=\(toHidden, privacy: .public), separatorX=\(separatorX, privacy: .public), afterX=\(afterFrame.origin.x, privacy: .public)")
        }

        return movedToExpectedSide
    }

    private nonisolated func getMenuBarIconFrame(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil) -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.error("🔧 getMenuBarIconFrame: App not found for bundleID: \(bundleID, privacy: .private)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        guard result == .success, let bar = extrasBar else {
            logger.error("🔧 getMenuBarIconFrame: App \(bundleID, privacy: .private) has no AXExtrasMenuBar (Error: \(result.rawValue))")
            return nil
        }
        guard let barElement = safeAXUIElement(bar) else { return nil }

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            logger.error("🔧 getMenuBarIconFrame: No items found in AXExtrasMenuBar for \(bundleID, privacy: .private)")
            return nil
        }

        let targetItem: AXUIElement?
        if let extraId = menuExtraId {
            var match: AXUIElement?
            for item in items {
                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                if let identifier = identifierValue as? String, identifier == extraId {
                    match = item
                    break
                }
            }
            targetItem = match
            if targetItem == nil {
                logger.error("🔧 Could not find status item with identifier: \(extraId, privacy: .private)")
                return nil
            }
        } else if let statusItemIndex, items.indices.contains(statusItemIndex) {
            targetItem = items[statusItemIndex]
        } else {
            if items.count > 1 {
                logger.warning("🔧 getMenuBarIconFrame: App has \(items.count) status items but no menuExtraId/statusItemIndex — using first item (may be wrong)")
            }
            targetItem = items[0]
        }

        guard let item = targetItem else { return nil }

        var positionValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
        guard posResult == .success, let posValue = positionValue else { return nil }
        guard CFGetTypeID(posValue) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        guard let axPosValue = safeAXValue(posValue),
              AXValueGetValue(axPosValue, .cgPoint, &origin) else { return nil }

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize(width: 22, height: 22)
        if sizeResult == .success, let sizeVal = sizeValue, let axSizeVal = safeAXValue(sizeVal) {
            var s = CGSize.zero
            if AXValueGetValue(axSizeVal, .cgSize, &s) {
                // Clamp to prevent 0-width (AX can return 0 for some Control Center items)
                size = CGSize(width: max(1, s.width), height: max(1, s.height))
            }
        }

        return CGRect(origin: origin, size: size)
    }

    /// Thread-safe box for cross-thread value passing (semaphore provides synchronization)
    private final class ResultBox: @unchecked Sendable {
        var value: Bool = false
    }

    /// Perform a Cmd+drag operation using CGEvent (runs on background thread).
    /// Uses human-like timing (Ice-style): pre-position cursor, hide cursor,
    /// slow multi-step drag, dual event tap posting for reliability.
    private nonisolated func performCmdDrag(from: CGPoint, to: CGPoint, restoreTo originalCGPoint: CGPoint) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()

        DispatchQueue.global(qos: .userInitiated).async {
            // Verify both from and to are on valid screens
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                logger.warning("🔧 performCmdDrag: no screens available — aborting")
                semaphore.signal()
                return
            }
            let fromOnScreen = screens.contains { $0.frame.contains(from) }
            let targetOnScreen = screens.contains { $0.frame.contains(to) }
            if !fromOnScreen {
                logger.warning("🔧 performCmdDrag: from point (\(from.x), \(from.y)) is off-screen — aborting")
                semaphore.signal()
                return
            }
            if !targetOnScreen {
                logger.warning("🔧 performCmdDrag: target point (\(to.x), \(to.y)) is off-screen — aborting")
                semaphore.signal()
                return
            }

            // 1. Pre-position cursor at the icon (like a human would)
            if let moveToStart = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: from,
                mouseButton: .left
            ) {
                moveToStart.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.05) // Let cursor settle
            }

            // 2. Hide cursor during drag (Ice-style: prevents visual glitches
            //    and may improve drag recognition by WindowServer)
            CGDisplayHideCursor(CGMainDisplayID())
            defer { CGDisplayShowCursor(CGMainDisplayID()) }

            // 3. Cmd+mouseDown at icon position
            guard let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: from,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse down event")
                semaphore.signal()
                return
            }
            mouseDown.flags = .maskCommand
            mouseDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05) // Hold before dragging (human-like)

            // 4. Multi-step drag with human-like timing
            //    16 steps × 15ms = ~240ms total drag (vs old: 6 × 5ms = 30ms)
            let steps = 16
            for i in 1 ... steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = from.x + (to.x - from.x) * t
                let y = from.y + (to.y - from.y) * t
                let point = CGPoint(x: x, y: y)

                if let drag = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseDragged,
                    mouseCursorPosition: point,
                    mouseButton: .left
                ) {
                    drag.flags = .maskCommand
                    drag.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.015)
                }
            }

            // 5. Cmd+mouseUp at destination
            guard let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: to,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse up event")
                semaphore.signal()
                return
            }
            mouseUp.flags = .maskCommand
            mouseUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.15) // Let the 'drop' settle

            // 6. Restore cursor position
            if let restoreEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: originalCGPoint,
                mouseButton: .left
            ) {
                restoreEvent.post(tap: .cghidEventTap)
            }

            result.value = true

            Task { @MainActor in
                AccessibilityService.shared.invalidateMenuBarItemCache()
            }

            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            logger.error("🔧 performCmdDrag: semaphore timed out — forcing mouseUp to prevent stuck cursor")
            // Force-release mouse button to prevent cursor being stuck in drag state
            if let forceUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) {
                forceUp.post(tap: .cghidEventTap)
            }
            // Restore cursor position even on timeout
            if let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalCGPoint, mouseButton: .left) {
                restore.post(tap: .cghidEventTap)
            }
            return false
        }
        return result.value
    }
}
