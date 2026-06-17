import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarAlwaysHiddenPinWorkflow")

@MainActor
final class MenuBarAlwaysHiddenPinWorkflow {
    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    nonisolated static func separatorNeedsRepair(
        hasAlwaysHiddenSeparator: Bool,
        separatorX: CGFloat?,
        alwaysHiddenSeparatorRightEdgeX: CGFloat?
    ) -> Bool {
        guard hasAlwaysHiddenSeparator else { return false }
        guard let separatorX,
              separatorX.isFinite,
              let alwaysHiddenSeparatorRightEdgeX,
              alwaysHiddenSeparatorRightEdgeX.isFinite
        else { return false }
        return alwaysHiddenSeparatorRightEdgeX >= separatorX
    }

    func repairSeparatorPositionIfNeeded(reason: String) {
        guard manager.settings.alwaysHiddenSectionEnabled else { return }
        guard !manager.isRepairingAlwaysHiddenSeparator else { return }
        guard let separatorFrame = manager.geometryResolver.currentLiveSeparatorFrame(),
              let alwaysHiddenFrame = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorFrame()
        else {
            logger.debug(
                "Always-hidden repair skipped until live separator geometry is available (\(reason, privacy: .public))"
            )
            return
        }
        let separatorX = separatorFrame.origin.x
        let alwaysHiddenRightEdgeX = alwaysHiddenFrame.origin.x + alwaysHiddenFrame.width
        guard Self.separatorNeedsRepair(
            hasAlwaysHiddenSeparator: manager.alwaysHiddenSeparatorItem != nil,
            separatorX: separatorX,
            alwaysHiddenSeparatorRightEdgeX: alwaysHiddenRightEdgeX
        ) else { return }

        let now = Date()
        if let lastAttempt = manager.lastAlwaysHiddenRepairAt,
           now.timeIntervalSince(lastAttempt) < 5 {
            return
        }
        manager.lastAlwaysHiddenRepairAt = now
        manager.isRepairingAlwaysHiddenSeparator = true
        defer { manager.isRepairingAlwaysHiddenSeparator = false }

        logger.error(
            "Always-hidden separator misordered (ahRight=\(alwaysHiddenRightEdgeX, privacy: .public), sep=\(separatorX, privacy: .public)) - repairing (\(reason, privacy: .public))"
        )

        manager.clearCachedSeparatorGeometry()
        manager.statusBarController.ensureAlwaysHiddenSeparator(enabled: false)
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
        manager.statusBarController.ensureAlwaysHiddenSeparator(enabled: true)
        manager.alwaysHiddenSeparatorItem = manager.statusBarController.alwaysHiddenSeparatorItem
        manager.hidingService.configureAlwaysHiddenDelimiter(manager.alwaysHiddenSeparatorItem)

        manager.clearCachedSeparatorGeometry()
        AccessibilityService.shared.invalidateMenuBarItemCache()

        let manager = self.manager
        manager.alwaysHiddenSeparatorRepairGeneration += 1
        let repairGeneration = manager.alwaysHiddenSeparatorRepairGeneration
        manager.alwaysHiddenSeparatorRepairFollowUpTask?.cancel()
        manager.alwaysHiddenSeparatorRepairFollowUpTask = Task { @MainActor [weak manager] in
            guard let manager else { return }
            defer {
                if manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration {
                    manager.alwaysHiddenSeparatorRepairFollowUpTask = nil
                }
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
            await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
            guard !Task.isCancelled else { return }
            guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
            await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
            guard !Task.isCancelled else { return }
            guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
            guard let postSeparatorFrame = manager.geometryResolver.currentLiveSeparatorFrame(),
                  let postAlwaysHiddenFrame = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorFrame()
            else {
                guard !Task.isCancelled else { return }
                guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
                manager.alwaysHiddenPinWorkflow.scheduleEnforcement(
                    reason: "post-repair-\(reason)",
                    delay: .milliseconds(500)
                )
                return
            }
            let postSepX = postSeparatorFrame.origin.x
            let postAHRightX = postAlwaysHiddenFrame.origin.x + postAlwaysHiddenFrame.width

            guard Self.separatorNeedsRepair(
                hasAlwaysHiddenSeparator: manager.alwaysHiddenSeparatorItem != nil,
                separatorX: postSepX,
                alwaysHiddenSeparatorRightEdgeX: postAHRightX
            ) else {
                guard !Task.isCancelled else { return }
                guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
                manager.alwaysHiddenPinWorkflow.scheduleEnforcement(
                    reason: "post-repair-\(reason)",
                    delay: .milliseconds(500)
                )
                return
            }

            guard !Task.isCancelled else { return }
            guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
            logger.error(
                "Always-hidden separator still misordered after repair (ahRight=\(postAHRightX, privacy: .public), sep=\(postSepX, privacy: .public)) - applying hard position recovery"
            )
            StatusBarController.recoverStartupPositions(
                alwaysHiddenEnabled: true,
                referenceScreen: manager.currentRecoveryReferenceScreen()
            )
            manager.clearCachedSeparatorGeometry()
            manager.statusBarController.ensureAlwaysHiddenSeparator(enabled: false)
            StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
            manager.statusBarController.ensureAlwaysHiddenSeparator(enabled: true)
            manager.alwaysHiddenSeparatorItem = manager.statusBarController.alwaysHiddenSeparatorItem
            manager.hidingService.configureAlwaysHiddenDelimiter(manager.alwaysHiddenSeparatorItem)
            manager.clearCachedSeparatorGeometry()
            await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
            guard !Task.isCancelled else { return }
            guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
            await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
            guard !Task.isCancelled else { return }
            guard manager.alwaysHiddenSeparatorRepairGeneration == repairGeneration else { return }
            AccessibilityService.shared.invalidateMenuBarItemCache()
            manager.alwaysHiddenPinWorkflow.scheduleEnforcement(
                reason: "post-hard-recovery-\(reason)",
                delay: .milliseconds(500)
            )
        }
    }

    func pin(app: RunningApp) {
        let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPinId(id) else {
            logger.warning("Rejecting invalid pin ID: \(id, privacy: .private)")
            return
        }

        var newIds = Set(manager.settings.alwaysHiddenPinnedItemIds)
        let inserted = newIds.insert(id).inserted
        guard inserted else { return }

        manager.settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()
        manager.saveSettings()
        AccessibilityService.shared.invalidateMenuBarItemCache()
    }

    @discardableResult
    func pin(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil) -> Bool {
        let rawId: String
        if let menuExtraId {
            if menuExtraId.hasPrefix("com.apple.menuextra.") {
                rawId = menuExtraId
            } else {
                rawId = "\(bundleID)::axid:\(menuExtraId)"
            }
        } else if let statusItemIndex {
            rawId = "\(bundleID)::statusItem:\(statusItemIndex)"
        } else {
            rawId = bundleID
        }

        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPinId(id) else {
            logger.warning("Rejecting invalid pin ID: \(id, privacy: .private)")
            return false
        }

        var newIds = Set(manager.settings.alwaysHiddenPinnedItemIds)
        let inserted = newIds.insert(id).inserted
        guard inserted else { return false }

        manager.settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()
        manager.saveSettings()
        AccessibilityService.shared.invalidateMenuBarItemCache()
        return true
    }

    func unpin(app: RunningApp) {
        let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let newIds = manager.settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
        guard newIds.count != manager.settings.alwaysHiddenPinnedItemIds.count else { return }
        manager.settings.alwaysHiddenPinnedItemIds = newIds
        manager.saveSettings()
        AccessibilityService.shared.invalidateMenuBarItemCache()
    }

    @discardableResult
    func unpin(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil) -> Bool {
        let cleanBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBundleID.isEmpty else { return false }

        let cleanMenuExtraId = menuExtraId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinCountBefore = manager.settings.alwaysHiddenPinnedItemIds.count

        let filtered = manager.settings.alwaysHiddenPinnedItemIds.filter { raw in
            guard let pin = parse(raw) else {
                return true
            }
            switch pin {
            case let .bundleId(bundle):
                return bundle != cleanBundleID

            case let .axId(bundle, axId):
                guard bundle == cleanBundleID else { return true }
                if let cleanMenuExtraId, !cleanMenuExtraId.isEmpty {
                    return axId != cleanMenuExtraId
                }
                return false

            case let .statusItem(bundle, index):
                guard bundle == cleanBundleID else { return true }
                if let statusItemIndex {
                    return index != statusItemIndex
                }
                return false

            case let .menuExtra(identifier):
                guard let cleanMenuExtraId, !cleanMenuExtraId.isEmpty else { return true }
                return identifier != cleanMenuExtraId
            }
        }

        guard filtered.count != pinCountBefore else { return false }
        manager.settings.alwaysHiddenPinnedItemIds = filtered
        manager.saveSettings()
        AccessibilityService.shared.invalidateMenuBarItemCache()
        return true
    }

    func parse(_ raw: String) -> SaneBarAlwaysHiddenPin? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("com.apple.menuextra.") {
            return .menuExtra(value)
        }

        if let range = value.range(of: "::axid:") {
            let bundleId = String(value[..<range.lowerBound])
            let axId = String(value[range.upperBound...])
            guard !bundleId.isEmpty, !axId.isEmpty else { return nil }
            return .axId(bundleId: bundleId, axId: axId)
        }

        if let range = value.range(of: "::statusItem:") {
            let bundleId = String(value[..<range.lowerBound])
            let indexString = String(value[range.upperBound...])
            guard !bundleId.isEmpty, let index = Int(indexString) else { return nil }
            return .statusItem(bundleId: bundleId, index: index)
        }

        return .bundleId(value)
    }

