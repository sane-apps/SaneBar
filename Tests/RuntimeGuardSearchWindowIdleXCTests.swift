@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardSearchWindowIdleXCTests: RuntimeGuardTestCase {
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
        let secondMenuBarSource = try secondMenuBarSource()
        let navigationURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView+Navigation.swift")
        let navigationSource = try String(contentsOf: navigationURL, encoding: .utf8)
        let smokeSource = try scriptSource(entrypoint: "live_zone_smoke.rb", partialPrefix: "live_zone_smoke")

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
            navigationSource.contains("await service.activate(app: app, isRightClick: isRightClick, origin: .browsePanel)"),
            "Second Menu Bar activation should still route through SearchService for browse-panel clicks"
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
            controllerSource.contains("shouldDeferCloseForBrowseActivation()") &&
                controllerSource.contains("close deferred during recent second menu bar activation"),
            "Spurious close/cancel events during second-menu-bar activation should share the post-activation grace instead of collapsing the panel"
        )
        XCTAssertTrue(
            controllerSource.contains("close(ignoringBrowseActivationGrace: true)") &&
                controllerSource.contains("self?.close(ignoringBrowseActivationGrace: true)"),
            "Explicit toggle and panel dismiss actions should bypass the activation grace so the user can intentionally close the panel"
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
        let appleScriptCommandsURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptCommands.swift")
        let appleScriptCommandsSource = try String(contentsOf: appleScriptCommandsURL, encoding: .utf8)
        let searchServiceURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchServiceSource = try String(contentsOf: searchServiceURL, encoding: .utf8)
        let navigationURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView+Navigation.swift")
        let navigationSource = try String(contentsOf: navigationURL, encoding: .utf8)

        XCTAssertTrue(
            searchServiceSource.contains("let tracksBrowseActivation = origin == .browsePanel") &&
                searchServiceSource.contains("browseController.noteBrowseActivationStarted()") &&
                searchServiceSource.contains("browseController.noteBrowseActivationFinished()"),
            "SearchService should own browse-panel activation grace bookkeeping so all callers get the same idle-close protection"
        )
        XCTAssertTrue(
            appleScriptCommandsSource.contains("SearchWindowController.shared.close(ignoringBrowseActivationGrace: true)"),
            "The scripted close command should still force cleanup so QA and automation can intentionally dismiss the panel"
        )
        XCTAssertTrue(
            !source.contains("noteBrowseActivationStarted()") &&
                !source.contains("noteBrowseActivationFinished()") &&
                !navigationSource.contains("noteBrowseActivationStarted()") &&
                !navigationSource.contains("noteBrowseActivationFinished()"),
            "UI and AppleScript callers should delegate browse activation lifecycle ownership to SearchService instead of bracketing it themselves"
        )
    }

    func testPostRevealClickPathAvoidsImmediateSpatialFallback() throws {
        let searchServiceURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchServiceURL, encoding: .utf8)
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchServiceSupport.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)
        let interactionURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityClickService.swift")
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
        let lifecycleURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelLifecycleModifier.swift")
        let lifecycleSource = try String(contentsOf: lifecycleURL, encoding: .utf8)
        let controllerURL = projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift")
        let controllerSource = try String(contentsOf: controllerURL, encoding: .utf8)

        XCTAssertTrue(
            lifecycleSource.contains("refreshApps(isSecondMenuBar)"),
            "Second menu bar show/reopen should force a fresh AX scan instead of trusting cached app lists"
        )
        XCTAssertTrue(
            searchViewSource.contains("AccessibilityService.shared.invalidateMenuBarItemPositionsCache()") &&
                searchViewSource.contains("await service.refreshKnownClassifiedApps()"),
            "Zone-only browse refreshes should invalidate positions and rebuild from known owners instead of paying for a full inventory scan on every relayout"
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

    func testMenuBarAXScansAreBoundedAndCancellationAware() throws {
        let menuExtraURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuExtraService.swift")
        let menuExtraSource = try String(contentsOf: menuExtraURL, encoding: .utf8)
        let boundedChildrenURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityBoundedAXChildFetch.swift")
        let boundedChildrenSource = try String(contentsOf: boundedChildrenURL, encoding: .utf8)
        let scannerURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarScanningService.swift")
        let scannerSource = try String(contentsOf: scannerURL, encoding: .utf8)
        let windowFallbackURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarWindowFallbackPolicy.swift")
        let windowFallbackSource = try String(contentsOf: windowFallbackURL, encoding: .utf8)
        let systemWideURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilitySystemWideMenuBarScanner.swift")
        let systemWideSource = try String(contentsOf: systemWideURL, encoding: .utf8)
        let clickURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityClickService.swift")
        let clickSource = try String(contentsOf: clickURL, encoding: .utf8)
        let visibilityURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
        let visibilitySource = try String(contentsOf: visibilityURL, encoding: .utf8)
        let menuBarChildSources = [
            menuExtraSource,
            scannerSource,
            windowFallbackSource,
            clickSource,
            visibilitySource
        ]
        let unboundedChildFetches = menuBarChildSources.flatMap { source in
            source.split(separator: "\n").filter { line in
                line.contains("AXUIElementCopyAttributeValue") &&
                    line.contains("kAXChildrenAttribute")
            }
        }

        XCTAssertTrue(
                menuExtraSource.contains("maxMenuExtraTraversalDepth") &&
                menuExtraSource.contains("maxMenuExtraTraversalNodes") &&
                menuExtraSource.contains("maxCollectedMenuExtraItems") &&
                menuExtraSource.contains("var visited = Set<CFHashCode>()") &&
                menuExtraSource.contains("CollectedMenuBarItems") &&
                menuExtraSource.contains("collectedRoots.contains(where: \\.truncated)") &&
                menuExtraSource.contains("refusing partial AXExtrasMenuBar child list") &&
                boundedChildrenSource.contains("AXUIElementGetAttributeValueCount") &&
                boundedChildrenSource.contains("AXUIElementCopyAttributeValues") &&
                !boundedChildrenSource.contains("AXUIElementCopyAttributeValue(") &&
                menuExtraSource.contains("AccessibilityBoundedAXChildFetch.children") &&
                menuExtraSource.contains("Task.isCancelled"),
            "Third-party AX menu-extra traversal should be depth/node/item bounded, cycle-safe, range-fetch children without unbounded fallback, and cancellation-aware"
        )
        XCTAssertTrue(
                scannerSource.contains("guard !Task.isCancelled else { return [] }") &&
                scannerSource.contains("group.cancelAll()") &&
                scannerSource.contains("accessibilityService.menuBarItemCache = apps") &&
                scannerSource.contains("AccessibilityBoundedAXChildFetch.children") &&
                scannerSource.contains("childResult.truncated") &&
                !scannerSource.contains("AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute"),
            "Known-owner scans should observe cancellation, use bounded child range fetches, fail closed on incomplete child lists, and avoid writing shared cache state after cancellation"
        )
        XCTAssertTrue(
            windowFallbackSource.contains("guard !Task.isCancelled else { return [] }") &&
                windowFallbackSource.contains("AccessibilityBoundedAXChildFetch.children") &&
                windowFallbackSource.contains("guard !childResult.truncated else { return nil }") &&
                !windowFallbackSource.contains("AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute") &&
                systemWideSource.contains("guard !Task.isCancelled else { return [] }"),
            "WindowServer and system-wide fallback scanners should use bounded child fetches and cooperate with cancellation so canceled browse refreshes cannot keep sampling"
        )
        XCTAssertTrue(
            unboundedChildFetches.isEmpty,
            "Menu-bar AX services must use AccessibilityBoundedAXChildFetch instead of unbounded AXChildren fetches: \(unboundedChildFetches)"
        )
        XCTAssertTrue(
            clickSource.contains("AccessibilityBoundedAXChildFetch.children") &&
                clickSource.contains("AXExtrasMenuBar children truncated") &&
                visibilitySource.contains("AccessibilityBoundedAXChildFetch.children") &&
                visibilitySource.contains("guard !childResult.truncated else"),
            "Click and visibility helpers share the bounded AX child fetcher and fail closed on incomplete child lists"
        )
    }

    func testLegacyUpgradePathDoesNotAutoGrantProFromSettingsState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarLifecycleWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("Legacy upgrade detected - showing freemium intro (manual grant only)"),
            "Legacy upgrade path should be explicit/manual for Pro grants"
        )
        XCTAssertFalse(
            source.contains("grantEarlyAdopterPro()"),
            "MenuBarManager should not auto-grant Pro based only on local settings flags"
        )
    }

    func testGeneralSettingsNoLongerCarryInlineLicenseChrome() throws {
        let source = try generalSettingsSource()

        XCTAssertFalse(
            source.contains("CompactSection(\"License\")"),
            "General settings should defer license management to the shared dedicated License tab"
        )
        XCTAssertFalse(
            source.contains("showingLicenseEntry"),
            "General settings should not keep a private license-entry sheet once the shared License tab owns that flow"
        )
    }

    func testActivationDiagnosticsKeepPostClickVerification() throws {
        let clickURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityClickService.swift")
        let clickSource = try String(contentsOf: clickURL, encoding: .utf8)
        let policyURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)
        let menuExtrasURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuExtraService.swift")
        let menuExtrasSource = try String(contentsOf: menuExtrasURL, encoding: .utf8)
        let combinedSource = clickSource + "\n" + policySource + "\n" + menuExtrasSource
        let diagnosticsSource = try diagnosticsSource()
        XCTAssertTrue(
            combinedSource.contains("kAXShownMenuUIElementAttribute"),
            "Click verification should check AXShownMenuUIElement so hardware-click success means more than event dispatch"
        )
        XCTAssertTrue(
            combinedSource.contains("observableReactionDescription"),
            "Click verification should compare before/after AX reaction snapshots"
        )
        XCTAssertTrue(
            clickSource.contains("includeWindowServerWindowCount: false"),
            "Click verification should poll cheap AX reaction signals in the loop instead of rescanning WindowServer every pass"
        )
        XCTAssertTrue(
            clickSource.contains("if baseline.windowServerWindowCount != nil"),
            "Click verification should reserve WindowServer counting for a narrow fallback pass instead of the hot polling path"
        )
        XCTAssertTrue(
            policySource.contains("if success, isRightClick"),
            "Hardware-first right-click activation should not pay for an AX fallback after a dispatched click"
        )

        let searchURL = projectRootURL().appendingPathComponent("Core/Services/SearchService.swift")
        let searchSource = try String(contentsOf: searchURL, encoding: .utf8)
        let searchClickURL = projectRootURL().appendingPathComponent("Core/Services/SearchClickAttemptService.swift")
        let searchClickSource = try String(contentsOf: searchClickURL, encoding: .utf8)
        XCTAssertTrue(
            searchClickSource.contains("clickMenuBarItemResult("),
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
            diagnosticsSource.contains("if origin == .browsePanel {") &&
                diagnosticsSource.contains("return true"),
            "Browse activation should prefer hardware-first for precise and coarse panel rows"
        )
        XCTAssertTrue(
            searchSource.contains("Rejecting unverified click success for revealed/browse-session activation"),
            "Unverified hardware click dispatch must not be treated as success for second-menu-bar/revealed flows"
        )
    }
}
