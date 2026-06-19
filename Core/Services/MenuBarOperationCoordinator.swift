import Foundation

enum MenuBarOperationCoordinator {
    struct StartupInitialInputs: Equatable {
        let hasCompletedOnboarding: Bool
        let autoRehideEnabled: Bool
        let shouldSkipHideForExternalMonitor: Bool
        let hasConnectedExternalMonitorWithAlwaysShow: Bool
    }

    enum StartupRecoveryReason: String, Equatable {
        case invalidStatusItems = "invalid-status-items"
        case missingCoordinates = "missing-coordinates"
        case invalidGeometry = "invalid-geometry"
    }

    enum StartupHoldReason: String, Equatable {
        case waitingForLiveCoordinates = "waiting-for-live-coordinates"
        case autoRehideDisabled = "auto-rehide-disabled"
        case externalMonitorPolicy = "external-monitor-policy"
        case externalMonitorConnectedAlwaysShow = "external-monitor-connected-always-show"
    }

    enum StartupInitialAction: Equatable {
        case recoverAndKeepExpanded(StartupRecoveryReason)
        case keepExpanded(StartupHoldReason)
        case performInitialHide
    }

    enum PositionValidationAction: Equatable {
        case stable
        case waitForLiveAnchor
        case repairPersistedLayoutAndRecreate
        case recreateFromPersistedLayout
        case bumpAutosaveVersion
        case stop
    }

    enum PositionValidationContext: String, Equatable {
        case startupFollowUp = "startup-follow-up"
        case screenParametersChanged = "screen-parameters-changed"
        case activeSpaceChanged = "active-space-changed"
        case wakeResume = "wake-resume"
        case manualLayoutRestore = "manual-layout-restore"
    }

    enum StatusItemRecoveryContext: Equatable {
        case startupInitial(StartupInitialInputs)
        case positionValidation(PositionValidationContext)
        case manualLayoutRestoreRequest
    }

    enum StatusItemRecoveryAction: Equatable {
        case keepExpanded(StartupHoldReason)
        case performInitialHide
        case captureCurrentDisplayBackup
        case waitForLiveAnchor
        case repairPersistedLayoutAndRecreate(StartupRecoveryReason?)
        case recreateFromPersistedLayout(StartupRecoveryReason?)
        case bumpAutosaveVersion(StartupRecoveryReason?)
        case stop(StartupRecoveryReason?)
    }

    struct BrowseActivationPlan: Equatable {
        let requireObservableReaction: Bool
        let forceFreshTargetResolution: Bool
        let allowImmediateFallbackCenter: Bool
        let allowWorkspaceActivationFallback: Bool
        let preferHardwareFirst: Bool
    }

    enum MoveQueueDecision: Equatable {
        case ready
        case rejectBusy
        case rejectInvalidStatusItems
        case rejectAwaitingAnchor
        case rejectMoveAlreadyInFlight
        case rejectMissingAlwaysHiddenSeparator
        case rejectMissingScreenGeometry
    }

