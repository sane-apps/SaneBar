import Testing
@testable import SaneBar

@Suite("Menu Bar Operation Coordinator Tests")
struct MenuBarOperationCoordinatorTests {
    @Test("Startup recovery is required for stale geometry")
    func startupRecoveryTriggersForInvalidGeometry() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: true,
            separatorX: 120,
            mainX: 100,
            mainRightGap: 400,
            screenWidth: 1440
        )

        #expect(MenuBarOperationCoordinator.startupRecoveryReason(snapshot: snapshot) == .invalidGeometry)
    }

    @Test("Startup waits for live coordinates after onboarding instead of hiding blindly")
    func startupHoldsExpandedWhenCoordinatesAreStillMissing() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            startupItemsValid: true,
            separatorX: nil,
            mainX: nil
        )

        let action = MenuBarOperationCoordinator.statusItemRecoveryAction(
            snapshot: snapshot,
            context: .startupInitial(.init(
                hasCompletedOnboarding: true,
                autoRehideEnabled: true,
                shouldSkipHideForExternalMonitor: false,
                hasConnectedExternalMonitorWithAlwaysShow: false
            )),
            recoveryCount: 0,
            maxRecoveryCount: 2
        )

        guard case .keepExpanded(.waitingForLiveCoordinates) = action else {
            Issue.record("Expected startup to hold expanded while waiting for live coordinates")
            return
        }
    }

    @Test("Startup waits when status-item windows are still unattached after onboarding")
    func startupHoldsExpandedWhenStatusItemWindowsAreStillMissing() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: false,
            separatorX: 160,
            mainX: 180
        )

        let action = MenuBarOperationCoordinator.statusItemRecoveryAction(
            snapshot: snapshot,
            context: .startupInitial(.init(
                hasCompletedOnboarding: true,
                autoRehideEnabled: true,
                shouldSkipHideForExternalMonitor: false,
                hasConnectedExternalMonitorWithAlwaysShow: false
            )),
            recoveryCount: 0,
            maxRecoveryCount: 2
        )

        guard case .keepExpanded(.waitingForLiveCoordinates) = action else {
            Issue.record("Expected startup to hold expanded while waiting for unattached status-item windows")
            return
        }
    }

    @Test("Startup follow-up repairs persisted geometry before recreating live items")
    func startupValidationRepairsGeometryBeforeRecreate() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: true,
            separatorX: 956,
            mainX: 976,
            mainRightGap: 944,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
    }

    @Test("Always-hidden startup drift escalates to a fresh autosave namespace after one failed repair")
    func alwaysHiddenStartupValidationBumpsAutosaveVersionAfterRetry() {
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .startupFollowUp,
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .startupFollowUp,
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
    }

    @Test("Always-hidden runtime drift stays bounded outside startup")
    func alwaysHiddenRuntimeValidationStopsAfterOneRepair() {
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .screenParametersChanged,
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .screenParametersChanged,
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .stop(.invalidGeometry)
        )
    }

    @Test("Screen-change geometry drift stays bounded after one failed repair")
    func runtimeValidationBoundsGeometryDriftForScreenChanges() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: true,
            separatorX: 956,
            mainX: 976,
            mainRightGap: 944,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .stop(.invalidGeometry)
        )
    }

    @Test("Wake validation stays bounded after one failed repair")
    func wakeValidationBoundsGeometryDrift() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: true,
            separatorX: 956,
            mainX: 976,
            mainRightGap: 944,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .stop(.invalidGeometry)
        )
    }

    @Test("Startup follow-up escalates persistent missing coordinates and invalid items after the retry window")
    func startupValidationEscalatesPersistentMissingCoordinateState() {
        let missingCoordinateSnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            startupItemsValid: true,
            separatorX: nil,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )
        let invalidItemSnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: false,
            separatorX: 1661,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: missingCoordinateSnapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: invalidItemSnapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: missingCoordinateSnapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .bumpAutosaveVersion(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: invalidItemSnapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .bumpAutosaveVersion(.invalidStatusItems)
        )
    }

    @Test("Manual restore skips repair path when the snapshot is already healthy")
    func manualRestoreUsesDirectReplayWhenHealthy() {
        let healthySnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .live,
            startupItemsValid: true,
            separatorX: 160,
            mainX: 180,
            mainRightGap: 200,
            screenWidth: 1440
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: healthySnapshot,
                context: .manualLayoutRestoreRequest,
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .recreateFromPersistedLayout(nil)
        )
    }

    @Test("Manual restore still repairs persisted layout when geometry is unhealthy")
    func manualRestoreUsesRepairPathWhenSnapshotIsUnhealthy() {
        let unhealthySnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: true,
            separatorX: 956,
            mainX: 976,
            mainRightGap: 944,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: unhealthySnapshot,
                context: .manualLayoutRestoreRequest,
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidGeometry)
        )
    }

    @Test("Browse panel right click uses strict verification and no workspace fallback")
    func browsePanelRightClickPlanStaysStrict() {
        let app = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Wi-Fi",
            identifier: "com.apple.menuextra.wifi",
            xPosition: 1400,
            width: 24
        )

        let plan = MenuBarOperationCoordinator.browseActivationPlan(
            snapshot: MenuBarRuntimeSnapshot(
                identityPrecision: .exact,
                geometryConfidence: .live,
                visibilityPhase: .expanded,
                browsePhase: .activationInFlight
            ),
            origin: .browsePanel,
            isRightClick: true,
            didReveal: false,
            requestedApp: app
        )

        #expect(plan.requireObservableReaction)
        #expect(plan.forceFreshTargetResolution)
        #expect(plan.allowImmediateFallbackCenter == false)
        #expect(plan.allowWorkspaceActivationFallback == false)
        #expect(plan.preferHardwareFirst)
    }

    @Test("Same-bundle fallback is rejected when the original identity was precise")
    func sameBundleFallbackRejectsPreciseIdentityLoss() {
        #expect(
            !MenuBarOperationCoordinator.shouldAllowSameBundleActivationFallback(
                snapshot: MenuBarRuntimeSnapshot(identityPrecision: .exact),
                sameBundleCount: 2
            )
        )
        #expect(
            MenuBarOperationCoordinator.shouldAllowSameBundleActivationFallback(
                snapshot: MenuBarRuntimeSnapshot(identityPrecision: .coarse),
                sameBundleCount: 2
            )
        )
    }

    @Test("Move queue decision rejects only busy or impossible runtime state")
    func moveQueueDecisionRejectsBusyStates() {
        let busySnapshot = MenuBarRuntimeSnapshot(
            visibilityPhase: .transitioning,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: false,
            hasAnyScreens: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: busySnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .rejectBusy
        )

        let missingSeparatorSnapshot = MenuBarRuntimeSnapshot(
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: false,
            hasActiveMoveTask: false,
            hasAnyScreens: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: missingSeparatorSnapshot,
                requiresAlwaysHiddenSeparator: true
            ) == .rejectMissingAlwaysHiddenSeparator
        )

        let activeMoveSnapshot = MenuBarRuntimeSnapshot(
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: true,
            hasAnyScreens: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: activeMoveSnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .rejectMoveAlreadyInFlight
        )

        let missingScreenSnapshot = MenuBarRuntimeSnapshot(
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: false,
            hasAnyScreens: false
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: missingScreenSnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .rejectMissingScreenGeometry
        )

        let staleGeometrySnapshot = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .stale,
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: false,
            hasAnyScreens: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: staleGeometrySnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .ready
        )

        let coarseCachedGeometrySnapshot = MenuBarRuntimeSnapshot(
            identityPrecision: .coarse,
            geometryConfidence: .cached,
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: false,
            hasAnyScreens: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: coarseCachedGeometrySnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .ready
        )
    }
}
