import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarStatusItemRecoveryWorkflow")

@MainActor
final class MenuBarStatusItemRecoveryWorkflow {
    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    nonisolated static func statusItemValidationInitialDelaySeconds(
        context: MenuBarOperationCoordinator.PositionValidationContext,
        recoveryCount: Int
    ) -> TimeInterval {
        switch context {
        case .startupFollowUp:
            return recoveryCount == 0 ? 1.5 : 2.0
        case .manualLayoutRestore:
            return recoveryCount == 0 ? 0.35 : 0.75
        case .screenParametersChanged:
            return recoveryCount == 0 ? 2.0 : 2.5
        case .wakeResume:
            return recoveryCount == 0 ? 2.0 : 2.5
        }
    }

    nonisolated static func statusItemValidationRetryDelaySeconds(
        context: MenuBarOperationCoordinator.PositionValidationContext
    ) -> TimeInterval {
        switch context {
        case .startupFollowUp, .screenParametersChanged, .wakeResume:
            return 0.5
        case .manualLayoutRestore:
            return 0.25
        }
    }

    nonisolated static func statusItemValidationMaxAttempts(
        context: MenuBarOperationCoordinator.PositionValidationContext
    ) -> Int {
        switch context {
        case .startupFollowUp, .screenParametersChanged, .wakeResume:
            return 6
        case .manualLayoutRestore:
            return 4
        }
    }

    nonisolated static func shouldRecoverUnexpectedVisibilityLoss(
        isVisible: Bool,
        isExecutingRecovery: Bool,
        lastRecoveryAt: Date?,
        now: Date,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard !isVisible else { return false }
        guard !isExecutingRecovery else { return false }
        guard let lastRecoveryAt else { return true }
        return now.timeIntervalSince(lastRecoveryAt) >= minimumInterval
    }

    nonisolated static func shouldResetPersistentStateForStatusItemRecovery(
        reason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        isStartupRecovery: Bool = false,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext? = nil
    ) -> Bool {
        switch reason {
        case .invalidStatusItems, .missingCoordinates:
            isStartupRecovery || validationContext == .startupFollowUp
        case .invalidGeometry:
            isStartupRecovery || validationContext == .startupFollowUp
        case nil:
            false
        }
    }

    func currentRuntimeSnapshot(
        identityPrecision: MenuBarIdentityPrecision = .unknown
    ) -> MenuBarRuntimeSnapshot {
        let controller = manager.statusBarControllerStorage
        let mainItem = manager.mainStatusItem ?? controller?.mainItem
        let separator = manager.separatorItem ?? controller?.separatorItem
        let alwaysHiddenSeparatorX = manager.geometryResolver.alwaysHiddenSeparatorOriginX()
        let startupItemsValid: Bool = {
            guard let mainItem, let separator else { return false }
            return StatusBarController.validateStartupItems(
                main: mainItem,
                separator: separator
            )
        }()
        let mainItemVisible = mainItem?.isVisible
        let separatorItemVisible = separator?.isVisible
        let alwaysHiddenSeparatorVisible = manager.alwaysHiddenSeparatorItem?.isVisible
        let separatorX = manager.geometryResolver.separatorOriginX(allowEstimatedFallback: false)
        let separatorAnchorSource = manager.geometryResolver.currentSeparatorAnchorSource()
        let mainX = manager.geometryResolver.mainStatusItemLeftEdgeX()
        let mainAnchorSource = manager.geometryResolver.currentMainStatusItemAnchorSource()
        let mainWindow = mainItem?.button?.window
        let runtimeScreen = mainWindow?.screen ?? manager.currentRecoveryReferenceScreen()
        let mainFrameIsLive: Bool = {
            guard let frame = mainWindow?.frame else { return false }
            return MenuBarMoveGeometryPolicy.mainStatusItemFrameLooksLive(originX: frame.origin.x, width: frame.width)
        }()
        let screenWidth = runtimeScreen?.frame.width
        let notchRightSafeMinX = runtimeScreen?.auxiliaryTopRightArea?.minX
        let mainRightGap: CGFloat? = {
            guard mainFrameIsLive, let mainWindow else { return nil }
            guard let rightEdge = runtimeScreen?.frame.maxX else { return nil }
            return rightEdge - mainWindow.frame.origin.x
        }()
        let alwaysHiddenSeparatorMisordered = MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
            hasAlwaysHiddenSeparator: manager.alwaysHiddenSeparatorItem != nil,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
        )
        let hasInvisibleRequiredItems =
            mainItemVisible == false ||
            separatorItemVisible == false ||
            (
                manager.currentEffectiveAlwaysHiddenSectionEnabled() &&
                    manager.alwaysHiddenSeparatorItem != nil &&
                    alwaysHiddenSeparatorVisible == false
            )
        let structuralState: MenuBarStructuralState = {
            guard mainItem != nil, separator != nil else { return .missingItems }
            guard !hasInvisibleRequiredItems else { return .invisibleItems }
            guard startupItemsValid else { return .unattachedWindows }
            return .ready
        }()

