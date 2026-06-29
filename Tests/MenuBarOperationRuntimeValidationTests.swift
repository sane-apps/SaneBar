@testable import SaneBar
import Testing

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

    @Test("Transient multi-monitor status-item detachment stands down instead of recreating (#160)")
    func transientUnattachedWindowsDoesNotRecreateOnSteadyStateValidation() {
        // The MAIN item is genuinely live and seated (mainAnchorSource == .live with
        // known coordinates); only the separator/window flapped not-live while macOS
        // recomposited the menu bar on a Space switch / app activation
        // (.unattachedWindows). Recreating the layout here is the visible
        // unfurl→collapse flash users see "every few minutes" (#160), so the steady-
        // state path must stand down — the live main proves the items still exist.
        // NOTE: .wakeResume is deliberately NOT a steady-state stand-down — a real
        // display sleep/wake needs the separator re-seated (#136), so it recovers
        // (asserted separately below). Standing wake down regressed it: the wake
        // layout probe caught a visible icon drifting into the hidden zone (2026-06-29).
        let transientlyDetached = MenuBarRuntimeSnapshot(
            structuralState: .unattachedWindows,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
            startupItemsValid: false,
            separatorX: 1442,
            mainX: 1697,
            mainRightGap: 223,
            screenWidth: 1920
        )

        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: transientlyDetached,
                context: .positionValidation(.activeSpaceChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .stop(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: transientlyDetached,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: transientlyDetached,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .stop(.invalidStatusItems)
        )

        // Contrast 1 — genuinely gone items (.missingItems) must still recover,
        // so #157/#152 (icon truly absent) is not weakened by the stand-down.
        let genuinelyGone = MenuBarRuntimeSnapshot(
            structuralState: .missingItems,
            separatorAnchorSource: .missing,
            mainAnchorSource: .missing,
            startupItemsValid: false,
            screenWidth: 1920
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: genuinelyGone,
                context: .positionValidation(.activeSpaceChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )

        // Contrast 2 — a genuinely detached MAIN item (mainAnchorSource != .live)
        // still recovers even with coordinates present: the live-main signal, not
        // the mere presence of coordinates, gates the stand-down. Keeps genuine
        // detached-icon recovery (cf. lifecycleValidationRepairsDetachedStatusItems).
        let detachedMainNotLive = MenuBarRuntimeSnapshot(
            structuralState: .unattachedWindows,
            separatorAnchorSource: .missing,
            mainAnchorSource: .missing,
            startupItemsValid: false,
            separatorX: 1442,
            mainX: 1697,
            mainRightGap: 223,
            screenWidth: 1920
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: detachedMainNotLive,
                context: .positionValidation(.activeSpaceChanged),
                recoveryCount: 0,
                maxRecoveryCount: 2
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
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

    @Test("Runtime attachment loss arms visible allow-list replay only after hidden lifecycle anchor loss")
    func runtimeAttachmentLossArmsVisibleAllowListReplayNarrowly() {
        let hiddenMissingAnchor = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            structuralState: .ready,
            separatorAnchorSource: .missing,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            separatorX: nil,
            mainX: 1700,
            mainRightGap: 220,
            screenWidth: 1920
        )
        let expandedMissingAnchor = MenuBarRuntimeSnapshot(
            geometryConfidence: .missing,
            structuralState: .ready,
            separatorAnchorSource: .missing,
            mainAnchorSource: .live,
            visibilityPhase: .expanded,
            startupItemsValid: true,
            separatorX: nil,
            mainX: 1700,
            mainRightGap: 220,
            screenWidth: 1920
        )
        let driftedHidden = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            structuralState: .ready,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            separatorX: 900,
            mainX: 930,
            mainRightGap: 990,
            screenWidth: 1920
        )

        #expect(
            !MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: hiddenMissingAnchor,
                validationContext: .activeSpaceChanged,
                action: .waitForLiveAnchor
            )
        )
        #expect(
            !MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: hiddenMissingAnchor,
                validationContext: .screenParametersChanged,
                action: .recreateFromPersistedLayout(.missingCoordinates)
            )
        )
        #expect(
            MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: hiddenMissingAnchor,
                validationContext: .wakeResume,
                action: .repairPersistedLayoutAndRecreate(.missingCoordinates)
            )
        )
        #expect(
            !MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: hiddenMissingAnchor,
                validationContext: .startupFollowUp,
                action: .waitForLiveAnchor
            )
        )
        #expect(
            !MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: expandedMissingAnchor,
                validationContext: .activeSpaceChanged,
                action: .waitForLiveAnchor
            )
        )
        #expect(
            !MenuBarOperationCoordinator.shouldArmWakeVisibleAllowListReplayAfterRuntimeAttachmentLoss(
                snapshot: driftedHidden,
                validationContext: .activeSpaceChanged,
                action: .repairPersistedLayoutAndRecreate(.invalidGeometry)
            )
        )
    }

    @Test("Lifecycle validation protects hidden cached separator presentation")
    func lifecycleValidationProtectsHiddenCachedSeparatorPresentation() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .cached,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            separatorX: 1661,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )

        #expect(MenuBarOperationCoordinator.startupRecoveryReason(snapshot: snapshot) == .missingCoordinates)
        #expect(MenuBarOperationCoordinator.positionValidationRecoveryReason(snapshot: snapshot) == nil)
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .captureCurrentDisplayBackup
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.screenParametersChanged),
                recoveryCount: 1,
                maxRecoveryCount: 4
            ) == .captureCurrentDisplayBackup
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.activeSpaceChanged),
                recoveryCount: 2,
                maxRecoveryCount: 4
            ) == .captureCurrentDisplayBackup
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .captureCurrentDisplayBackup
        )
    }

    @Test("Lifecycle validation does not protect misordered hidden cached separator presentation")
    func lifecycleValidationRejectsMisorderedHiddenCachedSeparatorPresentation() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .shielded,
            separatorAnchorSource: .cached,
            mainAnchorSource: .live,
            visibilityPhase: .hidden,
            startupItemsValid: true,
            separatorX: 1712,
            mainX: 1684,
            mainRightGap: 236,
            screenWidth: 1920
        )

        #expect(MenuBarOperationCoordinator.positionValidationRecoveryReason(snapshot: snapshot) == .missingCoordinates)
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .waitForLiveAnchor
        )
    }

    @Test("Lifecycle validation still rejects unsafe cached separator anchors")
    func lifecycleValidationStillRejectsUnsafeCachedSeparatorAnchors() {
        let expandedSnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .cached,
            separatorAnchorSource: .cached,
            mainAnchorSource: .live,
            visibilityPhase: .expanded,
            startupItemsValid: true,
            separatorX: 1661,
            mainX: 1691,
            mainRightGap: 229,
            screenWidth: 1920
        )
        let liveConfidenceSnapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .live,
            separatorAnchorSource: .cached,
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
                snapshot: expandedSnapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .waitForLiveAnchor
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: liveConfidenceSnapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.missingCoordinates)
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

    @Test("Lifecycle validation repairs detached status items instead of doing a weak recreate")
    func lifecycleValidationRepairsDetachedStatusItems() {
        let snapshot = MenuBarRuntimeSnapshot(
            geometryConfidence: .stale,
            startupItemsValid: false,
            likelySystemSuppressedStatusItems: false,
            separatorX: 832,
            mainX: 852,
            mainRightGap: nil,
            screenWidth: 1920
        )

        for context in [
            MenuBarOperationCoordinator.PositionValidationContext.screenParametersChanged,
            .activeSpaceChanged,
            .wakeResume,
        ] {
            #expect(
                MenuBarOperationCoordinator.statusItemRecoveryAction(
                    snapshot: snapshot,
                    context: .positionValidation(context),
                    recoveryCount: 0,
                    maxRecoveryCount: 4
                ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
            )
            #expect(
                MenuBarOperationCoordinator.statusItemRecoveryAction(
                    snapshot: snapshot,
                    context: .positionValidation(context),
                    recoveryCount: 1,
                    maxRecoveryCount: 4
                ) == .bumpAutosaveVersion(.invalidStatusItems)
            )
            #expect(
                MenuBarOperationCoordinator.statusItemRecoveryAction(
                    snapshot: snapshot,
                    context: .positionValidation(context),
                    recoveryCount: 4,
                    maxRecoveryCount: 4
                ) == .stop(.invalidStatusItems)
            )
        }
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

    @Test("Position validation attempts one repair then stops for likely macOS suppression")
    func positionValidationRepairsOnceThenStopsForLikelySystemSuppressedStatusItems() {
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
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.startupFollowUp),
                recoveryCount: 1,
                maxRecoveryCount: 4
            ) == .stop(.invalidStatusItems)
        )
        #expect(
            MenuBarOperationCoordinator.statusItemRecoveryAction(
                snapshot: snapshot,
                context: .positionValidation(.wakeResume),
                recoveryCount: 2,
                maxRecoveryCount: 4
            ) == .stop(.invalidStatusItems)
        )
    }

    @Test("Manual repair request always attempts repair even for likely macOS suppression")
    func manualRepairRequestRepairsForLikelySystemSuppressedStatusItems() {
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
                context: .manualLayoutRestoreRequest,
                recoveryCount: 0,
                maxRecoveryCount: 4
            ) == .repairPersistedLayoutAndRecreate(.invalidStatusItems)
        )
    }
}
