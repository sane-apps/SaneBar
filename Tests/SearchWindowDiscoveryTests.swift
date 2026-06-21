import AppKit
@testable import SaneBar
import SwiftUI
import Testing


struct SearchWindowDiscoveryTests {
    @Test("Merged discoverable apps append owner-only fallbacks without duplicating precise matches")
    @MainActor
    func mergedDiscoverableAppsPrefersPreciseItems() {
        let positioned = [
            RunningApp(
                id: "com.example.precise",
                name: "Precise",
                icon: nil,
                menuExtraIdentifier: "com.example.precise.status",
                xPosition: 400,
                width: 20
            ),
        ]
        let owners = [
            RunningApp(id: "com.example.precise", name: "Precise", icon: nil),
            RunningApp(id: "at.obdev.littlesnitch.networkmonitor", name: "Little Snitch", icon: nil),
        ]

        let merged = SearchServiceSupport.mergedDiscoverableApps(positioned: positioned, owners: owners)

        #expect(merged.count == 2)
        #expect(merged[0].uniqueId == "com.example.precise::axid:com.example.precise.status")
        #expect(merged[1].uniqueId == "at.obdev.littlesnitch.networkmonitor")
    }

    @Test("Merged discoverable apps collapse Little Snitch helper-family duplicates without hiding the live item")
    @MainActor
    func mergedDiscoverableAppsCollapseLittleSnitchFamilyDuplicates() {
        let positioned = [
            RunningApp(
                id: "at.obdev.littlesnitch.networkmonitor",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch",
                xPosition: 320,
                width: 22
            ),
            RunningApp(
                id: "at.obdev.littlesnitch.agent",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.agent.menuextra.little-snitch",
                xPosition: -3400,
                width: 22
            ),
        ]

        let merged = SearchServiceSupport.mergedDiscoverableApps(positioned: positioned, owners: [])

        #expect(merged.count == 1)
        #expect(merged[0].bundleId == "at.obdev.littlesnitch.networkmonitor")
    }

    @Test("Pinned hidden apps promote to always-hidden classification")
    func pinnedHiddenAppsPromoteToAlwaysHidden() {
        let weather = RunningApp(
            id: "com.apple.weather.menu",
            name: "WeatherMenu",
            icon: nil,
            menuExtraIdentifier: "com.apple.weather.menu",
            xPosition: 865,
            width: 70.5
        )

        let promoted = SearchService.promotePinnedHiddenAppsToAlwaysHidden(
            hidden: [weather],
            alwaysHidden: [],
            pinnedIds: [weather.uniqueId]
        )

        #expect(promoted.hidden.isEmpty)
        #expect(promoted.alwaysHidden.map(\.uniqueId) == [weather.uniqueId])
    }

    @Test("Pinned hidden promotion honors bundle-level fallback for precise extras")
    func pinnedHiddenAppsPromoteViaBundleFallback() {
        let helperHosted = RunningApp(
            id: "com.example.helper",
            name: "HelperHosted",
            icon: nil,
            menuExtraIdentifier: "com.example.status.item",
            xPosition: 900,
            width: 32
        )

        let promoted = SearchService.promotePinnedHiddenAppsToAlwaysHidden(
            hidden: [helperHosted],
            alwaysHidden: [],
            pinnedIds: [helperHosted.bundleId]
        )

        #expect(promoted.hidden.isEmpty)
        #expect(promoted.alwaysHidden.map(\.uniqueId) == [helperHosted.uniqueId])
    }

    @Test("Move verification classification does not collapse always-hidden into hidden")
    @MainActor
    func moveVerificationClassificationIgnoresPinnedAlwaysHiddenState() {
        let optimistic = RunningApp(
            id: "com.example.optimistic",
            name: "Optimistic",
            icon: nil,
            menuExtraIdentifier: "com.example.optimistic.status",
            xPosition: 900,
            width: 24
        )
        let alwaysHidden = RunningApp(
            id: "com.example.always-hidden",
            name: "Pinned",
            icon: nil,
            menuExtraIdentifier: "com.example.always-hidden.status",
            xPosition: 860,
            width: 24
        )
        let classified = SearchClassifiedApps(
            visible: [],
            hidden: [optimistic],
            alwaysHidden: [alwaysHidden]
        )

        let physical = SearchService.shared.classifyAppsForMoveVerification(classified)

        #expect(physical.hidden.map(\.uniqueId) == [optimistic.uniqueId])
        #expect(physical.alwaysHidden.map(\.uniqueId) == [alwaysHidden.uniqueId])
    }

