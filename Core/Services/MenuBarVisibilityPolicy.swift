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

    nonisolated static func shouldRecoverStartupPositions(
        separatorX: CGFloat?,
        mainX: CGFloat?,
        mainRightGap: CGFloat? = nil,
        screenWidth: CGFloat? = nil,
        notchRightSafeMinX: CGFloat? = nil
    ) -> Bool {
        guard let separatorX, let mainX else { return false }
        guard separatorX > 0, mainX > 0 else { return false }
        if separatorX >= mainX {
            return true
        }

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

@MainActor
extension MenuBarManager {
    func visibilityIntentReplayHideAllOtherMode(
        reason: String
    ) -> (mode: MenuBarVisibilityIntentMode, physicalMoveOrigin: MenuBarPhysicalMoveOrigin?) {
        if reason.contains("wake-resume") {
            return (.repairWithPhysicalMoves, .systemWakeRecovery)
        }
        return (.auditOnly, nil)
    }

    func restoreHiddenStateAfterHealthyValidationIfNeeded(reason: String) {
        guard MenuBarVisibilityPolicy.shouldRestoreHiddenAfterStatusItemRecovery(
            hidingState: hidingService.state,
            shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor
        ) else { return }

        hidingService.applyCurrentStateToLiveItems()
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)
        visibilityReplayLogger.info("Reapplied hidden state after healthy validation (\(reason, privacy: .public))")
    }

    func schedulePostRecoveryAutoRehideIfNeeded(reason: String) {
        if reason.contains("wakeResume") { isRevealPinned = false }
        guard settings.autoRehide, hidingService.state == .expanded, !isRevealPinned, !shouldSkipHideForExternalMonitor else { return }
        visibilityReplayLogger.info("Auto-rehide rearmed after recovery replay (\(reason, privacy: .public))")
        hidingService.scheduleRehide(after: 0.5)
    }
}
