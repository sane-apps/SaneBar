import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarMoveTaskCoordinator")

@MainActor
final class MenuBarMoveTaskCoordinator {
    enum QueuedAlwaysHiddenMutation {
        case pin(bundleID: String, menuExtraId: String?, statusItemIndex: Int?)
        case unpin(bundleID: String, menuExtraId: String?, statusItemIndex: Int?)
    }

    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func queueDetachedMoveTask(
        operationName: String,
        optimisticAlwaysHiddenMutation: QueuedAlwaysHiddenMutation? = nil,
        _ operation: @escaping @Sendable (MenuBarManager) async -> Bool
    ) -> Bool {
        let manager = self.manager
        manager.activeMoveTask = Task.detached(priority: .userInitiated) { [weak manager] () async -> Bool in
            guard let manager else { return false }

            await MainActor.run {
                manager.alwaysHiddenPinEnforcementTask?.cancel()
                manager.alwaysHiddenPinEnforcementTask = nil
                manager.alwaysHiddenSeparatorRepairGeneration += 1
                manager.alwaysHiddenSeparatorRepairFollowUpTask?.cancel()
                manager.alwaysHiddenSeparatorRepairFollowUpTask = nil
                SearchWindowController.shared.setMoveInProgress(true)
                manager.hidingService.cancelRehide()
                AccessibilityService.shared.beginMenuBarCacheWarmupSuppression()
            }
            logger.info("\(operationName, privacy: .public) task started")
            let operationSuccess = await operation(manager)
            let success = !Task.isCancelled && operationSuccess
            await MainActor.run {
                if success {
                    self.applyQueuedAlwaysHiddenMutation(optimisticAlwaysHiddenMutation)
                    manager.alwaysHiddenPinEnforcementTask?.cancel()
                    manager.alwaysHiddenPinEnforcementTask = nil
                } else {
                    self.rollbackQueuedAlwaysHiddenMutation(optimisticAlwaysHiddenMutation)
                }
                manager.lastManualZoneMoveSettledAt = Date()
                manager.activeMoveTask = nil
                // Move tasks already leave behind a fresh post-move cache.
                // Replaying deferred reveal/conceal warmups here just adds a
                // second AX refresh on top of the work we already finished.
                AccessibilityService.shared.endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: false)
                SearchWindowController.shared.setMoveInProgress(false)
            }
            return success
        }

        return true
    }

    func queuedMoveTaskIfStarted(_ started: Bool) -> Task<Bool, Never>? {
        guard started, let task = manager.activeMoveTask else { return nil }
        return task
    }

    func waitForActiveMoveTaskIfNeeded() async {
        if let task = manager.activeMoveTask {
            _ = await task.value
        }
    }

    func refreshAccessibilityCacheAfterMove() async {
        await MainActor.run {
            AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
        }
        _ = await AccessibilityService.shared.refreshKnownMenuBarItemsWithPositions()
        await MainActor.run {
            NotificationCenter.default.post(name: .menuBarIconsDidChange, object: nil)
        }
    }

    private func applyQueuedAlwaysHiddenMutation(_ mutation: QueuedAlwaysHiddenMutation?) {
        guard let mutation else { return }
        switch mutation {
        case let .pin(bundleID, menuExtraId, statusItemIndex):
            _ = manager.alwaysHiddenPinWorkflow.pin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        case let .unpin(bundleID, menuExtraId, statusItemIndex):
            _ = removeQueuedAlwaysHiddenPin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }
    }

    private func rollbackQueuedAlwaysHiddenMutation(_ mutation: QueuedAlwaysHiddenMutation?) {
        guard let mutation else { return }
        switch mutation {
        case let .pin(bundleID, menuExtraId, statusItemIndex):
            _ = removeQueuedAlwaysHiddenPin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        case let .unpin(bundleID, menuExtraId, statusItemIndex):
            _ = manager.alwaysHiddenPinWorkflow.pin(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }
    }

    private func removeQueuedAlwaysHiddenPin(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> Bool {
        manager.alwaysHiddenPinWorkflow.unpin(
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex
        ) || (!bundleID.hasPrefix("com.apple.controlcenter") && manager.alwaysHiddenPinWorkflow.unpin(bundleID: bundleID))
    }
}
