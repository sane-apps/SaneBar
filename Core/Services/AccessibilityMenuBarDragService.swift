import AppKit
import ApplicationServices
import os.log

private let accessibilityDragLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityMenuBarDragService")

final class AccessibilityMenuBarDragService {
    private unowned let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    // MARK: - Icon Moving (CGEvent-based)

    /// Move a menu bar icon starting from a known WindowServer frame.
    /// Used for fallback paths when AX can't resolve an element.
    nonisolated func moveMenuBarIcon(
        fromKnownFrame iconFrame: CGRect,
        toHidden: Bool,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat? = nil,
        eventTap: CGEventTapLocation = .cghidEventTap,
        originalMouseLocation: CGPoint,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        guard accessibilityService.isTrusted else {
            accessibilityDragLogger.error("🔧 Accessibility permission not granted")
            return false
        }

        let targetX = AccessibilityInteractionPolicy.moveTargetX(
            toHidden: toHidden,
            iconWidth: iconFrame.size.width,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        let rawFromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        let rawToPoint = CGPoint(x: targetX, y: iconFrame.midY)
        let fromPoint = AccessibilityInteractionPolicy.normalizedCGEventPoint(
            fromAccessibilityPoint: rawFromPoint,
            preferredScreenFrame: referenceScreenFrame
        )
        let toPoint = AccessibilityInteractionPolicy.normalizedCGEventPoint(
            fromAccessibilityPoint: rawToPoint,
            preferredScreenFrame: referenceScreenFrame
        )
        return performCmdDrag(from: fromPoint, to: toPoint, eventTap: eventTap, restoreTo: originalMouseLocation)
    }

    /// Reorder one icon relative to another icon using Cmd+drag.
    /// Returns true when drag events were posted successfully.
    nonisolated func reorderMenuBarIcon(
        sourceBundleID: String,
        sourceMenuExtraID: String? = nil,
        sourceStatusItemIndex: Int? = nil,
        targetBundleID: String,
        targetMenuExtraID: String? = nil,
        targetStatusItemIndex: Int? = nil,
        placeAfterTarget: Bool,
        originalMouseLocation: CGPoint,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        guard accessibilityService.isTrusted else {
            accessibilityDragLogger.error("🔧 Accessibility permission not granted")
            return false
        }

        guard let sourceFrame = AccessibilityMenuExtraFrameResolver.getMenuBarIconFrameOnScreen(
            bundleID: sourceBundleID,
            menuExtraId: sourceMenuExtraID,
            statusItemIndex: sourceStatusItemIndex
        ) else {
            accessibilityDragLogger.error("🔧 reorderMenuBarIcon: source frame unavailable")
            return false
        }

        guard let targetFrame = AccessibilityMenuExtraFrameResolver.getMenuBarIconFrameOnScreen(
            bundleID: targetBundleID,
            menuExtraId: targetMenuExtraID,
            statusItemIndex: targetStatusItemIndex
        ) else {
            accessibilityDragLogger.error("🔧 reorderMenuBarIcon: target frame unavailable")
            return false
        }

        let spacing = max(8, targetFrame.width * 0.25)
        let targetX = placeAfterTarget ? (targetFrame.maxX + spacing) : (targetFrame.minX - spacing)
        let rawFromPoint = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let rawToPoint = CGPoint(x: targetX, y: targetFrame.midY)
        let fromPoint = AccessibilityInteractionPolicy.normalizedCGEventPoint(
            fromAccessibilityPoint: rawFromPoint,
            preferredScreenFrame: referenceScreenFrame
        )
        let toPoint = AccessibilityInteractionPolicy.normalizedCGEventPoint(
            fromAccessibilityPoint: rawToPoint,
            preferredScreenFrame: referenceScreenFrame
        )
        return performCmdDrag(from: fromPoint, to: toPoint, restoreTo: originalMouseLocation)
    }

    /// Move a menu bar icon to visible or hidden position using CGEvent Cmd+drag.
    /// Returns `true` only if post-move verification indicates the icon crossed the separator.
    /// - Parameter visibleBoundaryX: The left edge of SaneBar's main icon. When moving to visible,
    ///   the target is clamped to stay LEFT of this position so icons don't overshoot past our icon.
    nonisolated func moveMenuBarIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        targetLane: AccessibilityInteractionPolicy.MoveTargetLane? = nil,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat? = nil,
        eventTap: CGEventTapLocation = .cghidEventTap,
        originalMouseLocation: CGPoint,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        let tapName = eventTap == .cgSessionEventTap ? "session" : "hid"
        let resolvedTargetLane = targetLane ?? (toHidden ? .hidden : .visible)
        accessibilityDragLogger.debug("🔧 moveMenuBarIcon: bundleID=\(bundleID, privacy: .private), menuExtraId=\(menuExtraId ?? "nil", privacy: .private), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public), toHidden=\(toHidden, privacy: .public), targetLane=\(String(describing: resolvedTargetLane), privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public), tap=\(tapName, privacy: .public)")

        guard accessibilityService.isTrusted else {
            accessibilityDragLogger.error("🔧 Accessibility permission not granted")
            return false
        }

        // Poll until icon is on-screen. After show()/showAll(), macOS WindowServer
        // re-layouts menu bar items asynchronously. Icons may still be at off-screen
        // positions (e.g. x=-3455) when the caller's sleep completes. We must wait
        // for the icon to reach a valid on-screen position before attempting the drag.
        var iconFrame: CGRect?
        for attempt in 1 ... 30 { // 30 × 100ms = 3s max
            guard let frame = AccessibilityMenuExtraService.getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            ) else {
                break // icon not found at all
            }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if AccessibilityInteractionPolicy.isAccessibilityPointOnAnyScreen(
                center,
                screenFrames: NSScreen.screens.map(\.frame),
                preferredScreenFrame: referenceScreenFrame
            ) {
                iconFrame = frame
                if attempt > 1 {
                    accessibilityDragLogger.debug("🔧 Icon moved on-screen after \(attempt * 100)ms polling (x=\(frame.origin.x, privacy: .public))")
                }
                break
            }
            accessibilityDragLogger.debug("🔧 Icon still off-screen (x=\(frame.origin.x, privacy: .public)), polling attempt \(attempt)...")
            Thread.sleep(forTimeInterval: 0.1)
        }

