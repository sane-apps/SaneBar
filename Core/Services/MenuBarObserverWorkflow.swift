import AppKit
import Combine
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarObserverWorkflow")
private let displayBeginConfigurationFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 0)
private let displayMovedFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 1)
private let displaySetMainFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 2)
private let displaySetModeFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 3)
private let displayAddFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 4)
private let displayRemoveFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 5)
private let displayEnabledFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 8)
private let displayDisabledFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 9)
private let displayMirrorFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 10)
private let displayUnMirrorFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 11)
private let displayDesktopShapeChangedFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 12)
private let displayTopologyChangedFlags = CGDisplayChangeSummaryFlags(
    rawValue: displayMovedFlag.rawValue |
        displaySetMainFlag.rawValue |
        displaySetModeFlag.rawValue |
        displayAddFlag.rawValue |
        displayRemoveFlag.rawValue |
        displayEnabledFlag.rawValue |
        displayDisabledFlag.rawValue |
        displayMirrorFlag.rawValue |
        displayUnMirrorFlag.rawValue |
        displayDesktopShapeChangedFlag.rawValue
)

@MainActor
final class MenuBarObserverWorkflow {
    private unowned let manager: MenuBarManager
    private var cancellables = Set<AnyCancellable>()
    private var previousObservedSettings = SaneBarSettings()
    private var displayReconfigurationObserverInstalled = false
    private var displayResumePendingAfterDisable = false
    /// Display arrangement fingerprint observed at the last screen-parameters
    /// event. Used to distinguish a genuine display-topology change from the
    /// spurious `didChangeScreenParametersNotification` macOS posts on a plain
    /// sleep/wake — see `screenParametersValidationContext` (#136/#153).
    private var lastObservedDisplayFingerprint = ""

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    deinit {
        guard displayReconfigurationObserverInstalled else { return }
        CGDisplayRemoveReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
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
                self?.manager.updateDividerStyle()
                self?.manager.visibilityWorkflow.scheduleAppMenuSuppressionEvaluation()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .hiddenSectionHidden)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.manager.updateDividerStyle()
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

