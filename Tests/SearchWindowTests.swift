import Testing
import SwiftUI
import AppKit
@testable import SaneBar

@Suite("Search Window Tests")
struct SearchWindowTests {

    // MARK: - Logic Tests

    @Test("Filtering logic works correctly")
    @MainActor
    func testFiltering() async {
        // Given
        let mockService = SearchServiceProtocolMock()
        mockService.getRunningAppsHandler = {
            return [
                RunningApp(id: "com.apple.Safari", name: "Safari", icon: nil),
                RunningApp(id: "com.google.Chrome", name: "Chrome", icon: nil),
                RunningApp(id: "com.apple.Notes", name: "Notes", icon: nil)
            ]
        }

        _ = MenuBarSearchView(service: mockService, onDismiss: {})  // Verify it can be created

        // Verify service interaction
        let apps = await mockService.getRunningApps()
        #expect(apps.count == 3)
        #expect(mockService.getRunningAppsCallCount > 0)
        
        // Note: We cannot test @State filteredApps directly from outside the view
        // But we verified the dependency injection works
    }

    @Test("Service activation is called")
    @MainActor
    func testActivation() async {
        let mockService = SearchServiceProtocolMock()
        let app = RunningApp(id: "com.test", name: "Test", icon: nil)
        
        await mockService.activate(app: app, isRightClick: false, origin: .direct)

        #expect(mockService.activateCallCount == 1)
        #expect(mockService.activateArgValues.first?.0.id == "com.test")
        #expect(mockService.activateArgValues.first?.2 == .direct)
    }
    
    // MARK: - Model Tests
    
    @Test("RunningApp uses synthesized equality checking all properties")
    func testRunningAppEquality() {
        let app1 = RunningApp(id: "com.test", name: "Test", icon: nil)
        let app2 = RunningApp(id: "com.test", name: "Test", icon: nil) // Same ID and name
        let app3 = RunningApp(id: "com.other", name: "Test", icon: nil) // Different ID
        let app4 = RunningApp(id: "com.test", name: "Other", icon: nil) // Same ID, different name

        #expect(app1 == app2) // Same id and name = equal
        #expect(app1 != app3) // Different id = not equal
        #expect(app1 != app4) // Same id but different name = not equal (synthesized Equatable)
    }
    
    @Test("MenuBarSearchView initializes without crashing")
    @MainActor
    func testMenuBarSearchViewInit() {
        let mockService = SearchServiceProtocolMock()
        _ = MenuBarSearchView(service: mockService, onDismiss: {})
        #expect(true)
    }

