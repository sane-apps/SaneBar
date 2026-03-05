import AppKit
import ApplicationServices
import LocalAuthentication
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Visibility")

extension MenuBarManager {
    // MARK: - Visibility Control

    func canAutoRehideAtFireTime() -> Bool {
        let browseController = SearchWindowController.shared

        // Never auto-hide while Browse Icons / second menu bar is visible
        // or while a drag move is actively running.
        if browseController.isMoveInProgress {
            return false
        }
        // Never auto-hide while a browse panel is actually visible.
        // This must not depend on session flags: if visibility is true, user is
        // actively in a panel and rehide should be suspended.
        if browseController.isVisible {
            return false
        }

        if isMenuOpen {
            return false
        }

        // Browse/Icon Panel intentionally suspends hover tracking. In that state,
        // stale hover-region state must not block rehide forever.
        if hoverService.isSuspended {
            return true
        }

        return !hoverService.isMouseInMenuBar
    }

    enum RevealTrigger: String, Sendable {
        case hotkey
        case search
        case automation
        case settingsButton
        case findIcon
    }

    // MARK: - Visibility Policy

    func shouldIgnoreHideRequest(origin: HideRequestOrigin) -> Bool {
        Self.shouldIgnoreHideRequest(
            disableOnExternalMonitor: settings.disableOnExternalMonitor,
            isOnExternalMonitor: isOnExternalMonitor,
            origin: origin
        )
    }

    static func shouldSkipHide(disableOnExternalMonitor: Bool, isOnExternalMonitor: Bool) -> Bool {
        shouldIgnoreHideRequest(
            disableOnExternalMonitor: disableOnExternalMonitor,
            isOnExternalMonitor: isOnExternalMonitor,
            origin: .automatic
        )
    }

    static func shouldIgnoreHideRequest(
        disableOnExternalMonitor: Bool,
        isOnExternalMonitor: Bool,
        origin: HideRequestOrigin
    ) -> Bool {
        disableOnExternalMonitor && isOnExternalMonitor && origin == .automatic
    }

    static func shouldRecoverStartupPositions(
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

        // On notched displays, keep the main icon in the right auxiliary area
        // (near Control Center). If it drifts left of this boundary, treat as
        // corrupted placement and recover startup positions.
        if let notchRightSafeMinX, notchRightSafeMinX > 0 {
            let notchTolerance: CGFloat = 8
            if mainX < (notchRightSafeMinX - notchTolerance) {
                return true
            }
        }

        // Machine-specific corruption can preserve an apparently "ordered"
        // separator/main pair that still lands far from the Control Center side.
        // Recover when the main icon drifts too far from the right edge.
        guard let mainRightGap, let screenWidth else { return false }
        guard mainRightGap > 0, screenWidth > 0 else { return false }

        let maxAllowedRightGap = max(500, screenWidth * 0.45)
        return mainRightGap > maxAllowedRightGap
    }

    func toggleHiddenItems() {
        Task {
            let currentState = hidingService.state
            let authSetting = settings.requireAuthToShowHiddenIcons
            logger.info("toggleHiddenItems() called - state: \(currentState.rawValue), authSetting: \(authSetting)")

            if currentState == .expanded, shouldSkipHideForExternalMonitor {
                logger.info("toggleHiddenItems(): external monitor policy active, honoring explicit user toggle")
            }

            // If we're about to SHOW (hidden -> expanded), optionally gate with auth.
            // Use hidingService.state directly (not cached hidingState) to avoid sync issues
            if currentState == .hidden, authSetting {
                // Guard against duplicate auth prompts
                guard !isAuthenticating else {
                    logger.info("Auth already in progress, skipping duplicate prompt")
                    return
                }
                isAuthenticating = true
                logger.info("Auth required to show hidden icons, prompting...")
                let ok = await authenticate(reason: "Show hidden menu bar icons")
                isAuthenticating = false
                guard ok else {
                    logger.info("Auth failed or cancelled, aborting toggle")
                    return
                }
            }

            await hidingService.toggle()
            logger.info("hidingService.toggle() completed, new state: \(self.hidingService.state.rawValue)")

            // If user explicitly hid everything, unpin.
            if hidingService.state == .hidden {
                isRevealPinned = false
                hidingService.cancelRehide()
            }

            // Schedule auto-rehide if enabled and we just showed
            if hidingService.state == .expanded, settings.autoRehide, !isRevealPinned, !shouldSkipHideForExternalMonitor {
                hidingService.scheduleRehide(after: settings.rehideDelay)
            }
        }
    }