        guard let iconFrame else {
            accessibilityDragLogger.error("🔧 Could not find on-screen icon frame for \(bundleID, privacy: .private) (menuExtraId: \(menuExtraId ?? "nil", privacy: .private))")
            return false
        }

        accessibilityDragLogger.debug("🔧 Icon frame BEFORE: x=\(iconFrame.origin.x, privacy: .public), y=\(iconFrame.origin.y, privacy: .public), w=\(iconFrame.size.width, privacy: .public), h=\(iconFrame.size.height, privacy: .public)")

        // Calculate target position
        // Hidden: LEFT of separator (into hidden zone) — need enough offset to clearly cross.
        // Visible: just LEFT of the SaneBar icon — macOS auto-inserts the icon there.
        //          Never overshoot past SaneBar or the icon lands in the system area.
        let targetX = AccessibilityInteractionPolicy.moveTargetX(
            targetLane: resolvedTargetLane,
            iconWidth: iconFrame.size.width,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        accessibilityDragLogger.debug("🔧 Target X: \(targetX, privacy: .public)")

        // AX and CGEvent Y-axis orientation can differ by OS/build.
        // Normalize both points so drag coordinates stay anchored to the menu bar.
        let rawFromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        let rawToPoint = CGPoint(x: targetX, y: iconFrame.midY)
        let fromPoint = AccessibilityInteractionPolicy.normalizedCGEventPoint(
            fromAccessibilityPoint: rawFromPoint,
            preferredScreenFrame: referenceScreenFrame
        )
        let toPoint = AccessibilityInteractionPolicy.normalizedCGEventPoint(
            fromAccessibilityPoint: rawToPoint,
            preferredScreenFrame: referenceScreenFrame
        )

        if abs(fromPoint.y - rawFromPoint.y) > 2 || abs(toPoint.y - rawToPoint.y) > 2 {
            accessibilityDragLogger.debug(
                "🔧 Normalized drag Y from raw (\(rawFromPoint.y, privacy: .public)->\(fromPoint.y, privacy: .public), \(rawToPoint.y, privacy: .public)->\(toPoint.y, privacy: .public))"
            )
        }
        accessibilityDragLogger.debug("🔧 CGEvent drag from (\(fromPoint.x, privacy: .public), \(fromPoint.y, privacy: .public)) to (\(toPoint.x, privacy: .public), \(toPoint.y, privacy: .public))")

        let didPostEvents = performCmdDrag(from: fromPoint, to: toPoint, eventTap: eventTap, restoreTo: originalMouseLocation)
        guard didPostEvents else {
            accessibilityDragLogger.error("🔧 Cmd+drag failed: could not post events")
            return false
        }

        // Poll for AX position stability instead of fixed wait.
        // On slow Macs, 250ms isn't enough; on fast Macs, we finish sooner.
        var afterFrame: CGRect?
        var previousFrame: CGRect?
        let maxAttempts = 20 // 20 × 50ms = 1s max
        for attempt in 1 ... maxAttempts {
            Thread.sleep(forTimeInterval: 0.05)
            let currentFrame = AccessibilityMenuExtraService.getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
            if let current = currentFrame, let previous = previousFrame, current.origin.x == previous.origin.x {
                afterFrame = current
                accessibilityDragLogger.debug("🔧 AX position stabilized after \(attempt * 50)ms")
                break
            }
            previousFrame = currentFrame
            afterFrame = currentFrame
        }

        guard let afterFrame else {
            accessibilityDragLogger.error("🔧 Icon position AFTER: unable to re-locate icon")
            return false
        }

        accessibilityDragLogger.debug("🔧 Icon frame AFTER: x=\(afterFrame.origin.x, privacy: .public), y=\(afterFrame.origin.y, privacy: .public), w=\(afterFrame.size.width, privacy: .public), h=\(afterFrame.size.height, privacy: .public)")

        // Verify icon landed in the expected zone using midpoint-based logic.
        // This aligns with SearchService zone classification and prevents
        // false negatives when visible moves land close to the separator.
        var movedToExpectedSide = AccessibilityInteractionPolicy.frameIsInTargetZone(
            afterFrame: afterFrame,
            separatorX: separatorX,
            toHidden: toHidden,
            alwaysHiddenBoundaryX: visibleBoundaryX
        )

        // Guard against stale-boundary false positives/negatives by ensuring motion
        // direction matches intent before accepting the separator-side check.
        let directionMismatch = AccessibilityInteractionPolicy.hasDirectionMismatch(
            beforeFrame: iconFrame,
            afterFrame: afterFrame,
            separatorX: separatorX,
            toHidden: toHidden
        )
        if directionMismatch, toHidden {
            let deltaX = afterFrame.midX - iconFrame.midX
            accessibilityDragLogger.warning("🔧 Move direction mismatch: expected leftward hidden move, deltaX=\(deltaX, privacy: .public)")
            movedToExpectedSide = false
        } else if directionMismatch, !toHidden {
            let deltaX = afterFrame.midX - iconFrame.midX
            accessibilityDragLogger.warning("🔧 Move direction mismatch: expected rightward visible move, deltaX=\(deltaX, privacy: .public)")
            movedToExpectedSide = false
        }

        if !movedToExpectedSide {
            accessibilityDragLogger.error(
                "🔧 Move verification failed: expected toHidden=\(toHidden, privacy: .public), targetLane=\(String(describing: resolvedTargetLane), privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public), targetX=\(targetX, privacy: .public), beforeX=\(iconFrame.origin.x, privacy: .public), beforeMidX=\(iconFrame.midX, privacy: .public), afterX=\(afterFrame.origin.x, privacy: .public), afterMidX=\(afterFrame.midX, privacy: .public), deltaMidX=\(afterFrame.midX - iconFrame.midX, privacy: .public), preferredCenterX=\(preferredCenterX ?? -1, privacy: .public), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public)"
            )
        }

        return movedToExpectedSide
    }