        if MenuBarVisibilityPolicy.shouldValidateStatusItemsAfterAppActivation(
            hidingState: manager.hidingState,
            shouldSkipHideForExternalMonitor: manager.shouldSkipHideForExternalMonitor,
            isBrowseSessionActive: browseSessionActive,
            activatedBundleID: activatedBundleID,
            ownBundleID: ownBundleID
        ) {
            manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "applicationActivated")
            logger.debug(
                "App activated - scheduling hidden status-item validation for \(activatedBundleID ?? "unknown", privacy: .public)"
            )
            manager.schedulePositionValidation(context: .activeSpaceChanged)
            manager.schedulePostRecoveryAutoRehideIfNeeded(reason: "applicationActivated")
        }
    }

    /// Picks the position-validation context for a screen-parameters
    /// notification. macOS posts `didChangeScreenParametersNotification` on a
    /// plain sleep/wake even when the display arrangement is identical; treating
    /// that as a topology change reanchors (and launders) the user's explicit
    /// divider toward Control Center (#136/#153). When the display fingerprint is
    /// unchanged, validate as a non-destructive `.wakeResume` instead — which the
    /// recovery decision already treats as steady-state (no reanchor/reset),
    /// while a genuine change keeps `.screenParametersChanged` (topology).
    nonisolated static func screenParametersValidationContext(
        displayActuallyChanged: Bool
    ) -> MenuBarOperationCoordinator.PositionValidationContext {
        displayActuallyChanged ? .screenParametersChanged : .wakeResume
    }

    private func installScreenAndWakeObservers() {
        // Seed the baseline so the first screen-parameters event is compared
        // against the arrangement present when observers came online.
        lastObservedDisplayFingerprint = MenuBarDisplayConfiguration.currentFingerprint()
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "screenParametersChanged")
                manager.cancelVisibilityIntentReplayTask(reason: "screenParametersChanged")
                logger.debug("Screen parameters changed - refreshed cached separator policy")
                manager.enforceExternalMonitorVisibilityPolicy(reason: "screenParametersChanged")
                // `didChangeScreenParametersNotification` also fires on a plain
                // sleep/wake when the display arrangement is byte-for-byte identical.
                // Treating that spurious event as a display-topology change authorizes
                // a destructive reanchor that clamps the user's explicit divider toward
                // Control Center (#136/#153 — "moves right then back after wake"). Only
                // validate as a topology change when the fingerprint actually changed;
                // otherwise validate as a non-destructive wake so the divider survives.
                let fingerprint = MenuBarDisplayConfiguration.currentFingerprint()
                let displayActuallyChanged = fingerprint != lastObservedDisplayFingerprint
                lastObservedDisplayFingerprint = fingerprint
                let validationContext = Self.screenParametersValidationContext(
                    displayActuallyChanged: displayActuallyChanged
                )
                logger.debug(
                    "Screen parameters changed - displayActuallyChanged=\(displayActuallyChanged, privacy: .public) → validating as \(validationContext.rawValue, privacy: .public)"
                )
                // Replay pinned visibility intent only after validation reports healthy anchors.
                manager.schedulePositionValidation(context: validationContext)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                manager.positionValidationGeneration += 1
                manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "willSleep")
                manager.cancelWakeVisibleAllowListReplay(reason: "willSleep")
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
                manager.cancelWakeVisibleAllowListReplay(reason: "screensDidSleep")
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
                self?.handleSessionBecameActive()
            }
            .store(in: &cancellables)

        installDisplayReconfigurationObserver()
    }

    private func installDisplayReconfigurationObserver() {
        guard !displayReconfigurationObserverInstalled else { return }

        let result = CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if result == .success {
            displayReconfigurationObserverInstalled = true
            logger.debug("Installed CoreGraphics display reconfiguration observer")
        } else {
            logger.error(
                "Failed to install CoreGraphics display reconfiguration observer: \(result.rawValue, privacy: .public)"
            )
        }
    }

    private nonisolated static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { display, flags, userInfo in
        guard let userInfo else { return }
        let workflow = Unmanaged<MenuBarObserverWorkflow>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor [workflow] in
            workflow.handleDisplayReconfiguration(display: display, flags: flags)
        }
    }

    private func handleDisplayReconfiguration(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(displayBeginConfigurationFlag) {
            cancelStaleDisplayValidation(
                reason: "displayReconfigurationBegin",
                display: display,
                flags: flags
            )
            return
        }

        if flags.contains(displayDisabledFlag) {
            displayResumePendingAfterDisable = true
            cancelStaleDisplayValidation(
                reason: "displayReconfigurationDisabled",
                display: display,
                flags: flags
            )
            return
        }

        guard !flags.isDisjoint(with: displayTopologyChangedFlags) else { return }

        if flags.contains(displayEnabledFlag) || displayResumePendingAfterDisable {
            displayResumePendingAfterDisable = false
            handleWakeResume(notificationName: "Display reconfiguration wake")
            return
        }

        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "screenParametersChanged")
        manager.cancelVisibilityIntentReplayTask(reason: "screenParametersChanged")
        logger.debug(
            "Display reconfiguration changed - refreshed cached separator policy (display=\(display, privacy: .public), flags=\(flags.rawValue, privacy: .public))"
        )
        manager.enforceExternalMonitorVisibilityPolicy(reason: "screenParametersChanged")
        manager.schedulePositionValidation(context: .screenParametersChanged)
    }

    private func cancelStaleDisplayValidation(
        reason: String,
        display: CGDirectDisplayID,
        flags: CGDisplayChangeSummaryFlags
    ) {
        manager.positionValidationGeneration += 1
        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: reason)
        manager.cancelWakeVisibleAllowListReplay(reason: reason)
        logger.debug(
            "Display reconfiguration invalidated pending status-item validation (\(reason, privacy: .public), display=\(display, privacy: .public), flags=\(flags.rawValue, privacy: .public))"
        )
    }

    private func handleWakeResume(notificationName: String) {
        manager.positionValidationGeneration += 1
        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "wakeResume")
        logger.debug("\(notificationName, privacy: .public) - refreshed cached separator policy")
        manager.enforceExternalMonitorVisibilityPolicy(reason: "wakeResume")
        // Wake can briefly report stale menu-bar coordinates. Arm the visible
        // allow-list replay immediately, but let the guarded replay path wait
        // for healthy anchors before any physical moves.
        manager.markWakeVisibleAllowListReplayPending(reason: "wakeResume")
        manager.schedulePositionValidation(context: .wakeResume)
        manager.schedulePostRecoveryAutoRehideIfNeeded(reason: "wakeResume")
    }

    private func handleSessionBecameActive() {
        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "sessionDidBecomeActive")
        logger.debug("Session became active - refreshed cached separator policy")
        manager.enforceExternalMonitorVisibilityPolicy(reason: "sessionDidBecomeActive")
        // Unlock/fast-user-switch can disturb status items, but it must not grant
        // the cached hidden-snapshot exception reserved for real wake recovery.
        manager.schedulePositionValidation(context: .activeSpaceChanged)
        manager.schedulePostRecoveryAutoRehideIfNeeded(reason: "sessionDidBecomeActive")
    }

    private func handleActiveSpaceChange() {
        manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: "activeSpaceChanged")
        manager.cancelVisibilityIntentReplayTask(reason: "activeSpaceChanged")
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
