import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarMoveQueueWorkflow")

@MainActor
final class MenuBarMoveQueueWorkflow {
    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func canQueueInteractiveMove(
        operationName: String,
        requiresAlwaysHiddenSeparator: Bool,
        identityPrecision: MenuBarIdentityPrecision
    ) -> Bool {
        switch MenuBarOperationCoordinator.moveQueueDecision(
            snapshot: currentMoveRuntimeSnapshot(identityPrecision: identityPrecision),
            requiresAlwaysHiddenSeparator: requiresAlwaysHiddenSeparator
        ) {
        case .ready:
            return true
        case .rejectBusy:
            logger.warning("🔧 \(operationName, privacy: .public) skipped — hiding service busy")
            return false
        case .rejectInvalidStatusItems:
            logger.warning("🔧 \(operationName, privacy: .public) skipped — status items are not in a ready structural state")
            return false
        case .rejectAwaitingAnchor:
            logger.warning("🔧 \(operationName, privacy: .public) skipped — status-item bootstrap still awaiting anchor")
            return false
        case .rejectMoveAlreadyInFlight:
            logger.warning("⚠️ \(operationName, privacy: .public) rejected: another move is in progress")
            return false
        case .rejectMissingAlwaysHiddenSeparator:
            logger.error("🔧 \(operationName, privacy: .public): always-hidden separator unavailable")
            return false
        case .rejectMissingScreenGeometry:
            logger.error("🔧 \(operationName, privacy: .public): no screens available — aborting")
            return false
        }
    }

    func prepareAlwaysHiddenMoveQueue(
        operationName: String,
        identityPrecision: MenuBarIdentityPrecision,
        shouldEnableSection: Bool
    ) -> Bool {
        _ = ensureAlwaysHiddenSeparatorReady(
            operationName: operationName,
            shouldEnableSection: shouldEnableSection
        )
        return canQueueInteractiveMove(
            operationName: operationName,
            requiresAlwaysHiddenSeparator: true,
            identityPrecision: identityPrecision
        )
    }

    func prepareAlwaysHiddenMoveQueueAfterDrop(
        operationName: String,
        identityPrecision: MenuBarIdentityPrecision,
        shouldEnableSection: Bool
    ) async -> Bool {
        _ = await ensureAlwaysHiddenSeparatorReadyAfterDrop(
            operationName: operationName,
            shouldEnableSection: shouldEnableSection
        )
        return canQueueInteractiveMove(
            operationName: operationName,
            requiresAlwaysHiddenSeparator: true,
            identityPrecision: identityPrecision
        )
    }

