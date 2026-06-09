import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarAlwaysHiddenIconMoveWorkflow")
private let alwaysHiddenOutboundRevealSettleMilliseconds = 1_500

@MainActor
final class MenuBarAlwaysHiddenIconMoveWorkflow {
    struct Request {
        let bundleID: String
        let menuExtraId: String?
        let statusItemIndex: Int?
        let preferredCenterX: CGFloat?
        let physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    }

    private struct DragContext {
        let accessibilityService: AccessibilityService
        let referenceScreenFrame: CGRect?
        let originalMouseLocation: CGPoint
    }

    private struct AlwaysHiddenTargets {
        var separatorX: CGFloat
        var visibleBoundaryX: CGFloat?
    }

    private struct AlwaysHiddenToHiddenTargets {
        var alwaysHiddenSeparatorRightEdgeX: CGFloat
        var mainSeparatorOriginX: CGFloat
    }

    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func moveAlwaysHidden(
        _ request: Request,
        toAlwaysHidden: Bool,
        preflightAlreadyPassed: Bool = false
    ) -> Bool {
        let identityPrecision: MenuBarIdentityPrecision = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex
        ) ? .exact : .coarse
        if preflightAlreadyPassed {
            guard manager.moveQueueWorkflow.canQueueInteractiveMove(
                operationName: "moveIconAlwaysHidden",
                requiresAlwaysHiddenSeparator: true,
                identityPrecision: identityPrecision
            ) else {
                return false
            }
        } else {
            guard manager.moveQueueWorkflow.prepareAlwaysHiddenMoveQueue(
                operationName: "moveIconAlwaysHidden",
                identityPrecision: identityPrecision,
                shouldEnableSection: toAlwaysHidden
            ) else {
                return false
            }
        }

        let wasHidden = manager.hidingService.state == .hidden
        let needsAuthCheck = !toAlwaysHidden && wasHidden && manager.settings.requireAuthToShowHiddenIcons
        let originalCGPoint = currentMousePoint()
        let optimisticMutation: MenuBarMoveTaskCoordinator.QueuedAlwaysHiddenMutation =
            toAlwaysHidden
                ? .pin(
                    bundleID: request.bundleID,
                    menuExtraId: request.menuExtraId,
                    statusItemIndex: request.statusItemIndex
                )
                : .unpin(
                    bundleID: request.bundleID,
                    menuExtraId: request.menuExtraId,
                    statusItemIndex: request.statusItemIndex
                )

        return manager.moveTaskCoordinator.queueDetachedMoveTask(
            operationName: "moveIconAlwaysHidden",
            optimisticAlwaysHiddenMutation: optimisticMutation
        ) { manager in
            if needsAuthCheck {
                let revealed = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .findIcon)
                guard revealed else { return false }
            }

            if !toAlwaysHidden {
                await self.prepareOutboundAlwaysHiddenMove(request, wasHidden: wasHidden)
            }
            await manager.hidingService.showAll()
            let revealSettleMilliseconds = toAlwaysHidden ? 300 : alwaysHiddenOutboundRevealSettleMilliseconds
            try? await Task.sleep(for: .milliseconds(revealSettleMilliseconds))
            if !toAlwaysHidden {
                await self.repairAlwaysHiddenSeparatorForOutboundMoveIfNeeded(request)
            }

            let resolvedTargets = await manager.moveTargetResolver.resolveAlwaysHiddenMoveTargetsWithRetries(
                toAlwaysHidden: toAlwaysHidden
            )

            guard let resolvedSeparatorX = resolvedTargets.separatorX else {
                logger.error("Cannot resolve separator position for always-hidden move")
                await self.restoreFromShield(wasHidden: wasHidden)
                return false
            }
            var targets = AlwaysHiddenTargets(
                separatorX: resolvedSeparatorX,
                visibleBoundaryX: resolvedTargets.visibleBoundaryX
            )
            let dragContext = await self.dragContext(originalMouseLocation: originalCGPoint)
            let actionableMoveSafety = AccessibilityMenuExtraService.actionableMoveResolutionSafety(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                preferredCenterX: request.preferredCenterX
            )
            if !actionableMoveSafety.canExecuteMove {
                logger.warning("Refusing ambiguous always-hidden move target for \(request.bundleID, privacy: .private); exact identity could not be proven")
                await self.restoreFromShield(wasHidden: wasHidden)
                return false
            }

            var success = await self.dragAlwaysHidden(
                request,
                toAlwaysHidden: toAlwaysHidden,
                targets: targets,
                dragContext: dragContext
            )

