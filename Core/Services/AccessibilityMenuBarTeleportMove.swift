import AppKit
import ApplicationServices
import os.log

private let teleportMoveLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityMenuBarDragService")

/// Maps an AXUIElement to its backing CGWindow ID. Private AX symbol, but the
/// only window-ID source that works with the Accessibility permission SaneBar
/// already holds — CGWindowList only enumerates other apps' status windows
/// when Screen Recording is granted, which SaneBar refuses on privacy grounds.
@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowPrivate(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AccessibilityMenuExtraService {
    /// Resolve the CGWindow ID for a menu bar item via AX (no Screen Recording
    /// needed). Returns nil when the element or its window cannot be resolved.
    nonisolated static func menuBarIconWindowID(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> CGWindowID? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var extrasBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar) == .success,
              let bar = extrasBar,
              let barElement = safeAXUIElement(bar)
        else {
            return nil
        }
        let childResult = AccessibilityBoundedAXChildFetch.children(
            of: barElement,
            maxCount: maxCollectedMenuExtraItems
        )
        guard !childResult.truncated, !childResult.children.isEmpty else { return nil }
        guard let item = resolvedTargetStatusItem(
            from: childResult.children,
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        ) else {
            return nil
        }
        var windowID: CGWindowID = 0
        guard AXUIElementGetWindowPrivate(item, &windowID) == .success, windowID != 0 else {
            return nil
        }
        return windowID
    }
}

/// Cross-notch "teleport" move primitive.
///
/// A straight-line cmd-drag whose interpolated path enters the notch cutout is
/// silently dropped by WindowServer (deltaMidX=0 on every accepted cross-notch
/// drag, proven live on the notched Air). The working primitive — shipped by
/// Ice (MIT) on notched hardware — is a windowID-tagged mouseDown/mouseUp pair:
/// the grabbed item rides the event's window-ID fields, so no pointer path
/// exists that could cross the notch dead zone.
extension AccessibilityMenuBarDragService {
    /// Private CGEventField (0x33) carrying the grabbed window's ID. WindowServer
    /// honors it for menu bar reorders even when the event location is nowhere
    /// near the item. The public mouseEventWindowUnderMousePointer fields are
    /// set alongside it.
    private static let teleportWindowIDField = CGEventField(rawValue: 0x33)!
    /// mouseDown location for teleport moves: far off every screen, so if the
    /// windowID targeting were ever ignored the synthetic click lands nowhere.
    private static let teleportOffscreenDownPoint = CGPoint(x: 20000, y: 20000)

    /// Move an item across the notch with a windowID-tagged mouseDown/mouseUp
    /// pair instead of a drag path. Returns true when both events posted; the
    /// caller's frame-delta verification remains the arbiter of success.
    nonisolated func performNotchTeleportMove(
        sourceBundleID: String,
        sourceMenuExtraId: String?,
        sourceStatusItemIndex: Int?,
        sourceFrame: CGRect,
        sourcePID: pid_t?,
        to: CGPoint,
        eventTap: CGEventTapLocation,
        restoreTo originalCGPoint: CGPoint
    ) -> Bool {
        guard let sourceWindowID = AccessibilityMenuExtraService.menuBarIconWindowID(
            bundleID: sourceBundleID,
            menuExtraId: sourceMenuExtraId,
            statusItemIndex: sourceStatusItemIndex,
            preferredCenterX: sourceFrame.midX
        ) else {
            teleportMoveLogger.warning("🔧 Teleport move: could not resolve source windowID for midX=\(sourceFrame.midX, privacy: .public) — falling back to drag")
            return false
        }

        // Anchor = SaneBar's own status item nearest the drop point (the
        // visible-lane target sits just left of our main icon). Its ID rides
        // the mouseUp so WindowServer inserts the grabbed item beside it.
        let hostBundleID = Bundle.main.bundleIdentifier ?? "com.sanebar.app"
        guard let anchorWindowID = AccessibilityMenuExtraService.menuBarIconWindowID(
            bundleID: hostBundleID,
            preferredCenterX: to.x
        ), anchorWindowID != sourceWindowID else {
            teleportMoveLogger.warning("🔧 Teleport move: could not resolve anchor windowID near targetX=\(to.x, privacy: .public) — falling back to drag")
            return false
        }

        guard let targetPID = sourcePID ?? NSRunningApplication.runningApplications(withBundleIdentifier: sourceBundleID).first?.processIdentifier else {
            teleportMoveLogger.warning("🔧 Teleport move: could not resolve source pid — falling back to drag")
            return false
        }

        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            teleportMoveLogger.error("🔧 Teleport move: could not create CGEventSource")
            return false
        }
        let permitAllEvents: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents
        ]
        eventSource.setLocalEventsFilterDuringSuppressionState(permitAllEvents, state: .eventSuppressionStateRemoteMouseDrag)
        eventSource.setLocalEventsFilterDuringSuppressionState(permitAllEvents, state: .eventSuppressionStateSuppressionInterval)
        eventSource.localEventsSuppressionInterval = 0

        func teleportEvent(type: CGEventType, location: CGPoint, windowID: CGWindowID, flags: CGEventFlags) -> CGEvent? {
            guard let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else {
                return nil
            }
            event.flags = flags
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
            event.setIntegerValueField(.eventSourceUserData, value: Int64(truncatingIfNeeded: UInt64(mach_absolute_time())))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            event.setIntegerValueField(Self.teleportWindowIDField, value: Int64(windowID))
            return event
        }

        guard let mouseDown = teleportEvent(
            type: .leftMouseDown,
            location: Self.teleportOffscreenDownPoint,
            windowID: sourceWindowID,
            flags: .maskCommand
        ), let mouseUp = teleportEvent(
            type: .leftMouseUp,
            location: to,
            windowID: anchorWindowID,
            flags: []
        ) else {
            teleportMoveLogger.error("🔧 Teleport move: could not create events")
            return false
        }

        teleportMoveLogger.info(
            "🔧 Teleport move: sourceWindowID=\(sourceWindowID, privacy: .public), anchorWindowID=\(anchorWindowID, privacy: .public), pid=\(targetPID, privacy: .public), dropX=\(to.x, privacy: .public)"
        )

        CGDisplayHideCursor(CGMainDisplayID())
        defer { CGDisplayShowCursor(CGMainDisplayID()) }

        mouseDown.post(tap: eventTap)
        Thread.sleep(forTimeInterval: 0.08)
        mouseUp.post(tap: eventTap)
        Thread.sleep(forTimeInterval: 0.05)
        // A second mouseUp guards against a stuck grab if the first was
        // swallowed by another app's event tap.
        if let secondUp = teleportEvent(type: .leftMouseUp, location: to, windowID: anchorWindowID, flags: []) {
            secondUp.post(tap: eventTap)
        }

        let screens = NSScreen.screens
        let globalMaxY = screens.map(\.frame.maxY).max() ?? 0
        Self.postMouseRestoreIfOnScreen(
            originalCGPoint,
            eventTap: eventTap,
            screenFrames: screens.map(\.frame),
            globalMaxY: globalMaxY
        )
        return true
    }
}
