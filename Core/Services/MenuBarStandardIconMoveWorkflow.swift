import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarStandardIconMoveWorkflow")

@MainActor
final class MenuBarStandardIconMoveWorkflow {
    struct Request {
        let bundleID: String
        let menuExtraId: String?
        let statusItemIndex: Int?
        let preferredCenterX: CGFloat?
        let toHidden: Bool
        let separatorOverrideX: CGFloat?
        let clearAlwaysHiddenPinAfterMove: Bool
    }

    private struct DragContext {
        let sourceIdentity: MenuBarMoveTargetResolver.SourceIdentity
        let accessibilityService: AccessibilityService
        let referenceScreenFrame: CGRect?
        let originalMouseLocation: CGPoint
    }

    private struct FinishContext {
        let success: Bool
        let request: Request
        let activeSeparatorX: CGFloat
        let activeVisibleBoundaryX: CGFloat?
        let usedShowAllShield: Bool
    }

    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func moveIcon(_ request: Request) -> Bool {
        let identityPrecision: MenuBarIdentityPrecision = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex
        ) ? .exact : .coarse
        guard manager.moveQueueWorkflow.canQueueInteractiveMove(
            operationName: "moveIcon",
            requiresAlwaysHiddenSeparator: false,
            identityPrecision: identityPrecision
        ) else {
            return false
        }

        logger.debug("========== MOVE ICON START ==========")
        logger.debug("moveIcon: bundleID=\(request.bundleID, privacy: .private), menuExtraId=\(request.menuExtraId ?? "nil", privacy: .private), toHidden=\(request.toHidden, privacy: .public)")
        logger.debug("Current hidingState: \(String(describing: self.manager.hidingState))")

        let preMoveSeparatorRightEdge = manager.geometryResolver.separatorRightEdgeX()
        if let sepX = preMoveSeparatorRightEdge {
            logger.debug("Separator right edge BEFORE: \(sepX)")
        }
        if let mainX = manager.geometryResolver.mainStatusItemLeftEdgeX() {
            logger.debug("Main icon left edge BEFORE: \(mainX)")
        }

        let wasHidden = manager.hidingService.state == .hidden
        logger.debug("wasHidden: \(wasHidden)")

        manager.alwaysHiddenPinEnforcementTask?.cancel()
        manager.alwaysHiddenPinEnforcementTask = nil

        if !request.toHidden {
            preClearAlwaysHiddenPinForVisibleMove(request)
        }

        let needsAuthCheck = !request.toHidden && wasHidden && manager.settings.requireAuthToShowHiddenIcons
        let originalLocation = NSEvent.mouseLocation
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 1080
        let originalCGPoint = CGPoint(x: originalLocation.x, y: globalMaxY - originalLocation.y)

        return manager.moveTaskCoordinator.queueDetachedMoveTask(operationName: "moveIcon") { manager in
            var usedShowAllShield = false
            let restoreShieldIfNeeded = { () async in
                guard usedShowAllShield else { return }
                let shouldSkipHide = wasHidden
                    ? await MainActor.run { manager.shouldSkipHideForExternalMonitor }
                    : false

                if wasHidden, !shouldSkipHide {
                    logger.info("Move complete - direct hide from showAll state")
                    await manager.hidingService.hide()
                    return
                }

                logger.info("Restoring from showAll shield pattern...")
                await manager.hidingService.restoreFromShowAll()
            }

            if wasHidden {
                logger.info("Expanding ALL icons via shield pattern for move...")
                if needsAuthCheck {
                    let revealed = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .findIcon)
                    guard revealed else {
                        logger.info("Auth failed or cancelled - aborting icon move")
                        return false
                    }
                }
                await manager.hidingService.showAll()
                usedShowAllShield = true
                try? await Task.sleep(for: .milliseconds(300))
            } else {
                try? await Task.sleep(for: .milliseconds(50))
            }

            if request.toHidden,
               await manager.moveTargetResolver.regularHiddenMoveRequiresAlwaysHiddenBoundary(),
               !usedShowAllShield {
                logger.info("Expanding ALL icons to resolve regular Hidden lane boundary...")
                await manager.hidingService.showAll()
                usedShowAllShield = true
                try? await Task.sleep(for: .milliseconds(300))
            }

