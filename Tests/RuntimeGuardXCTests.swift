@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardXCTests: XCTestCase {
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root
    }

    func testNormalizedEventYKeepsAlreadyFlippedMenuBarY() {
        let y = AccessibilityService.normalizedEventY(rawY: 15, globalMaxY: 1440, anchorY: 15)
        XCTAssertEqual(y, 15, accuracy: 0.001)
    }

    func testDuplicateLaunchPolicyTerminatesCurrentWhenAnotherInstanceExists() throws {
        let fileURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("scheduleDuplicateInstanceTerminationCheckIfNeeded()"),
            "Startup path should guard against duplicate app instances"
        )
        XCTAssertTrue(
            source.contains("static func duplicateLaunchResolution(othersAtLaunch: Int, othersAfterGrace: Int?) -> DuplicateLaunchResolution"),
            "Duplicate-launch guard should only terminate when another live instance is detected"
        )
        XCTAssertTrue(
            source.contains("return othersAfterGrace > 0 ? .terminateCurrent : .noConflict"),
            "Duplicate-launch resolution should only terminate when another instance remains after grace period"
        )
        XCTAssertTrue(
            source.contains("NSApp.terminate(nil)"),
            "Duplicate-launch guard should terminate the current launch to prevent dual-runtime corruption"
        )
    }

    func testAppStartupInitializesSingleMenuBarRuntimePath() throws {
        let fileURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("scheduleDuplicateInstanceTerminationCheckIfNeeded()"),
            "Startup should short-circuit when a duplicate SaneBar instance is already running"
        )
        XCTAssertTrue(
            source.contains("NSApp.setActivationPolicy(.accessory)"),
            "SaneBar should configure accessory activation before creating menu bar status items"
        )
        XCTAssertTrue(
            source.contains("_ = MenuBarManager.shared"),
            "Startup should initialize MenuBarManager exactly once from the app delegate path"
        )
    }

    func testNormalizedEventYFlipsUnflippedMenuBarY() {
        let y = AccessibilityService.normalizedEventY(rawY: 1425, globalMaxY: 1440, anchorY: 15)
        XCTAssertEqual(y, 15, accuracy: 0.001)
    }

    func testNormalizedEventYClampsOutOfRangeValues() {
        let y = AccessibilityService.normalizedEventY(rawY: 1451, globalMaxY: 1440, anchorY: 30)
        XCTAssertEqual(y, 1, accuracy: 0.001)
    }

    func testFrameInTargetZoneTreatsNearBoundaryVisibleAsVisible() {
        let frame = CGRect(x: 101, y: 0, width: 22, height: 22) // midX=112
        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: frame,
                separatorX: 100,
                toHidden: false
            )
        )
    }

    func testFrameInTargetZoneTreatsLeftSideAsHidden() {
        let frame = CGRect(x: 60, y: 0, width: 22, height: 22) // midX=71
        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: frame,
                separatorX: 100,
                toHidden: true
            )
        )
    }

    func testDirectionMismatchIgnoredWhenVisibleMoveStartsAlreadyVisible() {
        let before = CGRect(x: 160, y: 0, width: 22, height: 22) // visible
        let after = CGRect(x: 145, y: 0, width: 22, height: 22) // moved left but still visible
        XCTAssertFalse(
            AccessibilityService.hasDirectionMismatch(
                beforeFrame: before,
                afterFrame: after,
                separatorX: 100,
                toHidden: false
            )
        )
    }

    func testDirectionMismatchDetectedWhenVisibleMoveStartsHiddenAndStillMovesLeft() {
        let before = CGRect(x: 60, y: 0, width: 22, height: 22) // hidden
        let after = CGRect(x: 50, y: 0, width: 22, height: 22) // moved farther left
        XCTAssertTrue(
            AccessibilityService.hasDirectionMismatch(
                beforeFrame: before,
                afterFrame: after,
                separatorX: 100,
                toHidden: false
            )
        )
    }

    func testHiddenMoveTargetFormulaPreservesSeparatorAndLaneSafety() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let farHiddenX = separatorX - max(80, iconWidth + 60)"),
            "Hidden-move targeting should branch on always-hidden lane availability"
        )
        XCTAssertTrue(
            source.contains("let minRegularHiddenX = ahBoundary + 2"),
            "Hidden moves should not overshoot left of the lane floor when an always-hidden boundary exists"
        )
        XCTAssertTrue(
            source.contains("guard let ahBoundary = visibleBoundaryX else { return farHiddenX }"),
            "Hidden moves without an always-hidden boundary should keep the direct farHiddenX target"
        )
        XCTAssertTrue(
            source.contains("let maxRegularHiddenX = separatorX - separatorSafety"),
            "Hidden moves should enforce a separator-side safety margin for reliable midpoint verification"
        )
        XCTAssertTrue(
            source.contains("let rightBiasInset = max(6, min(20, iconWidth * 0.45))"),
            "Hidden moves should bias toward the separator-side hidden lane to avoid AH drift after re-hide transitions"
        )
        XCTAssertTrue(
            source.contains("return max(boundedPreferredX, min(max(farHiddenX, minRegularHiddenX), maxRegularHiddenX))"),
            "Hidden move target should stay clamped to lane bounds while preserving far-hidden fallback for wide icons"
        )
    }

    func testVisibleMoveTargetAvoidsBoundaryOvershootInFlushLayout() {
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: 16,
            separatorX: 1663,
            visibleBoundaryX: 1663
        )
        XCTAssertEqual(target, 1661, accuracy: 0.001)
    }

    func testMoveVerificationContainsDirectionGuard() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Move direction mismatch: expected rightward visible move"),
            "Move verification should reject stale-boundary false positives when visible moves drift left"
        )
    }

    func testVisibleAndAlwaysHiddenRetriesReResolveTargets() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Re-resolved visible move targets for retry"),
            "Visible retry path should refresh separator targets before retrying"
        )
        XCTAssertTrue(
            source.contains("Re-resolved always-hidden move targets for retry"),
            "Always-hidden retry path should refresh separator targets before retrying"
        )
        XCTAssertTrue(
            source.contains("Re-resolved AH-to-Hidden targets for retry"),
            "AH-to-Hidden retry path should refresh separator targets before retrying"
        )
        XCTAssertTrue(
            source.contains("Move accepted after classification verification"),
            "Standard move path should reconcile verification failures with classified zones before returning false"
        )
        XCTAssertTrue(
            source.contains("Always-hidden move accepted after classification verification"),
            "Always-hidden move path should reconcile verification failures with classified zones before returning false"
        )
    }

    func testAppleScriptAlwaysHiddenMovesUseStandardMovePath() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("var skipZoneWait = false"),
            "AppleScript move routing should track no-op moves and skip zone wait when no move is needed"
        )
        XCTAssertTrue(
            source.contains("if skipZoneWait {"),
            "No-op move requests should return success without polling for zone convergence"
        )
        XCTAssertTrue(
            source.contains("sourceZone == targetZone"),
            "AppleScript routing should detect when an icon is already in the requested zone"
        )
        XCTAssertTrue(
            source.contains("case .alwaysHidden:\n                        let removedPin = manager.unpinAlwaysHidden"),
            "Always-hidden sources should be unpinned before routing to a standard move"
        )
        XCTAssertTrue(
            source.contains("toHidden: true"),
            "Move-to-hidden should route through standard moveIcon so targeting logic stays consistent"
        )
        XCTAssertTrue(
            source.contains("toHidden: false"),
            "Move-to-visible should route through standard moveIcon so targeting logic stays consistent"
        )
        XCTAssertFalse(
            source.contains("manager.moveIconFromAlwaysHiddenToHidden("),
            "AppleScript move routing should avoid async always-hidden helper starts that can mask failures"
        )
        XCTAssertFalse(
            source.contains("manager.moveIconFromAlwaysHidden("),
            "AppleScript move routing should avoid async always-hidden helper starts that can mask failures"
        )
    }

    func testHiddenStateClassificationUsesPinnedFallbackForAlwaysHidden() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if MenuBarManager.shared.hidingService.state == .hidden {"),
            "Hidden-state classification should not trust live always-hidden separator geometry"
        )
        XCTAssertTrue(
            source.contains("return (separatorX, nil)"),
            "Hidden-state classification should force two-zone split before pinned-ID post-pass"
        )
        XCTAssertTrue(
            source.contains("post-pass moved"),
            "When AH geometry is disabled, pinned IDs should still populate always-hidden classification"
        )
    }

    func testShouldSkipHideForExternalMonitorPolicy() {
        XCTAssertTrue(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: false, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarManager.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: false))
    }

    func testManualHideRequestsAreNotSuppressedByExternalMonitorPolicy() {
        XCTAssertFalse(
            MenuBarManager.shouldIgnoreHideRequest(
                disableOnExternalMonitor: true,
                isOnExternalMonitor: true,
                origin: .manual
            )
        )
    }

    func testAutomaticHideRequestsAreSuppressedByExternalMonitorPolicy() {
        XCTAssertTrue(
            MenuBarManager.shouldIgnoreHideRequest(
                disableOnExternalMonitor: true,
                isOnExternalMonitor: true,
                origin: .automatic
            )
        )
    }

    func testStartupRecoveryTriggersWhenSeparatorIsRightOfMain() {
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 1200,
                mainX: 1100
            )
        )
    }

    func testStartupRecoveryDoesNotTriggerForHealthyOrdering() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100
            )
        )
    }

    func testStartupRecoveryTriggersWhenMainIconIsTooFarFromRightEdge() {
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 900,
                screenWidth: 1440
            )
        )
    }

    func testStartupRecoveryAllowsReasonableRightEdgeGap() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 300,
                screenWidth: 1440
            )
        )
    }

    func testStartupRecoveryTriggersWhenMainIconDriftsIntoNotchDeadZone() {
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1300,
                mainRightGap: 220,
                screenWidth: 1728,
                notchRightSafeMinX: 1450
            )
        )
    }

    func testStartupRecoveryAllowsMainIconInsideNotchSafeRightZone() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1462,
                mainRightGap: 220,
                screenWidth: 1728,
                notchRightSafeMinX: 1450
            )
        )
    }

    func testStartupRecoveryFallsBackToRightGapWhenNoNotchBoundary() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 300,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
    }

    func testStartupRecoveryDoesNotTriggerWithMissingCoordinates() {
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: nil,
                mainX: 1100
            )
        )
        XCTAssertFalse(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: nil
            )
        )
    }

    func testSearchServiceRefreshesTargetAfterReveal() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("await waitForIconOnScreen(app: app)"),
            "SearchService.activate should wait for icon re-layout after reveal (#102)"
        )
        XCTAssertTrue(
            source.contains("resolveLatestClickTarget(for: app, forceRefresh: didReveal)"),
            "SearchService.activate should force-refresh click target identity after reveal (#102)"
        )
    }

    func testSearchServiceDebouncesBackToBackActivationRequests() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("activationDebounceInterval: TimeInterval = 0.45"),
            "SearchService.activate should debounce rapid duplicate requests to prevent panel lockups on double-click"
        )
        XCTAssertTrue(
            source.contains("beginActivationIfAllowed(for: app.uniqueId"),
            "SearchService.activate should pass through shared activation guard logic"
        )
    }

    func testSearchServiceSkipsActivationWhenAnotherActivationIsInFlight() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if let inFlight = activationInFlightAppID"),
            "SearchService.activate should reject overlapping activation workflows while one request is in progress"
        )
    }

    func testSearchServiceRunsClickOffMainAndSkipsSlowRetry() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("withTaskGroup(of: ClickAttemptResult.self)"),
            "SearchService.activate should run click path through a bounded background task group to avoid UI stalls during AX calls"
        )
        XCTAssertTrue(
            source.contains("Click failed after slow attempt; skipping forced-refresh retry"),
            "SearchService.activate should avoid compounding delays by skipping retry after a slow failed click"
        )
        XCTAssertTrue(
            source.contains("Click failed after timeout; skipping forced-refresh retry"),
            "SearchService.activate should skip retry when a click attempt times out to avoid duplicate delayed activations"
        )
        XCTAssertTrue(
            source.contains("shouldPreferHardwareFirst(for app: RunningApp)"),
            "SearchService should expose a hardware-first policy for unstable Apple menu extras (e.g. Spotlight)"
        )
        XCTAssertTrue(
            source.contains("return app.bundleId.hasPrefix(\"com.apple.\")"),
            "SearchService should prefer hardware-first for Apple-owned menu extras that are AX-unstable across macOS builds"
        )
        XCTAssertTrue(
            source.contains("if app.menuExtraIdentifier == nil"),
            "SearchService should prefer hardware-first when a status item lacks stable AX per-item identity"
        )
    }

    func testSearchServiceUsesStableSeparatorOriginForClassificationBoundary() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func separatorBoundaryXForClassification() -> CGFloat?"),
            "SearchService should centralize separator lookup through a dedicated classification helper"
        )
        XCTAssertTrue(
            source.contains("MenuBarManager.shared.getSeparatorRightEdgeX()"),
            "Classification helper should prefer separator right-edge cache for stable hidden/visible partitioning"
        )
        XCTAssertTrue(
            source.contains("MenuBarManager.shared.getSeparatorOriginX()"),
            "Classification helper should use the main separator origin for stable hidden/visible partitioning"
        )
        XCTAssertTrue(
            source.contains("repairAlwaysHiddenSeparatorPositionIfNeeded(reason: \"classification\")"),
            "Classification should attempt separator repair when always-hidden ordering is invalid"
        )
    }

    func testBrowseFlowsAvoidImmediateRehideAndDeferSearchRehideWhileVisible() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+Visibility.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let shouldScheduleImmediateRehide = trigger != .search && trigger != .findIcon"),
            "showHiddenItemsNow should not arm the short rehide timer for Browse Icons flows"
        )
        XCTAssertTrue(
            source.contains("SearchWindowController.shared.isVisible"),
            "Search rehide should defer while Browse Icons is still visible"
        )
    }

    func testAppleScriptMoveVerificationUsesForcedRefreshFallback() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func refreshedIconZones(timeoutSeconds: TimeInterval = 2.5)"),
            "AppleScript move checks should use a longer classified-app refresh window before fallback"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.invalidateMenuBarItemCache()"),
            "AppleScript move verification should invalidate AX cache before fallback refresh"
        )
        XCTAssertTrue(
            source.contains("for _ in 0 ..< 3"),
            "AppleScript move verification should run bounded forced-refresh retries before declaring failure"
        )
    }

    func testAppleScriptMoveResolutionRefreshesWhenCachedZonesMiss() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let startZones = zonesForScriptResolution(trimmedId)"),
            "AppleScript moves should escalate from cached zones to a refreshed classification snapshot before declaring not-found"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.invalidateMenuBarItemCache()"),
            "AppleScript move resolution should invalidate the AX cache before the refreshed lookup"
        )
    }

    func testAppleScriptMoveCommandsWaitOnMoveTasks() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let movingURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let movingSource = try String(contentsOf: movingURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let moved = runScriptMove {"),
            "AppleScript move commands should block on the real move task instead of fire-and-forget polling"
        )
        XCTAssertTrue(
            source.contains("await manager.moveIconAndWait("),
            "AppleScript visible/hidden moves should wait on the standard move task"
        )
        XCTAssertTrue(
            source.contains("await manager.moveIconAlwaysHiddenAndWait("),
            "AppleScript always-hidden moves should wait on the dedicated always-hidden move task"
        )
        XCTAssertTrue(
            movingSource.contains("func moveIconAlwaysHiddenAndWait("),
            "MenuBarManager should expose an awaitable always-hidden move helper for AppleScript command reliability"
        )
    }

    func testAppleScriptAlwaysHiddenExitsUseRobustUnpinHelpers() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("manager.unpinAlwaysHidden("),
            "AppleScript always-hidden exits should unpin through robust helper paths, not exact-ID only removal"
        )
        XCTAssertTrue(
            source.contains("manager.unpinAlwaysHidden(bundleID: icon.bundleId)"),
            "AppleScript always-hidden exits should include non-Control-Center bundle fallback unpin"
        )
    }

    func testMoveIconClearsStaleAlwaysHiddenPinsForVisibleMovesAndAfterHiddenMoves() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !toHidden {"),
            "Pre-move stale-pin cleanup should run only for move-to-visible paths"
        )
        XCTAssertTrue(
            source.contains("removedPin = unpinAlwaysHidden("),
            "moveIcon should clear stale always-hidden pins through targeted unpin helpers"
        )
        XCTAssertTrue(
            source.contains("Cleared stale always-hidden pin before move-to-visible"),
            "Visible move pre-clear should emit an explicit log marker"
        )
        XCTAssertTrue(
            source.contains("if success, toHidden {"),
            "Hidden moves should defer stale-pin cleanup until after successful drag completion"
        )
        XCTAssertTrue(
            source.contains("Cleared stale always-hidden pin after successful move-to-hidden"),
            "Hidden move deferred cleanup should emit an explicit post-move log marker"
        )
    }

    func testMoveIconUsesShieldFallbackWhenHiddenMoveFailsOutsideHiddenState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !success && toHidden && !usedShowAllShield"),
            "Hidden moves that fail while state appears expanded should trigger a shield fallback retry"
        )
        XCTAssertTrue(
            source.contains("await hidingService.showAll()"),
            "Shield fallback should force showAll before recomputing move targets"
        )
        XCTAssertTrue(
            source.contains("let restoreShieldIfNeeded = { () async in"),
            "moveIcon should centralize shield restoration so fallback retries cannot leave geometry half-transitioned"
        )
    }

    func testHiddenMoveTargetResolutionRepairsStaleSeparatorOriginFromRightEdge() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let derivedFromRightEdge: CGFloat? = {"),
            "Hidden-target resolution should derive separator origin from right-edge cache for stale-frame recovery"
        )
        XCTAssertTrue(
            source.contains("if origin + 40 < derivedFromRightEdge"),
            "Hidden-target resolution should detect implausibly-left origin values after transitions"
        )
        XCTAssertTrue(
            source.contains("Hidden move target corrected from stale origin"),
            "Hidden-target repair should emit an explicit log marker for stale-origin corrections"
        )
        XCTAssertTrue(
            source.contains("Hidden move target drifted too far left"),
            "Hidden-target resolution should reject implausible separator drift and re-resolve under shield"
        )
        XCTAssertTrue(
            source.contains("separatorOverrideX == nil"),
            "Hidden-target drift guard must not run for always-hidden separator overrides"
        )
        XCTAssertTrue(
            source.contains("getAlwaysHiddenSeparatorBoundaryX()"),
            "Always-hidden move targeting should use AH right-edge boundary, not AH origin"
        )
        XCTAssertTrue(
            source.contains("AH separator boundary for hidden target"),
            "Hidden move target resolution should log AH boundary usage from the boundary helper"
        )
        XCTAssertTrue(
            source.contains("Ignoring AH boundary >= separator during hidden move target resolution"),
            "Hidden move target resolution should reject invalid AH boundaries that overlap the main separator"
        )
    }

    func testSearchClassificationUsesAlwaysHiddenBoundaryRightEdge() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("getAlwaysHiddenSeparatorBoundaryX()"),
            "Search classification should use AH boundary/right-edge for zone splits near the AH divider"
        )
    }

    func testAccessibilityClickSkipsAXPressForOffscreenItems() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !isElementOnScreen(item)"),
            "clickMenuBarItem should gate AXPress behind on-screen checks (#102)"
        )
        XCTAssertTrue(
            source.contains("Target item off-screen; skipping AXPress, using hardware click"),
            "Off-screen targets should route to hardware fallback (#102)"
        )
        XCTAssertTrue(
            source.contains("using immediate spatial center"),
            "Hardware fallback should use an immediate on-screen spatial click before expensive AX frame polling"
        )
        XCTAssertTrue(
            source.contains("attempts: 10"),
            "Hardware click fallback should use bounded AX frame polling to prevent long UI stalls"
        )
    }

    func testSearchWindowForcesDarkColorSchemeAtSwiftUIBoundary() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(".preferredColorScheme(.dark)"),
            "Search windows should force dark color scheme so Icon Panel text stays readable in light mode (#85)"
        )
    }

    func testSearchWindowReappliesDarkAppearanceWhenShown() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("applyDarkAppearance(to: window)"),
            "Search window show() should reapply dark appearance before display to avoid washed-out panel state (#85)"
        )
        XCTAssertTrue(
            source.contains("window.contentView?.appearance = dark"),
            "Dark appearance must propagate to the hosted content view to keep SwiftUI/AppKit in sync (#85)"
        )
    }

    func testSearchWindowUsesExplicitClosePolicy() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func windowDidResignKey"),
            "SearchWindowController should still observe resign-key transitions"
        )
        XCTAssertTrue(
            source.contains("click-triggered dismissals while launching icons/popovers"),
            "SearchWindowController should keep search panels open when focus shifts during icon activation"
        )
        XCTAssertFalse(
            source.contains("resignCloseTask = Task"),
            "windowDidResignKey should not schedule delayed auto-close tasks"
        )
    }

    func testSearchWindowCloseSchedulesDeferredRehideWhenExpanded() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let dismissDelaySeconds = browseDismissRehideDelay(baseDelay: manager.settings.rehideDelay)"),
            "Closing Browse Icons should use standard auto-rehide timing when dismissing the panel"
        )
        XCTAssertTrue(
            source.contains("manager.hidingService.scheduleRehide(after: dismissDelaySeconds)"),
            "Closing Browse Icons should arm rehide directly after panel dismissal"
        )
        XCTAssertTrue(
            source.contains("refreshMouseInMenuBarStateForBrowseDismissal()"),
            "Browse panel dismissal should refresh hover state using strict strip bounds so rehide does not get stuck near the menu bar"
        )
        XCTAssertTrue(
            source.contains("scheduleForceRehideAfterBrowseDismissal(mode: currentMode, baseDelay: dismissDelaySeconds, reason: reason)"),
            "Browse panel dismissal should arm a bounded fallback hide window so expanded bars cannot remain stuck open indefinitely"
        )
        XCTAssertTrue(
            source.contains("let fallbackDelaySeconds = fallbackRehideDelay(for: mode, baseDelay: baseDelay)"),
            "Fallback rehide timing should derive from a bounded helper so second menu bar closes do not feel stuck open"
        )
        XCTAssertTrue(
            source.contains("private func browseDismissRehideDelay(baseDelay: TimeInterval) -> TimeInterval"),
            "SearchWindowController should normalize panel-dismiss rehide timing in one helper"
        )
        XCTAssertTrue(
            source.contains("private func fallbackRehideDelay(for mode: SearchWindowMode?, baseDelay: TimeInterval) -> TimeInterval"),
            "SearchWindowController should centralize fallback rehide timing in a dedicated helper"
        )
        XCTAssertTrue(
            source.contains("return min(20, max(12, normalizedBase + 4))"),
            "Second menu bar fallback should stay permissive but bounded"
        )
        XCTAssertTrue(
            source.contains("return min(12, max(8, normalizedBase + 2))"),
            "Find Icon fallback should remain shorter and bounded"
        )
        XCTAssertTrue(
            source.contains("await manager.hidingService.hide()"),
            "Fallback rehide should force-hide expanded bars once the bounded grace window expires"
        )
        XCTAssertTrue(
            source.contains("private(set) var isBrowseSessionActive = false"),
            "SearchWindowController should track browse session state explicitly for reliable fire-time rehide gating"
        )
        XCTAssertTrue(
            source.contains("isBrowseSessionActive = true"),
            "Showing a browse panel should mark the session active before interaction begins"
        )
        XCTAssertTrue(
            source.contains("isBrowseSessionActive = false"),
            "Browse dismissal/reset paths should clear session-active state"
        )
    }

    func testFireTimeRehideGuardAllowsBrowseWhenHoverMonitoringIsSuspended() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+Visibility.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func canAutoRehideAtFireTime() -> Bool"),
            "MenuBarManager should centralize fire-time rehide guard logic in a dedicated helper"
        )
        XCTAssertTrue(
            source.contains("if hoverService.isSuspended"),
            "Rehide guard should explicitly allow auto-rehide while Browse Icons intentionally suspends hover monitoring"
        )
    }

    func testAppMenuSuppressionUsesClassifiedVisibleAndHiddenLanes() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+Visibility.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let classified = await SearchService.shared.refreshClassifiedApps()"),
            "App menu suppression should evaluate overlap from the latest classified zones"
        )
        XCTAssertTrue(
            source.contains("(classified.visible + classified.hidden)"),
            "App menu suppression should consider visible + hidden lanes so overflowed hidden icons trigger overlap recovery"
        )
        XCTAssertTrue(
            source.contains(".compactMap(\\.xPosition)"),
            "App menu suppression should use RunningApp xPosition values from classification snapshots"
        )
    }

    func testRehideTimerUsesGenerationGuardToPreventStaleHideFires() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/HidingService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private var rehideGeneration: UInt64 = 0"),
            "HidingService should track rehide timer generations so stale tasks cannot fire after cancellation/replacement"
        )
        XCTAssertTrue(
            source.contains("guard generation == self.rehideGeneration else { return }"),
            "Rehide timer tasks should validate generation before executing guard/hide logic"
        )
        XCTAssertTrue(
            source.contains("rehideGeneration &+= 1"),
            "Scheduling/canceling rehide should invalidate prior generations"
        )
    }

    func testFireTimeRehideGuardBlocksWhileBrowsePanelOrMoveIsActive() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+Visibility.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if browseController.isVisible"),
            "Fire-time rehide guard should block auto-hide whenever a browse panel is visible"
        )
        XCTAssertTrue(
            source.contains("if browseController.isMoveInProgress"),
            "Fire-time rehide guard should block auto-hide while icon drag move is in progress"
        )
    }

    func testIconMovePipelinesCancelPendingRehideBeforeDragWork() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("cancelRehide()"),
            "Move pipelines should cancel any pending rehide timer before drag simulation begins"
        )

        // Guard against formatting churn by validating the intent per pipeline:
        // each detached move/reorder task should cancel rehide before drag work.
        let pipelinePatterns = [
            #"func\s+moveIcon\([\s\S]*?activeMoveTask\s*=\s*Task\.detached[\s\S]*?cancelRehide\(\)"#,
            #"func\s+moveIconAlwaysHidden\([\s\S]*?activeMoveTask\s*=\s*Task\.detached[\s\S]*?cancelRehide\(\)"#,
            #"func\s+moveIconFromAlwaysHiddenToHidden\([\s\S]*?activeMoveTask\s*=\s*Task\.detached[\s\S]*?cancelRehide\(\)"#,
            #"func\s+reorderIcon\([\s\S]*?activeMoveTask\s*=\s*Task\.detached[\s\S]*?cancelRehide\(\)"#,
        ]

        for pattern in pipelinePatterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(source.startIndex ..< source.endIndex, in: source)
            XCTAssertGreaterThan(
                regex.numberOfMatches(in: source, range: range),
                0,
                "Detached move/reorder pipeline must cancel rehide before drag simulation"
            )
        }
    }

    func testBrowsePanelShowSuspendsRehideWhileVisible() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("browse panel show (\\(String(describing: desiredMode), privacy: .public)) suspended rehide while panel is visible"),
            "Browse panel show should suspend rehide so panel interactions don't race against hide transitions"
        )
        XCTAssertTrue(
            source.contains("manager.hidingService.cancelRehide()"),
            "Browse panel show should cancel active rehide timers while the panel remains open"
        )
    }

    func testAutomationShowPathDoesNotPinRevealState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+Visibility.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)

        let automationPattern = #"func\s+showHiddenItems\(\)\s*\{[\s\S]*?showHiddenItemsNow\(trigger:\s*\.automation\)"#
        let automationRegex = try NSRegularExpression(pattern: automationPattern)
        XCTAssertGreaterThan(
            automationRegex.numberOfMatches(in: source, range: range),
            0,
            "Automation/script reveal path should use non-pinned automation trigger so auto-rehide remains active"
        )

        let pinnedPattern = #"func\s+showHiddenItems\(\)\s*\{[\s\S]*?showHiddenItemsNow\(trigger:\s*\.settingsButton\)"#
        let pinnedRegex = try NSRegularExpression(pattern: pinnedPattern)
        XCTAssertEqual(
            pinnedRegex.numberOfMatches(in: source, range: range),
            0,
            "Automation/script reveal path must not use pinned settings-button trigger"
        )
    }

    func testQAGateTreatsDoesNotFunctionAsRegressionLikeIssue() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("/does not function|doesn't function|doesnt function/"),
            "Open regression guardrails should detect issue titles that say an interaction 'does not function'"
        )
        XCTAssertTrue(
            source.contains("/nothing seems to happen|nothing happens/"),
            "Open regression guardrails should detect issue titles that describe no-op interactions"
        )
    }

    func testMoveAndPinFlowsUseLiveHidingServiceState() throws {
        let movingURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let movingSource = try String(contentsOf: movingURL, encoding: .utf8)
        XCTAssertTrue(
            movingSource.contains("let wasHidden = hidingService.state == .hidden"),
            "Icon move flows should use live hidingService.state to avoid stale hidingState races during fast transitions"
        )
        XCTAssertFalse(
            movingSource.contains("let wasHidden = hidingState == .hidden"),
            "Icon move flows should not rely on cached hidingState for hidden/expanded checks"
        )

        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+AlwaysHidden.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)
        XCTAssertTrue(
            alwaysHiddenSource.contains("let wasHidden = hidingService.state == .hidden"),
            "Always-hidden pin enforcement should use live hidingService.state for restore/hide decisions"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("getAlwaysHiddenSeparatorBoundaryX() ?? getAlwaysHiddenSeparatorOriginX()"),
            "Pin reconciliation should prefer AH boundary (right edge) so auto-pin/unpin decisions match zone classification"
        )
    }

    func testHiddenOriginMovePathUsesDirectHideBeforeRestoreFallback() throws {
        let movingURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: movingURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if wasHidden, !shouldSkipHide"),
            "Hidden-origin move restore path should branch explicitly on wasHidden + external monitor policy"
        )
        XCTAssertTrue(
            source.contains("Move complete - direct hide from showAll state"),
            "Hidden-origin move restore path should return directly to hidden before restore fallback"
        )
        XCTAssertTrue(
            source.contains("await self.hidingService.restoreFromShowAll()"),
            "Restore fallback must remain for expanded-return paths and external-monitor skip-hide policy"
        )
    }

    func testIconPanelForcesAlwaysHiddenWhenNeeded() {
        XCTAssertTrue(
            SearchWindowController.shouldForceAlwaysHiddenForIconPanel(
                mode: .findIcon,
                isPro: true,
                useSecondMenuBar: false,
                alwaysHiddenEnabled: false
            )
        )
    }

    func testIconPanelDoesNotForceAlwaysHiddenForFreeUsers() {
        XCTAssertFalse(
            SearchWindowController.shouldForceAlwaysHiddenForIconPanel(
                mode: .findIcon,
                isPro: false,
                useSecondMenuBar: false,
                alwaysHiddenEnabled: false
            )
        )
    }

    func testSecondMenuBarDoesNotForceAlwaysHidden() {
        XCTAssertFalse(
            SearchWindowController.shouldForceAlwaysHiddenForIconPanel(
                mode: .secondMenuBar,
                isPro: true,
                useSecondMenuBar: true,
                alwaysHiddenEnabled: false
            )
        )
    }

    func testRightClickPathAttemptsAXShowMenuBeforeHardwareFallback() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if isRightClick {"),
            "Right-click path should be explicit in performSmartPress"
        )
        XCTAssertTrue(
            source.contains("performShowMenu(on: element)"),
            "Right-click path should attempt AXShowMenu before forcing hardware click"
        )
        XCTAssertTrue(
            source.contains("let restorePoint: CGPoint? = isRightClick ? nil : currentCGEventMousePoint()"),
            "Hardware fallback should restore cursor after left-click to avoid pointer jumps"
        )
    }

    func testStartupExternalMonitorPolicyRunsBeforeInitialHide() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        guard let skipIndex = source.range(of: "if self.shouldSkipHideForExternalMonitor"),
              let hideIndex = source.range(of: "await self.hidingService.hide()")
        else {
            XCTFail("Startup external-monitor or initial-hide blocks not found")
            return
        }

        XCTAssertLessThan(
            skipIndex.lowerBound.utf16Offset(in: source),
            hideIndex.lowerBound.utf16Offset(in: source),
            "Startup should apply external-monitor policy before attempting initial hide"
        )
    }

    func testStartupPositionValidationRetriesBeforeAutosaveRecovery() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let maxAttempts = 4"),
            "Startup position validation should retry before escalating to autosave recovery"
        )
        XCTAssertTrue(
            source.contains("Status item remained off-menu-bar after"),
            "Autosave recovery should only run after repeated validation failures"
        )
        XCTAssertTrue(
            source.contains("Status item position validation recovered after"),
            "Startup validation should log successful transient recovery without bumping autosave version"
        )
    }

    func testStartupHideContinuesWhenAccessibilityPermissionIsMissing() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Accessibility permission not granted at startup — continuing initial hide"),
            "Startup should still hide at launch even when Accessibility trust is temporarily unavailable"
        )
        XCTAssertFalse(
            source.contains("startupDeferredPermissionGrant"),
            "Launch-time permission callbacks should not trigger pin drag automation"
        )
        XCTAssertFalse(
            source.contains("await self.enforceAlwaysHiddenPinnedItems(reason: \"startup\")"),
            "Startup should not run always-hidden pin enforcement before initial hide"
        )
        XCTAssertFalse(
            source.contains("Skipping initial hide: accessibility permission not granted"),
            "Legacy startup skip behavior should be removed to prevent stuck-open launch regressions"
        )
    }

    func testSearchViewOnlyForcesLiveAccessibilityProbeOnRetry() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func syncAccessibilityState() -> Bool"),
            "Search view should centralize accessibility trust checks in one sync helper"
        )
        XCTAssertTrue(
            source.contains("let liveStatus = forceProbe ?"),
            "Accessibility sync helper should perform a live trust probe when state is refreshed"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.requestAccessibility(promptUser: promptUser)"),
            "Accessibility sync helper should perform a live trust probe when state is refreshed"
        )
        XCTAssertTrue(
            source.contains("Button(\"Try Again\") {"),
            "Search view should expose a retry CTA in the accessibility prompt"
        )
        XCTAssertTrue(
            source.contains("syncAccessibilityState(forceProbe: true, promptUser: true)"),
            "Retry CTA should re-run accessibility synchronization before continuing"
        )
    }

    func testSearchViewSchedulesDeferredFollowupRefreshAfterMoveEvent() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("schedulePostMoveFollowupRefresh()"),
            "Move notifications should schedule a deferred follow-up refresh to converge post-drag classification"
        )
        XCTAssertTrue(
            source.contains("private func schedulePostMoveFollowupRefresh()"),
            "Search view should centralize delayed post-move refresh behavior in a dedicated helper"
        )
        XCTAssertTrue(
            source.contains("try? await Task.sleep(for: .milliseconds(320))"),
            "Deferred post-move refresh should wait briefly for WindowServer/AX geometry to settle"
        )
        XCTAssertTrue(
            source.contains("postMoveRefreshTask?.cancel()"),
            "Deferred post-move refresh must cancel previous scheduled work to avoid refresh pileups"
        )
        XCTAssertTrue(
            source.contains("SearchWindowController.iconMoveDidFinishNotification"),
            "Search view should refresh once more when move-in-progress fully clears"
        )
    }

    func testBrowseModeSwitchTransitionsVisiblePanelToNewMode() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/Settings/GeneralSettingsView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let wasBrowseVisible = SearchWindowController.shared.isVisible"),
            "Settings mode switch should detect whether a browse panel is currently visible"
        )
        XCTAssertTrue(
            source.contains("let nextMode: SearchWindowMode = useSecondMenuBar ? .secondMenuBar : .findIcon"),
            "Settings mode switch should compute the target browse mode explicitly"
        )
        XCTAssertTrue(
            source.contains("SearchWindowController.shared.transition(to: nextMode)"),
            "Switching while visible should keep browse open by transitioning to the new mode"
        )
    }

    func testSearchWindowResetWindowRestoresRehideWhenVisible() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let wasVisible = window?.isVisible == true"),
            "resetWindow should detect visible-panel resets"
        )
        XCTAssertTrue(
            source.contains("let dismissDelaySeconds = browseDismissRehideDelay(baseDelay: manager.settings.rehideDelay)"),
            "Visible reset should derive panel-dismiss rehide from standard auto-rehide timing"
        )
        XCTAssertTrue(
            source.contains("manager.hidingService.scheduleRehide(after: dismissDelaySeconds)"),
            "Visible reset should re-arm rehide so hidden icons don't stay stuck open"
        )
        XCTAssertTrue(
            source.contains("func transition(to mode: SearchWindowMode)"),
            "SearchWindowController should expose explicit mode transition support"
        )
    }

    func testSearchWindowWindowWillCloseRestoresRehide() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func handleBrowseDismissal(reason: String)"),
            "SearchWindowController should centralize panel-close teardown in a dedicated helper"
        )
        XCTAssertTrue(
            source.contains("handleBrowseDismissal(reason: \"windowWillClose\")"),
            "windowWillClose should run the same teardown path so titlebar closes re-arm auto-rehide"
        )
    }

    func testSearchWindowPanelIdleTimeoutClosesAndQuickRehides() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let idleDelaySeconds: TimeInterval = (mode == .findIcon) ? 10 : 20"),
            "Browse panel idle timeout should use mode-specific defaults (10s icon panel, 20s second menu bar)"
        )
        XCTAssertTrue(
            source.contains("window.frame.contains(NSEvent.mouseLocation)"),
            "Idle timeout should defer when the pointer is still inside the panel"
        )
        XCTAssertTrue(
            source.contains("manager.hidingService.scheduleRehide(after: 0.2)"),
            "Idle timeout close should force a short rehide delay so the menu bar does not stay expanded"
        )
    }

    func testPostRevealClickPathAvoidsImmediateSpatialFallback() throws {
        let searchServiceURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchServiceURL, encoding: .utf8)
        let interactionURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let interactionSource = try String(contentsOf: interactionURL, encoding: .utf8)

        XCTAssertTrue(
            searchSource.contains("allowImmediateFallbackCenter: !didReveal"),
            "Post-reveal click attempts should disable immediate spatial fallback so hardware clicks poll the live icon frame"
        )
        XCTAssertTrue(
            searchSource.contains("allowImmediateFallbackCenter: false"),
            "Forced-refresh click retries should continue to avoid immediate spatial fallback"
        )
        XCTAssertTrue(
            interactionSource.contains("allowImmediateFallbackCenter: Bool = true"),
            "Accessibility click path should expose an explicit immediate-fallback gate"
        )
        XCTAssertTrue(
            interactionSource.contains("if allowImmediateFallbackCenter,"),
            "Immediate spatial fallback should be gated so reveal-time clicks can require live frame polling"
        )
    }

    func testSecondMenuBarShowForcesFreshScanAndRelayout() throws {
        let searchViewURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let searchViewSource = try String(contentsOf: searchViewURL, encoding: .utf8)
        let controllerURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let controllerSource = try String(contentsOf: controllerURL, encoding: .utf8)

        XCTAssertTrue(
            searchViewSource.contains("refreshApps(force: isSecondMenuBar)"),
            "Second menu bar show/reopen should force a fresh AX scan instead of trusting cached app lists"
        )
        XCTAssertTrue(
            searchViewSource.contains("SearchWindowController.shared.refitSecondMenuBarWindowIfNeeded()"),
            "Second menu bar refreshes should refit the window after real data arrives so the panel doesn't stay undersized"
        )
        XCTAssertTrue(
            controllerSource.contains("func refitSecondMenuBarWindowIfNeeded()"),
            "SearchWindowController should expose an explicit second-menu-bar refit hook"
        )
        XCTAssertTrue(
            controllerSource.contains("scheduleDeferredSecondMenuBarRelayoutIfNeeded()"),
            "Second menu bar show should schedule deferred relayout passes while WindowServer geometry settles"
        )
    }

    func testLegacyUpgradePathDoesNotAutoGrantProFromSettingsState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Legacy upgrade detected — showing freemium intro (manual grant only)"),
            "Legacy upgrade path should be explicit/manual for Pro grants"
        )
        XCTAssertFalse(
            source.contains("grantEarlyAdopterPro()"),
            "MenuBarManager should not auto-grant Pro based only on local settings flags"
        )
    }

}
