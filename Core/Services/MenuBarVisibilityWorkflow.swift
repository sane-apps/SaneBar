import AppKit
import ApplicationServices
import LocalAuthentication
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarVisibilityWorkflow")

@MainActor
final class MenuBarVisibilityWorkflow {
    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func canAutoRehideAtFireTime() -> Bool {
        autoRehideBlockReason() == "none"
    }

    func autoRehideBlockReason() -> String {
        let browseController = SearchWindowController.shared

        if browseController.isMoveInProgress {
            return "move-in-progress"
        }
        if browseController.isBrowseSessionActive {
            return "browse-session-active"
        }
        if browseController.isVisible {
            return "browse-visible"
        }
        if manager.isMenuOpen {
            return "status-menu-open"
        }
        if manager.hoverService.isSuspended {
            return "none"
        }

        let ownAppWindowActive = NSApp.isActive && NSApp.windows.contains { window in
            window.isVisible && window.isKeyWindow && !window.isMiniaturized
        }
        if MenuBarVisibilityPolicy.shouldIgnorePointerRehideBlockForOwnAppWindow(
            ownAppWindowActive: ownAppWindowActive,
            isStatusMenuOpen: manager.isMenuOpen,
            isBrowseSessionActive: browseController.isBrowseSessionActive,
            isBrowseVisible: browseController.isVisible
        ) {
            return "none"
        }

        if MenuBarVisibilityPolicy.shouldBlockRehideForMouseLocation(
            NSEvent.mouseLocation,
            screenFrames: NSScreen.screens.map(\.frame)
        ) {
            return "mouse-in-menu-bar-interaction-region"
        }

        return "none"
    }

    func scheduleRehideAfterSettingsChangeIfNeeded() {
        guard manager.settings.autoRehide else { return }
        guard manager.hidingService.state == .expanded else { return }
        guard !manager.isRevealPinned else { return }
        guard !manager.shouldSkipHideForExternalMonitor else { return }

        manager.hidingService.scheduleRehide(after: manager.settings.rehideDelay)
    }

    func toggleHiddenItems(trigger: MenuBarRevealTrigger = .automation) {
        Task { @MainActor in
            let currentState = manager.hidingService.state
            let authSetting = manager.settings.requireAuthToShowHiddenIcons
            logger.info("toggleHiddenItems() called - state: \(currentState.rawValue), authSetting: \(authSetting)")

            if currentState == .expanded, manager.shouldSkipHideForExternalMonitor {
                logger.info("toggleHiddenItems(): external monitor policy active, honoring explicit user toggle")
            }

            if currentState == .hidden, authSetting {
                guard !manager.isAuthenticating else {
                    logger.info("Auth already in progress, skipping duplicate prompt")
                    return
                }
                manager.isAuthenticating = true
                logger.info("Auth required to show hidden icons, prompting...")
                let ok = await authenticate(reason: "Show hidden menu bar icons")
                manager.isAuthenticating = false
                guard ok else {
                    logger.info("Auth failed or cancelled, aborting toggle")
                    return
                }
            }

            if currentState == .hidden {
                manager.lastMenuBarRevealTrigger = trigger
            }

            await manager.hidingService.toggle()
            logger.info("hidingService.toggle() completed, new state: \(self.manager.hidingService.state.rawValue)")

            if manager.hidingService.state == .hidden {
                manager.isRevealPinned = false
                manager.hidingService.cancelRehide()
            }

            if manager.hidingService.state == .expanded,
               manager.settings.autoRehide,
               !manager.isRevealPinned,
               !manager.shouldSkipHideForExternalMonitor {
                manager.hidingService.scheduleRehide(after: manager.settings.rehideDelay)
            }
        }
    }

