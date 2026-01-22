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
    /// If `menuExtraId` is provided, this clicks the matching AX child by `AXIdentifier`.
    func clickMenuBarItem(bundleID: String, menuExtraId: String?, statusItemIndex: Int? = nil) -> Bool {
        let menuExtraIdString = menuExtraId ?? "nil"
        let statusItemIndexString = statusItemIndex.map(String.init) ?? "nil"
        logger.info("Attempting to click menu bar item for: \(bundleID) (menuExtraId: \(menuExtraIdString), statusItemIndex: \(statusItemIndexString))")

        guard isTrusted else {
            logger.error("Accessibility permission not granted")
            return false
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return false
        }

        return clickSystemWideItem(for: app.processIdentifier, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex)
    }

    private func clickSystemWideItem(for targetPID: pid_t, menuExtraId: String?, statusItemIndex: Int?) -> Bool {
        let appElement = AXUIElementCreateApplication(targetPID)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

        guard result == .success, let bar = extrasBar else {
            logger.debug("App \(targetPID) has no AXExtrasMenuBar")
            return false
        }

        guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            logger.debug("No items in app's Extras Menu Bar")
            return false
        }

        logger.info("Found \(items.count) status item(s) for PID \(targetPID)")

        if let extraId = menuExtraId {
            for item in items {
                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                if let identifier = identifierValue as? String, identifier == extraId {
                    return performPress(on: item)
                }
            }
            logger.warning("Could not find status item with identifier: \(extraId)")
            return false
        }

        if let statusItemIndex, items.indices.contains(statusItemIndex) {
            return performPress(on: items[statusItemIndex])
        }

        return performPress(on: items[0])
    }

    // MARK: - Interaction

    private func performPress(on element: AXUIElement) -> Bool {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        if error == .success {
            logger.info("AXPress successful")
            return true
        }

        logger.debug("AXPress failed with error: \(error.rawValue)")

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

    /// Move a menu bar icon to visible or hidden position using CGEvent Cmd+drag.
    /// Returns `true` only if post-move verification indicates the icon crossed the separator.
    nonisolated func moveMenuBarIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        toHidden: Bool,
        separatorX: CGFloat,
        originalMouseLocation: CGPoint
    ) -> Bool {
        logger.error("🔧 moveMenuBarIcon: bundleID=\(bundleID, privacy: .public), menuExtraId=\(menuExtraId ?? "nil", privacy: .public), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public), toHidden=\(toHidden, privacy: .public), separatorX=\(separatorX, privacy: .public)")

        guard isTrusted else {
            logger.error("🔧 Accessibility permission not granted")
            return false
        }

        guard let iconFrame = getMenuBarIconFrame(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex) else {
            logger.error("🔧 Could not find icon frame for \(bundleID, privacy: .public) (menuExtraId: \(menuExtraId ?? "nil", privacy: .public))")
            return false
        }

        logger.error("🔧 Icon frame BEFORE: x=\(iconFrame.origin.x, privacy: .public), y=\(iconFrame.origin.y, privacy: .public), w=\(iconFrame.size.width, privacy: .public), h=\(iconFrame.size.height, privacy: .public)")

        // Calculate target position - keep it simple, just get on the correct SIDE of separator
        // Hidden: LEFT of separator (into hidden zone)
        // Visible: Just RIGHT of separator (between separator and main icon, not past main icon!)
        let targetX: CGFloat = toHidden ? (separatorX - 50) : (separatorX + 15)
        
        logger.error("🔧 Target X: \(targetX, privacy: .public)")

        // Apple docs: kAXPositionAttribute returns GLOBAL screen coordinates.
        // CGEvent also uses global screen coordinates.
        // X coordinate is IDENTICAL in both systems (no conversion needed).
        // Menu bar is at top of screen; Y≈12 is middle of standard menu bar.
        let fromPoint = CGPoint(x: iconFrame.midX, y: 12)
        let toPoint = CGPoint(x: targetX, y: 12)

        logger.error("🔧 CGEvent drag from (\(fromPoint.x, privacy: .public), \(fromPoint.y, privacy: .public)) to (\(toPoint.x, privacy: .public), \(toPoint.y, privacy: .public))")

        let didPostEvents = performCmdDrag(from: fromPoint, to: toPoint, restoreTo: originalMouseLocation)
        guard didPostEvents else {
            logger.error("🔧 Cmd+drag failed: could not post events")
            return false
        }

        // Wait longer for macOS to update the icon's AX position (0.25s)
        Thread.sleep(forTimeInterval: 0.25)

        guard let afterFrame = getMenuBarIconFrame(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex) else {
            logger.error("🔧 Icon position AFTER: unable to re-locate icon")
            return false
        }

        logger.error("🔧 Icon frame AFTER: x=\(afterFrame.origin.x, privacy: .public), y=\(afterFrame.origin.y, privacy: .public), w=\(afterFrame.size.width, privacy: .public), h=\(afterFrame.size.height, privacy: .public)")

        let margin: CGFloat = 8
        let movedToExpectedSide: Bool
        if toHidden {
            movedToExpectedSide = afterFrame.origin.x < (separatorX - margin)
        } else {
            movedToExpectedSide = afterFrame.origin.x > (separatorX + margin)
        }

        if !movedToExpectedSide {
            logger.error("🔧 Move verification failed: expected toHidden=\(toHidden, privacy: .public), separatorX=\(separatorX, privacy: .public), afterX=\(afterFrame.origin.x, privacy: .public)")
        }

        return movedToExpectedSide
    }

    nonisolated private func getMenuBarIconFrame(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil) -> CGRect? {
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
                logger.error("🔧 Could not find status item with identifier: \(extraId, privacy: .public)")
                return nil
            }
        } else if let statusItemIndex, items.indices.contains(statusItemIndex) {
            targetItem = items[statusItemIndex]
        } else {
            targetItem = items[0]
        }

        guard let item = targetItem else { return nil }

        var positionValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
        guard posResult == .success, let posValue = positionValue else { return nil }
        guard CFGetTypeID(posValue) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &origin) else { return nil }

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize(width: 22, height: 22)
        if sizeResult == .success, let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            var s = CGSize.zero
            // swiftlint:disable:next force_cast
            if AXValueGetValue(sizeVal as! AXValue, .cgSize, &s) {
                size = s
            }
        }

        return CGRect(origin: origin, size: size)
    }

    /// Thread-safe box for cross-thread value passing (semaphore provides synchronization)
    private final class ResultBox: @unchecked Sendable {
        var value: Bool = false
    }

    /// Perform a Cmd+drag operation using CGEvent (runs on background thread)
    nonisolated private func performCmdDrag(from: CGPoint, to: CGPoint, restoreTo originalCGPoint: CGPoint) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()

        DispatchQueue.global(qos: .userInitiated).async {
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

            // Start drag
            mouseDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.01)

            // Multi-step drag (6 steps for better reliability with macOS WindowServer)
            let steps = 6
            for i in 1...steps {
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
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }

            // Finish drag
            mouseUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.01)

            // Restore original cursor position immediately
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

        _ = semaphore.wait(timeout: .now() + 1.0)
        return result.value
    }

}
