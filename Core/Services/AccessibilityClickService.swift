import AppKit
import ApplicationServices
import os.log

private let accessibilityClickLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityClickService")

final class AccessibilityClickService {
    private unowned let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    struct ClickMenuBarItemResult {
        let success: Bool
        let verification: String
    }

    nonisolated static func shouldFallbackToAXAfterHardwareAttempt(
        success: Bool,
        verificationSummary: String,
        isItemOnScreen: Bool,
        isRightClick: Bool
    ) -> Bool {
        guard isItemOnScreen else { return false }
        if success, verificationSummary.hasPrefix("verified") {
            return false
        }
        if success, isRightClick {
            return false
        }
        return true
    }

    struct StatusItemReactionSnapshot: Equatable {
        let shownMenuPresent: Bool?
        let focusedWindowPresent: Bool?
        let windowCount: Int?
        let windowServerWindowCount: Int?
        let expanded: Bool?
        let selected: Bool?
    }

    private enum StatusItemReactionVerification {
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
            case let .verified(detail):
                "verified (\(detail))"
            case let .unavailable(detail):
                "unavailable (\(detail))"
            case let .failed(detail):
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
        accessibilityClickLogger.info("Attempting to click menu bar item for: \(bundleID) (menuExtraId: \(menuExtraIdString), statusItemIndex: \(statusItemIndexString), rightClick: \(isRightClick))")

