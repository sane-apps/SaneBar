import Testing
@testable import SaneBar

@Suite("Menu Bar Operation — Browse and Move")
struct MenuBarOperationBrowseAndMoveTests {
    @Test("Manual restore skips repair path when the snapshot is already healthy")
    func manualRestoreUsesDirectReplayWhenHealthy() {
        let healthySnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .live,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
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
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
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

    @Test("Browse panel left click uses hardware-first activation and no workspace fallback")
    func browsePanelLeftClickPlanPrefersHardwareFirstWithoutWorkspaceFallback() {
        let app = RunningApp(
            id: "com.openai.codex",
            name: "Codex",
            icon: nil,
            policy: .accessory,
            category: .developerTools,
            xPosition: 1490,
            width: 36
        )

        let plan = MenuBarOperationCoordinator.browseActivationPlan(
            snapshot: MenuBarRuntimeSnapshot(
                identityPrecision: .coarse,
                geometryConfidence: .live,
                visibilityPhase: .expanded,
                browsePhase: .activationInFlight
            ),
            origin: .browsePanel,
            isRightClick: false,
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
            bootstrapPhase: .steady,
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
            bootstrapPhase: .steady,
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
            bootstrapPhase: .steady,
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

        let invisibleStatusItemSnapshot = MenuBarRuntimeSnapshot(
            bootstrapPhase: .steady,
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: false,
            hasAnyScreens: true,
            mainItemVisible: false,
            separatorItemVisible: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: invisibleStatusItemSnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .rejectInvalidStatusItems
        )

        let staleGeometrySnapshot = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .stale,
            bootstrapPhase: .steady,
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
            bootstrapPhase: .steady,
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

        let bootstrappingSnapshot = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .cached,
            bootstrapPhase: .awaitingAnchor,
            visibilityPhase: .expanded,
            hasAlwaysHiddenSeparator: true,
            hasActiveMoveTask: false,
            hasAnyScreens: true
        )
        #expect(
            MenuBarOperationCoordinator.moveQueueDecision(
                snapshot: bootstrappingSnapshot,
                requiresAlwaysHiddenSeparator: false
            ) == .rejectAwaitingAnchor
        )
    }
}
