import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarHideAllOtherWorkflow")

@MainActor
final class MenuBarHideAllOtherWorkflow {
    enum HideAllOtherZone: Equatable {
        case alwaysHidden
        case hidden
        case visible
    }

    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    nonisolated static func storedItemId(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> String {
        if let menuExtraId {
            if menuExtraId.hasPrefix("com.apple.menuextra.") {
                return menuExtraId
            }
            return "\(bundleID)::axid:\(menuExtraId)"
        }
        if let statusItemIndex {
            return "\(bundleID)::statusItem:\(statusItemIndex)"
        }
        return bundleID
    }

    nonisolated static func shouldSkipItem(
        bundleID: String,
        menuExtraId: String?,
        name: String
    ) -> Bool {
        if bundleID.hasPrefix("com.sanebar.") { return true }
        if bundleID.hasPrefix("com.surteesstudios.Bartender") { return true }
        if menuExtraId == "com.apple.menuextra.clock" { return true }
        if menuExtraId == "com.apple.menuextra.controlcenter" { return true }
        if bundleID == "com.apple.controlcenter", name == "Control Center" { return true }
        return false
    }

    nonisolated static func shouldShowItem(
        app: RunningApp,
        visibleIds: Set<String>
    ) -> Bool {
        visibleIds.contains(app.uniqueId) || visibleIds.contains(app.bundleId)
    }

    nonisolated static func isAlwaysHiddenZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        alwaysHiddenBoundaryX: CGFloat?
    ) -> Bool {
        guard let alwaysHiddenBoundaryX,
              alwaysHiddenBoundaryX.isFinite,
              alwaysHiddenBoundaryX > 0
        else {
            return false
        }
        let width = max(1, itemWidth ?? 22)
        let midX = itemX + (width / 2)
        let margin = max(4, width * 0.3)
        return midX < (alwaysHiddenBoundaryX - margin)
    }