    /// Returns current AX width for a specific menu bar item, if available.
    /// Used by move guardrails to avoid unsafe drags for unusually wide items.
    nonisolated func currentMenuBarIconWidth(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil
    ) -> CGFloat? {
        guard let frame = AccessibilityMenuExtraService.getMenuBarIconFrame(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        ) else {
            return nil
        }
        return frame.width
    }

    /// Thread-safe box for cross-thread value passing (semaphore provides synchronization)
    private final class ResultBox: @unchecked Sendable {
        var value: Bool = false
    }

    /// Perform a Cmd+drag operation using CGEvent (runs on background thread).
    /// Uses human-like timing (Ice-style): pre-position cursor, hide cursor,
    /// slow multi-step drag, dual event tap posting for reliability.
    private nonisolated func performCmdDrag(
        from: CGPoint,
        to: CGPoint,
        eventTap: CGEventTapLocation = .cghidEventTap,
        restoreTo originalCGPoint: CGPoint
    ) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()
        let tapName = eventTap == .cgSessionEventTap ? "session" : "hid"

        DispatchQueue.global(qos: .userInitiated).async {
            // Verify both from and to are on valid screens
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                accessibilityDragLogger.warning("🔧 performCmdDrag(\(tapName, privacy: .public)): no screens available — aborting")
                semaphore.signal()
                return
            }
            let globalMaxY = screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
            let screenFrames = screens.map(\.frame)
            let fromOnScreen = AccessibilityInteractionPolicy.isCGEventPointOnAnyScreen(
                from,
                screenFrames: screenFrames,
                globalMaxY: globalMaxY
            )
            let targetOnScreen = AccessibilityInteractionPolicy.isCGEventPointOnAnyScreen(
                to,
                screenFrames: screenFrames,
                globalMaxY: globalMaxY
            )
            if !fromOnScreen {
                accessibilityDragLogger.warning("🔧 performCmdDrag(\(tapName, privacy: .public)): from point (\(from.x), \(from.y)) is off-screen — aborting")
                semaphore.signal()
                return
            }
            if !targetOnScreen {
                accessibilityDragLogger.warning("🔧 performCmdDrag(\(tapName, privacy: .public)): target point (\(to.x), \(to.y)) is off-screen — aborting")
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
                moveToStart.post(tap: eventTap)
                Thread.sleep(forTimeInterval: 0.06) // Let cursor settle
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
                accessibilityDragLogger.error("Failed to create mouse down event")
                semaphore.signal()
                return
            }
            mouseDown.flags = .maskCommand
            mouseDown.post(tap: eventTap)
            Thread.sleep(forTimeInterval: 0.08) // Hold before dragging (human-like)

