import LocalAuthentication
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Visibility")

extension MenuBarManager {
    // MARK: - Visibility Control

    enum RevealTrigger: String, Sendable {
        case hotkey
        case search
        case automation
        case settingsButton
        case findIcon
    }

    func toggleHiddenItems() {
        // Second menu bar mode: toggle the panel AND expand/collapse the real menu bar
        if settings.useSecondMenuBar {
            SearchWindowController.shared.toggle()
            // Also toggle the real delimiter so icons are accessible in the menu bar
            Task {
                if hidingService.state == .hidden {
                    await hidingService.show()
                } else {
                    await hidingService.hide()
                }
            }
            return
        }

        Task {
            let currentState = hidingService.state
            let authSetting = settings.requireAuthToShowHiddenIcons
            logger.info("toggleHiddenItems() called - state: \(currentState.rawValue), authSetting: \(authSetting)")

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
        // Second menu bar mode: show the panel alongside the real expand
        if settings.useSecondMenuBar {
            SearchWindowController.shared.show()
            // Don't return — fall through to also expand the real delimiter
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

        // Refresh rehide timer on every trigger (Hover/Scroll/Click) to prevent
        // icons hiding while the user is still actively interacting with them.
        if settings.autoRehide, !isRevealPinned, !shouldSkipHideForExternalMonitor {
            hidingService.scheduleRehide(after: settings.rehideDelay)
        }
        return didReveal
    }

    /// Schedule a rehide specifically from Find Icon search (always hides, ignores autoRehide setting)
    func scheduleRehideFromSearch(after delay: TimeInterval) {
        guard !isRevealPinned, !shouldSkipHideForExternalMonitor else { return }
        hidingService.scheduleRehide(after: delay)
    }

    func showHiddenItems() {
        Task {
            _ = await showHiddenItemsNow(trigger: .settingsButton)
        }
    }

    func hideHiddenItems() {
        // Second menu bar mode: close the panel alongside the real hide
        if settings.useSecondMenuBar {
            SearchWindowController.shared.close()
            // Don't return — fall through to also hide the real delimiter
        }

        Task {
            // Skip hiding if user is on external monitor and setting is enabled
            if shouldSkipHideForExternalMonitor {
                logger.debug("Skipping hide: user is on external monitor")
                return
            }

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
