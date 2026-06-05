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
        alwaysHiddenSeparatorX: CGFloat?
    ) -> Bool {
        guard hasAlwaysHiddenSeparator else { return false }
        guard let separatorX,
              separatorX.isFinite,
              separatorX > 0,
              let alwaysHiddenSeparatorX,
              alwaysHiddenSeparatorX.isFinite,
              alwaysHiddenSeparatorX > 0
        else { return false }
        return alwaysHiddenSeparatorX >= separatorX
    }

    func repairSeparatorPositionIfNeeded(reason: String) {
        guard manager.settings.alwaysHiddenSectionEnabled else { return }
        guard !manager.isRepairingAlwaysHiddenSeparator else { return }
        guard let separatorX = manager.geometryResolver.separatorOriginX(),
              let alwaysHiddenX = manager.geometryResolver.alwaysHiddenSeparatorOriginX(),
              alwaysHiddenX >= separatorX else { return }
        guard separatorX > 1, alwaysHiddenX > 1 else {
            logger.debug(
                "Always-hidden repair skipped due unresolved coordinates (ah=\(alwaysHiddenX, privacy: .public), sep=\(separatorX, privacy: .public))"
            )
            return
        }

        let now = Date()
        if let lastAttempt = manager.lastAlwaysHiddenRepairAt,
           now.timeIntervalSince(lastAttempt) < 5 {
            return
        }
        manager.lastAlwaysHiddenRepairAt = now
        manager.isRepairingAlwaysHiddenSeparator = true
        defer { manager.isRepairingAlwaysHiddenSeparator = false }

        logger.error(
            "Always-hidden separator misordered (ah=\(alwaysHiddenX, privacy: .public), sep=\(separatorX, privacy: .public)) - repairing (\(reason, privacy: .public))"
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
        Task { @MainActor [weak manager] in
            guard let manager else { return }
            try? await Task.sleep(for: .milliseconds(350))
            await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
            await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
            guard let postSepX = manager.geometryResolver.separatorOriginX(),
                  let postAHX = manager.geometryResolver.alwaysHiddenSeparatorOriginX(),
                  postSepX > 1,
                  postAHX > 1
            else {
                manager.alwaysHiddenPinWorkflow.scheduleEnforcement(
                    reason: "post-repair-\(reason)",
                    delay: .milliseconds(500)
                )
                return
            }

            guard postAHX >= postSepX else {
                manager.alwaysHiddenPinWorkflow.scheduleEnforcement(
                    reason: "post-repair-\(reason)",
                    delay: .milliseconds(500)
                )
                return
            }

            logger.error(
                "Always-hidden separator still misordered after repair (ah=\(postAHX, privacy: .public), sep=\(postSepX, privacy: .public)) - applying hard position recovery"
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
            await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
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
        AccessibilityService.shared.invalidateMenuBarItemCache()
        return true
    }

    func unpin(app: RunningApp) {
        let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let newIds = manager.settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
        guard newIds.count != manager.settings.alwaysHiddenPinnedItemIds.count else { return }
        manager.settings.alwaysHiddenPinnedItemIds = newIds
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
            _ = await manager.alwaysHiddenPinWorkflow.enforce(reason: reason, filterBundleId: filterBundleId)
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
    func enforce(reason: String, filterBundleId: String? = nil) async -> Bool {
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
        }

        guard !pins.isEmpty else { return true }

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

        let wasHidden = manager.hidingService.state == .hidden

        await manager.hidingService.showAll()
        try? await Task.sleep(for: .milliseconds(300))

        guard let alwaysHiddenBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX() else {
            logger.warning("Always-hidden pin enforcement (\(reason, privacy: .public)): live separator boundary unavailable")
            await manager.hidingService.restoreFromShowAll()
            if wasHidden { await manager.hidingService.hide() }
            return false
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        if Task.isCancelled {
            await manager.hidingService.restoreFromShowAll()
            if wasHidden { await manager.hidingService.hide() }
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
            if wasHidden { await manager.hidingService.hide() }
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
                clearAlwaysHiddenPinAfterMove: false
            )
            if !moveSucceeded {
                failedMoveUniqueIds.insert(uniqueId)
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        await manager.hidingService.restoreFromShowAll()
        if wasHidden {
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
