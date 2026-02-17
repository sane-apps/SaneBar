import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "SearchService")

// MARK: - SearchServiceProtocol

/// @mockable
protocol SearchServiceProtocol: Sendable {
    /// Fetch all running apps suitable for menu bar interaction
    func getRunningApps() async -> [RunningApp]

    /// Fetch apps that currently own a menu bar icon (requires Accessibility permission)
    func getMenuBarApps() async -> [RunningApp]

    /// Fetch ONLY the menu bar apps that are currently HIDDEN by SaneBar
    func getHiddenMenuBarApps() async -> [RunningApp]

    /// Fetch ONLY the menu bar apps that are always hidden (if enabled)
    func getAlwaysHiddenMenuBarApps() async -> [RunningApp]

    /// Cached menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedMenuBarApps() -> [RunningApp]

    /// Cached hidden menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedHiddenMenuBarApps() -> [RunningApp]

    /// Cached always hidden menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedAlwaysHiddenMenuBarApps() -> [RunningApp]

    /// Cached shown (visible) menu bar apps (may be stale). Returns immediately.
    @MainActor
    func cachedVisibleMenuBarApps() -> [RunningApp]

    /// Refresh menu bar apps in the background (may take time).
    func refreshMenuBarApps() async -> [RunningApp]

    /// Refresh hidden menu bar apps in the background (may take time).
    func refreshHiddenMenuBarApps() async -> [RunningApp]

    /// Refresh always hidden menu bar apps in the background (may take time).
    func refreshAlwaysHiddenMenuBarApps() async -> [RunningApp]

    /// Refresh shown (visible) menu bar apps in the background (may take time).
    func refreshVisibleMenuBarApps() async -> [RunningApp]

    /// Classify all cached menu bar items into zones in a single pass.
    /// Guarantees each item appears in exactly one zone.
    @MainActor
    func cachedClassifiedApps() -> (visible: [RunningApp], hidden: [RunningApp], alwaysHidden: [RunningApp])

    /// Refresh and classify all menu bar items into zones in a single pass.
    func refreshClassifiedApps() async -> (visible: [RunningApp], hidden: [RunningApp], alwaysHidden: [RunningApp])

    /// Activate an app, revealing hidden items and attempting virtual click
    @MainActor
    func activate(app: RunningApp, isRightClick: Bool) async
}

// MARK: - SearchService

final class SearchService: SearchServiceProtocol {
    static let shared = SearchService()

    enum VisibilityZone: Equatable, Hashable {
        case visible
        case hidden
        case alwaysHidden
    }

    @MainActor
    private func menuBarScreenFrame() -> CGRect? {
        // Prefer the actual screen hosting our status items.
        if let screen = MenuBarManager.shared.mainStatusItem?.button?.window?.screen {
            return screen.frame
        }
        return NSScreen.main?.frame
    }

    @MainActor
    private func separatorOriginXForClassification() -> CGFloat? {
        MenuBarManager.shared.getSeparatorOriginX()
    }

