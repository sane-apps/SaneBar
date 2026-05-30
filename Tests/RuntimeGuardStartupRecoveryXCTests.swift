@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardStartupRecoveryXCTests: RuntimeGuardTestCase {
    func testRightClickPathAttemptsAXShowMenuBeforeHardwareFallback() throws {
        let clickURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityClickService.swift")
        let clickSource = try String(contentsOf: clickURL, encoding: .utf8)
        let dragURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarDragService.swift")
        let dragSource = try String(contentsOf: dragURL, encoding: .utf8)

        XCTAssertTrue(
            clickSource.contains("if isRightClick {"),
            "Right-click path should be explicit in performSmartPress"
        )
        XCTAssertTrue(
            clickSource.contains("performShowMenu(on: element)"),
            "Right-click path should attempt AXShowMenu before forcing hardware click"
        )
        XCTAssertTrue(
            dragSource.contains("let restorePoint: CGPoint? = isRightClick ? nil : currentCGEventMousePoint()") ||
                clickSource.contains("let restorePoint: CGPoint? = isRightClick ? nil : currentCGEventMousePoint()"),
            "Hardware fallback should restore cursor after left-click to avoid pointer jumps"
        )
    }

    func testStartupExternalMonitorPolicyRunsBeforeInitialHide() throws {
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)

        guard let startupBlockStart = coordinatorSource.range(of: "case let .startupInitial(inputs):"),
              let startupBlockEnd = coordinatorSource.range(of: "case let .positionValidation(validationContext):"),
              startupBlockStart.upperBound <= startupBlockEnd.lowerBound
        else {
            XCTFail("Startup recovery block not found")
            return
        }

        let startupBlock = String(coordinatorSource[startupBlockStart.lowerBound ..< startupBlockEnd.lowerBound])

        guard let autoRehideIndex = startupBlock.range(of: "if !inputs.autoRehideEnabled"),
              let skipIndex = startupBlock.range(of: "if inputs.shouldSkipHideForExternalMonitor"),
              let hideIndex = startupBlock.range(of: "return .performInitialHide")
        else {
            XCTFail("Startup auto-rehide, external-monitor, or initial-hide blocks not found")
            return
        }

        XCTAssertLessThan(
            autoRehideIndex.lowerBound.utf16Offset(in: startupBlock),
            hideIndex.lowerBound.utf16Offset(in: startupBlock),
            "Startup should respect auto-rehide before attempting initial hide"
        )
        XCTAssertLessThan(
            skipIndex.lowerBound.utf16Offset(in: startupBlock),
            hideIndex.lowerBound.utf16Offset(in: startupBlock),
            "Startup should apply external-monitor policy before attempting initial hide"
        )
        XCTAssertTrue(
            setupSource.contains("MenuBarOperationCoordinator.statusItemRecoveryAction(") &&
                setupSource.contains("case .performInitialHide:") &&
                setupSource.contains("await manager.hidingService.hide()"),
            "MenuBarManager should route startup hide policy through the runtime coordinator before performing the initial hide"
        )
        XCTAssertTrue(
            setupSource.contains("Skipping initial hide: auto-rehide disabled"),
            "Startup should log when the launch hide is skipped because auto-rehide is off"
        )
    }

    func testStartupPositionValidationRetriesBeforeAutosaveRecovery() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let recoveryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift")
        let recoverySource = try String(contentsOf: recoveryURL, encoding: .utf8)
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)
        let controllerSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Controllers/StatusBarController.swift"),
            encoding: .utf8
        )
        let positionStoreSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/StatusBarPositionStore.swift"),
            encoding: .utf8
        )
        let positionDefaultsSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/StatusBarPositionDefaultsStore.swift"),
            encoding: .utf8
        )
        let positionRecoverySource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/StatusBarPositionRecoveryStore.swift"),
            encoding: .utf8
        )
        let screenResolverSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/StatusItemScreenResolver.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            recoverySource.contains("statusItemValidationMaxAttempts(context: context)") &&
                recoverySource.contains("statusItemValidationRetryDelaySeconds(context: context)") &&
                recoverySource.contains("case .startupFollowUp, .screenParametersChanged, .wakeResume:\n            return 6") &&
                recoverySource.contains("case .startupFollowUp, .screenParametersChanged, .wakeResume:\n            return 0.5"),
            "Startup position validation should retry before escalating to autosave recovery"
        )
        XCTAssertTrue(
            recoverySource.contains("Status item remained off-menu-bar after"),
            "Autosave recovery should only run after repeated validation failures"
        )
        XCTAssertTrue(
            recoverySource.contains("Status item position validation recovered after"),
            "Startup validation should log successful transient recovery without bumping autosave version"
        )
        XCTAssertTrue(
            recoverySource.contains("geometry drift detected"),
            "Runtime validation should log attached-but-drifted status items so leftward shoves are distinguishable from missing windows"
        )
        XCTAssertTrue(
            coordinatorSource.contains("validationContext == .screenParametersChanged") &&
                coordinatorSource.contains("validationContext == .wakeResume") &&
                coordinatorSource.contains("return .bumpAutosaveVersion(recoveryReason)"),
            "Wake and screen-change invalid geometry should escalate through bounded autosave recovery after repair fails"
        )
        XCTAssertTrue(
            recoverySource.contains("stableSnapshotNeedsAlwaysHiddenRepair(") &&
                recoverySource.contains("alwaysHiddenPinWorkflow.repairSeparatorPositionIfNeeded(reason: \"position-validation-\\(context.rawValue)\")"),
            "Position validation should repair a misordered always-hidden separator before it blesses the layout as stable"
        )
        XCTAssertTrue(
            recoverySource.contains("captureCurrentDisplayBackupAfterStableValidation(") &&
                recoverySource.contains("hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(\n                referenceScreen: manager.currentRecoveryReferenceScreen()"),
            "Stable validation should wait briefly for a safe current-width backup instead of assuming one exists immediately"
        )
        XCTAssertTrue(
            recoverySource.contains("StatusBarController.captureCurrentDisplayPositionBackupIfPossible(\n                referenceScreen: manager.currentRecoveryReferenceScreen()\n            )") &&
                !recoverySource.contains("mainPosition: snapshot.mainX.map(Double.init)") &&
                !recoverySource.contains("separatorPosition: snapshot.separatorX.map(Double.init)"),
            "Stable backup capture should use persisted NSStatusItem preferred positions, not raw runtime screen coordinates"
        )
        XCTAssertTrue(
            positionDefaultsSource.contains("UserDefaults.standard.set(value, forKey: appKey)\n        UserDefaults.standard.synchronize()") &&
                positionDefaultsSource.contains("UserDefaults.standard.removeObject(forKey: appKey)\n        UserDefaults.standard.synchronize()"),
            "Recovered NSStatusItem preferred positions must be flushed to the app defaults domain before startup probes or restarts depend on them"
        )
        XCTAssertTrue(
            coordinatorSource.contains("case waitForLiveAnchor") &&
                coordinatorSource.contains("shouldWaitForLiveSeparatorAnchor(") &&
                recoverySource.contains("Status item validation is still waiting for a live anchor"),
            "Wake/display validation should defer recovery while the separator is only estimated from the main icon"
        )
        XCTAssertTrue(
            recoverySource.contains("MenuBarOperationCoordinator.alwaysHiddenMisorderRecoveryAction(") &&
                recoverySource.contains("trigger: \"always-hidden-position-validation-\\(context.rawValue)\""),
            "Persistent always-hidden separator drift should escalate through the shared bounded recovery policy instead of repeating same-version repairs forever"
        )
        XCTAssertTrue(
            recoverySource.contains("case let .repairPersistedLayoutAndRecreate(reason):") &&
                recoverySource.contains("shouldResetPersistentStateForStatusItemRecovery(") &&
                recoverySource.contains("reason: reason,") &&
                recoverySource.contains("isStartupRecovery: trigger.hasPrefix(\"startup-\")") &&
                recoverySource.contains("validationContext: validationContext") &&
                recoverySource.contains("StatusBarController.resetPersistentStatusItemState(") &&
                recoverySource.contains("freshAutosaveNamespace: true") &&
                recoverySource.contains("StatusBarController.recoverStartupPositions(") &&
                recoverySource.contains("recreateStatusItemsFromPersistedLayout(reason: trigger)"),
            "Status-item recovery should hard-reset poisoned startup geometry into a fresh autosave namespace while keeping non-startup geometry recovery on the lighter path"
        )
        XCTAssertTrue(
            screenResolverSource.contains("lastKnownStatusItemDisplayID") &&
                screenResolverSource.contains("private static func displayID(_ screen: NSScreen?)") &&
                screenResolverSource.contains("let cachedScreen = NSScreen.screens.first(where: { Self.displayID($0) == lastKnownStatusItemDisplayID })"),
            "Status-item recovery should preserve the last live display identity so stale windows do not reseed against the wrong monitor"
        )
        XCTAssertTrue(
            source.contains("let resolvedScreen = statusItemScreen") &&
                source.contains("statusItemScreenResolver.isExternalScreen(resolvedScreen)"),
            "External-monitor policy should use the same status-item screen source as startup recovery"
        )
        XCTAssertTrue(
            positionStoreSource.contains("resolvedReferenceScreen(_ referenceScreen: NSScreen? = nil)") &&
                positionStoreSource.contains("if let pointerScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })") &&
                positionStoreSource.contains("return NSScreen.main ?? NSScreen.screens.first"),
            "StatusBarController should share one pointer-aware fallback screen resolver instead of scattering raw NSScreen.main fallbacks"
        )
        XCTAssertTrue(
            positionRecoverySource.contains("StatusBarPositionStore.resolvedReferenceScreen(referenceScreen)") &&
                controllerSource.contains("let screenFrame = window?.screen?.frame ?? StatusBarPositionStore.resolvedReferenceScreen()?.frame"),
            "Startup validation and backup recovery should route through the shared reference-screen resolver"
        )
    }

    func testBlockingSeparatorEstimateDoesNotBecomeTrustedCache() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarGeometryResolver.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        guard let blockingStart = source.range(of: "if separatorItem.length > 1000 {"),
              let blockingEnd = source.range(
                  of: "guard let separatorButton = separatorItem.button",
                  range: blockingStart.upperBound ..< source.endIndex
              )
        else {
            XCTFail("Blocking-mode separator path not found")
            return
        }

        let blockingPath = String(source[blockingStart.lowerBound ..< blockingEnd.lowerBound])
        XCTAssertTrue(
            blockingPath.contains("estimatedSeparatorEdgesFromMainIcon()"),
            "Blocking mode should still estimate a temporary separator edge when no cache exists"
        )
        XCTAssertFalse(
            blockingPath.contains("cache.lastKnownSeparatorX = estimated.originX"),
            "Main-icon-derived separator estimates must not become trusted separator origin cache"
        )
        XCTAssertFalse(
            blockingPath.contains("cache.lastKnownSeparatorRightEdgeX = estimated.rightEdgeX"),
            "Main-icon-derived separator estimates must not become trusted separator right-edge cache"
        )
    }

    func testStartupRecoveryRecreatesLiveItemsImmediately() throws {
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)

        XCTAssertTrue(
            setupSource.contains("case let .repairPersistedLayoutAndRecreate(reason):") &&
                setupSource.contains("manager.executeStatusItemRecoveryAction(") &&
                setupSource.contains("trigger: \"startup-\\(reason?.rawValue ?? \"recovery\")\"") &&
                setupSource.contains("validationContext: nil") &&
                setupSource.contains("await manager.hidingService.show()") &&
                setupSource.contains("manager.scheduleInitialPositionValidationAfterStartup()") &&
                coordinatorSource.contains("case missingCoordinates = \"missing-coordinates\"") &&
                coordinatorSource.contains("case invalidGeometry = \"invalid-geometry\""),
            "Startup recovery should recreate immediately, then arm follow-up validation only after the recovery show path has settled"
        )
    }

    func testInitialPositionValidationWaitsForStartupHideOrRecovery() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func scheduleInitialPositionValidationAfterStartup()") &&
                source.contains("Avoid racing the first geometry check against the startup"),
            "MenuBarManager should have an explicit helper for post-startup validation so launch recovery and initial hide do not race the first geometry check"
        )
        XCTAssertFalse(
            source.contains("setupStatusItem()\n            schedulePositionValidation()"),
            "Deferred UI setup should not arm position validation in parallel with setupStatusItem anymore"
        )
        XCTAssertTrue(
            setupSource.contains("manager.scheduleInitialPositionValidationAfterStartup()"),
            "Startup setup should arm the first position validation only after startup hide/skip/recovery has settled"
        )
    }

    func testLaunchLoadsLicenseBeforeCreatingLicenseGatedStatusItems() throws {
        let appURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let managerURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let managerSource = try String(contentsOf: managerURL, encoding: .utf8)
        let recoveryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift")
        let recoverySource = try String(contentsOf: recoveryURL, encoding: .utf8)
        let smokeSource = try scriptSource(entrypoint: "live_zone_smoke.rb", partialPrefix: "live_zone_smoke")

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
            managerSource.contains("func currentEffectiveAlwaysHiddenSectionEnabled() -> Bool"),
            "MenuBarManager should centralize the effective always-hidden gate instead of mixing raw settings and license state"
        )
        XCTAssertTrue(
            managerSource.contains("statusBarController.ensureAlwaysHiddenSeparator(enabled: currentEffectiveAlwaysHiddenSectionEnabled())"),
            "Initial status-item wiring should gate the always-hidden separator on effective Pro state"
        )
        XCTAssertTrue(
            recoverySource.contains("alwaysHiddenEnabled: manager.currentEffectiveAlwaysHiddenSectionEnabled()"),
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
        let observerURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarObserverWorkflow.swift")
        let observerSource = try String(contentsOf: observerURL, encoding: .utf8)
        let recoveryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift")
        let recoverySource = try String(contentsOf: recoveryURL, encoding: .utf8)

        XCTAssertTrue(
            observerSource.contains("manager.clearCachedSeparatorGeometryForLifecycleTransition(reason: \"screenParametersChanged\")") &&
                source.contains("Preserving cached separator geometry during") &&
                observerSource.contains("manager.schedulePositionValidation(context: .screenParametersChanged)") &&
                observerSource.contains("NSWorkspace.willSleepNotification") &&
                observerSource.contains("NSWorkspace.screensDidSleepNotification") &&
                observerSource.contains("NSWorkspace.didWakeNotification") &&
                observerSource.contains("NSWorkspace.screensDidWakeNotification") &&
                observerSource.contains("NSWorkspace.sessionDidBecomeActiveNotification") &&
                observerSource.contains("manager.schedulePositionValidation(context: .wakeResume)") &&
                observerSource.contains("manager.schedulePostRecoveryAutoRehideIfNeeded(reason: \"wakeResume\")") &&
                observerSource.contains("Replay pinned visibility intent only after validation reports healthy anchors.") &&
                observerSource.contains("Wake can briefly report stale menu-bar coordinates; validation owns replay once stable.") &&
                !observerSource.contains("manager.schedulePostRecoveryVisibilityIntentReplay(reason: \"wakeResume\")") &&
                !observerSource.contains("manager.schedulePostRecoveryVisibilityIntentReplay(reason: \"screenParametersChanged\")") &&
                recoverySource.contains("schedulePostRecoveryVisibilityIntentReplay(reason: \"healthy-validation-\\(context.rawValue)\")") &&
                !source.contains("settings.layoutMode == .live") &&
                recoverySource.contains("positionValidationGeneration += 1") &&
                recoverySource.contains("guard self.manager.positionValidationGeneration == validationGeneration else"),
            "Screen and wake topology changes should invalidate stale validation work while preserving trustworthy hidden-state anchors, rearm auto-rehide after wake movement, then replay visibility intent only after wake-aware validation confirms healthy anchors"
        )

        let wakeProbeURL = projectRootURL().appendingPathComponent("Scripts/wake_layout_probe.rb")
        let wakeProbeSource = try String(contentsOf: wakeProbeURL, encoding: .utf8)
        XCTAssertTrue(
                wakeProbeSource.contains("SNAPSHOT_SETTLE_TIMEOUT_SECONDS") &&
                wakeProbeSource.contains("HIDDEN_BASELINE_TIMEOUT_SECONDS") &&
                wakeProbeSource.contains("expected_state: 'hidden'") &&
                wakeProbeSource.contains("expected_state: 'expanded'") &&
                wakeProbeSource.contains("wait_for_snapshot(") &&
                wakeProbeSource.contains("!truthy?(candidate['possibleSystemMenuBarSuppression'])") &&
                wakeProbeSource.contains("scan_power_wake_events_since(started_at)") &&
                wakeProbeSource.contains("wait_for_icon_zone_persistence!") &&
                wakeProbeSource.contains("SNAPSHOT_SETTLE_POLL_SECONDS") &&
                wakeProbeSource.contains("Wake probe will turn the Mini display off"),
            "Wake runtime proof should wait through bounded post-wake layout and icon-zone recovery until the expected customer-visible state is healthy instead of sampling one transient frame"
        )
    }

    func testStatusItemRecoverySkipsStaleOrOverlappingStructuralActions() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let recoveryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift")
        let recoverySource = try String(contentsOf: recoveryURL, encoding: .utf8)
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("var isExecutingStatusItemRecovery = false") &&
                source.contains("var pendingRecoveryHideRestore = false") &&
                recoverySource.contains("validationGeneration: Int? = nil") &&
                recoverySource.contains("currentPositionValidationGeneration != validationGeneration") &&
                recoverySource.contains("Skipping stale status item recovery action") &&
                recoverySource.contains("Skipping overlapping status item recovery action") &&
                recoverySource.contains("positionValidationGeneration += 1") &&
                setupSource.contains("let preservedHidingState: HidingState = shouldRestoreHidden ? .hidden : manager.hidingService.state") &&
                setupSource.contains("deferApplyingState: shouldRestoreHidden") &&
                source.contains("self.hidingService.applyCurrentStateToLiveItems()") &&
                setupSource.contains("Preserved hidden state during status item recovery"),
            "Structural status-item recovery should reject stale validation escalations, defer hidden-state collapse until geometry warmup, and avoid leaving the bar permanently expanded after a wake/display repair"
        )
    }

    func testInlineAppMenuSuppressionDoesNotForceDockIconVisible() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityWorkflow.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let policyURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityPolicy.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func suppressApplicationMenusIfNeeded()") &&
                policySource.contains("nonisolated static func shouldSuppressApplicationMenus") &&
                policySource.contains("for revealTrigger: MenuBarRevealTrigger"),
            "Inline reveal path should still have an explicit app-menu suppression handler and a trigger-aware policy gate"
        )
        XCTAssertFalse(
            source.contains("private func suppressApplicationMenusIfNeeded() {\n        guard !manager.isAppMenuSuppressed else { return }\n        guard !manager.settings.showDockIcon else { return }\n\n        manager.appToReactivateAfterSuppression = NSWorkspace.shared.frontmostApplication\n        NSApp.setActivationPolicy(.regular)"),
            "Inline app-menu suppression must not force regular activation when the user has hidden the Dock icon"
        )
        XCTAssertTrue(
            source.contains("revealTrigger: manager.lastMenuBarRevealTrigger") &&
                policySource.contains("shouldSuppressApplicationMenus(for: revealTrigger)") &&
                source.contains("MenuBarVisibilityPolicy.shouldSuppressApplicationMenus(for: manager.lastMenuBarRevealTrigger)") &&
                source.contains("restoreApplicationMenusIfNeeded(reason: \"passiveReveal\")"),
            "Passive hover/system reveals must not reuse the inline overlap suppression path that activates SaneBar and restores focus later"
        )
        XCTAssertTrue(
            source.contains("manager.appToReactivateAfterSuppression = NSWorkspace.shared.frontmostApplication") &&
                source.contains("NSApp.activate(ignoringOtherApps: true)") &&
                source.contains("scheduleAppMenuDockPolicyReassertionIfNeeded()"),
            "Inline app-menu suppression should still activate SaneBar while reasserting accessory policy during the suppression window"
        )
        XCTAssertTrue(
            source.contains("manager.appMenuDockPolicyTask?.cancel()") &&
                source.contains("manager.appMenuDockPolicyTask = Task"),
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
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)

        XCTAssertTrue(
            setupSource.contains("Accessibility permission not granted at startup - continuing initial hide"),
            "Startup should still hide at launch even when Accessibility trust is temporarily unavailable"
        )
        XCTAssertFalse(
            source.contains("startupDeferredPermissionGrant"),
            "Launch-time permission callbacks should not trigger pin drag automation"
        )
        XCTAssertFalse(
            setupSource.contains("await manager.alwaysHiddenPinWorkflow.enforce(reason: \"startup\")"),
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
        let chromeURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelChromeViews.swift")
        let chromeSource = try String(contentsOf: chromeURL, encoding: .utf8)

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
            chromeSource.contains("Button(\"Try Again\", action: retry)"),
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
        let lifecycleURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelLifecycleModifier.swift")
        let lifecycleSource = try String(contentsOf: lifecycleURL, encoding: .utf8)

        XCTAssertTrue(
            lifecycleSource.contains("schedulePostMoveFollowupRefresh()"),
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
            lifecycleSource.contains("SearchWindowController.iconMoveDidFinishNotification"),
            "Search view should refresh once more when move-in-progress fully clears"
        )
    }

    func testBrowseModeSwitchTransitionsVisiblePanelToNewMode() throws {
        let source = try generalSettingsSource()

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

    func testQuickSearchPrefillSurvivesInitialPanelCreation() throws {
        let controllerSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/SearchWindow/SearchWindowController.swift"),
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            controllerSource.contains("createWindow(mode: desiredMode, prefill: searchText)") &&
                controllerSource.contains("createFindIconWindow(prefill: searchText)"),
            "Quick Search should pass its prefill into newly-created Browse Icons windows instead of only posting an early notification"
        )
        XCTAssertTrue(
            viewSource.contains("initialSearchText: String? = nil") &&
                viewSource.contains("_searchText = State(initialValue: initialSearchText)") &&
                viewSource.contains("_searchTextDebounced = State(initialValue: initialSearchText)"),
            "Browse Icons should seed search state from Quick Search before notification subscribers exist"
        )
    }

    func testSearchURLRevealsHiddenItemsBeforeOpeningPanel() throws {
        let appSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("SaneBarApp.swift"),
            encoding: .utf8
        )
        guard let searchCase = appSource.range(of: "case \"search\":"),
              let settingsCase = appSource.range(of: "case \"settings\":")
        else {
            XCTFail("Expected URL handler search and settings cases")
            return
        }

        let searchBlock = String(appSource[searchCase.lowerBound ..< settingsCase.lowerBound])
        XCTAssertTrue(
            searchBlock.contains("await MenuBarManager.shared.visibilityWorkflow.showHiddenItemsNow(trigger: .search)") &&
                searchBlock.range(of: "showHiddenItemsNow")!.lowerBound < searchBlock.range(of: "SearchWindowController.shared.show")!.lowerBound,
            "sanebar://search?q=... should reveal hidden items before opening Browse Icons so URL quick search can find hidden icons"
        )
    }

    func testDockMenuUsesSharedUtilityActions() throws {
        let appSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("SaneBarApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            appSource.contains("SaneStandardMenu.addCoreUtilityItems") &&
                appSource.contains("openSettingsFromDock") &&
                appSource.contains("openLicenseFromDock") &&
                appSource.contains("openAboutFromDock"),
            "SaneBar Dock right-click menu should expose shared Settings, License, and About / Report actions"
        )
    }

    func testControlSettingsExposeInlineRevealAppMenuToggle() throws {
        let source = try generalSettingsSource()

        XCTAssertTrue(
            source.contains("Hide app menus during inline reveal"),
            "Control settings should expose the inline reveal app-menu toggle label"
        )
        XCTAssertTrue(
            source.contains("Only affects inline reveal."),
            "Control settings should explain that the toggle only applies to inline reveal"
        )
        XCTAssertTrue(
            source.contains("$menuBarManager.settings.hideApplicationMenusOnInlineReveal"),
            "Control settings should bind the toggle to the persisted inline reveal app-menu setting"
        )
    }

    func testAdvancedWorkflowOnboardingPageUsesCompactLayoutWithinFixedWindow() throws {
        let source = try welcomeOnboardingSource()

        XCTAssertTrue(
            source.contains(".frame(width: 700, height: 520)"),
            "Onboarding still uses a fixed-size window, so the Advanced Workflow page must stay compact enough to fit it"
        )
        XCTAssertTrue(
            source.contains("HStack(alignment: .top, spacing: 16)") &&
                source.contains("browseStyleCard") &&
                source.contains("zoneSummaryCard"),
            "Advanced Workflow should use a compact two-column layout instead of stacking the screenshot and zone guide vertically"
        )
        XCTAssertTrue(
            source.contains("workflowTipsCard") &&
                source.contains("frame(maxWidth: .infinity, maxHeight: 142"),
            "Advanced Workflow should keep a compact footer and constrain the settings screenshot height so the bottom navigation stays visible"
        )
        XCTAssertFalse(
            source.contains("• Icon Panel: browse and click icons. Pro lets you drag an icon onto the Visible, Hidden, or Always Hidden tab."),
            "Advanced Workflow should not regress to the old long bullet stack that overflowed the onboarding window"
        )
        XCTAssertFalse(
            source.contains("• Second Menu Bar: browse and click icons in the Hidden and Visible rows. Pro lets you move icons between the Visible, Hidden, and Always Hidden rows."),
            "Advanced Workflow should not reintroduce the oversized second-menu-bar paragraph that pushed the bottom buttons off-screen"
        )
    }

}
