import Foundation
import os.log

private let accessibilityCacheLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityMenuBarCacheStore")

@MainActor
final class AccessibilityMenuBarCacheStore {
    typealias MenuBarItemPosition = AccessibilityService.MenuBarItemPosition
    typealias CacheWarmupReason = AccessibilityService.CacheWarmupReason
    typealias KnownOwnerRefreshDiagnostics = AccessibilityService.KnownOwnerRefreshDiagnostics

    private unowned let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    nonisolated static func cacheWarmupDelay(for reason: CacheWarmupReason) -> TimeInterval {
        switch reason {
        case .launch:
            return 0
        case .reveal:
            // Let WindowServer finish the reveal relayout before scanning.
            return 0.2
        case .conceal:
            return 0.1
        case .structuralChange:
            return 0.25
        }
    }

    nonisolated static func cacheWarmupUsesKnownOwnerRefresh(for reason: CacheWarmupReason) -> Bool {
        switch reason {
        case .launch:
            return false
        case .reveal, .conceal, .structuralChange:
            return true
        }
    }

    nonisolated static func mergedDeferredCacheWarmupReason(
        current: CacheWarmupReason?,
        new: CacheWarmupReason
    ) -> CacheWarmupReason {
        func priority(for reason: CacheWarmupReason) -> Int {
            switch reason {
            case .launch:
                0
            case .conceal:
                1
            case .reveal:
                2
            case .structuralChange:
                3
            }
        }

        guard let current else { return new }
        return priority(for: new) >= priority(for: current) ? new : current
    }

    @MainActor
    func diagnosticsSnapshot() -> String {
        func ageString(since date: Date) -> String {
            guard date != .distantPast else { return "stale" }
            return String(format: "%.1fs", Date().timeIntervalSince(date))
        }

        let noExtrasBundles = accessibilityService.bundlesWithoutExtrasMenuBarSnapshot()
        let bundleSummary = noExtrasBundles.prefix(6).joined(separator: ", ")
        let bundleSuffix = noExtrasBundles.count > 6 ? ", …" : ""

        return """
        accessibility:
          granted: \(accessibilityService.isGranted)
          ownersCacheCount: \(accessibilityService.menuBarOwnersCache.count)
          ownersCacheAge: \(ageString(since: accessibilityService.menuBarOwnersCacheTime))
          itemsCacheCount: \(accessibilityService.menuBarItemCache.count)
          itemsCacheAge: \(ageString(since: accessibilityService.menuBarItemCacheTime))
          ownersRefreshInFlight: \(accessibilityService.menuBarOwnersRefreshTask != nil)
          itemsRefreshInFlight: \(accessibilityService.menuBarItemsRefreshTask != nil)
          cacheWarmupInFlight: \(accessibilityService.menuBarCacheWarmupTask != nil)
          cacheWarmupSuppressionDepth: \(accessibilityService.menuBarCacheWarmupSuppressionDepth)
          deferredCacheWarmupReason: \(accessibilityService.deferredMenuBarCacheWarmupReason?.rawValue ?? "none")
          knownOwnerRefreshAttempts: \(accessibilityService.knownOwnerRefreshDiagnostics.attemptCount)
          knownOwnerRefreshAccepted: \(accessibilityService.knownOwnerRefreshDiagnostics.acceptedCount)
          knownOwnerRefreshFullFallbacks: \(accessibilityService.knownOwnerRefreshDiagnostics.fullFallbackCount)
          knownOwnerRefreshLastOutcome: \(accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome)
          knownOwnerRefreshLastSeededItems: \(accessibilityService.knownOwnerRefreshDiagnostics.lastSeededItemCount)
          knownOwnerRefreshLastSeededOwners: \(accessibilityService.knownOwnerRefreshDiagnostics.lastSeededOwnerCount)
          knownOwnerRefreshLastFirstResult: \(accessibilityService.knownOwnerRefreshDiagnostics.lastFirstResultCount)
          knownOwnerRefreshLastFirstCoverage: \(String(format: "%.2f", accessibilityService.knownOwnerRefreshDiagnostics.lastFirstCoverage))
          knownOwnerRefreshLastRetryOwners: \(accessibilityService.knownOwnerRefreshDiagnostics.lastRetryOwnerCount)
          knownOwnerRefreshLastRetryResult: \(accessibilityService.knownOwnerRefreshDiagnostics.lastRetryResultCount)
          knownOwnerRefreshLastRetryCoverage: \(String(format: "%.2f", accessibilityService.knownOwnerRefreshDiagnostics.lastRetryCoverage))
          bundlesWithoutExtrasMenuBarCount: \(noExtrasBundles.count)
          bundlesWithoutExtrasMenuBar: \(bundleSummary.isEmpty ? "none" : bundleSummary + bundleSuffix)
        """
    }

