import AppKit
import os.log

private let visibilityReplayLogger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager")

enum MenuBarVisibilityPolicy {
    nonisolated static let appMenuDockPolicyReassertionIntervalsNanoseconds: [UInt64] = [
        150_000_000,
        850_000_000,
        2_000_000_000,
        3_000_000_000
    ]

    nonisolated static func shouldBlockRehideForMouseLocation(
        _ point: NSPoint,
        screenFrames: [CGRect],
        detectionZoneHeight: CGFloat = 24,
        leaveThreshold: CGFloat = 200
    ) -> Bool {
        guard HoverService.isPointInMenuBarInteractionRegion(
            point,
            screenFrames: screenFrames,
            detectionZoneHeight: detectionZoneHeight,
            leaveThreshold: leaveThreshold
        ) else {
            return false
        }

        // The top strip alone is not enough to keep the bar open forever.
        return !HoverService.isPointInMenuBarStrip(
            point,
            screenFrames: screenFrames,
            detectionZoneHeight: detectionZoneHeight
        )
    }

    static func shouldSkipHide(disableOnExternalMonitor: Bool, isOnExternalMonitor: Bool) -> Bool {
        disableOnExternalMonitor && isOnExternalMonitor
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated static func shouldScheduleRehideOnAppChange(
        rehideOnAppChange: Bool,
        autoRehideEnabled: Bool,
        hidingState: HidingState,
        isRevealPinned: Bool,
        shouldSkipHideForExternalMonitor: Bool,
        isBrowseSessionActive: Bool,
        activatedBundleID: String?,
        ownBundleID: String?
    ) -> Bool {
        guard rehideOnAppChange else { return false }
        guard autoRehideEnabled else { return false }
        guard hidingState == .expanded else { return false }
        guard !isRevealPinned else { return false }
        guard !shouldSkipHideForExternalMonitor else { return false }
        guard !isBrowseSessionActive else { return false }

        if let activatedBundleID,
           let ownBundleID,
           activatedBundleID == ownBundleID {
            return false
        }

        return true
    }

    nonisolated static func shouldValidateStatusItemsAfterAppActivation(
        hidingState: HidingState,
        shouldSkipHideForExternalMonitor: Bool,
        isBrowseSessionActive: Bool,
        activatedBundleID: String?,
        ownBundleID: String?
    ) -> Bool {
        guard hidingState == .hidden else { return false }
        guard !shouldSkipHideForExternalMonitor else { return false }
        guard !isBrowseSessionActive else { return false }

        if let activatedBundleID,
           let ownBundleID,
           activatedBundleID == ownBundleID {
            return false
        }

        return true
    }

    nonisolated static func shouldArmAutoRehideAfterSettingsChange(
        _ context: AutoRehideSettingsChangeContext
    ) -> Bool {
        guard !context.wasAutoRehideEnabled, context.isAutoRehideEnabled else { return false }
        guard context.hidingState == .expanded else { return false }
        guard !context.isRevealPinned else { return false }
        guard !context.shouldSkipHideForExternalMonitor else { return false }
        guard !context.isStatusMenuOpen else { return false }
        return true
    }

    nonisolated static func shouldIgnorePointerRehideBlockForOwnAppWindow(
        ownAppWindowActive: Bool,
        isStatusMenuOpen: Bool,
        isBrowseSessionActive: Bool,
        isBrowseVisible: Bool
    ) -> Bool {
        ownAppWindowActive && !isStatusMenuOpen && !isBrowseSessionActive && !isBrowseVisible
    }

    nonisolated static func shouldReactivateSavedAppAfterSuppression(
        savedAppPID: pid_t?,
        currentFrontmostPID: pid_t?,
        ownPID: pid_t
    ) -> Bool {
        guard let savedAppPID, savedAppPID != ownPID else { return false }
        guard let currentFrontmostPID else { return true }
        return currentFrontmostPID == ownPID
    }

    nonisolated static func shouldRestoreHiddenAfterStatusItemRecovery(
        hidingState: HidingState,
        shouldSkipHideForExternalMonitor: Bool
    ) -> Bool {
        hidingState == .hidden && !shouldSkipHideForExternalMonitor
    }

    nonisolated static func shouldReplayAlwaysHiddenIntent(
        alwaysHiddenSectionEnabled: Bool,
        pinnedItemCount: Int
    ) -> Bool {
        alwaysHiddenSectionEnabled && pinnedItemCount > 0
    }

    nonisolated static func canApplyHiddenStateAfterStatusItemRecovery(
        hidingState: HidingState,
        shouldSkipHideForExternalMonitor: Bool,
        snapshot: MenuBarRuntimeSnapshot,
        requiresLiveGeometryForVisibleAllowList: Bool = false
    ) -> Bool {
        guard shouldRestoreHiddenAfterStatusItemRecovery(
            hidingState: hidingState,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor
        ) else { return false }

        guard snapshot.structuralState == .ready, snapshot.startupItemsValid else { return false }

        if snapshot.separatorAnchorSource == .live, snapshot.mainAnchorSource == .live {
            return true
        }

        guard !requiresLiveGeometryForVisibleAllowList else { return false }

        // Hidden replay only reapplies SaneBar's collapsed delimiter length; it
        // does not physically move third-party icons. While hidden, AppKit can
        // shield the separator behind a cached anchor even though the main
        // status item is attached and the collapsed presentation is valid.
        guard snapshot.visibilityPhase == .hidden,
              snapshot.mainAnchorSource == .live,
              snapshot.separatorAnchorSource == .cached
        else {
            return false
        }

        switch snapshot.geometryConfidence {
        case .cached, .shielded:
            return true
        case .live, .stale, .missing:
            return false
        }
    }

    nonisolated static func shouldSurfaceHealthAfterStatusItemRecoveryStop(
        recoveryReason: MenuBarOperationCoordinator.StartupRecoveryReason?,
        recoveryCount: Int,
        validationContext: MenuBarOperationCoordinator.PositionValidationContext?
    ) -> Bool {
        // Only after recovery has genuinely exhausted its attempts (recoveryCount > 0)
        // with a real failure reason.
        guard recoveryReason != nil, recoveryCount > 0 else { return false }
        switch validationContext {
        case .manualLayoutRestore:
            // The user explicitly asked to restore layout and it failed.
            return true
        case .startupFollowUp:
            // The icon never came up at launch — e.g. macOS won't place the status
            // item (#157). Without surfacing Health the user is left with an
            // invisible, unreachable app and no way to repair or export a diagnostic.
            // startup-follow-up recovery runs once per launch, so Health surfaces at
            // most once and is not a repeating popup.
            return true
        case .screenParametersChanged, .activeSpaceChanged, .wakeResume, .none:
            // Steady-state validations fire repeatedly during normal use; surfacing
            // Health here would pop the window unexpectedly. The reopen handler
            // (applicationShouldHandleReopen) is the recovery path for those.
            return false
        }
    }

    nonisolated static func maxAllowedStartupRightGap(screenWidth: CGFloat) -> CGFloat {
        min(480, max(300, screenWidth * 0.18))
    }

    nonisolated static func isMainNearControlCenter(
        mainX: CGFloat?,
        mainRightGap: CGFloat? = nil,
        screenWidth: CGFloat? = nil,
        notchRightSafeMinX: CGFloat? = nil
    ) -> Bool {
        let notchSafe = isMainInsideNotchSafeRightZone(
            mainX: mainX,
            notchRightSafeMinX: notchRightSafeMinX
        )
        if let notchSafe {
            return notchSafe
        }

        let gapHealthy = isMainRightGapHealthy(
            mainRightGap: mainRightGap,
            screenWidth: screenWidth
        )
        if let gapHealthy {
            return gapHealthy
        }

        return false
    }

    /// How far the live main position may deviate from SaneBar's own persisted
    /// preferred position (both measured as distance from the screen's right
    /// edge) before soft drift is flagged.
    nonisolated static let minimumMainDriftFromPersistedIntentTolerance: CGFloat = 160
    nonisolated static let maximumMainDriftFromPersistedIntentTolerance: CGFloat = 320
    nonisolated static let customMainDriftFromPersistedIntentTolerance: CGFloat = 32

    nonisolated static func mainDriftFromPersistedIntentTolerance(screenWidth: CGFloat?) -> CGFloat {
        guard let screenWidth, screenWidth.isFinite, screenWidth > 0 else {
            return minimumMainDriftFromPersistedIntentTolerance
        }
        return min(
            maximumMainDriftFromPersistedIntentTolerance,
            max(minimumMainDriftFromPersistedIntentTolerance, screenWidth * 0.10)
        )
    }

    nonisolated static func shouldRecoverStartupPositions(
        separatorX: CGFloat?,
        mainX: CGFloat?,
        mainRightGap: CGFloat? = nil,
        screenWidth: CGFloat? = nil,
        notchRightSafeMinX: CGFloat? = nil,
        persistedMainDistanceFromRight: CGFloat? = nil
    ) -> Bool {
        guard let separatorX, let mainX else { return false }
        guard separatorX.isFinite, mainX.isFinite else { return false }
        if separatorX >= mainX {
            // Hard invariant: the separator must sit left of the main toggle.
            return true
        }

        // Soft drift: when SaneBar's own persisted intent is known, judge the
        // live position against IT instead of an absolute zone. Users may
        // legitimately keep the toggle far from Control Center (icons parked
        // right of SaneBar); macOS rewrites the persisted preferred position
        // whenever the user drags the toggle, so intent tracks the user.
        if let persistedMainDistanceFromRight,
           persistedMainDistanceFromRight.isFinite,
           persistedMainDistanceFromRight >= 0,
           persistedMainDistanceFromRight < 5000,
           let mainRightGap,
           mainRightGap.isFinite {
            let drift = abs(mainRightGap - persistedMainDistanceFromRight)
            if drift < customMainDriftFromPersistedIntentTolerance {
                return false
            }

            if let gapHealthy = isMainRightGapHealthy(
                mainRightGap: mainRightGap,
                screenWidth: screenWidth
            ), !gapHealthy {
                return true
            }

            let tolerance = mainDriftFromPersistedIntentTolerance(screenWidth: screenWidth)
            return drift > tolerance
        }

        // Fallback when persisted intent is unavailable: absolute zone checks.
        if let notchSafe = isMainInsideNotchSafeRightZone(
            mainX: mainX,
            notchRightSafeMinX: notchRightSafeMinX
        ) {
            return !notchSafe
        }

        if let gapHealthy = isMainRightGapHealthy(
            mainRightGap: mainRightGap,
            screenWidth: screenWidth
        ), !gapHealthy {
            return true
        }

        return false
    }

    nonisolated static func shouldSuppressApplicationMenus(
        for revealTrigger: MenuBarRevealTrigger
    ) -> Bool {
        switch revealTrigger {
        case .click, .scroll, .userDrag:
            true
        case .hotkey, .search, .automation, .hover, .settingsButton, .findIcon:
            false
        }
    }

    nonisolated static func shouldHideApplicationMenus(
        leftmostVisibleItemX: CGFloat,
        appMenuMaxX: CGFloat,
        collisionPadding: CGFloat = 2
    ) -> Bool {
        leftmostVisibleItemX <= (appMenuMaxX + collisionPadding)
    }

    nonisolated static func shouldManageApplicationMenus(
        hideApplicationMenusOnInlineReveal: Bool,
        showDockIcon: Bool,
        accessibilityGranted: Bool,
        hidingState: HidingState,
        revealTrigger: MenuBarRevealTrigger
    ) -> Bool {
        hideApplicationMenusOnInlineReveal &&
            !showDockIcon &&
            accessibilityGranted &&
            hidingState == .expanded &&
            shouldSuppressApplicationMenus(for: revealTrigger)
    }

    private nonisolated static func isMainInsideNotchSafeRightZone(
        mainX: CGFloat?,
        notchRightSafeMinX: CGFloat?
    ) -> Bool? {
        guard let notchRightSafeMinX, notchRightSafeMinX > 0 else { return nil }
        guard let mainX, mainX > 0 else { return false }
        let notchTolerance: CGFloat = 8
        return mainX >= (notchRightSafeMinX - notchTolerance)
    }

    private nonisolated static func isMainRightGapHealthy(
        mainRightGap: CGFloat?,
        screenWidth: CGFloat?
    ) -> Bool? {
        guard let mainRightGap, let screenWidth else { return nil }
        guard mainRightGap > 0, screenWidth > 0 else { return false }
        return mainRightGap <= maxAllowedStartupRightGap(screenWidth: screenWidth)
    }
}

extension MenuBarVisibilityPolicy {
    /// Automatic replay may only use physical Cmd+drag moves when the runtime
    /// snapshot reports live geometry. Replays on cached/estimated/stale
    /// geometry moved items users never asked to move (#151, #154).
    ///
    /// Startup/relaunch reconciliation gets the same live-gated physical
    /// capability: hide-all-other and pinned intent are standing user
    /// instructions, and a relaunch can land the separator on the other side
    /// of an allow-listed item without anything physically moving. Session,
    /// Space, screen, and immediate wake validations stay passive unless the
    /// explicit post-wake visible allow-list repair gate is armed.
    nonisolated static func visibilityIntentReplayMode(
        reason: String,
        geometryConfidence: MenuBarGeometryConfidence,
        hidingState _: HidingState,
        hasVisibleAllowList: Bool = false,
        hasPendingWakeVisibleAllowListReplay: Bool = false,
        canRepairHiddenWakeVisibleAllowList: Bool = false
    ) -> (mode: MenuBarVisibilityIntentMode, physicalMoveOrigin: MenuBarPhysicalMoveOrigin?) {
        // Startup/relaunch reconciliation follows an explicit user context
        // (the app was just launched) and may restore standing intent
        // physically. Immediate wake stays passive because raw wake
        // notifications arrive before geometry and dynamic helper items settle.
        // Post-wake healthy validation may repair an explicit Hide All Other
        // visible allow-list, because collapsing hidden state first would hide
        // the item the user asked to keep visible.
        //
        // Physical replay normally runs only on a live snapshot. The sole
        // non-live exception is a fresh wake recovery where Hidden state has a
        // protected cached separator and a visible allow-list item needs to be
        // moved back before the bar is collapsed again. Shielded geometry may
        // preserve Hidden state, but is not safe enough for cursor moves.
        let isImmediateWakeReplay = reason.hasPrefix("wake-resume")
        let isPostWakeHealthyValidation = isPostWakeVisibleAllowListReplayReason(reason)
        let isStartupReconciliation = isStartupVisibilityIntentReplayReason(reason)
        if isImmediateWakeReplay {
            return (.auditOnly, nil)
        }

        let confidenceAllowsMoves = geometryConfidence == .live
        let isWakeVisibleAllowListRecovery = hasVisibleAllowList &&
            isPostWakeHealthyValidation &&
            hasPendingWakeVisibleAllowListReplay
        if isWakeVisibleAllowListRecovery, confidenceAllowsMoves {
            return (.repairWithPhysicalMoves, .systemWakeRecovery)
        }
        if isWakeVisibleAllowListRecovery, canRepairHiddenWakeVisibleAllowList {
            return (.repairWithPhysicalMoves, .systemWakeRecovery)
        }
        if isStartupReconciliation, confidenceAllowsMoves {
            return (.repairWithPhysicalMoves, .systemWakeRecovery)
        }
        return (.auditOnly, nil)
    }