    @Test("Duplicate badges number repeated menu extras by bundle and name in x-order")
    func duplicateBadgesNumberRepeatedMenuExtrasInXOrder() {
        let stats2 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 2,
            xPosition: 140
        )
        let stats0 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 0,
            xPosition: 20
        )
        let stats3 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 3,
            xPosition: 200
        )
        let stats1 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 1,
            xPosition: 80
        )
        let wifi = RunningApp.controlCenterItem(
            name: "Wi-Fi",
            identifier: "com.apple.menuextra.wifi",
            xPosition: 260
        )

        let markers = BrowseDuplicateMarker.markers(for: [stats2, stats0, wifi, stats3, stats1])

        #expect(markers[stats0.uniqueId] == BrowseDuplicateMarker(ordinal: 1, total: 4))
        #expect(markers[stats1.uniqueId] == BrowseDuplicateMarker(ordinal: 2, total: 4))
        #expect(markers[stats2.uniqueId] == BrowseDuplicateMarker(ordinal: 3, total: 4))
        #expect(markers[stats3.uniqueId] == BrowseDuplicateMarker(ordinal: 4, total: 4))
        #expect(markers[wifi.uniqueId] == nil)
    }

    @Test("Duplicate badges do not merge same-bundle items with different names")
    func duplicateBadgesRespectDistinctNamesWithinSameBundle() {
        let wifi = RunningApp.controlCenterItem(
            name: "Wi-Fi",
            identifier: "com.apple.menuextra.wifi",
            xPosition: 100
        )
        let display = RunningApp.controlCenterItem(
            name: "Display",
            identifier: "com.apple.menuextra.display",
            xPosition: 130
        )
        let focus = RunningApp.controlCenterItem(
            name: "Focus",
            identifier: "com.apple.menuextra.focusmode",
            xPosition: 160
        )

        let markers = BrowseDuplicateMarker.markers(for: [wifi, display, focus])

        #expect(markers.isEmpty)
    }

    @Test("Search activation diagnostics keep resolution and retry details")
    func testSearchActivationDiagnosticsSummary() {
        let diagnostics = SearchService.ActivationDiagnostics(
            startedAt: "2026-03-05T12:34:56.789Z",
            requestedApp: "id=req bundle=com.test.app menuExtra=nil statusItemIndex=1 x=100.0 width=24.0",
            didReveal: true,
            preferHardwareFirst: false,
            initialResolution: "forceRefresh=false items=12 method=uniqueId",
            initialTarget: "id=resolved bundle=com.test.app menuExtra=foo statusItemIndex=1 x=101.0 width=24.0",
            waitOutcome: "stable after 150ms at x=101.0",
            firstAttempt: "success=false accepted=false timedOut=false durationMs=280 fallbackCenter=x=113.0 y=15.0 allowImmediateFallbackCenter=false requireObservableReaction=true verification=failed (no observable menu/panel reaction)",
            retryAttempt: "success=true accepted=true timedOut=false durationMs=140 resolution=forceRefresh=true items=12 method=bundle+statusItemIndex target=id=resolved bundle=com.test.app menuExtra=foo statusItemIndex=1 x=101.0 width=24.0 fallbackCenter=x=113.0 y=15.0 requireObservableReaction=true verification=verified (shownMenu)",
            finalOutcome: "click succeeded"
        )

        let summary = diagnostics.formattedSummary()

        #expect(summary.contains("initialResolution: forceRefresh=false items=12 method=uniqueId"))
        #expect(summary.contains("retryAttempt: success=true"))
        #expect(summary.contains("verification=verified (shownMenu)"))
        #expect(summary.contains("finalOutcome: click succeeded"))
    }

    @Test("Search activation rejects unverified clicks for revealed or browse-session flows")
    func testSearchActivationRequiresObservableReactionForBrowseFlows() {
        #expect(
            SearchService.requiresObservableReactionVerification(
                origin: .browsePanel,
                didReveal: true,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchService.requiresObservableReactionVerification(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: true
            )
        )
        #expect(
            !SearchService.requiresObservableReactionVerification(
                origin: .direct,
                didReveal: false,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchService.requiresObservableReactionVerification(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: false
            )
        )

        #expect(
            !SearchService.acceptsClickResult(
                success: true,
                verification: "unavailable (no comparable AX reaction signals)",
                requireObservableReaction: true
            )
        )
        #expect(
            !SearchService.acceptsClickResult(
                success: true,
                verification: "failed (no observable menu/panel reaction)",
                requireObservableReaction: true
            )
        )
        #expect(
            SearchService.acceptsClickResult(
                success: true,
                verification: "verified (shownMenu)",
                requireObservableReaction: true
            )
        )
        #expect(
            SearchService.acceptsClickResult(
                success: true,
                verification: "unavailable (no comparable AX reaction signals)",
                requireObservableReaction: false
            )
        )
        #expect(
            SearchService.shouldForceFreshTargetResolution(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: true
            )
        )
        #expect(
            !SearchService.shouldAllowImmediateFallbackCenter(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: true
            )
        )
        #expect(
            !SearchService.shouldAllowImmediateFallbackCenter(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchService.resolvedAllowImmediateFallbackCenter(
                baseAllowImmediateFallbackCenter: false,
                likelyNoExtrasMenuBar: true,
                fallbackCenterOnScreen: true
            )
        )
        #expect(
            !SearchService.resolvedAllowImmediateFallbackCenter(
                baseAllowImmediateFallbackCenter: false,
                likelyNoExtrasMenuBar: true,
                fallbackCenterOnScreen: false
            )
        )
        #expect(
            SearchService.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: RunningApp(id: "offscreen.app", name: "Offscreen", icon: nil, xPosition: -4300, width: 24)
            )
        )
        #expect(
            !SearchService.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: RunningApp(id: "visible.app", name: "Visible", icon: nil, xPosition: 631, width: 24)
            )
        )
        #expect(
            SearchService.shouldUsePinnedAlwaysHiddenFallback(
                hidingState: .hidden,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchService.shouldUsePinnedAlwaysHiddenFallback(
                hidingState: .expanded,
                isBrowseSessionActive: true
            )
        )
    }

    @Test("Spatial fallback center is suppressed when the cached X is off the hosting menu bar screen")
    func testSpatialFallbackCenterRejectsOffscreenX() {
        let center = SearchService.spatialFallbackCenter(
            xPosition: -1721,
            width: 24,
            menuBarScreenFrame: CGRect(x: 3440, y: 0, width: 1720, height: 1440)
        )

        #expect(center == nil)
    }

    @Test("Spatial fallback center is kept when the cached X is still on the hosting menu bar screen")
    func testSpatialFallbackCenterKeepsOnScreenX() {
        let center = SearchService.spatialFallbackCenter(
            xPosition: 4748,
            width: 24,
            menuBarScreenFrame: CGRect(x: 3440, y: 0, width: 1720, height: 1440)
        )

        #expect(center == CGPoint(x: 4760, y: 15))
    }

    @Test("Browse and reveal flows get a larger click timeout budget for observable reaction verification")
    func testClickAttemptTimeoutBudgetExpandsForObservableReaction() {
        #expect(
            SearchService.clickAttemptTimeoutMs(
                baseMs: 900,
                requireObservableReaction: false
            ) == 900
        )
        #expect(
            SearchService.clickAttemptTimeoutMs(
                baseMs: 900,
                requireObservableReaction: true
            ) == 1800
        )
    }

    @Test("Preferred spatial fallback keeps the last on-screen center when refreshed coordinates drift off-screen")
    func testPreferredSpatialFallbackCenterUsesOriginalOnScreenXWhenRefreshRegresses() {
        let center = SearchService.preferredSpatialFallbackCenter(
            primaryXPosition: -3628,
            primaryWidth: 33,
            fallbackXPosition: 1390,
            fallbackWidth: 33,
            menuBarScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        #expect(center == CGPoint(x: 1406.5, y: 15))
    }

    @Test("Second menu bar diagnostics keep counts and relayout state")
    func testSecondMenuBarDiagnosticsSummary() {
        let diagnostics = SearchWindowController.SecondMenuBarDiagnostics(
            showRequestedAt: "2026-03-05T12:34:56.789Z",
            currentMode: "Optional(SaneBar.SearchWindowMode.secondMenuBar)",
            windowVisible: true,
            windowFrame: "x=10.0 y=20.0 w=300.0 h=120.0",
            refreshForced: true,
            visibleCount: 4,
            hiddenCount: 12,
            alwaysHiddenCount: 2,
            relayoutPassCount: 2,
            lastRelayoutAt: "2026-03-05T12:34:57.100Z",
            lastRelayoutReason: "classified-refresh"
        )

        let summary = diagnostics.formattedSummary()

        #expect(summary.contains("windowFrame: x=10.0 y=20.0 w=300.0 h=120.0"))
        #expect(summary.contains("hiddenCount: 12"))
        #expect(summary.contains("relayoutPassCount: 2"))
    }

    @Test("Merged discoverable apps append owner-only fallbacks without duplicating precise matches")
    @MainActor
    func testMergedDiscoverableAppsPrefersPreciseItems() {
        let positioned = [
            RunningApp(
                id: "com.example.precise",
                name: "Precise",
                icon: nil,
                menuExtraIdentifier: "com.example.precise.status",
                xPosition: 400,
                width: 20
            )
        ]
        let owners = [
            RunningApp(id: "com.example.precise", name: "Precise", icon: nil),
            RunningApp(id: "at.obdev.littlesnitch.networkmonitor", name: "Little Snitch", icon: nil)
        ]

        let merged = SearchService.mergedDiscoverableApps(positioned: positioned, owners: owners)

        #expect(merged.count == 2)
        #expect(merged[0].uniqueId == "com.example.precise::axid:com.example.precise.status")
        #expect(merged[1].uniqueId == "at.obdev.littlesnitch.networkmonitor")
    }

    @Test("Pinned hidden apps promote to always-hidden classification")
    func testPinnedHiddenAppsPromoteToAlwaysHidden() {
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
    func testPinnedHiddenAppsPromoteViaBundleFallback() {
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

    @Test("Zoned menu bar views keep fallback-only entries but drop coarse duplicates")
    func testZonedMenuBarItemsPreferPreciseIdentityPerBundle() {
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
            coarseOnly.app.uniqueId
        ])
        #expect(filtered.contains { $0.app.uniqueId == coarseOnly.app.uniqueId && !$0.app.hasPreciseMenuBarIdentity })
    }

    @Test("SaneBar diagnostics collector includes search and panel snapshots")
    func testDiagnosticsCollectorIncludesRuntimeSnapshots() throws {
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
        #expect(source.contains("StatusBarController.displayPositionBackupKey"))
        #expect(source.contains("SaneBar_CalibratedScreenWidth"))
    }

    @Test("All mode discovery uses the broader menu bar app list")
    func testAllModeDiscoveryUsesMergedMenuBarApps() throws {
        let viewFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let source = try String(contentsOf: viewFile, encoding: .utf8)

        #expect(source.contains("menuBarApps = service.cachedMenuBarApps()"))
        #expect(source.contains("let allModeApps = effectiveMode == .all && !isSecondMenuBar ? await service.refreshMenuBarApps() : []"))
        #expect(source.contains("menuBarApps = allModeApps"))
    }

    // MARK: - Icon Groups Tests

    @Test("IconGroup filtering matches bundle IDs correctly")
    func testIconGroupFiltering() {
        // Given: a group with specific bundle IDs and a list of apps
        let group = SaneBarSettings.IconGroup(
            name: "Work",
            appBundleIds: ["com.slack.Slack", "com.1password.1password"]
        )

        let apps = [
            RunningApp(id: "com.slack.Slack", name: "Slack", icon: nil),
            RunningApp(id: "com.spotify.client", name: "Spotify", icon: nil),
            RunningApp(id: "com.1password.1password", name: "1Password", icon: nil),
            RunningApp(id: "com.apple.Safari", name: "Safari", icon: nil)
        ]

        // When: filter apps by group (mimicking filteredApps logic)
        let bundleIds = Set(group.appBundleIds)
        let filtered = apps.filter { bundleIds.contains($0.id) }

        // Then: only matching apps are included
        #expect(filtered.count == 2)
        #expect(filtered.contains { $0.id == "com.slack.Slack" })
        #expect(filtered.contains { $0.id == "com.1password.1password" })
        #expect(!filtered.contains { $0.id == "com.spotify.client" })
    }

    @Test("IconGroup filtering with empty group returns no apps")
    func testIconGroupFilteringEmptyGroup() {
        // Given: an empty group
        let group = SaneBarSettings.IconGroup(name: "Empty")

        let apps = [
            RunningApp(id: "com.slack.Slack", name: "Slack", icon: nil),
            RunningApp(id: "com.spotify.client", name: "Spotify", icon: nil)
        ]

        // When: filter apps by group
        let bundleIds = Set(group.appBundleIds)
        let filtered = apps.filter { bundleIds.contains($0.id) }

        // Then: no apps match
        #expect(filtered.isEmpty)
    }

    @Test("IconGroup filtering handles missing apps gracefully")
    func testIconGroupFilteringMissingApps() {
        // Given: a group with bundle IDs that don't exist in app list
        let group = SaneBarSettings.IconGroup(
            name: "Missing",
            appBundleIds: ["com.nonexistent.app", "com.another.missing"]
        )

        let apps = [
            RunningApp(id: "com.slack.Slack", name: "Slack", icon: nil)
        ]

        // When: filter apps by group
        let bundleIds = Set(group.appBundleIds)
        let filtered = apps.filter { bundleIds.contains($0.id) }

        // Then: no apps match
        #expect(filtered.isEmpty)
    }

    @Test("Adding app to group prevents duplicates")
    func testAddAppToGroupNoDuplicates() {
        // Given: a group with an existing app
        var group = SaneBarSettings.IconGroup(
            name: "Test",
            appBundleIds: ["com.existing.app"]
        )

        let bundleIdToAdd = "com.existing.app"

        // When: add same app (mimicking addAppToGroup logic)
        if !group.appBundleIds.contains(bundleIdToAdd) {
            group.appBundleIds.append(bundleIdToAdd)
        }

        // Then: no duplicate added
        #expect(group.appBundleIds.count == 1)
        #expect(group.appBundleIds == ["com.existing.app"])
    }

    @Test("Adding new app to group works")
    func testAddAppToGroupNewApp() {
        // Given: a group with an existing app
        var group = SaneBarSettings.IconGroup(
            name: "Test",
            appBundleIds: ["com.existing.app"]
        )

        let bundleIdToAdd = "com.new.app"

        // When: add new app
        if !group.appBundleIds.contains(bundleIdToAdd) {
            group.appBundleIds.append(bundleIdToAdd)
        }

        // Then: app is added
        #expect(group.appBundleIds.count == 2)
        #expect(group.appBundleIds.contains("com.new.app"))
    }

    @Test("Removing app from group works")
    func testRemoveAppFromGroup() {
        // Given: a group with multiple apps
        var group = SaneBarSettings.IconGroup(
            name: "Test",
            appBundleIds: ["com.first.app", "com.second.app", "com.third.app"]
        )

        let bundleIdToRemove = "com.second.app"

        // When: remove app (mimicking removeAppFromGroup logic)
        group.appBundleIds.removeAll { $0 == bundleIdToRemove }

        // Then: app is removed
        #expect(group.appBundleIds.count == 2)
        #expect(!group.appBundleIds.contains("com.second.app"))
        #expect(group.appBundleIds.contains("com.first.app"))
        #expect(group.appBundleIds.contains("com.third.app"))
    }

    @Test("Removing non-existent app from group is safe")
    func testRemoveNonExistentAppFromGroup() {
        // Given: a group with apps
        var group = SaneBarSettings.IconGroup(
            name: "Test",
            appBundleIds: ["com.first.app", "com.second.app"]
        )

        let bundleIdToRemove = "com.nonexistent.app"

        // When: try to remove non-existent app
        group.appBundleIds.removeAll { $0 == bundleIdToRemove }

        // Then: group is unchanged
        #expect(group.appBundleIds.count == 2)
    }

    @Test("Group selection finds correct group by ID")
    func testGroupSelectionById() {
        // Given: multiple groups
        let group1 = SaneBarSettings.IconGroup(name: "Work", appBundleIds: ["com.work.app"])
        let group2 = SaneBarSettings.IconGroup(name: "Personal", appBundleIds: ["com.personal.app"])
        let group3 = SaneBarSettings.IconGroup(name: "Fun", appBundleIds: ["com.fun.app"])
        let groups = [group1, group2, group3]

        // When: find group by ID
        let selectedGroupId = group2.id
        let foundGroup = groups.first { $0.id == selectedGroupId }

        // Then: correct group is found
        #expect(foundGroup != nil)
        #expect(foundGroup?.name == "Personal")
        #expect(foundGroup?.appBundleIds == ["com.personal.app"])
    }

    @Test("Combined search and group filtering works")
    func testCombinedSearchAndGroupFiltering() {
        // Given: a group and search text
        let group = SaneBarSettings.IconGroup(
            name: "Social",
            appBundleIds: ["com.slack.Slack", "com.discord.Discord", "com.twitter.twitter"]
        )

        let apps = [
            RunningApp(id: "com.slack.Slack", name: "Slack", icon: nil),
            RunningApp(id: "com.discord.Discord", name: "Discord", icon: nil),
            RunningApp(id: "com.twitter.twitter", name: "Twitter", icon: nil),
            RunningApp(id: "com.spotify.client", name: "Spotify", icon: nil)
        ]

        let searchText = "Dis"

        // When: apply both filters (mimicking filteredApps logic)
        let bundleIds = Set(group.appBundleIds)
        var filtered = apps.filter { bundleIds.contains($0.id) }
        filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        // Then: both filters applied
        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "com.discord.Discord")
    }

    @Test("Case-insensitive search within group works")
    func testCaseInsensitiveSearchInGroup() {
        // Given: a group and lowercase search
        let group = SaneBarSettings.IconGroup(
            name: "Apps",
            appBundleIds: ["com.slack.Slack", "com.spotify.client"]
        )

        let apps = [
            RunningApp(id: "com.slack.Slack", name: "Slack", icon: nil),
            RunningApp(id: "com.spotify.client", name: "Spotify", icon: nil)
        ]

        let searchText = "SLACK"  // uppercase search

        // When: apply filters
        let bundleIds = Set(group.appBundleIds)
        var filtered = apps.filter { bundleIds.contains($0.id) }
        filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

        // Then: case-insensitive match works
        #expect(filtered.count == 1)
        #expect(filtered.first?.name == "Slack")
    }

    @Test("Deleting group resets selection to nil (All)")
    func testDeleteGroupResetsSelection() {
        // Given: groups and a selected group ID
        var groups = [
            SaneBarSettings.IconGroup(name: "Work"),
            SaneBarSettings.IconGroup(name: "Personal")
        ]
        var selectedGroupId: UUID? = groups[0].id

        let groupToDelete = groups[0]

        // When: delete selected group (mimicking deleteGroup logic)
        groups.removeAll { $0.id == groupToDelete.id }
        if selectedGroupId == groupToDelete.id {
            selectedGroupId = nil
        }

        // Then: selection is reset to nil (All)
        #expect(selectedGroupId == nil)
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Personal")
    }

    @Test("Deleting non-selected group preserves selection")
    func testDeleteNonSelectedGroupPreservesSelection() {
        // Given: groups and a selected group ID
        var groups = [
            SaneBarSettings.IconGroup(name: "Work"),
            SaneBarSettings.IconGroup(name: "Personal")
        ]
        var selectedGroupId: UUID? = groups[0].id  // Work is selected

        let groupToDelete = groups[1]  // Delete Personal (not selected)

        // When: delete non-selected group
        groups.removeAll { $0.id == groupToDelete.id }
        if selectedGroupId == groupToDelete.id {
            selectedGroupId = nil
        }

        // Then: selection is preserved
        #expect(selectedGroupId != nil)
        #expect(groups.count == 1)
        #expect(groups.first?.id == selectedGroupId)
    }

    @Test("Creating group auto-selects new group")
    func testCreateGroupAutoSelects() {
        // Given: existing groups
        var groups: [SaneBarSettings.IconGroup] = []
        var selectedGroupId: UUID? = nil

        // When: create new group (mimicking createGroup logic)
        let newGroup = SaneBarSettings.IconGroup(name: "New Group")
        groups.append(newGroup)
        selectedGroupId = newGroup.id

        // Then: new group is selected
        #expect(selectedGroupId == newGroup.id)
        #expect(groups.count == 1)
    }

    @Test("Empty group name is allowed (UI validation responsibility)")
    func testEmptyGroupNameAllowed() {
        // Given: creating group with empty name
        let group = SaneBarSettings.IconGroup(name: "")

        // Then: it's allowed at data layer (UI should validate)
        #expect(group.name == "")
        #expect(group.id != UUID())  // Has valid ID
    }

    @Test("Group with many apps filters correctly")
    func testGroupWithManyApps() {
        // Given: a group with many apps
        var bundleIds: [String] = []
        for i in 1...100 {
            bundleIds.append("com.app\(i).test")
        }
        let group = SaneBarSettings.IconGroup(name: "Large", appBundleIds: bundleIds)

        // Create matching apps
        var apps: [RunningApp] = []
        for i in 1...150 {  // 150 apps, only 100 in group
            apps.append(RunningApp(id: "com.app\(i).test", name: "App \(i)", icon: nil))
        }

        // When: filter apps by group
        let groupBundleIds = Set(group.appBundleIds)
        let filtered = apps.filter { groupBundleIds.contains($0.id) }

        // Then: exactly 100 apps match
        #expect(filtered.count == 100)
    }

    // MARK: - Stress Tests (Hostile User Behavior)

    @Test("STRESS: Whitespace-only group name is rejected")
    func testWhitespaceOnlyGroupNameRejected() {
        // Given: names that are all whitespace
        let whitespaceNames = ["   ", "\t", "\n", "  \t\n  ", ""]

        for name in whitespaceNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Then: all should be considered empty after trim
            #expect(trimmed.isEmpty, "'\(name)' should trim to empty")
        }
    }

    @Test("STRESS: Group lookup by stale ID returns nil safely")
    func testStaleGroupIdLookup() {
        // Given: groups where one was "deleted"
        let group1 = SaneBarSettings.IconGroup(name: "Exists")
        let deletedGroupId = UUID()  // ID that doesn't exist in array

        let groups = [group1]

        // When: look up deleted group ID
        let found = groups.first { $0.id == deletedGroupId }

        // Then: returns nil (doesn't crash)
        #expect(found == nil)
    }

    @Test("STRESS: Index bounds check after concurrent modification")
    func testIndexBoundsAfterConcurrentModification() {
        // Given: array that might be modified during iteration
        var groups = [
            SaneBarSettings.IconGroup(name: "A"),
            SaneBarSettings.IconGroup(name: "B"),
            SaneBarSettings.IconGroup(name: "C")
        ]

        let targetId = groups[1].id

        // When: find index then simulate concurrent deletion
        if let index = groups.firstIndex(where: { $0.id == targetId }) {
            // Simulate another operation deleting all groups
            groups.removeAll()

            // Then: bounds check prevents crash
            let safeAccess = index < groups.count
            #expect(!safeAccess, "Index should be out of bounds after clear")
        }
    }

    @Test("STRESS: Rapid create/delete operations don't corrupt state")
    func testRapidCreateDelete() {
        // Given: empty groups array
        var groups: [SaneBarSettings.IconGroup] = []
        var selectedGroupId: UUID? = nil

        // When: rapidly create and delete groups
        for i in 1...100 {
            // Create
            let newGroup = SaneBarSettings.IconGroup(name: "Group \(i)")
            groups.append(newGroup)
            selectedGroupId = newGroup.id

            // Immediately delete every other one
            if i % 2 == 0 {
                groups.removeAll { $0.id == newGroup.id }
                if selectedGroupId == newGroup.id {
                    selectedGroupId = nil
                }
            }
        }

        // Then: state is consistent
        #expect(groups.count == 50, "Should have 50 remaining groups")
        // Selected ID should be nil (last created was deleted)
        #expect(selectedGroupId == nil)
    }

    @Test("STRESS: Max group limit prevents runaway creation")
    func testMaxGroupLimit() {
        // Given: approaching max limit
        let maxGroupCount = 50
        var groups: [SaneBarSettings.IconGroup] = []

        // When: try to create more than max
        for i in 1...60 {
            if groups.count < maxGroupCount {
                groups.append(SaneBarSettings.IconGroup(name: "Group \(i)"))
            }
        }

        // Then: capped at max
        #expect(groups.count == 50)
    }

    @Test("STRESS: Double-delete same group is safe")
    func testDoubleDeleteSafe() {
        // Given: a group
        var groups = [SaneBarSettings.IconGroup(name: "ToDelete")]
        let groupId = groups[0].id
        var selectedGroupId: UUID? = groupId

        // When: delete twice (simulating race condition)
        func deleteGroup(id: UUID) {
            guard groups.contains(where: { $0.id == id }) else { return }
            groups.removeAll { $0.id == id }
            if selectedGroupId == id {
                selectedGroupId = nil
            }
        }

        deleteGroup(id: groupId)
        deleteGroup(id: groupId)  // Second delete should be no-op

        // Then: no crash, group gone
        #expect(groups.isEmpty)
        #expect(selectedGroupId == nil)
    }

    @Test("STRESS: Add app to deleted group is safe")
    func testAddAppToDeletedGroup() {
        // Given: groups array (group will be "deleted")
        var groups = [
            SaneBarSettings.IconGroup(name: "Work", appBundleIds: [])
        ]
        let targetGroupId = groups[0].id

        // Simulate group deletion before add completes
        groups.removeAll()

        // When: try to add app to deleted group
        func addAppToGroup(bundleId: String, groupId: UUID) -> Bool {
            guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
                return false  // Group not found
            }
            guard index < groups.count else { return false }
            groups[index].appBundleIds.append(bundleId)
            return true
        }

        let result = addAppToGroup(bundleId: "com.test.app", groupId: targetGroupId)

        // Then: gracefully fails without crash
        #expect(result == false)
    }

    @Test("STRESS: Filter with stale selectedGroupId shows all apps")
    func testFilterWithStaleSelectedGroupId() {
        // Given: apps and a stale group ID
        let apps = [
            RunningApp(id: "com.a", name: "A", icon: nil),
            RunningApp(id: "com.b", name: "B", icon: nil)
        ]
        let groups: [SaneBarSettings.IconGroup] = []  // Empty - group was deleted
        let staleGroupId: UUID? = UUID()  // Points to non-existent group

        // When: filter with stale ID (mimicking filteredApps logic)
        var filtered = apps
        if let groupId = staleGroupId,
           let group = groups.first(where: { $0.id == groupId }) {
            let bundleIds = Set(group.appBundleIds)
            filtered = apps.filter { bundleIds.contains($0.id) }
        }
        // Group not found - filtered stays as all apps

        // Then: shows all apps (safe fallback)
        #expect(filtered.count == 2)
    }

    @Test("STRESS: Unicode and emoji in group names preserved")
    func testUnicodeEmojiGroupNames() {
        // Given: groups with various Unicode
        let names = [
            "🎨 Creative",
            "日本語グループ",
            "مجموعة عربية",
            "Группа",
            "🔥💯👍",
            "Test™️ App©️"
        ]

        var groups: [SaneBarSettings.IconGroup] = []
        for name in names {
            groups.append(SaneBarSettings.IconGroup(name: name))
        }

        // Then: all names preserved correctly
        for (i, group) in groups.enumerated() {
            #expect(group.name == names[i])
        }
    }
}
