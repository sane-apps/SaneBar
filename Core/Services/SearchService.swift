import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "SearchService")

// MARK: - SearchService

final class SearchService: SearchServiceProtocol, @unchecked Sendable {
    static let shared = SearchService()
    private var lastAlwaysHiddenOrderWarningAt: Date?
    private let activationGate = SearchActivationGate(debounceInterval: 0.45)
    private let clickAttemptTimeoutMs: Int = 900
    private var lastActivationDiagnostics = SearchServiceSupport.ActivationDiagnostics()

    enum VisibilityZone: Equatable, Hashable {
        case visible
        case hidden
        case alwaysHidden
    }

    @MainActor
    func diagnosticsSnapshot() -> String {
        lastActivationDiagnostics.formattedSummary()
    }

    @MainActor
    private func menuBarScreenFrame() -> CGRect? {
        if let screen = MenuBarManager.shared.mainStatusItem?.button?.window?.screen {
            return screen.frame
        }
        return NSScreen.main?.frame
    }

    @MainActor
    private func separatorBoundaryXForClassification(allowEstimatedFallback: Bool = false) -> CGFloat? {
        // Use the separator's right edge as the hidden/visible boundary.
        // In collapsed mode, right-edge cache remains stable while live AX frames
        // can lag, which avoids misclassifying hidden icons as visible.
        if let rightEdge = MenuBarManager.shared.geometryResolver.separatorRightEdgeX(allowEstimatedFallback: allowEstimatedFallback) {
            return rightEdge
        }
        return MenuBarManager.shared.geometryResolver.separatorOriginX(allowEstimatedFallback: allowEstimatedFallback)
    }

    /// Normalize the always-hidden boundary against the main separator boundary.
    /// Returns nil when the candidate is stale/inverted (on or to the right of main).
    nonisolated static func normalizedAlwaysHiddenBoundary(
        _ candidate: CGFloat?,
        separatorX: CGFloat,
        minimumGap: CGFloat = 8
    ) -> CGFloat? {
        guard let candidate, candidate.isFinite, candidate > 0 else { return nil }
        guard separatorX.isFinite, separatorX > 0 else { return nil }

        let maxAllowed = separatorX - max(1, minimumGap)
        guard maxAllowed > 0 else { return nil }
        guard candidate < maxAllowed else { return nil }
        return candidate
    }