        let geometryConfidence: MenuBarGeometryConfidence = {
            if structuralState != .ready {
                switch structuralState {
                case .missingItems:
                    return .missing
                case .invisibleItems:
                    return .missing
                case .unattachedWindows:
                    return .stale
                case .ready:
                    break
                }
            }
            guard separatorX != nil, mainX != nil else { return .missing }
            guard !alwaysHiddenSeparatorMisordered else { return .stale }
            if MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: separatorX,
                mainX: mainX,
                mainRightGap: mainRightGap,
                screenWidth: screenWidth,
                notchRightSafeMinX: notchRightSafeMinX
            ) {
                return .stale
            }
            guard separatorAnchorSource.isTrustworthySeparatorAnchor else {
                return .stale
            }
            if separatorAnchorSource == .live, mainAnchorSource == .live {
                return .live
            }
            if separatorAnchorSource == .missing || mainAnchorSource == .missing {
                return .missing
            }
            return .cached
        }()
        let bootstrapPhase = resolveStatusItemBootstrapPhase(
            structuralState: structuralState,
            separatorAnchorSource: separatorAnchorSource,
            mainAnchorSource: mainAnchorSource
        )

        return MenuBarRuntimeSnapshot(
            identityPrecision: identityPrecision,
            geometryConfidence: geometryConfidence,
            structuralState: structuralState,
            separatorAnchorSource: separatorAnchorSource,
            mainAnchorSource: mainAnchorSource,
            bootstrapPhase: bootstrapPhase,
            visibilityPhase: manager.hidingService.isAnimating || manager.hidingService.isTransitioning ? .transitioning : (manager.hidingService.state == .hidden ? .hidden : .expanded),
            browsePhase: SearchWindowController.shared.isMoveInProgress ? .moveInProgress : (SearchWindowController.shared.isBrowseSessionActive ? .open : .idle),
            startupItemsValid: startupItemsValid,
            hasAlwaysHiddenSeparator: manager.alwaysHiddenSeparatorItem != nil,
            hasActiveMoveTask: manager.activeMoveTask?.isCancelled == false,
            hasAnyScreens: !NSScreen.screens.isEmpty,
            mainItemVisible: mainItemVisible,
            separatorItemVisible: separatorItemVisible,
            alwaysHiddenSeparatorVisible: alwaysHiddenSeparatorVisible,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
            mainX: mainX,
            mainRightGap: mainRightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX
        )
    }

    func markStatusItemsAwaitingAnchor(reason: String) {
        if manager.statusItemBootstrapPhase != .awaitingAnchor {
            logger.info("Status-item bootstrap awaiting live anchor (\(reason, privacy: .public))")
        }
        manager.statusItemBootstrapPhase = .awaitingAnchor
    }

    func currentStatusItemRecoverySnapshot() -> MenuBarRuntimeSnapshot {
        currentRuntimeSnapshot()
    }

    func logStatusItemRecoveryReason(
        _ reason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        snapshot: MenuBarRuntimeSnapshot,
        prefix: String
    ) {
        guard let reason else { return }

        switch reason {
        case .invalidStatusItems:
            logger.error("\(prefix, privacy: .public): status-item windows are invalid")
        case .missingCoordinates:
            logger.error("\(prefix, privacy: .public): live coordinates are still missing")
        case .invalidGeometry:
            logger.error(
                "\(prefix, privacy: .public): geometry drift detected (separator=\(snapshot.separatorX ?? -1, privacy: .public), main=\(snapshot.mainX ?? -1, privacy: .public), rightGap=\(snapshot.mainRightGap ?? -1, privacy: .public), width=\(snapshot.screenWidth ?? -1, privacy: .public))"
            )
        }
    }

    func executeStatusItemRecoveryAction(
        _ action: MenuBarOperationCoordinator.StatusItemRecoveryAction,
        trigger: String,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext? = nil,
        recoveryCount: Int = 0,
        validationGeneration: Int? = nil
    ) {
        let currentPositionValidationGeneration = manager.positionValidationGeneration
        if let validationGeneration,
           currentPositionValidationGeneration != validationGeneration {
            logger.debug(
                "Skipping stale status item recovery action for \(trigger, privacy: .public) (expected generation \(validationGeneration, privacy: .public), current \(currentPositionValidationGeneration, privacy: .public))"
            )
            return
        }

        switch action {
        case .captureCurrentDisplayBackup:
            manager.pendingRecoveryHideRestore = false
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(
                referenceScreen: manager.currentRecoveryReferenceScreen()
            )

        case .waitForLiveAnchor:
            manager.pendingRecoveryHideRestore = false
            logger.warning("Waiting for a live status-item anchor before running \(trigger, privacy: .public) recovery")

        case let .repairPersistedLayoutAndRecreate(reason):
            guard !manager.isExecutingStatusItemRecovery else {
                logger.warning("Skipping overlapping status item recovery action for \(trigger, privacy: .public)")
                return
            }
            manager.pendingRecoveryHideRestore = MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
                hidingState: manager.hidingService.state,
                shouldSkipHideForExternalMonitor: manager.shouldSkipHideForExternalMonitor
            )
            manager.isExecutingStatusItemRecovery = true
            manager.positionValidationGeneration += 1
            defer { manager.isExecutingStatusItemRecovery = false }
            let shouldResetPersistentState = MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: reason,
                isStartupRecovery: trigger.hasPrefix("startup-"),
                validationContext: validationContext
            )
            if !shouldResetPersistentState {
                StatusBarController.recoverStartupPositions(
                    alwaysHiddenEnabled: manager.currentEffectiveAlwaysHiddenSectionEnabled(),
                    referenceScreen: manager.currentRecoveryReferenceScreen()
                )
            }
            manager.clearCachedSeparatorGeometry()
            manager.recreateStatusItemsFromPersistedLayout(reason: trigger) {
                if shouldResetPersistentState {
                    StatusBarController.resetPersistentStatusItemState(
                        alwaysHiddenEnabled: self.manager.currentEffectiveAlwaysHiddenSectionEnabled(),
                        referenceScreen: self.manager.currentRecoveryReferenceScreen(),
                        freshAutosaveNamespace: true
                    )
                }
            }
            if let validationContext {
                schedulePositionValidation(context: validationContext, recoveryCount: recoveryCount + 1)
            }

        case .recreateFromPersistedLayout:
            guard !manager.isExecutingStatusItemRecovery else {
                logger.warning("Skipping overlapping status item recovery action for \(trigger, privacy: .public)")
                return
            }
            manager.pendingRecoveryHideRestore = MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
                hidingState: manager.hidingService.state,
                shouldSkipHideForExternalMonitor: manager.shouldSkipHideForExternalMonitor
            )
            manager.isExecutingStatusItemRecovery = true
            manager.positionValidationGeneration += 1
            defer { manager.isExecutingStatusItemRecovery = false }
            manager.recreateStatusItemsFromPersistedLayout(reason: trigger)
            if let validationContext {
                schedulePositionValidation(context: validationContext, recoveryCount: recoveryCount + 1)
            }

        case .bumpAutosaveVersion:
            guard !manager.isExecutingStatusItemRecovery else {
                logger.warning("Skipping overlapping status item recovery action for \(trigger, privacy: .public)")
                return
            }
            manager.pendingRecoveryHideRestore = MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
                hidingState: manager.hidingService.state,
                shouldSkipHideForExternalMonitor: manager.shouldSkipHideForExternalMonitor
            )
            manager.isExecutingStatusItemRecovery = true
            manager.positionValidationGeneration += 1
            defer { manager.isExecutingStatusItemRecovery = false }
            let (newMain, newSep) = manager.statusBarController.recreateItemsWithBumpedVersion(
                referenceScreen: manager.currentRecoveryReferenceScreen(),
                allowCurrentDisplayBackup: false
            )
            manager.statusBarController.onItemsRecreated?(newMain, newSep)
            if let validationContext {
                schedulePositionValidation(context: validationContext, recoveryCount: recoveryCount + 1)
            }

        case let .stop(reason):
            manager.pendingRecoveryHideRestore = false
            logger.error(
                "Status item recovery stopped after \(recoveryCount, privacy: .public) attempt(s) for \(trigger, privacy: .public); last reason=\(reason?.rawValue ?? "none", privacy: .public)"
            )

        case .keepExpanded, .performInitialHide:
            manager.pendingRecoveryHideRestore = false
        }
    }

    func schedulePositionValidation(
        context: MenuBarOperationCoordinator.PositionValidationContext = .startupFollowUp,
        recoveryCount: Int = 0
    ) {
        manager.positionValidationGeneration += 1
        let validationGeneration = manager.positionValidationGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }

            let initialDelay = MenuBarManager.statusItemValidationInitialDelaySeconds(
                context: context,
                recoveryCount: recoveryCount
            )
            let initialDelayDuration: Duration = .milliseconds(Int(initialDelay * 1000))
            let retryDelaySeconds = MenuBarManager.statusItemValidationRetryDelaySeconds(context: context)
            let retryDelay: Duration = .milliseconds(Int(retryDelaySeconds * 1000))
            let maxAttempts = MenuBarManager.statusItemValidationMaxAttempts(context: context)

            try? await Task.sleep(for: initialDelayDuration)
            guard self.manager.positionValidationGeneration == validationGeneration else {
                logger.debug("Skipping stale status item validation task for \(context.rawValue, privacy: .public)")
                return
            }

            var lastSnapshot: MenuBarRuntimeSnapshot?
            var lastAlwaysHiddenNeedsRepair = false

            for attempt in 1 ... maxAttempts {
                guard self.manager.positionValidationGeneration == validationGeneration else {
                    logger.debug("Aborting stale status item validation retry for \(context.rawValue, privacy: .public)")
                    return
                }

                let snapshot = self.currentStatusItemRecoverySnapshot()
                let recoveryReason = MenuBarOperationCoordinator.startupRecoveryReason(snapshot: snapshot)
                let alwaysHiddenNeedsRepair = self.stableSnapshotNeedsAlwaysHiddenRepair(snapshot)

                lastSnapshot = snapshot
                lastAlwaysHiddenNeedsRepair = alwaysHiddenNeedsRepair

                if recoveryReason == nil, !alwaysHiddenNeedsRepair {
                    let capturedBackup = await self.captureCurrentDisplayBackupAfterStableValidation(snapshot: snapshot)
                    if !capturedBackup {
                        logger.warning(
                            "Status item validation reached a healthy layout without a current-width backup for \(context.rawValue, privacy: .public)"
                        )
                    }
                    self.manager.schedulePostRecoveryVisibilityIntentReplay(reason: "healthy-validation-\(context.rawValue)")
                    if attempt > 1 {
                        logger.info("Status item position validation recovered after \(attempt, privacy: .public) checks")
                    }
                    return
                }

                if alwaysHiddenNeedsRepair {
                    self.logAlwaysHiddenSeparatorRecoveryNeed(
                        snapshot: snapshot,
                        prefix: "Status item validation"
                    )
                    self.manager.alwaysHiddenPinWorkflow.repairSeparatorPositionIfNeeded(reason: "position-validation-\(context.rawValue)")
                } else {
                    self.logStatusItemRecoveryReason(
                        recoveryReason,
                        snapshot: snapshot,
                        prefix: "Status item validation"
                    )
                }

                if attempt < maxAttempts {
                    try? await Task.sleep(for: retryDelay)
                }
            }

            guard self.manager.positionValidationGeneration == validationGeneration else {
                logger.debug("Skipping stale recovery escalation for \(context.rawValue, privacy: .public)")
                return
            }

            if lastAlwaysHiddenNeedsRepair {
                logger.error(
                    "Always-hidden separator remained misordered after \(maxAttempts, privacy: .public) checks — triggering persisted-layout recovery"
                )
                let action = MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                    context: context,
                    recoveryCount: recoveryCount,
                    maxRecoveryCount: MenuBarManager.maxStatusItemRecoveryCount
                )
                self.executeStatusItemRecoveryAction(
                    action,
                    trigger: "always-hidden-position-validation-\(context.rawValue)",
                    validationContext: context,
                    recoveryCount: recoveryCount,
                    validationGeneration: validationGeneration
                )
                return
            }

            let snapshot = lastSnapshot ?? self.currentStatusItemRecoverySnapshot()
            let action = MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(context),
                recoveryCount: recoveryCount,
                maxRecoveryCount: MenuBarManager.maxStatusItemRecoveryCount
            )

            if action == .waitForLiveAnchor {
                logger.warning(
                    "Status item validation is still waiting for a live anchor after \(maxAttempts, privacy: .public) checks for \(context.rawValue, privacy: .public) — retrying before recovery escalation"
                )
            } else if case .stop = action {
                logger.warning(
                    "Status item validation stopped after \(maxAttempts, privacy: .public) checks for \(context.rawValue, privacy: .public) without autosave recovery"
                )
            } else {
                logger.error(
                    "Status item remained off-menu-bar after \(maxAttempts, privacy: .public) checks — triggering autosave recovery"
                )
            }

            self.executeStatusItemRecoveryAction(
                action,
                trigger: "position-validation-\(context.rawValue)",
                validationContext: context,
                recoveryCount: recoveryCount,
                validationGeneration: validationGeneration
            )

            if action == .waitForLiveAnchor {
                self.schedulePositionValidation(context: context, recoveryCount: recoveryCount + 1)
            }
        }
    }

    private func resolveStatusItemBootstrapPhase(
        structuralState: MenuBarStructuralState,
        separatorAnchorSource: MenuBarAnchorSource,
        mainAnchorSource: MenuBarAnchorSource
    ) -> MenuBarBootstrapPhase {
        guard manager.statusItemBootstrapPhase == .awaitingAnchor else { return .steady }
        guard structuralState == .ready else { return .awaitingAnchor }
        let snapshot = MenuBarRuntimeSnapshot(
            structuralState: structuralState,
            separatorAnchorSource: separatorAnchorSource,
            mainAnchorSource: mainAnchorSource
        )
        guard snapshot.hasTrustworthyBootstrapAnchors else { return .awaitingAnchor }

        manager.statusItemBootstrapPhase = .steady
        logger.info(
            "Status-item bootstrap resolved (main=\(mainAnchorSource.rawValue, privacy: .public), separator=\(separatorAnchorSource.rawValue, privacy: .public))"
        )
        return .steady
    }

    private func stableSnapshotNeedsAlwaysHiddenRepair(_ snapshot: MenuBarRuntimeSnapshot) -> Bool {
        MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
            hasAlwaysHiddenSeparator: snapshot.hasAlwaysHiddenSeparator,
            separatorX: snapshot.separatorX,
            alwaysHiddenSeparatorX: snapshot.alwaysHiddenSeparatorX
        )
    }

    private func logAlwaysHiddenSeparatorRecoveryNeed(
        snapshot: MenuBarRuntimeSnapshot,
        prefix: String
    ) {
        logger.error(
            "\(prefix, privacy: .public): always-hidden separator misordered (ah=\(snapshot.alwaysHiddenSeparatorX ?? -1, privacy: .public), sep=\(snapshot.separatorX ?? -1, privacy: .public))"
        )
    }

    private func captureCurrentDisplayBackupAfterStableValidation(
        snapshot _: MenuBarRuntimeSnapshot,
        maxAttempts: Int = 6,
        delay: Duration = .milliseconds(150)
    ) async -> Bool {
        for attempt in 1 ... maxAttempts {
            if StatusBarController.captureCurrentDisplayPositionBackupIfPossible(
                referenceScreen: manager.currentRecoveryReferenceScreen()
            ) {
                return true
            }
            if StatusBarController.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(
                referenceScreen: manager.currentRecoveryReferenceScreen()
            ) {
                return true
            }
            if attempt < maxAttempts {
                try? await Task.sleep(for: delay)
            }
        }
        return StatusBarController.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(
            referenceScreen: manager.currentRecoveryReferenceScreen()
        )
    }
}
