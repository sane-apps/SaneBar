@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardAppleScriptMoveXCTests: RuntimeGuardTestCase {
    func testRuntimeCoordinatorOwnsStartupAndMoveAdmissionPolicies() throws {
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let queueURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveQueueWorkflow.swift")
        let queueSource = try String(contentsOf: queueURL, encoding: .utf8)

        XCTAssertTrue(
            coordinatorSource.contains("enum MenuBarOperationCoordinator") &&
                coordinatorSource.contains("statusItemRecoveryAction(") &&
                coordinatorSource.contains("manualLayoutRestoreRequest") &&
                coordinatorSource.contains("moveQueueDecision("),
            "Runtime coordinator should own the shared startup, restore, and move admission policies"
        )
        XCTAssertTrue(
            managerSource.contains("currentStatusItemRecoverySnapshot()") &&
                managerSource.contains("MenuBarOperationCoordinator.statusItemRecoveryAction(") &&
                managerSource.contains("executeStatusItemRecoveryAction("),
            "MenuBarManager should build one typed recovery snapshot and route startup, validation, and restore through one coordinator action"
        )
        XCTAssertTrue(
            managerSource.contains("context: .manualLayoutRestoreRequest") &&
                managerSource.contains("trigger: \"manual-layout-restore\""),
            "Manual restore should go through the shared recovery executor instead of directly replaying persisted layout"
        )
        XCTAssertTrue(
            queueSource.contains("canQueueInteractiveMove(") &&
                queueSource.contains("currentMoveRuntimeSnapshot(") &&
                queueSource.contains("MenuBarOperationCoordinator.moveQueueDecision("),
            "Interactive move entry points should use the shared move-admission policy instead of duplicating local guard ladders"
        )
    }

    func testSearchServiceUsesStableSeparatorOriginForClassificationBoundary() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func separatorBoundaryXForClassification(allowEstimatedFallback: Bool = false) -> CGFloat?"),
            "SearchService should centralize separator lookup through a dedicated classification helper"
        )
        XCTAssertTrue(
            source.contains("MenuBarManager.shared.geometryResolver.separatorRightEdgeX(allowEstimatedFallback: allowEstimatedFallback)"),
            "Classification helper should prefer separator right-edge cache for stable hidden/visible partitioning"
        )
        XCTAssertTrue(
            source.contains("MenuBarManager.shared.geometryResolver.separatorOriginX(allowEstimatedFallback: allowEstimatedFallback)"),
            "Classification helper should use the main separator origin for stable hidden/visible partitioning"
        )
        XCTAssertTrue(
            source.contains("alwaysHiddenPinWorkflow.repairSeparatorPositionIfNeeded(") &&
                source.contains("reason: \"classification\"") &&
                // FM-2 (#136/#168): steady-state classification repair preserves the
                // explicit persisted divider; it must not reanchor toward Control Center.
                source.contains("preserveExplicitPersistedPositions: true"),
            "Classification should attempt separator repair when always-hidden ordering is invalid, preserving the explicit persisted divider"
        )
    }

    func testBrowseFlowsAvoidImmediateRehideAndDeferSearchRehideWhileVisible() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let shouldScheduleImmediateRehide = trigger != .search && trigger != .findIcon"),
            "showHiddenItemsNow should not arm the short rehide timer for Browse Icons flows"
        )
        XCTAssertTrue(
            source.contains("await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)") &&
                source.contains("_ = manager.geometryResolver.separatorOriginX()") &&
                source.contains("_ = manager.geometryResolver.separatorRightEdgeX()"),
            "Browse/search reveals should refresh real separator geometry before classification so wake-cleared caches do not fall back to stale visible/hidden zones"
        )
        XCTAssertTrue(
            source.contains("browseController.isVisible"),
            "Search rehide should defer while Browse Icons is still visible"
        )
        XCTAssertTrue(
            source.contains("browseController.isBrowseSessionActive || browseController.isVisible"),
            "Search rehide should defer while Browse Icons session startup/teardown is still in progress"
        )
    }

    func testAppleScriptMoveCommandsDoNotAddPostMoveSettleWork() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("private func refreshedIconZones(\n    timeoutSeconds: TimeInterval = 2.5,\n    allowAuthoritativeFallback: Bool = true"),
            "AppleScript move checks should use a longer classified-app refresh window before fallback"
        )
        XCTAssertTrue(
            !source.contains("waitForScriptZone(") &&
                !source.contains("settleScriptZoneAfterVerifiedMove("),
            "AppleScript move commands should not run a second script-layer zone settle loop after the move task already verified the drag"
        )
        XCTAssertTrue(
            !source.contains("invalidateScriptMoveCachesAfterVerifiedDrag()"),
            "AppleScript move commands should leave post-drag cache invalidation to the shared move pipeline instead of duplicating it"
        )
    }

    func testAppleScriptMoveResolutionAvoidsUnneededFreshSnapshots() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("func zonesForScriptMoveResolution(_ identifier: String) -> [ScriptZonedIcon]"),
            "AppleScript moves should use a dedicated move-resolution helper instead of the looser read path"
        )
        XCTAssertTrue(
            source.contains("let startZones = zonesForScriptMoveResolution(trimmedId)"),
            "AppleScript moves should resolve zones through the dedicated helper before dispatching drag work"
        )
        XCTAssertTrue(
            source.contains("shouldPreferFreshZonesForScriptMove("),
            "AppleScript move resolution should explicitly encode when cached zone snapshots are too stale to trust"
        )
        XCTAssertTrue(
            source.contains("let cacheAge = Date().timeIntervalSince(AccessibilityService.shared.menuBarItemCacheTime)") &&
                source.contains("cacheIsFresh: cacheIsFresh") &&
                source.contains("let refreshTimeout = cached.isEmpty ? 2.5 : 1.8"),
            "AppleScript move resolution should gate fresh scans on real cache freshness and give cold-start moves the same patience as list icon zones"
        )
        XCTAssertTrue(
            source.contains("scriptMoveResolutionZonesAfterRefresh(") &&
                source.contains("authoritativeScriptListingZonesForCommand()"),
            "AppleScript move resolution should not report not-found from a cheap refresh that missed the requested exact ID"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.invalidateMenuBarItemPositionsCache()"),
            "AppleScript move resolution should invalidate only positioned item state before the refreshed lookup"
        )
    }

    func testScriptMoveResolutionFallsBackToAuthoritativeWhenCheapRefreshMissesExactId() {
        let target = RunningApp(
            id: "com.example.target",
            name: "Target",
            icon: nil,
            statusItemIndex: 0,
            xPosition: 120,
            width: 22
        )
        let other = RunningApp(
            id: "com.example.other",
            name: "Other",
            icon: nil,
            statusItemIndex: 0,
            xPosition: 160,
            width: 22
        )

        let zones = scriptMoveResolutionZonesAfterRefresh(
            identifier: target.uniqueId,
            cached: [],
            refreshed: [(other, .visible)]
        ) {
            [(target, .hidden)]
        }

        XCTAssertEqual(resolveScriptIcon(target.uniqueId, from: zones)?.app.uniqueId, target.uniqueId)
    }

    func testScriptMoveResolutionDoesNotPayAuthoritativeRefreshWhenCheapRefreshHasExactId() {
        let target = RunningApp(
            id: "com.example.target",
            name: "Target",
            icon: nil,
            statusItemIndex: 0,
            xPosition: 120,
            width: 22
        )
        var usedAuthoritativeFallback = false

        let zones = scriptMoveResolutionZonesAfterRefresh(
            identifier: target.uniqueId,
            cached: [],
            refreshed: [(target, .visible)]
        ) {
            usedAuthoritativeFallback = true
            return []
        }

        XCTAssertEqual(resolveScriptIcon(target.uniqueId, from: zones)?.zone, .visible)
        XCTAssertFalse(usedAuthoritativeFallback)
    }

    func testAppleScriptMoveCommandsFallbackToFreshExactZoneVerification() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("func freshZonesForScriptMoveVerification(timeoutSeconds: TimeInterval = 2.5) -> [ScriptZonedIcon]") &&
                source.contains("AccessibilityService.shared.invalidateMenuBarItemPositionsCache()") &&
                source.contains("return refreshedIconZones(timeoutSeconds: timeoutSeconds)"),
            "AppleScript move fallback should force a fresh classified snapshot before accepting a failed physical drag"
        )
        XCTAssertTrue(
            source.contains("if !moved, moveVerifiedByFreshExactZone(trimmedId: trimmedId, targetZone: targetZone)") &&
                source.contains("guard resolved.zone == targetZone else") &&
                source.contains("AppleScript move fallback accepted fresh exact-zone verification"),
            "AppleScript move commands should return success only when the exact requested icon is freshly observed in the target zone after a failed move task"
        )
    }

    func testAppleScriptMoveCommandsWaitOnMoveTasks() throws {
        let source = try appleScriptCommandSource()
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let queueURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveQueueWorkflow.swift")
        let queueSource = try String(contentsOf: queueURL, encoding: .utf8)
        let standardURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let standardSource = try String(contentsOf: standardURL, encoding: .utf8)
        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("return runScriptMove {"),
            "AppleScript move commands should block on the real move task instead of fire-and-forget polling"
        )
        XCTAssertTrue(
            source.contains("await manager.moveQueueWorkflow.moveIconAndWait("),
            "AppleScript visible/hidden moves should wait on the standard move task"
        )
        XCTAssertTrue(
            source.contains("await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait("),
            "AppleScript always-hidden moves should wait on the dedicated always-hidden move task"
        )
        XCTAssertTrue(
            source.contains("await manager.moveQueueWorkflow.moveIconFromAlwaysHiddenToHiddenAndWait("),
            "AppleScript always-hidden exits to hidden should wait on the dedicated always-hidden helper task"
        )
        XCTAssertTrue(
            !source.contains("invalidateScriptMoveCachesAfterVerifiedDrag()"),
            "AppleScript move commands should trust the verified move helper and avoid duplicating post-move cache invalidation"
        )
        XCTAssertTrue(
            queueSource.contains("func moveIconAlwaysHiddenAndWait("),
            "Move queue workflow should expose an awaitable always-hidden move helper for AppleScript command reliability"
        )
        XCTAssertTrue(
            queueSource.contains("func moveIconFromAlwaysHiddenToHiddenAndWait("),
            "Move queue workflow should expose an awaitable always-hidden-to-hidden helper for AppleScript command reliability"
        )
        XCTAssertTrue(
            queueSource.contains("prepareAlwaysHiddenMoveQueue(") &&
                queueSource.contains("ensureAlwaysHiddenSeparatorReady(") &&
                queueSource.contains("always-hidden separator became ready after") &&
                managerSource.contains("Force-recreating always-hidden separator after nil update"),
            "Always-hidden move entry should wait for the always-hidden separator to exist before queue admission"
        )
        XCTAssertTrue(
            standardSource.contains("let actionableMoveSafety = AccessibilityMenuExtraService.actionableMoveResolutionSafety(") &&
                alwaysHiddenSource.contains("let actionableMoveSafety = AccessibilityMenuExtraService.actionableMoveResolutionSafety("),
            "Interactive move flows should ask the menu-extra owner whether a multi-item bundle can be moved safely before dragging"
        )
        XCTAssertTrue(
            standardSource.contains("if actionableMoveSafety.allowsClassifiedZoneFallback {") &&
                alwaysHiddenSource.contains("if actionableMoveSafety.allowsClassifiedZoneFallback {") &&
                standardSource.contains("Skipping classified-zone move fallback for ambiguous multi-item identity"),
            "Interactive move flows should refuse classified-zone success fallback when exact move identity could not be proven"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("Refusing ambiguous always-hidden move target") &&
                alwaysHiddenSource.contains("Skipping always-hidden classified-zone fallback for ambiguous multi-item identity") &&
                alwaysHiddenSource.contains("Refusing ambiguous AH-to-Hidden move target") &&
                alwaysHiddenSource.contains("Skipping AH-to-Hidden classified-zone fallback for ambiguous multi-item identity"),
            "Always-hidden move flows should use the same ambiguity safety gate and fallback refusal as the standard move path"
        )
    }

    func testAppleScriptReorderCommandsUseSharedReorderQueue() throws {
        let source = try appleScriptCommandSource()
        let sdefSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Resources/SaneBar.sdef"),
            encoding: .utf8
        )
        let shortcutsSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/Settings/ShortcutsSettingsView.swift"),
            encoding: .utf8
        )
        let guideSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("docs/how-to-automate-menu-bar-icons-applescript.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            sdefSource.contains(#"<command name="move icon before" code="SBarmvbf""#) &&
                sdefSource.contains(#"<command name="move icon after" code="SBarmvaf""#) &&
                sdefSource.contains(#"<parameter name="target icon" code="trgt" type="text""#),
            "AppleScript should expose target-relative reorder commands with a named target icon parameter"
        )
        XCTAssertTrue(
            source.contains("@objc(MoveIconBeforeCommand)") &&
                source.contains("@objc(MoveIconAfterCommand)") &&
                source.contains("class ReorderIconScriptCommand: SaneBarScriptCommand"),
            "Reorder AppleScript commands should be registered as Cocoa script command classes"
        )
        XCTAssertTrue(
            source.contains("manager.moveQueueWorkflow.queueReorderIcon(") &&
                source.contains("return await task.value"),
            "AppleScript reorder should wait on the shared reorder move task instead of posting direct drag events"
        )
        XCTAssertTrue(
            source.contains("reorderVerifiedByFreshRelativeOrder(") &&
                source.contains("freshZonesForScriptMoveVerification(timeoutSeconds: 2.5)") &&
                source.contains("guard source.zone == target.zone else") &&
                source.contains("let sameZone = zones.filter { $0.zone == source.zone }") &&
                source.contains("let expectedSourceIndex = placeAfterTarget ? targetIndex + 1 : targetIndex - 1") &&
                source.contains("let isAdjacent = sourceIndex == expectedSourceIndex"),
            "AppleScript reorder should verify fresh same-zone adjacency before reporting success"
        )
        XCTAssertTrue(
            source.contains("manager.moveQueueWorkflow.queueReorderIcon(") &&
                source.contains("physicalMoveOrigin: .appleScriptUserAction") &&
                source.contains("guard source.zone == target.zone else") &&
                source.contains("failure: .crossZone"),
            "AppleScript reorder should route target-relative moves through the shared queue and reject cross-zone reorders"
        )
        XCTAssertFalse(
            source.contains("reorderMenuBarIcon(\n                sourceBundleID"),
            "AppleScript command code should not call the low-level drag service directly"
        )
        XCTAssertTrue(
            shortcutsSource.contains("move icon before \\\"SOURCE_ID\\\" target icon \\\"TARGET_ID\\\"") &&
                shortcutsSource.contains("move icon after \\\"SOURCE_ID\\\" target icon \\\"TARGET_ID\\\"") &&
                guideSource.contains("move icon before \"SOURCE_ID\" target icon \"TARGET_ID\"") &&
                guideSource.contains("move icon after \"SOURCE_ID\" target icon \"TARGET_ID\""),
            "Customer-facing AppleScript examples should use the SDEF command phrase shape"
        )
        XCTAssertFalse(
            shortcutsSource.contains("move icon \\\"SOURCE_ID\\\" before target icon") ||
                guideSource.contains("move icon \"SOURCE_ID\" before target icon"),
            "Customer-facing AppleScript examples should not use the invalid prepositional phrase shape"
        )
    }

    func testVisibilityTransitionsInvalidateAndWarmCaches() throws {
        let hidingURL = projectRootURL().appendingPathComponent("Core/Services/HidingService.swift")
        let hidingSource = try String(contentsOf: hidingURL, encoding: .utf8)
        let cacheURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarCacheStore.swift")
        let cacheSource = try String(contentsOf: cacheURL, encoding: .utf8)
        let taskURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let taskSource = try String(contentsOf: taskURL, encoding: .utf8)

        XCTAssertTrue(
            hidingSource.contains("invalidateMenuBarItemCache(scheduleWarmupAfter: .reveal)"),
            "Reveal transitions should schedule a background cache warmup instead of leaving the next interaction cold"
        )
        XCTAssertTrue(
            hidingSource.contains("invalidateMenuBarItemCache(scheduleWarmupAfter: .conceal)"),
            "Hide transitions should also refresh the cache soon after state changes"
        )
        XCTAssertTrue(
            cacheSource.contains("private func scheduleMenuBarCacheWarmup(reason: CacheWarmupReason)"),
            "Accessibility cache invalidation should have a dedicated warmup scheduler"
        )
        XCTAssertTrue(
            cacheSource.contains("if Self.cacheWarmupUsesKnownOwnerRefresh(for: reason)") &&
                cacheSource.contains("await self.refreshKnownMenuBarItemsWithPositions()"),
            "Geometry-only warmups should rebuild positions from known owners instead of defaulting every relayout to a full inventory scan"
        )
        XCTAssertTrue(
            cacheSource.contains("cacheWarmupInFlight"),
            "Accessibility diagnostics should report whether a background cache warmup is running"
        )
        XCTAssertTrue(
            cacheSource.contains("func beginMenuBarCacheWarmupSuppression()") &&
                cacheSource.contains("func endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: Bool = true)"),
            "Accessibility cache warmup control should support suppressing repeated warmups during a single move operation"
        )
        XCTAssertTrue(
            taskSource.contains("AccessibilityService.shared.beginMenuBarCacheWarmupSuppression()") &&
                taskSource.contains("AccessibilityService.shared.endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: false)"),
            "Move tasks should suspend intermediate cache warmups and skip replaying them after the move's explicit cache refresh"
        )
    }

    func testAppleScriptAlwaysHiddenExitsUseRobustUnpinHelpers() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func removeQueuedAlwaysHiddenPin("),
            "Always-hidden exit rollback should flow through one shared helper in the move engine"
        )
        XCTAssertTrue(
            source.contains("!bundleID.hasPrefix(\"com.apple.controlcenter\") && manager.alwaysHiddenPinWorkflow.unpin(bundleID: bundleID)"),
            "Always-hidden exit rollback should still include the non-Control-Center bundle fallback unpin"
        )
    }

    func testMoveEngineLeavesReadersWithAWarmPostMoveCache() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let standardURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let standardSource = try String(contentsOf: standardURL, encoding: .utf8)
        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)
        let cacheURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarCacheStore.swift")
        let cacheSource = try String(contentsOf: cacheURL, encoding: .utf8)
        let scanningURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Scanning.swift")
        let scanningSource = try String(contentsOf: scanningURL, encoding: .utf8)
        let searchURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchURL, encoding: .utf8)
        let classifierURL = projectRootURL().appendingPathComponent("Core/Services/SearchMenuBarZoneClassifier.swift")
        let classifierSource = try String(contentsOf: classifierURL, encoding: .utf8)
        let verifierURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveVerifier.swift")
        let verifierSource = try String(contentsOf: verifierURL, encoding: .utf8)
        let taskURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let taskSource = try String(contentsOf: taskURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func refreshAccessibilityCacheAfterMove() async"),
            "The move engine should own one shared post-move cache refresh helper instead of pushing cache rebuilds onto the next reader"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.invalidateMenuBarItemPositionsCache()") &&
                source.contains("await AccessibilityService.shared.refreshKnownMenuBarItemsWithPositions()"),
            "Post-move cache refresh should rebuild positions from the known owner set before scripts poll zones again"
        )
        XCTAssertTrue(
            cacheSource.contains("func refreshKnownMenuBarItemsWithPositions() async") &&
                cacheSource.contains("return await refreshMenuBarItemsWithPositions()"),
            "Known-owner move refresh should keep a full-scan fallback when the lighter refresh cannot rebuild enough state"
        )
        XCTAssertTrue(
            taskSource.contains("AccessibilityService.shared.endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: false)"),
            "Move completion should skip deferred cache warmups after it already performed an explicit post-move refresh"
        )
        XCTAssertTrue(
            standardSource.contains("await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()") &&
                alwaysHiddenSource.contains("await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()"),
            "Move completion should call the shared post-move refresh helper before returning success"
        )
        XCTAssertTrue(
            standardSource.contains("let shouldPreservePreHideMoveSnapshot = context.success") &&
                standardSource.contains("&& context.request.toHidden") &&
                standardSource.contains("&& context.usedShowAllShield") &&
                standardSource.contains("Capturing regular Hidden move snapshot before re-hide") &&
                standardSource.contains("if !shouldPreservePreHideMoveSnapshot"),
            "Hidden moves performed through the showAll shield should keep the post-drag regular Hidden classification instead of replacing it with a post-hide stale scan"
        )
        XCTAssertTrue(
            verifierSource.contains("let scopedItems = await AccessibilityService.shared.scopedMenuBarItemsWithPositions(for: owners)") &&
                verifierSource.contains("if attempt == attempts") &&
                verifierSource.contains("let classified = await SearchService.shared.refreshClassifiedApps()"),
            "Move verification should use scoped owner scans first and reserve the authoritative full classified refresh for the final fallback"
        )
        XCTAssertTrue(
            scanningSource.contains("func scopedMenuBarItemsWithPositions(for owners: [RunningApp]) async -> [MenuBarItemPosition]"),
            "AccessibilityService should expose a scoped positioned-item scan for targeted verification without clobbering the global cache"
        )
        XCTAssertTrue(
            searchSource.contains("func classifyItemsForVerification(_ items: [AccessibilityService.MenuBarItemPosition]) -> SearchClassifiedApps") &&
                searchSource.contains("classifyItems(items, allowEstimatedFallback: false)"),
            "SearchService should expose direct classification for targeted verification scans without blessing estimated separator geometry"
        )
        XCTAssertTrue(
            classifierSource.contains("strict classification failed closed"),
            "Strict move verification should fail closed instead of falling back to screen-only visible/hidden guesses when separator geometry is missing"
        )
    }

    func testAppleScriptZoneRefreshPrefersKnownOwnerClassificationBeforeFullFallback() throws {
        let commandsSource = try appleScriptCommandSource()
        let searchURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchURL, encoding: .utf8)

        XCTAssertTrue(
            commandsSource.contains("result.value = await SearchService.shared.refreshKnownClassifiedApps()"),
            "AppleScript zone refresh should try the known-owner classified refresh before paying for a full inventory rebuild"
        )
        XCTAssertTrue(
            commandsSource.contains("refreshedIconZones(\n    timeoutSeconds: TimeInterval = 2.5,\n    allowAuthoritativeFallback: Bool = true") &&
                commandsSource.contains("guard allowAuthoritativeFallback else {"),
            "AppleScript zone refresh should be able to skip the authoritative fallback when a plain listing poll can safely wait for the lighter refresh"
        )
        XCTAssertTrue(
            commandsSource.contains("let cacheValiditySeconds = scriptListingCacheValiditySeconds("),
            "Repeated AppleScript zone polling should widen the cache window instead of forcing a rebuild every few seconds"
        )
        XCTAssertFalse(
            commandsSource.contains("Task { @MainActor in\n            _ = await SearchService.shared.refreshClassifiedApps()"),
            "currentIconZones should stay a pure cached snapshot instead of secretly kicking off a second refresh before the explicit listing refresh path runs"
        )
        XCTAssertTrue(
            commandsSource.contains("let coldStart = cached.isEmpty") &&
                commandsSource.contains("timeoutSeconds: coldStart ? 2.5 : 1.2") &&
                commandsSource.contains("allowAuthoritativeFallback: coldStart"),
            "List icon zones should use the lighter known-owner refresh during normal polling but allow authoritative fallback when a relaunch starts with an empty cache"
        )
        XCTAssertTrue(
            commandsSource.contains("retryResult.value = await SearchService.shared.refreshClassifiedApps()"),
            "AppleScript zone refresh should still retain the authoritative full refresh as the fallback"
        )
        XCTAssertTrue(
            commandsSource.contains("final class ListAuthoritativeIconZonesCommand") &&
                commandsSource.contains("authoritativeScriptListingZonesForCommand()") &&
                commandsSource.contains("AccessibilityService.shared.invalidateMenuBarItemPositionsCache()"),
            "Wake proof needs a dedicated authoritative listing command so 1s/5s/15s checks cannot false-green from the normal cached zone listing"
        )
        XCTAssertTrue(
            searchSource.contains("func refreshKnownClassifiedApps() async -> SearchClassifiedApps"),
            "SearchService should expose a lighter classified refresh path for repeated script zone polling"
        )
        XCTAssertTrue(
            searchSource.contains("func refreshKnownClassifiedAppsAllowingEstimatedFallback() async -> SearchClassifiedApps") &&
                searchSource.contains("classifyItems(items, allowEstimatedFallback: true)"),
            "Estimated classification should be an explicit read-only browse path, not the default for AppleScript or persistence"
        )
    }

    func testAuthoritativeZoneListingDoesNotReturnBlankDuringStartupRace() throws {
        let commandsSource = try appleScriptCommandSource()

        XCTAssertTrue(
            commandsSource.contains("let cachedBeforeAuthoritativeRefresh = sortedScriptZones(currentIconZones())"),
            "The authoritative AppleScript listing should keep a pre-refresh fallback so startup races do not return a blank diagnostics surface"
        )
        XCTAssertTrue(
            commandsSource.contains("let authoritativeZones = sortedScriptZones(zones(from: classified))") &&
                commandsSource.contains("if !authoritativeZones.isEmpty") &&
                commandsSource.contains("return authoritativeZones"),
            "The normal path should still prefer the fresh authoritative scan when it returns real rows"
        )
        XCTAssertTrue(
            commandsSource.contains("let warmedZones = sortedScriptZones(currentIconZones())") &&
                commandsSource.contains("if !warmedZones.isEmpty") &&
                commandsSource.contains("return warmedZones"),
            "A transient empty authoritative startup scan should wait for the app's warmed cache before reporting no rows"
        )
        XCTAssertTrue(
            commandsSource.contains("return cachedBeforeAuthoritativeRefresh"),
            "Only the deadline fallback should use the pre-refresh cache; returning a blank listing hides release-diagnostic failures"
        )
    }
}