    @Test("Hidden-state classification ignores always-hidden separator geometry")
    func hiddenStateClassificationUsesPinsInsteadOfAlwaysHiddenGeometry() {
        #expect(
            SearchService.alwaysHiddenSeparatorForClassification(
                hidingState: .hidden,
                alwaysHiddenSeparatorX: 1329
            ) == nil
        )
        #expect(
            SearchService.alwaysHiddenSeparatorForClassification(
                hidingState: .expanded,
                alwaysHiddenSeparatorX: 1329
            ) == 1329
        )
    }

    @Test("Zoned menu bar views keep fallback-only entries but drop coarse duplicates")
    func zonedMenuBarItemsPreferPreciseIdentityPerBundle() {
        let preciseAX = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "com.example.precise",
                name: "Precise",
                icon: nil,
                menuExtraIdentifier: "com.example.precise.status",
                xPosition: 100,
                width: 20
            ),
            x: 100,
            width: 20
        )
        let preciseIndexed = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "com.example.indexed",
                name: "Indexed",
                icon: nil,
                statusItemIndex: 0,
                xPosition: 130,
                width: 22
            ),
            x: 130,
            width: 22
        )
        let coarse = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "com.example.precise",
                name: "CoarseDuplicate",
                icon: nil,
                xPosition: 160,
                width: 24
            ),
            x: 160,
            width: 24
        )
        let coarseOnly = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "com.example.fallback",
                name: "FallbackOnly",
                icon: nil,
                xPosition: 190,
                width: 24
            ),
            x: 190,
            width: 24
        )

        let filtered = SearchService.zonedMenuBarItems(from: [preciseAX, preciseIndexed, coarse, coarseOnly])

        #expect(filtered.map(\.app.uniqueId) == [
            preciseAX.app.uniqueId,
            preciseIndexed.app.uniqueId,
            coarseOnly.app.uniqueId,
        ])
        #expect(filtered.contains { $0.app.uniqueId == coarseOnly.app.uniqueId && !$0.app.hasPreciseMenuBarIdentity })
    }

    @Test("Zoned menu bar views exclude compatibility-limited overlay apps")
    @MainActor
    func zonedMenuBarItemsExcludeCompatibilityLimitedOverlayApps() {
        let boringNotch = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "theboringteam.boringnotch",
                name: "TheBoringNotch",
                icon: nil,
                statusItemIndex: 0,
                xPosition: -3530,
                width: 33
            ),
            x: -3530,
            width: 33
        )

        let filtered = SearchService.zonedMenuBarItems(from: [boringNotch])
        let discoverable = SearchServiceSupport.mergedDiscoverableApps(
            positioned: [],
            owners: [boringNotch.app]
        )

        #expect(filtered.isEmpty)
        #expect(discoverable.map(\.uniqueId) == [boringNotch.app.uniqueId])
    }

    @Test("Zoned menu bar views collapse Little Snitch helper-family duplicates without hiding the visible item")
    func zonedMenuBarItemsCollapseLittleSnitchFamilyDuplicates() {
        let visibleNetworkMonitor = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "at.obdev.littlesnitch.networkmonitor",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch",
                xPosition: 1180,
                width: 22
            ),
            x: 1180,
            width: 22
        )
        let hiddenAgent = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "at.obdev.littlesnitch.agent",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.agent.menuextra.little-snitch",
                xPosition: -3520,
                width: 22
            ),
            x: -3520,
            width: 22
        )

        let filtered = SearchService.zonedMenuBarItems(from: [visibleNetworkMonitor, hiddenAgent])

        #expect(filtered.count == 1)
        #expect(filtered[0].app.bundleId == "at.obdev.littlesnitch.networkmonitor")
    }

    @Test("Helper-family fallback resolution prefers current Little Snitch helper")
    func helperHostedAliasResolutionPrefersCurrentLittleSnitchHelper() {
        let original = RunningApp(
            id: "at.obdev.littlesnitch.networkmonitor",
            name: "Little Snitch",
            icon: nil,
            menuExtraIdentifier: "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch",
            xPosition: 1180,
            width: 22
        )
        let candidates = [
            RunningApp(
                id: "at.obdev.littlesnitch.agent",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.agent.menuextra.little-snitch",
                xPosition: -3520,
                width: 22
            ),
            RunningApp(
                id: "com.obdev.LittleSnitchUIAgent",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "com.obdev.LittleSnitchUIAgent-Item-0",
                xPosition: -3440,
                width: 22
            ),
        ]

        let resolved = SearchServiceSupport.bestHelperHostedAliasResolutionCandidate(
            for: original,
            candidates: candidates
        )

        #expect(resolved?.bundleId == "at.obdev.littlesnitch.agent")
    }

    @Test("Collapsed helper-family duplicates still prefer the current helper when all candidates are hidden")
    @MainActor
    func mergedDiscoverableAppsCollapseLittleSnitchFamilyHiddenDuplicates() {
        let positioned = [
            RunningApp(
                id: "at.obdev.littlesnitch.networkmonitor",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch",
                xPosition: -3440,
                width: 22
            ),
            RunningApp(
                id: "at.obdev.littlesnitch.agent",
                name: "Little Snitch",
                icon: nil,
                menuExtraIdentifier: "at.obdev.littlesnitch.agent.menuextra.little-snitch",
                xPosition: -3520,
                width: 22
            ),
        ]

        let merged = SearchServiceSupport.mergedDiscoverableApps(positioned: positioned, owners: [])

        #expect(merged.count == 1)
        #expect(merged[0].bundleId == "at.obdev.littlesnitch.agent")
    }

    @Test("SaneBar diagnostics collector includes search and panel snapshots")
    func diagnosticsCollectorIncludesRuntimeSnapshots() throws {
        let diagnosticsFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Core/Services/DiagnosticsService.swift")
        let source = try String(contentsOf: diagnosticsFile, encoding: .utf8)

        #expect(source.contains("AccessibilityService.shared.diagnosticsSnapshot()"))
        #expect(source.contains("SearchService.shared.diagnosticsSnapshot()"))
        #expect(source.contains("SearchWindowController.shared.diagnosticsSnapshot()"))
        #expect(source.contains("prefsForensics:"))
        #expect(source.contains("StatusBarController.autosaveVersion"))
        #expect(source.contains("StatusBarPositionStore.displayPositionBackupKey"))
        #expect(source.contains("SaneBar_CalibratedScreenWidth"))
        #expect(source.contains("statusItemScreenWidth"))
        #expect(source.contains("pointerScreenWidth"))
    }

    @Test("All mode discovery uses the broader menu bar app list")
    func allModeDiscoveryUsesMergedMenuBarApps() throws {
        let viewFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let source = try String(contentsOf: viewFile, encoding: .utf8)

        #expect(source.contains("menuBarApps = service.cachedMenuBarApps()"))
        #expect(source.contains("classified = nil"))
        #expect(source.contains("allModeApps = await service.refreshMenuBarApps()"))
        #expect(source.contains("menuBarApps = allModeApps"))
        #expect(!source.contains("await service.refreshClassifiedApps()"))
        #expect(source.contains("AccessibilityService.shared.invalidateMenuBarItemPositionsCache()"))
        #expect(!source.contains("AccessibilityService.shared.invalidateMenuBarItemCache()"))
    }

    @Test("All mode refresh uses known-owner positions before the owner merge")
    func allModeRefreshUsesKnownOwnerPositions() throws {
        let serviceFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: serviceFile, encoding: .utf8)

        #expect(source.contains("let items = await AccessibilityService.shared.refreshKnownMenuBarItemsWithPositions()"))
        #expect(source.contains("let cachedOwners = await MainActor.run"))
        #expect(source.contains("AccessibilityService.shared.cachedMenuBarItemOwners()"))
        #expect(source.contains("let owners = if cachedOwners.isEmpty"))
        #expect(source.contains("await AccessibilityService.shared.refreshMenuBarItemOwners()"))
    }

    // MARK: - Icon Groups Tests

}