            let accessibilityService = await MainActor.run { AccessibilityService.shared }
            let referenceScreenFrame = await MainActor.run { manager.currentRecoveryReferenceScreen()?.frame }
            let sourceIdentity = MenuBarMoveTargetResolver.SourceIdentity(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                preferredCenterX: request.preferredCenterX
            )
            let actionableMoveSafety = AccessibilityMenuExtraService.actionableMoveResolutionSafety(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                preferredCenterX: request.preferredCenterX
            )
            if !actionableMoveSafety.canExecuteMove {
                logger.warning("Refusing ambiguous move target for \(request.bundleID, privacy: .private); exact identity could not be proven")
                await restoreShieldIfNeeded()
                return false
            }
            let dragContext = DragContext(
                sourceIdentity: sourceIdentity,
                accessibilityService: accessibilityService,
                referenceScreenFrame: referenceScreenFrame,
                originalMouseLocation: originalCGPoint
            )

            var (separatorX, visibleBoundaryX) = await manager.moveTargetResolver.resolveMoveTargetsWithRetries(
                toHidden: request.toHidden,
                sourceIdentity: sourceIdentity,
                separatorOverrideX: request.separatorOverrideX
            )

            if request.toHidden,
               request.separatorOverrideX == nil,
               !usedShowAllShield,
               let baselineRightEdge = preMoveSeparatorRightEdge,
               let resolvedSeparatorX = separatorX {
                let resolvedRightEdge = resolvedSeparatorX + MenuBarMoveGeometryPolicy.separatorVisualWidth
                if resolvedRightEdge + 140 < baselineRightEdge {
                    logger.warning("Hidden move target drifted too far left (baselineRight=\(baselineRightEdge), resolvedRight=\(resolvedRightEdge)) - forcing shield re-resolve")
                    await manager.hidingService.showAll()
                    usedShowAllShield = true
                    try? await Task.sleep(for: .milliseconds(300))
                    (separatorX, visibleBoundaryX) = await manager.moveTargetResolver.resolveMoveTargetsWithRetries(
                        toHidden: request.toHidden,
                        sourceIdentity: sourceIdentity,
                        separatorOverrideX: request.separatorOverrideX
                    )
                }
            }

            guard let resolvedSeparatorX = separatorX else {
                logger.error("Cannot get separator position - ABORTING")
                await restoreShieldIfNeeded()
                return false
            }
            var activeSeparatorX = resolvedSeparatorX
            var activeVisibleBoundaryX = visibleBoundaryX
            if !request.toHidden {
                guard let activeVisibleBoundaryX, activeVisibleBoundaryX > 0 else {
                    logger.error("Missing visible boundary for move-to-visible - ABORTING")
                    await restoreShieldIfNeeded()
                    return false
                }
            }

            if request.toHidden,
               let hiddenLaneLeftBoundaryX = activeVisibleBoundaryX,
               let iconWidth = accessibilityService.currentMenuBarIconWidth(
                   bundleID: request.bundleID,
                   menuExtraId: request.menuExtraId,
                   statusItemIndex: request.statusItemIndex
               ) {
                let hiddenLaneWidth = activeSeparatorX - hiddenLaneLeftBoundaryX
                if MenuBarMoveGeometryPolicy.shouldBlockWideIconHiddenMove(iconWidth: iconWidth, hiddenLaneWidth: hiddenLaneWidth) {
                    logger.warning("Hidden move blocked for wide icon edge case (iconWidth=\(iconWidth, privacy: .public), hiddenLaneWidth=\(hiddenLaneWidth, privacy: .public)); keeping current zone")
                    await restoreShieldIfNeeded()
                    return false
                }
            }

            var success = accessibilityService.moveMenuBarIcon(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                preferredCenterX: request.preferredCenterX,
                toHidden: request.toHidden,
                separatorX: activeSeparatorX,
                visibleBoundaryX: activeVisibleBoundaryX,
                originalMouseLocation: originalCGPoint,
                referenceScreenFrame: referenceScreenFrame
            )

