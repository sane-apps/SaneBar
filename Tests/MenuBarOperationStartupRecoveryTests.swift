import Testing
@testable import SaneBar

@Suite("Menu Bar Operation — Startup Recovery")
struct MenuBarOperationStartupRecoveryTests {
    @Test("Startup recovery is required for stale geometry")
    func startupRecoveryTriggersForInvalidGeometry() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
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

    @Test("Estimated separator anchor still counts as missing coordinates")
    func startupTreatsEstimatedSeparatorAsMissingCoordinates() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live,
            startupItemsValid: true,
            separatorX: 160,
            mainX: 180,
            mainRightGap: 640,
            screenWidth: 1440
        )

        #expect(MenuBarOperationCoordinator.startupRecoveryReason(snapshot: snapshot) == .missingCoordinates)
    }

    @Test("Startup repair does not reuse cached hidden replay geometry")
    func startupRepairRequiresLiveAnchorsEvenWhenHiddenReplayCouldUseCache() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            separatorX: 956,
            mainX: 976,
            mainRightGap: 944,
            screenWidth: 1920
        )

        #expect(
            MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: snapshot
            ),
            "Hidden replay may use protected cached hidden geometry"
        )
        #expect(
            MenuBarOperationCoordinator.startupRecoveryReason(snapshot: snapshot) == .missingCoordinates,
            "Startup repair must not treat hidden replay geometry as a general repair basis"
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .startupInitial(.init(
                    hasCompletedOnboarding: true,
                    autoRehideEnabled: true,
                    shouldSkipHideForExternalMonitor: false,
                    hasConnectedExternalMonitorWithAlwaysShow: false
                )),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .keepExpanded(.waitingForLiveCoordinates)
        )
    }

    @Test("Startup waits while the separator anchor is only estimated")
    func startupHoldsExpandedWhenSeparatorAnchorIsEstimated() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live,
            bootstrapPhase: .awaitingAnchor,
            startupItemsValid: true,
            separatorX: 160,
            mainX: 180,
            mainRightGap: 640,
            screenWidth: 1440
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
            Issue.record("Expected startup to keep waiting while separator geometry is only estimated")
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

    @Test("Startup repairs immediately when status-item windows are invalid and no coordinates survived")
    func startupRepairsAnchorlessInvalidStatusItems() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            startupItemsValid: false,
            separatorX: nil,
            mainX: nil
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .startupInitial(.init(
                    hasCompletedOnboarding: true,
                    autoRehideEnabled: true,
                    shouldSkipHideForExternalMonitor: false,
                    hasConnectedExternalMonitorWithAlwaysShow: false
                )),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
    }

    @Test("Startup does not reset autosave state when macOS appears to suppress visible status items")
    func startupHoldsForLikelySystemSuppressedStatusItems() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            startupItemsValid: false,
            likelySystemSuppressedStatusItems: true,
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
            Issue.record("Expected startup to wait instead of resetting autosave state for likely macOS suppression")
            return
        }
    }

    @Test("Startup repairs immediately when a required status item is invisible")
    func startupRepairsInvisibleStatusItems() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            mainItemVisible: false,
            separatorItemVisible: true,
            separatorX: 160,
            mainX: 180
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .startupInitial(.init(
                    hasCompletedOnboarding: true,
                    autoRehideEnabled: true,
                    shouldSkipHideForExternalMonitor: false,
                    hasConnectedExternalMonitorWithAlwaysShow: false
                )),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
    }

    @Test("Startup follow-up repairs persisted geometry before recreating live items")
    func startupValidationRepairsGeometryBeforeRecreate() {
        let snapshot = MenuBarRuntimeSnapshot(
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

    @Test("Always-hidden runtime drift escalates through fresh autosave namespaces")
    func alwaysHiddenRuntimeValidationBumpsAutosaveVersionAfterRetry() {
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
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .activeSpaceChanged,
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .wakeResume,
                recoveryCount: 1,
                maxRecoveryCount: 2
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(
                context: .activeSpaceChanged,
                recoveryCount: 2,
                maxRecoveryCount: 2
            ) == .stop(.invalidGeometry)
        )
    }
}