    // MARK: - Cached Results (Fast)

    func cachedMenuBarItemOwners() -> [RunningApp] {
        accessibilityService.menuBarOwnersCache
    }

    func cachedMenuBarItemsWithPositions() -> [MenuBarItemPosition] {
        accessibilityService.menuBarItemCache
    }

    // MARK: - Async Refresh (Non-blocking)

    func refreshMenuBarItemOwners() async -> [RunningApp] {
        guard accessibilityService.isTrusted else { return [] }

        let now = Date()
        if now.timeIntervalSince(accessibilityService.menuBarOwnersCacheTime) < accessibilityService.menuBarOwnersCacheValiditySeconds && !accessibilityService.menuBarOwnersCache.isEmpty {
            return accessibilityService.menuBarOwnersCache
        }

        if let task = accessibilityService.menuBarOwnersRefreshTask {
            return await task.value
        }

        let task = Task<[RunningApp], Never> {
            await self.accessibilityService.listMenuBarItemOwners()
        }

        accessibilityService.menuBarOwnersRefreshTask = task
        let result = await task.value
        accessibilityService.menuBarOwnersRefreshTask = nil
        return result
    }

    func refreshMenuBarItemsWithPositions() async -> [MenuBarItemPosition] {
        guard accessibilityService.isTrusted else { return [] }

        let now = Date()
        if now.timeIntervalSince(accessibilityService.menuBarItemCacheTime) < accessibilityService.menuBarItemCacheValiditySeconds && !accessibilityService.menuBarItemCache.isEmpty {
            return accessibilityService.menuBarItemCache
        }

        if let task = accessibilityService.menuBarItemsRefreshTask {
            return await task.value
        }

        let task = Task<[MenuBarItemPosition], Never> {
            // Use the authoritative scanner (includes width) and benefits from its caching.
            await self.accessibilityService.listMenuBarItemsWithPositions()
        }

        accessibilityService.menuBarItemsRefreshTask = task
        let result = await task.value
        accessibilityService.menuBarItemsRefreshTask = nil
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
        guard accessibilityService.isTrusted else { return [] }

        let seededItemCount = accessibilityService.menuBarItemCache.count
        var seededOwners: [RunningApp] = if !accessibilityService.menuBarOwnersCache.isEmpty {
            accessibilityService.menuBarOwnersCache
        } else {
            dedupedMenuBarOwners(from: accessibilityService.menuBarItemCache.map(\.app))
        }

        if seededOwners.isEmpty {
            seededOwners = await refreshMenuBarItemOwners()
        }

        accessibilityService.knownOwnerRefreshDiagnostics.attemptCount += 1
        accessibilityService.knownOwnerRefreshDiagnostics.lastSeededItemCount = seededItemCount
        accessibilityService.knownOwnerRefreshDiagnostics.lastSeededOwnerCount = seededOwners.count
        accessibilityService.knownOwnerRefreshDiagnostics.lastFirstResultCount = 0
        accessibilityService.knownOwnerRefreshDiagnostics.lastFirstCoverage = 0
        accessibilityService.knownOwnerRefreshDiagnostics.lastRetryOwnerCount = 0
        accessibilityService.knownOwnerRefreshDiagnostics.lastRetryResultCount = 0
        accessibilityService.knownOwnerRefreshDiagnostics.lastRetryCoverage = 0
        accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome = "started"

        guard !seededOwners.isEmpty else {
            accessibilityService.knownOwnerRefreshDiagnostics.fullFallbackCount += 1
            accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome = "fallback.noOwners"
            accessibilityCacheLogger.debug("Known-owner position refresh could not discover any owners; falling back to full refresh")
            return await refreshMenuBarItemsWithPositions()
        }

        if let task = accessibilityService.menuBarKnownItemsRefreshTask {
            return await task.value
        }

        let task = Task<[MenuBarItemPosition], Never> {
            await self.accessibilityService.listKnownMenuBarItemsWithPositions(owners: seededOwners)
        }

        accessibilityService.menuBarKnownItemsRefreshTask = task
        let result = await task.value
        accessibilityService.menuBarKnownItemsRefreshTask = nil
        let firstCoverage = AccessibilityService.knownOwnerPositionRefreshCoverage(
            seededItemCount: seededItemCount,
            refreshedItemCount: result.count
        )
        accessibilityService.knownOwnerRefreshDiagnostics.lastFirstResultCount = result.count
        accessibilityService.knownOwnerRefreshDiagnostics.lastFirstCoverage = firstCoverage

        guard AccessibilityService.shouldAcceptKnownOwnerPositionRefresh(
            seededItemCount: seededItemCount,
            refreshedItemCount: result.count
        ) else {
            let refreshedOwners = await refreshMenuBarItemOwners()
            accessibilityService.knownOwnerRefreshDiagnostics.lastRetryOwnerCount = refreshedOwners.count
            if !refreshedOwners.isEmpty {
                let retry = await self.accessibilityService.listKnownMenuBarItemsWithPositions(owners: refreshedOwners)
                let retryCoverage = AccessibilityService.knownOwnerPositionRefreshCoverage(
                    seededItemCount: seededItemCount,
                    refreshedItemCount: retry.count
                )
                accessibilityService.knownOwnerRefreshDiagnostics.lastRetryResultCount = retry.count
                accessibilityService.knownOwnerRefreshDiagnostics.lastRetryCoverage = retryCoverage
                if AccessibilityService.shouldAcceptKnownOwnerPositionRefresh(
                    seededItemCount: seededItemCount,
                    refreshedItemCount: retry.count
                ) {
                    accessibilityService.knownOwnerRefreshDiagnostics.acceptedCount += 1
                    accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome = "accepted.afterOwnerRefresh"
                    return retry
                }
                accessibilityService.knownOwnerRefreshDiagnostics.fullFallbackCount += 1
                accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome = "fallback.lowCoverageAfterOwnerRefresh"
                accessibilityCacheLogger.info(
                    "Known-owner position refresh stayed below coverage after owner refresh (seeded=\(seededItemCount, privacy: .public) first=\(result.count, privacy: .public) retry=\(retry.count, privacy: .public)); falling back to full refresh"
                )
            } else {
                accessibilityService.knownOwnerRefreshDiagnostics.fullFallbackCount += 1
                accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome = "fallback.ownerRefreshEmpty"
                accessibilityCacheLogger.info(
                    "Known-owner position refresh coverage too low and owner refresh returned no owners (seeded=\(seededItemCount, privacy: .public) refreshed=\(result.count, privacy: .public)); falling back to full refresh"
                )
            }
            return await refreshMenuBarItemsWithPositions()
        }

        accessibilityService.knownOwnerRefreshDiagnostics.acceptedCount += 1
        accessibilityService.knownOwnerRefreshDiagnostics.lastOutcome = "accepted.initial"
        return result
    }