    nonisolated static func hideAllOtherZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        separatorX: CGFloat,
        alwaysHiddenBoundaryX: CGFloat?
    ) -> HideAllOtherZone {
        if isAlwaysHiddenZone(
            itemX: itemX,
            itemWidth: itemWidth,
            alwaysHiddenBoundaryX: alwaysHiddenBoundaryX
        ) {
            return .alwaysHidden
        }

        let width = max(1, itemWidth ?? 22)
        let midX = itemX + (width / 2)
        return midX >= (separatorX - 4) ? .visible : .hidden
    }

    nonisolated static func hideAllOtherMoveNeeded(
        initialZone: HideAllOtherZone,
        shouldShow: Bool
    ) -> Bool {
        if shouldShow {
            return true
        }
        return initialZone == .visible
    }

    nonisolated static func hideAllOtherFinalMoveNeeded(
        currentZone: HideAllOtherZone,
        shouldShow: Bool
    ) -> Bool {
        if shouldShow {
            return currentZone != .visible
        }
        return currentZone == .visible
    }

    nonisolated static func visibleItemIds(from apps: [RunningApp]) -> [String] {
        var ids = Set<String>()
        for app in apps {
            guard !shouldSkipItem(
                bundleID: app.bundleId,
                menuExtraId: app.menuExtraIdentifier,
                name: app.name
            ) else {
                continue
            }
            ids.insert(app.uniqueId)
        }
        return Array(ids).sorted()
    }

    func enableFromCurrentLayout() {
        manager.hideAllOtherRuleEnforcementTask?.cancel()

        guard manager.shouldRunVisibilityIntentEnforcement(reason: "enableHideAllOther") else {
            logger.warning("Hide-all-other rule not enabled because menu bar geometry is not healthy enough to seed a visible allow-list")
            return
        }

        Task { [weak manager] in
            let classified = await SearchService.shared.refreshKnownClassifiedApps()
            await MainActor.run {
                guard let manager else { return }
                guard manager.shouldRunVisibilityIntentEnforcement(reason: "enableHideAllOther-refresh") else {
                    logger.warning("Hide-all-other rule not enabled after refresh because menu bar geometry is not healthy enough to seed a visible allow-list")
                    return
                }
                let refreshedIds = Self.visibleItemIds(from: classified.visible)
                guard !refreshedIds.isEmpty else {
                    logger.warning("Hide-all-other rule not enabled because no current visible item ids could be seeded")
                    return
                }
                manager.settings.hideAllOtherVisibleItemIds = refreshedIds
                manager.settings.hideAllOtherMenuBarItems = true
            }
        }
    }

    func scheduleEnforcement(reason: String, filterBundleId: String? = nil, delay: Duration) {
        guard manager.settings.hideAllOtherMenuBarItems else { return }
        guard !manager.shouldSkipHideForExternalMonitor else {
            logger.info("Hide-all-other enforcement skipped by external monitor policy (\(reason, privacy: .public))")
            return
        }
        manager.hideAllOtherRuleEnforcementTask?.cancel()
        manager.hideAllOtherRuleEnforcementTask = Task { [weak manager] in
            guard let manager else { return }
            try? await Task.sleep(for: delay)
            _ = await manager.hideAllOtherWorkflow.enforce(reason: reason, filterBundleId: filterBundleId)
        }
    }

    @discardableResult
    func enforce(reason: String, filterBundleId: String? = nil) async -> Bool {
        if let activeMoveTask = manager.activeMoveTask, !activeMoveTask.isCancelled {
            logger.debug("Hide-all-other enforcement skipped while icon move is in progress (\(reason, privacy: .public))")
            return false
        }
        guard manager.settings.hideAllOtherMenuBarItems else { return true }
        guard manager.shouldRunVisibilityIntentEnforcement(reason: reason) else { return false }
        guard !manager.shouldSkipHideForExternalMonitor else {
            logger.info("Hide-all-other enforcement skipped by external monitor policy (\(reason, privacy: .public))")
            return true
        }
        guard AccessibilityService.shared.isTrusted else {
            logger.debug("Hide-all-other enforcement skipped (no Accessibility permission)")
            return false
        }

        let visibleIds = Set(manager.settings.hideAllOtherVisibleItemIds)
        let wasHidden = manager.hidingService.state == .hidden

        guard let separatorX = manager.geometryResolver.separatorOriginX() ?? manager.geometryResolver.separatorRightEdgeX() else {
            logger.warning("Hide-all-other enforcement (\(reason, privacy: .public)): separator position unavailable")
            return false
        }
        let alwaysHiddenBoundaryX = manager.geometryResolver.alwaysHiddenSeparatorBoundaryX() ?? manager.geometryResolver.alwaysHiddenSeparatorOriginX()
        let baselineItems = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        var initialZoneByUniqueId: [String: HideAllOtherZone] = [:]
        initialZoneByUniqueId.reserveCapacity(baselineItems.count)
        for item in baselineItems {
            initialZoneByUniqueId[item.app.uniqueId] = Self.hideAllOtherZone(
                itemX: item.x,
                itemWidth: item.app.width,
                separatorX: separatorX,
                alwaysHiddenBoundaryX: alwaysHiddenBoundaryX
            )
        }

        await manager.hidingService.showAll()
        try? await Task.sleep(for: .milliseconds(300))

        var failedMoveUniqueIds = Set<String>()
        for pass in 1 ... 2 {
            let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
            if Task.isCancelled {
                await manager.hidingService.restoreFromShowAll()
                if wasHidden { await manager.hidingService.hide() }
                return false
            }

            var movedAnyItem = false
            var seenUniqueIds = Set<String>()
            for item in items {
                if Task.isCancelled { break }
                let app = item.app
                if let filterBundleId, app.bundleId != filterBundleId { continue }
                guard seenUniqueIds.insert(app.uniqueId).inserted else { continue }
                guard !Self.shouldSkipItem(
                    bundleID: app.bundleId,
                    menuExtraId: app.menuExtraIdentifier,
                    name: app.name
                ) else {
                    continue
                }

                let shouldShow = Self.shouldShowItem(app: app, visibleIds: visibleIds)
                let initialZone = initialZoneByUniqueId[app.uniqueId] ?? Self.hideAllOtherZone(
                    itemX: item.x,
                    itemWidth: app.width,
                    separatorX: separatorX,
                    alwaysHiddenBoundaryX: alwaysHiddenBoundaryX
                )
                guard Self.hideAllOtherMoveNeeded(initialZone: initialZone, shouldShow: shouldShow) else {
                    continue
                }

                movedAnyItem = true
                let isCurrentlyAlwaysHidden = initialZone == .alwaysHidden
                let moveSucceeded: Bool
                if shouldShow, isCurrentlyAlwaysHidden {
                    moveSucceeded = await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                        bundleID: app.bundleId,
                        menuExtraId: app.menuExtraIdentifier,
                        statusItemIndex: app.statusItemIndex,
                        preferredCenterX: app.preferredCenterX,
                        toAlwaysHidden: false
                    )
                } else {
                    moveSucceeded = await manager.moveQueueWorkflow.moveIconAndWait(
                        bundleID: app.bundleId,
                        menuExtraId: app.menuExtraIdentifier,
                        statusItemIndex: app.statusItemIndex,
                        preferredCenterX: app.preferredCenterX,
                        toHidden: !shouldShow
                    )
                }
                if moveSucceeded {
                    failedMoveUniqueIds.remove(app.uniqueId)
                } else {
                    failedMoveUniqueIds.insert(app.uniqueId)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }

            if !movedAnyItem { break }
            if pass == 1 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        await manager.hidingService.restoreFromShowAll()
        if wasHidden {
            await manager.hidingService.hide()
        }

        try? await Task.sleep(for: .milliseconds(250))
        var finalMoveFailedUniqueIds = Set<String>()
        for pass in 1 ... 2 {
            let verificationSeparatorX = manager.geometryResolver.separatorOriginX() ?? manager.geometryResolver.separatorRightEdgeX() ?? separatorX
            let verificationAlwaysHiddenBoundaryX = manager.geometryResolver.alwaysHiddenSeparatorBoundaryX() ?? manager.geometryResolver.alwaysHiddenSeparatorOriginX()
            let verificationItems = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
            var movedAnyItem = false

            for item in verificationItems {
                let app = item.app
                if let filterBundleId, app.bundleId != filterBundleId { continue }
                guard !Self.shouldSkipItem(
                    bundleID: app.bundleId,
                    menuExtraId: app.menuExtraIdentifier,
                    name: app.name
                ) else {
                    continue
                }

                let shouldShow = Self.shouldShowItem(app: app, visibleIds: visibleIds)
                let currentZone = Self.hideAllOtherZone(
                    itemX: item.x,
                    itemWidth: app.width,
                    separatorX: verificationSeparatorX,
                    alwaysHiddenBoundaryX: verificationAlwaysHiddenBoundaryX
                )
                guard Self.hideAllOtherFinalMoveNeeded(currentZone: currentZone, shouldShow: shouldShow) else {
                    finalMoveFailedUniqueIds.remove(app.uniqueId)
                    continue
                }

                movedAnyItem = true
                let moveSucceeded: Bool
                if shouldShow, currentZone == .alwaysHidden {
                    moveSucceeded = await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                        bundleID: app.bundleId,
                        menuExtraId: app.menuExtraIdentifier,
                        statusItemIndex: app.statusItemIndex,
                        preferredCenterX: app.preferredCenterX,
                        toAlwaysHidden: false
                    )
                } else {
                    moveSucceeded = await manager.moveQueueWorkflow.moveIconAndWait(
                        bundleID: app.bundleId,
                        menuExtraId: app.menuExtraIdentifier,
                        statusItemIndex: app.statusItemIndex,
                        preferredCenterX: app.preferredCenterX,
                        toHidden: !shouldShow
                    )
                }
                if moveSucceeded {
                    finalMoveFailedUniqueIds.remove(app.uniqueId)
                } else {
                    finalMoveFailedUniqueIds.insert(app.uniqueId)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }

            if !movedAnyItem { break }
            if pass == 1 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        failedMoveUniqueIds.formUnion(finalMoveFailedUniqueIds)

        if !failedMoveUniqueIds.isEmpty {
            logger.warning(
                "Hide-all-other enforcement incomplete (\(reason, privacy: .public), failedMoves=\(failedMoveUniqueIds.count, privacy: .public))"
            )
            return false
        }
        return !Task.isCancelled
    }
}
