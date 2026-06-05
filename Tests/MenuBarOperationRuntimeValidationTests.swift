import Testing
@testable import SaneBar

@Suite("Menu Bar Operation — Runtime Validation")
struct MenuBarOperationRuntimeValidationTests {
    @Test("Screen-change geometry drift escalates once before stopping")
    func runtimeValidationBoundsGeometryDriftForScreenChanges() {
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
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 2,
                maxRecoveryCount: 2
            ) == .stop(.invalidGeometry)
        )
    }

    @Test("Wake validation escalates once before stopping")
    func wakeValidationBoundsGeometryDrift() {
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
            ) == .bumpAutosaveVersion(.invalidGeometry)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 2,
                maxRecoveryCount: 2
            ) == .stop(.invalidGeometry)
        )
    }

    @Test("Wake validation waits briefly then recreates when only the separator anchor is estimated")
    func wakeValidationRecreatesForEstimatedSeparatorAnchor() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live,
            startupItemsValid: true,
            separatorX: 1661,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .waitForLiveAnchor
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 1,
                maxRecoveryCount: 4
            ) == .recreateFromPersistedLayout(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 2,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 3,
                maxRecoveryCount: 4
            ) == .bumpAutosaveVersion(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 4,
                maxRecoveryCount: 4
            ) == .stop(.missingCoordinates)
        )
    }

    @Test("Screen-change validation waits briefly then recreates when only the separator anchor is estimated")
    func screenChangeValidationRecreatesForEstimatedSeparatorAnchor() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            separatorX: 1661,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .waitForLiveAnchor
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 1,
                maxRecoveryCount: 4
            ) == .recreateFromPersistedLayout(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 2,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 3,
                maxRecoveryCount: 4
            ) == .bumpAutosaveVersion(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 4,
                maxRecoveryCount: 4
            ) == .stop(.missingCoordinates)
        )
    }

    @Test("Wake validation recreates persisted layout when coordinates are missing after wake")
    func wakeValidationRecreatesForMissingCoordinates() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            separatorAnchorSource: .missing,
            mainAnchorSource: .live,
            startupItemsValid: true,
            separatorX: nil,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .waitForLiveAnchor
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 1,
                maxRecoveryCount: 4
            ) == .recreateFromPersistedLayout(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 2,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 3,
                maxRecoveryCount: 4
            ) == .bumpAutosaveVersion(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 4,
                maxRecoveryCount: 4
            ) == .stop(.missingCoordinates)
        )
    }

    @Test("Screen-change validation recreates persisted layout when coordinates are missing")
    func screenChangeValidationRecreatesForMissingCoordinates() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            separatorAnchorSource: .missing,
            mainAnchorSource: .live,
            startupItemsValid: true,
            separatorX: nil,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .waitForLiveAnchor
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 1,
                maxRecoveryCount: 4
            ) == .recreateFromPersistedLayout(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 2,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 3,
                maxRecoveryCount: 4
            ) == .bumpAutosaveVersion(.missingCoordinates)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 4,
                maxRecoveryCount: 4
            ) == .stop(.missingCoordinates)
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
        let estimatedSeparatorSnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live,
            bootstrapPhase: .awaitingAnchor,
            startupItemsValid: true,
            separatorX: 1661,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: estimatedSeparatorSnapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
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

    @Test("Position validation stops instead of resetting autosave state for likely macOS suppression")
    func positionValidationStopsForLikelySystemSuppressedStatusItems() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: false,
            likelySystemSuppressedStatusItems: true,
            separatorX: nil,
            mainX: nil
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .stop(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .stop(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .manualLayoutRestoreRequest,
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .stop(.invalidStatusItems)
        )
    }
}
