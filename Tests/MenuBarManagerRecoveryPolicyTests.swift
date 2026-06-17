import Foundation
@testable import SaneBar
import Testing

@Suite("MenuBarManager — Recovery Policy")
struct MenuBarManagerRecoveryPolicyTests {
    // MARK: - AutosaveName Tests

    @Test("Autosave names are unique to prevent position conflicts")
    func autosaveNamesAreUnique() {
        // These are the autosaveName values used by StatusBarController (and relied on by MenuBarManager).
        // They must be unique for macOS to persist positions correctly
        var autosaveNames = [
            StatusBarController.mainAutosaveName,
            StatusBarController.separatorAutosaveName,
            StatusBarController.alwaysHiddenSeparatorAutosaveName,
        ]
        for index in 0 ..< StatusBarController.maxSpacerCount {
            autosaveNames.append("SaneBar_spacer_\(index)")
        }

        let uniqueNames = Set(autosaveNames)

        #expect(uniqueNames.count == autosaveNames.count,
                "All autosaveName values must be unique - found duplicates")
    }

    @Test("Autosave names follow naming convention")
    func autosaveNamesFollowConvention() {
        let autosaveNames = [
            StatusBarController.mainAutosaveName,
            StatusBarController.separatorAutosaveName,
            StatusBarController.alwaysHiddenSeparatorAutosaveName,
            "SaneBar_spacer_0",
        ]

        for name in autosaveNames {
            #expect(name.hasPrefix("SaneBar_"),
                    "Autosave names should start with 'SaneBar_' prefix")
            #expect(!name.contains(" "),
                    "Autosave names should not contain spaces")
        }
    }

    @Test("Tahoe-class systems default to a longer deferred status-item creation delay")
    func statusItemCreationDelayDefaultsForTahoeClassSystems() {
        #expect(
            MenuBarManager.statusItemCreationDelaySeconds(
                environmentOverrideMs: nil,
                majorOSVersion: 26
            ) == 0.35
        )
        #expect(
            MenuBarManager.statusItemCreationDelaySeconds(
                environmentOverrideMs: nil,
                majorOSVersion: 27
            ) == 0.35
        )
        #expect(
            MenuBarManager.statusItemCreationDelaySeconds(
                environmentOverrideMs: nil,
                majorOSVersion: 15
            ) == 0.1
        )
    }

    @Test("Deferred status-item creation delay respects environment override")
    func statusItemCreationDelayRespectsOverride() {
        #expect(
            MenuBarManager.statusItemCreationDelaySeconds(
                environmentOverrideMs: "900",
                majorOSVersion: 26
            ) == 0.9
        )
        #expect(
            MenuBarManager.statusItemCreationDelaySeconds(
                environmentOverrideMs: "-100",
                majorOSVersion: 26
            ) == 0.0
        )
    }

    @Test("Status-item validation timing stays more conservative for wake and screen changes")
    func statusItemValidationDelayBackoff() {
        #expect(MenuBarManager.maxStatusItemRecoveryCount == 4)
        #expect(
            MenuBarManager.statusItemValidationInitialDelaySeconds(
                context: .startupFollowUp,
                recoveryCount: 0
            ) == 1.5
        )
        #expect(
            MenuBarManager.statusItemValidationInitialDelaySeconds(
                context: .startupFollowUp,
                recoveryCount: 1
            ) == 2.0
        )
        #expect(
            MenuBarManager.statusItemValidationInitialDelaySeconds(
                context: .startupFollowUp,
                recoveryCount: 2
            ) == 2.0
        )
        #expect(
            MenuBarManager.statusItemValidationInitialDelaySeconds(
                context: .wakeResume,
                recoveryCount: 0
            ) == 2.0
        )
        #expect(
            MenuBarManager.statusItemValidationInitialDelaySeconds(
                context: .activeSpaceChanged,
                recoveryCount: 0
            ) == 0.35
        )
        #expect(
            MenuBarManager.statusItemValidationRetryDelaySeconds(
                context: .startupFollowUp
            ) == 0.5
        )
        #expect(
            MenuBarManager.statusItemValidationRetryDelaySeconds(
                context: .screenParametersChanged
            ) == 0.5
        )
        #expect(
            MenuBarManager.statusItemValidationRetryDelaySeconds(
                context: .activeSpaceChanged
            ) == 0.25
        )
        #expect(
            MenuBarManager.statusItemValidationMaxAttempts(
                context: .startupFollowUp
            ) == 6
        )
        #expect(
            MenuBarManager.statusItemValidationMaxAttempts(
                context: .wakeResume
            ) == 6
        )
        #expect(
            MenuBarManager.statusItemValidationMaxAttempts(
                context: .activeSpaceChanged
            ) == 6
        )
    }

    @Test("Status-item recovery restores hidden state only when hide is allowed")
    func statusItemRecoveryHiddenStateDecisionMatrix() {
        #expect(
            MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
                hidingState: .expanded,
                shouldSkipHideForExternalMonitor: false
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: true
            )
        )
    }

    @Test("Hidden state replay after status-item recovery requires live core anchors")
    func statusItemRecoveryHiddenReplayRequiresLiveAnchors() {
        #expect(
            MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: MenuBarRuntimeSnapshot(
                    structuralState: .ready,
                    separatorAnchorSource: .live,
                    mainAnchorSource: .live,
                    startupItemsValid: true
                )
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: MenuBarRuntimeSnapshot(
                    structuralState: .unattachedWindows,
                    separatorAnchorSource: .live,
                    mainAnchorSource: .live,
                    startupItemsValid: false
                )
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .hidden,
                shouldSkipHideForExternalMonitor: false,
                snapshot: MenuBarRuntimeSnapshot(
                    structuralState: .ready,
                    separatorAnchorSource: .cached,
                    mainAnchorSource: .live,
                    startupItemsValid: true
                )
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
                hidingState: .expanded,
                shouldSkipHideForExternalMonitor: false,
                snapshot: MenuBarRuntimeSnapshot(
                    structuralState: .ready,
                    separatorAnchorSource: .live,
                    mainAnchorSource: .live,
                    startupItemsValid: true
                )
            )
        )
    }

    @Test("Unrecoverable status-item recovery surfaces Health only after real recovery attempts")
    func statusItemRecoveryStopHealthFallbackDecision() {
        #expect(
            MenuBarVisibilityPolicy.shouldSurfaceHealthAfterStatusItemRecoveryStop(
                recoveryReason: .invalidStatusItems,
                recoveryCount: 1
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldSurfaceHealthAfterStatusItemRecoveryStop(
                recoveryReason: nil,
                recoveryCount: 4
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldSurfaceHealthAfterStatusItemRecoveryStop(
                recoveryReason: .missingCoordinates,
                recoveryCount: 0
            )
        )
    }

    @Test("Hidden collapsed separator can remain structurally healthy while offscreen")
    func hiddenCollapsedSeparatorStructuralHealth() {
        #expect(
            StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
                hidingState: .hidden,
                mainWindowValid: true,
                separatorVisible: true,
                separatorX: 1640,
                mainX: 1660,
                mainRightGap: 260,
                screenWidth: 1920,
                notchRightSafeMinX: nil
            ))
        )
        #expect(
            !StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
                hidingState: .expanded,
                mainWindowValid: true,
                separatorVisible: true,
                separatorX: 1640,
                mainX: 1660,
                mainRightGap: 260,
                screenWidth: 1920,
                notchRightSafeMinX: nil
            ))
        )
        #expect(
            !StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
                hidingState: .hidden,
                mainWindowValid: false,
                separatorVisible: true,
                separatorX: 1640,
                mainX: 1660,
                mainRightGap: 260,
                screenWidth: 1920,
                notchRightSafeMinX: nil
            ))
        )
        #expect(
            !StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
                hidingState: .hidden,
                mainWindowValid: true,
                separatorVisible: true,
                separatorX: 1660,
                mainX: 1640,
                mainRightGap: 260,
                screenWidth: 1920,
                notchRightSafeMinX: nil
            ))
        )
    }

    @Test("Hidden lifecycle preserves trustworthy cached separator geometry")
    func hiddenLifecyclePreservesTrustworthyCachedSeparatorGeometry() {
        #expect(
            MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: 500,
                separatorRightEdgeX: 520,
                mainStatusItemX: 560,
                displayStillPresent: true
            )
        )
        #expect(
            MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: -600,
                separatorRightEdgeX: -580,
                mainStatusItemX: -540,
                displayStillPresent: true
            )
        )
        #expect(
            !MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .expanded,
                separatorX: 500,
                separatorRightEdgeX: 520,
                mainStatusItemX: 560,
                displayStillPresent: true
            )
        )
        #expect(
            !MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: 500,
                separatorRightEdgeX: 520,
                mainStatusItemX: 560,
                displayStillPresent: false
            )
        )
        #expect(
            !MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: 500,
                separatorRightEdgeX: 520,
                mainStatusItemX: 510,
                displayStillPresent: true
            )
        )
    }

    @Test("Layout rescue restore points require healthy status item anchors")
    func layoutRescueRestorePointEligibilityMatrix() {
        let healthy = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .live,
            structuralState: .ready,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
            startupItemsValid: true,
            separatorX: 520,
            mainX: 620
        )
        #expect(MenuBarProfileWorkflow.canCreateLayoutRescueRestorePoint(from: healthy))

        let cached = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .cached,
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .cached,
            startupItemsValid: true,
            separatorX: 520,
            mainX: 620
        )
        #expect(MenuBarProfileWorkflow.canCreateLayoutRescueRestorePoint(from: cached))

        let stale = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .stale,
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .cached,
            startupItemsValid: true,
            separatorX: 520,
            mainX: 620
        )
        #expect(!MenuBarProfileWorkflow.canCreateLayoutRescueRestorePoint(from: stale))

        let missingAnchor = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .live,
            structuralState: .ready,
            separatorAnchorSource: .missing,
            mainAnchorSource: .live,
            startupItemsValid: true,
            separatorX: nil,
            mainX: 620
        )
        #expect(!MenuBarProfileWorkflow.canCreateLayoutRescueRestorePoint(from: missingAnchor))

        let detached = MenuBarRuntimeSnapshot(
            identityPrecision: .exact,
            geometryConfidence: .live,
            structuralState: .unattachedWindows,
            separatorAnchorSource: .live,
            mainAnchorSource: .live,
            startupItemsValid: false,
            separatorX: 520,
            mainX: 620
        )
        #expect(!MenuBarProfileWorkflow.canCreateLayoutRescueRestorePoint(from: detached))
    }

    @Test("Bad data during any recovery context forces hard reset to live anchor; nil-reason paths preserve persisted state")
    func statusItemRecoveryResetDecisionMatrix() {
        // Bad data cases now reset for wake/screen/manual recovery contexts (fixes #147/#142/#150 dynamic + post-arrange jumps)
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidStatusItems,
                validationContext: .wakeResume
            )
        )
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .missingCoordinates,
                validationContext: .manualLayoutRestore
            )
        )
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .missingCoordinates,
                validationContext: .startupFollowUp
            )
        )
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                isStartupRecovery: true
            )
        )
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                validationContext: .wakeResume
            )
        )
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                validationContext: .startupFollowUp
            )
        )
        #expect(
            !MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: nil
            )
        )
    }

    @Test("Unexpected visibility loss only recovers when item is invisible and not rate-limited")
    func unexpectedVisibilityLossRecoveryDecisionMatrix() {
        let now = Date()

        #expect(
            !MenuBarManager.shouldRecoverUnexpectedVisibilityLoss(
                isVisible: true,
                isExecutingRecovery: false,
                lastRecoveryAt: nil,
                now: now,
                minimumInterval: 1.0
            )
        )
        #expect(
            !MenuBarManager.shouldRecoverUnexpectedVisibilityLoss(
                isVisible: false,
                isExecutingRecovery: true,
                lastRecoveryAt: nil,
                now: now,
                minimumInterval: 1.0
            )
        )
        #expect(
            !MenuBarManager.shouldRecoverUnexpectedVisibilityLoss(
                isVisible: false,
                isExecutingRecovery: false,
                lastRecoveryAt: now.addingTimeInterval(-0.5),
                now: now,
                minimumInterval: 1.0
            )
        )
        #expect(
            MenuBarManager.shouldRecoverUnexpectedVisibilityLoss(
                isVisible: false,
                isExecutingRecovery: false,
                lastRecoveryAt: now.addingTimeInterval(-2.0),
                now: now,
                minimumInterval: 1.0
            )
        )
        #expect(
            MenuBarManager.shouldRecoverUnexpectedVisibilityLoss(
                isVisible: false,
                isExecutingRecovery: false,
                lastRecoveryAt: nil,
                now: now,
                minimumInterval: 1.0
            )
        )
    }

    @Test("Runtime snapshot is safe before deferred status-item setup")
    @MainActor
    func currentRuntimeSnapshotBeforeDeferredSetupDoesNotCrash() {
        let manager = MenuBarManager(statusBarController: nil)

        let snapshot = manager.currentRuntimeSnapshot(identityPrecision: .exact)

        #expect(snapshot.identityPrecision == .exact)
        #expect(snapshot.geometryConfidence == .missing)
        #expect(snapshot.structuralState == .missingItems)
        #expect(snapshot.separatorAnchorSource == .missing)
        #expect(snapshot.mainAnchorSource == .missing)
        #expect(snapshot.bootstrapPhase == .steady)
        #expect(snapshot.startupItemsValid == false)
    }

    @Test("Bootstrap trust requires non-estimated separator and main anchors")
    func bootstrapTrustRequiresNonEstimatedSeparatorAnchor() {
        let estimatedSeparatorSnapshot = MenuBarRuntimeSnapshot(
            structuralState: .ready,
            separatorAnchorSource: .estimated,
            mainAnchorSource: .live
        )
        let cachedSeparatorSnapshot = MenuBarRuntimeSnapshot(
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .estimated
        )
        let cachedAnchorSnapshot = MenuBarRuntimeSnapshot(
            structuralState: .ready,
            separatorAnchorSource: .cached,
            mainAnchorSource: .cached
        )

        #expect(!estimatedSeparatorSnapshot.hasTrustworthyBootstrapAnchors)
        #expect(!cachedSeparatorSnapshot.hasTrustworthyBootstrapAnchors)
        #expect(cachedAnchorSnapshot.hasTrustworthyBootstrapAnchors)
    }

    @Test("Hidden near-control-center presentation is protected instead of stale")
    func hiddenNearControlCenterPresentationIsShielded() {
        let confidence = MenuBarStatusItemRecoveryWorkflow.resolvedGeometryConfidence(
            for: MenuBarRuntimeSnapshot(
                structuralState: .ready,
                separatorAnchorSource: .live,
                mainAnchorSource: .live,
                separatorX: 1667,
                mainX: 1660,
                mainRightGap: 260,
                screenWidth: 1920
            ),
            hidingState: .hidden,
            alwaysHiddenSeparatorMisordered: false
        )

        #expect(confidence == .shielded)
    }

    @Test("Expanded misordered geometry still needs repair")
    func expandedMisorderedGeometryIsStillStale() {
        let confidence = MenuBarStatusItemRecoveryWorkflow.resolvedGeometryConfidence(
            for: MenuBarRuntimeSnapshot(
                structuralState: .ready,
                separatorAnchorSource: .live,
                mainAnchorSource: .live,
                separatorX: 1667,
                mainX: 1660,
                mainRightGap: 260,
                screenWidth: 1920
            ),
            hidingState: .expanded,
            alwaysHiddenSeparatorMisordered: false
        )

        #expect(confidence == .stale)
    }

    @Test("Main icon fallback can derive its left edge from a visible separator")
    func estimatedMainStatusItemLeftEdgeUsesSeparatorGeometry() {
        #expect(
            MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
                separatorIsPresentInVisualMode: true,
                separatorRightEdge: 320,
                separatorOrigin: 300
            ) == 320
        )
        #expect(
            MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
                separatorIsPresentInVisualMode: true,
                separatorRightEdge: nil,
                separatorOrigin: 300
            ) == 320
        )
    }

    @Test("Main icon fallback refuses separator caches when the separator is not visually present")
    func estimatedMainStatusItemLeftEdgeRequiresVisibleSeparator() {
        #expect(
            MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
                separatorIsPresentInVisualMode: false,
                separatorRightEdge: 320,
                separatorOrigin: 300
            ) == nil
        )
        #expect(
            MenuBarMoveGeometryPolicy.estimatedMainStatusItemLeftEdge(
                separatorIsPresentInVisualMode: true,
                separatorRightEdge: nil,
                separatorOrigin: nil
            ) == nil
        )
    }

    @Test("Always-hidden separator repair only triggers for a real misordered live divider")
    func alwaysHiddenSeparatorRepairGuard() {
        #expect(
            !MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: false,
                separatorX: 200,
                alwaysHiddenSeparatorRightEdgeX: 220
            )
        )
        #expect(
            !MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: true,
                separatorX: 200,
                alwaysHiddenSeparatorRightEdgeX: 180
            )
        )
        #expect(
            !MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: true,
                separatorX: 200,
                alwaysHiddenSeparatorRightEdgeX: nil
            )
        )
        #expect(
            MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: true,
                separatorX: 200,
                alwaysHiddenSeparatorRightEdgeX: 220
            )
        )
        #expect(
            !MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: true,
                separatorX: -200,
                alwaysHiddenSeparatorRightEdgeX: -240
            ),
            "Negative global X is valid on a left-arranged display; ordering, not sign, determines repair"
        )
        #expect(
            MenuBarAlwaysHiddenPinWorkflow.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: true,
                separatorX: -200,
                alwaysHiddenSeparatorRightEdgeX: -180
            ),
            "Repair should still trigger for misordered live geometry in negative global coordinates"
        )
    }
}
