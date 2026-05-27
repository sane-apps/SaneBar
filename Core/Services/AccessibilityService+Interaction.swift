import AppKit
import ApplicationServices

extension AccessibilityService {
    typealias MoveTargetLane = AccessibilityInteractionPolicy.MoveTargetLane
    typealias ClickMenuBarItemResult = AccessibilityClickService.ClickMenuBarItemResult
    typealias StatusItemReactionSnapshot = AccessibilityClickService.StatusItemReactionSnapshot

    private nonisolated var clickService: AccessibilityClickService {
        AccessibilityClickService(accessibilityService: self)
    }

    private nonisolated var dragService: AccessibilityMenuBarDragService {
        AccessibilityMenuBarDragService(accessibilityService: self)
    }

    nonisolated static func shouldFallbackToAXAfterHardwareAttempt(
        success: Bool,
        verificationSummary: String,
        isItemOnScreen: Bool,
        isRightClick: Bool
    ) -> Bool {
        AccessibilityInteractionPolicy.shouldFallbackToAXAfterHardwareAttempt(
            success: success,
            verificationSummary: verificationSummary,
            isItemOnScreen: isItemOnScreen,
            isRightClick: isRightClick
        )
    }

    nonisolated func clickMenuBarItem(for bundleID: String) -> Bool {
        clickService.clickMenuBarItem(for: bundleID)
    }

    nonisolated func clickMenuBarItem(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int? = nil,
        fallbackCenter: CGPoint? = nil,
        isRightClick: Bool = false,
        preferHardwareFirst: Bool = false,
        allowImmediateFallbackCenter: Bool = true
    ) -> Bool {
        clickService.clickMenuBarItem(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            fallbackCenter: fallbackCenter,
            isRightClick: isRightClick,
            preferHardwareFirst: preferHardwareFirst,
            allowImmediateFallbackCenter: allowImmediateFallbackCenter
        )
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
        clickService.clickMenuBarItemResult(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            fallbackCenter: fallbackCenter,
            isRightClick: isRightClick,
            preferHardwareFirst: preferHardwareFirst,
            allowImmediateFallbackCenter: allowImmediateFallbackCenter
        )
    }

    nonisolated static func cgEventScreenFrame(
        fromAppKitScreenFrame screenFrame: CGRect,
        globalMaxY: CGFloat,
        inset: CGFloat = 2
    ) -> CGRect {
        AccessibilityInteractionPolicy.cgEventScreenFrame(
            fromAppKitScreenFrame: screenFrame,
            globalMaxY: globalMaxY,
            inset: inset
        )
    }

    nonisolated static func isCGEventPointOnAnyScreen(
        _ point: CGPoint,
        screenFrames: [CGRect],
        globalMaxY: CGFloat,
        inset: CGFloat = 2
    ) -> Bool {
        AccessibilityInteractionPolicy.isCGEventPointOnAnyScreen(
            point,
            screenFrames: screenFrames,
            globalMaxY: globalMaxY,
            inset: inset
        )
    }

    nonisolated static func resolvedGlobalAccessibilityPoint(
        _ point: CGPoint,
        screenFrames: [CGRect],
        preferredScreenFrame: CGRect? = nil,
        inset: CGFloat = 2
    ) -> CGPoint {
        AccessibilityInteractionPolicy.resolvedGlobalAccessibilityPoint(
            point,
            screenFrames: screenFrames,
            preferredScreenFrame: preferredScreenFrame,
            inset: inset
        )
    }

    nonisolated static func isAccessibilityPointOnAnyScreen(
        _ point: CGPoint,
        screenFrames: [CGRect],
        preferredScreenFrame: CGRect? = nil,
        inset: CGFloat = 2
    ) -> Bool {
        AccessibilityInteractionPolicy.isAccessibilityPointOnAnyScreen(
            point,
            screenFrames: screenFrames,
            preferredScreenFrame: preferredScreenFrame,
            inset: inset
        )
    }

