@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardMoveActivationXCTests: RuntimeGuardTestCase {
    func testVisibleAndAlwaysHiddenRetriesReResolveTargets() throws {
        let standardURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let standardSource = try String(contentsOf: standardURL, encoding: .utf8)
        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)
        let resolverURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTargetResolver.swift")
        let resolverSource = try String(contentsOf: resolverURL, encoding: .utf8)

        XCTAssertTrue(
            standardSource.contains("let retryTargets = await manager.moveTargetResolver.resolveMoveTargetsWithRetries("),
            "Standard retry path should refresh move targets before retrying"
        )
        XCTAssertTrue(
            standardSource.contains("let retryLabel = request.toHidden ? \"hidden\" : \"visible\""),
            "Standard retry path should label hidden and visible re-resolution distinctly in logs"
        )
        XCTAssertTrue(
            standardSource.contains("Re-resolved \\(retryLabel) move targets for retry"),
            "Standard retry path should log the re-resolved target set for both hidden and visible retries"
        )
        XCTAssertFalse(
            standardSource.contains("if !success,\n               !request.toHidden,\n               actionableMoveSafety.allowsClassifiedZoneFallback"),
            "Standard retry path should not special-case visible moves before the extra drag"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("Re-resolved always-hidden move targets for retry"),
            "Always-hidden retry path should refresh separator targets before retrying"
        )
        XCTAssertTrue(
            resolverSource.contains("Waiting for live always-hidden separator geometry before move target acceptance"),
            "Always-hidden moves should wait for live AH separator geometry before trusting cached drag targets"
        )
        XCTAssertTrue(
            resolverSource.contains("let liveBoundaryX = manager.geometryResolver.inboundAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: true)") &&
                resolverSource.contains("targets: (liveBoundaryX, nil)") &&
                resolverSource.contains("alwaysHiddenSeparatorIsLive: liveBoundaryX != nil") &&
                resolverSource.contains("mainSeparatorIsLive: liveBoundaryX != nil"),
            "To-Always-Hidden moves should require live AH separator geometry and allow cached main separator geometry during shielded reveal"
        )
        XCTAssertTrue(
            resolverSource.contains("Always-hidden move target resolution failed without live separator geometry"),
            "Always-hidden move target resolution must fail closed instead of returning cached-only targets at the retry limit"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("await manager.moveTargetResolver.resolveAlwaysHiddenMoveTargetsWithRetries("),
            "Always-hidden move pipelines should use the dedicated always-hidden target resolver instead of a one-shot separator lookup"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("Re-resolved AH-to-Hidden targets for retry"),
            "AH-to-Hidden retry path should refresh separator targets before retrying"
        )
        XCTAssertTrue(
            standardSource.contains("Move accepted after classification verification"),
            "Standard move path should reconcile verification failures with classified zones before returning false"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("Always-hidden move accepted after classification verification"),
            "Always-hidden move path should reconcile verification failures with classified zones before returning false"
        )
        XCTAssertTrue(
            standardSource.contains("let shouldAttemptShieldFallback = !success && (request.toHidden ? !usedShowAllShield : true)"),
            "Visible moves should get one shield-backed final retry even when the standard retry already ran"
        )
        XCTAssertTrue(
            standardSource.contains("Visible move still failed after standard retry while already using showAll shield - refreshing move targets once more"),
            "Visible moves that were already using the shield path should still get one last target refresh before failing"
        )
        XCTAssertTrue(
            standardSource.contains("Shield fallback could not resolve ordered visible boundary - keeping failure"),
            "Visible shield fallback should refuse to retry without an ordered visible boundary"
        )
        XCTAssertTrue(
            resolverSource.contains("func verifyVisibleMoveWithFreshGeometry("),
            "Visible return moves should have a narrow fresh-geometry recheck before spending another drag"
        )
        XCTAssertTrue(
            resolverSource.contains("Visible move accepted after fresh geometry recheck"),
            "Fresh geometry acceptance should stay explicit in source so stale-separator fixes do not silently regress"
        )
        XCTAssertTrue(
            standardSource.contains("if !success, !request.toHidden {") &&
                standardSource.contains("success = await manager.moveTargetResolver.verifyVisibleMoveWithFreshGeometry(") &&
                standardSource.contains("identity: sourceIdentity,"),
            "Regular visible returns should attempt the fresh-geometry recheck before the retry drag"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("if !success, !toAlwaysHidden {") &&
                alwaysHiddenSource.contains("success = await manager.moveTargetResolver.verifyVisibleMoveWithFreshGeometry("),
            "Always-hidden visible returns should attempt the same fresh-geometry recheck before retrying"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("targetLane: toAlwaysHidden ? .alwaysHidden : .visibleFromAlwaysHidden"),
            "Always-hidden visible returns should use a separator-adjacent visible insertion target instead of the normal hidden-to-visible target"
        )
    }

    func testAppleScriptMoveTimeoutAllowsShieldFallbackPath() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("func runScriptMove(timeoutSeconds: TimeInterval = 9.0"),
            "AppleScript move commands should allow enough time for the hardened fallback path before reporting a timeout"
        )
        XCTAssertTrue(
            source.contains("task.cancel()") &&
                source.contains("MenuBarManager.shared.activeMoveTask?.cancel()"),
            "AppleScript move timeouts should cancel the wrapper and active move task"
        )
        XCTAssertFalse(
            source.contains("MenuBarManager.shared.activeMoveTask = nil") ||
                source.contains("SearchWindowController.shared.setMoveInProgress(false)"),
            "AppleScript timeout handling must not mark the move lane idle before the shared move coordinator finishes rollback and cleanup"
        )
    }

    func testAlwaysHiddenRepairAndDragLookupAreMoveSafe() throws {
        let pinURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenPinWorkflow.swift")
        let pinSource = try String(contentsOf: pinURL, encoding: .utf8)
        let dragURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarDragService.swift")
        let dragSource = try String(contentsOf: dragURL, encoding: .utf8)
        let interactionPolicySource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            pinSource.contains("guard !SearchWindowController.shared.isMoveInProgress else") &&
                pinSource.contains("Always-hidden separator repair skipped while icon move is in progress"),
            "Always-hidden separator repair must not remove/recreate status items during an active drag"
        )
        XCTAssertTrue(
            dragSource.contains("let usablePreferredCenterX = AccessibilityMenuExtraFrameResolver.screenValidPreferredCenterX(") &&
                dragSource.contains("Dropping off-screen preferredCenterX before drag lookup") &&
                dragSource.contains("preferredCenterX: usablePreferredCenterX"),
            "Drag lookup should ignore stale off-screen preferred centers from prior fullscreen/notch layouts"
        )
        XCTAssertTrue(
            dragSource.contains("AccessibilityInteractionPolicy.frameStartsInNotchUnsafeMenuBarRegion") &&
                dragSource.contains("Refusing visible move from notch-unsafe drag origin") &&
                dragSource.contains("notch-unsafe drag source beforeMidX") &&
                dragSource.contains("AccessibilityMenuBarMoveFailureStore.shared.record") &&
                dragSource.contains("resolvedTargetLane == .visible || resolvedTargetLane == .visibleFromAlwaysHidden") &&
                interactionPolicySource.contains("topOriginMenuBandMaxY") &&
                interactionPolicySource.contains("Status items live in the right auxiliary area on notched MacBooks") &&
                interactionPolicySource.contains("frame.minX < unsafeRightX + rightAuxiliaryInset"),
            "Visible return moves must fail closed from top-origin AX menu-bar frames under the MacBook notch"
        )
    }

    func testAppleScriptZoneGeometryExposesNotchSafeDragSourcesForRuntimeSmoke() throws {
        let listingSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/AppleScriptIconListingCommands.swift"),
            encoding: .utf8
        )
        let sdefSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Resources/SaneBar.sdef"),
            encoding: .utf8
        )
        let smokeSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Scripts/live_zone_smoke.rb"),
            encoding: .utf8
        )
        let moveSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Scripts/lib/live_zone_smoke_moves.rb"),
            encoding: .utf8
        )

        XCTAssertTrue(
            sdefSource.contains("command name=\"list icon zone geometry\"") &&
                sdefSource.contains("ListIconZoneGeometryCommand"),
            "Runtime smoke needs a scriptable geometry listing instead of inferring notch safety from zone names"
        )
        XCTAssertTrue(
            listingSource.contains("@objc(ListIconZoneGeometryCommand)") &&
                listingSource.contains("auxiliaryTopRightArea") &&
                listingSource.contains("xPosition < rightArea.minX + rightAuxiliaryInset") &&
                listingSource.contains("AccessibilityInteractionPolicy.frameStartsInNotchUnsafeMenuBarRegion") &&
                listingSource.contains("dragSourceSafety") &&
                listingSource.contains("offscreen"),
            "The app should report whether a menu-extra drag source is safe on the current notched or non-notched screen"
        )
        XCTAssertTrue(
            smokeSource.contains("list icon zone geometry") &&
                smokeSource.contains("drag_source_safety") &&
                smokeSource.contains("unsafe_always_hidden_drag_source?") &&
                smokeSource.contains("drag_source_safe?") &&
                smokeSource.contains("notch_unsafe_required_skip?"),
            "The release harness should consume app-reported geometry and remove unsafe Always Hidden outbound sources"
        )
        XCTAssertTrue(
            moveSource.contains("safe_matrix_drag_source_candidates") &&
                moveSource.contains("Refusing outbound move from unsafe drag source"),
            "Move-matrix resume should skip known unsafe sources and fail closed if live geometry becomes unsafe before the drag"
        )
    }

    func testFullscreenZonePersistenceDoesNotRequireMovableBaselineIds() throws {
        let sourceURL = projectRootURL().appendingPathComponent("Scripts/lib/live_zone_smoke_browse_visual.rb")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        guard let baselineRange = source.range(of: "def capture_fullscreen_space_transition_zone_baseline!"),
              let baselineNextRange = source[baselineRange.upperBound...].range(of: "\n  def ")
        else {
            XCTFail("Expected capture_fullscreen_space_transition_zone_baseline! helper in live zone smoke visual script")
            return
        }
        let baselineSource = String(source[baselineRange.lowerBound ..< baselineNextRange.lowerBound])
        guard let methodRange = source.range(of: "def fullscreen_space_transition_zone_ids"),
              let nextMethodRange = source[methodRange.upperBound...].range(of: "\n  def ")
        else {
            XCTFail("Expected fullscreen_space_transition_zone_ids helper in live zone smoke visual script")
            return
        }
        let methodSource = String(source[methodRange.lowerBound ..< nextMethodRange.lowerBound])

        XCTAssertFalse(
            baselineSource.contains("reseed_missing_zone_candidates"),
            "Fullscreen baseline proof must not drag a representative donor just to create a visible ID on notched MacBooks"
        )
        XCTAssertFalse(
            methodSource.contains("item[:movable]"),
            "Fullscreen zone persistence proof should accept stable visible IDs even when they are not safe move donors on notched MacBooks"
        )
    }

    func testMoveTargetResolutionWaitsForLiveSeparatorFrame() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTargetResolver.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let liveSeparatorReady = separatorOverrideX != nil || manager.geometryResolver.currentLiveSeparatorFrame() != nil"),
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
        XCTAssertTrue(
            source.contains("Hidden move target resolution failed without live separator geometry"),
            "Hidden moves should fail closed instead of returning cached-only targets after lifecycle recovery"
        )
    }

    func testMoveTargetResolutionUsesOrderedGeometryInsteadOfPositiveXGuards() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTargetResolver.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let geometryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarGeometryResolver.swift")
        let geometrySource = try String(contentsOf: geometryURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("hiddenBoundaryIsOrdered") &&
                source.contains("visibleBoundaryIsOrdered"),
            "Move target readiness should be based on boundary ordering so negative global X remains valid on left-arranged displays"
        )
        XCTAssertFalse(
            source.contains("separatorX > 0") ||
                source.contains("visibleBoundaryX > 0") ||
                source.contains("candidateBoundaryX > 0") ||
                source.contains("(targets.visibleBoundaryX ?? 0) > 0"),
            "Move target resolution must not use positive-X checks for live geometry validity"
        )
        XCTAssertFalse(
            geometrySource.contains("cachedX > 0 ? cachedX : nil") ||
                geometrySource.contains("return cachedX > 0"),
            "Blocking-mode separator right-edge fallback must accept ordered negative coordinates on left-arranged displays"
        )
    }

    func testAppleScriptAlwaysHiddenMovesUseStandardMovePath() throws {
        let source = try appleScriptCommandSource()
        let alwaysHiddenVisibleBranch = """
                    case .alwaysHidden:
                        let removedPin = manager.alwaysHiddenPinWorkflow.unpin(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.alwaysHiddenPinWorkflow.unpin(bundleID: icon.bundleId))
                        if removedPin {
                            manager.saveSettings()
                        }
                        let moved = runScriptMove {
                            await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toAlwaysHidden: false
                            )
                        }
        """

        XCTAssertTrue(
            source.contains("var skipZoneWait: Bool = false"),
            "AppleScript move routing should track no-op moves and skip zone wait when no move is needed"
        )
        XCTAssertTrue(
            source.contains("if outcome.skipZoneWait {"),
            "No-op move requests should return success without polling for zone convergence"
        )
        XCTAssertTrue(
            source.contains("sourceZone == targetZone"),
            "AppleScript routing should detect when an icon is already in the requested zone"
        )
        XCTAssertTrue(
            source.contains("await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(") &&
                source.contains("await manager.moveQueueWorkflow.moveIconFromAlwaysHiddenToHiddenAndWait("),
            "Always-hidden sources should route through the dedicated manager move helpers instead of rolling their own pin mutation first"
        )
        XCTAssertTrue(
            source.contains("await manager.moveQueueWorkflow.moveIconFromAlwaysHiddenToHiddenAndWait("),
            "Always-hidden to hidden should use the dedicated helper so showAll runs even when the bar is merely expanded"
        )
        XCTAssertTrue(
            source.contains("await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(") &&
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

    func testAlwaysHiddenToHiddenMovePreservesPreHideSnapshot() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Capturing AH-to-Hidden move snapshot before re-hide") &&
                source.contains("await manager.moveTaskCoordinator.refreshAccessibilityCacheAfterMove()") &&
                source.contains("AccessibilityService.shared.preserveFreshMenuBarItemPositionsAfterManualMove()"),
            "AH-to-Hidden moves should preserve the shown-state post-move cache so immediate AppleScript verification does not reclassify regular Hidden as Always Hidden after re-hide"
        )
    }

    func testAlwaysHiddenToHiddenMoveUsesRegularHiddenLaneBoundaries() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("separatorX: targets.mainSeparatorOriginX") &&
                source.contains("visibleBoundaryX: targets.alwaysHiddenSeparatorRightEdgeX") &&
                source.contains("targetLane: .hiddenFromAlwaysHidden"),
            "AH-to-Hidden moves must use the main separator as the hidden-lane right edge, the AH separator as the left boundary, and the dedicated AH-origin hidden-lane target"
        )
        XCTAssertTrue(
            source.contains("manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()") &&
                source.contains("manager.geometryResolver.currentLiveSeparatorFrame()") &&
                source.contains("mainSeparatorOriginX > alwaysHiddenSeparatorRightEdgeX"),
            "AH-to-Hidden physical moves must require live ordered separator geometry instead of raw or cached AH separator frames"
        )
        XCTAssertFalse(
            source.contains("alwaysHiddenButton.window") ||
                source.contains("alwaysHiddenWindow.frame"),
            "AH-to-Hidden must not trust raw AH separator window frames; parked/off-screen frames were the #155 failure mode"
        )
        XCTAssertFalse(
            source.contains("alwaysHiddenSeparatorRightEdgeX > 0"),
            "AH-to-Hidden live geometry must stay sign-independent; negative global X is valid on displays arranged left of the primary"
        )
    }

    func testAlwaysHiddenToHiddenRepairsMissingLiveTargetsAfterReveal() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("requiresAlwaysHiddenToHiddenTargets: true") &&
                source.contains("if requiresAlwaysHiddenToHiddenTargets") &&
                source.contains("let liveTargetsReady: Bool = if requiresAlwaysHiddenToHiddenTargets {") &&
                source.contains("await currentAlwaysHiddenToHiddenTargets() != nil") &&
                source.contains("repairStatusItemsForAlwaysHiddenToHiddenTargetsIfNeeded") &&
                source.contains(".recreateFromPersistedLayout(.invalidStatusItems)") &&
                source.contains("Always-hidden move geometry is not live after showAll; recreating AH separator before retry") &&
                source.contains("Outbound AH-to-Hidden targets stayed unavailable after AH separator repair"),
            "AH-to-Hidden moves must repair missing live AH/main separator targets after reveal, including the main/separator status-item graph, instead of failing just because the source icon is visible"
        )
    }

    func testAlwaysHiddenInboundMoveAllowsCachedMainSeparatorBoundaryDuringShieldedReveal() throws {
        let workflowURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let workflowSource = try String(contentsOf: workflowURL, encoding: .utf8)
        let resolverURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarGeometryResolver.swift")
        let resolverSource = try String(contentsOf: resolverURL, encoding: .utf8)
        let targetURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTargetResolver.swift")
        let targetSource = try String(contentsOf: targetURL, encoding: .utf8)

        XCTAssertTrue(
            resolverSource.contains("currentLiveAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: Bool = false)") &&
                resolverSource.contains("} else if allowCachedMainSeparator {") &&
                resolverSource.contains("separatorRightEdgeX(allowEstimatedFallback: false)") &&
                resolverSource.contains("func inboundAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: Bool = false)") &&
                resolverSource.contains("StatusBarPositionDefaultsStore.resolvedPreferredPosition(") &&
                resolverSource.contains("referenceScreen.frame.maxX - CGFloat(preferredPosition)") &&
                resolverSource.contains("Rejecting live AH separator boundary") &&
                resolverSource.contains("Using seeded AH separator boundary without a live/cached main separator boundary for inbound move") &&
                resolverSource.contains("Using seeded AH separator boundary after rejecting stale main separator boundary") &&
                workflowSource.contains("inboundAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: true)") &&
                targetSource.contains("inboundAlwaysHiddenSeparatorBoundaryX(allowCachedMainSeparator: true)"),
            "Inbound Always Hidden moves should accept a seeded notch-safe AH boundary when showAll leaves live AH and main separator frames unavailable"
        )
    }

    func testAlwaysHiddenToVisibleUsesSeparatorAdjacentVisibleTarget() throws {
        let policyURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)
        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)

        XCTAssertTrue(
            policySource.contains("case visibleFromAlwaysHidden") &&
                policySource.contains("let laneMidX = separatorX + (visibleLaneWidth * 0.5)") &&
                policySource.contains("return min(max(laneMidX, minX), maxX)"),
            "AH-to-visible moves should target the visible lane midpoint (clamped away from the SaneBar icon) so menu bar reflow cannot strand the icon at the separator"
        )
        XCTAssertTrue(
            alwaysHiddenSource.contains("targetLane: toAlwaysHidden ? .alwaysHidden : .visibleFromAlwaysHidden"),
            "AH-to-visible drag and retry paths should use the dedicated separator-adjacent lane"
        )
    }

    func testAlwaysHiddenOutboundMovesUseLongerRevealSettle() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private let alwaysHiddenOutboundRevealSettleMilliseconds = 1500") &&
                source.contains("let revealSettleMilliseconds = toAlwaysHidden ? 300 : alwaysHiddenOutboundRevealSettleMilliseconds") &&
                source.contains("try? await Task.sleep(for: .milliseconds(alwaysHiddenOutboundRevealSettleMilliseconds))"),
            "Always Hidden outbound moves should let unpin + showAll settle before the physical drag"
        )
    }

    func testRuntimeSmokeRequiresProAccessForFocusedExactIdLanes() throws {
        let source = try scriptSource(entrypoint: "qa.rb", partialPrefix: "project_qa")

        XCTAssertTrue(
            source.contains("focused_runtime_smoke_pro_error(target, lane_name)") &&
                source.contains("licenseIsPro") &&
                source.contains("runtime_smoke_target_process_detail(target)") &&
                source.contains("paid license or active Pro trial"),
            "Focused exact-ID runtime smoke should fail early with Pro/process diagnostics before moving Apple menu extras"
        )
        XCTAssertTrue(
            source.contains("require_no_keychain && !command.include?('--sane-no-keychain')"),
            "Runtime smoke should not accept a real-keychain process when the target was launched for no-keychain release automation"
        )
        XCTAssertFalse(
            source.contains(".filter_map"),
            "Project QA must avoid newer Ruby helpers because the Mini runtime can be older than the controller machine"
        )
    }

    func testHiddenStateClassificationUsesPinnedFallbackForAlwaysHidden() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let classifierURL = projectRootURL().appendingPathComponent("Core/Services/SearchMenuBarZoneClassifier.swift")
        let classifierSource = try String(contentsOf: classifierURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("shouldUsePinnedAlwaysHiddenFallback"),
            "Hidden and browse-session classification should centralize the pinned-ID fallback policy"
        )
        XCTAssertTrue(
            source.contains("MenuBarManager.shared.geometryResolver.alwaysHiddenSeparatorBoundaryX() == nil") &&
                source.contains("return (separatorX, nil)"),
            "Pinned-ID fallback should force two-zone split only when live always-hidden geometry is unavailable"
        )
        XCTAssertTrue(
            classifierSource.contains("post-pass moved"),
            "When AH geometry is disabled, pinned IDs should still populate always-hidden classification"
        )
    }

    func testShouldSkipHideForExternalMonitorPolicy() {
        XCTAssertTrue(MenuBarVisibilityPolicy.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarVisibilityPolicy.shouldSkipHide(disableOnExternalMonitor: false, isOnExternalMonitor: true))
        XCTAssertFalse(MenuBarVisibilityPolicy.shouldSkipHide(disableOnExternalMonitor: true, isOnExternalMonitor: false))
    }

    func testStartupRecoveryTriggersWhenSeparatorIsRightOfMain() {
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 1200,
                mainX: 1100
            )
        )
    }

    func testStartupRecoveryDoesNotTriggerForHealthyOrdering() {
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100
            )
        )
    }

    func testStartupRecoveryTriggersWhenMainIconIsTooFarFromRightEdge() {
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 900,
                screenWidth: 1440
            )
        )
    }

    func testStartupRecoveryAllowsReasonableRightEdgeGap() {
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 300,
                screenWidth: 1440
            )
        )
    }

    func testStartupRecoveryTriggersWhenMainIconDriftsIntoNotchDeadZone() {
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
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
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
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
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: 1100,
                mainRightGap: 301,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
    }

    func testStartupRecoveryAllowsCrowdedNotchedRightZone() {
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 1050,
                mainX: 1219,
                mainRightGap: 290,
                screenWidth: 1470,
                notchRightSafeMinX: 825
            )
        )
    }

    func testStartupRecoveryDoesNotTriggerWithMissingCoordinates() {
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: nil,
                mainX: 1100
            )
        )
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 900,
                mainX: nil
            )
        )
    }

    func testSearchServiceRefreshesTargetAfterReveal() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchServiceSupport.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)
        let resolverURL = projectRootURL().appendingPathComponent("Core/Services/SearchActivationTargetResolver.swift")
        let resolverSource = try String(contentsOf: resolverURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("SearchActivationTargetResolver.waitForIconOnScreen(app: app") &&
                resolverSource.contains("static func waitForIconOnScreen("),
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
        let gateURL = projectRootURL().appendingPathComponent("Core/Services/SearchActivationGate.swift")
        let gateSource = try String(contentsOf: gateURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("SearchActivationGate(debounceInterval: 0.45)") &&
                gateSource.contains("debounceInterval: TimeInterval"),
            "SearchService.activate should debounce rapid duplicate requests to prevent panel lockups on double-click"
        )
        XCTAssertTrue(
            source.contains("activationGate.begin(for: app.uniqueId"),
            "SearchService.activate should pass through shared activation guard logic"
        )
    }

    func testSearchServiceSkipsActivationWhenAnotherActivationIsInFlight() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchActivationGate.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if let inFlightAppID"),
            "SearchService.activate should reject overlapping activation workflows while one request is in progress"
        )
    }

    func testSearchServiceRunsClickOffMainAndSkipsSlowRetry() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let clickURL = projectRootURL().appendingPathComponent("Core/Services/SearchClickAttemptService.swift")
        let clickSource = try String(contentsOf: clickURL, encoding: .utf8)
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchServiceSupport.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)

        XCTAssertTrue(
            clickSource.contains("withTaskGroup(of: SearchClickAttemptResult.self)"),
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
            diagnosticsSource.contains("if origin == .browsePanel {") &&
                diagnosticsSource.contains("return true"),
            "Browse-panel hardware-vs-AX policy should route all panel clicks through hardware-first so unverified AXPress successes get a real click attempt"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("if app.menuExtraIdentifier == nil"),
            "Direct activation should still prefer hardware-first when a status item lacks stable AX per-item identity"
        )
        XCTAssertTrue(
            source.contains("let activationPlan = SearchServiceSupport.activationPlan(") &&
                source.contains("if activationPlan.allowWorkspaceActivationFallback"),
            "SearchService.activate should drive fallback policy from one activation plan so browse-panel right-click failures do not steal focus"
        )
        XCTAssertTrue(
            source.contains("NSApp.yieldActivation(to: runningApp)") &&
                source.contains("runningApp.activate(options: [])"),
            "Workspace activation fallback should use cooperative activation on modern macOS before requesting the target app to activate"
        )
    }
}
