import Foundation
import os.log

private let profileLogger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Profiles")
@MainActor private var triggerProfileApplicationKeys: [String: Date] = [:]
@MainActor private var activeTriggerProfileIds = Set<UUID>()

extension SaneBarSettings {
    func preservingAutomation(from current: SaneBarSettings) -> SaneBarSettings {
        var next = self
        next.showOnAppLaunch = current.showOnAppLaunch
        next.triggerApps = current.triggerApps
        next.appLaunchTriggerAction = current.appLaunchTriggerAction
        next.appLaunchTriggerProfileId = current.appLaunchTriggerProfileId
        next.showOnLowBattery = current.showOnLowBattery
        next.batteryThreshold = current.batteryThreshold
        next.batteryTriggerAction = current.batteryTriggerAction
        next.batteryTriggerProfileId = current.batteryTriggerProfileId
        next.showOnNetworkChange = current.showOnNetworkChange
        next.triggerNetworks = current.triggerNetworks
        next.networkTriggerAction = current.networkTriggerAction
        next.networkTriggerProfileId = current.networkTriggerProfileId
        next.showOnFocusModeChange = current.showOnFocusModeChange
        next.triggerFocusModes = current.triggerFocusModes
        next.focusTriggerAction = current.focusTriggerAction
        next.focusTriggerProfileId = current.focusTriggerProfileId
        next.showOnSchedule = current.showOnSchedule
        next.scheduleWeekdays = current.scheduleWeekdays
        next.scheduleStartHour = current.scheduleStartHour
        next.scheduleStartMinute = current.scheduleStartMinute
        next.scheduleEndHour = current.scheduleEndHour
        next.scheduleEndMinute = current.scheduleEndMinute
        next.scheduleTriggerAction = current.scheduleTriggerAction
        next.scheduleTriggerProfileId = current.scheduleTriggerProfileId
        next.scriptTriggerEnabled = current.scriptTriggerEnabled
        next.scriptTriggerPath = current.scriptTriggerPath
        next.scriptTriggerInterval = current.scriptTriggerInterval
        return next
    }

    func preservingProtectedSettings(from current: SaneBarSettings) -> SaneBarSettings {
        var next = self
        if current.requireAuthToShowHiddenIcons, !next.requireAuthToShowHiddenIcons {
            next.requireAuthToShowHiddenIcons = true
        }
        return next
    }

    func preservingLocalLifecycleState(from current: SaneBarSettings) -> SaneBarSettings {
        var next = self
        next.hasCompletedOnboarding = current.hasCompletedOnboarding
        next.hasSeenFreemiumIntro = current.hasSeenFreemiumIntro
        next.hasCompletedHealthWizard = current.hasCompletedHealthWizard
        next.layoutRescueRestorePoint = current.layoutRescueRestorePoint
        next.layoutRescueRestorePointCreatedAt = current.layoutRescueRestorePointCreatedAt
        return next
    }
}

@MainActor
extension MenuBarManager {
    nonisolated static func canCreateLayoutRescueRestorePoint(from snapshot: MenuBarRuntimeSnapshot) -> Bool {
        guard snapshot.structuralState == .ready else { return false }
        guard snapshot.startupItemsValid else { return false }
        guard snapshot.hasTrustworthyBootstrapAnchors else { return false }

        switch snapshot.geometryConfidence {
        case .live, .cached:
            return true
        case .shielded, .stale, .missing:
            return false
        }
    }

