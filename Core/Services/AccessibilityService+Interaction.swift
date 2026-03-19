import AppKit
import ApplicationServices
import os.log

// swiftlint:disable file_length
private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Interaction")
extension AccessibilityService {
    enum MoveTargetLane: Sendable {
        case hidden
        case alwaysHidden
        case visible
    }

    struct ClickMenuBarItemResult: Sendable {
        let success: Bool
        let verification: String
    }

    nonisolated static func shouldFallbackToAXAfterHardwareAttempt(
        success: Bool,
        verificationSummary: String,
        isItemOnScreen: Bool
    ) -> Bool {
        guard isItemOnScreen else { return false }
        if success, verificationSummary.hasPrefix("verified") {
            return false
        }
        return true
    }

    struct StatusItemReactionSnapshot: Equatable, Sendable {
        let shownMenuPresent: Bool?
        let focusedWindowPresent: Bool?
        let windowCount: Int?
        let windowServerWindowCount: Int?
        let expanded: Bool?
        let selected: Bool?
    }
    private enum StatusItemReactionVerification: Sendable {
        case verified(String)
        case unavailable(String)
        case failed(String)

        var success: Bool {
            switch self {
            case .failed:
                false
            case .verified, .unavailable:
                true
            }
        }

        var summary: String {
            switch self {
            case .verified(let detail):
                "verified (\(detail))"
            case .unavailable(let detail):
                "unavailable (\(detail))"
            case .failed(let detail):
                "failed (\(detail))"
            }
        }
    }
    // MARK: - Actions
    nonisolated func clickMenuBarItem(for bundleID: String) -> Bool {
        clickMenuBarItem(bundleID: bundleID, menuExtraId: nil, fallbackCenter: nil)
    }
    /// Perform a "Virtual Click" on a specific menu bar item.
    nonisolated func clickMenuBarItem(bundleID: String, menuExtraId: String?, statusItemIndex: Int? = nil, fallbackCenter: CGPoint? = nil, isRightClick: Bool = false, preferHardwareFirst: Bool = false, allowImmediateFallbackCenter: Bool = true) -> Bool {
        clickMenuBarItemResult(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            fallbackCenter: fallbackCenter,
            isRightClick: isRightClick,
            preferHardwareFirst: preferHardwareFirst,
            allowImmediateFallbackCenter: allowImmediateFallbackCenter
        ).success
    }

    nonisolated func clickMenuBarItemResult(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int? = nil,
        fallbackCenter: CGPoint? = nil,
        isRightClick: Bool = false,
        preferHardwareFirst: Bool = false,
        allowImmediateFallbackCenter: Bool = true
    ) -> ClickMenuBarItemResult {
        let menuExtraIdString = menuExtraId ?? "nil"
        let statusItemIndexString = statusItemIndex.map(String.init) ?? "nil"
        logger.info("Attempting to click menu bar item for: \(bundleID) (menuExtraId: \(menuExtraIdString), statusItemIndex: \(statusItemIndexString), rightClick: \(isRightClick))")

        guard isTrusted else {
            logger.error("Accessibility permission not granted")
            return ClickMenuBarItemResult(success: false, verification: "not-run (accessibility permission missing)")
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            if let fallbackCenter = validatedRawSpatialFallbackCenter(
                bundleID: bundleID,
                fallbackCenter: fallbackCenter,
                allowImmediateFallbackCenter: allowImmediateFallbackCenter,
                context: "app not running"
            ) {
                logger.info("App missing; using spatial fallback click for \(bundleID)")
                let point = normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
                return ClickMenuBarItemResult(
                    success: simulateHardwareClick(at: point, isRightClick: isRightClick),
                    verification: "unavailable (app not running; spatial fallback)"
                )
            }
            return ClickMenuBarItemResult(success: false, verification: "not-run (app not running)")
        }

        return clickSystemWideItem(
            for: app.processIdentifier,
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            fallbackCenter: fallbackCenter,
            isRightClick: isRightClick,
            preferHardwareFirst: preferHardwareFirst,
            allowImmediateFallbackCenter: allowImmediateFallbackCenter
        )
    }

