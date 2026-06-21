import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarStatusItemRecoveryWorkflow")

@MainActor
final class MenuBarStatusItemRecoveryWorkflow {
    private unowned let manager: MenuBarManager

    /// Detects macOS flapping our items healthy/unhealthy (Tahoe visibility
    /// loop). While dormant, automatic validation stands down instead of
    /// fighting the OS; manual repair bypasses and clears dormancy.
    private var visibilityFlapDetector = MenuBarVisibilityFlapDetector()
    private(set) var recoveryDormantUntil: Date?

    /// Set when a wake-resume layout restore was downgraded to audit-only
    /// because geometry was not live. Surfaced in Health so the user can
    /// apply it explicitly via Repair; cleared when a physical replay runs.
    var pendingDeferredWakeRestoreReason: String?
    private var pendingWakeVisibleAllowListReplayUntil: Date?
    private static let pendingWakeVisibleAllowListReplayTTL: TimeInterval = 45

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func markWakeVisibleAllowListReplayPending(
        reason: String,
        now: Date = Date(),
        surfaceDeferredReason: Bool = true
    ) {
        pendingWakeVisibleAllowListReplayUntil = now.addingTimeInterval(Self.pendingWakeVisibleAllowListReplayTTL)
        if surfaceDeferredReason {
            pendingDeferredWakeRestoreReason = reason
        }
        logger.info("Marked wake visible allow-list replay pending (\(reason, privacy: .public))")
    }

    func clearWakeVisibleAllowListReplayPending(clearDeferredReason: Bool = true) {
        if clearDeferredReason {
            pendingDeferredWakeRestoreReason = nil
        }
        pendingWakeVisibleAllowListReplayUntil = nil
    }