    nonisolated static func isPostWakeVisibleAllowListReplayReason(_ reason: String) -> Bool {
        reason.hasPrefix("healthy-validation-wake-resume") ||
            reason.hasPrefix("status-item-recreate-wake-resume")
    }

    nonisolated static func isStartupVisibilityIntentReplayReason(_ reason: String) -> Bool {
        reason.hasPrefix("healthy-validation-startup-follow-up")
    }

    nonisolated static func visibilityIntentReplayReason(
        reason: String,
        hasPendingWakeVisibleAllowListReplay: Bool
    ) -> String {
        guard hasPendingWakeVisibleAllowListReplay,
              reason.hasPrefix("healthy-validation-screen-parameters-changed"),
              !isPostWakeVisibleAllowListReplayReason(reason)
        else {
            return reason
        }
        return "healthy-validation-wake-resume-\(reason)"
    }

    nonisolated static func canRepairWakeVisibleAllowListFromHiddenSnapshot(
        _ snapshot: MenuBarRuntimeSnapshot
    ) -> Bool {
        guard snapshot.structuralState == .ready,
              snapshot.startupItemsValid,
              snapshot.visibilityPhase == .hidden,
              snapshot.mainAnchorSource == .live,
              snapshot.separatorAnchorSource == .cached,
              snapshot.mainItemVisible != false,
              snapshot.separatorItemVisible != false,
              snapshot.hasAnyScreens,
              snapshot.separatorX != nil,
              snapshot.mainX != nil
        else {
            return false
        }

        switch snapshot.geometryConfidence {
        case .cached:
            return true
        case .live, .shielded, .stale, .missing:
            return false
        }
    }

