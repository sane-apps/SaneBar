@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardRepoGeometryXCTests: RuntimeGuardTestCase {
    func testPublicRepoHygieneGuardsLocalAgentState() throws {
        let gitignoreURL = projectRootURL().appendingPathComponent(".gitignore")
        let gitignore = try String(contentsOf: gitignoreURL, encoding: .utf8)

        XCTAssertTrue(gitignore.contains(".build-logs"), "Local build-log symlinks should never be tracked")
        XCTAssertTrue(gitignore.contains(".claude/"), "Private Claude agent state should stay local")
        XCTAssertTrue(gitignore.contains(".agent/"), "Private agent workflow state should stay local")
        XCTAssertTrue(gitignore.contains(".gemini"), "Gemini mirrors should stay local unless intentionally sanitized")
        XCTAssertTrue(gitignore.contains("SESSION_HANDOFF.md"), "Session handoff state should not be published")
    }

    func testPublicCIWorkflowExistsForBuildAndTestVisibility() throws {
        let workflowURL = projectRootURL().appendingPathComponent(".github/workflows/ci.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("name: CI"), "Public CI should be visible in GitHub Actions")
        XCTAssertTrue(workflow.contains("SANEAPPS_GITHUB_HOSTED_EXCEPTION"), "Automatic public CI should document the SaneApps workflow exception")
        XCTAssertTrue(workflow.contains("xcodegen generate"), "CI should regenerate the project from project.yml")
        XCTAssertTrue(workflow.contains("xcodebuild test"), "CI should run the app test scheme")
        XCTAssertTrue(workflow.contains("CODE_SIGNING_ALLOWED=NO"), "CI should not require private signing credentials")
    }

    func testFileBackedAppInfoPlistDoesNotInheritGeneratedPlistSetting() throws {
        let projectURL = projectRootURL().appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        XCTAssertTrue(
            project.contains("info:\n      path: SaneBar/Info.plist"),
            "The app target should keep its checked-in Info.plist as the source of truth"
        )
        XCTAssertTrue(
            project.contains("GENERATE_INFOPLIST_FILE: NO"),
            "The app target must not inherit generated Info.plist mode; Xcode can otherwise build an app bundle missing Contents/Info.plist"
        )
    }

    func testSaneUIPackageIsPinnedForReproducibleBuilds() throws {
        let projectURL = projectRootURL().appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let resolvedURL = projectRootURL()
            .appendingPathComponent("SaneBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let resolved = try String(contentsOf: resolvedURL, encoding: .utf8)

        XCTAssertTrue(project.contains("SaneUI:"), "SaneUI should remain an explicit dependency")
        XCTAssertTrue(
            project.contains("revision: 83d825911a53aaa6560fd342969b12d02a364de3"),
            "SaneUI should pin the shared settings chrome revision for release reproducibility"
        )
        XCTAssertFalse(
            project.contains("SaneUI:\n    url: https://github.com/sane-apps/SaneUI.git\n    branch: main"),
            "SaneUI should not track a moving branch in release configuration"
        )
        XCTAssertTrue(
            resolved.contains("\"revision\" : \"83d825911a53aaa6560fd342969b12d02a364de3\""),
            "Package.resolved should resolve SaneUI to the release-tested revision"
        )
        XCTAssertFalse(
            resolved.contains("\"branch\" : \"main\""),
            "Package.resolved should not preserve SaneUI as a moving branch pin"
        )
    }

    func testLocalOnboardingCrossSellStaysDirectAndFocused() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/Onboarding/WelcomePlanPage.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("!licenseService.usesAppStorePurchase && !licenseService.usesSetappDistribution"),
            "SaneBar onboarding companion apps should stay direct-download only"
        )
        XCTAssertTrue(source.contains("https://saneclip.com?ref=sanebar-app"))
        XCTAssertTrue(source.contains("https://saneclick.com?ref=sanebar-app"))
        XCTAssertTrue(source.contains("https://sanehosts.com?ref=sanebar-app"))
        XCTAssertTrue(source.contains("More helpful SaneApps"))
        XCTAssertTrue(source.contains("SaneClipCompanionIcon"))
        XCTAssertTrue(source.contains("SaneClickCompanionIcon"))
        XCTAssertTrue(source.contains("SaneHostsCompanionIcon"))
        XCTAssertTrue(source.contains("CompanionAppCard"))
        XCTAssertTrue(source.contains("outboundActionInFlight"))
        XCTAssertTrue(source.contains("runSingleOutboundAction"))
        XCTAssertTrue(source.contains(".disabled(licenseService.isPurchasing || outboundActionInFlight)"))
        XCTAssertTrue(source.contains(".buttonStyle(OnboardingSecondaryButtonStyle())"))
        XCTAssertFalse(source.contains("Also useful"))
        XCTAssertFalse(source.contains(".font(.system(size: 11))"))
        XCTAssertFalse(source.contains("SaneSales"))
        XCTAssertFalse(source.contains("SaneVideo"))
        XCTAssertFalse(source.contains("Works well with"))
        XCTAssertFalse(source.contains(".buttonStyle(.bordered)"))
    }

    func testLocalOnboardingPrimaryButtonsUseSharedGlassGradient() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/Onboarding/WelcomeOnboardingStyle.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SaneGlassRoundedBackground("))
        XCTAssertTrue(source.contains("tint: SanePanelChrome.accentTeal"))
        XCTAssertTrue(source.contains("edgeTint: SanePanelChrome.accentHighlight"))
        XCTAssertFalse(source.contains("colors: [saneAccentSoft.opacity(0.98), saneAccent.opacity(0.98)]"))
    }

    func testURLHandlingLogsDoNotExposeQueryText() throws {
        let appURL = projectRootURL().appendingPathComponent("SaneBarApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("url.absoluteString, privacy: .public"),
            "URL handler should not publicly log full URL payloads"
        )
        XCTAssertFalse(
            source.contains("searchQuery ?? \"\", privacy: .public"),
            "URL handler should not publicly log user-supplied search query text"
        )
        XCTAssertTrue(
            source.contains("queryPresent: \\(searchQuery != nil, privacy: .public)"),
            "URL handler can log query presence without exposing the query value"
        )
    }

    func testPublicDocsUseCurrentSecurityAndSourceAvailableWording() throws {
        let security = try String(
            contentsOf: projectRootURL().appendingPathComponent("SECURITY.md"),
            encoding: .utf8
        )
        let readme = try String(
            contentsOf: projectRootURL().appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let website = try String(
            contentsOf: projectRootURL().appendingPathComponent("docs/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(security.contains("| 2.x"), "Security policy should track the current major version")
        XCTAssertFalse(security.contains("| 1.0.x"), "Security policy should not advertise stale 1.0.x support")
        XCTAssertTrue(readme.contains("source-available under PolyForm Shield"), "README should avoid ambiguous open-source licensing claims")
        XCTAssertTrue(website.contains("transparent source"), "Website metadata should avoid over-broad public-code wording")
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
        XCTAssertTrue(
            source.contains("shouldSkipDuplicateTerminationForAutomation") &&
                source.contains("SANEAPPS_DISABLE_KEYCHAIN") &&
                source.contains("--sane-no-keychain"),
            "No-keychain automation launches should not self-terminate during runtime smoke relaunch probes"
        )
        XCTAssertTrue(
            source.contains("applicationShouldTerminate") &&
                source.contains("shouldCancelUnexpectedTerminationForAutomation") &&
                source.contains("automationLifecycleBreadcrumbPath"),
            "No-keychain automation should record and cancel unexpected AppKit termination instead of disappearing without diagnostics"
        )
        XCTAssertTrue(
            source.contains("signal(SIGTERM, SIG_IGN)") &&
                source.contains("shouldInstallNoKeychainAutomationSignalGuard"),
            "No-keychain automation should ignore raw SIGTERM so long release soaks cannot lose the app without AppKit diagnostics"
        )
        let mainSource = try String(contentsOf: projectRootURL().appendingPathComponent("main.swift"), encoding: .utf8)
        let signalGuardCall = mainSource.range(of: "installNoKeychainAutomationSignalGuardIfNeeded()")
        let runLoopCall = mainSource.range(of: "\napp.run()")
        XCTAssertTrue(
            signalGuardCall != nil && runLoopCall != nil && signalGuardCall!.lowerBound < runLoopCall!.lowerBound,
            "No-keychain automation signal guard should install before the app run loop starts"
        )

        let actionSource = try String(contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarActionWorkflow.swift"), encoding: .utf8)
        let explicitQuitMarker = actionSource.range(of: ".saneBarExplicitTerminationRequested")?.lowerBound
        let terminateCall = actionSource.range(of: "NSApplication.shared.terminate(nil)")?.lowerBound
        XCTAssertTrue(
            explicitQuitMarker != nil && terminateCall != nil && explicitQuitMarker! < terminateCall!,
            "Explicit menu Quit should mark termination intent before calling terminate"
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
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)
        let recoveryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift")
        let recoverySource = try String(contentsOf: recoveryURL, encoding: .utf8)
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/DiagnosticsService.swift")
        let diagnosticsSource = try String(contentsOf: diagnosticsURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("var statusBarControllerStorage: StatusBarController?"),
            "MenuBarManager should keep the default StatusBarController lazy until deferred UI setup"
        )
        XCTAssertTrue(
            setupSource.contains("let statusBarController = manager.ensureStatusBarController()"),
            "MenuBarManager should only create the default StatusBarController inside setupStatusItem"
        )
        XCTAssertTrue(
            recoverySource.contains("StatusBarController.validateItemPosition(mainItem)") &&
                recoverySource.contains("StatusBarController.validateItemPosition(separator)") &&
                recoverySource.contains("hiddenCollapsedSeparatorIsStructurallyHealthy") &&
                recoverySource.contains("persistedMainDistanceFromRight: persistedMainDistanceFromRight"),
            "Startup validation should require attached status-item windows except for the hidden collapsed separator state, where the main item must stay attached and ordered by persisted user intent"
        )
        XCTAssertTrue(
            diagnosticsSource.contains("hiddenCollapsedSeparatorIsStructurallyHealthy") &&
                diagnosticsSource.contains("startupItemsValid = mainWindowValid && (separatorWindowValid || hiddenCollapsedSeparatorHealthy)") &&
                diagnosticsSource.contains("hiddenCollapsedSeparatorHealthy:") &&
                diagnosticsSource.contains("persistedMainDistanceFromRight: StatusBarDiagnostics.persistedMainDistanceFromRight()"),
            "Diagnostics should report startup item health using the same hidden collapsed separator exception as runtime recovery"
        )
        let coordinatorURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarOperationCoordinator.swift")
        let coordinatorSource = try String(contentsOf: coordinatorURL, encoding: .utf8)
        XCTAssertTrue(
            coordinatorSource.contains("moveQueueHasUsableStructuralState") &&
                coordinatorSource.contains("snapshot.visibilityPhase == .hidden") &&
                coordinatorSource.contains("snapshot.identityPrecision == .exact") &&
                coordinatorSource.contains("snapshot.structuralState == .unattachedWindows"),
            "Hidden-state exact moves should be allowed through pre-queue admission so the move workflow can run its showAll shield before live geometry checks"
        )
        let standardMoveURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let standardMoveSource = try String(contentsOf: standardMoveURL, encoding: .utf8)
        XCTAssertTrue(
            standardMoveSource.contains("activeVisibleBoundaryX > activeSeparatorX") &&
                standardMoveSource.contains("fallbackVisibleBoundaryX > fallbackSeparatorX"),
            "Move-to-visible boundary checks must be ordered-boundary checks, not positive-global-X checks, so left-arranged displays stay valid"
        )
        XCTAssertFalse(
            standardMoveSource.contains("activeVisibleBoundaryX > 0") ||
                standardMoveSource.contains("fallbackVisibleBoundaryX ?? 0"),
            "Move-to-visible code must not reintroduce positive-X assumptions"
        )
        XCTAssertFalse(
            source.contains("self.statusBarController = statusBarController ?? StatusBarController()"),
            "MenuBarManager should not eagerly create status items during init before the deferred startup delay"
        )
        XCTAssertTrue(
            source.contains("currentStatusItemRecoverySnapshot()") &&
                source.contains("executeStatusItemRecoveryAction(") &&
                recoverySource.contains("func currentRuntimeSnapshot("),
            "Runtime position validation should route startup, validation, and restore through one typed recovery snapshot plus one recovery executor"
        )
        guard let visibilityPhaseRange = recoverySource.range(of: "let visibilityPhase: MenuBarVisibilityPhase"),
              let geometrySnapshotRange = recoverySource.range(of: "let geometrySnapshot = MenuBarRuntimeSnapshot("),
              let returnedVisibilityRange = recoverySource.range(of: "visibilityPhase: visibilityPhase,") else {
            XCTFail("Could not locate runtime snapshot visibility-phase wiring")
            return
        }
        XCTAssertLessThan(
            visibilityPhaseRange.lowerBound,
            geometrySnapshotRange.lowerBound,
            "Runtime snapshot should compute the real visibility phase before misorder/geometry checks use the snapshot"
        )
        XCTAssertTrue(
            geometrySnapshotRange.lowerBound < returnedVisibilityRange.lowerBound,
            "Runtime snapshot should reuse the same visibility phase in the returned snapshot"
        )
        XCTAssertTrue(
            setupSource.contains("observe(\\.isVisible") &&
                setupSource.contains("handleUnexpectedStatusItemVisibilityChange(") &&
                setupSource.contains("unexpected-visibility-loss-") &&
                setupSource.contains(".repairPersistedLayoutAndRecreate(.invalidStatusItems)") &&
                setupSource.contains("validationContext: .startupFollowUp"),
            "MenuBarManager should observe unexpected status-item visibility loss, repair it on the background recovery path, and avoid promoting it to manual-repair UX"
        )
        XCTAssertTrue(
            source.contains("geometryCache.clearSeparatorGeometry()"),
            "Recreating status items from persisted layout should invalidate cached separator edges first"
        )
    }

    func testResetToDefaultsAlsoResetsPersistentStatusItemState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("StatusBarPositionRecoveryStore.resetPersistentStatusItemState(") &&
                source.contains("MenuBarSpacingService.shared.resetToDefaults()") &&
                source.contains("MenuBarSpacingService.shared.attemptGracefulRefresh()") &&
                source.contains("freshAutosaveNamespace: true") &&
                source.contains("recreateStatusItemsFromPersistedLayout(reason: \"reset-to-defaults\") {") &&
                source.contains("schedulePositionValidation(context: .manualLayoutRestore, recoveryCount: 0)"),
            "Reset to Defaults should reset host spacing defaults, reset status-item persistence into a fresh autosave namespace, and recreate live menu bar items immediately"
        )
    }

    func testRecoveryRewireWarmsGeometryAndAccessibilityCaches() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let replayURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityPolicy.swift")
        let replaySource = try String(contentsOf: replayURL, encoding: .utf8)
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)
        let recoveryURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift")
        let recoverySource = try String(contentsOf: recoveryURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func schedulePostRecoveryGeometryWarmup(restoreHiddenStateAfterWarmup: Bool = false)"),
            "MenuBarManager should define a dedicated post-recovery geometry warmup helper"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)") &&
                source.contains("await self.geometryResolver.warmSeparatorPositionCache(maxAttempts: 32)") &&
                source.contains("await self.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 32)") &&
                source.contains("let snapshot = self.currentStatusItemRecoverySnapshot()") &&
                source.contains("snapshot.separatorAnchorSource == .live, snapshot.mainAnchorSource == .live") &&
                setupSource.contains("manager.schedulePostRecoveryGeometryWarmup(restoreHiddenStateAfterWarmup: shouldRestoreHidden)") &&
                setupSource.contains("let visibilityReplayReason = manager.statusItemRecoveryWorkflow.hasPendingWakeVisibleAllowListReplay()") &&
                setupSource.contains("? \"status-item-recreate-wake-resume\"") &&
                setupSource.contains("manager.schedulePostRecoveryVisibilityIntentReplay(reason: visibilityReplayReason)") &&
                source.contains("func shouldRunVisibilityIntentEnforcement(reason: String) -> Bool") &&
                source.contains("MenuBarVisibilityPolicy.shouldRunVisibilityIntentEnforcement(") &&
                replaySource.contains("func canRepairWakeVisibleAllowListFromHiddenSnapshot(") &&
                replaySource.contains("hasPendingWakeVisibleAllowListReplay") &&
                source.contains("visibilityIntentReplayTask = Task { @MainActor [weak self] in") &&
                source.contains("while attempt < Self.maxVisibilityIntentReplayAttempts ||") &&
                source.contains("self.statusItemRecoveryWorkflow.hasPendingWakeVisibleAllowListReplay()") &&
                source.contains("schedulePostRecoveryAutoRehideIfNeeded(reason: \"\\(reason)-no-visibility-intent\")") &&
                source.contains("await self.alwaysHiddenPinWorkflow.enforce(") &&
                source.contains("mode: .auditOnly") &&
                source.contains("alwaysHiddenAnchorsNeedReplayRetry()") &&
                source.contains("let alwaysHiddenBoundaryX = geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()") &&
                source.contains("let separatorFrame = geometryResolver.currentLiveSeparatorFrame()") &&
                source.contains("return alwaysHiddenBoundaryX >= separatorFrame.origin.x") &&
                source.contains("Visibility intent replay waiting for healthy always-hidden anchors") &&
                source.contains("let hideAllOtherEnforced = await self.hideAllOtherWorkflow.enforce(") &&
                source.contains("Visibility intent replay waiting for hide-all-other completion") &&
                source.contains("var completedWakeVisibleAllowListRepair = false") &&
                source.contains("completedWakeVisibleAllowListRepair = true") &&
                source.contains("if completedWakeVisibleAllowListRepair {") &&
                source.contains("self.statusItemRecoveryWorkflow.clearWakeVisibleAllowListReplayPending()") &&
                source.contains("if hideAllOtherMode.mode == .repairWithPhysicalMoves") &&
                replaySource.contains("func restoreHiddenStateAfterHealthyValidationIfNeeded(reason: String)") &&
                replaySource.contains("hidingService.applyCurrentStateToLiveItems()") &&
                replaySource.contains("hidingService.configureAlwaysHiddenDelimiter(alwaysHiddenSeparatorItem)") &&
                replaySource.contains("shouldDeferHiddenStateForWakeVisibleAllowList(") &&
                replaySource.contains("Deferring hidden state after wake until Hide All Other visible allow-list replay completes") &&
                source.contains("self.schedulePostRecoveryAutoRehideIfNeeded(reason: replayReason)") &&
                source.contains("self.restorePendingHiddenStateAfterVisibilityReplayFailure(reason: \"\\(replayReasonBase)-replay-gave-up\")") &&
                source.contains("self.schedulePostRecoveryAutoRehideIfNeeded(reason: \"\\(replayReasonBase)-replay-gave-up\")") &&
                replaySource.contains("func schedulePostRecoveryAutoRehideIfNeeded(reason: String)") &&
                replaySource.contains("clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)") &&
                recoverySource.contains("func clearWakeVisibleAllowListReplayPending(clearDeferredReason: Bool = true)") &&
                recoverySource.contains("clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)") &&
                !recoverySource.contains("self.pendingWakeVisibleAllowListReplayUntil = nil\n            return false") &&
                replaySource.contains("Deferring post-recovery hidden state warmup until wake visible allow-list replay completes") &&
                source.contains("func cancelWakeVisibleAllowListReplay(reason: String)") &&
                source.contains("statusItemRecoveryWorkflow.clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)") &&
                !replaySource.contains("if reason.contains(\"wakeResume\") || reason.contains(\"wake-resume\") { isRevealPinned = false }") &&
                replaySource.contains("shouldReplayWakeVisibleAllowListBeforeAutoRehide(") &&
                replaySource.contains("schedulePostRecoveryVisibilityIntentReplay(reason: \"healthy-validation-wake-resume\")") &&
                replaySource.contains("hidingService.scheduleRehide(after: 0.5)") &&
                source.contains("self.appearanceService.refreshAfterStatusItemRecovery()"),
            "Structural recovery should re-warm live core anchors before hidden replay, replay persisted visibility intent, cancel stale wake allow-list replay without unpinning explicit reveals, rearm auto-rehide after recovery movement cancels prior timers, then refresh appearance overlay visibility"
        )
        let replayRetryStart = try XCTUnwrap(source.range(of: "private func alwaysHiddenAnchorsNeedReplayRetry() -> Bool {"))
        let replayRetryEnd = try XCTUnwrap(source.range(of: "func shouldRunVisibilityIntentEnforcement(reason: String) -> Bool {"))
        let replayRetrySource = String(source[replayRetryStart.lowerBound ..< replayRetryEnd.lowerBound])
        XCTAssertFalse(
            replayRetrySource.contains("separatorOriginX()") ||
                replayRetrySource.contains("alwaysHiddenSeparatorOriginX()") ||
                replayRetrySource.contains("> 1"),
            "Visibility replay health must use live separator frames/boundaries, not cached origin/sign checks"
        )
        XCTAssertTrue(
            setupSource.contains("manager.statusBarController.configureStatusItems(") &&
                setupSource.contains("clickAction: #selector(MenuBarActionWorkflow.statusItemClicked(_:))") &&
                setupSource.contains("manager.installMainStatusItemHoverTrackingArea(on: button)"),
            "Structural recovery should restore the main status button identifier, action, image, and hover tracking after recreation"
        )
    }

    func testUninstallScriptClearsCurrentHostStatusItemState() throws {
        let fileURL = projectRootURL().appendingPathComponent("Scripts/uninstall_sanebar.sh")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("defaults -currentHost export NSGlobalDomain -") &&
                source.contains("NSStatusItem (Visible(CC)?|Preferred Position) SaneBar_") &&
                source.contains("defaults -currentHost delete NSGlobalDomain"),
            "Uninstall should remove current-host NSStatusItem visibility and preferred-position state that survives reinstall"
        )
    }

    func testManualHealthRepairRunsDeferredWakeReplayBeforeClearingHealthNote() throws {
        let profileSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarProfileWorkflow.swift"),
            encoding: .utf8
        )
        let healthSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/Settings/HealthSettingsView.swift"),
            encoding: .utf8
        )
        let recoverySource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemRecoveryWorkflow.swift"),
            encoding: .utf8
        )
        let managerSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/MenuBarManager.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            profileSource.contains("private func repairVisibilityReplayReason(reason: String) -> String") &&
                profileSource.contains("manager.hasActionableDeferredWakeVisibleAllowListRepair()") &&
                profileSource.contains("manager.markWakeVisibleAllowListReplayPending(") &&
                profileSource.contains("reason: \"manual-repair-\\(reason)\"") &&
                profileSource.contains("requiresHiddenState: false") &&
                profileSource.contains("return \"healthy-validation-wake-resume-manual-repair-\\(reason)\"") &&
                profileSource.contains("manager.schedulePostRecoveryVisibilityIntentReplay(reason: replayReason)"),
            "Manual Health repair should re-arm the deferred wake replay and use the post-wake physical replay path before claiming the repair is complete"
        )
        XCTAssertTrue(
            !healthSource.contains("pendingDeferredWakeRestoreReason = nil") &&
                healthSource.contains("menuBarManager.hasActionableDeferredWakeVisibleAllowListRepair()") &&
                healthSource.contains("Repair is running. SaneBar will clear the wake repair note after the layout restore finishes."),
            "Health UI should not clear deferred wake guidance until the replay path clears it after a successful physical repair"
        )
        XCTAssertTrue(
            recoverySource.contains("clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)") &&
                recoverySource.contains("guard now <= pendingWakeVisibleAllowListReplayUntil else") &&
                recoverySource.contains("func pendingWakeVisibleAllowListReplayExpired") &&
                managerSource.contains("self.statusItemRecoveryWorkflow.clearWakeVisibleAllowListReplayPending(clearDeferredReason: false)"),
            "Replay TTL expiry should clear only the short-lived replay window, not the customer-visible Health guidance"
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

    func testFrameInTargetZoneRejectsAlwaysHiddenWhenExpectingRegularHidden() {
        let alwaysHiddenFrame = CGRect(x: 60, y: 0, width: 22, height: 22) // midX=71
        let regularHiddenFrame = CGRect(x: 84, y: 0, width: 10, height: 22) // midX=89

        XCTAssertFalse(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: alwaysHiddenFrame,
                separatorX: 100,
                toHidden: true,
                alwaysHiddenBoundaryX: 80
            )
        )
        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: regularHiddenFrame,
                separatorX: 100,
                toHidden: true,
                alwaysHiddenBoundaryX: 80
            )
        )
    }

    func testFrameInTargetZoneRejectsVisibleWhenExpectingIntermediateHiddenLane() {
        let visibleFrame = CGRect(x: 116, y: 0, width: 12, height: 22) // midX=122
        let regularHiddenFrame = CGRect(x: 100, y: 0, width: 10, height: 22) // midX=105

        XCTAssertFalse(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: visibleFrame,
                separatorX: 80,
                toHidden: false,
                alwaysHiddenBoundaryX: 120
            )
        )
        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: regularHiddenFrame,
                separatorX: 80,
                toHidden: false,
                alwaysHiddenBoundaryX: 120
            )
        )
    }

    func testFrameInTargetZoneAcceptsNarrowRegularHiddenLaneMidpoint() {
        let regularHiddenFrame = CGRect(x: 486, y: 0, width: 18, height: 22) // midX=495

        XCTAssertTrue(
            AccessibilityService.frameIsInTargetZone(
                afterFrame: regularHiddenFrame,
                separatorX: 500,
                toHidden: true,
                alwaysHiddenBoundaryX: 490
            )
        )
    }

    func testAlwaysHiddenToHiddenVerificationUsesHiddenLaneNotVisibleLane() {
        let afterFrame = CGRect(x: 708, y: 0, width: 40, height: 22) // midX=728

        XCTAssertTrue(
            AccessibilityInteractionPolicy.frameIsInTargetLane(
                afterFrame: afterFrame,
                targetLane: .hidden,
                separatorX: 1174,
                visibleBoundaryX: 683
            )
        )
        XCTAssertFalse(
            AccessibilityInteractionPolicy.frameIsInTargetLane(
                afterFrame: afterFrame,
                targetLane: .visible,
                separatorX: 1174,
                visibleBoundaryX: 683
            )
        )
    }

    func testAlwaysHiddenToHiddenDirectionAllowsRightwardLaneEntry() {
        let beforeFrame = CGRect(x: 682, y: 0, width: 40, height: 22) // midX=702
        let afterFrame = CGRect(x: 708, y: 0, width: 40, height: 22) // midX=728

        XCTAssertFalse(
            AccessibilityInteractionPolicy.hasDirectionMismatch(
                beforeFrame: beforeFrame,
                afterFrame: afterFrame,
                separatorX: 1174,
                targetLane: .hidden,
                visibleBoundaryX: 683
            )
        )
    }

    func testAlwaysHiddenToHiddenVerificationAcceptsNegativeCoordinateHiddenLane() {
        let hiddenLaneFrame = CGRect(x: -910, y: 0, width: 40, height: 22) // midX=-890
        let alwaysHiddenFrame = CGRect(x: -1120, y: 0, width: 40, height: 22) // midX=-1100
        let visibleFrame = CGRect(x: -560, y: 0, width: 40, height: 22) // midX=-540

        XCTAssertTrue(
            AccessibilityInteractionPolicy.frameIsInTargetLane(
                afterFrame: hiddenLaneFrame,
                targetLane: .hiddenFromAlwaysHidden,
                separatorX: -600,
                visibleBoundaryX: -1080
            )
        )
        XCTAssertFalse(
            AccessibilityInteractionPolicy.frameIsInTargetLane(
                afterFrame: alwaysHiddenFrame,
                targetLane: .hiddenFromAlwaysHidden,
                separatorX: -600,
                visibleBoundaryX: -1080
            )
        )
        XCTAssertFalse(
            AccessibilityInteractionPolicy.frameIsInTargetLane(
                afterFrame: visibleFrame,
                targetLane: .hiddenFromAlwaysHidden,
                separatorX: -600,
                visibleBoundaryX: -1080
            )
        )
        XCTAssertFalse(
            AccessibilityInteractionPolicy.frameIsInTargetLane(
                afterFrame: hiddenLaneFrame,
                targetLane: .hiddenFromAlwaysHidden,
                separatorX: -600,
                visibleBoundaryX: nil
            ),
            "AH-to-Hidden verification should fail closed without an ordered AH boundary"
        )
    }

    func testAlwaysHiddenToHiddenNegativeCoordinateDirectionAllowsRightwardLaneEntryOnly() {
        let beforeFrame = CGRect(x: -1120, y: 0, width: 40, height: 22) // midX=-1100
        let afterFrame = CGRect(x: -910, y: 0, width: 40, height: 22) // midX=-890
        let wrongWayFrame = CGRect(x: -1160, y: 0, width: 40, height: 22) // midX=-1140

        XCTAssertFalse(
            AccessibilityInteractionPolicy.hasDirectionMismatch(
                beforeFrame: beforeFrame,
                afterFrame: afterFrame,
                separatorX: -600,
                targetLane: .hiddenFromAlwaysHidden,
                visibleBoundaryX: -1080
            )
        )
        XCTAssertTrue(
            AccessibilityInteractionPolicy.hasDirectionMismatch(
                beforeFrame: beforeFrame,
                afterFrame: wrongWayFrame,
                separatorX: -600,
                targetLane: .hiddenFromAlwaysHidden,
                visibleBoundaryX: -1080
            )
        )
        XCTAssertTrue(
            AccessibilityInteractionPolicy.hasDirectionMismatch(
                beforeFrame: beforeFrame,
                afterFrame: afterFrame,
                separatorX: -600,
                targetLane: .hiddenFromAlwaysHidden,
                visibleBoundaryX: nil
            ),
            "AH-to-Hidden direction verification should not pass when the lane boundary is missing"
        )
    }

    func testAlwaysHiddenToHiddenTargetsHiddenLaneMidpoint() {
        let target = AccessibilityService.moveTargetX(
            targetLane: .hiddenFromAlwaysHidden,
            iconWidth: 40,
            separatorX: 1174,
            visibleBoundaryX: 823
        )

        XCTAssertEqual(target, 1124, accuracy: 0.001)
    }

    func testRegularHiddenMoveFailsClosedWhenAlwaysHiddenBoundaryIsUnavailable() throws {
        let standardSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift"),
            encoding: .utf8
        )
        let resolverSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveTargetResolver.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            resolverSource.contains("func regularHiddenMoveRequiresAlwaysHiddenBoundary() -> Bool") &&
                standardSource.contains("Expanding ALL icons to resolve regular Hidden lane boundary") &&
                resolverSource.contains("await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)") &&
                resolverSource.contains("Waiting for always-hidden boundary before accepting regular hidden move target") &&
                !standardSource.contains("Falling back to separator-only hidden move target without always-hidden boundary") &&
                !resolverSource.contains("Falling back to separator-only hidden move target without always-hidden boundary") &&
                resolverSource.contains("Regular hidden move target resolution failed without separator or always-hidden boundary") &&
                resolverSource.contains("separatorOverrideX == nil"),
            "Regular Hidden moves must fail closed when the Always Hidden lane boundary is unavailable"
        )
    }

    func testVisibilityReplayDoesNotStarveHideAllOtherBehindAlwaysHiddenRetry() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/MenuBarManager.swift"),
            encoding: .utf8
        )
        let replaySource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarVisibilityPolicy.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
                source.contains("var shouldRetryVisibilityReplay = false") &&
                source.contains("let shouldReplayHideAllOther = settings.hideAllOtherMenuBarItems") &&
                source.contains("statusItemRecoveryWorkflow.recoveryDormantUntil") &&
                source.contains("await self.alwaysHiddenPinWorkflow.enforce(") &&
                source.contains("mode: .auditOnly") &&
                source.contains("let hideAllOtherEnforced = await self.hideAllOtherWorkflow.enforce(") &&
                source.contains("let hideAllOtherMode = self.visibilityIntentReplayHideAllOtherMode(reason: replayReason)") &&
                source.contains("physicalMoveOrigin: hideAllOtherMode.physicalMoveOrigin") &&
                replaySource.contains("let isPostWakeHealthyValidation = isPostWakeVisibleAllowListReplayReason(reason)") &&
                replaySource.contains("let isImmediateWakeReplay = reason.hasPrefix(\"wake-resume\")") &&
                replaySource.contains("let isStartupReconciliation = isStartupVisibilityIntentReplayReason(reason)") &&
                replaySource.contains("if isImmediateWakeReplay {\n            return (.auditOnly, nil)\n        }") &&
                replaySource.contains("if isStartupReconciliation, confidenceAllowsMoves") &&
                replaySource.contains("let hasVisibleAllowList = settings.hideAllOtherMenuBarItems") &&
                replaySource.contains("hasVisibleAllowList: hasVisibleAllowList") &&
                replaySource.contains("isPostWakeHealthyValidation &&") &&
                replaySource.contains("hasPendingWakeVisibleAllowListReplay") &&
                replaySource.contains("canRepairHiddenWakeVisibleAllowList") &&
                replaySource.contains("reason.hasPrefix(\"healthy-validation-wake-resume\")") &&
                replaySource.contains("reason.hasPrefix(\"status-item-recreate-wake-resume\")") &&
                replaySource.contains("reason.hasPrefix(\"healthy-validation-startup-follow-up\")") &&
                replaySource.contains("func visibilityIntentReplayReason(") &&
                replaySource.contains("reason.hasPrefix(\"healthy-validation-screen-parameters-changed\")") &&
                source.contains("let replayReasonBase = MenuBarVisibilityPolicy.visibilityIntentReplayReason(") &&
                source.contains("let replayReason = \"\\(replayReasonBase)-attempt-\\(attempt)\"") &&
                !replaySource.contains("reason.contains(\"healthy-validation\")") &&
                replaySource.contains("hidingState: hidingService.state") &&
                replaySource.contains("return (.repairWithPhysicalMoves, .systemWakeRecovery)") &&
                source.contains("var completedWakeVisibleAllowListRepair = false") &&
                source.contains("if completedWakeVisibleAllowListRepair") &&
                source.contains("Visibility intent replay waiting for hide-all-other completion") &&
                source.contains("self.restorePendingHiddenStateAfterVisibilityReplayFailure(reason: \"\\(replayReasonBase)-replay-gave-up\")") &&
                source.contains("if shouldRetryVisibilityReplay") &&
                source.contains("MenuBarVisibilityPolicy.shouldRunVisibilityIntentEnforcement(") &&
                !source.contains("snapshot.geometryConfidence == .live || snapshot.geometryConfidence == .cached"),
            "Replay should still audit the regular Hidden allow-list when Always Hidden needs another retry, retry incomplete hide-all-other checks, avoid stale geometry, keep immediate wake passive, and allow post-wake visible allow-list repair only on trustworthy healthy validation"
        )
    }

    func testHideAllOtherReportsIncompleteMovesForWakeReplay() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarHideAllOtherWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("mode: MenuBarVisibilityIntentMode = .auditOnly") &&
                source.contains("physicalMoveOrigin: MenuBarPhysicalMoveOrigin? = nil") &&
                source.contains("Physical menu bar moves rejected without an explicit user/automation origin") &&
                source.contains("Hide-all-other enforcement audited without physical moves") &&
                source.contains("let alwaysHiddenBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()") &&
                source.contains("var initialZoneByUniqueId: [String: HideAllOtherZone]") &&
                source.contains("initialZoneByUniqueId[item.app.uniqueId] = Self.hideAllOtherZone(") &&
                source.contains("let orderedItems = items.enumerated().sorted") &&
                source.contains("Hide-all-other rule enabled with an empty visible allow-list") &&
                !source.contains("Hide-all-other enforcement skipped because the visible allow-list is empty") &&
                !source.contains("Hide-all-other enforcement rejected because the visible allow-list is empty") &&
                source.contains("SearchMenuBarZoneClassifier.classifyZone(") &&
                source.contains("SearchMenuBarZoneClassifier.isAlwaysHiddenZone(") &&
                !source.contains("width * 0.3") &&
                source.contains("Self.hideAllOtherReplayMovePriority(shouldShow: lhsShouldShow)") &&
                source.contains("guard Self.hideAllOtherMoveNeeded(initialZone: initialZone, shouldShow: shouldShow)") &&
                source.contains("if shouldShow, isCurrentlyAlwaysHidden") &&
                source.contains("let isCurrentlyAlwaysHidden = initialZone == .alwaysHidden") &&
                source.contains("automaticMoveBudget(forCandidateItemCount: candidateItemCount)") &&
                source.contains("moveIconAlwaysHiddenAndWait(") &&
                source.contains("for pass in 1 ... 2") &&
                source.contains("let verificationItems = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()") &&
                source.contains("let orderedVerificationItems = verificationItems.enumerated().sorted") &&
                source.contains("hideAllOtherFinalMoveNeeded(currentZone: currentZone, shouldShow: shouldShow)") &&
                source.contains("if shouldShow, currentZone == .alwaysHidden") &&
                source.contains("failedMoveUniqueIds.formUnion(finalMoveFailedUniqueIds)") &&
                source.contains("var failedMoveUniqueIds = Set<String>()") &&
                source.contains("var finalMoveFailedUniqueIds = Set<String>()") &&
                source.contains("failedMoveUniqueIds.insert(app.uniqueId)") &&
                source.contains("let shouldRestoreHiddenState = manager.hidingService.state == .hidden") &&
                !source.contains("let shouldRestoreHiddenState = wasHidden || isWakeReplay") &&
                source.contains("if shouldRestoreHiddenState { await manager.hidingService.hide() }") &&
                source.contains("Hide-all-other enforcement incomplete") &&
                source.contains("return false") &&
                source.contains("return !Task.isCancelled"),
            "Hide-all-other replay must repair and report failed post-wake visible allow-list moves so visibility intent replay keeps retrying instead of silently accepting exposed or hidden icons"
        )
    }

    func testHideAllOtherEnforcementUsesSameSeparatorBoundaryAsSearchClassification() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarHideAllOtherWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("manager.geometryResolver.separatorRightEdgeX() ?? manager.geometryResolver.separatorOriginX()"),
            "Hide-all-other enforcement should use the same separator right-edge boundary as search/list classification"
        )
        XCTAssertFalse(
            source.contains("manager.geometryResolver.separatorOriginX() ?? manager.geometryResolver.separatorRightEdgeX()"),
            "Hide-all-other enforcement must not classify from separator origin first; that creates a disagreement band near the divider"
        )
    }

    func testAlwaysHiddenPinEnforcementUsesDedicatedLaneAndAuditDefault() throws {
        let alwaysHiddenSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenPinWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            alwaysHiddenSource.contains("await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(") &&
                alwaysHiddenSource.contains("preferredCenterX: item.app.preferredCenterX") &&
                alwaysHiddenSource.contains("toAlwaysHidden: true") &&
                alwaysHiddenSource.contains("mode: MenuBarVisibilityIntentMode = .auditOnly") &&
                alwaysHiddenSource.contains("physicalMoveOrigin: MenuBarPhysicalMoveOrigin? = nil") &&
                alwaysHiddenSource.contains("Physical menu bar moves rejected without an explicit user/automation origin") &&
                alwaysHiddenSource.contains("Always-hidden pin enforcement audited without physical moves") &&
                alwaysHiddenSource.contains("mode: .auditOnly") &&
                alwaysHiddenSource.contains("let shouldRestoreHiddenState = wasHidden || isWakeReplay") &&
                alwaysHiddenSource.contains("automaticMoveBudget(forCandidateItemCount: filteredPins.count)") &&
                alwaysHiddenSource.contains("if shouldRestoreHiddenState { await manager.hidingService.hide() }") &&
                alwaysHiddenSource.contains("@discardableResult") &&
                alwaysHiddenSource.contains("return false") &&
                alwaysHiddenSource.contains("failedMoveUniqueIds.insert(uniqueId)") &&
                alwaysHiddenSource.contains("Always-hidden pin enforcement incomplete"),
            "Always Hidden pin replay should use the dedicated Always Hidden lane, but scheduled recovery must not perform background physical cursor-moving drags"
        )
    }

    func testHideAllOtherVisibleAllowListTakesPriorityOverAlwaysHiddenPins() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenPinWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("pinConflictsWithHideAllOtherVisibleAllowList") &&
                source.contains("let hideAllOtherVisibleIds = manager.settings.hideAllOtherMenuBarItems") &&
                source.contains("Set(manager.settings.hideAllOtherVisibleItemIds)") &&
                source.contains("!Self.pinConflictsWithHideAllOtherVisibleAllowList("),
            "Always Hidden replay must not move a hide-all-other allow-listed visible item back into Always Hidden"
        )
    }

    func testSettingsProfileLoadUsesCentralProfileApplicationPath() throws {
        let source = try generalSettingsSource()

        XCTAssertTrue(
            source.contains("menuBarManager.profileWorkflow.applyProfile(") &&
                source.contains("preserveProtectedSettings: true") &&
                source.contains("reason: \"settings\"") &&
                !source.contains("settings: profile.settings,\n            layoutSnapshot: profile.layoutSnapshot"),
            "Settings profile Load should use the same central profile-application path as menu and App Intent loading"
        )
    }

    func testHideAllOtherSeedingAvoidsStaleCachedVisibleList() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarHideAllOtherWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
                !source.contains("guard manager.shouldRunVisibilityIntentEnforcement(reason: \"enableHideAllOther\")") &&
                source.contains("manager.visibilityWorkflow.showHiddenItemsNow(trigger: .settingsButton)") &&
                source.contains("refreshKnownClassifiedApps()") &&
                source.contains("Hide-all-other enabled; live enforcement will wait until menu bar anchors are healthy") &&
                source.contains("preserving the existing visible allow-list") &&
                source.contains("Hide-all-other rule enabled with an empty visible allow-list") &&
                source.contains("func enableFromCurrentLayout(onComplete:") &&
                source.contains("onComplete?(false)") &&
                source.contains("onComplete?(true)") &&
                !source.contains("SearchService.shared.cachedClassifiedApps().visible") &&
                !source.contains("self.settings.hideAllOtherMenuBarItems = false") &&
                !source.contains("self.settings.hideAllOtherVisibleItemIds = []") &&
                !source.contains("manager.settings.hideAllOtherVisibleItemIds = []") &&
                !source.contains("settings.hideAllOtherVisibleItemIds = []"),
            "Hide-all-other setup should seed from a fresh, healthy menu bar snapshot without erasing the existing allow-list on transient geometry failures"
        )
    }

    func testHideNewUnlistedSettingsRowOwnsPressAction() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("UI/Settings/GeneralSettingsHidingSection.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("private var hideNewUnlistedToggleRow: some View") &&
                source.contains("Button {") &&
                source.contains("hideAllOtherMenuBarItemsBinding.wrappedValue.toggle()") &&
                source.contains(".accessibilityIdentifier(\"sanebar-hide-new-unlisted-toggle\")") &&
                source.contains("Capsule()") &&
                source.contains("Circle()"),
            "Hide new/unlisted must own a real pressable row so customers and the UI sweep can toggle it reliably"
        )
    }

    func testDiagnosticsIncludeHideAllOtherState() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/DiagnosticsService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("hideAllOtherMenuBarItems: \\(settings.hideAllOtherMenuBarItems)") &&
                source.contains("hideAllOtherVisibleItemCount: \\(settings.hideAllOtherVisibleItemIds.count)"),
            "Bug reports must include Hide All Other state because it changes hidden-state replay safety decisions"
        )
    }

    func testWakeProbeProvesHiddenIconsRemainHidden() throws {
        let source = try scriptSource(entrypoint: "wake_layout_probe.rb", partialPrefix: "wake_layout_probe")

        XCTAssertTrue(
            source.contains("SANEBAR_WAKE_PROBE_REQUIRED_HIDDEN_IDS") &&
                source.contains("SANEBAR_WAKE_PROBE_DYNAMIC_HELPER_IDS") &&
                source.contains("seed_dynamic_helper_hidden_ids!") &&
                source.contains("wait_for_dynamic_helper_ids!") &&
                source.contains("Dynamic helper IDs did not appear before wake proof") &&
                source.contains("move icon to hidden") &&
                source.contains("capture_hidden_zone_baseline!") &&
                source.contains("assert_hidden_zone_persistence!") &&
                source.contains("hidden required IDs remain hidden and are not moved into Visible or Always Hidden") &&
                source.contains("helper-specific Hidden to Visible drift is rejected as a release blocker") &&
                source.contains("missing_hidden_ids") &&
                source.contains("could not prove any baseline hidden IDs stayed present") &&
                source.contains("Falling back to separator-only hidden move target without always-hidden boundary") &&
                source.contains("observed_power_wake_events") &&
                source.contains("seed_hide_all_other_allowlist!") &&
                source.contains("hideAllOtherVisibleItemIds") &&
                source.contains("wait_for_hide_all_other_zone_settle!") &&
                source.contains("seed_required_visible_ids!(missing_visible)") &&
                source.contains("wait_for_required_visible_baseline!") &&
                source.contains("seed_required_visible_ids!(non_visible)") &&
                source.contains("Required visible baseline inventory unavailable") &&
                source.contains("zone_read_error") &&
                source.contains("inventory unavailable while waiting") &&
                source.contains("SANEBAR_WAKE_PROBE_COMMAND_TIMEOUT_SECONDS") &&
                source.contains("wake probe command timeout after") &&
                source.contains("Hide-all-other seeded baseline did not settle before wake proof") &&
                source.contains("hidden_baseline_skip_item?") &&
                source.contains("!item[:bundle_id].to_s.start_with?('com.apple.')") &&
                source.contains("park_pointer_away_from_menu_bar!(label: 'hidden wake')") &&
                source.contains("Wake probe requires cliclick on the Mini to park the pointer away from the menu bar") &&
                source.contains("autoRehideBlockReason'] != 'mouse-in-menu-bar-interaction-region'") &&
                source.contains("wait_for_parked_cursor!(label: label)") &&
                source.contains("Pointer parking did not settle after") &&
                source.contains("cursor_near_park_target?") &&
                source.contains("Passive wake recovery moved cursor") &&
                source.contains("passive wake recovery did not physically move the cursor") &&
                !source.contains("!truthy?(candidate['isMoveInProgress'])") &&
                source.contains("capture_visible_zone_baseline!(required_override: seeded_visible_ids)") &&
                source.contains("Wake probe did not observe app wake logs or system display off/on events") &&
                source.contains("Display is turned off") &&
                source.contains("Display is turned on"),
            "Wake proof should settle the seeded hide-all-other baseline, park the pointer, fail if passive recovery moves the cursor, ignore Apple-owned system extras in the customer fixture, fail if a required regular Hidden icon moves into Visible or Always Hidden, and prove a display wake cycle happened"
        )
        let seededVisibleRange = try XCTUnwrap(source.range(of: "seeded_visible_ids = seed_hide_all_other_allowlist!"))
        let settleRange = try XCTUnwrap(source.range(of: "wait_for_hide_all_other_zone_settle!(seeded_visible_ids)"))
        let seededHideRange = try XCTUnwrap(source.range(of: "hidden seeded baseline"))
        XCTAssertLessThan(
            seededVisibleRange.lowerBound,
            settleRange.lowerBound,
            "Wake probe should only wait for hide-all-other settle after seeding the visible allow-list"
        )
        XCTAssertLessThan(
            settleRange.lowerBound,
            seededHideRange.lowerBound,
            "Wake probe should let hide-all-other enforcement settle before it hides for the wake baseline"
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
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift")
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
            source.contains("let laneMidX = ahBoundary + (hiddenLaneWidth * 0.5)") &&
                source.contains("let laneMargin = min(CGFloat(6), max(CGFloat(1), hiddenLaneWidth * 0.25))"),
            "Hidden moves should target the real regular Hidden lane, even when the lane is narrow"
        )
        XCTAssertTrue(
            source.contains("guard let ahBoundary = visibleBoundaryX else {") &&
                source.contains("return farHiddenX"),
            "Hidden moves without an always-hidden boundary should still keep the direct farHiddenX target for normal-width icons"
        )
        XCTAssertTrue(
            source.contains("let boundedSeparatorSafety = min(separatorSafety, max(laneMargin, hiddenLaneWidth * 0.45))") &&
                source.contains("let maxRegularHiddenX = separatorX - boundedSeparatorSafety"),
            "Hidden moves should enforce a separator-side safety margin for reliable midpoint verification"
        )
        XCTAssertTrue(
            source.contains("let rightBiasInset = max(6, min(20, iconWidth * 0.45))"),
            "Hidden moves should bias toward the separator-side hidden lane to avoid AH drift after re-hide transitions"
        )
        XCTAssertTrue(
            source.contains("let wideRegularHiddenThreshold: CGFloat = 56") &&
                source.contains("let fallbackRegularHiddenX = min(max(farHiddenX, minRegularHiddenX), maxRegularHiddenX)") &&
                source.contains("return iconWidth >= wideRegularHiddenThreshold ? fallbackRegularHiddenX : boundedPreferredX"),
            "Hidden move target should stay clamped to lane bounds while allowing the deeper fallback to win for wide icons"
        )
    }

    func testWideRegularHiddenMoveCanUseDeeperFallbackInsideLane() {
        let target = AccessibilityService.moveTargetX(
            targetLane: .hidden,
            iconWidth: 72,
            separatorX: 500,
            visibleBoundaryX: 410
        )

        XCTAssertEqual(target, 416, accuracy: 0.001)
    }

    func testNarrowRegularHiddenMoveTargetsLaneMidpoint() {
        let target = AccessibilityService.moveTargetX(
            targetLane: .hidden,
            iconWidth: 72,
            separatorX: 500,
            visibleBoundaryX: 490
        )

        XCTAssertEqual(target, 495, accuracy: 0.001)
    }

    func testVisibleMoveTargetUsesMinimumRightOfSeparatorInFlushLayout() {
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: 16,
            separatorX: 1663,
            visibleBoundaryX: 1663
        )
        XCTAssertEqual(target, 1664, accuracy: 0.001)
    }

    func testVisibleMoveTargetStaysInsideTightVisibleLane() {
        let target = AccessibilityService.moveTargetX(
            toHidden: false,
            iconWidth: 40,
            separatorX: 1249,
            visibleBoundaryX: 1251
        )
        XCTAssertEqual(target, 1250, accuracy: 0.001)
        XCTAssertLessThan(target, 1251)
    }

    func testAlwaysHiddenMoveTargetUsesSeparatorAdjacentInsertion() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("case .alwaysHidden:") &&
                source.contains("let wideAlwaysHiddenThreshold: CGFloat = 56") &&
                source.contains("? max(moveOffset, iconWidth + 40)") &&
                source.contains("return separatorX - alwaysHiddenOffset"),
            "Always-hidden moves should use a dedicated separator-adjacent target with extra depth for wide status items"
        )

        let target = AccessibilityService.moveTargetX(
            targetLane: .alwaysHidden,
            iconWidth: 22,
            separatorX: 828,
            visibleBoundaryX: nil
        )
        XCTAssertEqual(target, 786, accuracy: 0.001)
    }

    func testWideAlwaysHiddenMoveTargetUsesExtraDepthWithoutGenericOvershoot() {
        let target = AccessibilityService.moveTargetX(
            targetLane: .alwaysHidden,
            iconWidth: 69,
            separatorX: 858,
            visibleBoundaryX: nil
        )

        XCTAssertEqual(target, 749, accuracy: 0.001)
    }

    func testMoveVerificationContainsDirectionGuard() throws {
        let dragURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarDragService.swift")
        let dragSource = try String(contentsOf: dragURL, encoding: .utf8)
        let policyURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)

        XCTAssertTrue(
            dragSource.contains("Move direction mismatch: expected rightward visible move"),
            "Move verification should reject stale-boundary false positives when visible moves drift left"
        )
        XCTAssertTrue(
            policySource.contains("private nonisolated static func visibleInsertionTargetX(") &&
                policySource.contains("let maxX = max(boundary - mainSafety, minX)") &&
                policySource.contains("return min(max(laneMidX, minX), maxX)"),
            "Visible move targeting must stay clamped inside the divider/SaneBar lane (no overshoot into the system area) while leaving reflow slack off the separator"
        )
    }

}