    /// Reveal hidden icons immediately, returning whether the reveal occurred.
    /// Search and hotkeys should await this before attempting virtual clicks.
    @MainActor
    func showHiddenItemsNow(trigger: RevealTrigger) async -> Bool {
        if shouldSkipHideForExternalMonitor {
            let didReveal = hidingService.state == .hidden
            if didReveal {
                await hidingService.show()
            }
            hidingService.cancelRehide()
            return didReveal
        }

        if settings.requireAuthToShowHiddenIcons {
            guard !isAuthenticating else { return false }
            isAuthenticating = true
            let ok = await authenticate(reason: "Show hidden menu bar icons")
            isAuthenticating = false
            guard ok else { return false }
        }

        // Manual reveal should pin and cancel any pending auto-rehide.
        if trigger == .settingsButton {
            isRevealPinned = true
            hidingService.cancelRehide()
        }

        let didReveal = hidingService.state == .hidden
        await hidingService.show()

        // Search / Find Icon paths use their own dedicated delay handling so
        // we don't double-schedule and close target menus too early.
        let shouldScheduleImmediateRehide = trigger != .search && trigger != .findIcon

        // Refresh rehide timer on user/automation reveals to prevent icons
        // hiding while the user is still actively interacting with them.
        if shouldScheduleImmediateRehide, settings.autoRehide, !isRevealPinned, !shouldSkipHideForExternalMonitor {
            hidingService.scheduleRehide(after: settings.rehideDelay)
        }
        return didReveal
    }

    /// Schedule a rehide specifically from Find Icon / Browse Icons flows.
    /// This always hides (ignores autoRehide setting) but defers while Browse Icons
    /// stays visible, so active panel interactions are never interrupted.
    @MainActor
    func scheduleRehideFromSearch(after delay: TimeInterval) {
        guard !shouldSkipHideForExternalMonitor else { return }
        if SearchWindowController.shared.isVisible {
            logger.debug("Search rehide deferred while Browse Icons is visible")
            return
        }
        hidingService.scheduleRehide(after: delay)
    }

    func showHiddenItems() {
        logger.info("showHiddenItems() requested")
        Task {
            // `showHiddenItems()` is used by automation/hotkey/script trigger paths.
            // Keep this reveal temporary so auto-rehide remains functional.
            _ = await showHiddenItemsNow(trigger: .automation)
        }
    }

    func hideHiddenItems() {
        logger.info("hideHiddenItems() requested")
        Task {
            isRevealPinned = false
            hidingService.cancelRehide()
            await hidingService.hide()
        }
    }

    // MARK: - App Menu Suppression (Ice-style overlap handling)

    nonisolated static func shouldHideApplicationMenus(
        leftmostVisibleItemX: CGFloat,
        appMenuMaxX: CGFloat,
        collisionPadding: CGFloat = 2
    ) -> Bool {
        leftmostVisibleItemX <= (appMenuMaxX + collisionPadding)
    }