        guard accessibilityService.isTrusted else {
            accessibilityClickLogger.error("Accessibility permission not granted")
            return ClickMenuBarItemResult(success: false, verification: "not-run (accessibility permission missing)")
        }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            accessibilityClickLogger.warning("App not running: \(bundleID)")
            if let fallbackCenter = validatedRawSpatialFallbackCenter(
                bundleID: bundleID,
                fallbackCenter: fallbackCenter,
                allowImmediateFallbackCenter: allowImmediateFallbackCenter,
                context: "app not running"
            ) {
                accessibilityClickLogger.info("App missing; using spatial fallback click for \(bundleID)")
                let point = AccessibilityInteractionPolicy.normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
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
        applyInteractionMessagingTimeout(to: appElement)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

        guard result == .success, let bar = extrasBar else {
            accessibilityClickLogger.debug("App \(targetPID) has no AXExtrasMenuBar (error \(result.rawValue))")
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
                let point = AccessibilityInteractionPolicy.normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
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
        applyInteractionMessagingTimeout(to: barElement)

        let childResult = AccessibilityBoundedAXChildFetch.children(
            of: barElement,
            maxCount: AccessibilityMenuExtraService.maxCollectedMenuExtraItems
        )
        if childResult.truncated {
            accessibilityClickLogger.warning("Refusing partial AXExtrasMenuBar child list for click; using spatial fallback when available")
            return ClickMenuBarItemResult(
                success: hardwareClickAsFallback(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    fallbackCenter: fallbackCenter,
                    isRightClick: isRightClick,
                    allowImmediateFallbackCenter: allowImmediateFallbackCenter
                ),
                verification: "unavailable (AXExtrasMenuBar children truncated; spatial fallback)"
            )
        }
        let items = childResult.children
        guard !items.isEmpty else {
            accessibilityClickLogger.debug("No items in app's Extras Menu Bar")
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

        accessibilityClickLogger.info("Found \(items.count) status item(s) for PID \(targetPID)")

        let targetItem = AccessibilityMenuExtraService.resolvedTargetStatusItem(
            from: items,
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: fallbackCenter?.x
        )

        guard let item = targetItem else {
            accessibilityClickLogger.warning("Could not find target status item for click")
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

        applyInteractionMessagingTimeout(to: item)

        let reactionBaseline = AccessibilityMenuExtraService.captureStatusItemReactionSnapshot(item: item, appElement: appElement)
        let itemOnScreen = isElementOnScreen(item)

        if preferHardwareFirst {
            accessibilityClickLogger.info("Using hardware-first click path for \(bundleID)")
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
                baseline: reactionBaseline,
                acceptDispatchWithoutObservableReaction: isRightClick && itemOnScreen
            )
            if !AccessibilityInteractionPolicy.shouldFallbackToAXAfterHardwareAttempt(
                success: hardwareResult.success,
                verificationSummary: hardwareResult.verification,
                isItemOnScreen: itemOnScreen,
                isRightClick: isRightClick
            ) {
                return hardwareResult
            }
            accessibilityClickLogger.info(
                "Hardware-first click path verification=\(hardwareResult.verification, privacy: .public); falling back to AX actions"
            )
            if !itemOnScreen {
                return hardwareResult
            }
            accessibilityClickLogger.info("Hardware-first click did not resolve target; falling back to AX actions")
        }

        // Verify item is on-screen before AXPress. After SaneBar reveals hidden
        // items, macOS re-layouts asynchronously. AXPress returns .success on
        // off-screen elements without opening any menu — this is why left-click
        // (AXPress path) fails while right-click (hardware path) works (#102).
        // Hardware click already has its own on-screen polling via
        // AccessibilityMenuExtraFrameResolver.getMenuBarIconFrameOnScreen(); AXPress was missing this gate.
        if !itemOnScreen {
            accessibilityClickLogger.info("Target item off-screen; skipping AXPress, using hardware click")
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
        baseline: StatusItemReactionSnapshot,
        acceptDispatchWithoutObservableReaction: Bool = false
    ) -> ClickMenuBarItemResult {
        guard dispatched else {
            return ClickMenuBarItemResult(success: false, verification: "failed (dispatch failed)")
        }

        let verification = verifyStatusItemReaction(
            item: item,
            appElement: appElement,
            baseline: baseline
        )
        if acceptDispatchWithoutObservableReaction, !verification.summary.hasPrefix("verified") {
            return ClickMenuBarItemResult(
                success: true,
                verification: "verified (rightClickDispatch; \(verification.summary))"
            )
        }

        return ClickMenuBarItemResult(
            success: verification.success,
            verification: verification.summary
        )
    }

    private nonisolated func applyInteractionMessagingTimeout(to element: AXUIElement) {
        // Keep browse activation responsive when a status item blocks AX reads after re-layout.
        AXUIElementSetMessagingTimeout(element, 0.18)
    }

    // swiftlint:disable:next function_parameter_count
    private nonisolated func hardwareClickAsFallback(bundleID: String, menuExtraId: String?, statusItemIndex: Int?, fallbackCenter: CGPoint?, isRightClick: Bool, allowImmediateFallbackCenter: Bool) -> Bool {
        accessibilityClickLogger.info("Performing hardware click fallback for \(bundleID)")
        // Fast path: if caller already provided an on-screen target center,
        // click there immediately instead of AX frame polling.
        if allowImmediateFallbackCenter,
           let fallbackCenter,
           AccessibilityInteractionPolicy.isAccessibilityPointOnAnyScreen(fallbackCenter) {
            accessibilityClickLogger.info("Hardware click fallback: using immediate spatial center for \(bundleID)")
            let point = AccessibilityInteractionPolicy.normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
            return simulateHardwareClick(at: point, isRightClick: isRightClick)
        }

        if let frame = AccessibilityMenuExtraFrameResolver.getMenuBarIconFrameOnScreen(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: fallbackCenter?.x,
            attempts: 10,
            interval: 0.03
        ) {
            let center = AccessibilityInteractionPolicy.normalizedCGEventPoint(fromAccessibilityPoint: CGPoint(x: frame.midX, y: frame.midY))
            return simulateHardwareClick(at: center, isRightClick: isRightClick)
        }

        if let fallbackCenter = validatedRawSpatialFallbackCenter(
            bundleID: bundleID,
            fallbackCenter: fallbackCenter,
            allowImmediateFallbackCenter: allowImmediateFallbackCenter,
            context: "frame polling failed"
        ) {
            accessibilityClickLogger.info("Hardware click fallback: using spatial center fallback for \(bundleID)")
            let point = AccessibilityInteractionPolicy.normalizedCGEventPoint(fromAccessibilityPoint: fallbackCenter)
            return simulateHardwareClick(at: point, isRightClick: isRightClick)
        }

        accessibilityClickLogger.error("Hardware click failed: could not find icon frame")
        return false
    }

    private nonisolated func validatedRawSpatialFallbackCenter(
        bundleID: String,
        fallbackCenter: CGPoint?,
        allowImmediateFallbackCenter: Bool,
        context: StaticString
    ) -> CGPoint? {
        guard let fallbackCenter else { return nil }
        let isOnScreen = AccessibilityInteractionPolicy.isAccessibilityPointOnAnyScreen(fallbackCenter)

        guard SearchServiceSupport.shouldUseRawSpatialFallback(
            allowImmediateFallbackCenter: allowImmediateFallbackCenter,
            isPointOnScreen: isOnScreen
        ) else {
            if !isOnScreen {
                accessibilityClickLogger.warning("Skipping raw spatial fallback for \(bundleID): point is off-screen (\(context))")
            } else {
                accessibilityClickLogger.info("Skipping stale raw spatial fallback for \(bundleID) during reveal/browse flow (\(context))")
            }
            return nil
        }

        return fallbackCenter
    }

    private nonisolated func verifyStatusItemReaction(
        item: AXUIElement,
        appElement: AXUIElement,
        baseline: StatusItemReactionSnapshot,
        attempts: Int = 14,
        interval: TimeInterval = 0.08
    ) -> StatusItemReactionVerification {
        var lastSnapshot = baseline

        if baseline.windowServerWindowCount != nil {
            Thread.sleep(forTimeInterval: interval)
            let windowServerSnapshot = StatusItemReactionSnapshot(
                shownMenuPresent: nil,
                focusedWindowPresent: nil,
                windowCount: nil,
                windowServerWindowCount: AccessibilityMenuExtraService.appWindowServerCount(appElement),
                expanded: nil,
                selected: nil
            )
            if let reaction = AccessibilityMenuExtraService.observableReactionDescription(before: baseline, after: windowServerSnapshot) {
                return .verified(reaction)
            }
        }

        for _ in 0 ..< attempts {
            Thread.sleep(forTimeInterval: interval)
            let currentSnapshot = AccessibilityMenuExtraService.captureStatusItemReactionSnapshot(
                item: item,
                appElement: appElement,
                includeWindowServerWindowCount: false
            )
            lastSnapshot = currentSnapshot
            if let reaction = AccessibilityMenuExtraService.observableReactionDescription(before: baseline, after: currentSnapshot) {
                return .verified(reaction)
            }
        }

        if AccessibilityMenuExtraService.hasComparableReactionSignals(before: baseline, after: lastSnapshot) {
            return .failed("no observable menu/panel reaction")
        }

        if baseline.windowServerWindowCount != nil {
            let finalSnapshot = AccessibilityMenuExtraService.captureStatusItemReactionSnapshot(item: item, appElement: appElement)
            if let reaction = AccessibilityMenuExtraService.observableReactionDescription(before: baseline, after: finalSnapshot) {
                return .verified(reaction)
            }
            if AccessibilityMenuExtraService.hasComparableReactionSignals(before: baseline, after: finalSnapshot) {
                return .failed("no observable menu/panel reaction")
            }
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
        return AccessibilityInteractionPolicy.isAccessibilityPointOnAnyScreen(
            center,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }

    // MARK: - Interaction

    private nonisolated func performSmartPress(on element: AXUIElement, isRightClick: Bool) -> Bool {
        if isRightClick {
            if performShowMenu(on: element) { return true }
            if performPress(on: element) {
                accessibilityClickLogger.info("AXShowMenu unavailable; falling back to AXPress for right-click")
                return true
            }

            let childItems = AccessibilityBoundedAXChildFetch.children(of: element, maxCount: 16).children
            for child in childItems {
                if performShowMenu(on: child) { return true }
                if performPress(on: child) {
                    accessibilityClickLogger.info("AXShowMenu unavailable on child; falling back to AXPress for right-click")
                    return true
                }
            }
            return false
        }

        // Some apps (Antinote, BetterDisplay) have nested clickable elements.
        // We look for any child that supports AXPress if the top-level doesn't.
        if performPress(on: element) { return true }

        let childItems = AccessibilityBoundedAXChildFetch.children(of: element, maxCount: 16).children
        for child in childItems where performPress(on: child) {
            return true
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
                accessibilityClickLogger.info("AXShowMenu successful")
                return true
            }
        }
        return false
    }

    private nonisolated func performPress(on element: AXUIElement) -> Bool {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        if error == .success {
            accessibilityClickLogger.info("AXPress successful")
            return true
        }

        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success,
           let names = actionNames as? [String],
           names.contains("AXShowMenu") {
            let menuError = AXUIElementPerformAction(element, "AXShowMenu" as CFString)
            if menuError == .success {
                accessibilityClickLogger.info("AXShowMenu successful")
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

        accessibilityClickLogger.debug("Simulated hardware click at \(point.x), \(point.y)")
        return true
    }

    private nonisolated func currentCGEventMousePoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? location.y
        return CGPoint(x: location.x, y: globalMaxY - location.y)
    }

}