    @MainActor
    private func separatorOriginsForClassification() -> (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?)? {
        guard let separatorX = separatorOriginXForClassification() else { return nil }

        guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else {
            return (separatorX, nil)
        }

        let alwaysHiddenSeparatorX = MenuBarManager.shared.getAlwaysHiddenSeparatorOriginX()
        if let alwaysHiddenSeparatorX, alwaysHiddenSeparatorX >= separatorX {
            logger.warning("Always-hidden separator is not left of main separator; ignoring always-hidden zone")
            return (separatorX, nil)
        }

        // If AH position is unavailable (blocking mode, never cached), return nil for AH.
        // classifyItems will use pinned IDs as a post-pass instead of a fake boundary.
        return (separatorX, alwaysHiddenSeparatorX)
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

    private func isOffscreen(x: CGFloat, in screenFrame: CGRect) -> Bool {
        // Small margin to avoid flapping due to tiny coordinate jitter.
        let margin: CGFloat = 6
        return x < (screenFrame.minX - margin) || x > (screenFrame.maxX + margin)
    }

    /// Classify an item's zone based on its position relative to separators.
    /// Internal for testability — the core zone classification logic.
    func classifyZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        separatorX: CGFloat,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> VisibilityZone {
        let width = max(1, itemWidth ?? 22)
        let midX = itemX + (width / 2)
        let margin: CGFloat = 6

        if let alwaysHiddenSeparatorX {
            if midX < (alwaysHiddenSeparatorX - margin) {
                return .alwaysHidden
            }
            if midX < (separatorX - margin) {
                return .hidden
            }
            return .visible
        }

        return midX < (separatorX - margin) ? .hidden : .visible
    }

    func getRunningApps() async -> [RunningApp] {
        // Run on main actor because accessing NSWorkspace.runningApplications is main-thread bound
        await MainActor.run {
            let workspace = NSWorkspace.shared
            return workspace.runningApplications
                .filter { app in
                    // Include regular apps and background apps that might have status items
                    app.activationPolicy == .regular ||
                        app.activationPolicy == .accessory
                }
                .filter { $0.bundleIdentifier != nil }
                .map { RunningApp(app: $0) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
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
        // Use position-aware cache for 'All' so we can sort spatially
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
        return items.map(\.app)
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

        // Fallback: separator unavailable — can't classify zones, return empty.
        // The async refresh will populate correctly once positions are available.
        logger.debug("cachedVisible: no separator, returning empty (will refresh async)")
        return []
    }

    func refreshMenuBarApps() async -> [RunningApp] {
        // Refresh positions to ensure 'All' is sorted spatially
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        return items.map(\.app)
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
        guard !apps.isEmpty else {
            logger.debug("Find Icon list empty (\(context, privacy: .public))")
            return
        }

        var countsById: [String: Int] = [:]
        countsById.reserveCapacity(apps.count)
        for app in apps {
            countsById[app.id, default: 0] += 1
        }

        let uniqueCount = countsById.count
        let duplicateIds = countsById.filter { $0.value > 1 }

        logger.debug("Find Icon \(context, privacy: .public): count=\(apps.count, privacy: .public) uniqueIds=\(uniqueCount, privacy: .public) dupIds=\(duplicateIds.count, privacy: .public)")

        if !duplicateIds.isEmpty {
            let sample = duplicateIds.prefix(10).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            logger.error("Find Icon \(context, privacy: .public): DUPLICATE ids detected: \(sample, privacy: .private)")
        }

        // Helpful sample of what the UI will render.
        for app in apps.prefix(12) {
            logger.debug("Find Icon sample (\(context, privacy: .public)): id=\(app.id, privacy: .private) bundleId=\(app.bundleId, privacy: .private) menuExtraId=\(app.menuExtraIdentifier ?? "nil", privacy: .private) name=\(app.name, privacy: .private)")
        }
    }

    // MARK: - Single-Pass Zone Classification

    @MainActor
    func cachedClassifiedApps() -> (visible: [RunningApp], hidden: [RunningApp], alwaysHidden: [RunningApp]) {
        let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
        return classifyItems(items)
    }

    func refreshClassifiedApps() async -> (visible: [RunningApp], hidden: [RunningApp], alwaysHidden: [RunningApp]) {
        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        return await MainActor.run {
            self.classifyItems(items)
        }
    }

    /// Single-pass classification for all items.
    ///
    /// Strategy:
    /// 1. If main separator position is known → use it for visible/hidden split
    /// 2. If AH separator position is also known → use it for hidden/always-hidden split
    /// 3. If AH position is unknown but AH separator exists → use pinned IDs for always-hidden
    /// 4. If main separator is unknown → use screen-based offscreen detection
    @MainActor
    private func classifyItems(_ items: [AccessibilityService.MenuBarItemPosition]) -> (visible: [RunningApp], hidden: [RunningApp], alwaysHidden: [RunningApp]) {
        let positions = separatorOriginsForClassification()

        // --- Main separator available: position-based classification ---
        if let positions {
            var visible: [RunningApp] = []
            var hidden: [RunningApp] = []
            var alwaysHidden: [RunningApp] = []

            for item in items {
                let zone = classifyZone(
                    itemX: item.x,
                    itemWidth: item.app.width,
                    separatorX: positions.separatorX,
                    alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
                )
                switch zone {
                case .visible: visible.append(item.app)
                case .hidden: hidden.append(item.app)
                case .alwaysHidden: alwaysHidden.append(item.app)
                }
            }

            // Post-pass: if AH separator exists but its position was unavailable,
            // classifyZone used two-zone split (no AH zone). Use pinned IDs to
            // pull always-hidden items out of the hidden bucket.
            if positions.alwaysHiddenSeparatorX == nil,
               MenuBarManager.shared.alwaysHiddenSeparatorItem != nil {
                let pinnedIds = Set(MenuBarManager.shared.settings.alwaysHiddenPinnedItemIds)
                if !pinnedIds.isEmpty {
                    let isPinned: (RunningApp) -> Bool = { app in
                        pinnedIds.contains(app.uniqueId) || pinnedIds.contains(app.bundleId)
                    }
                    alwaysHidden = hidden.filter(isPinned)
                    hidden = hidden.filter { !isPinned($0) }
                    logger.debug("classifyItems: post-pass moved \(alwaysHidden.count, privacy: .public) pinned apps to alwaysHidden")
                }
            }

            logger.debug("classifyItems: visible=\(visible.count, privacy: .public) hidden=\(hidden.count, privacy: .public) alwaysHidden=\(alwaysHidden.count, privacy: .public)")
            return (visible, hidden, alwaysHidden)
        }

        // --- No main separator: screen-based fallback ---
        logger.debug("classifyItems: no separator, using screen-based fallback for \(items.count, privacy: .public) items")
        let allApps = items.map(\.app)

        // Always-hidden: match against persisted pinned IDs
        let alwaysHidden = appsMatchingPinnedIds(from: allApps)
        let alwaysHiddenIds = Set(alwaysHidden.map(\.id))

        // Hidden: items off-screen (excluding always-hidden)
        let frame = menuBarScreenFrame()
        let hidden: [RunningApp] = if let frame {
            items
                .filter { isOffscreen(x: $0.x, in: frame) && !alwaysHiddenIds.contains($0.app.id) }
                .map(\.app)
        } else {
            items
                .filter { $0.x < 0 && !alwaysHiddenIds.contains($0.app.id) }
                .map(\.app)
        }

        // Visible: everything else
        let hiddenIds = Set(hidden.map(\.id))
        let visible = allApps.filter { !alwaysHiddenIds.contains($0.id) && !hiddenIds.contains($0.id) }

        logger.debug("classifyItems(fallback): visible=\(visible.count, privacy: .public) hidden=\(hidden.count, privacy: .public) alwaysHidden=\(alwaysHidden.count, privacy: .public)")
        return (visible, hidden, alwaysHidden)
    }

    @MainActor
    func activate(app: RunningApp, isRightClick: Bool = false) async {
        // 1. Show hidden menu bar items first
        let didReveal = await MenuBarManager.shared.showHiddenItemsNow(trigger: .search)

        // 2. Wait for menu bar animation to complete
        // When icons move from hidden (left of separator) to visible, macOS needs time
        if didReveal {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        // 3. Resolve latest target identity after reveal.
        // AX child ordering can change when hidden icons become visible.
        let initialTarget = await resolveLatestClickTarget(for: app, forceRefresh: false)

        // 4. Perform Virtual Click on the menu bar item
        var clickSuccess = AccessibilityService.shared.clickMenuBarItem(
            bundleID: initialTarget.bundleId,
            menuExtraId: initialTarget.menuExtraIdentifier,
            statusItemIndex: initialTarget.statusItemIndex,
            isRightClick: isRightClick
        )

        // One retry with a forced refresh if first click failed.
        if !clickSuccess {
            logger.info("Click failed, retrying after forced menu bar refresh")
            let refreshedTarget = await resolveLatestClickTarget(for: app, forceRefresh: true)
            clickSuccess = AccessibilityService.shared.clickMenuBarItem(
                bundleID: refreshedTarget.bundleId,
                menuExtraId: refreshedTarget.menuExtraIdentifier,
                statusItemIndex: refreshedTarget.statusItemIndex,
                isRightClick: isRightClick
            )
        }

        if !clickSuccess {
            // Fallback: Just activate the app normally (user can then click the now-visible icon)
            let workspace = NSWorkspace.shared
            if let runningApp = workspace.runningApplications.first(where: { $0.bundleIdentifier == app.bundleId }) {
                runningApp.activate()
            }
        }

        // 4. ALWAYS auto-hide after Find Icon use (seamless experience)
        // Give user time to interact with the opened menu before hiding.
        // Configurable delay (default 15s) allows browsing through menus without feeling rushed.
        // Note: When icons hide, any open menu from that icon closes (macOS behavior).
        if didReveal {
            let delay = MenuBarManager.shared.settings.findIconRehideDelay
            MenuBarManager.shared.scheduleRehideFromSearch(after: delay)
        }
    }

    @MainActor
    private func resolveLatestClickTarget(for original: RunningApp, forceRefresh: Bool) async -> RunningApp {
        let items = if forceRefresh {
            await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        } else {
            await AccessibilityService.shared.listMenuBarItemsWithPositions()
        }

        // First choice: stable unique identity.
        if let exact = items.first(where: { $0.app.uniqueId == original.uniqueId })?.app {
            return exact
        }

        // Next: bundle + menuExtra identifier.
        if let menuExtraIdentifier = original.menuExtraIdentifier,
           let match = items.first(where: { $0.app.bundleId == original.bundleId && $0.app.menuExtraIdentifier == menuExtraIdentifier })?.app {
            return match
        }

        // Next: bundle + status item index.
        if let statusItemIndex = original.statusItemIndex,
           let match = items.first(where: { $0.app.bundleId == original.bundleId && $0.app.statusItemIndex == statusItemIndex })?.app {
            return match
        }

        // Last fallback: closest position within the same bundle.
        let sameBundle = items.filter { $0.app.bundleId == original.bundleId }.map(\.app)
        if let originalX = original.xPosition,
           let closest = sameBundle.min(by: { abs(($0.xPosition ?? originalX) - originalX) < abs(($1.xPosition ?? originalX) - originalX) }) {
            return closest
        }
        return sameBundle.first ?? original
    }
}
