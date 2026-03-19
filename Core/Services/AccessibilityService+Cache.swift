import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Cache")

extension AccessibilityService {
    @MainActor
    func diagnosticsSnapshot() -> String {
        func ageString(since date: Date) -> String {
            guard date != .distantPast else { return "stale" }
            return String(format: "%.1fs", Date().timeIntervalSince(date))
        }

        let noExtrasBundles = bundlesWithoutExtrasMenuBarSnapshot()
        let bundleSummary = noExtrasBundles.prefix(6).joined(separator: ", ")
        let bundleSuffix = noExtrasBundles.count > 6 ? ", …" : ""

        return """
        accessibility:
          granted: \(isGranted)
          ownersCacheCount: \(menuBarOwnersCache.count)
          ownersCacheAge: \(ageString(since: menuBarOwnersCacheTime))
          itemsCacheCount: \(menuBarItemCache.count)
          itemsCacheAge: \(ageString(since: menuBarItemCacheTime))
          ownersRefreshInFlight: \(menuBarOwnersRefreshTask != nil)
          itemsRefreshInFlight: \(menuBarItemsRefreshTask != nil)
          cacheWarmupInFlight: \(menuBarCacheWarmupTask != nil)
          bundlesWithoutExtrasMenuBarCount: \(noExtrasBundles.count)
          bundlesWithoutExtrasMenuBar: \(bundleSummary.isEmpty ? "none" : bundleSummary + bundleSuffix)
        """
    }

    // MARK: - Cached Results (Fast)

    func cachedMenuBarItemOwners() -> [RunningApp] {
        menuBarOwnersCache
    }

    func cachedMenuBarItemsWithPositions() -> [MenuBarItemPosition] {
        menuBarItemCache
    }

    // MARK: - Async Refresh (Non-blocking)

    func refreshMenuBarItemOwners() async -> [RunningApp] {
        guard isTrusted else { return [] }

        let now = Date()
        if now.timeIntervalSince(menuBarOwnersCacheTime) < menuBarOwnersCacheValiditySeconds && !menuBarOwnersCache.isEmpty {
            return menuBarOwnersCache
        }

        if let task = menuBarOwnersRefreshTask {
            return await task.value
        }

        let task = Task<[RunningApp], Never> {
            await self.listMenuBarItemOwners()
        }

        menuBarOwnersRefreshTask = task
        let result = await task.value
        menuBarOwnersRefreshTask = nil
        return result
    }

    func refreshMenuBarItemsWithPositions() async -> [MenuBarItemPosition] {
        guard isTrusted else { return [] }

        let now = Date()
        if now.timeIntervalSince(menuBarItemCacheTime) < menuBarItemCacheValiditySeconds && !menuBarItemCache.isEmpty {
            return menuBarItemCache
        }

        if let task = menuBarItemsRefreshTask {
            return await task.value
        }

        let task = Task<[MenuBarItemPosition], Never> {
            // Use the authoritative scanner (includes width) and benefits from its caching.
            await self.listMenuBarItemsWithPositions()
        }

        menuBarItemsRefreshTask = task
        let result = await task.value
        menuBarItemsRefreshTask = nil
        return result
    }
    
    @MainActor
    private func scheduleMenuBarCacheWarmup(reason: CacheWarmupReason) {
        guard isTrusted else {
            logger.debug("Skipping cache warmup (\(reason.rawValue, privacy: .public)) - accessibility not granted")
            return
        }

        menuBarCacheWarmupTask?.cancel()
        let delaySeconds = Self.cacheWarmupDelay(for: reason)

        menuBarCacheWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if delaySeconds > 0 {
                try? await Task.sleep(for: .milliseconds(Int(delaySeconds * 1000)))
            }
            guard !Task.isCancelled else {
                self.menuBarCacheWarmupTask = nil
                return
            }

            logger.info("Pre-warming menu bar cache (\(reason.rawValue, privacy: .public))...")
            let startTime = Date()

            _ = await self.refreshMenuBarItemOwners()
            _ = await self.refreshMenuBarItemsWithPositions()

            let elapsed = Date().timeIntervalSince(startTime)
            logger.info(
                "Menu bar cache pre-warmed (\(reason.rawValue, privacy: .public)) in \(String(format: "%.2f", elapsed), privacy: .public)s"
            )
            self.menuBarCacheWarmupTask = nil
        }
    }

    /// Invalidates all menu bar caches, forcing a fresh scan on next call.
    /// Optionally schedules a background warmup so the next UI/script interaction
    /// does not pay the full cold-scan penalty.
    func invalidateMenuBarItemCache(scheduleWarmupAfter reason: CacheWarmupReason? = nil) {
        menuBarItemCacheTime = .distantPast
        menuBarOwnersCacheTime = .distantPast
        menuBarOwnersRefreshTask?.cancel()
        menuBarItemsRefreshTask?.cancel()
        menuBarCacheWarmupTask?.cancel()
        menuBarOwnersRefreshTask = nil
        menuBarItemsRefreshTask = nil
        logger.debug("Menu bar item caches invalidated")

        if let reason {
            scheduleMenuBarCacheWarmup(reason: reason)
        } else {
            menuBarCacheWarmupTask = nil
        }
    }

    /// Pre-warms the menu bar caches in the background.
    /// Call this on app launch so Find Icon opens instantly.
    func prewarmCache() {
        scheduleMenuBarCacheWarmup(reason: .launch)
    }
}
