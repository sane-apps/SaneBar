import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Cache")

extension AccessibilityService {
    
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
            // Candidate apps list must be gathered on the main thread.
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let candidatePIDs: [pid_t] = NSWorkspace.shared.runningApplications.compactMap { app in
                guard app.processIdentifier != selfPID else { return nil }
                if let bundleID = app.bundleIdentifier,
                   bundleID == Bundle.main.bundleIdentifier {
                    return nil
                }
                return app.processIdentifier
            }

            let pidsWithExtras = await Self.scanMenuBarOwnerPIDs(candidatePIDs: candidatePIDs)

            var seenIds = Set<String>()
            var apps: [RunningApp] = []
            apps.reserveCapacity(pidsWithExtras.count)
            var controlCenterPID: pid_t?

            for pid in pidsWithExtras {
                guard let app = NSRunningApplication(processIdentifier: pid),
                      let bundleID = Self.resolvedBundleIdentifier(for: app) else { continue }

                // Special case: Control Center - remember its PID for later expansion
                if bundleID == "com.apple.controlcenter" {
                    controlCenterPID = pid
                    continue  // Don't add the collapsed entry
                }

                guard !seenIds.contains(bundleID) else { continue }
                seenIds.insert(bundleID)
                apps.append(RunningApp(app: app, resolvedBundleId: bundleID))
            }

            // Expand Control Center into individual items (Battery, WiFi, Clock, etc.)
            if let ccPID = controlCenterPID {
                let ccItems = Self.enumerateControlCenterItems(pid: ccPID)
                for item in ccItems {
                    let key = item.app.uniqueId
                    guard !seenIds.contains(key) else { continue }
                    seenIds.insert(key)
                    apps.append(item.app)
                }
            }

            let sortedApps = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            self.menuBarOwnersCache = sortedApps
            self.menuBarOwnersCacheTime = Date()
            return sortedApps
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
    
    /// Invalidates all menu bar caches, forcing a fresh scan on next call.
    /// Call this when you know menu bar items have changed (e.g., after hiding/showing).
    func invalidateMenuBarItemCache() {
        menuBarItemCacheTime = .distantPast
        menuBarOwnersCacheTime = .distantPast
        menuBarOwnersRefreshTask?.cancel()
        menuBarItemsRefreshTask?.cancel()
        menuBarOwnersRefreshTask = nil
        menuBarItemsRefreshTask = nil
        logger.debug("Menu bar item caches invalidated")
    }

    /// Pre-warms the menu bar caches in the background.
    /// Call this on app launch so Find Icon opens instantly.
    func prewarmCache() {
        guard isTrusted else {
            logger.debug("Skipping cache prewarm - accessibility not granted")
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            logger.info("Pre-warming menu bar cache...")
            let startTime = Date()

            // Warm both caches (off the main thread)
            _ = await self.refreshMenuBarItemOwners()
            _ = await self.refreshMenuBarItemsWithPositions()

            let elapsed = Date().timeIntervalSince(startTime)
            logger.info("Menu bar cache pre-warmed in \(String(format: "%.2f", elapsed))s")
        }
    }
}