    @MainActor
    private func separatorOriginsForClassification(
        allowEstimatedFallback: Bool = false
    ) -> (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?)? {
        guard let separatorX = separatorBoundaryXForClassification(allowEstimatedFallback: allowEstimatedFallback) else { return nil }

        guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else {
            return (separatorX, nil)
        }

        // During collapsed hidden mode and active browse sessions, WindowServer
        // geometry can temporarily place regular hidden items left of the AH
        // separator. Use pinned IDs only when live AH geometry is unavailable
        // or stale; otherwise browse panels should reflect the real separator.
        if SearchServiceSupport.shouldUsePinnedAlwaysHiddenFallback(
            hidingState: MenuBarManager.shared.hidingService.state,
            isBrowseSessionActive: SearchWindowController.shared.isBrowseSessionActive
        ),
            MenuBarManager.shared.geometryResolver.alwaysHiddenSeparatorBoundaryX() == nil {
            return (separatorX, nil)
        }

        let alwaysHiddenSeparatorOriginX = MenuBarManager.shared.geometryResolver.alwaysHiddenSeparatorOriginX()
        let rawAlwaysHiddenBoundaryX = MenuBarManager.shared.geometryResolver.alwaysHiddenSeparatorBoundaryX()
        var alwaysHiddenBoundaryX = Self.normalizedAlwaysHiddenBoundary(
            rawAlwaysHiddenBoundaryX,
            separatorX: separatorX
        )
        if let rawAlwaysHiddenBoundaryX, alwaysHiddenBoundaryX == nil {
            logger.warning(
                "Dropping stale always-hidden boundary candidate (\(rawAlwaysHiddenBoundaryX, privacy: .public)) with separator=\(separatorX, privacy: .public)"
            )
        }

        if alwaysHiddenBoundaryX == nil,
           let alwaysHiddenSeparatorOriginX,
           alwaysHiddenSeparatorOriginX > 0 {
            alwaysHiddenBoundaryX = Self.normalizedAlwaysHiddenBoundary(
                alwaysHiddenSeparatorOriginX + 20,
                separatorX: separatorX
            )
        }

        if let alwaysHiddenSeparatorOriginX,
           alwaysHiddenSeparatorOriginX >= separatorX {
            let now = Date()
            if let last = lastAlwaysHiddenOrderWarningAt {
                if now.timeIntervalSince(last) >= 5 {
                    logger.warning("Always-hidden separator is not left of main separator; attempting repair")
                    lastAlwaysHiddenOrderWarningAt = now
                }
            } else {
                logger.warning("Always-hidden separator is not left of main separator; attempting repair")
                lastAlwaysHiddenOrderWarningAt = now
            }

            MenuBarManager.shared.alwaysHiddenPinWorkflow.repairSeparatorPositionIfNeeded(reason: "classification")
            let repairedSeparatorX = separatorBoundaryXForClassification(allowEstimatedFallback: allowEstimatedFallback) ?? separatorX
            let repairedAlwaysHiddenOriginX = MenuBarManager.shared.geometryResolver.alwaysHiddenSeparatorOriginX()
            let rawRepairedAlwaysHiddenBoundaryX = MenuBarManager.shared.geometryResolver.alwaysHiddenSeparatorBoundaryX()
            var repairedAlwaysHiddenBoundaryX = Self.normalizedAlwaysHiddenBoundary(
                rawRepairedAlwaysHiddenBoundaryX,
                separatorX: repairedSeparatorX
            )
            if let rawRepairedAlwaysHiddenBoundaryX, repairedAlwaysHiddenBoundaryX == nil {
                logger.warning(
                    "Dropping stale repaired always-hidden boundary candidate (\(rawRepairedAlwaysHiddenBoundaryX, privacy: .public)) with separator=\(repairedSeparatorX, privacy: .public)"
                )
            }
            if repairedAlwaysHiddenBoundaryX == nil,
               let repairedAlwaysHiddenOriginX,
               repairedAlwaysHiddenOriginX > 0 {
                repairedAlwaysHiddenBoundaryX = Self.normalizedAlwaysHiddenBoundary(
                    repairedAlwaysHiddenOriginX + 20,
                    separatorX: repairedSeparatorX
                )
            }
            if let repairedAlwaysHiddenOriginX,
               repairedAlwaysHiddenOriginX < repairedSeparatorX,
               let repairedAlwaysHiddenBoundaryX {
                return (repairedSeparatorX, repairedAlwaysHiddenBoundaryX)
            }
            return (repairedSeparatorX, nil)
        }

        // If AH position is unavailable or stale/inverted, return nil for AH.
        // classifyItems will use pinned IDs as a post-pass instead of trusting bad geometry.
        return (separatorX, alwaysHiddenBoundaryX)
    }

    /// Match apps against persisted always-hidden pinned IDs.
    /// Used as fallback when position-based classification is unavailable (items off-screen).
    @MainActor
    private func appsMatchingPinnedIds(from apps: [RunningApp]) -> [RunningApp] {
        let pinnedIds = Set(MenuBarManager.shared.settings.alwaysHiddenPinnedItemIds)
        guard !pinnedIds.isEmpty else { return [] }
        let matched = apps.filter { app in
            pinnedIds.contains(app.uniqueId) || pinnedIds.contains(app.bundleId)
        }
        logger.debug("alwaysHidden fallback: matched \(matched.count, privacy: .public) apps from \(pinnedIds.count, privacy: .public) pinned IDs")
        return matched
    }

    nonisolated static func promotePinnedHiddenAppsToAlwaysHidden(
        hidden: [RunningApp],
        alwaysHidden: [RunningApp],
        pinnedIds: Set<String>
    ) -> (hidden: [RunningApp], alwaysHidden: [RunningApp]) {
        guard !pinnedIds.isEmpty else { return (hidden, alwaysHidden) }

        let promoted = hidden.filter { app in
            pinnedIds.contains(app.uniqueId) || pinnedIds.contains(app.bundleId)
        }
        guard !promoted.isEmpty else { return (hidden, alwaysHidden) }

        let promotedIds = Set(promoted.map(\.uniqueId))
        let existingAlwaysHiddenIds = Set(alwaysHidden.map(\.uniqueId))
        let appended = promoted.filter { !existingAlwaysHiddenIds.contains($0.uniqueId) }

        return (
            hidden.filter { !promotedIds.contains($0.uniqueId) },
            alwaysHidden + appended
        )
    }