    @MainActor
    private func scheduleMenuBarCacheWarmup(reason: CacheWarmupReason) {
        guard accessibilityService.isTrusted else {
            accessibilityCacheLogger.debug("Skipping cache warmup (\(reason.rawValue, privacy: .public)) - accessibility not granted")
            return
        }

        accessibilityService.menuBarCacheWarmupTask?.cancel()
        let delaySeconds = Self.cacheWarmupDelay(for: reason)

        accessibilityService.menuBarCacheWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if delaySeconds > 0 {
                try? await Task.sleep(for: .milliseconds(Int(delaySeconds * 1000)))
            }
            guard !Task.isCancelled else {
                self.accessibilityService.menuBarCacheWarmupTask = nil
                return
            }

            accessibilityCacheLogger.info("Pre-warming menu bar cache (\(reason.rawValue, privacy: .public))...")
            let startTime = Date()

            if Self.cacheWarmupUsesKnownOwnerRefresh(for: reason) {
                _ = await self.refreshKnownMenuBarItemsWithPositions()
            } else {
                _ = await self.refreshMenuBarItemOwners()
                _ = await self.refreshMenuBarItemsWithPositions()
            }

            let elapsed = Date().timeIntervalSince(startTime)
            accessibilityCacheLogger.info(
                "Menu bar cache pre-warmed (\(reason.rawValue, privacy: .public)) in \(String(format: "%.2f", elapsed), privacy: .public)s"
            )
            self.accessibilityService.menuBarCacheWarmupTask = nil
        }
    }

    @MainActor
    func beginMenuBarCacheWarmupSuppression() {
        accessibilityService.menuBarCacheWarmupSuppressionDepth += 1
        accessibilityService.menuBarCacheWarmupTask?.cancel()
        accessibilityService.menuBarCacheWarmupTask = nil
    }

    @MainActor
    func endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: Bool = true) {
        guard accessibilityService.menuBarCacheWarmupSuppressionDepth > 0 else { return }
        accessibilityService.menuBarCacheWarmupSuppressionDepth -= 1
        guard accessibilityService.menuBarCacheWarmupSuppressionDepth == 0 else { return }

        let deferredReason = accessibilityService.deferredMenuBarCacheWarmupReason
        accessibilityService.deferredMenuBarCacheWarmupReason = nil
        guard scheduleDeferredWarmup, let deferredReason else { return }
        scheduleMenuBarCacheWarmup(reason: deferredReason)
    }

    /// Invalidates all menu bar caches, forcing a fresh scan on next call.
    /// Optionally schedules a background warmup so the next UI/script interaction
    /// does not pay the full cold-scan penalty.
    func invalidateMenuBarItemCache(scheduleWarmupAfter reason: CacheWarmupReason? = nil) {
        accessibilityService.menuBarItemCacheTime = .distantPast
        accessibilityService.menuBarOwnersCacheTime = .distantPast
        accessibilityService.menuBarOwnersRefreshTask?.cancel()
        accessibilityService.menuBarItemsRefreshTask?.cancel()
        accessibilityService.menuBarKnownItemsRefreshTask?.cancel()
        accessibilityService.menuBarCacheWarmupTask?.cancel()
        accessibilityService.menuBarOwnersRefreshTask = nil
        accessibilityService.menuBarItemsRefreshTask = nil
        accessibilityService.menuBarKnownItemsRefreshTask = nil
        accessibilityCacheLogger.debug("Menu bar item caches invalidated")

        if let reason {
            if accessibilityService.menuBarCacheWarmupSuppressionDepth > 0 {
                accessibilityService.deferredMenuBarCacheWarmupReason = Self.mergedDeferredCacheWarmupReason(
                    current: accessibilityService.deferredMenuBarCacheWarmupReason,
                    new: reason
                )
                accessibilityService.menuBarCacheWarmupTask = nil
            } else {
                scheduleMenuBarCacheWarmup(reason: reason)
            }
        } else {
            accessibilityService.menuBarCacheWarmupTask = nil
        }
    }

    /// Invalidates only positioned item state.
    /// Use this when icon lanes moved but the owner set did not change.
    func invalidateMenuBarItemPositionsCache() {
        accessibilityService.menuBarItemCacheTime = .distantPast
        accessibilityService.menuBarItemsRefreshTask?.cancel()
        accessibilityService.menuBarKnownItemsRefreshTask?.cancel()
        accessibilityService.menuBarItemsRefreshTask = nil
        accessibilityService.menuBarKnownItemsRefreshTask = nil
        accessibilityService.menuBarCacheWarmupTask?.cancel()
        accessibilityService.menuBarCacheWarmupTask = nil
        accessibilityCacheLogger.debug("Menu bar item position cache invalidated")
    }

    /// Keep a deliberately refreshed pre-hide item-position snapshot alive after
    /// a manual move restores the hidden state. Hidden-state AX geometry pushes
    /// regular Hidden items far offscreen, which can otherwise look identical to
    /// Always Hidden during the immediate post-move AppleScript verification.
    @MainActor
    func preserveFreshMenuBarItemPositionsAfterManualMove() {
        guard !accessibilityService.menuBarItemCache.isEmpty else { return }
        accessibilityService.menuBarItemCacheTime = Date()
        accessibilityService.menuBarItemsRefreshTask?.cancel()
        accessibilityService.menuBarKnownItemsRefreshTask?.cancel()
        accessibilityService.menuBarCacheWarmupTask?.cancel()
        accessibilityService.menuBarItemsRefreshTask = nil
        accessibilityService.menuBarKnownItemsRefreshTask = nil
        accessibilityService.menuBarCacheWarmupTask = nil
        accessibilityService.deferredMenuBarCacheWarmupReason = nil
        accessibilityCacheLogger.debug("Preserved fresh menu bar item position cache after manual move")
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
    }}