    nonisolated static func normalizedEventY(rawY: CGFloat, globalMaxY: CGFloat, anchorY: CGFloat) -> CGFloat {
        AccessibilityInteractionPolicy.normalizedEventY(rawY: rawY, globalMaxY: globalMaxY, anchorY: anchorY)
    }

    nonisolated static func frameIsInTargetZone(
        afterFrame: CGRect,
        separatorX: CGFloat,
        toHidden: Bool,
        margin: CGFloat = 6,
        alwaysHiddenBoundaryX: CGFloat? = nil
    ) -> Bool {
        AccessibilityInteractionPolicy.frameIsInTargetZone(
            afterFrame: afterFrame,
            separatorX: separatorX,
            toHidden: toHidden,
            margin: margin,
            alwaysHiddenBoundaryX: alwaysHiddenBoundaryX
        )
    }

    nonisolated static func hasDirectionMismatch(
        beforeFrame: CGRect,
        afterFrame: CGRect,
        separatorX: CGFloat,
        toHidden: Bool,
        margin: CGFloat = 6,
        tolerance: CGFloat = 2
    ) -> Bool {
        AccessibilityInteractionPolicy.hasDirectionMismatch(
            beforeFrame: beforeFrame,
            afterFrame: afterFrame,
            separatorX: separatorX,
            toHidden: toHidden,
            margin: margin,
            tolerance: tolerance
        )
    }

    nonisolated static func shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
        staleSeparatorX: CGFloat,
        staleFrame: CGRect,
        freshSeparatorX: CGFloat,
        freshVisibleBoundaryX: CGFloat,
        refreshedFrame: CGRect
    ) -> Bool {
        AccessibilityInteractionPolicy.shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
            staleSeparatorX: staleSeparatorX,
            staleFrame: staleFrame,
            freshSeparatorX: freshSeparatorX,
            freshVisibleBoundaryX: freshVisibleBoundaryX,
            refreshedFrame: refreshedFrame
        )
    }

    nonisolated static func moveTargetX(
        targetLane: MoveTargetLane,
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        AccessibilityInteractionPolicy.moveTargetX(
            targetLane: targetLane,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )
    }

    nonisolated static func moveTargetX(
        toHidden: Bool,
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        AccessibilityInteractionPolicy.moveTargetX(
            toHidden: toHidden,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )
    }

    nonisolated static func cmdDragStepCount(distance: CGFloat) -> Int {
        AccessibilityInteractionPolicy.cmdDragStepCount(distance: distance)
    }

    nonisolated func moveMenuBarIcon(
        fromKnownFrame iconFrame: CGRect,
        toHidden: Bool,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat? = nil,
        eventTap: CGEventTapLocation = .cghidEventTap,
        originalMouseLocation: CGPoint,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        dragService.moveMenuBarIcon(
            fromKnownFrame: iconFrame,
            toHidden: toHidden,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX,
            eventTap: eventTap,
            originalMouseLocation: originalMouseLocation,
            referenceScreenFrame: referenceScreenFrame
        )
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
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        dragService.reorderMenuBarIcon(
            sourceBundleID: sourceBundleID,
            sourceMenuExtraID: sourceMenuExtraID,
            sourceStatusItemIndex: sourceStatusItemIndex,
            targetBundleID: targetBundleID,
            targetMenuExtraID: targetMenuExtraID,
            targetStatusItemIndex: targetStatusItemIndex,
            placeAfterTarget: placeAfterTarget,
            originalMouseLocation: originalMouseLocation,
            referenceScreenFrame: referenceScreenFrame
        )
    }

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
        originalMouseLocation: CGPoint,
        referenceScreenFrame: CGRect? = nil
    ) -> Bool {
        dragService.moveMenuBarIcon(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toHidden: toHidden,
            targetLane: targetLane,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX,
            eventTap: eventTap,
            originalMouseLocation: originalMouseLocation,
            referenceScreenFrame: referenceScreenFrame
        )
    }

    nonisolated func currentMenuBarIconWidth(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil
    ) -> CGFloat? {
        dragService.currentMenuBarIconWidth(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        )
    }
}