    private func isOffscreen(x: CGFloat, in screenFrame: CGRect) -> Bool {
        SearchMenuBarZoneClassifier.isOffscreen(x: x, in: screenFrame)
    }

    /// Classify an item's zone based on its position relative to separators.
    /// Internal for testability — the core zone classification logic.
    func classifyZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        separatorX: CGFloat,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> VisibilityZone {
        SearchMenuBarZoneClassifier.classifyZone(
            itemX: itemX,
            itemWidth: itemWidth,
            separatorX: separatorX,
            alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
        )
    }

    nonisolated static func alwaysHiddenSeparatorForClassification(
        hidingState: HidingState,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> CGFloat? {
        hidingState == .hidden ? nil : alwaysHiddenSeparatorX
    }

    func getRunningApps() async -> [RunningApp] {
        await SearchRunningAppsProvider.runningApps()
    }

    func getMenuBarApps() async -> [RunningApp] {
        await refreshMenuBarApps()
    }

    func getHiddenMenuBarApps() async -> [RunningApp] {
        await refreshHiddenMenuBarApps()
    }

    func getAlwaysHiddenMenuBarApps() async -> [RunningApp] {
        await refreshAlwaysHiddenMenuBarApps()
    }

    @MainActor
    func cachedMenuBarApps() -> [RunningApp] {
        let positioned = AccessibilityService.shared.cachedMenuBarItemsWithPositions().map(\.app)
        let owners = AccessibilityService.shared.cachedMenuBarItemOwners()
        return SearchServiceSupport.mergedDiscoverableApps(positioned: positioned, owners: owners)
    }

    @MainActor
    func cachedHiddenMenuBarApps() -> [RunningApp] {
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()

        // Classify by separator position (works even when temporarily expanded for moving)
        if let positions = separatorOriginsForClassification() {
            logger.debug("cachedHidden: using separatorX=\(positions.separatorX, privacy: .public) for classification")
            let apps = items
                .filter {
                    classifyZone(
                        itemX: $0.x,
                        itemWidth: $0.app.width,
                        separatorX: positions.separatorX,
                        alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                    ) == .hidden
                }
                .map(\.app)
            logger.debug("cachedHidden: found \(apps.count, privacy: .public) hidden apps")
            logIdentityHealth(apps: apps, context: "cachedHidden")
            return apps
        }

        // Fallback: if separator can't be located, approximate by offscreen or negative X.
        guard let frame = menuBarScreenFrame() else {
            return items.filter { $0.x < 0 }.map(\.app)
        }

        let apps = items.filter { isOffscreen(x: $0.x, in: frame) }.map(\.app)

        logIdentityHealth(apps: apps, context: "cachedHidden")
        return apps
    }

    @MainActor
    func cachedAlwaysHiddenMenuBarApps() -> [RunningApp] {
        guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else { return [] }
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()

        if let positions = separatorOriginsForClassification(), positions.alwaysHiddenSeparatorX != nil {
            let apps = items
                .filter {
                    classifyZone(
                        itemX: $0.x,
                        itemWidth: $0.app.width,
                        separatorX: positions.separatorX,
                        alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                    ) == .alwaysHidden
                }
                .map(\.app)
            logger.debug("cachedAlwaysHidden: found \(apps.count, privacy: .public) always hidden apps")
            logIdentityHealth(apps: apps, context: "cachedAlwaysHidden")
            return apps
        }

        // Fallback: when positions are unavailable (items off-screen at startup),
        // match against persisted pinned IDs to identify always-hidden apps.
        return appsMatchingPinnedIds(from: items.map(\.app))
    }

    @MainActor
    func cachedVisibleMenuBarApps() -> [RunningApp] {
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()

        // Classify by separator position (works even when temporarily expanded for moving)
        if let positions = separatorOriginsForClassification() {
            logger.debug("cachedVisible: using separatorX=\(positions.separatorX, privacy: .public) for classification")
            let apps = items
                .filter {
                    classifyZone(
                        itemX: $0.x,
                        itemWidth: $0.app.width,
                        separatorX: positions.separatorX,
                        alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                    ) == .visible
                }
                .map(\.app)
            logger.debug("cachedVisible: found \(apps.count, privacy: .public) visible apps")
            logIdentityHealth(apps: apps, context: "cachedVisible")
            return apps
        }

        // Fallback: separator unavailable — use the same robust single-pass
        // classifier used by refresh/cachedClassifiedApps.
        let classified = classifyItems(items)
        logger.debug("cachedVisible: no separator, fallback visible count \(classified.visible.count, privacy: .public)")
        logIdentityHealth(apps: classified.visible, context: "cachedVisibleFallback")
        return classified.visible
    }

    func refreshMenuBarApps() async -> [RunningApp] {
        let items = await AccessibilityService.shared.refreshKnownMenuBarItemsWithPositions()
        let cachedOwners = await MainActor.run {
            AccessibilityService.shared.cachedMenuBarItemOwners()
        }
        let owners = if cachedOwners.isEmpty {
            await AccessibilityService.shared.refreshMenuBarItemOwners()
        } else {
            cachedOwners
        }
        return await MainActor.run {
            SearchServiceSupport.mergedDiscoverableApps(positioned: items.map(\.app), owners: owners)
        }
    }

    func refreshHiddenMenuBarApps() async -> [RunningApp] {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        let (positions, frame) = await MainActor.run {
            (self.separatorOriginsForClassification(), self.menuBarScreenFrame())
        }

        if let positions {
            let apps = items
                .filter {
                    self.classifyZone(
                        itemX: $0.x,
                        itemWidth: $0.app.width,
                        separatorX: positions.separatorX,
                        alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                    ) == .hidden
                }
                .map(\.app)
            await MainActor.run {
                self.logIdentityHealth(apps: apps, context: "refreshHidden")
            }
            return apps
        }

        guard let frame else {
            return items.filter { $0.x < 0 }.map(\.app)
        }

        let apps = items.filter { self.isOffscreen(x: $0.x, in: frame) }.map(\.app)
        await MainActor.run {
            self.logIdentityHealth(apps: apps, context: "refreshHidden")
        }
        return apps
    }

    func refreshAlwaysHiddenMenuBarApps() async -> [RunningApp] {
        let isEnabled = await MainActor.run {
            MenuBarManager.shared.alwaysHiddenSeparatorItem != nil
        }
        guard isEnabled else { return [] }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        let positions = await MainActor.run {
            self.separatorOriginsForClassification()
        }

        if let positions, positions.alwaysHiddenSeparatorX != nil {
            let apps = items
                .filter {
                    self.classifyZone(
                        itemX: $0.x,
                        itemWidth: $0.app.width,
                        separatorX: positions.separatorX,
                        alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                    ) == .alwaysHidden
                }
                .map(\.app)

            await MainActor.run {
                self.logIdentityHealth(apps: apps, context: "refreshAlwaysHidden")
            }
            return apps
        }

        // Fallback: when positions are unavailable (items off-screen at startup),
        // match against persisted pinned IDs to identify always-hidden apps.
        let allApps = items.map(\.app)
        return await MainActor.run {
            self.appsMatchingPinnedIds(from: allApps)
        }
    }

    func refreshVisibleMenuBarApps() async -> [RunningApp] {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        let (positions, frame) = await MainActor.run {
            (self.separatorOriginsForClassification(), self.menuBarScreenFrame())
        }

        // Classify by separator position (works even when temporarily expanded)
        if let positions {
            let apps = items
                .filter {
                    self.classifyZone(
                        itemX: $0.x,
                        itemWidth: $0.app.width,
                        separatorX: positions.separatorX,
                        alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                    ) == .visible
                }
                .map(\.app)
            await MainActor.run {
                self.logIdentityHealth(apps: apps, context: "refreshVisible")
            }
            return apps
        }

        // Not hiding: treat everything as visible.
        _ = frame // keep for potential future debug; intentionally unused.
        let apps = items.map(\.app)
        await MainActor.run {
            self.logIdentityHealth(apps: apps, context: "refreshVisible")
        }
        return apps
    }

    @MainActor
    private func logIdentityHealth(apps: [RunningApp], context: String) {
        SearchIdentityHealthLogger.log(apps: apps, context: context, logger: logger)
    }

    // MARK: - Single-Pass Zone Classification

    @MainActor
    func cachedClassifiedApps() -> SearchClassifiedApps {
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
        return classifyItems(items)
    }

    func refreshClassifiedApps() async -> SearchClassifiedApps {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        return await MainActor.run {
            self.classifyItems(items)
        }
    }

    func refreshKnownClassifiedApps() async -> SearchClassifiedApps {
        let items = await AccessibilityService.shared.refreshKnownMenuBarItemsWithPositions()
        return await MainActor.run {
            self.classifyItems(items)
        }
    }

    @MainActor
    func classifyItemsForVerification(_ items: [AccessibilityService.MenuBarItemPosition]) -> SearchClassifiedApps {
        classifyItems(items, allowEstimatedFallback: false)
    }

    @MainActor
    func classifyItemsForMoveVerification(_ items: [AccessibilityService.MenuBarItemPosition]) -> SearchClassifiedApps {
        classifyItems(items, allowEstimatedFallback: false, promotePinnedAlwaysHidden: false)
    }

    @MainActor
    func classifyAppsForMoveVerification(_ classified: SearchClassifiedApps) -> SearchClassifiedApps {
        classified
    }

    @MainActor
    private func classifyItems(
        _ items: [AccessibilityService.MenuBarItemPosition],
        // Read-only classification may use estimates transiently: the cache is
        // empty after a fresh launch (estimates are never cached). Verification
        // callers pass false explicitly and stay strict.
        allowEstimatedFallback: Bool = true,
        promotePinnedAlwaysHidden: Bool = true
    ) -> SearchClassifiedApps {
        let zonedItems = SearchMenuBarZoneClassifier.zonedMenuBarItems(from: items)
        return SearchMenuBarZoneClassifier.classifyItems(
            items,
            context: SearchMenuBarZoneClassificationContext(
                positions: separatorOriginsForClassification(allowEstimatedFallback: allowEstimatedFallback),
                allowEstimatedFallback: allowEstimatedFallback,
                promotePinnedAlwaysHidden: promotePinnedAlwaysHidden,
                screenFrame: menuBarScreenFrame(),
                hidingState: MenuBarManager.shared.hidingService.state,
                hasAlwaysHiddenSeparator: MenuBarManager.shared.alwaysHiddenSeparatorItem != nil,
                pinnedIds: Set(MenuBarManager.shared.settings.alwaysHiddenPinnedItemIds),
                pinnedApps: appsMatchingPinnedIds(from: zonedItems.map(\.app)),
                logger: logger
            )
        )
    }

    nonisolated static func zonedMenuBarItems(
        from items: [AccessibilityService.MenuBarItemPosition]
    ) -> [AccessibilityService.MenuBarItemPosition] {
        SearchMenuBarZoneClassifier.zonedMenuBarItems(from: items)
    }

    @MainActor
    func activate(
        app: RunningApp,
        isRightClick: Bool = false,
        origin: SearchServiceSupport.ActivationOrigin = .direct
    ) async {
        let browseController = SearchWindowController.shared
        let tracksBrowseActivation = origin == .browsePanel
        if tracksBrowseActivation {
            browseController.noteBrowseActivationStarted()
        }
        defer {
            if tracksBrowseActivation {
                browseController.noteBrowseActivationFinished()
            }
        }

        var diagnostics = SearchServiceSupport.ActivationDiagnostics(
            startedAt: SearchServiceSupport.diagnosticsTimestamp(Date()),
            requestedApp: SearchServiceSupport.diagnosticsApp(app),
            origin: origin.rawValue
        )
        if !activationGate.begin(for: app.uniqueId, nameForLog: app.name) {
            diagnostics.finalOutcome = "skipped (activation already in flight or debounced)"
            lastActivationDiagnostics = diagnostics
            return
        }
        defer { activationGate.finish(for: app.uniqueId) }

        // 1. Show hidden menu bar items first. Always Hidden icons need the
        // stronger showAll path; regular reveal intentionally keeps them blocked.
        let shouldUseFullReveal = await MainActor.run {
            SearchServiceSupport.shouldUseFullRevealForActivation(
                appUniqueId: app.uniqueId,
                bundleId: app.bundleId,
                xPosition: app.xPosition,
                origin: origin,
                pinnedIds: Set(MenuBarManager.shared.settings.alwaysHiddenPinnedItemIds)
            )
        }
        let didReveal: Bool
        if shouldUseFullReveal {
            let requiresAuthFromHidden = await MainActor.run {
                MenuBarManager.shared.settings.requireAuthToShowHiddenIcons &&
                    MenuBarManager.shared.hidingService.state == .hidden
            }
            if requiresAuthFromHidden {
                guard await MenuBarManager.shared.visibilityWorkflow.showHiddenItemsNow(trigger: .search) else {
                    diagnostics.finalOutcome = "aborted (auth failed before always-hidden reveal)"
                    lastActivationDiagnostics = diagnostics
                    return
                }
            }
            await MenuBarManager.shared.hidingService.showAll()
            didReveal = true
        } else {
            didReveal = await MenuBarManager.shared.visibilityWorkflow.showHiddenItemsNow(trigger: .search)
        }
        diagnostics.didReveal = didReveal
        let browseSessionActive = SearchWindowController.shared.isBrowseSessionActive
        let activationPlan = SearchServiceSupport.activationPlan(
            app: app,
            origin: origin,
            isRightClick: isRightClick,
            didReveal: didReveal,
            isBrowseSessionActive: browseSessionActive
        )
        let requireObservableReaction = activationPlan.requireObservableReaction
        let forceFreshTargetResolution = activationPlan.forceFreshTargetResolution
        let allowImmediateFallbackCenter = activationPlan.allowImmediateFallbackCenter
        let requestedPreferHardwareFirst = activationPlan.preferHardwareFirst
        // 2. Wait for menu bar re-layout after reveal.
        // Previously used a fixed 500ms sleep which was insufficient on slower
        // systems with many hidden icons (#69, #77, #102). Now polls until the
        // target icon reaches a stable on-screen position (up to 2s).
        if didReveal {
            try? await Task.sleep(nanoseconds: 80_000_000) // keep this short; polling handles settling
            // Hardware-first visible items can skip the extra settle wait, but
            // hidden/off-screen targets still need time to re-enter the bar.
            if SearchServiceSupport.shouldWaitForRevealSettle(
                preferHardwareFirst: requestedPreferHardwareFirst,
                xPosition: shouldUseFullReveal ? nil : app.xPosition
            ) {
                diagnostics.waitOutcome = await SearchActivationTargetResolver.waitForIconOnScreen(app: app, logger: logger)
            } else {
                diagnostics.waitOutcome = "skipped (preferHardwareFirst)"
            }
        } else {
            diagnostics.waitOutcome = "skipped (didReveal=false)"
        }

        // 3. Resolve latest target identity after reveal.
        // AX child ordering changes when hidden icons become visible — stale
        // cached data causes AXPress to target the wrong (off-screen) element,
        // which returns .success without opening any menu (#69, #77, #102).
        let initialResolution = await SearchActivationTargetResolver.resolveLatestClickTarget(
            for: app,
            forceRefresh: forceFreshTargetResolution,
            logger: logger
        )
        let initialTarget = initialResolution.app
        let initialPlan = SearchServiceSupport.activationPlan(
            app: initialTarget,
            origin: origin,
            isRightClick: isRightClick,
            didReveal: didReveal,
            isBrowseSessionActive: browseSessionActive
        )
        let initialFallbackCenter = SearchActivationTargetResolver.fallbackCenter(
            for: initialTarget,
            fallbackSource: app,
            menuBarScreenFrame: menuBarScreenFrame(),
            logger: logger
        )
        let preferHardwareFirst = initialPlan.preferHardwareFirst
        let initialFallbackCenterOnScreen = SearchServiceSupport.isFallbackCenterOnScreen(initialFallbackCenter)
        let initialFreshHardwareFallback = SearchServiceSupport.shouldAllowFreshHardwareFallbackCenter(
            preferHardwareFirst: preferHardwareFirst,
            requireObservableReaction: requireObservableReaction,
            hasPreciseMenuBarIdentity: initialTarget.hasPreciseMenuBarIdentity,
            fallbackCenterOnScreen: initialFallbackCenterOnScreen
        )
        diagnostics.initialResolution = initialResolution.strategy
        diagnostics.initialTarget = SearchServiceSupport.diagnosticsApp(initialTarget)
        diagnostics.preferHardwareFirst = preferHardwareFirst
        let axService = AccessibilityService.shared
        let initialLikelyNoExtras = axService.likelyLacksExtrasMenuBar(bundleID: initialTarget.bundleId)
        let initialAllowImmediateFallbackCenter = SearchServiceSupport.resolvedAllowImmediateFallbackCenter(
            baseAllowImmediateFallbackCenter: allowImmediateFallbackCenter || initialFreshHardwareFallback,
            likelyNoExtrasMenuBar: initialLikelyNoExtras,
            fallbackCenterOnScreen: initialFallbackCenterOnScreen,
            hasPreciseMenuBarIdentity: initialTarget.hasPreciseMenuBarIdentity
        )
        logger.info(
            "Activation start requested=\(SearchServiceSupport.diagnosticsApp(app), privacy: .private) resolved=\(SearchServiceSupport.diagnosticsApp(initialTarget), privacy: .private) didReveal=\(didReveal, privacy: .public) preferHardwareFirst=\(preferHardwareFirst, privacy: .public)"
        )

        // 4. Perform click off-main-thread to avoid UI stalls when AX APIs block.
        let firstAttemptStart = Date()
        let firstAttempt = await SearchClickAttemptService.perform(
            axService: axService,
            request: SearchClickAttemptRequest(
                target: initialTarget,
                fallbackCenter: initialFallbackCenter,
                isRightClick: isRightClick,
                preferHardwareFirst: preferHardwareFirst,
                allowImmediateFallbackCenter: initialAllowImmediateFallbackCenter,
                requireObservableReaction: requireObservableReaction
            ),
            baseTimeoutMs: clickAttemptTimeoutMs
        )
        var clickSuccess = SearchServiceSupport.acceptsClickResult(
            success: firstAttempt.success,
            verification: firstAttempt.verification,
            requireObservableReaction: requireObservableReaction
        )
        let firstAttemptDuration = Date().timeIntervalSince(firstAttemptStart)
        diagnostics.firstAttempt =
            "success=\(firstAttempt.success) accepted=\(clickSuccess) timedOut=\(firstAttempt.timedOut) durationMs=\(Int(firstAttemptDuration * 1000)) fallbackCenter=\(SearchServiceSupport.diagnosticsPoint(initialFallbackCenter)) allowImmediateFallbackCenter=\(initialAllowImmediateFallbackCenter) requireObservableReaction=\(requireObservableReaction) verification=\(firstAttempt.verification)"
        if firstAttempt.success, !clickSuccess {
            logger.info("Rejecting unverified click success for revealed/browse-session activation")
        }
        if firstAttemptDuration > 1.2 {
            logger.info("Click attempt took \(firstAttemptDuration, privacy: .public)s")
        }
        if firstAttempt.timedOut {
            let timeoutMs = clickAttemptTimeoutMs
            logger.warning("Click attempt timed out after \(timeoutMs, privacy: .public)ms")
        }

        // One retry with a forced refresh if first click failed.
        // Skip retry when first attempt is already slow, to avoid compounding delay.
        if !clickSuccess {
            let likelyNoExtras = AccessibilityService.shared.likelyLacksExtrasMenuBar(bundleID: initialTarget.bundleId)
            if likelyNoExtras {
                logger.info("Click failed and AXExtrasMenuBar is unavailable; skipping forced-refresh retry")
                diagnostics.retryAttempt = "skipped (AXExtrasMenuBar unavailable)"
            } else if firstAttempt.timedOut {
                logger.info("Click failed after timeout; skipping forced-refresh retry")
                diagnostics.retryAttempt = "skipped (first attempt timed out)"
            } else if firstAttemptDuration > 1.5 {
                logger.info("Click failed after slow attempt; skipping forced-refresh retry")
                diagnostics.retryAttempt = "skipped (first attempt already slow)"
            } else {
                logger.info("Click failed, retrying after forced menu bar refresh")
                let refreshedResolution = await SearchActivationTargetResolver.resolveLatestClickTarget(
                    for: app,
                    forceRefresh: true,
                    logger: logger
                )
                let refreshedTarget = refreshedResolution.app
                let refreshedFallbackCenter = SearchActivationTargetResolver.fallbackCenter(
                    for: refreshedTarget,
                    fallbackSource: app,
                    menuBarScreenFrame: menuBarScreenFrame(),
                    logger: logger
                )
                let refreshedPlan = SearchServiceSupport.activationPlan(
                    app: refreshedTarget,
                    origin: origin,
                    isRightClick: isRightClick,
                    didReveal: didReveal,
                    isBrowseSessionActive: browseSessionActive
                )
                let refreshedPreferHardwareFirst = refreshedPlan.preferHardwareFirst
                let refreshedLikelyNoExtras = axService.likelyLacksExtrasMenuBar(bundleID: refreshedTarget.bundleId)
                let refreshedFallbackCenterOnScreen = SearchServiceSupport.isFallbackCenterOnScreen(refreshedFallbackCenter)
                let refreshedFreshHardwareFallback = SearchServiceSupport.shouldAllowFreshHardwareFallbackCenter(
                    preferHardwareFirst: refreshedPreferHardwareFirst,
                    requireObservableReaction: requireObservableReaction,
                    hasPreciseMenuBarIdentity: refreshedTarget.hasPreciseMenuBarIdentity,
                    fallbackCenterOnScreen: refreshedFallbackCenterOnScreen
                )
                let refreshedAllowImmediateFallbackCenter = SearchServiceSupport.resolvedAllowImmediateFallbackCenter(
                    baseAllowImmediateFallbackCenter: refreshedFreshHardwareFallback,
                    likelyNoExtrasMenuBar: refreshedLikelyNoExtras,
                    fallbackCenterOnScreen: refreshedFallbackCenterOnScreen,
                    hasPreciseMenuBarIdentity: refreshedTarget.hasPreciseMenuBarIdentity
                )
                let refreshedAttemptStart = Date()
                let refreshedAttempt = await SearchClickAttemptService.perform(
                    axService: axService,
                    request: SearchClickAttemptRequest(
                        target: refreshedTarget,
                        fallbackCenter: refreshedFallbackCenter,
                        isRightClick: isRightClick,
                        preferHardwareFirst: refreshedPreferHardwareFirst,
                        allowImmediateFallbackCenter: refreshedAllowImmediateFallbackCenter,
                        requireObservableReaction: requireObservableReaction
                    ),
                    baseTimeoutMs: clickAttemptTimeoutMs
                )
                clickSuccess = SearchServiceSupport.acceptsClickResult(
                    success: refreshedAttempt.success,
                    verification: refreshedAttempt.verification,
                    requireObservableReaction: requireObservableReaction
                )
                let refreshedAttemptDuration = Date().timeIntervalSince(refreshedAttemptStart)
                diagnostics.retryAttempt =
                    "success=\(refreshedAttempt.success) accepted=\(clickSuccess) timedOut=\(refreshedAttempt.timedOut) durationMs=\(Int(refreshedAttemptDuration * 1000)) resolution=\(refreshedResolution.strategy) target=\(SearchServiceSupport.diagnosticsApp(refreshedTarget)) fallbackCenter=\(SearchServiceSupport.diagnosticsPoint(refreshedFallbackCenter)) allowImmediateFallbackCenter=\(refreshedAllowImmediateFallbackCenter) requireObservableReaction=\(requireObservableReaction) verification=\(refreshedAttempt.verification)"
                if refreshedAttempt.success, !clickSuccess {
                    logger.info("Rejecting unverified retry click success for revealed/browse-session activation")
                }
            }
        } else {
            diagnostics.retryAttempt = "not-needed"
        }

        if !clickSuccess {
            if activationPlan.allowWorkspaceActivationFallback {
                // Fallback: Just activate the app normally (user can then click the now-visible icon)
                let workspace = NSWorkspace.shared
                if let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == app.bundleId }) {
                    if NSApp.isActive {
                        NSApp.yieldActivation(to: runningApp)
                    }
                    _ = runningApp.activate(options: [])
                }
                diagnostics.finalOutcome = "workspace activation fallback"
            } else {
                logger.info("Click failed for browse-panel right-click; keeping panel active")
                diagnostics.finalOutcome = "click failed (kept browse panel active)"
            }
        } else {
            diagnostics.finalOutcome = "click succeeded"
        }

        // 4. ALWAYS auto-hide after Find Icon use (seamless experience)
        // Give user time to interact with the opened menu before hiding.
        // Configurable delay (default 15s) allows browsing through menus without feeling rushed.
        // Note: When icons hide, any open menu from that icon closes (macOS behavior).
        if didReveal {
            let delay = MenuBarManager.shared.settings.findIconRehideDelay
            MenuBarManager.shared.visibilityWorkflow.scheduleRehideFromSearch(after: delay)
        }

        lastActivationDiagnostics = diagnostics
        logger.info(
            "Activation finished outcome=\(diagnostics.finalOutcome, privacy: .public) resolution=\(diagnostics.initialResolution, privacy: .public) wait=\(diagnostics.waitOutcome, privacy: .public)"
        )
    }
}
