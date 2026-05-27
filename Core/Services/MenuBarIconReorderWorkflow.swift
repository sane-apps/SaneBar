import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarIconReorderWorkflow")

@MainActor
final class MenuBarIconReorderWorkflow {
    struct Request {
        let sourceBundleID: String
        let sourceMenuExtraID: String?
        let sourceStatusItemIndex: Int?
        let targetBundleID: String
        let targetMenuExtraID: String?
        let targetStatusItemIndex: Int?
        let placeAfterTarget: Bool
    }

    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func reorderIcon(_ request: Request) -> Bool {
        let preciseSourceIdentity = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
            menuExtraId: request.sourceMenuExtraID,
            statusItemIndex: request.sourceStatusItemIndex
        )
        let preciseTargetIdentity = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
            menuExtraId: request.targetMenuExtraID,
            statusItemIndex: request.targetStatusItemIndex
        )
        guard manager.moveQueueWorkflow.canQueueInteractiveMove(
            operationName: "reorderIcon",
            requiresAlwaysHiddenSeparator: false,
            identityPrecision: preciseSourceIdentity && preciseTargetIdentity ? .exact : .coarse
        ) else {
            return false
        }

        let wasHidden = manager.hidingService.state == .hidden
        let requiresAuth = wasHidden && manager.settings.requireAuthToShowHiddenIcons
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)

        return manager.moveTaskCoordinator.queueDetachedMoveTask(operationName: "reorderIcon") { manager in
            if requiresAuth {
                let revealed = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
            }

            if wasHidden {
                await manager.hidingService.showAll()
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                try? await Task.sleep(for: .milliseconds(50))
            }

            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            let referenceScreenFrame = await MainActor.run { manager.currentRecoveryReferenceScreen()?.frame }
            var success = accessibilityService.reorderMenuBarIcon(
                sourceBundleID: request.sourceBundleID,
                sourceMenuExtraID: request.sourceMenuExtraID,
                sourceStatusItemIndex: request.sourceStatusItemIndex,
                targetBundleID: request.targetBundleID,
                targetMenuExtraID: request.targetMenuExtraID,
                targetStatusItemIndex: request.targetStatusItemIndex,
                placeAfterTarget: request.placeAfterTarget,
                originalMouseLocation: originalCGPoint,
                referenceScreenFrame: referenceScreenFrame
            )

            if !success {
                logger.info("reorderIcon retry...")
                try? await Task.sleep(for: .milliseconds(200))
                success = accessibilityService.reorderMenuBarIcon(
                    sourceBundleID: request.sourceBundleID,
                    sourceMenuExtraID: request.sourceMenuExtraID,
                    sourceStatusItemIndex: request.sourceStatusItemIndex,
                    targetBundleID: request.targetBundleID,
                    targetMenuExtraID: request.targetMenuExtraID,
                    targetStatusItemIndex: request.targetStatusItemIndex,
                    placeAfterTarget: request.placeAfterTarget,
                    originalMouseLocation: originalCGPoint,
                    referenceScreenFrame: referenceScreenFrame
                )
            }

            await manager.geometryResolver.refreshSeparatorCacheAfterMove()

            let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
            if wasHidden {
                await manager.hidingService.restoreFromShowAll()
                if !shouldSkipHide {
                    await manager.hidingService.hide()
                }
            }

            try? await Task.sleep(for: .milliseconds(300))
            await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()

            return success
        }
    }
}