    func hasPendingWakeVisibleAllowListReplay(now: Date = Date()) -> Bool {
        guard let pendingWakeVisibleAllowListReplayUntil else { return false }
        guard now <= pendingWakeVisibleAllowListReplayUntil else {
            clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)
            return false
        }
        return true
    }

    func pendingWakeVisibleAllowListReplayExpired(now: Date = Date()) -> Bool {
        guard let pendingWakeVisibleAllowListReplayUntil else { return false }
        return now > pendingWakeVisibleAllowListReplayUntil
    }

    func clearRecoveryDormancy() {
        recoveryDormantUntil = nil
        visibilityFlapDetector.reset()
    }

    nonisolated static func statusItemValidationInitialDelaySeconds(
        context: MenuBarOperationCoordinator.PositionValidationContext,
        recoveryCount: Int
    ) -> TimeInterval {
        switch context {
        case .startupFollowUp:
            return recoveryCount == 0 ? 1.5 : 2.0
        case .activeSpaceChanged:
            return recoveryCount == 0 ? 2.0 : 2.5
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
        case .startupFollowUp, .screenParametersChanged, .activeSpaceChanged, .wakeResume:
            return 0.5
        case .manualLayoutRestore:
            return 0.25
        }
    }

    nonisolated static func statusItemValidationMaxAttempts(
        context: MenuBarOperationCoordinator.PositionValidationContext
    ) -> Int {
        switch context {
        case .startupFollowUp, .screenParametersChanged, .activeSpaceChanged, .wakeResume:
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
        isStartupRecovery _: Bool = false,
        validationContext _: MenuBarOperationCoordinator.PositionValidationContext? = nil
    ) -> Bool {
        switch reason {
        case .invalidStatusItems, .missingCoordinates, .invalidGeometry:
            // Bad data (missing coordinates, invalid items/geometry) during any recovery context
            // (startup, wake, screen change, manual arrange) forces hard reset to current live
            // left-edge anchor instead of replaying stale persisted layout. This fixes dynamic
            // item jumps (#147) and post-Spotlight/arrange reordering (#150, #142).
            true
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
        let liveSeparatorFrame = manager.geometryResolver.currentLiveSeparatorFrame()
        let liveAlwaysHiddenSeparatorRightEdgeX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorFrame()
            .map { $0.origin.x + $0.width }
        let alwaysHiddenSeparatorX =
            liveAlwaysHiddenSeparatorRightEdgeX ??
            manager.geometryResolver.alwaysHiddenSeparatorBoundaryX() ??
            manager.geometryResolver.alwaysHiddenSeparatorOriginX().map { $0 + MenuBarMoveGeometryPolicy.separatorVisualWidth }
        let persistedMainDistanceFromRight = StatusBarDiagnostics.persistedMainDistanceFromRight()
        let startupItemsValid: Bool = {
            guard let mainItem, let separator else { return false }
            let mainWindow = mainItem.button?.window
            let runtimeScreen = mainWindow?.screen ?? manager.currentRecoveryReferenceScreen()
            let mainFrameIsLive: Bool = {
                guard let mainWindow else { return false }
                // Liveness is judged against the window's OWN screen; the
                // recovery reference screen is only a fallback for gap math.
                return MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
                    frame: mainWindow.frame,
                    screenFrame: mainWindow.screen?.frame
                )
            }()
            let mainRightGap: CGFloat? = {
                guard mainFrameIsLive, let mainWindow else { return nil }
                guard let rightEdge = mainWindow.screen?.frame.maxX else { return nil }
                return rightEdge - mainWindow.frame.origin.x
            }()
            let mainWindowValid = StatusBarController.validateItemPosition(mainItem)
            let separatorWindowValid = StatusBarController.validateItemPosition(separator)
            let hiddenCollapsedSeparatorHealthy = StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
                hidingState: manager.hidingService.state,
                mainWindowValid: mainWindowValid,
                separatorVisible: separator.isVisible,
                separatorX: manager.geometryResolver.separatorOriginX(allowEstimatedFallback: false),
                mainX: manager.geometryResolver.mainStatusItemLeftEdgeX(),
                mainRightGap: mainRightGap,
                screenWidth: runtimeScreen?.frame.width,
                notchRightSafeMinX: runtimeScreen?.auxiliaryTopRightArea?.minX,
                persistedMainDistanceFromRight: persistedMainDistanceFromRight
            ))
            return mainWindowValid && (separatorWindowValid || hiddenCollapsedSeparatorHealthy)
        }()
        let mainItemVisible = mainItem?.isVisible
        let separatorItemVisible = separator?.isVisible
        let alwaysHiddenSeparatorVisible = manager.alwaysHiddenSeparatorItem?.isVisible
        let likelySystemSuppressedStatusItems: Bool = {
            let mainWindow = mainItem?.button?.window
            let separatorWindow = separator?.button?.window
            return StatusBarDiagnostics.likelySystemSuppressedStatusItems(
                startupItemsValid: startupItemsValid,
                main: .init(
                    isVisibleFlag: mainItemVisible,
                    windowFrame: mainWindow?.frame,
                    screenFrame: mainWindow?.screen?.frame
                ),
                separator: .init(
                    isVisibleFlag: separatorItemVisible,
                    windowFrame: separatorWindow?.frame,
                    screenFrame: separatorWindow?.screen?.frame
                )
            )
        }()
        let separatorX = manager.geometryResolver.separatorOriginX(allowEstimatedFallback: false)
        let separatorAnchorSource = manager.geometryResolver.currentSeparatorAnchorSource()
        let mainX = manager.geometryResolver.mainStatusItemLeftEdgeX()
        let mainAnchorSource = manager.geometryResolver.currentMainStatusItemAnchorSource()
        let mainWindow = mainItem?.button?.window
        let runtimeScreen = mainWindow?.screen ?? manager.currentRecoveryReferenceScreen()
        let mainFrameIsLive: Bool = {
            guard let mainWindow else { return false }
            return MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
                frame: mainWindow.frame,
                screenFrame: mainWindow.screen?.frame
            )
        }()
        let screenWidth = runtimeScreen?.frame.width
        let notchRightSafeMinX = runtimeScreen?.auxiliaryTopRightArea?.minX
        let mainRightGap: CGFloat? = {
            guard mainFrameIsLive, let mainWindow else { return nil }
            guard let rightEdge = mainWindow.screen?.frame.maxX else { return nil }
            return rightEdge - mainWindow.frame.origin.x
        }()
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
        let visibilityPhase: MenuBarVisibilityPhase =
            manager.hidingService.isAnimating || manager.hidingService.isTransitioning
                ? .transitioning
                : (manager.hidingService.state == .hidden ? .hidden : .expanded)

        let geometrySnapshot = MenuBarRuntimeSnapshot(
            structuralState: structuralState,
            separatorAnchorSource: separatorAnchorSource,
            mainAnchorSource: mainAnchorSource,
            visibilityPhase: visibilityPhase,
            startupItemsValid: startupItemsValid,
            hasAlwaysHiddenSeparator: manager.alwaysHiddenSeparatorItem != nil,
            likelySystemSuppressedStatusItems: likelySystemSuppressedStatusItems,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
            mainX: mainX,
            mainRightGap: mainRightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX,
            persistedMainDistanceFromRight: persistedMainDistanceFromRight
        )
        let alwaysHiddenSeparatorMisordered = Self.alwaysHiddenMisorderNeedsRecovery(
            snapshot: geometrySnapshot,
            liveSeparatorX: liveSeparatorFrame?.origin.x,
            liveAlwaysHiddenSeparatorRightEdgeX: liveAlwaysHiddenSeparatorRightEdgeX
        )
        let geometryConfidence = Self.resolvedGeometryConfidence(
            for: geometrySnapshot,
            hidingState: manager.hidingService.state,
            alwaysHiddenSeparatorMisordered: alwaysHiddenSeparatorMisordered
        )
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
            visibilityPhase: visibilityPhase,
            browsePhase: SearchWindowController.shared.isMoveInProgress ? .moveInProgress : (SearchWindowController.shared.isBrowseSessionActive ? .open : .idle),
            startupItemsValid: startupItemsValid,
            hasAlwaysHiddenSeparator: manager.alwaysHiddenSeparatorItem != nil,
            hasActiveMoveTask: manager.activeMoveTask?.isCancelled == false,
            hasAnyScreens: !NSScreen.screens.isEmpty,
            mainItemVisible: mainItemVisible,
            separatorItemVisible: separatorItemVisible,
            alwaysHiddenSeparatorVisible: alwaysHiddenSeparatorVisible,
            likelySystemSuppressedStatusItems: likelySystemSuppressedStatusItems,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX,
            mainX: mainX,
            mainRightGap: mainRightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX,
            persistedMainDistanceFromRight: persistedMainDistanceFromRight
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

    nonisolated static func resolvedGeometryConfidence(
        for snapshot: MenuBarRuntimeSnapshot,
        hidingState: HidingState,
        alwaysHiddenSeparatorMisordered: Bool
    ) -> MenuBarGeometryConfidence {
        if snapshot.structuralState != .ready {
            switch snapshot.structuralState {
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
        guard snapshot.separatorX != nil, snapshot.mainX != nil else { return .missing }
        guard !alwaysHiddenSeparatorMisordered else { return .stale }
        if MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: snapshot.separatorX,
            mainX: snapshot.mainX,
            mainRightGap: snapshot.mainRightGap,
            screenWidth: snapshot.screenWidth,
            notchRightSafeMinX: snapshot.notchRightSafeMinX,
            persistedMainDistanceFromRight: snapshot.persistedMainDistanceFromRight
        ) {
            if hiddenPresentationHasHealthyCollapsedSeparator(
                snapshot: snapshot,
                hidingState: hidingState,
                allowStartupPositionDrift: true
            ) {
                return .shielded
            }
            return .stale
        }
        if !snapshot.separatorAnchorSource.isTrustworthySeparatorAnchor {
            if hiddenPresentationHasHealthyCollapsedSeparator(
                snapshot: snapshot,
                hidingState: hidingState
            ) {
                return .cached
            }
            return .stale
        }
        if snapshot.separatorAnchorSource == .live, snapshot.mainAnchorSource == .live {
            return .live
        }
        if snapshot.separatorAnchorSource == .missing || snapshot.mainAnchorSource == .missing {
            return .missing
        }
        return .cached
    }

    nonisolated static func alwaysHiddenMisorderNeedsRecovery(
        snapshot: MenuBarRuntimeSnapshot,
        liveSeparatorX: CGFloat?,
        liveAlwaysHiddenSeparatorRightEdgeX: CGFloat?
    ) -> Bool {
        guard snapshot.structuralState == .ready,
              snapshot.startupItemsValid,
              snapshot.hasAlwaysHiddenSeparator,
              snapshot.visibilityPhase != .transitioning,
              snapshot.separatorAnchorSource == .live,
              snapshot.mainAnchorSource != .missing
        else {
            return false
        }

        return MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
            hasAlwaysHiddenSeparator: snapshot.hasAlwaysHiddenSeparator,
            separatorX: liveSeparatorX,
            alwaysHiddenSeparatorRightEdgeX: liveAlwaysHiddenSeparatorRightEdgeX,
            notchRightSafeMinX: snapshot.notchRightSafeMinX
        )
    }

    private nonisolated static func hiddenPresentationHasHealthyCollapsedSeparator(
        snapshot: MenuBarRuntimeSnapshot,
        hidingState: HidingState,
        allowStartupPositionDrift: Bool = false
    ) -> Bool {
        guard hidingState == .hidden else { return false }
        let hiddenStructureHealthy =
            snapshot.structuralState == .ready &&
            snapshot.startupItemsValid
        guard snapshot.separatorAnchorSource == .live ||
            (snapshot.separatorAnchorSource == .cached && hiddenStructureHealthy) else { return false }
        guard snapshot.mainAnchorSource != .missing else { return false }
        let startupPositionDrift = MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: snapshot.separatorX,
            mainX: snapshot.mainX,
            mainRightGap: snapshot.mainRightGap,
            screenWidth: snapshot.screenWidth,
            notchRightSafeMinX: snapshot.notchRightSafeMinX,
            persistedMainDistanceFromRight: snapshot.persistedMainDistanceFromRight
        )
        guard !startupPositionDrift || allowStartupPositionDrift else {
            return false
        }
        if startupPositionDrift, allowStartupPositionDrift {
            guard let separatorX = snapshot.separatorX,
                  let mainX = snapshot.mainX,
                  separatorX.isFinite,
                  mainX.isFinite,
                  separatorX < mainX else {
                return false
            }
            return true
        }
        return StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
            hidingState: hidingState,
            mainWindowValid: true,
            separatorVisible: true,
            separatorX: snapshot.separatorX,
            mainX: snapshot.mainX,
            mainRightGap: snapshot.mainRightGap,
            screenWidth: snapshot.screenWidth,
            notchRightSafeMinX: snapshot.notchRightSafeMinX,
            persistedMainDistanceFromRight: snapshot.persistedMainDistanceFromRight
        ))
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
            StatusBarPositionStore.captureCurrentDisplayPositionBackupIfPossible(
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
                StatusBarPositionRecoveryStore.recoverStartupPositions(
                    alwaysHiddenEnabled: manager.currentEffectiveAlwaysHiddenSectionEnabled(),
                    referenceScreen: manager.currentRecoveryReferenceScreen()
                )
            }
            manager.clearCachedSeparatorGeometry()
            manager.recreateStatusItemsFromPersistedLayout(reason: trigger) {
                if shouldResetPersistentState {
                    StatusBarPositionRecoveryStore.resetPersistentStatusItemState(
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
            manager.clearCachedSeparatorGeometry()
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
            surfaceHealthFallbackAfterRecoveryStopIfNeeded(
                reason: reason,
                trigger: trigger,
                validationContext: validationContext,
                recoveryCount: recoveryCount
            )

        case .keepExpanded, .performInitialHide:
            manager.pendingRecoveryHideRestore = false
        }
    }

    private func surfaceHealthFallbackAfterRecoveryStopIfNeeded(
        reason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        trigger: String,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext?,
        recoveryCount: Int
    ) {
        guard MenuBarVisibilityPolicy.shouldSurfaceHealthAfterStatusItemRecoveryStop(
            recoveryReason: reason,
            recoveryCount: recoveryCount,
            validationContext: validationContext
        ) else { return }

        logger.error(
            "Opening Health fallback after unrecoverable status-item recovery failure for \(trigger, privacy: .public)"
        )
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        SettingsOpener.open(tab: .health)
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

            if let dormantUntil = self.recoveryDormantUntil {
                if context == .manualLayoutRestore || Date() >= dormantUntil {
                    self.clearRecoveryDormancy()
                } else {
                    logger.warning(
                        "Status item validation dormant (visibility flap) — skipping \(context.rawValue, privacy: .public)"
                    )
                    return
                }
            }

            var lastSnapshot: MenuBarRuntimeSnapshot?
            var lastAlwaysHiddenNeedsRepair = false

            for attempt in 1 ... maxAttempts {
                guard self.manager.positionValidationGeneration == validationGeneration else {
                    logger.debug("Aborting stale status item validation retry for \(context.rawValue, privacy: .public)")
                    return
                }

                let snapshot = self.currentStatusItemRecoverySnapshot()
                let recoveryReason = MenuBarOperationCoordinator.positionValidationRecoveryReason(snapshot: snapshot)
                let alwaysHiddenNeedsRepair = self.stableSnapshotNeedsAlwaysHiddenRepair(snapshot)

                self.visibilityFlapDetector.record(itemsHealthy: recoveryReason == nil, at: Date())
                if self.visibilityFlapDetector.isFlapping(now: Date()) {
                    self.recoveryDormantUntil = Date().addingTimeInterval(
                        MenuBarVisibilityFlapDetector.defaultDormancySeconds
                    )
                    self.manager.pendingRecoveryHideRestore = false
                    logger.error(
                        "macOS appears to be flapping status-item visibility — standing down recovery for \(Int(MenuBarVisibilityFlapDetector.defaultDormancySeconds), privacy: .public)s. If SaneBar's icons are missing, check System Settings > Menu Bar > Allow in Menu Bar for SaneBar."
                    )
                    return
                }

                lastSnapshot = snapshot
                lastAlwaysHiddenNeedsRepair = alwaysHiddenNeedsRepair

                if recoveryReason == nil, !alwaysHiddenNeedsRepair {
                    let capturedBackup = await self.captureCurrentDisplayBackupAfterStableValidation(snapshot: snapshot)
                    if !capturedBackup {
                        logger.warning(
                            "Status item validation reached a healthy layout without a current-width backup for \(context.rawValue, privacy: .public)"
                        )
                    }
                    self.manager.restoreHiddenStateAfterHealthyValidationIfNeeded(reason: "healthy-validation-\(context.rawValue)")
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
            if MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: snapshot,
                validationContext: context,
                action: action
            ) {
                self.manager.markWakeVisibleAllowListReplayPending(
                    reason: "runtime-attachment-loss-\(context.rawValue)"
                )
            }

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
        let liveSeparatorFrame = manager.geometryResolver.currentLiveSeparatorFrame()
        let liveAlwaysHiddenFrame = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorFrame()
        return Self.alwaysHiddenMisorderNeedsRecovery(
            snapshot: snapshot,
            liveSeparatorX: liveSeparatorFrame?.origin.x,
            liveAlwaysHiddenSeparatorRightEdgeX: liveAlwaysHiddenFrame.map { $0.origin.x + $0.width }
        )
    }

    private func logAlwaysHiddenSeparatorRecoveryNeed(
        snapshot: MenuBarRuntimeSnapshot,
        prefix: String
    ) {
        logger.error(
            "\(prefix, privacy: .public): always-hidden separator misordered (ahRight=\(snapshot.alwaysHiddenSeparatorX ?? -1, privacy: .public), sep=\(snapshot.separatorX ?? -1, privacy: .public))"
        )
    }

    private func captureCurrentDisplayBackupAfterStableValidation(
        snapshot _: MenuBarRuntimeSnapshot,
        maxAttempts: Int = 6,
        delay: Duration = .milliseconds(150)
    ) async -> Bool {
        for attempt in 1 ... maxAttempts {
            if StatusBarPositionStore.captureCurrentDisplayPositionBackupIfPossible(
                referenceScreen: manager.currentRecoveryReferenceScreen()
            ) {
                return true
            }
            if StatusBarPositionStore.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(
                referenceScreen: manager.currentRecoveryReferenceScreen()
            ) {
                return true
            }
            if attempt < maxAttempts {
                try? await Task.sleep(for: delay)
            }
        }
        return StatusBarPositionStore.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(
            referenceScreen: manager.currentRecoveryReferenceScreen()
        )
    }
}
