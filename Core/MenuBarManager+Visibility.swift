import LocalAuthentication
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Visibility")

extension MenuBarManager {
    // MARK: - Visibility Control

    func canAutoRehideAtFireTime() -> Bool {
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
            _ = await showHiddenItemsNow(trigger: .settingsButton)
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
