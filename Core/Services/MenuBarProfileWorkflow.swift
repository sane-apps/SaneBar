import Foundation
import os.log

private let profileLogger = Logger(subsystem: "com.sanebar.app", category: "MenuBarProfileWorkflow")

@MainActor
final class MenuBarProfileWorkflow {
    private unowned let manager: MenuBarManager
    private var triggerProfileApplicationKeys: [String: Date] = [:]
    private var activeTriggerProfileIds = Set<UUID>()

    init(manager: MenuBarManager) {
        self.manager = manager
    }

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
            settings: manager.settings,
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
            ? profile.settings.preservingAutomation(from: manager.settings)
            : profile.settings
        if preserveProtectedSettings {
            nextSettings = nextSettings.preservingProtectedSettings(from: manager.settings)
        }
        nextSettings = nextSettings.preservingLocalLifecycleState(from: manager.settings)

        manager.settings = nextSettings
        manager.saveSettings()
        manager.restoreStatusItemLayoutIfNeeded()
        manager.schedulePostRecoveryVisibilityIntentReplay(reason: "profile-\(reason)")
        profileLogger.info("Applied profile \(profile.name, privacy: .public) reason=\(reason, privacy: .public)")
    }

    func runTriggerAction(
        _ action: SaneBarSettings.TriggerAction,
        profileId: UUID?,
        reason: String
    ) {
        switch action {
        case .showIcons:
            manager.visibilityWorkflow.showHiddenItems()
        case .applyProfile:
            guard let profileId else {
                profileLogger.warning("Trigger \(reason, privacy: .public) requested profile action with no profile id; showing icons instead")
                manager.visibilityWorkflow.showHiddenItems()
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
                manager.visibilityWorkflow.showHiddenItems()
            }
        }
    }

    func arrangeNow(reason: String = "manual") {
        Task { @MainActor [weak manager] in
            guard let manager else { return }
            _ = await manager.profileWorkflow.repairMenuBarHealth(reason: "arrange-now-\(reason)")
        }
    }

    func repairMenuBarHealth(reason: String = "manual") async -> MenuBarRuntimeSnapshot {
        manager.hidingService.cancelRehide()
        if manager.hidingService.state == .hidden {
            let didReveal = await revealHiddenIconsForHealthRepair(reason: reason)
            guard didReveal else {
                return manager.currentRuntimeSnapshot()
            }
        }

        await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 24)
        _ = manager.geometryResolver.mainStatusItemLeftEdgeX()
        _ = manager.geometryResolver.separatorRightEdgeX()

        let initialSnapshot = manager.currentRuntimeSnapshot()
        if !Self.canCreateLayoutRescueRestorePoint(from: initialSnapshot) {
            manager.restoreStatusItemLayoutIfNeeded()
        }

        for attempt in 1 ... 16 {
            if attempt > 1 {
                try? await Task.sleep(for: .milliseconds(150))
            }
            if manager.hidingService.state == .hidden {
                guard await revealHiddenIconsForHealthRepair(reason: reason) else {
                    return manager.currentRuntimeSnapshot()
                }
            }
            await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 4)
            _ = manager.geometryResolver.mainStatusItemLeftEdgeX()
            _ = manager.geometryResolver.separatorRightEdgeX()

            let snapshot = manager.currentRuntimeSnapshot()
            if Self.canCreateLayoutRescueRestorePoint(from: snapshot) {
                profileLogger.info(
                    "Health repair reached healthy snapshot after \(attempt, privacy: .public) check(s) reason=\(reason, privacy: .public)"
                )
                manager.schedulePostRecoveryVisibilityIntentReplay(reason: "repair-\(reason)")
                return snapshot
            }
        }

        let finalSnapshot = manager.currentRuntimeSnapshot()
        profileLogger.warning(
            "Health repair still needs attention reason=\(reason, privacy: .public) geometry=\(finalSnapshot.geometryConfidence.rawValue, privacy: .public) structure=\(finalSnapshot.structuralState.rawValue, privacy: .public)"
        )
        manager.schedulePostRecoveryVisibilityIntentReplay(reason: "repair-\(reason)")
        return finalSnapshot
    }

    private func revealHiddenIconsForHealthRepair(reason: String) async -> Bool {
        if manager.settings.requireAuthToShowHiddenIcons {
            guard !manager.isAuthenticating else { return false }
            manager.isAuthenticating = true
            let ok = await manager.visibilityWorkflow.authenticate(reason: "Repair hidden menu bar icons")
            manager.isAuthenticating = false
            guard ok else {
                profileLogger.info("Health repair hidden-icon reveal blocked by auth reason=\(reason, privacy: .public)")
                return false
            }
        }

        manager.hidingService.cancelRehide()
        await manager.hidingService.show()
        return true
    }

    func setLayoutMode(_ mode: SaneBarSettings.LayoutMode, reason: String = "manual") async -> MenuBarRuntimeSnapshot? {
        guard manager.settings.layoutMode != mode else { return nil }
        manager.settings.layoutMode = mode
        manager.saveSettings()

        guard mode == .live else { return nil }
        return await repairMenuBarHealth(reason: "layout-mode-live-\(reason)")
    }

    @discardableResult
    func createLayoutRescueRestorePoint(reason: String = "manual") -> Bool {
        let runtimeSnapshot = manager.currentRuntimeSnapshot()
        guard Self.canCreateLayoutRescueRestorePoint(from: runtimeSnapshot) else {
            profileLogger.warning(
                "Layout rescue restore point skipped for unhealthy snapshot reason=\(reason, privacy: .public) geometry=\(runtimeSnapshot.geometryConfidence.rawValue, privacy: .public) structure=\(runtimeSnapshot.structuralState.rawValue, privacy: .public)"
            )
            return false
        }

        let snapshot = StatusBarController.captureLayoutSnapshot()
        manager.settings.layoutRescueRestorePoint = snapshot
        manager.settings.layoutRescueRestorePointCreatedAt = Date()
        manager.saveSettings()
        profileLogger.info("Created layout rescue restore point reason=\(reason, privacy: .public)")
        return true
    }

    @discardableResult
    func restoreLayoutRescueRestorePoint(reason: String = "manual") -> Bool {
        guard let snapshot = manager.settings.layoutRescueRestorePoint else {
            profileLogger.warning("Layout rescue restore requested without a restore point reason=\(reason, privacy: .public)")
            return false
        }

        StatusBarController.applyLayoutSnapshot(snapshot)
        manager.saveSettings()
        manager.restoreStatusItemLayoutIfNeeded()
        profileLogger.info("Restored layout rescue restore point reason=\(reason, privacy: .public)")
        return true
    }

    func completeHealthWizard() {
        manager.settings.hasCompletedHealthWizard = true
        manager.saveSettings()
    }
}
