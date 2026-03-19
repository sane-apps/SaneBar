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

    @Test("Runtime geometry drift stops after one persisted-layout repair attempt")
    func runtimeValidationDoesNotEscalateGeometryDriftIndefinitely() {
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

    @Test("Manual restore always sanitizes persisted layout before replay")
    func manualRestoreUsesRepairPathFirst() {
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
            ) == .repairPersistedLayoutAndRecreate(nil)
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

    @Test("Move queue decision rejects busy or incomplete runtime state")
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
    }
}
