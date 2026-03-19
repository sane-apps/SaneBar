import Foundation

enum MenuBarOperationCoordinator {
    struct StartupInitialInputs: Equatable, Sendable {
        let hasCompletedOnboarding: Bool
        let autoRehideEnabled: Bool
        let shouldSkipHideForExternalMonitor: Bool
        let hasConnectedExternalMonitorWithAlwaysShow: Bool
    }

    enum StartupRecoveryReason: String, Equatable, Sendable {
        case invalidStatusItems = "invalid-status-items"
        case missingCoordinates = "missing-coordinates"
        case invalidGeometry = "invalid-geometry"
    }

    enum StartupHoldReason: String, Equatable, Sendable {
        case waitingForLiveCoordinates = "waiting-for-live-coordinates"
        case autoRehideDisabled = "auto-rehide-disabled"
        case externalMonitorPolicy = "external-monitor-policy"
        case externalMonitorConnectedAlwaysShow = "external-monitor-connected-always-show"
    }

    enum StartupInitialAction: Equatable, Sendable {
        case recoverAndKeepExpanded(StartupRecoveryReason)
        case keepExpanded(StartupHoldReason)
        case performInitialHide
    }

    enum PositionValidationAction: Equatable, Sendable {
        case stable
        case repairPersistedLayoutAndRecreate
        case recreateFromPersistedLayout
        case bumpAutosaveVersion
        case stop
    }

    enum PositionValidationContext: String, Equatable, Sendable {
        case startupFollowUp = "startup-follow-up"
        case screenParametersChanged = "screen-parameters-changed"
        case manualLayoutRestore = "manual-layout-restore"
    }

    enum StatusItemRecoveryContext: Equatable, Sendable {
        case startupInitial(StartupInitialInputs)
        case positionValidation(PositionValidationContext)
        case manualLayoutRestoreRequest
    }

    enum StatusItemRecoveryAction: Equatable, Sendable {
        case keepExpanded(StartupHoldReason)
        case performInitialHide
        case captureCurrentDisplayBackup
        case repairPersistedLayoutAndRecreate(StartupRecoveryReason?)
        case recreateFromPersistedLayout(StartupRecoveryReason?)
        case bumpAutosaveVersion(StartupRecoveryReason?)
        case stop(StartupRecoveryReason?)
    }

    struct BrowseActivationPlan: Equatable, Sendable {
        let requireObservableReaction: Bool
        let forceFreshTargetResolution: Bool
        let allowImmediateFallbackCenter: Bool
        let allowWorkspaceActivationFallback: Bool
        let preferHardwareFirst: Bool
    }

    enum MoveQueueDecision: Equatable, Sendable {
        case ready
        case rejectBusy
        case rejectMoveAlreadyInFlight
        case rejectMissingAlwaysHiddenSeparator
        case rejectMissingScreenGeometry
    }

    static func startupRecoveryReason(
        snapshot: MenuBarRuntimeSnapshot
    ) -> StartupRecoveryReason? {
        if !snapshot.startupItemsValid {
            return .invalidStatusItems
        }

        guard let separatorX = snapshot.separatorX, let mainX = snapshot.mainX else {
            return .missingCoordinates
        }

        if MenuBarManager.shouldRecoverStartupPositions(
            separatorX: separatorX,
            mainX: mainX,
            mainRightGap: snapshot.mainRightGap,
            screenWidth: snapshot.screenWidth,
            notchRightSafeMinX: snapshot.notchRightSafeMinX
        ) {
            return .invalidGeometry
        }

        return nil
    }

    static func needsStartupRecovery(snapshot: MenuBarRuntimeSnapshot) -> Bool {
        startupRecoveryReason(snapshot: snapshot) != nil
    }

    static func startupInitialAction(
        snapshot: MenuBarRuntimeSnapshot,
        hasCompletedOnboarding: Bool,
        autoRehideEnabled: Bool,
        shouldSkipHideForExternalMonitor: Bool,
        hasConnectedExternalMonitorWithAlwaysShow: Bool
    ) -> StartupInitialAction {
        let inputs = StartupInitialInputs(
            hasCompletedOnboarding: hasCompletedOnboarding,
            autoRehideEnabled: autoRehideEnabled,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor,
            hasConnectedExternalMonitorWithAlwaysShow: hasConnectedExternalMonitorWithAlwaysShow
        )

        switch statusItemRecoveryAction(
            snapshot: snapshot,
            context: .startupInitial(inputs),
            recoveryCount: 0,
            maxRecoveryCount: 0
        ) {
        case let .keepExpanded(reason):
            return .keepExpanded(reason)
        case .performInitialHide:
            return .performInitialHide
        case let .repairPersistedLayoutAndRecreate(reason):
            return .recoverAndKeepExpanded(reason ?? .invalidGeometry)
        case let .recreateFromPersistedLayout(reason):
            return .recoverAndKeepExpanded(reason ?? .invalidStatusItems)
        case let .bumpAutosaveVersion(reason):
            return .recoverAndKeepExpanded(reason ?? .invalidStatusItems)
        case .captureCurrentDisplayBackup, .stop:
            return .performInitialHide
        }
    }