            if !success, !request.toHidden {
                success = await manager.moveTargetResolver.verifyVisibleMoveWithFreshGeometry(
                    identity: sourceIdentity,
                    staleSeparatorX: activeSeparatorX,
                    allowsGeometryRecheck: actionableMoveSafety.allowsClassifiedZoneFallback
                )
            }

            if !success {
                logger.info("Retrying move once with session tap...")
                try? await Task.sleep(for: .milliseconds(200))
                let retryTargets = await manager.moveTargetResolver.resolveMoveTargetsWithRetries(
                    toHidden: request.toHidden,
                    sourceIdentity: sourceIdentity,
                    separatorOverrideX: request.separatorOverrideX
                )
                if let retrySeparatorX = retryTargets.separatorX {
                    activeSeparatorX = retrySeparatorX
                    activeVisibleBoundaryX = retryTargets.visibleBoundaryX
                    let retryLabel = request.toHidden ? "hidden" : "visible"
                    logger.debug("Re-resolved \(retryLabel) move targets for retry: separator=\(activeSeparatorX), visibleBoundary=\(activeVisibleBoundaryX ?? -1)")
                }

                success = accessibilityService.moveMenuBarIcon(
                    bundleID: request.bundleID,
                    menuExtraId: request.menuExtraId,
                    statusItemIndex: request.statusItemIndex,
                    preferredCenterX: request.preferredCenterX,
                    toHidden: request.toHidden,
                    separatorX: activeSeparatorX,
                    visibleBoundaryX: activeVisibleBoundaryX,
                    eventTap: .cgSessionEventTap,
                    originalMouseLocation: originalCGPoint,
                    referenceScreenFrame: referenceScreenFrame
                )
            }

            success = await self.runShieldFallbackIfNeeded(
                success: success,
                request: request,
                dragContext: dragContext,
                usedShowAllShield: &usedShowAllShield
            )

            if !success {
                success = await self.verifyByClassifiedZoneIfAllowed(
                    request: request,
                    actionableMoveSafety: actionableMoveSafety
                )
            }

            await self.finishMove(
                FinishContext(
                    success: success,
                    request: request,
                    activeSeparatorX: activeSeparatorX,
                    activeVisibleBoundaryX: activeVisibleBoundaryX,
                    usedShowAllShield: usedShowAllShield
                ),
                restoreShieldIfNeeded: restoreShieldIfNeeded
            )

