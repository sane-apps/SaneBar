import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.AlwaysHidden")

extension MenuBarManager {
    // MARK: - Always-Hidden Pins (Experimental)

    nonisolated static func alwaysHiddenSeparatorNeedsRepair(
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

    func repairAlwaysHiddenSeparatorPositionIfNeeded(reason: String) {
        guard settings.alwaysHiddenSectionEnabled else { return }
        guard !isRepairingAlwaysHiddenSeparator else { return }
        guard let separatorX = getSeparatorOriginX(),
              let alwaysHiddenX = getAlwaysHiddenSeparatorOriginX(),
              alwaysHiddenX >= separatorX else { return }
        guard separatorX > 1, alwaysHiddenX > 1 else {
            logger.debug(
                "Always-hidden repair skipped due unresolved coordinates (ah=\(alwaysHiddenX, privacy: .public), sep=\(separatorX, privacy: .public))"
            )
            return
        }

        let now = Date()
        if let lastAttempt = lastAlwaysHiddenRepairAt,
           now.timeIntervalSince(lastAttempt) < 5 {
            return
        }
        lastAlwaysHiddenRepairAt = now
        isRepairingAlwaysHiddenSeparator = true
        defer { isRepairingAlwaysHiddenSeparator = false }

        logger.error(
            "Always-hidden separator misordered (ah=\(alwaysHiddenX, privacy: .public), sep=\(separatorX, privacy: .public)) — repairing (\(reason, privacy: .public))"
        )

        statusBarController.ensureAlwaysHiddenSeparator(enabled: false)
        StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
        statusBarController.ensureAlwaysHiddenSeparator(enabled: true)
        alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem
        hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)

        lastKnownAlwaysHiddenSeparatorX = nil
        lastKnownAlwaysHiddenSeparatorRightEdgeX = nil
        AccessibilityService.shared.invalidateMenuBarItemCache()

        // Validate after macOS settles the relayout. If still misordered, apply
        // a stronger seed reset so the next scene pass cannot reuse stale state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            guard let postSepX = self.getSeparatorOriginX(),
                  let postAHX = self.getAlwaysHiddenSeparatorOriginX(),
                  postSepX > 1,
                  postAHX > 1,
                  postAHX >= postSepX else { return }

            logger.error(
                "Always-hidden separator still misordered after repair (ah=\(postAHX, privacy: .public), sep=\(postSepX, privacy: .public)) — applying hard position recovery"
            )
            StatusBarController.recoverStartupPositions(alwaysHiddenEnabled: true)
            self.statusBarController.ensureAlwaysHiddenSeparator(enabled: false)
            StatusBarController.seedAlwaysHiddenSeparatorPositionIfNeeded()
            self.statusBarController.ensureAlwaysHiddenSeparator(enabled: true)
            self.alwaysHiddenSeparatorItem = self.statusBarController.alwaysHiddenSeparatorItem
            self.hidingService.configureAlwaysHiddenDelimiter(self.alwaysHiddenSeparatorItem)
            self.lastKnownAlwaysHiddenSeparatorX = nil
            self.lastKnownAlwaysHiddenSeparatorRightEdgeX = nil
            AccessibilityService.shared.invalidateMenuBarItemCache()
        }
    }

    /// Pin a menu bar item so it stays in the always-hidden section across launches.
    /// Uses best-effort identity (`RunningApp.uniqueId`).
    /// Validate that a pin identifier contains no control characters and is reasonably formed.
    private func isValidPinId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 500 else { return false }
        // Reject control characters (U+0000–U+001F, U+007F)
        return id.unicodeScalars.allSatisfy { $0.value > 0x1F && $0.value != 0x7F }
    }

    func pinAlwaysHidden(app: RunningApp) {
        let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPinId(id) else {
            logger.warning("Rejecting invalid pin ID: \(id, privacy: .private)")
            return
        }

        var newIds = Set(settings.alwaysHiddenPinnedItemIds)
        let inserted = newIds.insert(id).inserted
        guard inserted else { return }

        settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()
        AccessibilityService.shared.invalidateMenuBarItemCache()
    }

    @discardableResult
    func pinAlwaysHidden(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil
    ) -> Bool {
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

        var newIds = Set(settings.alwaysHiddenPinnedItemIds)
        let inserted = newIds.insert(id).inserted
        guard inserted else { return false }

        settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()
        AccessibilityService.shared.invalidateMenuBarItemCache()
        return true
    }

    /// Remove a pin so the item no longer gets auto-moved into always-hidden.
    func unpinAlwaysHidden(app: RunningApp) {
        let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let newIds = settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
        guard newIds.count != settings.alwaysHiddenPinnedItemIds.count else { return }
        settings.alwaysHiddenPinnedItemIds = newIds
        AccessibilityService.shared.invalidateMenuBarItemCache()
    }

    /// Defensive unpin used before move-to-visible paths.
    /// Removes any pin identity that could map to this app instance.
    /// Returns true when at least one pin entry was removed.
    @discardableResult
    func unpinAlwaysHidden(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil) -> Bool {
        let cleanBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBundleID.isEmpty else { return false }

        let cleanMenuExtraId = menuExtraId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinCountBefore = settings.alwaysHiddenPinnedItemIds.count

        let filtered = settings.alwaysHiddenPinnedItemIds.filter { raw in
            guard let pin = parseAlwaysHiddenPin(raw) else {
                // Keep unknown pins untouched; parse cleanup happens in enforcement path.
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
        settings.alwaysHiddenPinnedItemIds = filtered
        AccessibilityService.shared.invalidateMenuBarItemCache()
        return true
    }

    // MARK: - Pin Parsing

    enum AlwaysHiddenPin: Hashable, Sendable {
        case menuExtra(String)
        case axId(bundleId: String, axId: String)
        case statusItem(bundleId: String, index: Int)
        case bundleId(String)

        var bundleId: String? {
            switch self {
            case .menuExtra:
                nil
            case let .axId(bundleId, _):
                bundleId
            case let .statusItem(bundleId, _):
                bundleId
            case let .bundleId(bundleId):
                bundleId
            }
        }
    }

    func parseAlwaysHiddenPin(_ raw: String) -> AlwaysHiddenPin? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        // Apple menu extras use the identifier alone as a stable unique key.
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

    func alwaysHiddenPinnedBundleIds() -> Set<String> {
        var bundleIds = Set<String>()
        for raw in settings.alwaysHiddenPinnedItemIds {
            guard let pin = parseAlwaysHiddenPin(raw), let bundleId = pin.bundleId else { continue }
            bundleIds.insert(bundleId)
        }
        return bundleIds
    }

    // MARK: - Pin Enforcement

    func scheduleAlwaysHiddenPinEnforcement(reason: String, filterBundleId: String? = nil, delay: Duration) {
        guard !shouldSkipHideForExternalMonitor else {
            logger.info(
                "Always-hidden pin enforcement skipped by external monitor policy (\(reason, privacy: .public))"
            )
            return
        }
        alwaysHiddenPinEnforcementTask?.cancel()
        alwaysHiddenPinEnforcementTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            await enforceAlwaysHiddenPinnedItems(reason: reason, filterBundleId: filterBundleId)
        }
    }

    func isInAlwaysHiddenZone(itemX: CGFloat, itemWidth: CGFloat?, alwaysHiddenSeparatorX: CGFloat) -> Bool {
        let width = max(1, itemWidth ?? 22)
        let midX = itemX + (width / 2)
        // Scale margin with icon width — small icons get tighter detection
        let margin = max(4, width * 0.3)
        return midX < (alwaysHiddenSeparatorX - margin)
    }

    func findPinnedItem(
        pin: AlwaysHiddenPin,
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

    func enforceAlwaysHiddenPinnedItems(reason: String, filterBundleId: String? = nil) async {
        if let activeMoveTask, !activeMoveTask.isCancelled {
            logger.debug("Always-hidden pin enforcement skipped while icon move is in progress (\(reason, privacy: .public))")
            return
        }
        guard !shouldSkipHideForExternalMonitor else {
            logger.info(
                "Always-hidden pin enforcement skipped by external monitor policy (\(reason, privacy: .public))"
            )
            return
        }
        guard alwaysHiddenSeparatorItem != nil else { return }
        guard !settings.alwaysHiddenPinnedItemIds.isEmpty else { return }

        guard AccessibilityService.shared.isTrusted else {
            logger.debug("Always-hidden pin enforcement skipped (no Accessibility permission)")
            return
        }

        let rawPins = settings.alwaysHiddenPinnedItemIds
        let pins = rawPins.compactMap(parseAlwaysHiddenPin)

        // Clean up stale/unparseable pin IDs
        if pins.count < rawPins.count {
            let validRaws = rawPins.filter { parseAlwaysHiddenPin($0) != nil }
            logger.info("Removing \(rawPins.count - validRaws.count) unparseable pin IDs")
            settings.alwaysHiddenPinnedItemIds = validRaws
        }

        guard !pins.isEmpty else { return }

        let filteredPins: [AlwaysHiddenPin] = if let filterBundleId {
            pins.filter { $0.bundleId == filterBundleId }
        } else {
            pins
        }

        guard !filteredPins.isEmpty else { return }

        let wasHidden = hidingService.state == .hidden

        // Reveal ALL items using the shield pattern (safe from any state)
        await hidingService.showAll()
        try? await Task.sleep(for: .milliseconds(300))

        guard let alwaysHiddenSeparatorOriginX = getAlwaysHiddenSeparatorOriginX() else {
            logger.warning("Always-hidden pin enforcement (\(reason, privacy: .public)): separator position unavailable")
            await hidingService.restoreFromShowAll()
            if wasHidden { await hidingService.hide() }
            return
        }
        let alwaysHiddenBoundaryX = getAlwaysHiddenSeparatorBoundaryX() ?? alwaysHiddenSeparatorOriginX

        // Validate separator ordering: always-hidden separator must be LEFT of main separator
        if let mainSeparatorX = getSeparatorOriginX(), alwaysHiddenSeparatorOriginX >= mainSeparatorX {
            logger.error("Always-hidden separator (\(alwaysHiddenSeparatorOriginX)) is not left of main separator (\(mainSeparatorX)) — skipping enforcement")
            repairAlwaysHiddenSeparatorPositionIfNeeded(reason: "pinEnforcement")
            await hidingService.restoreFromShowAll()
            if wasHidden { await hidingService.hide() }
            return
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        if Task.isCancelled {
            await hidingService.restoreFromShowAll()
            if wasHidden { await hidingService.hide() }
            return
        }

        var itemsByUniqueId: [String: AccessibilityService.MenuBarItemPosition] = [:]
        itemsByUniqueId.reserveCapacity(items.count)
        for item in items {
            itemsByUniqueId[item.app.uniqueId] = item
        }
        let itemsByBundleId = Dictionary(grouping: items, by: { $0.app.bundleId })

        // Resolve pins to concrete current items.
        var pinnedItems: [AccessibilityService.MenuBarItemPosition] = []
        pinnedItems.reserveCapacity(filteredPins.count)
        for pin in filteredPins {
            if let item = findPinnedItem(pin: pin, itemsByUniqueId: itemsByUniqueId, itemsByBundleId: itemsByBundleId) {
                pinnedItems.append(item)
            }
        }

        guard !pinnedItems.isEmpty else {
            await hidingService.restoreFromShowAll()
            if wasHidden { await hidingService.hide() }
            return
        }

        var seenUniqueIds = Set<String>()
        for item in pinnedItems {
            if Task.isCancelled { break }
            let uniqueId = item.app.uniqueId
            guard seenUniqueIds.insert(uniqueId).inserted else { continue }

            // Re-read separator position before each move — moving the previous
            // icon causes macOS to relayout the menu bar and shift positions.
            let currentAHBoundaryX = getAlwaysHiddenSeparatorBoundaryX() ?? alwaysHiddenBoundaryX

            let alreadyAlwaysHidden = isInAlwaysHiddenZone(
                itemX: item.x,
                itemWidth: item.app.width,
                alwaysHiddenSeparatorX: currentAHBoundaryX
            )
            guard !alreadyAlwaysHidden else { continue }

            logger.info("Enforcing always-hidden pin (\(reason, privacy: .public)): moving \(uniqueId, privacy: .private)")

            // All items are on-screen (via showAll), so moveIconAndWait can
            // find the icon and the target position is accurate.
            _ = await moveIconAndWait(
                bundleID: item.app.bundleId,
                menuExtraId: item.app.menuExtraIdentifier,
                statusItemIndex: item.app.statusItemIndex,
                toHidden: true,
                separatorOverrideX: currentAHBoundaryX
            )

            // Brief settle after each move to let macOS finish relayout
            try? await Task.sleep(for: .milliseconds(200))
        }

        // Restore: re-block always-hidden items (shield pattern)
        await hidingService.restoreFromShowAll()
        if wasHidden {
            await hidingService.hide()
        }
    }

    // MARK: - Pin Reconciliation After Cmd+Drag

    /// Reconcile pin list with physical icon positions after a user Cmd+drag.
    /// Auto-pins items found in the AH zone that aren't pinned yet.
    /// Auto-unpins items found outside the AH zone (with safety margin).
    func reconcilePinsAfterUserDrag() async {
        guard settings.alwaysHiddenSectionEnabled else { return }
        guard alwaysHiddenSeparatorItem != nil else { return }
        guard AccessibilityService.shared.isTrusted else { return }

        // Wait for macOS to finish relayout after drag
        try? await Task.sleep(for: .milliseconds(400))

        guard let ahSeparatorX = (getAlwaysHiddenSeparatorBoundaryX() ?? getAlwaysHiddenSeparatorOriginX()) else {
            logger.debug("reconcilePins: AH separator not found — skipping")
            return
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        guard !items.isEmpty else { return }

        var currentPins = Set(settings.alwaysHiddenPinnedItemIds)
        let originalPins = currentPins
        var changed = false

        for item in items {
            guard !item.app.isUnmovableSystemItem else { continue }
            let pinId = item.app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidPinId(pinId) else { continue }

            let inAH = isInAlwaysHiddenZone(
                itemX: item.x,
                itemWidth: item.app.width,
                alwaysHiddenSeparatorX: ahSeparatorX
            )

            if inAH, !currentPins.contains(pinId) {
                // Auto-pin: item is in AH zone but not pinned
                currentPins.insert(pinId)
                logger.info("reconcilePins: auto-pinned \(pinId, privacy: .private)")
                changed = true
            } else if !inAH, currentPins.contains(pinId) {
                // Auto-unpin: item was dragged out of AH zone
                // Safety: only unpin if clearly outside (midX > ahSeparatorX + 20)
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
            settings.alwaysHiddenPinnedItemIds = Array(currentPins).sorted()
            let added = currentPins.subtracting(originalPins).count
            let removed = originalPins.subtracting(currentPins).count
            logger.info("reconcilePins: \(added) pinned, \(removed) unpinned")
            AccessibilityService.shared.invalidateMenuBarItemCache()
        }
    }
}