    nonisolated static func shouldRunVisibilityIntentEnforcement(
        reason: String,
        snapshot: MenuBarRuntimeSnapshot,
        hasVisibleAllowList: Bool,
        hasPendingWakeVisibleAllowListReplay: Bool
    ) -> Bool {
        guard snapshot.structuralState == .ready,
              snapshot.visibilityPhase != .transitioning
        else {
            return false
        }

        if snapshot.hasLiveCoreAnchors, snapshot.geometryConfidence == .live {
            return true
        }

        guard hasVisibleAllowList,
              hasPendingWakeVisibleAllowListReplay,
              isPostWakeVisibleAllowListReplayReason(reason) else { return false }
        return canRepairWakeVisibleAllowListFromHiddenSnapshot(snapshot)
    }

    nonisolated static func shouldDeferHiddenStateForWakeVisibleAllowList(
        reason: String,
        hideAllOtherMenuBarItems: Bool,
        visibleAllowListIds: [String],
        hasPendingWakeVisibleAllowListReplay: Bool = false
    ) -> Bool {
        isPostWakeVisibleAllowListReplayReason(reason) &&
            hasPendingWakeVisibleAllowListReplay &&
            hideAllOtherMenuBarItems &&
            !visibleAllowListIds.isEmpty
    }

    nonisolated static func shouldReplayWakeVisibleAllowListBeforeAutoRehide(
        reason: String,
        hideAllOtherMenuBarItems: Bool,
        visibleAllowListIds: [String],
        hasPendingWakeVisibleAllowListReplay: Bool
    ) -> Bool {
        let isImmediateWakeRecovery = reason == "wakeResume" || reason == "wake-resume"
        return isImmediateWakeRecovery &&
            hasPendingWakeVisibleAllowListReplay &&
            hideAllOtherMenuBarItems &&
            !visibleAllowListIds.isEmpty
    }
}

@MainActor
extension MenuBarManager {
    func visibilityIntentReplayHideAllOtherMode(
        reason: String
    ) -> (mode: MenuBarVisibilityIntentMode, physicalMoveOrigin: MenuBarPhysicalMoveOrigin?) {
        let snapshot = currentStatusItemRecoverySnapshot()
        let confidence = snapshot.geometryConfidence
        let hasVisibleAllowList = settings.hideAllOtherMenuBarItems &&
            !settings.hideAllOtherVisibleItemIds.isEmpty
        let hasPendingWakeVisibleAllowListReplay = statusItemRecoveryWorkflow
            .hasPendingWakeVisibleAllowListReplay()
        let resolved = MenuBarVisibilityPolicy.visibilityIntentReplayMode(
            reason: reason,
            geometryConfidence: confidence,
            hidingState: hidingService.state,
            hasVisibleAllowList: hasVisibleAllowList,
            hasPendingWakeVisibleAllowListReplay: hasPendingWakeVisibleAllowListReplay,
            canRepairHiddenWakeVisibleAllowList: MenuBarVisibilityPolicy
                .canRepairWakeVisibleAllowListFromHiddenSnapshot(snapshot)
        )
        if resolved.mode == .repairWithPhysicalMoves {
            AccessibilityService.shared.automaticMoveGate.arm()
        } else if MenuBarVisibilityPolicy.isPostWakeVisibleAllowListReplayReason(reason) {
            statusItemRecoveryWorkflow.pendingDeferredWakeRestoreReason = reason
            visibilityReplayLogger.warning(
                "Visibility replay downgraded to audit-only (\(reason, privacy: .public)): geometry confidence is \(confidence.rawValue, privacy: .public)"
            )
        }
        return resolved
    }

