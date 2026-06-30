import Foundation

struct BrowsePanelMoveContext {
    let isAlwaysHiddenEnabled: Bool
    let manager: MenuBarManager
    let setMovingAppID: (String?) -> Void
    /// Records the app whose move resolved to a retryable miss so
    /// the Second Menu Bar can surface a "couldn't move — try again" affordance
    /// instead of silently clearing the in-flight indicator. Informational only:
    /// this never synthesizes input or mutates geometry.
    var recordFailedMove: (String?) -> Void = { _ in }
}

enum BrowsePanelMoveQueue {
    static func zoneMoveRequest(
        from sourceZone: BrowseAppZone,
        to targetZone: BrowseAppZone,
        isAlwaysHiddenEnabled: Bool
    ) -> MenuBarZoneMoveRequest? {
        switch (sourceZone, targetZone) {
        case (.visible, .hidden):
            .visibleToHidden
        case (.hidden, .visible):
            .hiddenToVisible
        case (.visible, .alwaysHidden):
            isAlwaysHiddenEnabled ? .visibleToAlwaysHidden : nil
        case (.hidden, .alwaysHidden):
            isAlwaysHiddenEnabled ? .hiddenToAlwaysHidden : nil
        case (.alwaysHidden, .visible):
            .alwaysHiddenToVisible
        case (.alwaysHidden, .hidden):
            .alwaysHiddenToHidden
        case (.visible, .visible), (.hidden, .hidden), (.alwaysHidden, .alwaysHidden):
            nil
        }
    }

    @MainActor
    static func observeMoveResult(
        _ task: Task<Bool, Never>,
        appID: String? = nil,
        setMovingAppID: @escaping (String?) -> Void,
        recordFailedMove: @escaping (String?) -> Void = { _ in }
    ) {
        Task { @MainActor in
            let moved = await task.value
            if !moved {
                setMovingAppID(nil)
                // Retryable miss: surface the app so the
                // UI can offer a retry. Informational only — no synthetic input.
                recordFailedMove(appID)
            }
        }
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
            guard let task = await context.manager.moveQueueWorkflow.queueZoneMoveAfterDrop(
                app: app,
                request: request,
                physicalMoveOrigin: .explicitUserAction
            ) else {
                context.setMovingAppID(nil)
                context.recordFailedMove(app.uniqueId)
                return
            }
            observeMoveResult(
                task,
                appID: app.uniqueId,
                setMovingAppID: context.setMovingAppID,
                recordFailedMove: context.recordFailedMove
            )
        }
        return true
    }

    @MainActor
    private static func queueReorder(
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
            placeAfterTarget: placeAfterTarget,
            physicalMoveOrigin: .explicitUserAction
        ) else {
            return false
        }

        context.setMovingAppID(sourceApp.uniqueId)
        observeMoveResult(
            task,
            appID: sourceApp.uniqueId,
            setMovingAppID: context.setMovingAppID,
            recordFailedMove: context.recordFailedMove
        )
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
