@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardXCTests: XCTestCase {
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root
    }

    private func saneAppsRootURL() -> URL {
        projectRootURL()
            .deletingLastPathComponent() // apps/
            .deletingLastPathComponent() // SaneApps/
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

    func testMenuBarManagerDefersStatusBarControllerCreationUntilDeferredUISetup() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private var statusBarControllerStorage: StatusBarController?"),
            "MenuBarManager should keep the default StatusBarController lazy until deferred UI setup"
        )
        XCTAssertTrue(
            source.contains("let statusBarController = ensureStatusBarController()"),
            "MenuBarManager should only create the default StatusBarController inside setupStatusItem"
        )
        XCTAssertTrue(
            source.contains("StatusBarController.validateStartupItems("),
            "Startup validation should require both the main icon and separator to attach to real status-item windows"
        )
        XCTAssertFalse(
            source.contains("self.statusBarController = statusBarController ?? StatusBarController()"),
            "MenuBarManager should not eagerly create status items during init before the deferred startup delay"
        )
        XCTAssertTrue(
            source.contains("statusItemsNeedRecovery()"),
            "Runtime position validation should reuse geometry-aware recovery checks instead of only verifying menu-bar attachment"
        )
        XCTAssertTrue(
            source.contains("lastKnownSeparatorRightEdgeX = nil"),
            "Recreating status items from persisted layout should invalidate cached separator edges first"
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
            source.contains("let wideAlwaysHiddenThreshold: CGFloat = 56"),
            "Hidden moves without an always-hidden boundary should recognize wide menu extras that need a deeper drag target"
        )
        XCTAssertTrue(
            source.contains("let wideAlwaysHiddenOffset = max(180, (iconWidth * 3) + 30)"),
            "Wide menu extras should get a deeper always-hidden drag target than the normal far-hidden fallback"
        )
        XCTAssertTrue(
            source.contains("let minRegularHiddenX = ahBoundary + 2"),
            "Hidden moves should not overshoot left of the lane floor when an always-hidden boundary exists"
        )
        XCTAssertTrue(
            source.contains("guard let ahBoundary = visibleBoundaryX else {") &&
                source.contains("return farHiddenX"),
            "Hidden moves without an always-hidden boundary should still keep the direct farHiddenX target for normal-width icons"
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

    func testVisibleMoveTargetUsesInsertionOverlapInFlushLayout() {
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: 16,
            separatorX: 1663,
            visibleBoundaryX: 1663
        )
        XCTAssertEqual(target, 1669, accuracy: 0.001)
    }

    func testVisibleMoveTargetUsesInsertionOverlapForWideIconInTightGap() {
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: 40,
            separatorX: 1249,
            visibleBoundaryX: 1251
        )
        XCTAssertEqual(target, 1265, accuracy: 0.001)
    }

    func testAlwaysHiddenMoveTargetUsesSeparatorAdjacentInsertion() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("case .alwaysHidden:") &&
                source.contains("return separatorX - moveOffset"),
            "Always-hidden moves should use a dedicated separator-adjacent target instead of reusing the deeper generic hidden-lane target"
        )

        let target = AccessibilityService.moveTargetX(
            targetLane: .alwaysHidden,
            iconWidth: 22,
            separatorX: 828,
            visibleBoundaryX: nil
        )
        XCTAssertEqual(target, 786, accuracy: 0.001)
    }

    func testMoveVerificationContainsDirectionGuard() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Move direction mismatch: expected rightward visible move"),
            "Move verification should reject stale-boundary false positives when visible moves drift left"
        )
        XCTAssertTrue(
            source.contains("let insertionOverlap = max(6, min(18, iconWidth * 0.35))"),
            "Visible move targeting should deliberately overlap SaneBar a little on tight layouts so wide icons actually cross into the visible zone"
        )
        XCTAssertTrue(
            source.contains("return max(separatorX + 1, boundary + insertionOverlap)"),
            "Visible move targeting should use insertion overlap instead of boundary-hugging targets when there is no inline space"
        )
    }

    func testVisibleAndAlwaysHiddenRetriesReResolveTargets() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let retryTargets = await self.resolveMoveTargetsWithRetries("),
            "Standard retry path should refresh move targets before retrying"
        )
        XCTAssertTrue(
            source.contains("let retryLabel = toHidden ? \"hidden\" : \"visible\""),
            "Standard retry path should label hidden and visible re-resolution distinctly in logs"
        )
        XCTAssertTrue(
            source.contains("Re-resolved \\(retryLabel) move targets for retry"),
            "Standard retry path should log the re-resolved target set for both hidden and visible retries"
        )
        XCTAssertFalse(
            source.contains("if !toHidden {\n                    let retryTargets"),
            "Standard retry path should not special-case visible moves when refreshing targets"
        )
        XCTAssertTrue(
            source.contains("Re-resolved always-hidden move targets for retry"),
            "Always-hidden retry path should refresh separator targets before retrying"
        )
        XCTAssertTrue(
            source.contains("Waiting for live always-hidden separator geometry before move target acceptance"),
            "Always-hidden moves should wait for live AH separator geometry before trusting cached drag targets"
        )
        XCTAssertTrue(
            source.contains("let (separatorX, visibleBoundaryX) = await self.resolveAlwaysHiddenMoveTargetsWithRetries("),
            "Always-hidden move pipelines should use the dedicated always-hidden target resolver instead of a one-shot separator lookup"
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

    func testMoveTargetResolutionWaitsForLiveSeparatorFrame() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let liveSeparatorReady = separatorOverrideX != nil || self.currentLiveSeparatorFrame() != nil"),
            "Move target resolution should wait for a live separator window when the main separator should already be visible"
        )
        XCTAssertTrue(
            source.contains("Waiting for live separator frame or an on-screen precise source icon before accepting cached move target"),
            "Visible moves should keep polling until the separator is live or the source icon is safely on-screen with a precise identity"
        )
        XCTAssertTrue(
            source.contains("Accepting cached visible move target because source icon is already on-screen with a precise identity"),
            "Visible moves should have a narrow fallback for precise on-screen items when the separator frame is still stale"
        )
    }

    func testAppleScriptAlwaysHiddenMovesUseStandardMovePath() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let alwaysHiddenVisibleBranch = """
                    case .alwaysHidden:
                        let removedPin = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        if removedPin {
                            manager.saveSettings()
                        }
                        let moved = runScriptMove {
                            await manager.moveIconAlwaysHiddenAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toAlwaysHidden: false
                            )
                        }
        """

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
            "Always-hidden sources should be unpinned before routing to a move helper"
        )
        XCTAssertTrue(
            source.contains("await manager.moveIconFromAlwaysHiddenToHiddenAndWait("),
            "Always-hidden to hidden should use the dedicated helper so showAll runs even when the bar is merely expanded"
        )
        XCTAssertTrue(
            source.contains("await manager.moveIconAlwaysHiddenAndWait(") &&
                source.contains("toAlwaysHidden: false"),
            "Always-hidden to visible should use the dedicated helper so showAll runs even when the bar is merely expanded"
        )
        XCTAssertFalse(
            alwaysHiddenVisibleBranch.contains("moveIconAndWait("),
            "Always-hidden to visible should not route through the standard move helper"
        )
        XCTAssertFalse(
            source.contains("manager.moveIconFromAlwaysHidden("),
            "AppleScript move routing should avoid the fire-and-forget always-hidden visible helper"
        )
    }

    func testHiddenStateClassificationUsesPinnedFallbackForAlwaysHidden() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("shouldUsePinnedAlwaysHiddenFallback"),
            "Hidden and browse-session classification should centralize the pinned-ID fallback policy"
        )
        XCTAssertTrue(
            source.contains("return (separatorX, nil)"),
            "Pinned-ID fallback should force two-zone split before the always-hidden post-pass"
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
                mainRightGap: 220,
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
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 300,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
    }

    func testStartupRecoveryTriggersForAirStyleRightGapDrift() {
        XCTAssertTrue(
            MenuBarManager.shouldRecoverStartupPositions(
                separatorX: 1050,
                mainX: 1219,
                mainRightGap: 251,
                screenWidth: 1470,
                notchRightSafeMinX: 825
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
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchService+Diagnostics.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("await waitForIconOnScreen(app: app)"),
            "SearchService.activate should wait for icon re-layout after reveal (#102)"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("static func shouldForceFreshTargetResolution"),
            "SearchService should centralize reveal/browse-session refresh policy (#102/#105)"
        )
        XCTAssertTrue(
            source.contains("forceRefresh: forceFreshTargetResolution"),
            "SearchService.activate should force-refresh click target identity after reveal or browse-session activation (#102/#105)"
        )
        XCTAssertTrue(
            source.contains("app: initialTarget"),
            "SearchService.activate should derive hardware-vs-AX click strategy from the resolved target identity so second-menu-bar clicks do not reuse stale off-screen requested coordinates (#101)"
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
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchService+Diagnostics.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)

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
            diagnosticsSource.contains("shouldPreferHardwareFirst("),
            "SearchService should expose a reusable hardware-vs-AX policy helper"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("shouldUseWorkspaceActivationFallback("),
            "SearchService should centralize workspace-fallback policy so browse-panel right-click failures do not steal focus"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("MenuBarOperationCoordinator.browseActivationPlan("),
            "Browse activation policy should route through the shared runtime coordinator instead of being rebuilt inline"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("if origin == .browsePanel, let xPosition = app.xPosition, xPosition >= 0"),
            "Browse-panel left clicks should prefer AX first for on-screen targets so Spotlight-like items do not burn the timeout budget on failed hardware attempts"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("if app.menuExtraIdentifier == nil"),
            "Direct activation should still prefer hardware-first when a status item lacks stable AX per-item identity"
        )
        XCTAssertTrue(
            source.contains("let activationPlan = Self.activationPlan(") &&
                source.contains("if activationPlan.allowWorkspaceActivationFallback"),
            "SearchService.activate should drive fallback policy from one activation plan so browse-panel right-click failures do not steal focus"
        )
        XCTAssertTrue(
            source.contains("NSApp.yieldActivation(to: runningApp)") &&
                source.contains("runningApp.activate(options: [])"),
            "Workspace activation fallback should use cooperative activation on modern macOS before requesting the target app to activate"
        )
    }

    func testRuntimeCoordinatorOwnsStartupAndMoveAdmissionPolicies() throws {
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let movingURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+IconMoving.swift")
        let movingSource = try String(contentsOf: movingURL, encoding: .utf8)

        XCTAssertTrue(
            coordinatorSource.contains("enum MenuBarOperationCoordinator") &&
                coordinatorSource.contains("startupInitialAction(") &&
                coordinatorSource.contains("positionValidationAction(") &&
                coordinatorSource.contains("moveQueueDecision("),
            "Runtime coordinator should own the shared startup and move admission policies"
        )
        XCTAssertTrue(
            managerSource.contains("currentStartupRuntimeSnapshot()") &&
                managerSource.contains("MenuBarOperationCoordinator.startupInitialAction(") &&
                managerSource.contains("MenuBarOperationCoordinator.positionValidationAction("),
            "MenuBarManager should build a typed startup snapshot and route launch validation through the coordinator"
        )
        XCTAssertTrue(
            movingSource.contains("currentMoveRuntimeSnapshot(") &&
                movingSource.contains("MenuBarOperationCoordinator.moveQueueDecision("),
            "Interactive move entry points should use the shared move-admission policy instead of duplicating local guard ladders"
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
            source.contains("browseController.isVisible"),
            "Search rehide should defer while Browse Icons is still visible"
        )
        XCTAssertTrue(
            source.contains("browseController.isBrowseSessionActive || browseController.isVisible"),
            "Search rehide should defer while Browse Icons session startup/teardown is still in progress"
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

    func testAppleScriptMoveResolutionPrefersFreshSnapshotsForExactIds() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func zonesForScriptMoveResolution(_ identifier: String) -> [ScriptZonedIcon]"),
            "AppleScript moves should use a dedicated move-resolution helper instead of the looser read path"
        )
        XCTAssertTrue(
            source.contains("let startZones = zonesForScriptMoveResolution(trimmedId)"),
            "AppleScript moves should prefer a fresh classified snapshot for exact or shared-bundle identifiers"
        )
        XCTAssertTrue(
            source.contains("shouldPreferFreshZonesForScriptMove("),
            "AppleScript move resolution should explicitly encode when cached zone snapshots are too stale to trust"
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
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)

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
            source.contains("await manager.moveIconFromAlwaysHiddenToHiddenAndWait("),
            "AppleScript always-hidden exits to hidden should wait on the dedicated always-hidden helper task"
        )
        XCTAssertTrue(
            source.contains("waitForScriptZone(iconUniqueID: movedUniqueID, expected: targetZone, timeoutSeconds: 4.0)"),
            "AppleScript move commands should finish with an exact zone-settle proof instead of trusting the first async success alone"
        )
        XCTAssertTrue(
            movingSource.contains("func moveIconAlwaysHiddenAndWait("),
            "MenuBarManager should expose an awaitable always-hidden move helper for AppleScript command reliability"
        )
        XCTAssertTrue(
            movingSource.contains("func moveIconFromAlwaysHiddenToHiddenAndWait("),
            "MenuBarManager should expose an awaitable always-hidden-to-hidden helper for AppleScript command reliability"
        )
        XCTAssertTrue(
            movingSource.contains("prepareAlwaysHiddenMoveQueue(") &&
                movingSource.contains("ensureAlwaysHiddenSeparatorReady(") &&
                movingSource.contains("always-hidden separator became ready after") &&
                managerSource.contains("Force-recreating always-hidden separator after nil update"),
            "Always-hidden move entry should wait for the always-hidden separator to exist before queue admission"
        )
        XCTAssertTrue(
            movingSource.contains("let actionableMoveSafety = accessibilityService.actionableMoveResolutionSafety("),
            "Interactive move flows should ask AccessibilityService whether a multi-item bundle can be moved safely before dragging"
        )
        XCTAssertTrue(
            movingSource.contains("if actionableMoveSafety.allowsClassifiedZoneFallback {") &&
                movingSource.contains("Skipping classified-zone move fallback for ambiguous multi-item identity"),
            "Interactive move flows should refuse classified-zone success fallback when exact move identity could not be proven"
        )
        XCTAssertTrue(
            movingSource.contains("Refusing ambiguous always-hidden move target") &&
                movingSource.contains("Skipping always-hidden classified-zone fallback for ambiguous multi-item identity") &&
                movingSource.contains("Refusing ambiguous AH-to-Hidden move target") &&
                movingSource.contains("Skipping AH-to-Hidden classified-zone fallback for ambiguous multi-item identity"),
            "Always-hidden move flows should use the same ambiguity safety gate and fallback refusal as the standard move path"
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

    func testBrowseViewsWaitOnQueuedMoveTasksInsteadOfGuessingWithDelays() throws {
        let iconPanelURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView+Navigation.swift")
        let iconPanelSource = try String(contentsOf: iconPanelURL, encoding: .utf8)
        let secondMenuBarURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SecondMenuBarView.swift")
        let secondMenuBarSource = try String(contentsOf: secondMenuBarURL, encoding: .utf8)

        XCTAssertTrue(
            iconPanelSource.contains("guard started, let task = menuBarManager.activeMoveTask else") &&
                iconPanelSource.contains("let moved = await task.value") &&
                iconPanelSource.contains("rollbackAlwaysHiddenMutation"),
            "Icon panel move flows should wait on the queued task result and roll back pin mutations when the drag fails"
        )
        XCTAssertTrue(
            secondMenuBarSource.contains("guard started, let task = menuBarManager.activeMoveTask else") &&
                secondMenuBarSource.contains("let moved = await task.value") &&
                secondMenuBarSource.contains("applySuccessfulMovePresentation"),
            "Second menu bar moves should wait on the real drag result before updating row state or reporting success"
        )
        XCTAssertFalse(
            secondMenuBarSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)"),
            "Second menu bar should stop guessing move completion with a fixed timer"
        )
    }

    func testAppleScriptAlwaysHiddenMovesPrePinToMatchBrowseUI() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("case .alwaysHidden:\n                    if !manager.settings.alwaysHiddenSectionEnabled {\n                        manager.settings.alwaysHiddenSectionEnabled = true\n                    }\n                    manager.pinAlwaysHidden(app: icon)\n                    manager.saveSettings()\n                    let moved = runScriptMove {"),
            "AppleScript moves into always-hidden should pin before the move, matching the browse UI path"
        )
        XCTAssertTrue(
            source.contains("if !moved {\n                        _ = manager.unpinAlwaysHidden("),
            "AppleScript always-hidden moves should roll back the pin when the drag fails"
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
            source.contains("let itemOnScreen = isElementOnScreen(item)"),
            "clickMenuBarItem should cache the on-screen check so hardware and AX paths use the same visibility decision"
        )
        XCTAssertTrue(
            source.contains("if !itemOnScreen"),
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
            source.contains("remainingActivationGracePeriod(for: currentMode)") &&
                source.contains("browseDismissRehideDelay(baseDelay: manager.settings.rehideDelay)"),
            "Closing Browse Icons should preserve standard rehide timing while protecting recent second-menu-bar activations"
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
            source.contains("if browseController.isBrowseSessionActive"),
            "Fire-time rehide guard should block auto-hide throughout the full browse session, not only after AppKit reports the panel visible"
        )
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

    func testQARegressionCloseGuardExemptsHistoricalDuplicateAndSupersededClosures() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("def closed_regression_confirmation_exemption_reason"),
            "Closed-regression confirmation guardrails should classify historical closure reasons before demanding reporter confirmation"
        )
        XCTAssertTrue(
            source.contains(#"/duplicate of #\d+/i"#),
            "Closed-regression confirmation guardrails should exempt duplicate closures from reporter-confirmation requirements"
        )
        XCTAssertTrue(
            source.contains("/superseded by/i"),
            "Closed-regression confirmation guardrails should exempt superseded closures from reporter-confirmation requirements"
        )
        XCTAssertTrue(
            source.contains("/settings mismatch/i") &&
            source.contains("never got the requested diagnostics"),
            "Closed-regression confirmation guardrails should exempt stale settings-mismatch closures that never produced current diagnostics"
        )
    }

    func testQARuntimeSmokeStagesReleaseAndRequiresMini() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("def check_runtime_release_smoke"),
            "Project QA should expose a dedicated runtime smoke gate"
        )
        XCTAssertTrue(
            source.contains("Runtime smoke must run on the mini via ./scripts/SaneMaster.rb"),
            "Project QA should block local false-confidence runtime smoke runs"
        )
        XCTAssertTrue(
            source.contains("Open3.capture2e(SANEMASTER_CLI, 'test_mode', '--release', '--no-logs')"),
            "Project QA should stage the release app before runtime smoke"
        )
        XCTAssertTrue(
            source.contains("startup_probe_script = File.join(__dir__, 'startup_layout_probe.rb')") &&
                source.contains("heartbeat_label: 'runtime startup layout probe'") &&
                source.contains("'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH") &&
                source.contains("'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH"),
            "Project QA should run a dedicated startup layout probe after browse smoke so poisoned relaunch state is release-gated too"
        )
        XCTAssertTrue(
            source.contains("screenshot_capture_available = runtime_screenshot_capture_available?(screenshot_dir)") &&
                source.contains("capture_runtime_smoke_screenshots = ENV['SANEBAR_RELEASE_SMOKE_SCREENSHOTS'] == '1' && screenshot_capture_available") &&
                source.contains("'SANEBAR_SMOKE_CAPTURE_SCREENSHOTS' => capture_runtime_smoke_screenshots ? '1' : '0'"),
            "Project QA runtime smoke should probe screenshot capability but keep capture opt-in so screenshot flakiness does not block release"
        )
        XCTAssertTrue(
            source.contains("return true if internal_runtime_snapshot_supported?") &&
                source.contains("def internal_runtime_snapshot_supported?") &&
                source.contains("capture browse panel snapshot") &&
                source.contains("queue browse panel snapshot"),
            "Project QA runtime smoke should treat the staged app's internal browse-panel snapshot commands as the primary screenshot capability"
        )
        XCTAssertTrue(
            source.contains("resolve_runtime_screenshot_tool") &&
                source.contains("command -v screenshot"),
            "Project QA runtime smoke should retain a host-level screenshot fallback when in-app snapshot support is unavailable"
        )
        XCTAssertTrue(
            source.contains("screenshots skipped on this host"),
            "Project QA runtime smoke should explicitly report when host screenshot capture is unavailable"
        )
        XCTAssertTrue(
            source.contains("screenshots disabled for release smoke") &&
                source.contains("smoke screenshots disabled for release gating"),
            "Project QA runtime smoke should explain when screenshot capture is intentionally disabled for release gating"
        )
        XCTAssertTrue(
            source.contains("expected_screenshots = runtime_smoke_expected_modes(target).to_h"),
            "Project QA runtime smoke should still resolve screenshot artifacts for every browse layout when screenshot capture is explicitly enabled"
        )
        XCTAssertTrue(
            source.contains(#"Dir.glob(File.join(screenshot_dir, "sanebar-#{mode}-*.png"))"#),
            "Project QA runtime smoke should resolve screenshot artifacts by browse mode"
        )
        XCTAssertTrue(
            source.contains("modes << 'findIcon' if commands.include?('open icon panel')"),
            "Project QA runtime smoke should derive expected browse layouts from the staged app's AppleScript support"
        )
        XCTAssertTrue(
            source.contains("RUNTIME_SMOKE_PASSES = 2"),
            "Project QA runtime smoke should require a repeat pass to catch warm-state regressions"
        )
        XCTAssertTrue(
            source.contains("RUNTIME_SHARED_BUNDLE_IDS = %w[") &&
                source.contains("com.apple.menuextra.focusmode") &&
                source.contains("com.apple.menuextra.display"),
            "Project QA runtime smoke should keep a stable focused shared-bundle candidate set for high-risk Apple menu extras"
        )
        XCTAssertTrue(
            source.contains("'SANEBAR_SMOKE_REQUIRE_CANDIDATE' => '1'") &&
                source.contains("'SANEBAR_SMOKE_WATCH_RESOURCES' => '1'") &&
                source.contains("'SANEBAR_SMOKE_MAX_CPU_PERCENT' => RUNTIME_SMOKE_MAX_CPU_PERCENT.to_s") &&
                source.contains("'SANEBAR_SMOKE_MAX_RSS_MB' => RUNTIME_SMOKE_MAX_RSS_MB.to_s"),
            "Project QA runtime smoke should require at least one movable candidate and force the resource watchdog on with explicit CPU and RSS thresholds"
        )
        XCTAssertTrue(
            source.contains("'SANEBAR_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX' => RUNTIME_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX.to_s") &&
                source.contains("'SANEBAR_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS' => RUNTIME_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS.to_s") &&
                source.contains("'SANEBAR_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS' => RUNTIME_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS.to_s") &&
                source.contains("'SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX' => RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX.to_s") &&
                source.contains("'SANEBAR_SMOKE_ACTIVE_AVG_CPU_MAX' => RUNTIME_SMOKE_ACTIVE_AVG_CPU_MAX.to_s"),
            "Project QA runtime smoke should also force explicit settle windows plus launch-idle, post-smoke idle, and active-average performance budgets"
        )
        XCTAssertTrue(
            source.contains("resource_sample_path = \"/tmp/sanebar_runtime_resource_sample-pass#{pass_number}-try#{attempt}.txt\"") &&
                source.contains("resource_sample=#{resource_sample_path}"),
            "Project QA runtime smoke should record a per-pass process sample path alongside the smoke transcript"
        )
        XCTAssertTrue(
            source.contains("retryable_runtime_smoke_failure?(smoke_out)") &&
                source.contains("relaunching after transient launch idle spike"),
            "Project QA runtime smoke should retry exactly the transient launch-idle spike path before failing the release"
        )
        XCTAssertTrue(
            source.contains("Runtime smoke failed on pass"),
            "Project QA runtime smoke should report which pass exposed the failure"
        )
        XCTAssertTrue(
            source.contains("FileUtils.rm_f(RUNTIME_SMOKE_LOG_PATH)") &&
                source.contains("FileUtils.rm_f(RUNTIME_LAUNCH_LOG_PATH)"),
            "Project QA runtime smoke should clear stale launch/smoke logs before each run"
        )
        XCTAssertTrue(
            source.contains("File.write(RUNTIME_LAUNCH_LOG_PATH, launch_out)"),
            "Project QA runtime smoke should persist the current launch transcript even on success so stale launch failures do not mislead later debugging"
        )
        XCTAssertTrue(
            source.contains("File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join(\"\\n\\n\"))"),
            "Project QA runtime smoke should persist the latest smoke transcript on success so the artifact always matches the current run"
        )
        XCTAssertTrue(
            source.contains("shared_bundle_ids = runtime_smoke_available_required_candidate_ids(") &&
                source.contains("'SANEBAR_SMOKE_REQUIRED_IDS' => shared_bundle_ids.join(',')") &&
                source.contains("'SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES' => '1'") &&
                source.contains("runtime smoke shared-bundle exact ids") &&
                source.contains("ensure_runtime_smoke_target_running!(target.merge(relaunch: true))"),
            "Project QA runtime smoke should run a dedicated focused pass for shared-bundle Apple extras when those exact IDs are present"
        )
        XCTAssertTrue(
            source.contains("def runtime_smoke_relaunch_command(target)") &&
                source.contains("command += ['--env', 'SANEAPPS_DISABLE_KEYCHAIN=1']") &&
                source.contains("command += ['--args', '--sane-no-keychain']") &&
                source.contains("system(*runtime_smoke_relaunch_command(target), out: File::NULL, err: File::NULL)"),
            "Project QA runtime smoke relaunches should preserve no-keychain launch mode so Pro-only checks do not silently downgrade to free mode"
        )
        XCTAssertTrue(
            source.contains("def runtime_smoke_available_required_candidate_ids") &&
                source.contains("'osascript'") &&
                source.contains("list icon zones"),
            "Project QA should discover whether the focused shared-bundle candidates are actually present before requiring that smoke pass"
        )
        XCTAssertTrue(
            source.contains("runtimeSmokeResourceWatchdog: {") &&
                source.contains("maxCpuPercent: RUNTIME_SMOKE_MAX_CPU_PERCENT") &&
                source.contains("maxRssMB: RUNTIME_SMOKE_MAX_RSS_MB"),
            "Project QA status snapshots should record the runtime smoke watchdog thresholds"
        )
        XCTAssertTrue(
            source.contains("runtimeSmokePerformanceBudget: {") &&
                source.contains("launchIdleCpuAvgMax: RUNTIME_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX") &&
                source.contains("postSmokeIdleSettleSeconds: RUNTIME_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS") &&
                source.contains("postSmokeIdleSampleSeconds: RUNTIME_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS") &&
                source.contains("activeAvgCpuMax: RUNTIME_SMOKE_ACTIVE_AVG_CPU_MAX"),
            "Project QA status snapshots should record the runtime smoke performance budget"
        )
    }

    func testReleasePreflightForwardsRuntimeSmokeToProjectQA() throws {
        let fileURL = saneAppsRootURL().appendingPathComponent("infra/SaneProcess/scripts/sanemaster/release.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("'SANEPROCESS_RUN_RUNTIME_SMOKE' => '1'"),
            "Release preflight should enable runtime smoke when invoking project QA"
        )
        XCTAssertTrue(
            source.contains("\"#{app_prefix}_RUN_RUNTIME_SMOKE\" => '1'"),
            "Release preflight should forward the app-specific runtime smoke flag to project QA"
        )
    }

    func testVerifyExplainsRuntimeSmokeWhenNoXCUITargetExists() throws {
        let fileURL = saneAppsRootURL().appendingPathComponent("infra/SaneProcess/scripts/sanemaster/verify.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("def runtime_smoke_coverage_present?"),
            "Verify should explicitly detect projects that use runtime smoke instead of an XCUITest target"
        )
        XCTAssertTrue(
            source.contains("Runtime UI coverage lives in Scripts/live_zone_smoke.rb + RuntimeGuardXCTests."),
            "Verify should explain the canonical runtime UI coverage path instead of emitting a misleading missing-UI-tests warning"
        )
    }

    func testQADocURLCheckFallsBackToGETForAntiBotSites() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("[Net::HTTP::Head, Net::HTTP::Get].each_with_index"),
            "QA URL checks should retry with GET when HEAD-only probing is blocked"
        )
        XCTAssertTrue(
            source.contains("[401, 403, 405].include?(response_code)"),
            "QA URL checks should treat anti-bot and auth-gated responses as reachable after fallback"
        )
    }

    func testLiveSmokeReportsMeaningfulBrowseActivationFailures() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/live_zone_smoke.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("browse_activation_failure_summary"),
            "Live smoke should summarize browse activation failures instead of only printing the last diagnostics line"
        )
        XCTAssertTrue(
            source.contains("requestedApp:', 'firstAttempt:', 'retryAttempt:', 'finalOutcome:', 'currentMode:', 'windowVisible:', 'lastRelayoutReason:'"),
            "Live smoke should surface the key activation and browse-panel diagnostics in failure output"
        )
    }

    func testProjectQAStatusFeedsSharedValidationReport() throws {
        let qaURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let qaSource = try String(contentsOf: qaURL, encoding: .utf8)
        XCTAssertTrue(
            qaSource.contains("QA_STATUS_PATH"),
            "Project QA should persist a latest-run status snapshot"
        )
        XCTAssertTrue(
            qaSource.contains("write_status_snapshot(exit_code: exit_code)"),
            "Project QA should record whether the latest gate passed or failed"
        )

        let validationURL = saneAppsRootURL().appendingPathComponent("infra/SaneProcess/scripts/validation_report.rb")
        let validationSource = try String(contentsOf: validationURL, encoding: .utf8)
        XCTAssertTrue(
            validationSource.contains("latest_project_qa_status(project_path)"),
            "Shared validation should read the latest per-project QA status when available"
        )
        XCTAssertTrue(
            validationSource.contains("release_preflight_status.json"),
            "Shared validation should also honor shared preflight snapshots so every app can participate before custom QA status adoption"
        )
        XCTAssertTrue(
            validationSource.contains(".max_by { |path| File.mtime(path) }"),
            "Shared validation should use the newest status snapshot instead of whichever file happens to be checked first"
        )
        XCTAssertTrue(
            validationSource.contains("critical gate failed"),
            "A failed project QA gate should prevent validation_report from claiming the app is ready to ship"
        )

        let saneMasterURL = saneAppsRootURL().appendingPathComponent("infra/SaneProcess/scripts/SaneMaster.rb")
        let saneMasterSource = try String(contentsOf: saneMasterURL, encoding: .utf8)
        XCTAssertTrue(
            saneMasterSource.contains("sync_outputs_from_mini!(Dir.pwd, execution_repo)"),
            "Mini-first routing should sync output artifacts back from the actual routed workspace so local reporting sees the same QA truth"
        )

        let releaseURL = saneAppsRootURL().appendingPathComponent("infra/SaneProcess/scripts/sanemaster/release.rb")
        let releaseSource = try String(contentsOf: releaseURL, encoding: .utf8)
        XCTAssertTrue(
            releaseSource.contains("outputs', 'release_preflight_status.json"),
            "Shared release preflight should persist its own status snapshot so apps without custom qa.rb support still feed validation"
        )
        XCTAssertTrue(
            releaseSource.contains("write_release_status_snapshot("),
            "Shared release preflight should write a durable pass/fail snapshot before exiting"
        )
    }

    func testReleasePreflightDowngradesAuthNoiseToStructuredSkips() throws {
        let releaseURL = saneAppsRootURL().appendingPathComponent("infra/SaneProcess/scripts/sanemaster/release.rb")
        let source = try String(contentsOf: releaseURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("def gh_auth_unavailable?(output)"),
            "Release preflight should explicitly detect GitHub auth/keychain failures so it can skip cleanly"
        )
        XCTAssertTrue(
            source.contains("Open3.capture2e({ 'PATH' => tool_path }, gh_bin, 'issue', 'list'"),
            "GitHub issue checks should capture stderr so keychain/auth noise does not leak into the release summary"
        )
        XCTAssertTrue(
            source.contains("Open3.capture2e({ 'PATH' => tool_path }, gh_bin, 'pr', 'list'"),
            "GitHub PR checks should capture stderr so auth failures are reported as structured skips"
        )
        XCTAssertTrue(
            source.contains("skipped (gh auth unavailable)"),
            "GitHub auth problems should render as an explicit skip instead of a scary raw keychain error"
        )
        XCTAssertTrue(
            source.contains("Open3.capture2e('security', 'find-generic-password'"),
            "Keychain-backed email checks should capture stderr to avoid leaking keychain lookup noise"
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

    func testBrowsePanelsKeepTierGatesAligned() throws {
        let iconPanelURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let iconPanelSource = try String(contentsOf: iconPanelURL, encoding: .utf8)
        let secondMenuBarURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SecondMenuBarView.swift")
        let secondMenuBarSource = try String(contentsOf: secondMenuBarURL, encoding: .utf8)

        XCTAssertTrue(
            iconPanelSource.contains("if isRightClick, !isPro {"),
            "Icon panel should keep right-click gated behind Pro"
        )
        XCTAssertTrue(
            iconPanelSource.contains("proUpsellFeature = .rightClickFromPanels"),
            "Icon panel should surface the right-click upsell instead of falling through"
        )
        XCTAssertTrue(
            iconPanelSource.contains("onToggleHidden: isPro ? makeToggleHiddenAction(for: app) : { proUpsellFeature = .zoneMoves }"),
            "Icon panel should keep hidden/visible moves gated behind Pro"
        )
        XCTAssertTrue(
            iconPanelSource.contains("onMoveToAlwaysHidden: isPro ? makeMoveToAlwaysHiddenAction(for: app) : { proUpsellFeature = .zoneMoves }"),
            "Icon panel should keep always-hidden moves gated behind Pro"
        )
        XCTAssertTrue(
            iconPanelSource.contains("onMoveToHidden: isPro ? makeMoveToHiddenAction(for: app) : { proUpsellFeature = .zoneMoves }"),
            "Icon panel should keep always-hidden exit moves gated behind Pro"
        )

        XCTAssertTrue(
            secondMenuBarSource.contains("if isRightClick, !licenseService.isPro {"),
            "Second menu bar should keep right-click gated behind Pro"
        )
        XCTAssertTrue(
            secondMenuBarSource.contains("guard licenseService.isPro else {"),
            "Second menu bar should block drag/drop move paths for free users"
        )
        XCTAssertTrue(
            secondMenuBarSource.contains("proUpsellFeature = .zoneMoves"),
            "Second menu bar should surface the zone-move upsell instead of attempting restricted moves"
        )
    }

    func testSecondMenuBarRowControlsStayAsTopToggleChips() throws {
        let secondMenuBarURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SecondMenuBarView.swift")
        let source = try String(contentsOf: secondMenuBarURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("ScrollView(.horizontal, showsIndicators: false)"),
            "Row toggles should stay in a compact horizontal strip above the actual rows"
        )
        XCTAssertTrue(
            source.contains("Text(SecondMenuBarLayout.rowStateLabel(isOn: isOn))"),
            "Top row toggles should keep a small inline On/Off state instead of a second row-like control"
        )
        XCTAssertTrue(
            source.contains("SaneBarChrome.activeControlFill") &&
                source.contains("SaneBarChrome.utilityFill") &&
                source.contains(".padding(.vertical, 4)"),
            "Top row toggles should keep compact capsule sizing while using the shared solid control fills"
        )
        XCTAssertFalse(
            source.contains("Color.green.opacity"),
            "Top row toggles should not fall back to a bright green status color that overwhelms the panel"
        )
    }

    func testIconPanelOnlyAdvertisesRealZoneDropTargets() throws {
        let iconPanelURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let source = try String(contentsOf: iconPanelURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func modeSupportsZoneDrop(_ mode: Mode) -> Bool"),
            "Icon panel tabs should centralize which tabs are real drop destinations"
        )
        XCTAssertTrue(
            source.contains("case .all:\n            false"),
            "All tab should stay browse-only and must not be presented as a drag destination"
        )
        XCTAssertTrue(
            source.contains("private var shouldShowMoveHint: Bool"),
            "Icon panel should expose a single inline drag hint state instead of duplicating the tabs in a second row"
        )
        XCTAssertTrue(
            source.contains("Text(\"Move to\")") &&
                source.contains("if shouldShowMoveHint") &&
                source.contains("modeSegment(segmentMode)") &&
                !source.contains("moveDestinationChip("),
            "Drag guidance should stay in the existing tab row with one Move to label and no duplicate destination strip"
        )
        XCTAssertTrue(
            source.contains("@State private var isModeStripDropActive = false"),
            "Icon panel should track drag-session state so the temporary destination rail only appears during drag"
        )
        XCTAssertTrue(
            source.contains("installModeStripDragEndMonitors()") &&
                source.contains("addLocalMonitorForEvents"),
            "Icon panel drag affordance should clean itself up when the drag session ends"
        )
        XCTAssertTrue(
            source.contains("@State private var activeModeStripSourceZone: AppZone?"),
            "Icon panel should track the dragged icon's actual source zone so it can suppress the current zone in the destination strip"
        )
        XCTAssertTrue(
            source.contains("private func modeAcceptsCurrentDrag(_ mode: Mode) -> Bool") &&
                source.contains("let isValidMoveTarget = shouldShowMoveHint && moveHintModes.contains(segmentMode)") &&
                source.contains(".dropDestination(for: String.self)") &&
                source.contains("if isValidMoveTarget"),
            "Icon panel should centralize whether a tab can accept the current drag and only attach drop handling to valid destination tabs"
        )
        XCTAssertTrue(
            source.contains("return originMode != mode"),
            "Origin zone should not glow as a destination during drag"
        )
        XCTAssertTrue(
            source.contains("noteModeStripDragStarted(sourceZone: appZone(for: app))"),
            "Drag state should capture the source app's real zone at drag start"
        )
        XCTAssertFalse(
            source.contains("dash: showsDropAffordance ? [4, 3] : []"),
            "Filter tabs should no longer use the old dashed-outline destination treatment"
        )
    }

    func testLiveSmokeCoversBothBrowseModesWithScreenshots() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/live_zone_smoke.rb")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("'secondMenuBar' => 'show second menu bar'"),
            "Live smoke should open the second menu bar browse mode"
        )
        XCTAssertTrue(
            source.contains("'findIcon' => 'open icon panel'"),
            "Live smoke should open the icon panel browse mode"
        )
        XCTAssertTrue(
            source.contains("capture_browse_screenshot"),
            "Live smoke should capture screenshots while each browse mode is open"
        )
        XCTAssertTrue(
            source.contains("capture_internal_browse_screenshot") &&
                source.contains("capture browse panel snapshot") &&
                source.contains("queue browse panel snapshot"),
            "Live smoke should prefer the app's internal browse-panel snapshot commands before falling back to host capture"
        )
        XCTAssertTrue(
            source.contains("capture_window_screenshot") &&
                source.contains("WINDOW_SCREENSHOT_TITLES"),
            "Live smoke should keep a window-level screenshot fallback for hosts where direct browse-panel snapshots are unavailable"
        )
        XCTAssertTrue(
            source.contains("exercise_browse_activation('activate browse icon'"),
            "Live smoke should verify browse left-click activation"
        )
        XCTAssertTrue(
            source.contains("exercise_browse_activation(") &&
                source.contains("'right click browse icon'"),
            "Live smoke should verify browse right-click activation"
        )
        XCTAssertTrue(
            source.contains("seed_focus_probe_prior_app") &&
                source.contains("assert_frontmost_did_not_revert_to") &&
                source.contains("windowTitle") &&
                source.contains("frontmost_app_state"),
            "Live smoke should seed a known prior frontmost app/window state and fail if browse right-click jumps focus back to it"
        )
        XCTAssertTrue(
            source.contains("sleep_with_watchdog(BROWSE_ACTIVATION_COOLDOWN_SECONDS)"),
            "Live smoke should wait out activation debounce before retrying the same browse tile via right-click"
        )
        XCTAssertTrue(
            source.contains("'browse panel diagnostics'") &&
            source.contains("'activate browse icon'") &&
            source.contains("'right click browse icon'"),
            "Live smoke should check support using full multi-word AppleScript command names"
        )
        XCTAssertTrue(
            source.contains("current_browse_activation_diagnostics") &&
            source.contains("salvage_timed_out_browse_activation"),
            "Live smoke should salvage SSH AppleScript reply timeouts using fresh in-app diagnostics"
        )
        XCTAssertTrue(
            source.contains("browse_activation_observably_verified?") &&
            source.contains("accepted=true") &&
            source.contains("verification=verified"),
            "Live smoke should require an accepted, observably verified browse activation before treating the panel click path as healthy"
        )
        XCTAssertTrue(
            source.contains("STANDARD_APP_MENU_TITLES") &&
            source.contains("likely_standard_app_menu_candidate?") &&
            source.contains("app_menu_bundle_ids(raw_candidates)") &&
            source.contains("coarse_bundle_fallback?(item) && precise_bundles.include?(item[:bundle])"),
            "Live smoke should ignore standard app-menu titles when choosing move candidates so all-candidate sweeps stay focused on real menu extras"
        )
        XCTAssertTrue(
            source.contains("BROWSE_ACTIVATION_BUNDLE_DENYLIST") &&
            source.contains("precise_non_apple") &&
            source.contains("browse_activation_pool(zones)") &&
            source.contains("(preferred + precise_non_apple + fallback).uniq") &&
            source.contains("com.apple.menuextra.bluetooth") &&
            source.contains("browse_activation_denied?(item)") &&
            source.contains("item[:bundle].start_with?('com.apple.')"),
            "Live smoke should prefer the explicit stable browse targets before falling back to non-Apple or noisy Apple-only menu extras"
        )
        XCTAssertTrue(
            source.contains("MOVE_CANDIDATE_BUNDLE_DENYLIST") &&
            source.contains("cc.ffitch.shottr") &&
            source.contains("com.yonilevy.cryptoticker") &&
            source.contains("candidates.reject! { |item| MOVE_CANDIDATE_BUNDLE_DENYLIST.include?(item[:bundle]) }") &&
            source.contains("MOVE_CANDIDATE_PREFERRED_BUNDLE_PREFIXES") &&
            source.contains("com.mrsane.") &&
            source.contains("return prioritize_move_candidates(ordered) if @required_candidate_ids.empty?") &&
            source.contains("preferred_move_candidate_rank(item[:bundle])") &&
            source.contains("if @require_always_hidden") &&
            source.contains("{ 'alwaysHidden' => 0, 'hidden' => 1, 'visible' => 2 }"),
            "Live smoke should prefer stable first-party move fixtures and exclude known noisy edge-case bundles when always-hidden moves are required"
        )
        XCTAssertTrue(
            source.contains("!non_idempotent_app_script?(statement)") &&
            source.contains("statement.start_with?('activate browse icon ')"),
            "Live smoke should not blindly retry side-effectful browse activation AppleScript commands after a timeout"
        )
        XCTAssertTrue(
            source.contains("APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS = 20") &&
            source.contains("statement == 'list icon zones' || statement == 'list icons'"),
            "Live smoke should allow longer timeouts for heavy read-only AppleScript commands during cold-start smoke"
        )
        XCTAssertTrue(
            source.contains("Salvaging timed-out move command via zone verification") &&
            source.contains("timed_out_move_command?"),
            "Live smoke should verify the final zone before failing a move command whose AppleScript reply timed out"
        )
        XCTAssertTrue(
            source.contains("icon_unique_id = resolve_live_move_identifier(candidate)") &&
            source.contains("def resolve_live_move_identifier(candidate)"),
            "Live smoke move commands should resolve through a move-specific identity helper instead of reusing the browse fallback path"
        )
        XCTAssertTrue(
            source.contains("if exact_move_identity_lost?(candidate, icon_unique_id, zones)") &&
            source.contains("Shared-bundle move verification lost exact identity"),
            "Live smoke should fail fast when a shared-bundle move can no longer prove the requested identity after relayout"
        )
        XCTAssertTrue(
            source.contains("return nil if same_bundle.length > 1") &&
            source.contains("def matched_move_candidate(zones, requested_unique_id, candidate)"),
            "Live smoke should refuse same-bundle sibling fallback when verifying a shared-bundle move result"
        )
        XCTAssertFalse(
            source.contains("zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] } ||\n        zones.find { |item| item[:bundle] == candidate[:bundle] && item[:movable] }"),
            "Live smoke should not allow wait_for_zone to bless move success through bundle/name or bundle-only fallback alone"
        )
        XCTAssertTrue(
            source.contains("retryable_zone_poll_error?") &&
            source.contains("after transient poll failures"),
            "Live smoke should keep polling through transient list-icon-zones timeouts while the menu bar is relayouting"
        )
        XCTAssertTrue(
            source.contains("start_resource_watchdog") &&
                source.contains("check_resource_watchdog!") &&
                source.contains("sleep_with_watchdog"),
            "Live smoke should run a background resource watchdog and check it during waits instead of sleeping blindly"
        )
        XCTAssertTrue(
            source.contains("peak_cpu_exceeded") &&
                source.contains("peak_rss_exceeded") &&
                source.contains("capture_resource_sample"),
            "Live smoke should fail loudly on runaway CPU/RSS and capture a process sample for follow-up"
        )
        XCTAssertTrue(
            source.contains("assert_idle_budget!(") &&
                source.contains("label: 'launch'") &&
                source.contains("label: 'post-smoke'"),
            "Live smoke should verify that launch settles down and that the app returns to an idle budget after the full browse/move pass"
        )
        XCTAssertTrue(
            source.contains("assert_active_average_budget!") &&
                source.contains("active_budget_exceeded"),
            "Live smoke should reject heavy average CPU/RSS behavior across the full interaction pass, not just absurd spikes"
        )
        XCTAssertTrue(
            source.contains("📉 Idle budget %s: avgCpu=%.1f%% peakCpu=%.1f%% avgRss=%.1fMB peakRss=%.1fMB") &&
                source.contains("🫀 Resource watchdog: samples=%d avgCpu=%.1f%% peakCpu=%.1f%% avgRss=%.1fMB peakRss=%.1fMB"),
            "Live smoke should print both idle-budget and whole-pass performance summaries so the numbers are reviewable in smoke logs"
        )
        XCTAssertTrue(
            source.contains("'/usr/bin/sample'") &&
                source.contains("ps',") &&
                source.contains("'pid=,%cpu=,rss=,etime=,command='"),
            "Live smoke should monitor the staged process with native macOS tooling and sample it when thresholds are breached"
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
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)

        guard let autoRehideIndex = coordinatorSource.range(of: "if !autoRehideEnabled"),
              let skipIndex = coordinatorSource.range(of: "if shouldSkipHideForExternalMonitor"),
              let hideIndex = coordinatorSource.range(of: "return .performInitialHide")
        else {
            XCTFail("Startup auto-rehide, external-monitor, or initial-hide blocks not found")
            return
        }

        XCTAssertLessThan(
            autoRehideIndex.lowerBound.utf16Offset(in: coordinatorSource),
            hideIndex.lowerBound.utf16Offset(in: coordinatorSource),
            "Startup should respect auto-rehide before attempting initial hide"
        )
        XCTAssertLessThan(
            skipIndex.lowerBound.utf16Offset(in: coordinatorSource),
            hideIndex.lowerBound.utf16Offset(in: coordinatorSource),
            "Startup should apply external-monitor policy before attempting initial hide"
        )
        XCTAssertTrue(
            managerSource.contains("MenuBarOperationCoordinator.startupInitialAction(") &&
                managerSource.contains("case .performInitialHide:") &&
                managerSource.contains("await self.hidingService.hide()"),
            "MenuBarManager should route startup hide policy through the runtime coordinator before performing the initial hide"
        )
        XCTAssertTrue(
            managerSource.contains("Skipping initial hide: auto-rehide disabled"),
            "Startup should log when the launch hide is skipped because auto-rehide is off"
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
        XCTAssertTrue(
            source.contains("Status item geometry drift detected"),
            "Runtime validation should log attached-but-drifted status items so leftward shoves are distinguishable from missing windows"
        )
        XCTAssertTrue(
            source.contains("recreating from persisted layout before autosave recovery"),
            "Validation should try a persisted-layout relayout before bumping autosave namespaces"
        )
    }

    func testStartupRecoveryRecreatesLiveItemsImmediately() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("case let .recoverAndKeepExpanded(reason):") &&
                source.contains("self.recreateStatusItemsFromPersistedLayout(reason: \"startup-\\(reason.rawValue)\")") &&
                coordinatorSource.contains("case missingCoordinates = \"missing-coordinates\"") &&
                coordinatorSource.contains("case invalidGeometry = \"invalid-geometry\""),
            "Startup recovery should recreate the live status items immediately using the coordinator-owned recovery reason"
        )
    }

    func testInitialPositionValidationWaitsForStartupHideOrRecovery() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func scheduleInitialPositionValidationAfterStartup()") &&
                source.contains("Avoid racing the first geometry check against the startup"),
            "MenuBarManager should have an explicit helper for post-startup validation so launch recovery and initial hide do not race the first geometry check"
        )
        XCTAssertFalse(
            source.contains("setupStatusItem()\n            schedulePositionValidation()"),
            "Deferred UI setup should not arm position validation in parallel with setupStatusItem anymore"
        )
        XCTAssertTrue(
            source.contains("self.scheduleInitialPositionValidationAfterStartup()"),
            "Startup setup should arm the first position validation only after startup hide/skip/recovery has settled"
        )
    }

    func testLaunchLoadsLicenseBeforeCreatingLicenseGatedStatusItems() throws {
        let appURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let smokeURL = projectRootURL().appendingPathComponent("Scripts/live_zone_smoke.rb")
        let smokeSource = try String(contentsOf: smokeURL, encoding: .utf8)

        let licenseRange = appSource.range(of: "LicenseService.shared.checkCachedLicense()")
        let managerRange = appSource.range(of: "_ = MenuBarManager.shared")
        XCTAssertNotNil(licenseRange, "App launch should load cached license state explicitly")
        XCTAssertNotNil(managerRange, "App launch should still bootstrap MenuBarManager explicitly")
        if let licenseRange, let managerRange {
            XCTAssertLessThan(
                appSource.distance(from: appSource.startIndex, to: licenseRange.lowerBound),
                appSource.distance(from: appSource.startIndex, to: managerRange.lowerBound),
                "Cached Pro state should load before MenuBarManager creates license-gated status items"
            )
        }

        XCTAssertTrue(
            managerSource.contains("private func currentEffectiveAlwaysHiddenSectionEnabled() -> Bool"),
            "MenuBarManager should centralize the effective always-hidden gate instead of mixing raw settings and license state"
        )
        XCTAssertTrue(
            managerSource.contains("statusBarController.ensureAlwaysHiddenSeparator(enabled: currentEffectiveAlwaysHiddenSectionEnabled())"),
            "Initial status-item wiring should gate the always-hidden separator on effective Pro state"
        )
        XCTAssertTrue(
            managerSource.contains("alwaysHiddenEnabled: self.currentEffectiveAlwaysHiddenSectionEnabled()"),
            "Startup recovery should only reseed always-hidden state when the feature is effectively enabled"
        )
        XCTAssertTrue(
            smokeSource.contains("last_error = e") &&
                smokeSource.contains("raise unless layout_snapshot_retryable?(e)") &&
                smokeSource.contains("def layout_snapshot_retryable?(error)"),
            "Live smoke should retry transient launch-time AppleScript handshake failures while waiting for layout stabilization"
        )
        XCTAssertTrue(
            smokeSource.contains("APPLESCRIPT_MOVE_TIMEOUT_SECONDS = 25") &&
                smokeSource.contains("return APPLESCRIPT_MOVE_TIMEOUT_SECONDS if move_app_script?(statement)") &&
                smokeSource.contains("def move_app_script?(statement)"),
            "Live smoke should give verified move AppleScripts a larger timeout budget so the harness does not kill the client mid-reply"
        )
    }

    func testScreenParameterChangesReschedulePositionValidation() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Screen parameters changed — invalidated cached separator positions") &&
                source.contains("self?.schedulePositionValidation()"),
            "Screen/menu-bar topology changes should trigger another position validation pass so attached-but-drifted items self-heal"
        )
    }

    func testInlineAppMenuSuppressionDoesNotForceDockIconVisible() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager+Visibility.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func suppressApplicationMenusIfNeeded()"),
            "Inline reveal path should still have an explicit app-menu suppression handler"
        )
        XCTAssertFalse(
            source.contains("private func suppressApplicationMenusIfNeeded() {\n        guard !isAppMenuSuppressed else { return }\n        guard !settings.showDockIcon else { return }\n\n        appToReactivateAfterSuppression = NSWorkspace.shared.frontmostApplication\n        NSApp.setActivationPolicy(.regular)"),
            "Inline app-menu suppression must not force regular activation when the user has hidden the Dock icon"
        )
        XCTAssertTrue(
            source.contains("appToReactivateAfterSuppression = NSWorkspace.shared.frontmostApplication") &&
                source.contains("NSApp.activate(ignoringOtherApps: true)") &&
                source.contains("scheduleAppMenuDockPolicyReassertionIfNeeded()"),
            "Inline app-menu suppression should still activate SaneBar while reasserting accessory policy during the suppression window"
        )
        XCTAssertTrue(
            source.contains("appMenuDockPolicyTask?.cancel()") &&
                source.contains("appMenuDockPolicyTask = Task"),
            "Inline app-menu suppression should cancel prior Dock-policy reassertion work and keep a delayed reassertion window alive until suppression ends"
        )
        XCTAssertTrue(
            source.contains("appMenuDockPolicyReassertionIntervalsNanoseconds") &&
                source.contains("reassertAccessoryPolicyDuringAppMenuSuppression(reason: \"suppressionHold\")"),
            "Inline app-menu suppression should keep checking for delayed Dock-policy drift instead of only restoring accessory mode once"
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
            source.contains("remainingActivationGracePeriod(for: currentMode)") &&
                source.contains("browseDismissRehideDelay(baseDelay: manager.settings.rehideDelay)"),
            "Visible reset should derive panel-dismiss rehide from standard timing while respecting activation grace"
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

    func testRulesSettingsExposeInlineRevealAppMenuToggle() throws {
        let fileURL = projectRootURL().appendingPathComponent("UI/Settings/RulesSettingsView.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Hide app menus during inline reveal"),
            "Rules settings should expose the inline reveal app-menu toggle label"
        )
        XCTAssertTrue(
            source.contains("Only affects inline reveal, not Icon Panel or Second Menu Bar."),
            "Rules settings should explain that the toggle only applies to inline reveal"
        )
        XCTAssertTrue(
            source.contains("$menuBarManager.settings.hideApplicationMenusOnInlineReveal"),
            "Rules settings should bind the toggle to the persisted inline reveal app-menu setting"
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
        let controllerURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let controllerSource = try String(contentsOf: controllerURL, encoding: .utf8)
        let secondMenuBarURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SecondMenuBarView.swift")
        let secondMenuBarSource = try String(contentsOf: secondMenuBarURL, encoding: .utf8)
        let smokeURL = projectRootURL().appendingPathComponent("Scripts/live_zone_smoke.rb")
        let smokeSource = try String(contentsOf: smokeURL, encoding: .utf8)

        XCTAssertTrue(
            controllerSource.contains("let idleDelaySeconds: TimeInterval = (mode == .findIcon) ? 10 : 20"),
            "Browse panel idle timeout should use mode-specific defaults (10s icon panel, 20s second menu bar)"
        )
        XCTAssertTrue(
            controllerSource.contains("let pointerInsidePanel = self.window?.frame.contains(NSEvent.mouseLocation) == true"),
            "Idle timeout should defer when the pointer is still inside the panel"
        )
        XCTAssertTrue(
            controllerSource.contains("manager.hidingService.scheduleRehide(after: 0.2)"),
            "Idle timeout close should force a short rehide delay so the menu bar does not stay expanded"
        )
        XCTAssertTrue(
            controllerSource.contains("noteBrowseActivationStarted()") &&
                controllerSource.contains("noteBrowseActivationFinished()"),
            "Browse activation should refresh second-menu-bar idle protection around panel clicks"
        )
        XCTAssertTrue(
            controllerSource.contains("func noteSecondMenuBarInteraction()"),
            "SearchWindowController should expose an explicit second-menu-bar interaction hook so idle-close protection can refresh before the panel ages out"
        )
        XCTAssertTrue(
            secondMenuBarSource.contains("SearchWindowController.shared.noteSecondMenuBarInteraction()") &&
                secondMenuBarSource.contains("onInteraction: notePanelInteraction"),
            "Second Menu Bar interactions should refresh the idle-close budget while the user hovers, types, clicks, or moves icons (#101)"
        )
        XCTAssertTrue(
            controllerSource.contains("recent second menu bar activation"),
            "Idle timeout should explicitly defer for a short post-activation grace window"
        )
        XCTAssertTrue(
            smokeSource.contains("verify_post_activation_browse_state!") &&
                smokeSource.contains("second menu bar collapsed after activation") &&
                smokeSource.contains("expected_mode == 'secondMenuBar' ? 'windowVisible: true' : nil"),
            "Runtime smoke should reject second-menu-bar activations that immediately collapse the panel after a click"
        )
    }

    func testBrowseAppleScriptActivationUsesSameIdleProtectionAsUI() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptActivationCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if activationOrigin == .browsePanel") &&
                source.contains("browseController.noteBrowseActivationStarted()") &&
                source.contains("browseController.noteBrowseActivationFinished()"),
            "Browse AppleScript activations should opt into the same second-menu-bar idle-close protection as the panel UI path"
        )
    }

    func testPostRevealClickPathAvoidsImmediateSpatialFallback() throws {
        let searchServiceURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchServiceURL, encoding: .utf8)
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchService+Diagnostics.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)
        let interactionURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let interactionSource = try String(contentsOf: interactionURL, encoding: .utf8)

        XCTAssertTrue(
            searchSource.contains("let allowImmediateFallbackCenter = activationPlan.allowImmediateFallbackCenter") &&
                diagnosticsSource.contains("func resolvedAllowImmediateFallbackCenter("),
            "Browse-session and post-reveal click attempts should centralize immediate spatial fallback policy"
        )
        XCTAssertTrue(
            searchSource.contains("allowImmediateFallbackCenter: initialAllowImmediateFallbackCenter"),
            "Browse-session clicks should pass the computed fallback policy into click attempts"
        )
        XCTAssertTrue(
            searchSource.contains("resolvedAllowImmediateFallbackCenter(") &&
                searchSource.contains("likelyNoExtrasMenuBar: refreshedLikelyNoExtras"),
            "Forced-refresh click retries should only re-enable immediate spatial fallback through the narrowed no-AX target policy"
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

    func testActivationDiagnosticsKeepPostClickVerification() throws {
        let interactionURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+Interaction.swift")
        let interactionSource = try String(contentsOf: interactionURL, encoding: .utf8)
        let menuExtrasURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityService+MenuExtras.swift")
        let menuExtrasSource = try String(contentsOf: menuExtrasURL, encoding: .utf8)
        let combinedSource = interactionSource + "\n" + menuExtrasSource
        let diagnosticsSource = try self.diagnosticsSource()
        XCTAssertTrue(
            combinedSource.contains("kAXShownMenuUIElementAttribute"),
            "Click verification should check AXShownMenuUIElement so hardware-click success means more than event dispatch"
        )
        XCTAssertTrue(
            combinedSource.contains("observableReactionDescription"),
            "Click verification should compare before/after AX reaction snapshots"
        )

        let searchURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchURL, encoding: .utf8)
        XCTAssertTrue(
            searchSource.contains("clickMenuBarItemResult("),
            "Search activation should consume detailed click results instead of bare Bool success"
        )
        XCTAssertTrue(
            searchSource.contains("verification=\\(firstAttempt.verification)"),
            "Activation diagnostics should record first-attempt verification details"
        )
        XCTAssertTrue(
            searchSource.contains("let requireObservableReaction = activationPlan.requireObservableReaction") &&
                diagnosticsSource.contains("func acceptsClickResult("),
            "Search activation should gate browse/revealed clicks behind observable verification policy"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("verification.hasPrefix(\"verified\")"),
            "Observable-reaction click acceptance should require verified feedback, not merely non-unavailable diagnostics"
        )
        XCTAssertTrue(
            searchSource.contains("SearchWindowController.shared.isBrowseSessionActive"),
            "Second menu bar activation should use active browse-session state when deciding whether to trust a click"
        )
        XCTAssertTrue(
            searchSource.contains("Rejecting unverified click success for revealed/browse-session activation"),
            "Unverified hardware click dispatch must not be treated as success for second-menu-bar/revealed flows"
        )
    }

    private func diagnosticsSource() throws -> String {
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchService+Diagnostics.swift")
        return try String(contentsOf: diagnosticsURL, encoding: .utf8)
    }

    func testAppleScriptActivationCommandsUseRunLoopWaitInsteadOfSemaphore() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptActivationCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func runScriptActivation("),
            "AppleScript activation commands should centralize async wait behavior in a run-loop helper"
        )
        XCTAssertTrue(
            source.contains("RunLoop.current.run(mode: .default"),
            "AppleScript activation commands should pump the run loop while main-actor work completes"
        )
        XCTAssertFalse(
            source.contains("DispatchSemaphore"),
            "AppleScript activation commands must not block the main thread with a semaphore"
        )
    }

    func testListIconsAppleScriptCommandDoesNotDeadlockMainThread() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("@objc(ListIconsCommand)"),
            "ListIconsCommand should exist as a scriptable command"
        )
        XCTAssertTrue(
            source.contains("if Thread.isMainThread"),
            "ListIconsCommand should detect the main-thread scripting path"
        )
        XCTAssertTrue(
            source.contains("RunLoop.current.run(mode: .default"),
            "ListIconsCommand should pump the run loop while waiting for async refresh on the main thread"
        )
        XCTAssertTrue(
            source.contains("runScriptRead(timeoutSeconds: 15.0)"),
            "ListIconsCommand should use the shared read helper with a longer timeout for slower owner scans"
        )
        XCTAssertTrue(
            source.contains("scriptErrorOperationTimedOut(self)"),
            "ListIconsCommand should report a real timeout instead of silently returning an empty result"
        )
    }

}
