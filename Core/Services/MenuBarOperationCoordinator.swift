import Foundation

enum MenuBarOperationCoordinator {
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
        if let recoveryReason = startupRecoveryReason(snapshot: snapshot) {
            switch recoveryReason {
            case .missingCoordinates where hasCompletedOnboarding:
                return .keepExpanded(.waitingForLiveCoordinates)
            default:
                return .recoverAndKeepExpanded(recoveryReason)
            }
        }

        if !autoRehideEnabled {
            return .keepExpanded(.autoRehideDisabled)
        }

        if shouldSkipHideForExternalMonitor {
            return .keepExpanded(.externalMonitorPolicy)
        }

        if hasConnectedExternalMonitorWithAlwaysShow {
            return .keepExpanded(.externalMonitorConnectedAlwaysShow)
        }

        return .performInitialHide
    }

    static func positionValidationAction(
        snapshot: MenuBarRuntimeSnapshot,
        context: PositionValidationContext,
        recoveryCount: Int,
        maxRecoveryCount: Int
    ) -> PositionValidationAction {
        guard let recoveryReason = startupRecoveryReason(snapshot: snapshot) else {
            return .stable
        }

        if recoveryReason == .invalidGeometry {
            if recoveryCount == 0 {
                return .repairPersistedLayoutAndRecreate
            }

            if context == .startupFollowUp, recoveryCount < maxRecoveryCount {
                return .bumpAutosaveVersion
            }

            return .stop
        }

        if recoveryCount >= maxRecoveryCount {
            return .stop
        }

        if recoveryCount == 0 {
            return .recreateFromPersistedLayout
        }

        return .bumpAutosaveVersion
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
