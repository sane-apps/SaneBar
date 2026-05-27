import Foundation

extension AccessibilityService {
    private var menuBarCacheStore: AccessibilityMenuBarCacheStore { AccessibilityMenuBarCacheStore(accessibilityService: self) }

    @MainActor func diagnosticsSnapshot() -> String { menuBarCacheStore.diagnosticsSnapshot() }
    func cachedMenuBarItemOwners() -> [RunningApp] { menuBarCacheStore.cachedMenuBarItemOwners() }
    func cachedMenuBarItemsWithPositions() -> [MenuBarItemPosition] { menuBarCacheStore.cachedMenuBarItemsWithPositions() }
    func refreshMenuBarItemOwners() async -> [RunningApp] { await menuBarCacheStore.refreshMenuBarItemOwners() }
    func refreshMenuBarItemsWithPositions() async -> [MenuBarItemPosition] { await menuBarCacheStore.refreshMenuBarItemsWithPositions() }
    nonisolated static func shouldAcceptKnownOwnerPositionRefresh(seededItemCount: Int, refreshedItemCount: Int, minimumCoverage: Double = 0.7) -> Bool { AccessibilityMenuBarCacheStore.shouldAcceptKnownOwnerPositionRefresh(seededItemCount: seededItemCount, refreshedItemCount: refreshedItemCount, minimumCoverage: minimumCoverage) }
    nonisolated static func knownOwnerPositionRefreshCoverage(seededItemCount: Int, refreshedItemCount: Int) -> Double { AccessibilityMenuBarCacheStore.knownOwnerPositionRefreshCoverage(seededItemCount: seededItemCount, refreshedItemCount: refreshedItemCount) }
    func refreshKnownMenuBarItemsWithPositions() async -> [MenuBarItemPosition] { await menuBarCacheStore.refreshKnownMenuBarItemsWithPositions() }
    @MainActor func beginMenuBarCacheWarmupSuppression() { menuBarCacheStore.beginMenuBarCacheWarmupSuppression() }
    @MainActor func endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: Bool = true) { menuBarCacheStore.endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: scheduleDeferredWarmup) }
    func invalidateMenuBarItemCache(scheduleWarmupAfter reason: CacheWarmupReason? = nil) { menuBarCacheStore.invalidateMenuBarItemCache(scheduleWarmupAfter: reason) }
    func invalidateMenuBarItemPositionsCache() { menuBarCacheStore.invalidateMenuBarItemPositionsCache() }
    @MainActor func preserveFreshMenuBarItemPositionsAfterManualMove() { menuBarCacheStore.preserveFreshMenuBarItemPositionsAfterManualMove() }
    func prewarmCache() { menuBarCacheStore.prewarmCache() }
}