    func restoreHiddenStateAfterHealthyValidationIfNeeded(reason: String) {
        guard MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
            hidingState: hidingService.state,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor
        ) else {
            pendingRecoveryHideRestore = false
            return
        }

        if MenuBarVisibilityPolicy.shouldDeferHiddenStateForWakeVisibleAllowList(
            reason: reason,
            hideAllOtherMenuBarItems: settings.hideAllOtherMenuBarItems,
            visibleAllowListIds: settings.hideAllOtherVisibleItemIds,
            hasPendingWakeVisibleAllowListReplay: statusItemRecoveryWorkflow
                .hasPendingWakeVisibleAllowListReplay()
        ) {
            pendingRecoveryHideRestore = true
            visibilityReplayLogger.info(
                "Deferring hidden state after wake until Hide All Other visible allow-list replay completes (\(reason, privacy: .public))"
            )
            return
        }

        let snapshot = currentStatusItemRecoverySnapshot()
        guard MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
            hidingState: hidingService.state,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor,
            snapshot: snapshot,
            requiresLiveGeometryForVisibleAllowList: settings.hideAllOtherMenuBarItems &&
                !settings.hideAllOtherVisibleItemIds.isEmpty
        ) else {
            pendingRecoveryHideRestore = true
            visibilityReplayLogger.warning(
                "Deferring hidden state after healthy validation until status-item anchors are live (\(reason, privacy: .public), structure=\(snapshot.structuralState.rawValue, privacy: .public), main=\(snapshot.mainAnchorSource.rawValue, privacy: .public), separator=\(snapshot.separatorAnchorSource.rawValue, privacy: .public))"
            )
            return
        }

