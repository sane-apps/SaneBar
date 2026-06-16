import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarObserverWorkflow")

@MainActor
final class MenuBarObserverWorkflow {
    private unowned let manager: MenuBarManager
    private var cancellables = Set<AnyCancellable>()
    private var previousObservedSettings = SaneBarSettings()

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func setInitialSettings(_ settings: SaneBarSettings) {
        previousObservedSettings = settings
    }

    func setupObservers() {
        manager.hidingService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                manager.setObservedHidingState(state)
                manager.updateStatusItemAppearance()
            }
            .store(in: &cancellables)

        manager.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.applySettingsChange(newSettings)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleActivatedApplication(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .hiddenSectionShown)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.manager.visibilityWorkflow.scheduleAppMenuSuppressionEvaluation()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .hiddenSectionHidden)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.manager.visibilityWorkflow.restoreApplicationMenusIfNeeded(reason: "sectionHidden")
            }
            .store(in: &cancellables)

        installScreenAndWakeObservers()
        installLaunchObservers()

        LicenseService.shared.$isPro
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.manager.actionWorkflow.normalizeLicenseDependentDefaults()
            }
            .store(in: &cancellables)
    }

    private func applySettingsChange(_ newSettings: SaneBarSettings) {
        let oldSettings = previousObservedSettings
        manager.updateSpacers()
        manager.updateAppearance()
        manager.updateNetworkTrigger(enabled: newSettings.showOnNetworkChange)
        manager.updateFocusModeTrigger(enabled: newSettings.showOnFocusModeChange)
        manager.updateScheduleTrigger(enabled: newSettings.showOnSchedule)
        manager.updateScriptTrigger(settings: newSettings)
        manager.triggerService.updateBatteryMonitoring(enabled: newSettings.showOnLowBattery)
        manager.updateHoverService()
        manager.actionWorkflow.syncUpdateConfiguration()
        manager.updateMainIconVisibility()
        manager.updateDividerStyle()
        manager.updateIconStyle()
        manager.updateAlwaysHiddenSeparator()
        manager.enforceExternalMonitorVisibilityPolicy(reason: "settingsChanged")
        manager.applyAutoRehideSettingsChange(from: oldSettings, to: newSettings)
        if newSettings.showDockIcon {
            manager.visibilityWorkflow.restoreApplicationMenusIfNeeded(reason: "dockIconEnabled")
        } else if manager.hidingState == .expanded {
            manager.visibilityWorkflow.scheduleAppMenuSuppressionEvaluation()
        }
        previousObservedSettings = newSettings
        manager.saveSettings()
    }

    private func handleActivatedApplication(_ notification: Notification) {
        if manager.hidingState == .expanded {
            manager.visibilityWorkflow.scheduleAppMenuSuppressionEvaluation()
        }

        let activatedBundleID =
            (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
        let browseSessionActive = SearchWindowController.shared.isBrowseSessionActive
        let ownBundleID = Bundle.main.bundleIdentifier

        if MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange(
            rehideOnAppChange: manager.settings.rehideOnAppChange,
            autoRehideEnabled: manager.settings.autoRehide,
            hidingState: manager.hidingState,
            isRevealPinned: manager.isRevealPinned,
            shouldSkipHideForExternalMonitor: manager.shouldSkipHideForExternalMonitor,
            isBrowseSessionActive: browseSessionActive,
            activatedBundleID: activatedBundleID,
            ownBundleID: ownBundleID
        ) {
            logger.debug(
                "App changed - scheduling auto-hide for \(activatedBundleID ?? "unknown", privacy: .public)"
            )
            manager.hidingService.scheduleRehide(after: 0.5)
        } else if manager.settings.rehideOnAppChange, manager.hidingState == .expanded {
            if browseSessionActive {
                logger.debug("App changed - skipping auto-hide while Browse Icons is active")
            } else if let activatedBundleID,
                      let ownBundleID,
                      activatedBundleID == ownBundleID {
                logger.debug("App changed - ignoring SaneBar self-activation")
            }
        }
    }

    private func installScreenAndWakeObservers() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "screenParametersChanged")
                logger.debug("Screen parameters changed - refreshed cached separator policy")
                manager.enforceExternalMonitorVisibilityPolicy(reason: "screenParametersChanged")
                // Replay pinned visibility intent only after validation reports healthy anchors.
                manager.schedulePositionValidation(context: .screenParametersChanged)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                manager.positionValidationGeneration += 1
                manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "willSleep")
                logger.debug("System will sleep - cancelled pending position validation and refreshed cached separator policy")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                manager.positionValidationGeneration += 1
                manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "screensDidSleep")
                logger.debug("Screens did sleep - cancelled pending position validation and refreshed cached separator policy")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleActiveSpaceChange()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleWakeResume(notificationName: "System did wake")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleWakeResume(notificationName: "Screens did wake")
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleWakeResume(notificationName: "Session became active")
            }
            .store(in: &cancellables)
    }

    private func handleWakeResume(notificationName: String) {
        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "wakeResume")
        logger.debug("\(notificationName, privacy: .public) - refreshed cached separator policy")
        manager.enforceExternalMonitorVisibilityPolicy(reason: "wakeResume")
        // Wake can briefly report stale menu-bar coordinates; validation owns replay once stable.
        manager.schedulePositionValidation(context: .wakeResume)
        manager.schedulePostRecoveryAutoRehideIfNeeded(reason: "wakeResume")
    }

    private func handleActiveSpaceChange() {
        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "activeSpaceChanged")
        logger.debug("Active Space changed - refreshed cached separator policy")
        manager.enforceExternalMonitorVisibilityPolicy(reason: "activeSpaceChanged")
        // Space switches can briefly report stale menu-bar coordinates on macOS 27;
        // validation owns hidden-state replay once the active Space settles.
        manager.schedulePositionValidation(context: .activeSpaceChanged)
        manager.schedulePostRecoveryAutoRehideIfNeeded(reason: "activeSpaceChanged")
    }

    private func installLaunchObservers() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.handleAlwaysHiddenCandidateLaunch(note)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.handleHideAllOtherCandidateLaunch(note)
            }
            .store(in: &cancellables)
    }

    private func handleAlwaysHiddenCandidateLaunch(_ note: Notification) {
        guard manager.alwaysHiddenSeparatorItem != nil else { return }
        guard !manager.settings.alwaysHiddenPinnedItemIds.isEmpty else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        let pinnedBundleIds = manager.alwaysHiddenPinWorkflow.pinnedBundleIds()
        guard pinnedBundleIds.contains(bundleID) else { return }

        manager.alwaysHiddenPinWorkflow.scheduleEnforcement(
            reason: "didLaunch:\(bundleID)",
            filterBundleId: bundleID,
            delay: .seconds(1)
        )
    }

    private func handleHideAllOtherCandidateLaunch(_ note: Notification) {
        guard manager.settings.hideAllOtherMenuBarItems else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }

        manager.hideAllOtherWorkflow.scheduleEnforcement(
            reason: "didLaunch:\(bundleID)",
            filterBundleId: bundleID,
            delay: .seconds(1)
        )
    }
}