            if !success, !toAlwaysHidden {
                let identity = MenuBarMoveTargetResolver.SourceIdentity(
                    bundleID: request.bundleID,
                    menuExtraId: request.menuExtraId,
                    statusItemIndex: request.statusItemIndex,
                    preferredCenterX: request.preferredCenterX
                )
                success = await manager.moveTargetResolver.verifyVisibleMoveWithFreshGeometry(
                    identity: identity,
                    staleSeparatorX: targets.separatorX,
                    allowsGeometryRecheck: actionableMoveSafety.allowsClassifiedZoneFallback
                )
            }

            if !success {
                success = await self.retryAlwaysHiddenMove(
                    request,
                    toAlwaysHidden: toAlwaysHidden,
                    targets: &targets,
                    dragContext: dragContext
                )
            }

            if !success {
                success = await self.verifyClassifiedAlwaysHiddenMoveIfAllowed(
                    request,
                    toAlwaysHidden: toAlwaysHidden,
                    actionableMoveSafety: actionableMoveSafety
                )
            }

            if success, !toAlwaysHidden {
                await MainActor.run {
                    MenuBarVisibleLaneCrowdingHint.postCandidate(
                        bundleID: request.bundleID,
                        menuExtraId: request.menuExtraId,
                        statusItemIndex: request.statusItemIndex,
                        separatorRightEdgeX: targets.separatorX,
                        visibleBoundaryX: targets.visibleBoundaryX
                    )
                }
            }

            await manager.geometryResolver.refreshSeparatorCacheAfterMove()
            await self.restoreFromShield(wasHidden: wasHidden)
            try? await Task.sleep(for: .milliseconds(300))
            await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()