    func savedProfiles() -> [SaneBarProfile] {
        do {
            return try PersistenceService.shared.listProfiles()
        } catch {
            profileLogger.error("Failed to list profiles: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func saveCurrentProfile(named name: String) throws {
        var profile = SaneBarProfile(
            name: name,
            settings: settings,
            layoutSnapshot: StatusBarController.captureLayoutSnapshot(),
            customIconSnapshot: PersistenceService.shared.makeCustomIconSnapshot()
        )
        profile.modifiedAt = Date()
        try PersistenceService.shared.saveProfile(profile)
    }

    @discardableResult
    func applyProfile(
        id: UUID,
        preserveAutomation: Bool = false,
        preserveProtectedSettings: Bool = true,
        reason: String = "manual"
    ) -> Bool {
        do {
            let profile = try PersistenceService.shared.loadProfile(id: id)
            applyProfile(
                profile,
                preserveAutomation: preserveAutomation,
                preserveProtectedSettings: preserveProtectedSettings,
                reason: reason
            )
            return true
        } catch {
            profileLogger.error("Failed to apply profile \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func applyProfile(
        _ profile: SaneBarProfile,
        preserveAutomation: Bool = false,
        preserveProtectedSettings: Bool = true,
        reason: String = "manual"
    ) {
        if let customIconSnapshot = profile.customIconSnapshot {
            do {
                try PersistenceService.shared.applyCustomIconSnapshot(customIconSnapshot)
            } catch {
                profileLogger.error("Failed to apply custom icon snapshot for profile \(profile.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if let layoutSnapshot = profile.layoutSnapshot {
            StatusBarController.applyLayoutSnapshot(layoutSnapshot)
        }

        var nextSettings = preserveAutomation
            ? profile.settings.preservingAutomation(from: settings)
            : profile.settings
        if preserveProtectedSettings {
            nextSettings = nextSettings.preservingProtectedSettings(from: settings)
        }
        nextSettings = nextSettings.preservingLocalLifecycleState(from: settings)

        settings = nextSettings
        saveSettings()
        restoreStatusItemLayoutIfNeeded()
        profileLogger.info("Applied profile \(profile.name, privacy: .public) reason=\(reason, privacy: .public)")
    }

    func runTriggerAction(
        _ action: SaneBarSettings.TriggerAction,
        profileId: UUID?,
        reason: String
    ) {
        switch action {
        case .showIcons:
            showHiddenItems()
        case .applyProfile:
            guard let profileId else {
                profileLogger.warning("Trigger \(reason, privacy: .public) requested profile action with no profile id; showing icons instead")
                showHiddenItems()
                return
            }
            let key = "\(reason)|\(profileId.uuidString)"
            let now = Date()
            if let lastApplied = triggerProfileApplicationKeys[key],
               now.timeIntervalSince(lastApplied) < 5 {
                profileLogger.info("Skipping duplicate trigger profile application reason=\(reason, privacy: .public)")
                return
            }
            guard activeTriggerProfileIds.insert(profileId).inserted else {
                profileLogger.info("Skipping reentrant trigger profile application reason=\(reason, privacy: .public)")
                return
            }
            defer { activeTriggerProfileIds.remove(profileId) }
            triggerProfileApplicationKeys[key] = now

            if !applyProfile(
                id: profileId,
                preserveAutomation: true,
                preserveProtectedSettings: true,
                reason: reason
            ) {
                showHiddenItems()
            }
        }
    }

    func arrangeNow(reason: String = "manual") {
        Task { @MainActor in
            _ = await repairMenuBarHealth(reason: "arrange-now-\(reason)")
        }
    }

    func repairMenuBarHealth(reason: String = "manual") async -> MenuBarRuntimeSnapshot {
        hidingService.cancelRehide()
        if hidingService.state == .hidden {
            await hidingService.show()
        }

        await warmSeparatorPositionCache(maxAttempts: 24)
        _ = getMainStatusItemLeftEdgeX()
        _ = getSeparatorRightEdgeX()

        let initialSnapshot = currentRuntimeSnapshot()
        if !Self.canCreateLayoutRescueRestorePoint(from: initialSnapshot) {
            restoreStatusItemLayoutIfNeeded()
        }

        for attempt in 1 ... 16 {
            if attempt > 1 {
                try? await Task.sleep(for: .milliseconds(150))
            }
            if hidingService.state == .hidden {
                await hidingService.show()
            }
            await warmSeparatorPositionCache(maxAttempts: 4)
            _ = getMainStatusItemLeftEdgeX()
            _ = getSeparatorRightEdgeX()

            let snapshot = currentRuntimeSnapshot()
            if Self.canCreateLayoutRescueRestorePoint(from: snapshot) {
                profileLogger.info(
                    "Health repair reached healthy snapshot after \(attempt, privacy: .public) check(s) reason=\(reason, privacy: .public)"
                )
                scheduleHideAllOtherRuleEnforcement(reason: "repair-\(reason)", delay: .milliseconds(250))
                return snapshot
            }
        }

        let finalSnapshot = currentRuntimeSnapshot()
        profileLogger.warning(
            "Health repair still needs attention reason=\(reason, privacy: .public) geometry=\(finalSnapshot.geometryConfidence.rawValue, privacy: .public) structure=\(finalSnapshot.structuralState.rawValue, privacy: .public)"
        )
        scheduleHideAllOtherRuleEnforcement(reason: "repair-\(reason)", delay: .milliseconds(250))
        return finalSnapshot
    }

    func setLayoutMode(_ mode: SaneBarSettings.LayoutMode, reason: String = "manual") async -> MenuBarRuntimeSnapshot? {
        guard settings.layoutMode != mode else { return nil }
        settings.layoutMode = mode
        saveSettings()

        guard mode == .live else { return nil }
        return await repairMenuBarHealth(reason: "layout-mode-live-\(reason)")
    }

    @discardableResult
    func createLayoutRescueRestorePoint(reason: String = "manual") -> Bool {
        let runtimeSnapshot = currentRuntimeSnapshot()
        guard Self.canCreateLayoutRescueRestorePoint(from: runtimeSnapshot) else {
            profileLogger.warning(
                "Layout rescue restore point skipped for unhealthy snapshot reason=\(reason, privacy: .public) geometry=\(runtimeSnapshot.geometryConfidence.rawValue, privacy: .public) structure=\(runtimeSnapshot.structuralState.rawValue, privacy: .public)"
            )
            return false
        }

        let snapshot = StatusBarController.captureLayoutSnapshot()
        settings.layoutRescueRestorePoint = snapshot
        settings.layoutRescueRestorePointCreatedAt = Date()
        saveSettings()
        profileLogger.info("Created layout rescue restore point reason=\(reason, privacy: .public)")
        return true
    }

    @discardableResult
    func restoreLayoutRescueRestorePoint(reason: String = "manual") -> Bool {
        guard let snapshot = settings.layoutRescueRestorePoint else {
            profileLogger.warning("Layout rescue restore requested without a restore point reason=\(reason, privacy: .public)")
            return false
        }

        StatusBarController.applyLayoutSnapshot(snapshot)
        saveSettings()
        restoreStatusItemLayoutIfNeeded()
        profileLogger.info("Restored layout rescue restore point reason=\(reason, privacy: .public)")
        return true
    }

    func completeHealthWizard() {
        settings.hasCompletedHealthWizard = true
        saveSettings()
    }
}