    // swiftlint:disable:next function_parameter_count
    private nonisolated func clickSystemWideItem(for targetPID: pid_t, bundleID: String, menuExtraId: String?, statusItemIndex: Int?, fallbackCenter: CGPoint?, isRightClick: Bool, preferHardwareFirst: Bool, allowImmediateFallbackCenter: Bool) -> ClickMenuBarItemResult {
        let appElement = AXUIElementCreateApplication(targetPID)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

        guard result == .success, let bar = extrasBar else {
            logger.debug("App \(targetPID) has no AXExtrasMenuBar (error \(result.rawValue))")
            Task { @MainActor in
                AccessibilityService.shared.markExtrasMenuBarUnavailable(bundleID: bundleID)
            }
            // If AX bar is unavailable, frame-based fallback usually fails too.
            // Use spatial fallback (from scanner coordinates) when available.
            if let fallbackCenter = validatedRawSpatialFallbackCenter(
                bundleID: bundleID,
                fallbackCenter: fallbackCenter,
                allowImmediateFallbackCenter: allowImmediateFallbackCenter,
                context: "AXExtrasMenuBar unavailable"
            ) {
                let point = normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
                return ClickMenuBarItemResult(
                    success: simulateHardwareClick(at: point, isRightClick: isRightClick),
                    verification: "unavailable (AXExtrasMenuBar unavailable; spatial fallback)"
                )
            }
            return ClickMenuBarItemResult(success: false, verification: "not-run (AXExtrasMenuBar unavailable)")
        }
        Task { @MainActor in
            AccessibilityService.shared.markExtrasMenuBarAvailable(bundleID: bundleID)
        }

        guard let barElement = safeAXUIElement(bar) else {
            return ClickMenuBarItemResult(success: false, verification: "not-run (invalid AXExtrasMenuBar element)")
        }

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            logger.debug("No items in app's Extras Menu Bar")
            return ClickMenuBarItemResult(
                success: hardwareClickAsFallback(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    fallbackCenter: fallbackCenter,
                    isRightClick: isRightClick,
                    allowImmediateFallbackCenter: allowImmediateFallbackCenter
                ),
                verification: "unavailable (no AXExtrasMenuBar children)"
            )
        }

        logger.info("Found \(items.count) status item(s) for PID \(targetPID)")

        let targetItem = resolvedTargetStatusItem(
            from: items,
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: fallbackCenter?.x
        )

        guard let item = targetItem else {
            logger.warning("Could not find target status item for click")
            return ClickMenuBarItemResult(
                success: hardwareClickAsFallback(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    fallbackCenter: fallbackCenter,
                    isRightClick: isRightClick,
                    allowImmediateFallbackCenter: allowImmediateFallbackCenter
                ),
                verification: "unavailable (target status item unresolved)"
            )
        }

        let reactionBaseline = captureStatusItemReactionSnapshot(item: item, appElement: appElement)
        let itemOnScreen = isElementOnScreen(item)

        if preferHardwareFirst {
            logger.info("Using hardware-first click path for \(bundleID)")
            let hardwareResult = verifiedClickResult(
                dispatched: hardwareClickAsFallback(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    fallbackCenter: fallbackCenter,
                    isRightClick: isRightClick,
                    allowImmediateFallbackCenter: allowImmediateFallbackCenter
                ),
                item: item,
                appElement: appElement,
                baseline: reactionBaseline
            )
            if !Self.shouldFallbackToAXAfterHardwareAttempt(
                success: hardwareResult.success,
                verificationSummary: hardwareResult.verification,
                isItemOnScreen: itemOnScreen
            ) {
                return hardwareResult
            }
            logger.info(
                "Hardware-first click path verification=\(hardwareResult.verification, privacy: .public); falling back to AX actions"
            )
            if !itemOnScreen {
                return hardwareResult
            }
            logger.info("Hardware-first click did not resolve target; falling back to AX actions")
        }

