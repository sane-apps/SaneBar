import AppKit
import os.log
import SaneUI
import ServiceManagement

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarLifecycleWorkflow")

@MainActor
final class MenuBarLifecycleWorkflow {
    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func loadSettings() {
        manager.settingsController.loadOrDefault()
        manager.settings = manager.settingsController.settings
        manager.observerWorkflow.setInitialSettings(manager.settings)

        // Apply dock visibility immediately so the Dock icon does not flash on startup.
        SaneActivationPolicy.applyPolicy(showDockIcon: manager.settings.showDockIcon)
    }

    /// Deferred UI setup with initial delay to ensure WindowServer is ready.
    func deferredUISetup() {
        let initialDelay = MenuBarManager.statusItemCreationDelaySeconds(
            environmentOverrideMs: ProcessInfo.processInfo.environment["SANEBAR_STATUSITEM_DELAY_MS"],
            majorOSVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak manager] in
            guard let manager else { return }
            logger.info("Starting deferred UI setup")

            manager.statusItemSetupWorkflow.setupStatusItem()
            manager.updateSpacers()
            manager.observerWorkflow.setupObservers()
            manager.updateAppearance()

            manager.triggerService.configure(menuBarManager: manager)
            manager.iconHotkeysService.configure(with: manager)
            manager.networkTriggerService.configure(menuBarManager: manager)
            if manager.settings.showOnNetworkChange {
                manager.networkTriggerService.startMonitoring()
            }

            manager.focusModeService.configure(menuBarManager: manager)
            if manager.settings.showOnFocusModeChange {
                manager.focusModeService.startMonitoring()
            }

            manager.scheduleTriggerService.configure(menuBarManager: manager)
            if manager.settings.showOnSchedule {
                manager.scheduleTriggerService.startMonitoring()
            }

            manager.scriptTriggerService.configure(menuBarManager: manager)
            if manager.settings.scriptTriggerEnabled {
                manager.scriptTriggerService.startMonitoring()
            }

            self.configureHoverService()
            self.showOnboardingIfNeeded()
            manager.actionWorkflow.syncUpdateConfiguration()
            AccessibilityService.shared.prewarmCache()

            logger.info("Deferred UI setup complete")
        }
    }

    func applySettingsSideEffects() {
        manager.iconHotkeysService.registerHotkeys(from: manager.settings)
        manager.updateHoverService()
        if manager.settings.hideAllOtherMenuBarItems {
            manager.hideAllOtherWorkflow.scheduleEnforcement(reason: "settingsChanged", delay: .milliseconds(500))
        } else {
            manager.hideAllOtherRuleEnforcementTask?.cancel()
            manager.hideAllOtherRuleEnforcementTask = nil
        }
    }

    func updateNetworkTrigger(enabled: Bool) {
        if enabled {
            manager.networkTriggerService.startMonitoring()
        } else {
            manager.networkTriggerService.stopMonitoring()
        }
    }

    func updateFocusModeTrigger(enabled: Bool) {
        if enabled {
            manager.focusModeService.startMonitoring()
        } else {
            manager.focusModeService.stopMonitoring()
        }
    }

    func updateScheduleTrigger(enabled: Bool) {
        if enabled {
            manager.scheduleTriggerService.startMonitoring()
        } else {
            manager.scheduleTriggerService.stopMonitoring()
        }
    }

    func updateScriptTrigger(settings: SaneBarSettings) {
        if settings.scriptTriggerEnabled {
            manager.scriptTriggerService.restartIfRunning()
            manager.scriptTriggerService.startMonitoring()
        } else {
            manager.scriptTriggerService.stopMonitoring()
        }
    }

    private func configureHoverService() {
        manager.hoverService.onTrigger = { [weak manager] reason in
            guard let manager else { return }
            Task { @MainActor in
                guard !manager.isMenuOpen else {
                    logger.debug("Ignoring hover trigger while status menu is open")
                    return
                }
                logger.debug("Hover trigger received: \(String(describing: reason))")

                switch reason {
                case .hover:
                    _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .hover)

                case let .scroll(direction):
                    if manager.settings.useDirectionalScroll {
                        if direction == .up {
                            _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .scroll)
                        } else if !manager.shouldSkipHideForExternalMonitor {
                            manager.visibilityWorkflow.hideHiddenItems()
                        }
                    } else if manager.settings.gestureToggles {
                        if manager.shouldSkipHideForExternalMonitor {
                            _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .scroll)
                        } else {
                            manager.visibilityWorkflow.toggleHiddenItems(trigger: .scroll)
                        }
                    } else {
                        _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .scroll)
                    }

                case .click:
                    if manager.settings.gestureToggles {
                        if manager.shouldSkipHideForExternalMonitor {
                            _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .click)
                        } else {
                            manager.visibilityWorkflow.toggleHiddenItems(trigger: .click)
                        }
                    } else {
                        _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .click)
                    }

                case .userDrag:
                    _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .userDrag)
                    manager.isRevealPinned = true
                }
            }
        }

        manager.hoverService.onUserDragEnd = { [weak manager] in
            guard let manager else { return }
            Task { @MainActor in
                guard !manager.isMenuOpen else { return }

                await manager.alwaysHiddenPinWorkflow.reconcileAfterUserDrag()

                manager.isRevealPinned = false
                if manager.settings.autoRehide, !manager.shouldSkipHideForExternalMonitor {
                    manager.hidingService.scheduleRehide(after: manager.settings.rehideDelay)
                }
            }
        }

        manager.hoverService.onLeaveMenuBar = { [weak manager] in
            guard let manager else { return }
            Task { @MainActor in
                guard !manager.isMenuOpen else { return }
                if manager.settings.autoRehide, !manager.isRevealPinned, !manager.shouldSkipHideForExternalMonitor {
                    manager.hidingService.scheduleRehide(after: manager.settings.rehideDelay)
                }
            }
        }

        manager.updateHoverService()
    }

    private func showOnboardingIfNeeded() {
        if !manager.settings.hasCompletedOnboarding {
            manager.settings.autoRehide = true
            manager.settings.rehideDelay = 5.0
            manager.settings.showOnHover = true
            manager.settings.showOnScroll = true
            manager.settings.showOnUserDrag = true
            manager.settings.hasSeenFreemiumIntro = true
            manager.saveSettings()
            Task.detached { await EventTracker.log("new_free_user") }

            if canMutateLaunchAtLogin() {
                try? SMAppService.mainApp.register()
                logger.info("Applied Smart defaults for first-launch onboarding (incl. launch at login)")
            } else {
                logger.warning("Skipping launch-at-login auto-register for non-canonical app path: \(Bundle.main.bundleURL.path, privacy: .public)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardingController.shared.show()
            }
        } else if !manager.settings.hasSeenFreemiumIntro {
            manager.settings.hasSeenFreemiumIntro = true
            manager.saveSettings()
            logger.info("Legacy upgrade detected - showing freemium intro (manual grant only)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                OnboardingController.shared.show()
            }
        } else if !manager.settings.hasCompletedHealthWizard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                HealthWizardController.shared.showIfNeeded()
            }
        }
    }

    /// Prevent development/test builds from mutating persistent login-item state.
    private func canMutateLaunchAtLogin() -> Bool {
        let bundlePath = Bundle.main.bundleURL.path
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        if bundlePath.contains("/DerivedData/") { return false }
        if bundleID.hasSuffix(".dev") { return false }
        return bundlePath.hasPrefix("/Applications/")
    }
}
