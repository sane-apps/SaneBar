import Foundation

struct BrowsePanelMoveContext {
    let isAlwaysHiddenEnabled: Bool
    let manager: MenuBarManager
    let setMovingAppID: (String?) -> Void
}

enum BrowsePanelMoveQueue {
    static func zoneMoveRequest(
        from sourceZone: BrowseAppZone,
        to targetZone: BrowseAppZone,
        isAlwaysHiddenEnabled: Bool
    ) -> MenuBarZoneMoveRequest? {
        switch (sourceZone, targetZone) {
        case (.visible, .hidden):
            return .visibleToHidden
        case (.hidden, .visible):
            return .hiddenToVisible
        case (.visible, .alwaysHidden):
            return isAlwaysHiddenEnabled ? .visibleToAlwaysHidden : nil
        case (.hidden, .alwaysHidden):
            return isAlwaysHiddenEnabled ? .hiddenToAlwaysHidden : nil
        case (.alwaysHidden, .visible):
            return .alwaysHiddenToVisible
        case (.alwaysHidden, .hidden):
            return .alwaysHiddenToHidden
        case (.visible, .visible), (.hidden, .hidden), (.alwaysHidden, .alwaysHidden):
            return nil
        }
    }

    @MainActor
    static func observeMoveResult(
        _ task: Task<Bool, Never>,
        setMovingAppID: @escaping (String?) -> Void
    ) {
        Task { @MainActor in
            let moved = await task.value
            if !moved {
                setMovingAppID(nil)
            }
        }
    }

    @MainActor
    static func queueMove(
        app: RunningApp,
        from sourceZone: BrowseAppZone,
        to targetZone: BrowseAppZone,
        context: BrowsePanelMoveContext
    ) -> Bool {
        let request = zoneMoveRequest(
            from: sourceZone,
            to: targetZone,
            isAlwaysHiddenEnabled: context.isAlwaysHiddenEnabled
        )

        guard let request,
              let task = context.manager.moveQueueWorkflow.queueZoneMove(app: app, request: request) else { return false }

        context.setMovingAppID(app.uniqueId)
        observeMoveResult(task, setMovingAppID: context.setMovingAppID)
        return true
    }

    @MainActor
    static func queueMoveAfterDrop(
        app: RunningApp,
        from sourceZone: BrowseAppZone,
        to targetZone: BrowseAppZone,
        context: BrowsePanelMoveContext
    ) -> Bool {
        guard let request = zoneMoveRequest(
            from: sourceZone,
            to: targetZone,
            isAlwaysHiddenEnabled: context.isAlwaysHiddenEnabled
        ) else { return false }

        context.setMovingAppID(app.uniqueId)
        Task { @MainActor in
            await Task.yield()
            guard let task = await context.manager.moveQueueWorkflow.queueZoneMoveAfterDrop(app: app, request: request) else {
                context.setMovingAppID(nil)
                return
            }
            observeMoveResult(task, setMovingAppID: context.setMovingAppID)
        }
        return true
    }

    @MainActor
    static func queueReorder(
        sourceApp: RunningApp,
        targetApp: RunningApp,
        context: BrowsePanelMoveContext
    ) -> Bool {
        let sourceX = sourceApp.xPosition ?? 0
        let targetX = targetApp.xPosition ?? 0
        let placeAfterTarget = sourceX < targetX

        guard let task = context.manager.moveQueueWorkflow.queueReorderIcon(
            sourceBundleID: sourceApp.bundleId,
            sourceMenuExtraID: sourceApp.menuExtraIdentifier,
            sourceStatusItemIndex: sourceApp.statusItemIndex,
            targetBundleID: targetApp.bundleId,
            targetMenuExtraID: targetApp.menuExtraIdentifier,
            targetStatusItemIndex: targetApp.statusItemIndex,
            placeAfterTarget: placeAfterTarget
        ) else {
            return false
        }

        context.setMovingAppID(sourceApp.uniqueId)
        observeMoveResult(task, setMovingAppID: context.setMovingAppID)
        return true
    }

    @MainActor
    static func queueReorderAfterDrop(
        sourceApp: RunningApp,
        targetApp: RunningApp,
        context: BrowsePanelMoveContext
    ) -> Bool {
        Task { @MainActor in
            await Task.yield()
            _ = queueReorder(
                sourceApp: sourceApp,
                targetApp: targetApp,
                context: context
            )
        }
        return true
    }
}