        // Verify item is on-screen before AXPress. After SaneBar reveals hidden
        // items, macOS re-layouts asynchronously. AXPress returns .success on
        // off-screen elements without opening any menu — this is why left-click
        // (AXPress path) fails while right-click (hardware path) works (#102).
        // Hardware click already has its own on-screen polling via
        // getMenuBarIconFrameOnScreen(); AXPress was missing this gate.
        if !itemOnScreen {
            logger.info("Target item off-screen; skipping AXPress, using hardware click")
            return verifiedClickResult(
                dispatched: hardwareClickAsFallback(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    fallbackCenter: fallbackCenter,
                    isRightClick: isRightClick,
                    allowImmediateFallbackCenter: allowImmediateFallbackCenter
                ),
                item: item,
                appElement: appElement,
                baseline: reactionBaseline
            )
        }

        // Try AX first
        if performSmartPress(on: item, isRightClick: isRightClick) {
            return verifiedClickResult(
                dispatched: true,
                item: item,
                appElement: appElement,
                baseline: reactionBaseline
            )
        }

        // Fallback to hardware event
        return verifiedClickResult(
            dispatched: hardwareClickAsFallback(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                fallbackCenter: fallbackCenter,
                isRightClick: isRightClick,
                allowImmediateFallbackCenter: allowImmediateFallbackCenter
            ),
            item: item,
            appElement: appElement,
            baseline: reactionBaseline
        )
    }

    private nonisolated func verifiedClickResult(
        dispatched: Bool,
        item: AXUIElement,
        appElement: AXUIElement,
        baseline: StatusItemReactionSnapshot
    ) -> ClickMenuBarItemResult {
        guard dispatched else {
            return ClickMenuBarItemResult(success: false, verification: "failed (dispatch failed)")
        }

        let verification = verifyStatusItemReaction(
            item: item,
            appElement: appElement,
            baseline: baseline
        )
        return ClickMenuBarItemResult(
            success: verification.success,
            verification: verification.summary
        )
    }

    // swiftlint:disable:next function_parameter_count
    private nonisolated func hardwareClickAsFallback(bundleID: String, menuExtraId: String?, statusItemIndex: Int?, fallbackCenter: CGPoint?, isRightClick: Bool, allowImmediateFallbackCenter: Bool) -> Bool {
        logger.info("Performing hardware click fallback for \(bundleID)")
        // Fast path: if caller already provided an on-screen target center,
        // click there immediately instead of AX frame polling.
        if allowImmediateFallbackCenter,
           let fallbackCenter,
           isAccessibilityPointOnAnyScreen(fallbackCenter) {
            logger.info("Hardware click fallback: using immediate spatial center for \(bundleID)")
            let point = normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
            return simulateHardwareClick(at: point, isRightClick: isRightClick)
        }

        if let frame = getMenuBarIconFrameOnScreen(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: fallbackCenter?.x,
            attempts: 10,
            interval: 0.03
        ) {
            let center = normalizedCGEventPoint(fromAccessibilityPoint: CGPoint(x: frame.midX, y: frame.midY))
            return simulateHardwareClick(at: center, isRightClick: isRightClick)
        }

        if let fallbackCenter = validatedRawSpatialFallbackCenter(
            bundleID: bundleID,
            fallbackCenter: fallbackCenter,
            allowImmediateFallbackCenter: allowImmediateFallbackCenter,
            context: "frame polling failed"
        ) {
            logger.info("Hardware click fallback: using spatial center fallback for \(bundleID)")
            let point = normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
            return simulateHardwareClick(at: point, isRightClick: isRightClick)
        }

        logger.error("Hardware click failed: could not find icon frame")
        return false
    }

    private nonisolated func validatedRawSpatialFallbackCenter(
        bundleID: String,
        fallbackCenter: CGPoint?,
        allowImmediateFallbackCenter: Bool,
        context: StaticString
    ) -> CGPoint? {
        guard let fallbackCenter else { return nil }
        let isOnScreen = isAccessibilityPointOnAnyScreen(fallbackCenter)

        guard SearchService.shouldUseRawSpatialFallback(
            allowImmediateFallbackCenter: allowImmediateFallbackCenter,
            isPointOnScreen: isOnScreen
        ) else {
            if !isOnScreen {
                logger.warning("Skipping raw spatial fallback for \(bundleID): point is off-screen (\(context))")
            } else {
                logger.info("Skipping stale raw spatial fallback for \(bundleID) during reveal/browse flow (\(context))")
            }
            return nil
        }

        return fallbackCenter
    }

    private nonisolated func isAccessibilityPointOnAnyScreen(_ point: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private nonisolated func verifyStatusItemReaction(
        item: AXUIElement,
        appElement: AXUIElement,
        baseline: StatusItemReactionSnapshot,
        attempts: Int = 14,
        interval: TimeInterval = 0.08
    ) -> StatusItemReactionVerification {
        var lastSnapshot = baseline

        for _ in 0 ..< attempts {
            Thread.sleep(forTimeInterval: interval)
            let currentSnapshot = captureStatusItemReactionSnapshot(item: item, appElement: appElement)
            lastSnapshot = currentSnapshot
            if let reaction = Self.observableReactionDescription(before: baseline, after: currentSnapshot) {
                return .verified(reaction)
            }
        }

        if Self.hasComparableReactionSignals(before: baseline, after: lastSnapshot) {
            return .failed("no observable menu/panel reaction")
        }

        return .unavailable("no comparable AX reaction signals")
    }

    // MARK: - On-Screen Verification

    /// Check whether an AX element's position is on any connected screen.
    /// Hidden icons are pushed far off-screen (x ≈ -3000+). AXPress returns
    /// .success on these elements without opening any menu — this gate ensures
    /// we only attempt AXPress on genuinely visible items.
    private nonisolated func isElementOnScreen(_ element: AXUIElement) -> Bool {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let posValue = positionValue,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              let axPosValue = safeAXValue(posValue)
        else { return false }

        var origin = CGPoint.zero
        guard AXValueGetValue(axPosValue, .cgPoint, &origin) else { return false }

        var sizeValue: CFTypeRef?
        var size = CGSize(width: 22, height: 22)
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let sVal = sizeValue,
           CFGetTypeID(sVal) == AXValueGetTypeID(),
           let axSizeVal = safeAXValue(sVal) {
            var s = CGSize.zero
            if AXValueGetValue(axSizeVal, .cgSize, &s) {
                size = CGSize(width: max(1, s.width), height: max(1, s.height))
            }
        }

        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(center) }
    }

    // MARK: - Interaction

    private nonisolated func performSmartPress(on element: AXUIElement, isRightClick: Bool) -> Bool {
        if isRightClick {
            if performShowMenu(on: element) { return true }
            if performPress(on: element) {
                logger.info("AXShowMenu unavailable; falling back to AXPress for right-click")
                return true
            }

            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let childItems = children as? [AXUIElement] {
                for child in childItems {
                    if performShowMenu(on: child) { return true }
                    if performPress(on: child) {
                        logger.info("AXShowMenu unavailable on child; falling back to AXPress for right-click")
                        return true
                    }
                }
            }
            return false
        }

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

    private nonisolated func performShowMenu(on element: AXUIElement) -> Bool {
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

    private nonisolated func performPress(on element: AXUIElement) -> Bool {
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

    private nonisolated func simulateHardwareClick(at point: CGPoint, isRightClick: Bool) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let restorePoint: CGPoint? = isRightClick ? nil : currentCGEventMousePoint()

        let mouseDownType: CGEventType = isRightClick ? .rightMouseDown : .leftMouseDown
        let mouseUpType: CGEventType = isRightClick ? .rightMouseUp : .leftMouseUp
        let mouseButton: CGMouseButton = isRightClick ? .right : .left

        guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: mouseDownType, mouseCursorPosition: point, mouseButton: mouseButton),
              let mouseUp = CGEvent(mouseEventSource: source, mouseType: mouseUpType, mouseCursorPosition: point, mouseButton: mouseButton)
        else {
            return false
        }

        mouseDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        mouseUp.post(tap: .cgSessionEventTap)
        if let restorePoint,
           let restoreEvent = CGEvent(
               mouseEventSource: source,
               mouseType: .mouseMoved,
               mouseCursorPosition: restorePoint,
               mouseButton: .left
           ) {
            restoreEvent.post(tap: .cgSessionEventTap)
        }

        logger.info("Simulated hardware click at \(point.x), \(point.y)")
        return true
    }

    private nonisolated func currentCGEventMousePoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? location.y
        return CGPoint(x: location.x, y: globalMaxY - location.y)
    }

    private nonisolated func normalizedCGEventPoint(fromAccessibilityPoint point: CGPoint) -> CGPoint {
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        let rawY = point.y
        let anchorY: CGFloat = 15
        let clampedY = Self.normalizedEventY(rawY: rawY, globalMaxY: globalMaxY, anchorY: anchorY)
        return CGPoint(x: point.x, y: clampedY)
    }

    nonisolated static func cgEventScreenFrame(
        fromAppKitScreenFrame screenFrame: CGRect,
        globalMaxY: CGFloat,
        inset: CGFloat = 2
    ) -> CGRect {
        let cgMinY = globalMaxY - screenFrame.maxY
        return CGRect(
            x: screenFrame.minX,
            y: cgMinY,
            width: screenFrame.width,
            height: screenFrame.height
        ).insetBy(dx: -inset, dy: -inset)
    }

    nonisolated static func isCGEventPointOnAnyScreen(
        _ point: CGPoint,
        screenFrames: [CGRect],
        globalMaxY: CGFloat,
        inset: CGFloat = 2
    ) -> Bool {
        screenFrames.contains {
            cgEventScreenFrame(fromAppKitScreenFrame: $0, globalMaxY: globalMaxY, inset: inset)
                .contains(point)
        }
    }

    nonisolated static func normalizedEventY(rawY: CGFloat, globalMaxY: CGFloat, anchorY: CGFloat) -> CGFloat {
        let flippedY = globalMaxY - rawY

        // AX values may arrive in either AppKit-unflipped or CoreGraphics-flipped space.
        // Use the menu bar anchor to pick whichever candidate is closer to reality.
        let chosenY = abs(rawY - anchorY) <= abs(flippedY - anchorY) ? rawY : flippedY

        let minY: CGFloat = 1
        let maxY = max(minY, globalMaxY - 1)
        return min(max(chosenY, minY), maxY)
    }

    /// Shared zone-edge verification used after cmd-drag moves.
    /// Uses icon midpoint (same basis as UI zone classification) to avoid
    /// false negatives when macOS lands just to the right of the separator.
    nonisolated static func frameIsInTargetZone(afterFrame: CGRect, separatorX: CGFloat, toHidden: Bool, margin: CGFloat = 6) -> Bool {
        let midpointX = afterFrame.midX
        let threshold = separatorX - margin
        return toHidden ? midpointX < threshold : midpointX >= threshold
    }

    /// Detect direction mismatches for post-drag verification without penalizing
    /// idempotent moves where the icon already started on the target side.
    /// This avoids false negatives when a visible->visible reorder shifts left
    /// while still remaining in the visible zone.
    nonisolated static func hasDirectionMismatch(
        beforeFrame: CGRect,
        afterFrame: CGRect,
        separatorX: CGFloat,
        toHidden: Bool,
        margin: CGFloat = 6,
        tolerance: CGFloat = 2
    ) -> Bool {
        let startedInTargetZone = frameIsInTargetZone(
            afterFrame: beforeFrame,
            separatorX: separatorX,
            toHidden: toHidden,
            margin: margin
        )
        if startedInTargetZone {
            return false
        }

        let deltaX = afterFrame.midX - beforeFrame.midX
        if toHidden {
            return deltaX > tolerance
        }
        return deltaX < -tolerance
    }

    /// Shared target X selection for Cmd+drag moves.
    /// Each lane uses its own insertion policy so we do not conflate regular
    /// hidden drags with always-hidden drags.
    nonisolated static func moveTargetX(
        targetLane: MoveTargetLane,
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        let moveOffset = max(30, iconWidth + 20)

        switch targetLane {
        case .hidden:
            // No clamp = direct hidden move.
            let farHiddenX = separatorX - max(80, iconWidth + 60)
            guard let ahBoundary = visibleBoundaryX else {
                // Wide text-style extras can stop in the regular hidden lane unless we
                // drag much deeper into the always-hidden section.
                let wideAlwaysHiddenThreshold: CGFloat = 56
                if iconWidth >= wideAlwaysHiddenThreshold {
                    let wideAlwaysHiddenOffset = max(180, (iconWidth * 3) + 30)
                    return separatorX - wideAlwaysHiddenOffset
                }
                return farHiddenX
            }

            // Hidden lane is between AH separator right edge and main separator left edge.
            // Keep enough room from separator so midpoint verification is reliable.
            let minRegularHiddenX = ahBoundary + 2
            let separatorSafety = max(20, (iconWidth * 0.5) + 12)
            let maxRegularHiddenX = separatorX - separatorSafety

            // If the lane is too narrow, prioritize landing left of separator.
            guard minRegularHiddenX <= maxRegularHiddenX else {
                return maxRegularHiddenX
            }
            // Bias toward the main separator side of the hidden lane so a
            // subsequent re-hide transition doesn't nudge the icon into the
            // always-hidden section.
            let rightBiasInset = max(6, min(20, iconWidth * 0.45))
            let preferredRegularHiddenX = maxRegularHiddenX - rightBiasInset
            let boundedPreferredX = min(max(preferredRegularHiddenX, minRegularHiddenX), maxRegularHiddenX)

            // Keep the old far-hidden fallback available for extremely wide
            // icons where right-bias would under-move.
            return max(boundedPreferredX, min(max(farHiddenX, minRegularHiddenX), maxRegularHiddenX))

        case .alwaysHidden:
            // Always-hidden insertion should stay close to the AH separator instead
            // of using the deeper generic hidden target, which can overshoot across
            // sibling icons and fail exact-identity verification.
            return separatorX - moveOffset

        case .visible:
            if let boundary = visibleBoundaryX {
            // Visible moves usually want a short hop right of the separator.
            // On tight notch layouts there may be no room between the separator
            // and the SaneBar icon, so hugging `boundary - 2` leaves wide icons
            // with their midpoint still hidden. In that case intentionally
            // overlap a little into the SaneBar icon so macOS inserts the icon
            // into the visible zone and pushes SaneBar right.
            let preferredVisibleX = max(separatorX + 1, separatorX + moveOffset)
            let inlineVisibleLimit = boundary - 2
            if preferredVisibleX <= inlineVisibleLimit {
                return preferredVisibleX
            }

            let insertionOverlap = max(6, min(18, iconWidth * 0.35))
            return max(separatorX + 1, boundary + insertionOverlap)
            }

            return separatorX + 1
        }
    }

    nonisolated static func moveTargetX(
        toHidden: Bool,
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        moveTargetX(
            targetLane: toHidden ? .hidden : .visible,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )
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
        originalMouseLocation: CGPoint
    ) -> Bool {
        guard isTrusted else {
            logger.error("🔧 Accessibility permission not granted")
            return false
        }

        let targetX = Self.moveTargetX(
            toHidden: toHidden,
            iconWidth: iconFrame.size.width,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        let rawFromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        let rawToPoint = CGPoint(x: targetX, y: iconFrame.midY)
        let fromPoint = normalizedCGEventPoint(fromAccessibilityPoint: rawFromPoint)
        let toPoint = normalizedCGEventPoint(fromAccessibilityPoint: rawToPoint)
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
        originalMouseLocation: CGPoint
    ) -> Bool {
        guard isTrusted else {
            logger.error("🔧 Accessibility permission not granted")
            return false
        }

        guard let sourceFrame = getMenuBarIconFrameOnScreen(
            bundleID: sourceBundleID,
            menuExtraId: sourceMenuExtraID,
            statusItemIndex: sourceStatusItemIndex
        ) else {
            logger.error("🔧 reorderMenuBarIcon: source frame unavailable")
            return false
        }

        guard let targetFrame = getMenuBarIconFrameOnScreen(
            bundleID: targetBundleID,
            menuExtraId: targetMenuExtraID,
            statusItemIndex: targetStatusItemIndex
        ) else {
            logger.error("🔧 reorderMenuBarIcon: target frame unavailable")
            return false
        }

        let spacing = max(8, targetFrame.width * 0.25)
        let targetX = placeAfterTarget ? (targetFrame.maxX + spacing) : (targetFrame.minX - spacing)
        let rawFromPoint = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let rawToPoint = CGPoint(x: targetX, y: targetFrame.midY)
        let fromPoint = normalizedCGEventPoint(fromAccessibilityPoint: rawFromPoint)
        let toPoint = normalizedCGEventPoint(fromAccessibilityPoint: rawToPoint)
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
        targetLane: MoveTargetLane? = nil,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat? = nil,
        eventTap: CGEventTapLocation = .cghidEventTap,
        originalMouseLocation: CGPoint
    ) -> Bool {
        let tapName = eventTap == .cgSessionEventTap ? "session" : "hid"
        let resolvedTargetLane = targetLane ?? (toHidden ? .hidden : .visible)
        logger.info("🔧 moveMenuBarIcon: bundleID=\(bundleID, privacy: .private), menuExtraId=\(menuExtraId ?? "nil", privacy: .private), statusItemIndex=\(statusItemIndex ?? -1, privacy: .public), toHidden=\(toHidden, privacy: .public), targetLane=\(String(describing: resolvedTargetLane), privacy: .public), separatorX=\(separatorX, privacy: .public), visibleBoundaryX=\(visibleBoundaryX ?? -1, privacy: .public), tap=\(tapName, privacy: .public)")

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
            guard let frame = getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            ) else {
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
        let targetX = Self.moveTargetX(
            targetLane: resolvedTargetLane,
            iconWidth: iconFrame.size.width,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )

        logger.info("🔧 Target X: \(targetX, privacy: .public)")

        // AX and CGEvent Y-axis orientation can differ by OS/build.
        // Normalize both points so drag coordinates stay anchored to the menu bar.
        let rawFromPoint = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
        let rawToPoint = CGPoint(x: targetX, y: iconFrame.midY)
        let fromPoint = normalizedCGEventPoint(fromAccessibilityPoint: rawFromPoint)
        let toPoint = normalizedCGEventPoint(fromAccessibilityPoint: rawToPoint)

        if abs(fromPoint.y - rawFromPoint.y) > 2 || abs(toPoint.y - rawToPoint.y) > 2 {
            logger.debug(
                "🔧 Normalized drag Y from raw (\(rawFromPoint.y, privacy: .public)->\(fromPoint.y, privacy: .public), \(rawToPoint.y, privacy: .public)->\(toPoint.y, privacy: .public))"
            )
        }
        logger.info("🔧 CGEvent drag from (\(fromPoint.x, privacy: .public), \(fromPoint.y, privacy: .public)) to (\(toPoint.x, privacy: .public), \(toPoint.y, privacy: .public))")

        let didPostEvents = performCmdDrag(from: fromPoint, to: toPoint, eventTap: eventTap, restoreTo: originalMouseLocation)
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
            let currentFrame = getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            )
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

        // Verify icon landed in the expected zone using midpoint-based logic.
        // This aligns with SearchService zone classification and prevents
        // false negatives when visible moves land close to the separator.
        var movedToExpectedSide = Self.frameIsInTargetZone(
            afterFrame: afterFrame,
            separatorX: separatorX,
            toHidden: toHidden
        )

        // Guard against stale-boundary false positives/negatives by ensuring motion
        // direction matches intent before accepting the separator-side check.
        let directionMismatch = Self.hasDirectionMismatch(
            beforeFrame: iconFrame,
            afterFrame: afterFrame,
            separatorX: separatorX,
            toHidden: toHidden
        )
        if directionMismatch, toHidden {
            let deltaX = afterFrame.midX - iconFrame.midX
            logger.warning("🔧 Move direction mismatch: expected leftward hidden move, deltaX=\(deltaX, privacy: .public)")
            movedToExpectedSide = false
        } else if directionMismatch, !toHidden {
            let deltaX = afterFrame.midX - iconFrame.midX
            logger.warning("🔧 Move direction mismatch: expected rightward visible move, deltaX=\(deltaX, privacy: .public)")
            movedToExpectedSide = false
        }

        if !movedToExpectedSide {
            logger.error("🔧 Move verification failed: expected toHidden=\(toHidden, privacy: .public), separatorX=\(separatorX, privacy: .public), afterX=\(afterFrame.origin.x, privacy: .public), afterMidX=\(afterFrame.midX, privacy: .public)")
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
        guard let frame = getMenuBarIconFrame(
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
                logger.warning("🔧 performCmdDrag(\(tapName, privacy: .public)): no screens available — aborting")
                semaphore.signal()
                return
            }
            let globalMaxY = screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
            let screenFrames = screens.map(\.frame)
            let fromOnScreen = Self.isCGEventPointOnAnyScreen(
                from,
                screenFrames: screenFrames,
                globalMaxY: globalMaxY
            )
            let targetOnScreen = Self.isCGEventPointOnAnyScreen(
                to,
                screenFrames: screenFrames,
                globalMaxY: globalMaxY
            )
            if !fromOnScreen {
                logger.warning("🔧 performCmdDrag(\(tapName, privacy: .public)): from point (\(from.x), \(from.y)) is off-screen — aborting")
                semaphore.signal()
                return
            }
            if !targetOnScreen {
                logger.warning("🔧 performCmdDrag(\(tapName, privacy: .public)): target point (\(to.x), \(to.y)) is off-screen — aborting")
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
                Thread.sleep(forTimeInterval: 0.08) // Let cursor settle
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
            mouseDown.post(tap: eventTap)
            Thread.sleep(forTimeInterval: 0.09) // Hold before dragging (human-like)

            // 4. Multi-step drag with human-like timing
            //    20 steps × 18ms = ~360ms total drag (vs old: 6 × 5ms = 30ms)
            let steps = 20
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
                    Thread.sleep(forTimeInterval: 0.018)
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
            mouseUp.post(tap: eventTap)
            Thread.sleep(forTimeInterval: 0.18) // Let the 'drop' settle

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
                AccessibilityService.shared.invalidateMenuBarItemCache()
            }

            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            logger.error("🔧 performCmdDrag(\(tapName, privacy: .public)): semaphore timed out — forcing mouseUp to prevent stuck cursor")
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
    }
}

// swiftlint:enable file_length
