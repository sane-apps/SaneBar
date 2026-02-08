import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.AlwaysHidden")

extension MenuBarManager {
    // MARK: - Always-Hidden Pins (Experimental)

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
    }

    /// Remove a pin so the item no longer gets auto-moved into always-hidden.
    func unpinAlwaysHidden(app: RunningApp) {
        let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let newIds = settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
        guard newIds.count != settings.alwaysHiddenPinnedItemIds.count else { return }
        settings.alwaysHiddenPinnedItemIds = newIds
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
        alwaysHiddenPinEnforcementTask?.cancel()
        alwaysHiddenPinEnforcementTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            await enforceAlwaysHiddenPinnedItems(reason: reason, filterBundleId: filterBundleId)
        }
    }

    func waitForAlwaysHiddenSeparatorX(maxAttempts: Int = 15, delay: Duration = .milliseconds(100)) async -> CGFloat? {
        for _ in 0 ..< maxAttempts {
            if Task.isCancelled { return nil }
            if let x = getAlwaysHiddenSeparatorOriginX() { return x }
            try? await Task.sleep(for: delay)
        }
        return nil
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
        guard settings.alwaysHiddenSectionEnabled, alwaysHiddenSeparatorItem != nil else { return }
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

        let wasHidden = hidingState == .hidden

        // Reveal ALL items using the shield pattern (safe from any state)
        await hidingService.showAll()
        try? await Task.sleep(for: .milliseconds(300))

        guard let alwaysHiddenSeparatorX = getAlwaysHiddenSeparatorOriginX() else {
            logger.warning("Always-hidden pin enforcement (\(reason, privacy: .public)): separator position unavailable")
            await hidingService.restoreFromShowAll()
            if wasHidden { await hidingService.hide() }
            return
        }

        // Validate separator ordering: always-hidden separator must be LEFT of main separator
        if let mainSeparatorX = getSeparatorOriginX(), alwaysHiddenSeparatorX >= mainSeparatorX {
            logger.error("Always-hidden separator (\(alwaysHiddenSeparatorX)) is not left of main separator (\(mainSeparatorX)) — skipping enforcement")
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

            let alreadyAlwaysHidden = isInAlwaysHiddenZone(
                itemX: item.x,
                itemWidth: item.app.width,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
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
                separatorOverrideX: alwaysHiddenSeparatorX
            )
        }

        // Restore: re-block always-hidden items (shield pattern)
        await hidingService.restoreFromShowAll()
        if wasHidden {
            await hidingService.hide()
        }
    }
}