    func scheduleAppMenuSuppressionEvaluation() {
        appMenuSuppressionTask?.cancel()
        appMenuSuppressionTask = nil

        guard !settings.showDockIcon else {
            restoreApplicationMenusIfNeeded(reason: "dockIconEnabled")
            return
        }

        guard AccessibilityService.shared.isGranted else {
            restoreApplicationMenusIfNeeded(reason: "axNotGranted")
            return
        }

        guard hidingService.state == .expanded else {
            restoreApplicationMenusIfNeeded(reason: "sectionHidden")
            return
        }

        // Once we temporarily suppress menus, keep that state until we hide again.
        guard !isAppMenuSuppressed else { return }

        appMenuSuppressionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await evaluateAppMenuSuppressionNow()
        }
    }

    func restoreApplicationMenusIfNeeded(reason: String) {
        appMenuSuppressionTask?.cancel()
        appMenuSuppressionTask = nil

        guard isAppMenuSuppressed else { return }
        isAppMenuSuppressed = false
        let appToRestore = appToReactivateAfterSuppression
        appToReactivateAfterSuppression = nil

        if let appToRestore,
           !appToRestore.isTerminated,
           appToRestore.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            _ = appToRestore.activate(options: [])
        } else {
            NSApp.deactivate()
        }

        if !settings.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }

        logger.info("Restored application menus (\(reason, privacy: .public))")
    }

    private func evaluateAppMenuSuppressionNow() async {
        guard hidingService.state == .expanded else {
            restoreApplicationMenusIfNeeded(reason: "sectionHidden")
            return
        }

        guard let appMenuFrame = currentFrontAppMenuFrame() else {
            return
        }

        guard let leftmostVisibleItemX = await leftmostVisibleMenuItemX() else {
            return
        }

        guard Self.shouldHideApplicationMenus(
            leftmostVisibleItemX: leftmostVisibleItemX,
            appMenuMaxX: appMenuFrame.maxX
        ) else {
            return
        }

        suppressApplicationMenusIfNeeded()
    }

    private func suppressApplicationMenusIfNeeded() {
        guard !isAppMenuSuppressed else { return }
        guard !settings.showDockIcon else { return }

        appToReactivateAfterSuppression = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        isAppMenuSuppressed = true
        logger.info("Temporarily hid application menus due to overlap")
    }

    private func leftmostVisibleMenuItemX() async -> CGFloat? {
        let classified = await SearchService.shared.refreshClassifiedApps()
        return (classified.visible + classified.hidden)
            .filter { ($0.width ?? 0) > 0 }
            .compactMap(\.xPosition)
            .min()
    }

    private func currentFrontAppMenuFrame() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        guard frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarValue,
              let menuBarElement = safeAXUIElement(menuBarValue) else {
            return nil
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let menuBarItems = childrenValue as? [AXUIElement],
              !menuBarItems.isEmpty else {
            return nil
        }

        var frameUnion: CGRect?
        for item in menuBarItems {
            guard axElementIsEnabled(item) else { continue }
            guard let frame = axFrame(of: item), frame.width > 0, frame.height > 0 else { continue }
            frameUnion = frameUnion.map { $0.union(frame) } ?? frame
        }

        return frameUnion
    }

    private func axElementIsEnabled(_ element: AXUIElement) -> Bool {
        var enabledValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue) == .success else {
            return true
        }

        if let enabled = enabledValue as? Bool {
            return enabled
        }
        if let enabled = enabledValue as? NSNumber {
            return enabled.boolValue
        }
        return true
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              let positionValue,
              let axPosition = safeAXValue(positionValue) else {
            return nil
        }

        var origin = CGPoint.zero
        guard AXValueGetValue(axPosition, .cgPoint, &origin) else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sizeValue,
              let axSize = safeAXValue(sizeValue) else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axSize, .cgSize, &size) else { return nil }

        return CGRect(origin: origin, size: size)
    }

    // MARK: - Privacy Auth

    func authenticate(reason: String) async -> Bool {
        // Rate limiting: check if locked out from too many failed attempts
        if let lastFailed = lastFailedAuthTime,
           failedAuthAttempts >= maxFailedAttempts {
            let elapsed = Date().timeIntervalSince(lastFailed)
            if elapsed < lockoutDuration {
                let attempts = failedAuthAttempts
                let remaining = Int(lockoutDuration - elapsed)
                logger.warning("Auth rate limited: \(attempts) failed attempts, \(remaining)s remaining")
                return false
            }
            // Lockout expired, reset counter
            failedAuthAttempts = 0
            lastFailedAuthTime = nil
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }

        // Track failed attempts for rate limiting
        if success {
            failedAuthAttempts = 0
            lastFailedAuthTime = nil
        } else {
            failedAuthAttempts += 1
            lastFailedAuthTime = Date()
            let attempts = failedAuthAttempts
            let maxAttempts = maxFailedAttempts
            logger.info("Auth failed, attempt \(attempts)/\(maxAttempts)")
        }

        return success
    }
}