            return success
        }
    }

    func moveAlwaysHiddenToHidden(_ request: Request) -> Bool {
        let identityPrecision: MenuBarIdentityPrecision = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex
        ) ? .exact : .coarse
        guard manager.moveQueueWorkflow.canQueueInteractiveMove(
            operationName: "moveIconFromAlwaysHiddenToHidden",
            requiresAlwaysHiddenSeparator: true,
            identityPrecision: identityPrecision
        ) else {
            return false
        }

        let wasHidden = manager.hidingService.state == .hidden
        let originalCGPoint = currentMousePoint()

        return manager.moveTaskCoordinator.queueDetachedMoveTask(
            operationName: "moveIconFromAlwaysHiddenToHidden",
            optimisticAlwaysHiddenMutation: .unpin(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex
            )
        ) { manager in
            await self.prepareOutboundAlwaysHiddenMove(request, wasHidden: wasHidden)
            await manager.hidingService.showAll()
            try? await Task.sleep(for: .milliseconds(alwaysHiddenOutboundRevealSettleMilliseconds))
            await self.repairAlwaysHiddenSeparatorForOutboundMoveIfNeeded(request)

            guard var targets = await self.currentAlwaysHiddenToHiddenTargets() else {
                logger.error("Cannot resolve AH separator position for AH-to-Hidden move")
                await self.restoreFromShield(wasHidden: wasHidden)
                return false
            }

            let dragContext = await self.dragContext(originalMouseLocation: originalCGPoint)
            let actionableMoveSafety = AccessibilityMenuExtraService.actionableMoveResolutionSafety(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                preferredCenterX: request.preferredCenterX
            )
            if !actionableMoveSafety.canExecuteMove {
                logger.warning("Refusing ambiguous AH-to-Hidden move target for \(request.bundleID, privacy: .private); exact identity could not be proven")
                await self.restoreFromShield(wasHidden: wasHidden)
                return false
            }

            var success = await self.dragAlwaysHiddenToHidden(
                request,
                targets: targets,
                dragContext: dragContext
            )

            if !success {
                success = await self.retryAlwaysHiddenToHiddenMove(
                    request,
                    targets: &targets,
                    dragContext: dragContext
                )
            }

            if !success {
                success = await self.verifyAlwaysHiddenToHiddenIfAllowed(
                    request,
                    actionableMoveSafety: actionableMoveSafety
                )
            }

            await manager.geometryResolver.refreshSeparatorCacheAfterMove()

            let shouldPreservePreHideMoveSnapshot = success
            if shouldPreservePreHideMoveSnapshot {
                logger.info("Capturing AH-to-Hidden move snapshot before re-hide")
                await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()
            }

            await self.restoreFromShield(wasHidden: wasHidden)

            if shouldPreservePreHideMoveSnapshot {
                await MainActor.run {
                    AccessibilityService.shared.preserveFreshMenuBarItemPositionsAfterManualMove()
                }
            } else {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
                    NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
                }
            }

            return success
        }
    }

    private func dragAlwaysHidden(
        _ request: Request,
        toAlwaysHidden: Bool,
        targets: AlwaysHiddenTargets,
        dragContext: DragContext
    ) -> Bool {
        dragContext.accessibilityService.moveMenuBarIcon(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex,
            preferredCenterX: request.preferredCenterX,
            toHidden: toAlwaysHidden,
            targetLane: toAlwaysHidden ? .alwaysHidden : .visibleFromAlwaysHidden,
            separatorX: targets.separatorX,
            visibleBoundaryX: targets.visibleBoundaryX,
            originalMouseLocation: dragContext.originalMouseLocation,
            physicalMoveOrigin: request.physicalMoveOrigin,
            referenceScreenFrame: dragContext.referenceScreenFrame
        )
    }

    private func retryAlwaysHiddenMove(
        _ request: Request,
        toAlwaysHidden: Bool,
        targets: inout AlwaysHiddenTargets,
        dragContext: DragContext
    ) async -> Bool {
        logger.info("Always-hidden move retry with session tap...")
        try? await Task.sleep(for: .milliseconds(200))
        let retryTargets = await manager.moveTargetResolver.resolveAlwaysHiddenMoveTargetsWithRetries(
            toAlwaysHidden: toAlwaysHidden,
            maxAttempts: 10
        )
        if let retrySeparatorX = retryTargets.separatorX {
            targets.separatorX = retrySeparatorX
            targets.visibleBoundaryX = retryTargets.visibleBoundaryX
            let separatorX = targets.separatorX
            let visibleBoundaryX = targets.visibleBoundaryX ?? -1
            logger.info("Re-resolved always-hidden move targets for retry: separator=\(separatorX), visibleBoundary=\(visibleBoundaryX)")
        }
        let success = dragContext.accessibilityService.moveMenuBarIcon(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex,
            preferredCenterX: request.preferredCenterX,
            toHidden: toAlwaysHidden,
            targetLane: toAlwaysHidden ? .alwaysHidden : .visibleFromAlwaysHidden,
            separatorX: targets.separatorX,
            visibleBoundaryX: targets.visibleBoundaryX,
            eventTap: .cgSessionEventTap,
            originalMouseLocation: dragContext.originalMouseLocation,
            physicalMoveOrigin: request.physicalMoveOrigin,
            referenceScreenFrame: dragContext.referenceScreenFrame
        )
        logger.info("Always-hidden retry returned: \(success, privacy: .public)")
        return success
    }

    private func verifyClassifiedAlwaysHiddenMoveIfAllowed(
        _ request: Request,
        toAlwaysHidden: Bool,
        actionableMoveSafety: (canExecuteMove: Bool, allowsClassifiedZoneFallback: Bool)
    ) async -> Bool {
        if actionableMoveSafety.allowsClassifiedZoneFallback {
            let expectedZone: MenuBarMoveExpectedZone = toAlwaysHidden ? .alwaysHidden : .visible
            let classifiedMatch = await MenuBarMoveVerifier.verifyByClassifiedZone(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                expectedZone: expectedZone
            )
            if classifiedMatch {
                logger.info("Always-hidden move accepted after classification verification (\(toAlwaysHidden ? "alwaysHidden" : "visible"))")
                return true
            }
        } else {
            logger.info("Skipping always-hidden classified-zone fallback for ambiguous multi-item identity")
        }
        return false
    }

    private func currentAlwaysHiddenToHiddenTargets() async -> AlwaysHiddenToHiddenTargets? {
        await MainActor.run {
            guard let alwaysHiddenItem = manager.alwaysHiddenSeparatorItem,
                  let alwaysHiddenButton = alwaysHiddenItem.button,
                  let alwaysHiddenWindow = alwaysHiddenButton.window,
                  let mainSeparatorOriginX = manager.geometryResolver.separatorOriginX() else {
                return nil
            }
            let alwaysHiddenFrame = alwaysHiddenWindow.frame
            guard alwaysHiddenFrame.width > 0 else { return nil }
            return AlwaysHiddenToHiddenTargets(
                alwaysHiddenSeparatorRightEdgeX: alwaysHiddenFrame.origin.x + alwaysHiddenFrame.width,
                mainSeparatorOriginX: mainSeparatorOriginX
            )
        }
    }

    private func dragAlwaysHiddenToHidden(
        _ request: Request,
        targets: AlwaysHiddenToHiddenTargets,
        dragContext: DragContext
    ) -> Bool {
        dragContext.accessibilityService.moveMenuBarIcon(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex,
            preferredCenterX: request.preferredCenterX,
            toHidden: false,
            targetLane: .hiddenFromAlwaysHidden,
            separatorX: targets.mainSeparatorOriginX,
            visibleBoundaryX: targets.alwaysHiddenSeparatorRightEdgeX,
            originalMouseLocation: dragContext.originalMouseLocation,
            physicalMoveOrigin: request.physicalMoveOrigin,
            referenceScreenFrame: dragContext.referenceScreenFrame
        )
    }

    private func retryAlwaysHiddenToHiddenMove(
        _ request: Request,
        targets: inout AlwaysHiddenToHiddenTargets,
        dragContext: DragContext
    ) async -> Bool {
        logger.info("AH-to-Hidden move retry with session tap...")
        try? await Task.sleep(for: .milliseconds(200))
        if let retryTargets = await currentAlwaysHiddenToHiddenTargets() {
            targets = retryTargets
            let alwaysHiddenRightEdgeX = targets.alwaysHiddenSeparatorRightEdgeX
            let mainSeparatorOriginX = targets.mainSeparatorOriginX
            logger.info("Re-resolved AH-to-Hidden targets for retry: ahRight=\(alwaysHiddenRightEdgeX), mainSepOrigin=\(mainSeparatorOriginX)")
        }
        return dragContext.accessibilityService.moveMenuBarIcon(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex,
            preferredCenterX: request.preferredCenterX,
            toHidden: false,
            targetLane: .hiddenFromAlwaysHidden,
            separatorX: targets.mainSeparatorOriginX,
            visibleBoundaryX: targets.alwaysHiddenSeparatorRightEdgeX,
            eventTap: .cgSessionEventTap,
            originalMouseLocation: dragContext.originalMouseLocation,
            physicalMoveOrigin: request.physicalMoveOrigin,
            referenceScreenFrame: dragContext.referenceScreenFrame
        )
    }

    private func verifyAlwaysHiddenToHiddenIfAllowed(
        _ request: Request,
        actionableMoveSafety: (canExecuteMove: Bool, allowsClassifiedZoneFallback: Bool)
    ) async -> Bool {
        if actionableMoveSafety.allowsClassifiedZoneFallback {
            let classifiedMatch = await MenuBarMoveVerifier.verifyByClassifiedZone(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                expectedZone: .hidden
            )
            if classifiedMatch {
                logger.info("AH-to-Hidden move accepted after classification verification")
                return true
            }
        } else {
            logger.info("Skipping AH-to-Hidden classified-zone fallback for ambiguous multi-item identity")
        }
        return false
    }

    private func prepareOutboundAlwaysHiddenMove(_ request: Request, wasHidden: Bool) async {
        let removedPin = await MainActor.run {
            manager.alwaysHiddenPinWorkflow.unpin(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex
            )
        }
        if removedPin {
            logger.info("Temporarily removed always-hidden pin before outbound move")
        }

        if wasHidden {
            await manager.hidingService.restoreFromShowAll()
        }
    }

    private func repairAlwaysHiddenSeparatorForOutboundMoveIfNeeded(_ request: Request) async {
        if sourceFrameIsOnScreen(request) { return }

        logger.warning("Outbound always-hidden source is still off-screen after showAll; recreating AH separator before retry")
        await MainActor.run {
            manager.clearCachedSeparatorGeometry()
            manager.statusBarController.ensureAlwaysHiddenSeparator(enabled: false)
            StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
            manager.statusBarController.ensureAlwaysHiddenSeparator(enabled: true)
            manager.alwaysHiddenSeparatorItem = manager.statusBarController.alwaysHiddenSeparatorItem
            manager.hidingService.configureAlwaysHiddenDelimiter(manager.alwaysHiddenSeparatorItem)
            manager.clearCachedSeparatorGeometry()
            AccessibilityService.shared.invalidateMenuBarItemCache()
        }

        await manager.hidingService.showAll()
        try? await Task.sleep(for: .milliseconds(400))
        await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
        await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
        await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()
    }

    private func sourceFrameIsOnScreen(_ request: Request) -> Bool {
        guard let frame = AccessibilityMenuExtraService.getMenuBarIconFrame(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex,
            preferredCenterX: request.preferredCenterX
        ) else {
            return false
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return AccessibilityInteractionPolicy.isAccessibilityPointOnAnyScreen(
            center,
            screenFrames: NSScreen.screens.map(\.frame),
            preferredScreenFrame: manager.currentRecoveryReferenceScreen()?.frame
        )
    }

    private func restoreFromShield(wasHidden: Bool) async {
        await manager.hidingService.restoreFromShowAll()

        let shouldSkipHide = await MainActor.run { manager.shouldSkipHideForExternalMonitor }
        if wasHidden, !shouldSkipHide {
            await manager.hidingService.hide()
        }
    }

    private func dragContext(originalMouseLocation: CGPoint) async -> DragContext {
        let accessibilityService = await MainActor.run { AccessibilityService.shared }
        let referenceScreenFrame = await MainActor.run { manager.currentRecoveryReferenceScreen()?.frame }
        return DragContext(
            accessibilityService: accessibilityService,
            referenceScreenFrame: referenceScreenFrame,
            originalMouseLocation: originalMouseLocation
        )
    }

    private func currentMousePoint() -> CGPoint {
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        return CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)
    }
}