            logger.debug("========== MOVE ICON END ==========")
            return success
        }
    }

    private func preClearAlwaysHiddenPinForVisibleMove(_ request: Request) {
        var removedPin = manager.alwaysHiddenPinWorkflow.unpin(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex
        )
        if !removedPin, !request.bundleID.hasPrefix("com.apple.controlcenter") {
            removedPin = manager.alwaysHiddenPinWorkflow.unpin(bundleID: request.bundleID)
        }
        if removedPin {
            logger.info("Cleared stale always-hidden pin before move-to-visible")
        }
    }

    private func runShieldFallbackIfNeeded(
        success: Bool,
        request: Request,
        dragContext: DragContext,
        usedShowAllShield: inout Bool
    ) async -> Bool {
        var success = success
        let shouldAttemptShieldFallback = !success && (request.toHidden ? !usedShowAllShield : true)
        guard shouldAttemptShieldFallback else { return success }

        if !usedShowAllShield {
            let fallbackLabel = request.toHidden ? "Hidden" : "Visible"
            logger.warning("\(fallbackLabel, privacy: .public) move still failed after standard retry - forcing showAll shield fallback")
            await manager.hidingService.showAll()
            usedShowAllShield = true
            try? await Task.sleep(for: .milliseconds(300))
        } else {
            logger.warning("Visible move still failed after standard retry while already using showAll shield - refreshing move targets once more")
        }

        await MainActor.run {
            AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
        }

        let (fallbackSeparatorX, fallbackVisibleBoundaryX) = await manager.moveTargetResolver.resolveMoveTargetsWithRetries(
            toHidden: request.toHidden,
            sourceIdentity: dragContext.sourceIdentity,
            separatorOverrideX: request.separatorOverrideX
        )

        if let fallbackSeparatorX {
            if !request.toHidden, (fallbackVisibleBoundaryX ?? 0) <= 0 {
                logger.error("Shield fallback could not resolve visible boundary - keeping failure")
            } else {
                success = dragContext.accessibilityService.moveMenuBarIcon(
                    bundleID: request.bundleID,
                    menuExtraId: request.menuExtraId,
                    statusItemIndex: request.statusItemIndex,
                    preferredCenterX: request.preferredCenterX,
                    toHidden: request.toHidden,
                    separatorX: fallbackSeparatorX,
                    visibleBoundaryX: fallbackVisibleBoundaryX,
                    eventTap: .cgSessionEventTap,
                    originalMouseLocation: dragContext.originalMouseLocation,
                    referenceScreenFrame: dragContext.referenceScreenFrame
                )
                logger.info("Shield fallback returned: \(success, privacy: .public)")
            }
        } else {
            logger.error("Shield fallback could not resolve separator - keeping failure")
        }

        return success
    }

    private func verifyByClassifiedZoneIfAllowed(
        request: Request,
        actionableMoveSafety: (canExecuteMove: Bool, allowsClassifiedZoneFallback: Bool)
    ) async -> Bool {
        if actionableMoveSafety.allowsClassifiedZoneFallback {
            let expectedZone: MenuBarMoveExpectedZone = request.toHidden ? .hidden : .visible
            let classifiedMatch = await MenuBarMoveVerifier.verifyByClassifiedZone(
                bundleID: request.bundleID,
                menuExtraId: request.menuExtraId,
                statusItemIndex: request.statusItemIndex,
                expectedZone: expectedZone
            )
            if classifiedMatch {
                logger.info("Move accepted after classification verification (\(request.toHidden ? "hidden" : "visible"))")
                return true
            }
        } else {
            logger.info("Skipping classified-zone move fallback for ambiguous multi-item identity")
        }
        return false
    }

    private func finishMove(
        _ context: FinishContext,
        restoreShieldIfNeeded: () async -> Void
    ) async {
        if context.success,
           context.request.toHidden,
           context.request.clearAlwaysHiddenPinAfterMove {
            clearAlwaysHiddenPinAfterHiddenMove(context.request)
        }

        if context.success, !context.request.toHidden {
            await MainActor.run {
                MenuBarVisibleLaneCrowdingHint.postCandidate(
                    bundleID: context.request.bundleID,
                    menuExtraId: context.request.menuExtraId,
                    statusItemIndex: context.request.statusItemIndex,
                    separatorRightEdgeX: context.activeSeparatorX,
                    visibleBoundaryX: context.activeVisibleBoundaryX
                )
            }
        }

        await manager.geometryResolver.refreshSeparatorCacheAfterMove()

        let shouldPreservePreHideMoveSnapshot = context.success
            && context.request.toHidden
            && context.usedShowAllShield
        if shouldPreservePreHideMoveSnapshot {
            logger.info("Capturing regular Hidden move snapshot before re-hide")
            await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()
        }

        await restoreShieldIfNeeded()

        if !shouldPreservePreHideMoveSnapshot {
            try? await Task.sleep(for: .milliseconds(300))
            await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()
        } else {
            await MainActor.run {
                AccessibilityService.shared.preserveFreshMenuBarItemPositionsAfterManualMove()
            }
        }
    }

    private func clearAlwaysHiddenPinAfterHiddenMove(_ request: Request) {
        var removed = manager.alwaysHiddenPinWorkflow.unpin(
            bundleID: request.bundleID,
            menuExtraId: request.menuExtraId,
            statusItemIndex: request.statusItemIndex
        )
        if !removed, !request.bundleID.hasPrefix("com.apple.controlcenter") {
            removed = manager.alwaysHiddenPinWorkflow.unpin(bundleID: request.bundleID)
        }
        if removed {
            logger.info("Cleared stale always-hidden pin after successful move-to-hidden")
        }
    }
}