    static func positionValidationAction(
        snapshot: MenuBarRuntimeSnapshot,
        context: PositionValidationContext,
        recoveryCount: Int,
        maxRecoveryCount: Int
    ) -> PositionValidationAction {
        switch statusItemRecoveryAction(
            snapshot: snapshot,
            context: .positionValidation(context),
            recoveryCount: recoveryCount,
            maxRecoveryCount: maxRecoveryCount
        ) {
        case .captureCurrentDisplayBackup:
            return .stable
        case .repairPersistedLayoutAndRecreate:
            return .repairPersistedLayoutAndRecreate
        case .recreateFromPersistedLayout:
            return .recreateFromPersistedLayout
        case .bumpAutosaveVersion:
            return .bumpAutosaveVersion
        case .stop:
            return .stop
        case .keepExpanded, .performInitialHide:
            return .stable
        }
    }

    static func statusItemRecoveryAction(
        snapshot: MenuBarRuntimeSnapshot,
        context: StatusItemRecoveryContext,
        recoveryCount: Int,
        maxRecoveryCount: Int
    ) -> StatusItemRecoveryAction {
        switch context {
        case let .startupInitial(inputs):
            if let recoveryReason = startupRecoveryReason(snapshot: snapshot) {
                switch recoveryReason {
                case .missingCoordinates where inputs.hasCompletedOnboarding:
                    return .keepExpanded(.waitingForLiveCoordinates)
                default:
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }
            }

            if !inputs.autoRehideEnabled {
                return .keepExpanded(.autoRehideDisabled)
            }

            if inputs.shouldSkipHideForExternalMonitor {
                return .keepExpanded(.externalMonitorPolicy)
            }

            if inputs.hasConnectedExternalMonitorWithAlwaysShow {
                return .keepExpanded(.externalMonitorConnectedAlwaysShow)
            }

            return .performInitialHide

        case let .positionValidation(validationContext):
            guard let recoveryReason = startupRecoveryReason(snapshot: snapshot) else {
                return .captureCurrentDisplayBackup
            }

            if validationContext == .manualLayoutRestore {
                if recoveryCount == 0 {
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }

                if recoveryCount < maxRecoveryCount {
                    return .bumpAutosaveVersion(recoveryReason)
                }

                return .stop(recoveryReason)
            }

            if recoveryReason == .invalidGeometry {
                if recoveryCount == 0 {
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }

                if validationContext == .startupFollowUp, recoveryCount < maxRecoveryCount {
                    return .bumpAutosaveVersion(recoveryReason)
                }

                return .stop(recoveryReason)
            }

            if recoveryCount >= maxRecoveryCount {
                return .stop(recoveryReason)
            }

            if recoveryCount == 0 {
                return .recreateFromPersistedLayout(recoveryReason)
            }

            return .bumpAutosaveVersion(recoveryReason)

        case .manualLayoutRestoreRequest:
            if let recoveryReason = startupRecoveryReason(snapshot: snapshot) {
                return .repairPersistedLayoutAndRecreate(recoveryReason)
            }
            return .recreateFromPersistedLayout(nil)
        }
    }

    static func browseActivationPlan(
        snapshot: MenuBarRuntimeSnapshot,
        origin: SearchService.ActivationOrigin,
        isRightClick: Bool,
        didReveal: Bool,
        requestedApp: RunningApp
    ) -> BrowseActivationPlan {
        let requiresStrictVerification = didReveal ||
            snapshot.browsePhase != .idle ||
            origin == .browsePanel

        let preferHardwareFirst: Bool = {
            if isRightClick {
                return true
            }

            if origin == .browsePanel, let xPosition = requestedApp.xPosition, xPosition >= 0 {
                return false
            }

            if requestedApp.menuExtraIdentifier?.hasPrefix("com.apple.menuextra.") == true {
                return true
            }

            if requestedApp.menuExtraIdentifier == nil {
                return true
            }

            return requestedApp.bundleId.hasPrefix("com.apple.")
        }()

        return BrowseActivationPlan(
            requireObservableReaction: requiresStrictVerification,
            forceFreshTargetResolution: requiresStrictVerification,
            allowImmediateFallbackCenter: !requiresStrictVerification,
            allowWorkspaceActivationFallback: !(origin == .browsePanel && isRightClick),
            preferHardwareFirst: preferHardwareFirst
        )
    }

    static func shouldAllowSameBundleActivationFallback(
        snapshot: MenuBarRuntimeSnapshot,
        sameBundleCount: Int
    ) -> Bool {
        guard sameBundleCount > 1 else { return true }
        return snapshot.identityPrecision != .exact
    }

    static func moveQueueDecision(
        snapshot: MenuBarRuntimeSnapshot,
        requiresAlwaysHiddenSeparator: Bool
    ) -> MoveQueueDecision {
        guard snapshot.hasAnyScreens else {
            return .rejectMissingScreenGeometry
        }

        if snapshot.visibilityPhase == .transitioning {
            return .rejectBusy
        }

        if requiresAlwaysHiddenSeparator, !snapshot.hasAlwaysHiddenSeparator {
            return .rejectMissingAlwaysHiddenSeparator
        }

        if snapshot.hasActiveMoveTask {
            return .rejectMoveAlreadyInFlight
        }

        return .ready
    }
}