    func showHiddenItemsNow(trigger: MenuBarRevealTrigger) async -> Bool {
        if manager.shouldSkipHideForExternalMonitor {
            let didReveal = manager.hidingService.state == .hidden
            if didReveal {
                manager.lastMenuBarRevealTrigger = trigger
                await manager.hidingService.show()
            }
            await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
            _ = manager.geometryResolver.separatorOriginX()
            _ = manager.geometryResolver.separatorRightEdgeX()
            manager.hidingService.cancelRehide()
            return didReveal
        }

        if manager.settings.requireAuthToShowHiddenIcons {
            guard !manager.isAuthenticating else { return false }
            manager.isAuthenticating = true
            let ok = await authenticate(reason: "Show hidden menu bar icons")
            manager.isAuthenticating = false
            guard ok else { return false }
        }

        if trigger == .settingsButton {
            manager.isRevealPinned = true
            manager.hidingService.cancelRehide()
        }

        let didReveal = manager.hidingService.state == .hidden
        if didReveal {
            manager.lastMenuBarRevealTrigger = trigger
        }
        await manager.hidingService.show()
        await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
        _ = manager.geometryResolver.separatorOriginX()
        _ = manager.geometryResolver.separatorRightEdgeX()

        let shouldScheduleImmediateRehide = trigger != .search && trigger != .findIcon
        if shouldScheduleImmediateRehide,
           manager.settings.autoRehide,
           !manager.isRevealPinned,
           !manager.shouldSkipHideForExternalMonitor {
            manager.hidingService.scheduleRehide(after: manager.settings.rehideDelay)
        }
        return didReveal
    }

    func scheduleRehideFromSearch(after delay: TimeInterval) {
        guard manager.settings.autoRehide else {
            logger.debug("Search rehide skipped because auto-rehide is disabled")
            return
        }
        guard !manager.shouldSkipHideForExternalMonitor else { return }
        let browseController = SearchWindowController.shared
        if browseController.isBrowseSessionActive || browseController.isVisible {
            logger.debug("Search rehide deferred while Browse Icons is visible")
            return
        }
        manager.hidingService.scheduleRehide(after: delay)
    }

    func showHiddenItems() {
        logger.info("showHiddenItems() requested")
        Task { @MainActor in
            _ = await showHiddenItemsNow(trigger: .automation)
        }
    }

    func hideHiddenItems() {
        logger.info("hideHiddenItems() requested")
        Task { @MainActor in
            manager.isRevealPinned = false
            manager.hidingService.cancelRehide()
            await manager.hidingService.hide()
        }
    }

