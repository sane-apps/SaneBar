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

    /// Activate an app, revealing hidden items and attempting virtual click
    @MainActor
    func activate(app: RunningApp, isRightClick: Bool) async
}

// MARK: - SearchService

final class SearchService: SearchServiceProtocol {
    static let shared = SearchService()

    private enum VisibilityZone {
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

        guard MenuBarManager.shared.settings.alwaysHiddenSectionEnabled,
              MenuBarManager.shared.alwaysHiddenSeparatorItem != nil
        else {
            return (separatorX, nil)
        }

        let alwaysHiddenSeparatorX = MenuBarManager.shared.getAlwaysHiddenSeparatorOriginX()
        if let alwaysHiddenSeparatorX, alwaysHiddenSeparatorX >= separatorX {
            logger.warning("Always-hidden separator is not left of main separator; ignoring always-hidden zone")
            return (separatorX, nil)
        }

        // If exact position unavailable (separator is in blocking mode at 10,000),
        // use the screen left edge as the boundary. During expanded state,
        // always-hidden items are pushed off-screen (x < 0) by the blocking separator,
        // so items left of screen edge = always-hidden, on-screen left of separator = hidden.
        if alwaysHiddenSeparatorX == nil {
            let screenMinX = menuBarScreenFrame()?.minX ?? 0
            return (separatorX, screenMinX)
        }

        return (separatorX, alwaysHiddenSeparatorX)
    }

    private func isOffscreen(x: CGFloat, in screenFrame: CGRect) -> Bool {
        // Small margin to avoid flapping due to tiny coordinate jitter.
        let margin: CGFloat = 6
        return x < (screenFrame.minX - margin) || x > (screenFrame.maxX + margin)
    }

    private func classifyZone(
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
        guard MenuBarManager.shared.settings.alwaysHiddenSectionEnabled else { return [] }
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

        return []
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

        // Fallback: when separator unavailable, treat all items as visible
        logger.debug("cachedVisible: no separator, returning all \(items.count, privacy: .public) items")
        return items.map(\.app)
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
            MenuBarManager.shared.settings.alwaysHiddenSectionEnabled &&
                MenuBarManager.shared.alwaysHiddenSeparatorItem != nil
        }
        guard isEnabled else { return [] }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        let positions = await MainActor.run {
            self.separatorOriginsForClassification()
        }

        guard let positions, positions.alwaysHiddenSeparatorX != nil else { return [] }

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

    @MainActor
    func activate(app: RunningApp, isRightClick: Bool = false) async {
        // 1. Show hidden menu bar items first
        let didReveal = await MenuBarManager.shared.showHiddenItemsNow(trigger: .search)

        // 2. Wait for menu bar animation to complete
        // When icons move from hidden (left of separator) to visible, macOS needs time
        if didReveal {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        // 3. Perform Virtual Click on the menu bar item
        let clickSuccess = AccessibilityService.shared.clickMenuBarItem(
            bundleID: app.bundleId,
            menuExtraId: app.menuExtraIdentifier,
            statusItemIndex: app.statusItemIndex,
            isRightClick: isRightClick
        )

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
}