        pendingRecoveryHideRestore = false
        hidingService.applyCurrentStateToLiveItems()
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
        visibilityReplayLogger.info("Reapplied hidden state after healthy validation (\(reason, privacy: .public))")
    }

    func restoreHiddenStateAfterPostRecoveryGeometryWarmupIfNeeded(snapshot: MenuBarRuntimeSnapshot) {
        let shouldRestoreHidden = MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
            hidingState: hidingService.state,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor
        )
        if !shouldRestoreHidden {
            pendingRecoveryHideRestore = false
            visibilityReplayLogger.info("Skipping post-recovery hidden state restore because hide is no longer allowed")
            return
        }

        if MenuBarVisibilityPolicy.shouldDeferHiddenStateForWakeVisibleAllowList(
            reason: "status-item-recreate-wake-resume",
            hideAllOtherMenuBarItems: settings.hideAllOtherMenuBarItems,
            visibleAllowListIds: settings.hideAllOtherVisibleItemIds,
            hasPendingWakeVisibleAllowListReplay: statusItemRecoveryWorkflow
                .hasPendingWakeVisibleAllowListReplay()
        ) {
            pendingRecoveryHideRestore = true
            visibilityReplayLogger.info(
                "Deferring post-recovery hidden state warmup until wake visible allow-list replay completes"
            )
            return
        }

        guard MenuBarVisibilityPolicy.canApplyHiddenStateAfterStatusItemRecovery(
            hidingState: hidingService.state,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor,
            snapshot: snapshot,
            requiresLiveGeometryForVisibleAllowList: settings.hideAllOtherMenuBarItems &&
                !settings.hideAllOtherVisibleItemIds.isEmpty
        ) else {
            pendingRecoveryHideRestore = true
            visibilityReplayLogger.warning(
                "Deferring hidden state restore until status-item anchors are live (structure=\(snapshot.structuralState.rawValue, privacy: .public), main=\(snapshot.mainAnchorSource.rawValue, privacy: .public), separator=\(snapshot.separatorAnchorSource.rawValue, privacy: .public))"
            )
            return
        }

        pendingRecoveryHideRestore = false
        hidingService.applyCurrentStateToLiveItems()
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
        visibilityReplayLogger.info("Restored hidden state after post-recovery geometry warmup")
    }

    func restorePendingHiddenStateAfterVisibilityReplayFailure(reason: String) {
        defer {
            if statusItemRecoveryWorkflow.pendingWakeVisibleAllowListReplayExpired() {
                statusItemRecoveryWorkflow.clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)
            }
        }

        guard pendingRecoveryHideRestore else { return }
        guard MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
            hidingState: hidingService.state,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor
        ) else {
            pendingRecoveryHideRestore = false
            visibilityReplayLogger.info("Skipping hidden-state replay failure fallback because hide is no longer allowed")
            return
        }

        pendingRecoveryHideRestore = false
        hidingService.applyCurrentStateToLiveItems()
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
        visibilityReplayLogger.warning("Restored hidden state after visibility intent replay failed (\(reason, privacy: .public))")
    }

    func hasActionableDeferredWakeVisibleAllowListRepair() -> Bool {
        statusItemRecoveryWorkflow.pendingDeferredWakeRestoreReason != nil &&
            settings.hideAllOtherMenuBarItems &&
            !settings.hideAllOtherVisibleItemIds.isEmpty
    }

    func markWakeVisibleAllowListReplayPending(reason: String, requiresHiddenState: Bool = true) {
        guard settings.hideAllOtherMenuBarItems,
              !settings.hideAllOtherVisibleItemIds.isEmpty
        else {
            return
        }
        guard !requiresHiddenState || hidingService.state == .hidden else {
            return
        }
        statusItemRecoveryWorkflow.markWakeVisibleAllowListReplayPending(reason: reason)
    }

    func schedulePostRecoveryAutoRehideIfNeeded(reason: String) {
        if MenuBarVisibilityPolicy.shouldReplayWakeVisibleAllowListBeforeAutoRehide(
            reason: reason,
            hideAllOtherMenuBarItems: settings.hideAllOtherMenuBarItems,
            visibleAllowListIds: settings.hideAllOtherVisibleItemIds,
            hasPendingWakeVisibleAllowListReplay: statusItemRecoveryWorkflow
                .hasPendingWakeVisibleAllowListReplay()
        ) {
            visibilityReplayLogger.info(
                "Deferring post-wake auto-rehide until Hide All Other visible allow-list replay completes (\(reason, privacy: .public))"
            )
            schedulePostRecoveryVisibilityIntentReplay(reason: "healthy-validation-wake-resume")
            return
        }
        guard settings.autoRehide, hidingService.state == .expanded, !isRevealPinned, !shouldSkipHideForExternalMonitor else { return }
        visibilityReplayLogger.info("Auto-rehide rearmed after recovery replay (\(reason, privacy: .public))")
        hidingService.scheduleRehide(after: 0.5)
    }
}