    static func startupRecoveryReason(
        snapshot: MenuBarRuntimeSnapshot
    ) -> StartupRecoveryReason? {
        if snapshot.structuralState != .ready {
            return .invalidStatusItems
        }

        if !snapshot.hasTrustworthyBootstrapAnchors {
            return .missingCoordinates
        }

        guard let separatorX = snapshot.separatorX, let mainX = snapshot.mainX else {
            return .missingCoordinates
        }

        if MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: separatorX,
            mainX: mainX,
            mainRightGap: snapshot.mainRightGap,
            screenWidth: snapshot.screenWidth,
            notchRightSafeMinX: snapshot.notchRightSafeMinX,
            persistedMainDistanceFromRight: snapshot.persistedMainDistanceFromRight
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
        case .waitForLiveAnchor:
            return .keepExpanded(.waitingForLiveCoordinates)
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
            .stable
        case .waitForLiveAnchor:
            .waitForLiveAnchor
        case .repairPersistedLayoutAndRecreate:
            .repairPersistedLayoutAndRecreate
        case .recreateFromPersistedLayout:
            .recreateFromPersistedLayout
        case .bumpAutosaveVersion:
            .bumpAutosaveVersion
        case .stop:
            .stop
        case .keepExpanded, .performInitialHide:
            .stable
        }
    }

    static func alwaysHiddenMisorderRecoveryAction(
        context: PositionValidationContext,
        recoveryCount: Int,
        maxRecoveryCount: Int
    ) -> StatusItemRecoveryAction {
        if context == .manualLayoutRestore {
            if recoveryCount == 0 {
                return .repairPersistedLayoutAndRecreate(.invalidGeometry)
            }

            if recoveryCount < maxRecoveryCount {
                return .bumpAutosaveVersion(.invalidGeometry)
            }

            return .stop(.invalidGeometry)
        }

        if recoveryCount == 0 {
            return .repairPersistedLayoutAndRecreate(.invalidGeometry)
        }

        if context == .startupFollowUp ||
            context == .screenParametersChanged ||
            context == .activeSpaceChanged ||
            context == .wakeResume,
            recoveryCount < maxRecoveryCount {
            return .bumpAutosaveVersion(.invalidGeometry)
        }

        return .stop(.invalidGeometry)
    }

    static func shouldWaitForLiveSeparatorAnchor(
        snapshot: MenuBarRuntimeSnapshot,
        validationContext: PositionValidationContext,
        recoveryReason: StartupRecoveryReason,
        recoveryCount: Int
    ) -> Bool {
        isRuntimeMissingCoordinateState(
            snapshot: snapshot,
            validationContext: validationContext,
            recoveryReason: recoveryReason
        ) && recoveryCount == 0
    }

    static func isRuntimeMissingCoordinateState(
        snapshot: MenuBarRuntimeSnapshot,
        validationContext: PositionValidationContext,
        recoveryReason: StartupRecoveryReason
    ) -> Bool {
        guard recoveryReason == .missingCoordinates else { return false }
        guard validationContext == .screenParametersChanged ||
            validationContext == .activeSpaceChanged ||
            validationContext == .wakeResume else { return false }
        guard snapshot.structuralState == .ready else { return false }
        return true
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
                case .invalidStatusItems where inputs.hasCompletedOnboarding:
                    if snapshot.likelySystemSuppressedStatusItems {
                        return .keepExpanded(.waitingForLiveCoordinates)
                    }
                    if snapshot.structuralState == .unattachedWindows,
                       snapshot.separatorX != nil || snapshot.mainX != nil {
                        return .keepExpanded(.waitingForLiveCoordinates)
                    }
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                case .missingCoordinates:
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

            if recoveryReason == .invalidStatusItems,
               snapshot.likelySystemSuppressedStatusItems {
                // One repair attempt is allowed so affected users are not left
                // without any in-app recovery path (#152); further attempts stop
                // to avoid autosave churn while macOS suppresses the items.
                if recoveryCount == 0 {
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }
                return .stop(recoveryReason)
            }

            if recoveryReason == .invalidStatusItems,
               validationContext == .screenParametersChanged ||
               validationContext == .activeSpaceChanged ||
               validationContext == .wakeResume {
                if recoveryCount == 0 {
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }
                if recoveryCount < maxRecoveryCount {
                    return .bumpAutosaveVersion(recoveryReason)
                }
                return .stop(recoveryReason)
            }

            if shouldWaitForLiveSeparatorAnchor(
                snapshot: snapshot,
                validationContext: validationContext,
                recoveryReason: recoveryReason,
                recoveryCount: recoveryCount
            ) {
                return .waitForLiveAnchor
            }

            if isRuntimeMissingCoordinateState(
                snapshot: snapshot,
                validationContext: validationContext,
                recoveryReason: recoveryReason
            ) {
                if recoveryCount == 1 {
                    return .recreateFromPersistedLayout(recoveryReason)
                }
                if recoveryCount == 2 {
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }
                if recoveryCount < maxRecoveryCount {
                    return .bumpAutosaveVersion(recoveryReason)
                }
                return .stop(recoveryReason)
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

            if validationContext == .startupFollowUp {
                switch recoveryReason {
                case .invalidGeometry:
                    break
                case .invalidStatusItems, .missingCoordinates:
                    if recoveryCount == 0 {
                        return .repairPersistedLayoutAndRecreate(recoveryReason)
                    }
                    if recoveryCount < maxRecoveryCount {
                        return .bumpAutosaveVersion(recoveryReason)
                    }
                    return .stop(recoveryReason)
                }
            }

            if recoveryReason == .invalidGeometry {
                if recoveryCount == 0 {
                    return .repairPersistedLayoutAndRecreate(recoveryReason)
                }

                if validationContext == .startupFollowUp ||
                    validationContext == .screenParametersChanged ||
                    validationContext == .activeSpaceChanged ||
                    validationContext == .wakeResume,
                    recoveryCount < maxRecoveryCount {
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
                // An explicit user repair request always attempts the full
                // repair, even when macOS suppression is suspected (#152) —
                // a single user-initiated reset cannot churn autosave state.
                return .repairPersistedLayoutAndRecreate(recoveryReason)
            }
            return .recreateFromPersistedLayout(nil)
        }
    }

    static func browseActivationPlan(
        snapshot: MenuBarRuntimeSnapshot,
        origin: SearchServiceSupport.ActivationOrigin,
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

            if origin == .browsePanel {
                return true
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
            allowWorkspaceActivationFallback: origin != .browsePanel,
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

    private static func moveQueueHasUsableStructuralState(
        snapshot: MenuBarRuntimeSnapshot
    ) -> Bool {
        if snapshot.structuralState == .ready {
            return true
        }

        // Hidden presentation can make the separator window look detached until
        // the move workflow runs its showAll shield. Exact identity is required
        // so this exception cannot mask broad/ambiguous recovery failures.
        return snapshot.visibilityPhase == .hidden &&
            snapshot.identityPrecision == .exact &&
            snapshot.structuralState == .unattachedWindows &&
            snapshot.mainItemVisible == true &&
            snapshot.separatorItemVisible == true
    }

    static func moveQueueDecision(
        snapshot: MenuBarRuntimeSnapshot,
        requiresAlwaysHiddenSeparator: Bool
    ) -> MoveQueueDecision {
        guard snapshot.hasAnyScreens else {
            return .rejectMissingScreenGeometry
        }

        if !moveQueueHasUsableStructuralState(snapshot: snapshot) {
            return .rejectInvalidStatusItems
        }

        if snapshot.visibilityPhase == .transitioning {
            return .rejectBusy
        }

        if snapshot.bootstrapPhase == .awaitingAnchor {
            return .rejectAwaitingAnchor
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
