import AppKit
import ApplicationServices
import os.log

private let accessibilityDragLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityMenuBarDragService")

final class AccessibilityMenuBarMoveFailureStore: @unchecked Sendable {
    static let shared = AccessibilityMenuBarMoveFailureStore()

    private let lock = NSLock()
    private var storedReason: String?

    func reset() {
        lock.lock()
        storedReason = nil
        lock.unlock()
    }

    func record(_ reason: String) {
        lock.lock()
        storedReason = reason
        lock.unlock()
    }

    func consume() -> String? {
        lock.lock()
        let reason = storedReason
        storedReason = nil
        lock.unlock()
        return reason
    }
}

final class AccessibilityMenuBarDragService {
    private unowned let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }


    nonisolated func moveMenuBarIcon(
        fromKnownFrame iconFrame: CGRect,
        toHidden: Bool,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat? = nil,
        eventTap: CGEventTapLocation = .cghidEventTap,
        originalMouseLocation: CGPoint,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        AccessibilityMenuBarMoveFailureStore.shared.reset()
        guard accessibilityService.automaticMoveGate.allowsMove(origin: physicalMoveOrigin) else {
            accessibilityDragLogger.warning("🔧 Automatic move blocked by consent gate (origin=systemWakeRecovery)")
            return false
        }
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
        let didPostEvents = performCmdDrag(from: fromPoint, to: toPoint, eventTap: eventTap, restoreTo: originalMouseLocation)
        if didPostEvents {
            accessibilityService.automaticMoveGate.recordPostedMove(origin: physicalMoveOrigin)
        }
        return didPostEvents
    }

    nonisolated func reorderMenuBarIcon(
        sourceBundleID: String,
        sourceMenuExtraID: String? = nil,
        sourceStatusItemIndex: Int? = nil,
        targetBundleID: String,
        targetMenuExtraID: String? = nil,
        targetStatusItemIndex: Int? = nil,
        placeAfterTarget: Bool,
        originalMouseLocation: CGPoint,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        AccessibilityMenuBarMoveFailureStore.shared.reset()
        guard accessibilityService.automaticMoveGate.allowsMove(origin: physicalMoveOrigin) else {
            accessibilityDragLogger.warning("🔧 Automatic reorder blocked by consent gate (origin=systemWakeRecovery)")
            return false
        }
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
        let didPostEvents = performCmdDrag(from: fromPoint, to: toPoint, restoreTo: originalMouseLocation)
        if didPostEvents {
            accessibilityService.automaticMoveGate.recordPostedMove(origin: physicalMoveOrigin)
        }
        return didPostEvents
    }

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
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        guard accessibilityService.automaticMoveGate.allowsMove(origin: physicalMoveOrigin) else {
            accessibilityDragLogger.warning("🔧 Automatic move blocked by consent gate (origin=systemWakeRecovery)")
            return false
        }
        let tapName = eventTap == .cgSessionEventTap ? "session" : "hid"
        let resolvedTargetLane = targetLane ?? (toHidden ? .hidden : .visible)
        let screenFrames = NSScreen.screens.map(\.frame)
        let usablePreferredCenterX = AccessibilityMenuExtraFrameResolver.screenValidPreferredCenterX(
            preferredCenterX,
            screenFrames: screenFrames
        )
        if preferredCenterX != nil, usablePreferredCenterX == nil {
            accessibilityDragLogger.warning(
                "🔧 Dropping off-screen preferredCenterX before drag lookup: \(preferredCenterX ?? -1, privacy: .public)"
            )
        }
        accessibilityDragLogger.debug("🔧 moveMenuBarIcon: bundleID=\(bundleID, privacy: .private), menuExtraId=\(menuExtraId ?? "nil", privacy: .private), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public), toHidden=\(toHidden, privacy: .public), targetLane=\(String(describing: resolvedTargetLane), privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public), tap=\(tapName, privacy: .public)")

        guard accessibilityService.isTrusted else {
            accessibilityDragLogger.error("🔧 Accessibility permission not granted")
            return false
        }

        var iconFrame: CGRect?
        for attempt in 1 ... 30 {
            guard let frame = AccessibilityMenuExtraService.getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: usablePreferredCenterX
            ) else {
                break
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
        let visibleMoveFromNotchedMenuBand =
            !toHidden &&
            (resolvedTargetLane == .visible || resolvedTargetLane == .visibleFromAlwaysHidden)
        let rawFromPoint: CGPoint
        if visibleMoveFromNotchedMenuBand {
            guard let safeDragPoint = AccessibilityInteractionPolicy.notchSafeMenuBarDragPoint(
                for: iconFrame,
                preferredScreenFrame: referenceScreenFrame
            ) else {
                AccessibilityMenuBarMoveFailureStore.shared.record(
                    "notch-unsafe drag source beforeMidX=\(String(format: "%.2f", Double(iconFrame.midX)))"
                )
                accessibilityDragLogger.error(
                    "🔧 Refusing visible move from notch-unsafe drag origin: beforeMidX=\(iconFrame.midX, privacy: .public)"
                )
                return false
            }
            rawFromPoint = safeDragPoint
            if abs(safeDragPoint.x - iconFrame.midX) > 0.5 {
                accessibilityDragLogger.info(
                    "🔧 Adjusted visible drag source to notch-safe point: beforeMidX=\(iconFrame.midX, privacy: .public), dragX=\(safeDragPoint.x, privacy: .public)"
                )
            }
        } else {
            rawFromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        }

        accessibilityDragLogger.debug("🔧 Icon frame BEFORE: x=\(iconFrame.origin.x, privacy: .public), y=\(iconFrame.origin.y, privacy: .public), w=\(iconFrame.size.width, privacy: .public), h=\(iconFrame.size.height, privacy: .public)")

        let targetX = AccessibilityInteractionPolicy.moveTargetX(
            targetLane: resolvedTargetLane,
            iconWidth: iconFrame.size.width,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        accessibilityDragLogger.debug("🔧 Target X: \(targetX, privacy: .public)")

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
        accessibilityService.automaticMoveGate.recordPostedMove(origin: physicalMoveOrigin)

        var afterFrame: CGRect?
        var previousFrame: CGRect?
        let maxAttempts = 20
        for attempt in 1 ... maxAttempts {
            Thread.sleep(forTimeInterval: 0.05)
            let currentFrame = AccessibilityMenuExtraService.getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: usablePreferredCenterX
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

        var movedToExpectedSide = AccessibilityInteractionPolicy.frameIsInTargetLane(
            afterFrame: afterFrame,
            targetLane: resolvedTargetLane,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        let directionMismatch = AccessibilityInteractionPolicy.hasDirectionMismatch(
            beforeFrame: iconFrame,
            afterFrame: afterFrame,
            separatorX: separatorX,
            targetLane: resolvedTargetLane,
            visibleBoundaryX: visibleBoundaryX
        )
        if directionMismatch, resolvedTargetLane == .alwaysHidden || (resolvedTargetLane == .hidden && toHidden) {
            let deltaX = afterFrame.midX - iconFrame.midX
            accessibilityDragLogger.warning("🔧 Move direction mismatch: expected leftward hidden move, deltaX=\(deltaX, privacy: .public)")
        } else if directionMismatch, resolvedTargetLane == .hidden || resolvedTargetLane == .hiddenFromAlwaysHidden {
            let deltaX = afterFrame.midX - iconFrame.midX
            accessibilityDragLogger.warning("🔧 Move direction mismatch: expected rightward hidden-lane move, deltaX=\(deltaX, privacy: .public)")
        } else if directionMismatch {
            let deltaX = afterFrame.midX - iconFrame.midX
            accessibilityDragLogger.warning("🔧 Move direction mismatch: expected rightward visible move, deltaX=\(deltaX, privacy: .public)")
        }
        if directionMismatch {
            movedToExpectedSide = false
        }

        let shouldRetryHiddenFromAlwaysHiddenAfterBoundaryRefresh =
            resolvedTargetLane == .hiddenFromAlwaysHidden &&
            !directionMismatch &&
            AccessibilityInteractionPolicy.shouldRetryHiddenFromAlwaysHiddenAfterBoundaryRefresh(
                beforeFrame: iconFrame,
                afterFrame: afterFrame,
                separatorX: separatorX,
                visibleBoundaryX: visibleBoundaryX
            )

        if shouldRetryHiddenFromAlwaysHiddenAfterBoundaryRefresh {
            accessibilityDragLogger.warning(
                "🔧 AH-to-Hidden verification pending refreshed boundary retry: expected toHidden=\(toHidden, privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public), targetX=\(targetX, privacy: .public), beforeX=\(iconFrame.origin.x, privacy: .public), beforeMidX=\(iconFrame.midX, privacy: .public), afterX=\(afterFrame.origin.x, privacy: .public), afterMidX=\(afterFrame.midX, privacy: .public), deltaMidX=\(afterFrame.midX - iconFrame.midX, privacy: .public), preferredCenterX=\(preferredCenterX ?? -1, privacy: .public), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public)"
            )
        } else if !movedToExpectedSide {
            accessibilityDragLogger.error(
                "🔧 Move verification failed: expected toHidden=\(toHidden, privacy: .public), targetLane=\(String(describing: resolvedTargetLane), privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public), targetX=\(targetX, privacy: .public), beforeX=\(iconFrame.origin.x, privacy: .public), beforeMidX=\(iconFrame.midX, privacy: .public), afterX=\(afterFrame.origin.x, privacy: .public), afterMidX=\(afterFrame.midX, privacy: .public), deltaMidX=\(afterFrame.midX - iconFrame.midX, privacy: .public), preferredCenterX=\(preferredCenterX ?? -1, privacy: .public), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public)"
            )
        }

        return movedToExpectedSide
    }

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

    private final class ResultBox: @unchecked Sendable {
        var value: Bool = false
    }

    private final class DragTimeoutState: @unchecked Sendable {
        private let lock = NSLock()
        private var timedOut = false

        func markTimedOut() {
            lock.lock()
            timedOut = true
            lock.unlock()
        }

        var shouldStop: Bool {
            lock.lock()
            defer { lock.unlock() }
            return timedOut
        }
    }

    private nonisolated static func postMouseRestoreIfOnScreen(
        _ point: CGPoint,
        eventTap: CGEventTapLocation,
        screenFrames: [CGRect],
        globalMaxY: CGFloat
    ) {
        guard AccessibilityInteractionPolicy.isCGEventPointOnAnyScreen(
            point,
            screenFrames: screenFrames,
            globalMaxY: globalMaxY
        ) else {
            accessibilityDragLogger.warning("Skipping cursor restore because the original pointer position is no longer on any current screen")
            return
        }

        if let restoreEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) {
            restoreEvent.post(tap: eventTap)
        }
    }

    private nonisolated func performCmdDrag(
        from: CGPoint,
        to: CGPoint,
        eventTap: CGEventTapLocation = .cghidEventTap,
        restoreTo originalCGPoint: CGPoint
    ) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = ResultBox()
        let timeoutState = DragTimeoutState()
        let tapName = eventTap == .cgSessionEventTap ? "session" : "hid"

        DispatchQueue.global(qos: .userInitiated).async {
            guard !timeoutState.shouldStop else {
                semaphore.signal()
                return
            }

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

            guard !timeoutState.shouldStop else {
                semaphore.signal()
                return
            }
            if let moveToStart = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: from,
                mouseButton: .left
            ) {
                moveToStart.post(tap: eventTap)
                Thread.sleep(forTimeInterval: 0.06)
            }
            guard !timeoutState.shouldStop else {
                semaphore.signal()
                return
            }

            CGDisplayHideCursor(CGMainDisplayID())
            defer { CGDisplayShowCursor(CGMainDisplayID()) }

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
            Thread.sleep(forTimeInterval: 0.08)
            guard !timeoutState.shouldStop else {
                if let forceUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: from, mouseButton: .left) {
                    forceUp.post(tap: eventTap)
                }
                semaphore.signal()
                return
            }

            let dragDistance = hypot(to.x - from.x, to.y - from.y)
            let steps = AccessibilityInteractionPolicy.cmdDragStepCount(distance: dragDistance)
            for i in 1 ... steps {
                guard !timeoutState.shouldStop else {
                    if let forceUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: from, mouseButton: .left) {
                        forceUp.post(tap: eventTap)
                    }
                    semaphore.signal()
                    return
                }
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

            guard !timeoutState.shouldStop else {
                if let forceUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) {
                    forceUp.post(tap: eventTap)
                }
                semaphore.signal()
                return
            }
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
            Thread.sleep(forTimeInterval: 0.14)
            guard !timeoutState.shouldStop else {
                semaphore.signal()
                return
            }

            Self.postMouseRestoreIfOnScreen(
                originalCGPoint,
                eventTap: eventTap,
                screenFrames: NSScreen.screens.map(\.frame),
                globalMaxY: NSScreen.screens.map(\.frame.maxY).max() ?? globalMaxY
            )

            result.value = true

            Task { @MainActor in
                AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
            }

            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            timeoutState.markTimedOut()
            accessibilityDragLogger.error("🔧 performCmdDrag(\(tapName, privacy: .public)): semaphore timed out — forcing mouseUp to prevent stuck cursor")
            if let forceUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left) {
                forceUp.post(tap: eventTap)
            }
            Self.postMouseRestoreIfOnScreen(originalCGPoint, eventTap: eventTap, screenFrames: NSScreen.screens.map(\.frame), globalMaxY: NSScreen.screens.map(\.frame.maxY).max() ?? 0)
            return false
        }
        return result.value
    }}