            // 4. Multi-step drag with human-like timing
            // Use fewer steps for short drags but keep a bounded, human-like path.
            let dragDistance = hypot(to.x - from.x, to.y - from.y)
            let steps = AccessibilityInteractionPolicy.cmdDragStepCount(distance: dragDistance)
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
                    drag.post(tap: eventTap)
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
                accessibilityDragLogger.error("Failed to create mouse up event")
                semaphore.signal()
                return
            }
            mouseUp.flags = .maskCommand
            mouseUp.post(tap: eventTap)
            Thread.sleep(forTimeInterval: 0.14) // Let the 'drop' settle

            // 6. Restore cursor position
            if let restoreEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: originalCGPoint,
                mouseButton: .left
            ) {
                restoreEvent.post(tap: eventTap)
            }

            result.value = true

            Task { @MainActor in
                AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
            }

            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            accessibilityDragLogger.error("🔧 performCmdDrag(\(tapName, privacy: .public)): semaphore timed out — forcing mouseUp to prevent stuck cursor")
            // Force-release mouse button to prevent cursor being stuck in drag state
            if let forceUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) {
                forceUp.post(tap: eventTap)
            }
            // Restore cursor position even on timeout
            if let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalCGPoint, mouseButton: .left) {
                restore.post(tap: eventTap)
            }
            return false
        }
        return result.value
    }}
