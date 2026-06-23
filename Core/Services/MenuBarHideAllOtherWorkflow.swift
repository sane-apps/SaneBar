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
        SearchMenuBarZoneClassifier.isAlwaysHiddenZone(
            itemX: itemX,
            itemWidth: itemWidth,
            alwaysHiddenSeparatorX: alwaysHiddenBoundaryX
        )
    }

    nonisolated static func hideAllOtherZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        separatorX: CGFloat,
        alwaysHiddenBoundaryX: CGFloat?
    ) -> HideAllOtherZone {
        switch SearchMenuBarZoneClassifier.classifyZone(
            itemX: itemX,
            itemWidth: itemWidth,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenBoundaryX
        ) {
        case .alwaysHidden:
            return .alwaysHidden
        case .hidden:
            return .hidden
        case .visible:
            return .visible
        }
    }

    nonisolated static func hideAllOtherMoveNeeded(
        initialZone: HideAllOtherZone,
        shouldShow: Bool
    ) -> Bool {
        if shouldShow {
            return initialZone != .visible
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

    nonisolated static func hideAllOtherReplayMovePriority(shouldShow: Bool) -> Int {
        // Moving non-allow-listed items can shift the Visible lane. Keep the
        // user's visible allow-list as the final physical repair in each pass.
        shouldShow ? 1 : 0
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

    nonisolated static func visibleAllowListIdsOutsideVisibleZone(
        visibleIds: Set<String>,
        classified: SearchClassifiedApps
    ) -> [String] {
        guard !visibleIds.isEmpty else { return [] }

        let visibleMatches = Set(
            classified.visible.flatMap { app in
                [app.uniqueId, app.bundleId].filter { !$0.isEmpty }
            }
        )

        let nonVisibleAllowedIds = (classified.hidden + classified.alwaysHidden)
            .filter { app in
                shouldShowItem(app: app, visibleIds: visibleIds) &&
                    !visibleMatches.contains(app.uniqueId)
            }
            .map(\.uniqueId)

        return Array(Set(nonVisibleAllowedIds)).sorted()
    }

    func enableFromCurrentLayout(onComplete: ((Bool) -> Void)? = nil) {
        manager.hideAllOtherRuleEnforcementTask?.cancel()

        Task { [weak manager] in
            guard let manager else {
                await MainActor.run { onComplete?(false) }
                return
            }

            if await MainActor.run(body: { manager.hidingService.state == .hidden }) {
                let revealed = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .settingsButton)
                let expanded = await MainActor.run(body: { manager.hidingService.state == .expanded })
                if !revealed, !expanded {
                    logger.warning("Hide-all-other enabled while hidden items could not be revealed; preserving the existing visible allow-list")
                }
            }

            let classified = await SearchService.shared.refreshKnownClassifiedApps()
            await MainActor.run {
                if !manager.shouldRunVisibilityIntentEnforcement(reason: "enableHideAllOther-refresh") {
                    logger.warning("Hide-all-other enabled; live enforcement will wait until menu bar anchors are healthy")
                }
                let refreshedIds = Self.visibleItemIds(from: classified.visible)
                if refreshedIds.isEmpty {
                    if manager.settings.hideAllOtherVisibleItemIds.isEmpty {
                        logger.info("Hide-all-other rule enabled with an empty visible allow-list; all non-exempt new items will be hidden")
                    } else {
                        logger.info("Hide-all-other refresh found no visible items; preserving the existing visible allow-list")
                    }
                } else {
                    manager.settings.hideAllOtherVisibleItemIds = refreshedIds
                }
                manager.settings.hideAllOtherMenuBarItems = true
                manager.saveSettings()
                onComplete?(true)
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
            _ = await manager.hideAllOtherWorkflow.enforce(
                reason: reason,
                filterBundleId: filterBundleId,
                mode: .auditOnly
            )
        }
    }

    @discardableResult
    func enforce(
        reason: String,
        filterBundleId: String? = nil,
        mode: MenuBarVisibilityIntentMode = .auditOnly,
        physicalMoveOrigin: MenuBarPhysicalMoveOrigin? = nil
    ) async -> Bool {
        if mode == .repairWithPhysicalMoves, physicalMoveOrigin == nil {
            logger.error("Physical menu bar moves rejected without an explicit user/automation origin")
            return false
        }
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
        guard let separatorX = manager.geometryResolver.separatorRightEdgeX() ?? manager.geometryResolver.separatorOriginX() else {
            logger.warning("Hide-all-other enforcement (\(reason, privacy: .public)): separator position unavailable")
            return false
        }
        let alwaysHiddenBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()

        if mode == .auditOnly {
            return await auditHideAllOtherWithoutPhysicalMoves(
                visibleIds: visibleIds,
                separatorX: separatorX,
                alwaysHiddenBoundaryX: alwaysHiddenBoundaryX,
                filterBundleId: filterBundleId,
                reason: reason
            )
        }
        guard let repairOrigin = physicalMoveOrigin else { return false }

        let shouldRestoreHiddenState = manager.hidingService.state == .hidden
        let baselineItems = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        if case .systemWakeRecovery = repairOrigin {
            let candidateItemCount = baselineItems.filter { item in
                if let filterBundleId, item.app.bundleId != filterBundleId { return false }
                return !Self.shouldSkipItem(
                    bundleID: item.app.bundleId,
                    menuExtraId: item.app.menuExtraIdentifier,
                    name: item.app.name
                )
            }.count
            AccessibilityService.shared.automaticMoveGate.arm(
                moveBudget: MenuBarAutomaticMoveGate.automaticMoveBudget(forCandidateItemCount: candidateItemCount)
            )
        }
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
                if shouldRestoreHiddenState { await manager.hidingService.hide() }
                return false
            }
            let orderedItems = items.enumerated().sorted { lhs, rhs in
                let lhsShouldShow = Self.shouldShowItem(app: lhs.element.app, visibleIds: visibleIds)
                let rhsShouldShow = Self.shouldShowItem(app: rhs.element.app, visibleIds: visibleIds)
                let lhsPriority = Self.hideAllOtherReplayMovePriority(shouldShow: lhsShouldShow)
                let rhsPriority = Self.hideAllOtherReplayMovePriority(shouldShow: rhsShouldShow)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.offset < rhs.offset
            }.map(\.element)

            var movedAnyItem = false
            var seenUniqueIds = Set<String>()
            for item in orderedItems {
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
                        toAlwaysHidden: false,
                        physicalMoveOrigin: repairOrigin
                    )
                } else {
                    moveSucceeded = await manager.moveQueueWorkflow.moveIconAndWait(
                        bundleID: app.bundleId,
                        menuExtraId: app.menuExtraIdentifier,
                        statusItemIndex: app.statusItemIndex,
                        preferredCenterX: app.preferredCenterX,
                        toHidden: !shouldShow,
                        physicalMoveOrigin: repairOrigin
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
        if shouldRestoreHiddenState {
            await manager.hidingService.hide()
        }

        try? await Task.sleep(for: .milliseconds(250))
        var finalMoveFailedUniqueIds = Set<String>()
        for pass in 1 ... 2 {
            let verificationSeparatorX = manager.geometryResolver.separatorRightEdgeX() ?? manager.geometryResolver.separatorOriginX() ?? separatorX
            let verificationAlwaysHiddenBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()
            let verificationItems = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
            let orderedVerificationItems = verificationItems.enumerated().sorted { lhs, rhs in
                let lhsShouldShow = Self.shouldShowItem(app: lhs.element.app, visibleIds: visibleIds)
                let rhsShouldShow = Self.shouldShowItem(app: rhs.element.app, visibleIds: visibleIds)
                let lhsPriority = Self.hideAllOtherReplayMovePriority(shouldShow: lhsShouldShow)
                let rhsPriority = Self.hideAllOtherReplayMovePriority(shouldShow: rhsShouldShow)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.offset < rhs.offset
            }.map(\.element)
            var movedAnyItem = false

            for item in orderedVerificationItems {
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
                        toAlwaysHidden: false,
                        physicalMoveOrigin: repairOrigin
                    )
                } else {
                    moveSucceeded = await manager.moveQueueWorkflow.moveIconAndWait(
                        bundleID: app.bundleId,
                        menuExtraId: app.menuExtraIdentifier,
                        statusItemIndex: app.statusItemIndex,
                        preferredCenterX: app.preferredCenterX,
                        toHidden: !shouldShow,
                        physicalMoveOrigin: repairOrigin
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

    private func auditHideAllOtherWithoutPhysicalMoves(
        visibleIds: Set<String>,
        separatorX: CGFloat,
        alwaysHiddenBoundaryX: CGFloat?,
        filterBundleId: String?,
        reason: String
    ) async -> Bool {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        let classified = await SearchService.shared.refreshKnownClassifiedApps()
        let hiddenVisibleAllowListIds = Self.visibleAllowListIdsOutsideVisibleZone(
            visibleIds: visibleIds,
            classified: classified
        )
        if !hiddenVisibleAllowListIds.isEmpty {
            logger.warning(
                "Hide-all-other audit found \(hiddenVisibleAllowListIds.count, privacy: .public) allow-listed visible item(s) outside Visible without moving the cursor (\(reason, privacy: .public)): \(hiddenVisibleAllowListIds.joined(separator: ","), privacy: .public)"
            )
            return false
        }

        var driftedItemCount = 0

        for item in items {
            let app = item.app
            if let filterBundleId, app.bundleId != filterBundleId { continue }
            guard !Self.shouldSkipItem(
                bundleID: app.bundleId,
                menuExtraId: app.menuExtraIdentifier,
                name: app.name
            ) else {
                continue
            }

            let currentZone = Self.hideAllOtherZone(
                itemX: item.x,
                itemWidth: app.width,
                separatorX: separatorX,
                alwaysHiddenBoundaryX: alwaysHiddenBoundaryX
            )
            if Self.hideAllOtherFinalMoveNeeded(
                currentZone: currentZone,
                shouldShow: Self.shouldShowItem(app: app, visibleIds: visibleIds)
            ) {
                driftedItemCount += 1
            }
        }

        if driftedItemCount > 0 {
            logger.warning(
                "Hide-all-other audit found \(driftedItemCount, privacy: .public) item(s) outside the allow-list intent without moving the cursor (\(reason, privacy: .public))"
            )
            return false
        }

        logger.info(
            "Hide-all-other enforcement audited without physical moves (\(reason, privacy: .public)); explicit user or automation move required for cursor-moving repair"
        )
        return true
    }
}