    func scheduleAppMenuSuppressionEvaluation() {
        manager.appMenuSuppressionTask?.cancel()
        manager.appMenuSuppressionTask = nil

        guard MenuBarVisibilityPolicy.shouldManageApplicationMenus(
            hideApplicationMenusOnInlineReveal: manager.settings.hideApplicationMenusOnInlineReveal,
            showDockIcon: manager.settings.showDockIcon,
            accessibilityGranted: AccessibilityService.shared.isGranted,
            hidingState: manager.hidingService.state,
            revealTrigger: manager.lastMenuBarRevealTrigger
        ) else {
            if !manager.settings.hideApplicationMenusOnInlineReveal {
                restoreApplicationMenusIfNeeded(reason: "settingDisabled")
            } else if manager.settings.showDockIcon {
                restoreApplicationMenusIfNeeded(reason: "dockIconEnabled")
            } else if !AccessibilityService.shared.isGranted {
                restoreApplicationMenusIfNeeded(reason: "axNotGranted")
            } else if !MenuBarVisibilityPolicy.shouldSuppressApplicationMenus(for: manager.lastMenuBarRevealTrigger) {
                restoreApplicationMenusIfNeeded(reason: "passiveReveal")
            } else {
                restoreApplicationMenusIfNeeded(reason: "sectionHidden")
            }
            return
        }

        guard !manager.isAppMenuSuppressed else { return }

        manager.appMenuSuppressionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await evaluateAppMenuSuppressionNow()
        }
    }

    func restoreApplicationMenusIfNeeded(reason: String) {
        manager.appMenuSuppressionTask?.cancel()
        manager.appMenuSuppressionTask = nil
        manager.appMenuDockPolicyTask?.cancel()
        manager.appMenuDockPolicyTask = nil

        guard manager.isAppMenuSuppressed else { return }
        manager.isAppMenuSuppressed = false
        let appToRestore = manager.appToReactivateAfterSuppression
        manager.appToReactivateAfterSuppression = nil

        let currentFrontmostApp = NSWorkspace.shared.frontmostApplication
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let shouldReactivateSavedApp = MenuBarVisibilityPolicy.shouldReactivateSavedAppAfterSuppression(
            savedAppPID: appToRestore?.processIdentifier,
            currentFrontmostPID: currentFrontmostApp?.processIdentifier,
            ownPID: ownPID
        )

        if shouldReactivateSavedApp,
           let appToRestore,
           !appToRestore.isTerminated {
            _ = appToRestore.activate(options: [])
        } else if currentFrontmostApp?.processIdentifier == ownPID || currentFrontmostApp == nil {
            NSApp.deactivate()
        }

        if !manager.settings.showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }

        logger.info("Restored application menus (\(reason, privacy: .public))")
    }

    func authenticate(reason: String) async -> Bool {
        if let lastFailed = manager.lastFailedAuthTime,
           manager.failedAuthAttempts >= manager.maxFailedAttempts {
            let elapsed = Date().timeIntervalSince(lastFailed)
            if elapsed < manager.lockoutDuration {
                let attempts = manager.failedAuthAttempts
                let remaining = Int(manager.lockoutDuration - elapsed)
                logger.warning("Auth rate limited: \(attempts) failed attempts, \(remaining)s remaining")
                return false
            }
            manager.failedAuthAttempts = 0
            manager.lastFailedAuthTime = nil
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

        if success {
            manager.failedAuthAttempts = 0
            manager.lastFailedAuthTime = nil
        } else {
            manager.failedAuthAttempts += 1
            manager.lastFailedAuthTime = Date()
            let attempts = manager.failedAuthAttempts
            let maxAttempts = manager.maxFailedAttempts
            logger.info("Auth failed, attempt \(attempts)/\(maxAttempts)")
        }

        return success
    }

    private func evaluateAppMenuSuppressionNow() async {
        guard manager.hidingService.state == .expanded else {
            restoreApplicationMenusIfNeeded(reason: "sectionHidden")
            return
        }

        guard let appMenuFrame = currentFrontAppMenuFrame() else {
            return
        }

        guard let leftmostVisibleItemX = await leftmostVisibleMenuItemX() else {
            return
        }

        guard MenuBarVisibilityPolicy.shouldHideApplicationMenus(
            leftmostVisibleItemX: leftmostVisibleItemX,
            appMenuMaxX: appMenuFrame.maxX
        ) else {
            return
        }

        suppressApplicationMenusIfNeeded()
    }

    private func suppressApplicationMenusIfNeeded() {
        guard !manager.isAppMenuSuppressed else { return }
        guard !manager.settings.showDockIcon else { return }

        manager.appToReactivateAfterSuppression = NSWorkspace.shared.frontmostApplication
        manager.isAppMenuSuppressed = true
        NSApp.activate(ignoringOtherApps: true)
        scheduleAppMenuDockPolicyReassertionIfNeeded()
        logger.info("Temporarily hid application menus due to overlap")
    }

    private func scheduleAppMenuDockPolicyReassertionIfNeeded() {
        manager.appMenuDockPolicyTask?.cancel()
        manager.appMenuDockPolicyTask = nil

        guard manager.isAppMenuSuppressed else { return }
        guard !manager.settings.showDockIcon else { return }

        reassertAccessoryPolicyDuringAppMenuSuppression(reason: "suppressionStarted")

        manager.appMenuDockPolicyTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for delay in MenuBarVisibilityPolicy.appMenuDockPolicyReassertionIntervalsNanoseconds {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                guard manager.isAppMenuSuppressed else { return }
                guard !manager.settings.showDockIcon else { return }

                reassertAccessoryPolicyDuringAppMenuSuppression(reason: "suppressionHold")
            }
        }
    }

    private func reassertAccessoryPolicyDuringAppMenuSuppression(reason: String) {
        guard manager.isAppMenuSuppressed else { return }
        guard !manager.settings.showDockIcon else { return }

        let currentPolicy = NSApp.activationPolicy()
        let hasDockBadge = NSApp.dockTile.badgeLabel != nil
        if currentPolicy != .accessory || hasDockBadge {
            logger.warning(
                "Reasserting accessory policy during app-menu suppression (\(reason, privacy: .public), policy=\(String(describing: currentPolicy), privacy: .public), badge=\(hasDockBadge, privacy: .public))"
            )
        }

        NSApp.dockTile.badgeLabel = nil
        if currentPolicy != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
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
              let menuBarElement = safeAXUIElement(menuBarValue)
        else {
            return nil
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let menuBarItems = childrenValue as? [AXUIElement],
              !menuBarItems.isEmpty
        else {
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
              let axPosition = safeAXValue(positionValue)
        else {
            return nil
        }

        var origin = CGPoint.zero
        guard AXValueGetValue(axPosition, .cgPoint, &origin) else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sizeValue,
              let axSize = safeAXValue(sizeValue)
        else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axSize, .cgSize, &size) else { return nil }

        return CGRect(origin: origin, size: size)
    }
}
