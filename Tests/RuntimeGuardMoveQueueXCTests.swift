@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardMoveQueueXCTests: RuntimeGuardTestCase {
    func testStaleGeometryFallbackLogsAreDeduplicated() throws {
        let cacheURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarGeometryCache.swift")
        let cacheSource = try String(contentsOf: cacheURL, encoding: .utf8)
        let resolverURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarGeometryResolver.swift")
        let resolverSource = try String(contentsOf: resolverURL, encoding: .utf8)

        XCTAssertTrue(
            cacheSource.contains("var hasLoggedStaleSeparatorRightEdgeFallback = false") &&
                cacheSource.contains("var hasLoggedStaleMainStatusItemFallback = false"),
            "MenuBarGeometryCache should track whether stale-frame fallback warnings were already emitted for the current recovery window"
        )
        XCTAssertTrue(
            resolverSource.contains("if !cache.hasLoggedStaleSeparatorRightEdgeFallback {") &&
                resolverSource.contains("cache.hasLoggedStaleSeparatorRightEdgeFallback = false"),
            "Separator fallback logging should emit once per stale-frame window and reset when live geometry returns"
        )
        XCTAssertTrue(
            resolverSource.contains("if !cache.hasLoggedStaleMainStatusItemFallback {") &&
                resolverSource.contains("cache.hasLoggedStaleMainStatusItemFallback = false"),
            "Main status-item fallback logging should emit once per stale-frame window and reset when live geometry returns"
        )
    }

    func testBrowseViewsWaitOnQueuedMoveTasksInsteadOfGuessingWithDelays() throws {
        let iconPanelURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelMoveQueue.swift")
        let iconPanelSource = try String(contentsOf: iconPanelURL, encoding: .utf8)
        let secondMenuBarSource = try secondMenuBarSource()
        let queueURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveQueueWorkflow.swift")
        let queueSource = try String(contentsOf: queueURL, encoding: .utf8)
        let verifierURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveVerifier.swift")
        let verifierSource = try String(contentsOf: verifierURL, encoding: .utf8)
        let taskURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let taskSource = try String(contentsOf: taskURL, encoding: .utf8)

        XCTAssertTrue(
            queueSource.contains("MenuBarZoneMoveRequest") &&
                queueSource.contains("func queueZoneMove(") &&
                queueSource.contains("func queueZoneMoveAfterDrop(") &&
                queueSource.contains("prepareAlwaysHiddenMoveQueueAfterDrop") &&
                queueSource.contains("ensureAlwaysHiddenSeparatorReadyAfterDrop") &&
                queueSource.contains("try? await Task.sleep(for: .milliseconds(50))") &&
                taskSource.contains("enum QueuedAlwaysHiddenMutation") &&
                taskSource.contains("optimisticAlwaysHiddenMutation") &&
                verifierSource.contains("classifyItemsForMoveVerification") &&
                taskSource.contains("applyQueuedAlwaysHiddenMutation(optimisticAlwaysHiddenMutation)") &&
                taskSource.contains("lastManualZoneMoveSettledAt"),
            "The move engine should keep queued zone-move planning, nonblocking drop preflight, classified physical verification, and post-success always-hidden pin mutation wired together"
        )
        XCTAssertTrue(
            iconPanelSource.contains("queueZoneMove(app: app, request: request)") &&
                iconPanelSource.contains("queueZoneMoveAfterDrop(app: app, request: request)") &&
                iconPanelSource.contains("guard let request,") &&
                iconPanelSource.contains("let moved = await task.value") &&
                iconPanelSource.contains("queueMoveAfterDrop") &&
                iconPanelSource.contains("queueReorderAfterDrop") &&
                iconPanelSource.contains("await Task.yield()") &&
                !iconPanelSource.contains("pinAlwaysHidden(app: app)") &&
                !iconPanelSource.contains("unpinAlwaysHidden(app: app)"),
            "Icon panel move flows should delegate queue planning to MenuBarManager and defer drag-drop queueing until after SwiftUI finishes the drop callback"
        )
        XCTAssertTrue(
            secondMenuBarSource.contains("queueZoneMove(app: app, request: request)") &&
                secondMenuBarSource.contains("queueZoneMoveAfterDrop(app: app, request: request)") &&
                secondMenuBarSource.contains("guard let request,") &&
                secondMenuBarSource.contains("let moved = await task.value") &&
                secondMenuBarSource.contains("applySuccessfulMovePresentation") &&
                secondMenuBarSource.contains("queueMoveAfterDrop") &&
                secondMenuBarSource.contains("await Task.yield()") &&
                !secondMenuBarSource.contains("pinAlwaysHidden(app: app)") &&
                !secondMenuBarSource.contains("unpinAlwaysHidden(app: app)"),
            "Second menu bar moves should wait on the shared manager-owned zone move result and defer drag-drop queueing until after SwiftUI finishes the drop callback"
        )
        XCTAssertFalse(
            secondMenuBarSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)"),
            "Second menu bar should stop guessing move completion with a fixed timer"
        )
    }

    func testAppleScriptAlwaysHiddenMovesUseManagerOwnedPinMutation() throws {
        let source = try appleScriptCommandSource()
        let managerURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)

        XCTAssertTrue(
            managerSource.contains("? .pin(") &&
                managerSource.contains(": .unpin(") &&
                managerSource.contains("optimisticAlwaysHiddenMutation: optimisticMutation"),
            "The move engine should own always-hidden optimistic pin and unpin mutations for both queued and awaited move flows"
        )
        XCTAssertTrue(
            source.contains("manager.saveSettings()") &&
                source.contains("await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait("),
            "AppleScript move commands should route always-hidden moves through the manager-owned move lifecycle"
        )
        XCTAssertFalse(
            source.contains("if !moved {\n                        _ = manager.alwaysHiddenPinWorkflow.unpin("),
            "AppleScript move commands should stop hand-rolling always-hidden rollback logic on move failure"
        )
    }

    func testShowIconOnlyUnpinsAfterVerifiedMoveOutOfAlwaysHidden() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("let startZones = zonesForScriptMoveResolution(trimmedId)") &&
                source.contains("source.zone == .alwaysHidden") &&
                source.contains("await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait("),
            "Show icon should resolve a real always-hidden source item and route the restore through the manager-owned always-hidden move path"
        )
        XCTAssertTrue(
            source.contains("let removedPin = manager.alwaysHiddenPinWorkflow.unpin(") &&
                source.contains("guard moved else {"),
            "Show icon should only clear pins after a successful visible restore, not before proving the move worked"
        )
        XCTAssertFalse(
            source.contains("pinId.hasPrefix(trimmedId)"),
            "Show icon should stop using prefix pin matches that can silently unpin the wrong item"
        )
    }

    func testMoveIconClearsStaleAlwaysHiddenPinsForVisibleMovesAndAfterHiddenMoves() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("if !request.toHidden {"),
            "Pre-move stale-pin cleanup should run only for move-to-visible paths"
        )
        XCTAssertTrue(
            source.contains("removedPin = manager.alwaysHiddenPinWorkflow.unpin("),
            "moveIcon should clear stale always-hidden pins through targeted unpin helpers"
        )
        XCTAssertTrue(
            source.contains("Cleared stale always-hidden pin before move-to-visible"),
            "Visible move pre-clear should emit an explicit log marker"
        )
        XCTAssertTrue(
            source.contains("context.success") &&
                source.contains("context.request.toHidden") &&
                source.contains("context.request.clearAlwaysHiddenPinAfterMove"),
            "Hidden moves should defer stale-pin cleanup until after successful drag completion"
        )
        XCTAssertTrue(
            source.contains("Cleared stale always-hidden pin after successful move-to-hidden"),
            "Hidden move deferred cleanup should emit an explicit post-move log marker"
        )
    }

    func testMoveIconUsesShieldFallbackWhenHiddenMoveFailsOutsideHiddenState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("let shouldAttemptShieldFallback = !success && (request.toHidden ? !usedShowAllShield : true)"),
            "Hidden moves that fail while state appears expanded should still be eligible for one shield fallback retry"
        )
        XCTAssertTrue(
            source.contains("await manager.hidingService.showAll()"),
            "Shield fallback should force showAll before recomputing move targets"
        )
        XCTAssertTrue(
            source.contains("let restoreShieldIfNeeded = { () async in"),
            "moveIcon should centralize shield restoration so fallback retries cannot leave geometry half-transitioned"
        )
    }

    func testHiddenMoveTargetResolutionRepairsStaleSeparatorOriginFromRightEdge() throws {
        let movingURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let movingSource = try String(contentsOf: movingURL, encoding: .utf8)
        let resolverURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTargetResolver.swift")
        let resolverSource = try String(contentsOf: resolverURL, encoding: .utf8)

        XCTAssertTrue(
            resolverSource.contains("let derivedFromRightEdge: CGFloat? = {"),
            "Hidden-target resolution should derive separator origin from right-edge cache for stale-frame recovery"
        )
        XCTAssertTrue(
            resolverSource.contains("if origin + 40 < derivedFromRightEdge"),
            "Hidden-target resolution should detect implausibly-left origin values after transitions"
        )
        XCTAssertTrue(
            resolverSource.contains("Hidden move target corrected from stale origin"),
            "Hidden-target repair should emit an explicit log marker for stale-origin corrections"
        )
        XCTAssertTrue(
            movingSource.contains("Hidden move target drifted too far left"),
            "Hidden-target resolution should reject implausible separator drift and re-resolve under shield"
        )
        XCTAssertTrue(
            movingSource.contains("separatorOverrideX == nil") &&
                resolverSource.contains("separatorOverrideX == nil"),
            "Hidden-target drift guard must not run for always-hidden separator overrides"
        )
        XCTAssertTrue(
            resolverSource.contains("geometryResolver.alwaysHiddenSeparatorBoundaryX()"),
            "Always-hidden move targeting should use AH right-edge boundary, not AH origin"
        )
        XCTAssertTrue(
            resolverSource.contains("AH separator boundary for hidden target"),
            "Hidden move target resolution should log AH boundary usage from the boundary helper"
        )
        XCTAssertTrue(
            resolverSource.contains("Ignoring AH boundary >= separator during hidden move target resolution"),
            "Hidden move target resolution should reject invalid AH boundaries that overlap the main separator"
        )
    }

    func testSearchClassificationUsesAlwaysHiddenBoundaryRightEdge() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("geometryResolver.alwaysHiddenSeparatorBoundaryX()"),
            "Search classification should use AH boundary/right-edge for zone splits near the AH divider"
        )
    }

    func testAllTabClassificationUsesSameAlwaysHiddenBoundaryNormalizationAsRuntimeClassifier() throws {
        let modelURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelModels.swift")
        let modelSource = try String(contentsOf: modelURL, encoding: .utf8)
        let navigationURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView+Navigation.swift")
        let navigationSource = try String(contentsOf: navigationURL, encoding: .utf8)

        XCTAssertTrue(
            modelSource.contains("alwaysHiddenBoundaryForAllTab(") &&
                modelSource.contains("SearchService.normalizedAlwaysHiddenBoundary(") &&
                navigationSource.contains("geometryResolver.alwaysHiddenSeparatorBoundaryX()"),
            "All-tab zone classification should use the same normalized always-hidden boundary model as the runtime classifier"
        )
    }

    func testAccessibilityClickSkipsAXPressForOffscreenItems() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityClickService.swift")
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
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func canAutoRehideAtFireTime() -> Bool"),
            "Visibility workflow should centralize fire-time rehide guard logic in a dedicated helper"
        )
        XCTAssertTrue(
            source.contains("if manager.hoverService.isSuspended"),
            "Rehide guard should explicitly allow auto-rehide while Browse Icons intentionally suspends hover monitoring"
        )
        XCTAssertTrue(
            source.contains("MenuBarVisibilityPolicy.shouldBlockRehideForMouseLocation"),
            "Fire-time rehide should distinguish the top strip from the real below-strip menu interaction zone"
        )
    }

    func testAppChangeRehideRequiresAutoRehideEnabled() throws {
        let policyURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityPolicy.swift")
        let typesURL = projectRootURL().appendingPathComponent("Core/Models/MenuBarVisibilityTypes.swift")
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let observerURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarObserverWorkflow.swift")
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let lifecycleURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarLifecycleWorkflow.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)
        let typesSource = try String(contentsOf: typesURL, encoding: .utf8)
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let observerSource = try String(contentsOf: observerURL, encoding: .utf8)
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)
        let lifecycleSource = try String(contentsOf: lifecycleURL, encoding: .utf8)

        XCTAssertTrue(
            policySource.contains("guard autoRehideEnabled else { return false }") &&
                observerSource.contains("MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange"),
            "App-change rehide should bail out when auto-rehide is disabled through the dedicated visibility policy"
        )
        XCTAssertTrue(
            observerSource.contains("autoRehideEnabled: manager.settings.autoRehide"),
            "MenuBarManager should pass the live auto-rehide setting into app-change rehide decisions"
        )
        XCTAssertTrue(
            typesSource.contains("struct AutoRehideSettingsChangeContext") &&
                policySource.contains("shouldArmAutoRehideAfterSettingsChange") &&
                observerSource.contains("applyAutoRehideSettingsChange(from: oldSettings, to: newSettings)") &&
                observerSource.contains("previousObservedSettings = newSettings"),
            "Turning on auto-hide while icons are already visible should compare old/new settings and schedule a hide instead of waiting for another reveal"
        )
        XCTAssertTrue(
            setupSource.contains("installMainStatusItemHoverTrackingArea(on: button)") &&
                managerSource.contains("@objc func mouseEntered(with event: NSEvent)") &&
                lifecycleSource.contains("showHiddenItemsNow(trigger: .hover)"),
            "Hovering the SaneBar status item itself should reveal hidden icons without relying only on global mouse monitors"
        )
    }

    func testAppMenuSuppressionUsesClassifiedVisibleAndHiddenLanes() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
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
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
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
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let taskURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTaskCoordinator.swift")
        let taskSource = try String(contentsOf: taskURL, encoding: .utf8)
        let queueURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveQueueWorkflow.swift")
        let queueSource = try String(contentsOf: queueURL, encoding: .utf8)
        let reorderURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarIconReorderWorkflow.swift")
        let reorderSource = try String(contentsOf: reorderURL, encoding: .utf8)
        let standardURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let standardSource = try String(contentsOf: standardURL, encoding: .utf8)
        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)

        XCTAssertTrue(
            taskSource.contains("cancelRehide()"),
            "Move pipelines should cancel any pending rehide timer before drag simulation begins"
        )
        XCTAssertTrue(
            source.contains("func queueDetachedMoveTask(") &&
                taskSource.contains("func queueDetachedMoveTask("),
            "Move/reorder flows should share one helper for move-task lifecycle instead of wiring activeMoveTask separately in each entry point"
        )
        XCTAssertTrue(
            queueSource.contains("private func waitForActiveMoveTaskIfNeeded() async"),
            "Awaitable move helpers should share one gate before queuing a new move task"
        )

        // Guard against formatting churn by validating the intent per pipeline:
        // each move/reorder entry should queue through the shared lifecycle helper,
        // and the helper must cancel rehide before drag work.
        let managerPipelinePatterns = [
            #"func\s+moveAlwaysHidden\([\s\S]*?queueDetachedMoveTask\([\s\S]*?operationName:\s*"moveIconAlwaysHidden""#,
            #"func\s+moveAlwaysHiddenToHidden\([\s\S]*?queueDetachedMoveTask\([\s\S]*?operationName:\s*"moveIconFromAlwaysHiddenToHidden""#,
        ]

        for pattern in managerPipelinePatterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(alwaysHiddenSource.startIndex ..< alwaysHiddenSource.endIndex, in: alwaysHiddenSource)
            XCTAssertGreaterThan(
                regex.numberOfMatches(in: alwaysHiddenSource, range: range),
                0,
                "Move/reorder pipeline should queue through the shared lifecycle helper"
            )
        }

        let standardPattern = #"func\s+moveIcon\([\s\S]*?queueDetachedMoveTask\([\s\S]*?operationName:\s*"moveIcon""#
        let standardRegex = try NSRegularExpression(pattern: standardPattern)
        let standardRange = NSRange(standardSource.startIndex ..< standardSource.endIndex, in: standardSource)
        XCTAssertGreaterThan(
            standardRegex.numberOfMatches(in: standardSource, range: standardRange),
            0,
            "Standard move workflow should queue through the shared lifecycle helper"
        )

        let reorderPattern = #"func\s+reorderIcon\([\s\S]*?queueDetachedMoveTask\([\s\S]*?operationName:\s*"reorderIcon""#
        let reorderRegex = try NSRegularExpression(pattern: reorderPattern)
        let reorderRange = NSRange(reorderSource.startIndex ..< reorderSource.endIndex, in: reorderSource)
        XCTAssertGreaterThan(
            reorderRegex.numberOfMatches(in: reorderSource, range: reorderRange),
            0,
            "Reorder workflow should queue through the shared lifecycle helper"
        )

        let helperPattern = #"func\s+queueDetachedMoveTask\([\s\S]*?activeMoveTask\s*=\s*Task\.detached[\s\S]*?cancelRehide\(\)"#
        let helperRegex = try NSRegularExpression(pattern: helperPattern)
        let helperRange = NSRange(taskSource.startIndex ..< taskSource.endIndex, in: taskSource)
        XCTAssertGreaterThan(
            helperRegex.numberOfMatches(in: taskSource, range: helperRange),
            0,
            "Shared move-task helper must still cancel rehide before drag simulation begins"
        )
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
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
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

}