    func pinnedBundleIds() -> Set<String> {
        var bundleIds = Set<String>()
        for raw in manager.settings.alwaysHiddenPinnedItemIds {
            guard let pin = parse(raw), let bundleId = pin.bundleId else { continue }
            bundleIds.insert(bundleId)
        }
        return bundleIds
    }

    nonisolated static func pinConflictsWithHideAllOtherVisibleAllowList(
        _ pin: SaneBarAlwaysHiddenPin,
        visibleIds: Set<String>
    ) -> Bool {
        guard !visibleIds.isEmpty else { return false }

        switch pin {
        case let .menuExtra(identifier):
            return visibleIds.contains(identifier)

        case let .axId(bundleId, axId):
            return visibleIds.contains(bundleId) || visibleIds.contains("\(bundleId)::axid:\(axId)")

        case let .statusItem(bundleId, index):
            return visibleIds.contains(bundleId) || visibleIds.contains("\(bundleId)::statusItem:\(index)")

        case let .bundleId(bundleId):
            return visibleIds.contains(bundleId)
        }
    }

    func scheduleEnforcement(reason: String, filterBundleId: String? = nil, delay: Duration) {
        guard !manager.shouldSkipHideForExternalMonitor else {
            logger.info(
                "Always-hidden pin enforcement skipped by external monitor policy (\(reason, privacy: .public))"
            )
            return
        }
        if let lastManualZoneMoveSettledAt = manager.lastManualZoneMoveSettledAt,
           Date().timeIntervalSince(lastManualZoneMoveSettledAt) < 1.5 {
            logger.debug("Always-hidden pin enforcement skipped during post-move settle window (\(reason, privacy: .public))")
            return
        }
        manager.alwaysHiddenPinEnforcementTask?.cancel()
        let manager = self.manager
        manager.alwaysHiddenPinEnforcementTask = Task { @MainActor [weak manager] in
            guard let manager else { return }
            try? await Task.sleep(for: delay)
            _ = await manager.alwaysHiddenPinWorkflow.enforce(
                reason: reason,
                filterBundleId: filterBundleId,
                mode: .auditOnly
            )
        }
    }

