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
          cacheWarmupSuppressionDepth: \(menuBarCacheWarmupSuppressionDepth)
          deferredCacheWarmupReason: \(deferredMenuBarCacheWarmupReason?.rawValue ?? "none")
          knownOwnerRefreshAttempts: \(knownOwnerRefreshDiagnostics.attemptCount)
          knownOwnerRefreshAccepted: \(knownOwnerRefreshDiagnostics.acceptedCount)
          knownOwnerRefreshFullFallbacks: \(knownOwnerRefreshDiagnostics.fullFallbackCount)
          knownOwnerRefreshLastOutcome: \(knownOwnerRefreshDiagnostics.lastOutcome)
          knownOwnerRefreshLastSeededItems: \(knownOwnerRefreshDiagnostics.lastSeededItemCount)
          knownOwnerRefreshLastSeededOwners: \(knownOwnerRefreshDiagnostics.lastSeededOwnerCount)
          knownOwnerRefreshLastFirstResult: \(knownOwnerRefreshDiagnostics.lastFirstResultCount)
          knownOwnerRefreshLastFirstCoverage: \(String(format: "%.2f", knownOwnerRefreshDiagnostics.lastFirstCoverage))
          knownOwnerRefreshLastRetryOwners: \(knownOwnerRefreshDiagnostics.lastRetryOwnerCount)
          knownOwnerRefreshLastRetryResult: \(knownOwnerRefreshDiagnostics.lastRetryResultCount)
          knownOwnerRefreshLastRetryCoverage: \(String(format: "%.2f", knownOwnerRefreshDiagnostics.lastRetryCoverage))
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

    nonisolated static func shouldAcceptKnownOwnerPositionRefresh(
        seededItemCount: Int,
        refreshedItemCount: Int,
        minimumCoverage: Double = 0.7
    ) -> Bool {
        guard refreshedItemCount > 0 else { return false }
        guard seededItemCount > 0 else { return true }

        let coverage = knownOwnerPositionRefreshCoverage(
            seededItemCount: seededItemCount,
            refreshedItemCount: refreshedItemCount
        )
        return coverage >= minimumCoverage
    }

    nonisolated static func knownOwnerPositionRefreshCoverage(
        seededItemCount: Int,
        refreshedItemCount: Int
    ) -> Double {
        guard refreshedItemCount > 0 else { return 0 }
        guard seededItemCount > 0 else { return 1 }
        return Double(refreshedItemCount) / Double(seededItemCount)
    }

    func refreshKnownMenuBarItemsWithPositions() async -> [MenuBarItemPosition] {
        guard isTrusted else { return [] }

        let seededItemCount = menuBarItemCache.count
        var seededOwners: [RunningApp] = if !menuBarOwnersCache.isEmpty {
            menuBarOwnersCache
        } else {
            dedupedMenuBarOwners(from: menuBarItemCache.map(\.app))
        }

        if seededOwners.isEmpty {
            seededOwners = await refreshMenuBarItemOwners()
        }

        knownOwnerRefreshDiagnostics.attemptCount += 1
        knownOwnerRefreshDiagnostics.lastSeededItemCount = seededItemCount
        knownOwnerRefreshDiagnostics.lastSeededOwnerCount = seededOwners.count
        knownOwnerRefreshDiagnostics.lastFirstResultCount = 0
        knownOwnerRefreshDiagnostics.lastFirstCoverage = 0
        knownOwnerRefreshDiagnostics.lastRetryOwnerCount = 0
        knownOwnerRefreshDiagnostics.lastRetryResultCount = 0
        knownOwnerRefreshDiagnostics.lastRetryCoverage = 0
        knownOwnerRefreshDiagnostics.lastOutcome = "started"

        guard !seededOwners.isEmpty else {
            knownOwnerRefreshDiagnostics.fullFallbackCount += 1
            knownOwnerRefreshDiagnostics.lastOutcome = "fallback.noOwners"
            logger.debug("Known-owner position refresh could not discover any owners; falling back to full refresh")
            return await refreshMenuBarItemsWithPositions()
        }

        if let task = menuBarKnownItemsRefreshTask {
            return await task.value
        }

        let task = Task<[MenuBarItemPosition], Never> {
            await self.listKnownMenuBarItemsWithPositions(owners: seededOwners)
        }

        menuBarKnownItemsRefreshTask = task
        let result = await task.value
        menuBarKnownItemsRefreshTask = nil
        let firstCoverage = Self.knownOwnerPositionRefreshCoverage(
            seededItemCount: seededItemCount,
            refreshedItemCount: result.count
        )
        knownOwnerRefreshDiagnostics.lastFirstResultCount = result.count
        knownOwnerRefreshDiagnostics.lastFirstCoverage = firstCoverage

        guard Self.shouldAcceptKnownOwnerPositionRefresh(
            seededItemCount: seededItemCount,
            refreshedItemCount: result.count
        ) else {
            let refreshedOwners = await refreshMenuBarItemOwners()
            knownOwnerRefreshDiagnostics.lastRetryOwnerCount = refreshedOwners.count
            if !refreshedOwners.isEmpty {
                let retry = await self.listKnownMenuBarItemsWithPositions(owners: refreshedOwners)
                let retryCoverage = Self.knownOwnerPositionRefreshCoverage(
                    seededItemCount: seededItemCount,
                    refreshedItemCount: retry.count
                )
                knownOwnerRefreshDiagnostics.lastRetryResultCount = retry.count
                knownOwnerRefreshDiagnostics.lastRetryCoverage = retryCoverage
                if Self.shouldAcceptKnownOwnerPositionRefresh(
                    seededItemCount: seededItemCount,
                    refreshedItemCount: retry.count
                ) {
                    knownOwnerRefreshDiagnostics.acceptedCount += 1
                    knownOwnerRefreshDiagnostics.lastOutcome = "accepted.afterOwnerRefresh"
                    return retry
                }
                knownOwnerRefreshDiagnostics.fullFallbackCount += 1
                knownOwnerRefreshDiagnostics.lastOutcome = "fallback.lowCoverageAfterOwnerRefresh"
                logger.info(
                    "Known-owner position refresh stayed below coverage after owner refresh (seeded=\(seededItemCount, privacy: .public) first=\(result.count, privacy: .public) retry=\(retry.count, privacy: .public)); falling back to full refresh"
                )
            } else {
                knownOwnerRefreshDiagnostics.fullFallbackCount += 1
                knownOwnerRefreshDiagnostics.lastOutcome = "fallback.ownerRefreshEmpty"
                logger.info(
                    "Known-owner position refresh coverage too low and owner refresh returned no owners (seeded=\(seededItemCount, privacy: .public) refreshed=\(result.count, privacy: .public)); falling back to full refresh"
                )
            }
            return await refreshMenuBarItemsWithPositions()
        }

        knownOwnerRefreshDiagnostics.acceptedCount += 1
        knownOwnerRefreshDiagnostics.lastOutcome = "accepted.initial"
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

            if Self.cacheWarmupUsesKnownOwnerRefresh(for: reason) {
                _ = await self.refreshKnownMenuBarItemsWithPositions()
            } else {
                _ = await self.refreshMenuBarItemOwners()
                _ = await self.refreshMenuBarItemsWithPositions()
            }

            let elapsed = Date().timeIntervalSince(startTime)
            logger.info(
                "Menu bar cache pre-warmed (\(reason.rawValue, privacy: .public)) in \(String(format: "%.2f", elapsed), privacy: .public)s"
            )
            self.menuBarCacheWarmupTask = nil
        }
    }

    @MainActor
    func beginMenuBarCacheWarmupSuppression() {
        menuBarCacheWarmupSuppressionDepth += 1
        menuBarCacheWarmupTask?.cancel()
        menuBarCacheWarmupTask = nil
    }

    @MainActor
    func endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: Bool = true) {
        guard menuBarCacheWarmupSuppressionDepth > 0 else { return }
        menuBarCacheWarmupSuppressionDepth -= 1
        guard menuBarCacheWarmupSuppressionDepth == 0 else { return }

        let deferredReason = deferredMenuBarCacheWarmupReason
        deferredMenuBarCacheWarmupReason = nil
        guard scheduleDeferredWarmup, let deferredReason else { return }
        scheduleMenuBarCacheWarmup(reason: deferredReason)
    }

    /// Invalidates all menu bar caches, forcing a fresh scan on next call.
    /// Optionally schedules a background warmup so the next UI/script interaction
    /// does not pay the full cold-scan penalty.
    func invalidateMenuBarItemCache(scheduleWarmupAfter reason: CacheWarmupReason? = nil) {
        menuBarItemCacheTime = .distantPast
        menuBarOwnersCacheTime = .distantPast
        menuBarOwnersRefreshTask?.cancel()
        menuBarItemsRefreshTask?.cancel()
        menuBarKnownItemsRefreshTask?.cancel()
        menuBarCacheWarmupTask?.cancel()
        menuBarOwnersRefreshTask = nil
        menuBarItemsRefreshTask = nil
        menuBarKnownItemsRefreshTask = nil
        logger.debug("Menu bar item caches invalidated")

        if let reason {
            if menuBarCacheWarmupSuppressionDepth > 0 {
                deferredMenuBarCacheWarmupReason = Self.mergedDeferredCacheWarmupReason(
                    current: deferredMenuBarCacheWarmupReason,
                    new: reason
                )
                menuBarCacheWarmupTask = nil
            } else {
                scheduleMenuBarCacheWarmup(reason: reason)
            }
        } else {
            menuBarCacheWarmupTask = nil
        }
    }

    /// Invalidates only positioned item state.
    /// Use this when icon lanes moved but the owner set did not change.
    func invalidateMenuBarItemPositionsCache() {
        menuBarItemCacheTime = .distantPast
        menuBarItemsRefreshTask?.cancel()
        menuBarKnownItemsRefreshTask?.cancel()
        menuBarItemsRefreshTask = nil
        menuBarKnownItemsRefreshTask = nil
        menuBarCacheWarmupTask?.cancel()
        menuBarCacheWarmupTask = nil
        logger.debug("Menu bar item position cache invalidated")
    }

    private func dedupedMenuBarOwners(from owners: [RunningApp]) -> [RunningApp] {
        var seenBundleIDs = Set<String>()
        var deduped: [RunningApp] = []
        deduped.reserveCapacity(owners.count)

        for owner in owners {
            guard seenBundleIDs.insert(owner.bundleId).inserted else { continue }
            deduped.append(owner)
        }

        return deduped
    }

    /// Pre-warms the menu bar caches in the background.
    /// Call this on app launch so Find Icon opens instantly.
    func prewarmCache() {
        scheduleMenuBarCacheWarmup(reason: .launch)
    }
}