    func queueZoneMove(
        app: RunningApp,
        request: MenuBarZoneMoveRequest,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) -> Task<Bool, Never>? {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex
        let preferredCenterX = app.preferredCenterX

        switch request {
        case .visibleToHidden:
            return queueMoveIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: true,
                physicalMoveOrigin: physicalMoveOrigin
            )
        case .hiddenToVisible:
            return queueMoveIcon(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                toHidden: false,
                physicalMoveOrigin: physicalMoveOrigin
            )
        case .visibleToAlwaysHidden, .hiddenToAlwaysHidden:
            return queueMoveIconToAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                physicalMoveOrigin: physicalMoveOrigin
            )
        case .alwaysHiddenToVisible:
            return queueMoveIconFromAlwaysHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                physicalMoveOrigin: physicalMoveOrigin
            )
        case .alwaysHiddenToHidden:
            return queueMoveIconFromAlwaysHiddenToHidden(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX,
                physicalMoveOrigin: physicalMoveOrigin
            )
        }
    }

    func queueZoneMoveAfterDrop(
        app: RunningApp,
        request: MenuBarZoneMoveRequest,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) async -> Task<Bool, Never>? {
        let bundleID = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex
        let preferredCenterX = app.preferredCenterX

        switch request {
        case .visibleToHidden, .hiddenToVisible, .alwaysHiddenToHidden:
            return queueZoneMove(app: app, request: request, physicalMoveOrigin: physicalMoveOrigin)
        case .visibleToAlwaysHidden, .hiddenToAlwaysHidden:
            let identityPrecision: MenuBarIdentityPrecision = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            ) ? .exact : .coarse
            guard await prepareAlwaysHiddenMoveQueueAfterDrop(
                operationName: "moveIconAlwaysHidden",
                identityPrecision: identityPrecision,
                shouldEnableSection: true
            ) else {
                return nil
            }
            return queuedMoveTaskIfStarted(
                manager.alwaysHiddenIconMoveWorkflow.moveAlwaysHidden(
                    MenuBarAlwaysHiddenIconMoveWorkflow.Request(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        preferredCenterX: preferredCenterX,
                        physicalMoveOrigin: physicalMoveOrigin
                    ),
                    toAlwaysHidden: true,
                    preflightAlreadyPassed: true
                )
            )
        case .alwaysHiddenToVisible:
            let identityPrecision: MenuBarIdentityPrecision = MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            ) ? .exact : .coarse
            guard await prepareAlwaysHiddenMoveQueueAfterDrop(
                operationName: "moveIconAlwaysHidden",
                identityPrecision: identityPrecision,
                shouldEnableSection: false
            ) else {
                return nil
            }
            return queuedMoveTaskIfStarted(
                manager.alwaysHiddenIconMoveWorkflow.moveAlwaysHidden(
                    MenuBarAlwaysHiddenIconMoveWorkflow.Request(
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        preferredCenterX: preferredCenterX,
                        physicalMoveOrigin: physicalMoveOrigin
                    ),
                    toAlwaysHidden: false,
                    preflightAlreadyPassed: true
                )
            )
        }
    }

    func queueMoveIcon(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        separatorOverrideX: CGFloat? = nil,
        clearAlwaysHiddenPinAfterMove: Bool = true,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            manager.standardIconMoveWorkflow.moveIcon(
                MenuBarStandardIconMoveWorkflow.Request(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    toHidden: toHidden,
                    separatorOverrideX: separatorOverrideX,
                    clearAlwaysHiddenPinAfterMove: clearAlwaysHiddenPinAfterMove,
                    physicalMoveOrigin: physicalMoveOrigin
                )
            )
        )
    }

    func queueMoveIconToAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            manager.alwaysHiddenIconMoveWorkflow.moveAlwaysHidden(
                MenuBarAlwaysHiddenIconMoveWorkflow.Request(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    physicalMoveOrigin: physicalMoveOrigin
                ),
                toAlwaysHidden: true
            )
        )
    }

    func queueMoveIconFromAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            manager.alwaysHiddenIconMoveWorkflow.moveAlwaysHidden(
                MenuBarAlwaysHiddenIconMoveWorkflow.Request(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    physicalMoveOrigin: physicalMoveOrigin
                ),
                toAlwaysHidden: false
            )
        )
    }

    func queueMoveIconFromAlwaysHiddenToHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            manager.alwaysHiddenIconMoveWorkflow.moveAlwaysHiddenToHidden(
                MenuBarAlwaysHiddenIconMoveWorkflow.Request(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    physicalMoveOrigin: physicalMoveOrigin
                )
            )
        )
    }

    func queueReorderIcon(
        sourceBundleID: String,
        sourceMenuExtraID: String? = nil,
        sourceStatusItemIndex: Int? = nil,
        targetBundleID: String,
        targetMenuExtraID: String? = nil,
        targetStatusItemIndex: Int? = nil,
        placeAfterTarget: Bool,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) -> Task<Bool, Never>? {
        queuedMoveTaskIfStarted(
            manager.iconReorderWorkflow.reorderIcon(
                MenuBarIconReorderWorkflow.Request(
                    sourceBundleID: sourceBundleID,
                    sourceMenuExtraID: sourceMenuExtraID,
                    sourceStatusItemIndex: sourceStatusItemIndex,
                    targetBundleID: targetBundleID,
                    targetMenuExtraID: targetMenuExtraID,
                    targetStatusItemIndex: targetStatusItemIndex,
                    placeAfterTarget: placeAfterTarget,
                    physicalMoveOrigin: physicalMoveOrigin
                )
            )
        )
    }

    func moveIconAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toHidden: Bool,
        separatorOverrideX: CGFloat? = nil,
        clearAlwaysHiddenPinAfterMove: Bool = true,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) async -> Bool {
        await waitForActiveMoveTaskIfNeeded()

        guard let task = queueMoveIcon(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            toHidden: toHidden,
            separatorOverrideX: separatorOverrideX,
            clearAlwaysHiddenPinAfterMove: clearAlwaysHiddenPinAfterMove,
            physicalMoveOrigin: physicalMoveOrigin
        ) else { return false }
        return await task.value
    }

    func moveIconAlwaysHiddenAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        toAlwaysHidden: Bool,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) async -> Bool {
        await waitForActiveMoveTaskIfNeeded()

        guard let task = queuedMoveTaskIfStarted(
            manager.alwaysHiddenIconMoveWorkflow.moveAlwaysHidden(
                MenuBarAlwaysHiddenIconMoveWorkflow.Request(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX,
                    physicalMoveOrigin: physicalMoveOrigin
                ),
                toAlwaysHidden: toAlwaysHidden
            )
        ) else { return false }
        return await task.value
    }

    func moveIconFromAlwaysHiddenToHiddenAndWait(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin
    ) async -> Bool {
        await waitForActiveMoveTaskIfNeeded()

        guard let task = queueMoveIconFromAlwaysHiddenToHidden(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX,
            physicalMoveOrigin: physicalMoveOrigin
        ) else { return false }
        return await task.value
    }

    private func currentMoveRuntimeSnapshot(
        identityPrecision: MenuBarIdentityPrecision
    ) -> MenuBarRuntimeSnapshot {
        var snapshot = manager.currentRuntimeSnapshot(identityPrecision: identityPrecision)
        if snapshot.visibilityPhase == .hidden {
            switch snapshot.geometryConfidence {
            case .live, .cached:
                snapshot.geometryConfidence = .shielded
            case .shielded, .stale, .missing:
                break
            }
        }
        return snapshot
    }

    private func queuedMoveTaskIfStarted(_ started: Bool) -> Task<Bool, Never>? {
        manager.moveTaskCoordinator.queuedMoveTaskIfStarted(started)
    }

    private func waitForActiveMoveTaskIfNeeded() async {
        await manager.moveTaskCoordinator.waitForActiveMoveTaskIfNeeded()
    }

    private func ensureAlwaysHiddenSeparatorReady(
        operationName: String,
        shouldEnableSection: Bool,
        maxAttempts: Int = 12
    ) -> Bool {
        if shouldEnableSection, !manager.settings.alwaysHiddenSectionEnabled {
            manager.settings.alwaysHiddenSectionEnabled = true
            manager.saveSettings()
        }

        let featureEnabled = MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
            isPro: LicenseService.shared.isPro,
            alwaysHiddenSectionEnabled: manager.settings.alwaysHiddenSectionEnabled
        )
        let requestedAlwaysHiddenSection = manager.settings.alwaysHiddenSectionEnabled
        guard featureEnabled else {
            logger.error(
                "🔧 \(operationName, privacy: .public): always-hidden feature unavailable (isPro=\(LicenseService.shared.isPro, privacy: .public) requested=\(requestedAlwaysHiddenSection, privacy: .public))"
            )
            return false
        }

        for attempt in 1 ... maxAttempts {
            manager.updateAlwaysHiddenSeparatorIfReady(forceRecreateIfMissing: attempt >= 4)
            if manager.alwaysHiddenSeparatorItem != nil {
                if attempt > 1 {
                    logger.info("🔧 \(operationName, privacy: .public): always-hidden separator became ready after \(attempt) attempts")
                }
                return true
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        logger.error("🔧 \(operationName, privacy: .public): always-hidden separator unavailable after wait")
        return false
    }

    private func ensureAlwaysHiddenSeparatorReadyAfterDrop(
        operationName: String,
        shouldEnableSection: Bool,
        maxAttempts: Int = 12
    ) async -> Bool {
        if shouldEnableSection, !manager.settings.alwaysHiddenSectionEnabled {
            manager.settings.alwaysHiddenSectionEnabled = true
            manager.saveSettings()
        }

        let featureEnabled = MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
            isPro: LicenseService.shared.isPro,
            alwaysHiddenSectionEnabled: manager.settings.alwaysHiddenSectionEnabled
        )
        let requestedAlwaysHiddenSection = manager.settings.alwaysHiddenSectionEnabled
        guard featureEnabled else {
            logger.error(
                "🔧 \(operationName, privacy: .public): always-hidden feature unavailable (isPro=\(LicenseService.shared.isPro, privacy: .public) requested=\(requestedAlwaysHiddenSection, privacy: .public))"
            )
            return false
        }

        for attempt in 1 ... maxAttempts {
            manager.updateAlwaysHiddenSeparatorIfReady(forceRecreateIfMissing: attempt >= 4)
            if manager.alwaysHiddenSeparatorItem != nil {
                if attempt > 1 {
                    logger.info("🔧 \(operationName, privacy: .public): always-hidden separator became ready after \(attempt) async attempts")
                }
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        logger.error("🔧 \(operationName, privacy: .public): always-hidden separator unavailable after async wait")
        return false
    }
}