    func isInZone(itemX: CGFloat, itemWidth: CGFloat?, alwaysHiddenSeparatorX: CGFloat) -> Bool {
        let width = max(1, itemWidth ?? 22)
        let midX = itemX + (width / 2)
        let margin = max(4, width * 0.3)
        return midX < (alwaysHiddenSeparatorX - margin)
    }

    func findPinnedItem(
        pin: SaneBarAlwaysHiddenPin,
        itemsByUniqueId: [String: AccessibilityService.MenuBarItemPosition],
        itemsByBundleId: [String: [AccessibilityService.MenuBarItemPosition]]
    ) -> AccessibilityService.MenuBarItemPosition? {
        switch pin {
        case let .menuExtra(identifier):
            return itemsByUniqueId[identifier]

        case let .axId(bundleId, axId):
            if let exact = itemsByUniqueId["\(bundleId)::axid:\(axId)"] { return exact }
            if let items = itemsByBundleId[bundleId], items.count == 1 { return items[0] }
            return nil

        case let .statusItem(bundleId, index):
            if let exact = itemsByUniqueId["\(bundleId)::statusItem:\(index)"] { return exact }
            if let items = itemsByBundleId[bundleId], items.count == 1 { return items[0] }
            return nil

        case let .bundleId(bundleId):
            if let items = itemsByBundleId[bundleId], items.count == 1 { return items[0] }
            return nil
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
            logger.debug("Always-hidden pin enforcement skipped while icon move is in progress (\(reason, privacy: .public))")
            return false
        }
        if let lastManualZoneMoveSettledAt = manager.lastManualZoneMoveSettledAt,
           Date().timeIntervalSince(lastManualZoneMoveSettledAt) < 1.5 {
            logger.debug("Always-hidden pin enforcement skipped during post-move settle window (\(reason, privacy: .public))")
            return false
        }
        guard !manager.shouldSkipHideForExternalMonitor else {
            logger.info(
                "Always-hidden pin enforcement skipped by external monitor policy (\(reason, privacy: .public))"
            )
            return true
        }
        guard manager.shouldRunVisibilityIntentEnforcement(reason: reason) else { return false }
        guard manager.alwaysHiddenSeparatorItem != nil else { return false }
        guard !manager.settings.alwaysHiddenPinnedItemIds.isEmpty else { return true }

        guard AccessibilityService.shared.isTrusted else {
            logger.debug("Always-hidden pin enforcement skipped (no Accessibility permission)")
            return false
        }

        let rawPins = manager.settings.alwaysHiddenPinnedItemIds
        let pins = rawPins.compactMap(parse)

        if pins.count < rawPins.count {
            let validRaws = rawPins.filter { parse($0) != nil }
            logger.info("Removing \(rawPins.count - validRaws.count) unparseable pin IDs")
            manager.settings.alwaysHiddenPinnedItemIds = validRaws
            manager.saveSettings()
        }

        let hideAllOtherVisibleIds = manager.settings.hideAllOtherMenuBarItems
            ? Set(manager.settings.hideAllOtherVisibleItemIds)
            : Set<String>()
        let filteredPins = pins
            .filter { pin in
                guard let filterBundleId else { return true }
                return pin.bundleId == filterBundleId
            }
            .filter { pin in
                !Self.pinConflictsWithHideAllOtherVisibleAllowList(
                    pin,
                    visibleIds: hideAllOtherVisibleIds
                )
            }

        guard !filteredPins.isEmpty else { return true }

        if mode == .auditOnly {
            return await auditPinnedItemsWithoutPhysicalMoves(
                filteredPins,
                reason: reason
            )
        }
        guard let repairOrigin = physicalMoveOrigin else { return false }

        let wasHidden = manager.hidingService.state == .hidden
        let isWakeReplay = reason.contains("wake-resume") || reason.contains("wakeResume")
        let shouldRestoreHiddenState = wasHidden || isWakeReplay

        await manager.hidingService.showAll()
        try? await Task.sleep(for: .milliseconds(300))

        guard let alwaysHiddenBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX() else {
            logger.warning("Always-hidden pin enforcement (\(reason, privacy: .public)): live separator boundary unavailable")
            await manager.hidingService.restoreFromShowAll()
            if shouldRestoreHiddenState { await manager.hidingService.hide() }
            return false
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        if Task.isCancelled {
            await manager.hidingService.restoreFromShowAll()
            if shouldRestoreHiddenState { await manager.hidingService.hide() }
            return false
        }

        var itemsByUniqueId: [String: AccessibilityService.MenuBarItemPosition] = [:]
        itemsByUniqueId.reserveCapacity(items.count)
        for item in items {
            itemsByUniqueId[item.app.uniqueId] = item
        }
        let itemsByBundleId = Dictionary(grouping: items, by: { $0.app.bundleId })

        var pinnedItems: [AccessibilityService.MenuBarItemPosition] = []
        pinnedItems.reserveCapacity(filteredPins.count)
        for pin in filteredPins {
            if let item = findPinnedItem(pin: pin, itemsByUniqueId: itemsByUniqueId, itemsByBundleId: itemsByBundleId) {
                pinnedItems.append(item)
            }
        }

        let unresolvedPinnedItemCount = filteredPins.count - pinnedItems.count

        guard !pinnedItems.isEmpty else {
            await manager.hidingService.restoreFromShowAll()
            if shouldRestoreHiddenState { await manager.hidingService.hide() }
            return false
        }

        var seenUniqueIds = Set<String>()
        var failedMoveUniqueIds = Set<String>()
        for item in pinnedItems {
            if Task.isCancelled { break }
            let uniqueId = item.app.uniqueId
            guard seenUniqueIds.insert(uniqueId).inserted else { continue }

            let currentAHBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX() ?? alwaysHiddenBoundaryX
            let alreadyAlwaysHidden = isInZone(
                itemX: item.x,
                itemWidth: item.app.width,
                alwaysHiddenSeparatorX: currentAHBoundaryX
            )
            guard !alreadyAlwaysHidden else { continue }

            logger.info("Enforcing always-hidden pin (\(reason, privacy: .public)): moving \(uniqueId, privacy: .private)")

            let moveSucceeded = await manager.moveQueueWorkflow.moveIconAndWait(
                bundleID: item.app.bundleId,
                menuExtraId: item.app.menuExtraIdentifier,
                statusItemIndex: item.app.statusItemIndex,
                toHidden: true,
                separatorOverrideX: currentAHBoundaryX,
                clearAlwaysHiddenPinAfterMove: false,
                physicalMoveOrigin: repairOrigin
            )
            if !moveSucceeded {
                failedMoveUniqueIds.insert(uniqueId)
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        await manager.hidingService.restoreFromShowAll()
        if shouldRestoreHiddenState {
            await manager.hidingService.hide()
        }

        if unresolvedPinnedItemCount > 0 || !failedMoveUniqueIds.isEmpty {
            logger.warning(
                "Always-hidden pin enforcement incomplete (\(reason, privacy: .public), unresolved=\(unresolvedPinnedItemCount, privacy: .public), failedMoves=\(failedMoveUniqueIds.count, privacy: .public))"
            )
            return false
        }
        return !Task.isCancelled
    }

    private func auditPinnedItemsWithoutPhysicalMoves(
        _ filteredPins: [SaneBarAlwaysHiddenPin],
        reason: String
    ) async -> Bool {
        guard let alwaysHiddenBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX() else {
            logger.warning("Always-hidden pin audit (\(reason, privacy: .public)): live separator boundary unavailable")
            return false
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        var itemsByUniqueId: [String: AccessibilityService.MenuBarItemPosition] = [:]
        itemsByUniqueId.reserveCapacity(items.count)
        for item in items {
            itemsByUniqueId[item.app.uniqueId] = item
        }
        let itemsByBundleId = Dictionary(grouping: items, by: { $0.app.bundleId })
        var driftedPinnedItemCount = 0

        for pin in filteredPins {
            guard let item = findPinnedItem(pin: pin, itemsByUniqueId: itemsByUniqueId, itemsByBundleId: itemsByBundleId) else {
                continue
            }
            if !isInZone(
                itemX: item.x,
                itemWidth: item.app.width,
                alwaysHiddenSeparatorX: alwaysHiddenBoundaryX
            ) {
                driftedPinnedItemCount += 1
            }
        }

        if driftedPinnedItemCount > 0 {
            logger.warning(
                "Always-hidden pin audit found \(driftedPinnedItemCount, privacy: .public) pinned item(s) outside Always Hidden without moving the cursor (\(reason, privacy: .public))"
            )
            return false
        }

        logger.info(
            "Always-hidden pin enforcement audited without physical moves (\(reason, privacy: .public)); explicit user or automation move required for cursor-moving repair"
        )
        return true
    }

    func reconcileAfterUserDrag() async {
        guard manager.settings.alwaysHiddenSectionEnabled else { return }
        guard manager.alwaysHiddenSeparatorItem != nil else { return }
        guard AccessibilityService.shared.isTrusted else { return }
        if let activeMoveTask = manager.activeMoveTask, !activeMoveTask.isCancelled {
            logger.debug("reconcilePins: skipped while icon move is in progress")
            return
        }
        if let lastManualZoneMoveSettledAt = manager.lastManualZoneMoveSettledAt,
           Date().timeIntervalSince(lastManualZoneMoveSettledAt) < 1.5 {
            logger.debug("reconcilePins: skipped during post-move settle window")
            return
        }

        try? await Task.sleep(for: .milliseconds(400))

        guard manager.shouldRunVisibilityIntentEnforcement(reason: "reconcilePins") else {
            logger.debug("reconcilePins: skipped until status-item anchors are healthy")
            return
        }

        guard let ahSeparatorX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX() else {
            logger.debug("reconcilePins: live AH separator boundary not found - skipping")
            return
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        guard !items.isEmpty else { return }

        var currentPins = Set(manager.settings.alwaysHiddenPinnedItemIds)
        let originalPins = currentPins
        var changed = false

        for item in items {
            guard !item.app.isUnmovableSystemItem else { continue }
            let pinId = item.app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidPinId(pinId) else { continue }

            let inAH = isInZone(
                itemX: item.x,
                itemWidth: item.app.width,
                alwaysHiddenSeparatorX: ahSeparatorX
            )

            if inAH, !currentPins.contains(pinId) {
                currentPins.insert(pinId)
                logger.info("reconcilePins: auto-pinned \(pinId, privacy: .private)")
                changed = true
            } else if !inAH, currentPins.contains(pinId) {
                let width = max(1, item.app.width ?? 22)
                let midX = item.x + (width / 2)
                if midX > ahSeparatorX + 20 {
                    currentPins.remove(pinId)
                    logger.info("reconcilePins: auto-unpinned \(pinId, privacy: .private)")
                    changed = true
                }
            }
        }

        if changed {
            manager.settings.alwaysHiddenPinnedItemIds = Array(currentPins).sorted()
            manager.saveSettings()
            let added = currentPins.subtracting(originalPins).count
            let removed = originalPins.subtracting(currentPins).count
            logger.info("reconcilePins: \(added) pinned, \(removed) unpinned")
            AccessibilityService.shared.invalidateMenuBarItemCache()
        }
    }

    private func isValidPinId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 500 else { return false }
        return id.unicodeScalars.allSatisfy { $0.value > 0x1F && $0.value != 0x7F }
    }
}
