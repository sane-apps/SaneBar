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

    func testSaneUIPackageIsPinnedForReproducibleBuilds() throws {
        let projectURL = projectRootURL().appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let resolvedURL = projectRootURL()
            .appendingPathComponent("SaneBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let resolved = try String(contentsOf: resolvedURL, encoding: .utf8)

        XCTAssertTrue(project.contains("SaneUI:"), "SaneUI should remain an explicit dependency")
        XCTAssertTrue(
            project.contains("revision: f1a8f67b9a53eb267a1e218b8807bd2ebddacaab"),
            "SaneUI should pin the shared settings chrome revision for release reproducibility"
        )
        XCTAssertFalse(
            project.contains("SaneUI:\n    url: https://github.com/sane-apps/SaneUI.git\n    branch: main"),
            "SaneUI should not track a moving branch in release configuration"
        )
        XCTAssertTrue(
            resolved.contains("\"revision\" : \"f1a8f67b9a53eb267a1e218b8807bd2ebddacaab\""),
            "Package.resolved should resolve SaneUI to the release-tested revision"
        )
        XCTAssertFalse(
            resolved.contains("\"branch\" : \"main\""),
            "Package.resolved should not preserve SaneUI as a moving branch pin"
        )
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
                recoverySource.contains("hiddenCollapsedSeparatorIsStructurallyHealthy"),
            "Startup validation should require attached status-item windows except for the hidden collapsed separator state, where the main item must stay attached and ordered near Control Center"
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
        XCTAssertTrue(
            setupSource.contains("observe(\\.isVisible") &&
                setupSource.contains("handleUnexpectedStatusItemVisibilityChange(") &&
                setupSource.contains("unexpected-visibility-loss-") &&
                setupSource.contains(".repairPersistedLayoutAndRecreate(.invalidStatusItems)"),
            "MenuBarManager should observe unexpected status-item visibility loss and route it through the existing structural recovery path"
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
            source.contains("StatusBarController.resetPersistentStatusItemState(") &&
                source.contains("freshAutosaveNamespace: true") &&
                source.contains("recreateStatusItemsFromPersistedLayout(reason: \"reset-to-defaults\") {") &&
                source.contains("schedulePositionValidation(context: .manualLayoutRestore, recoveryCount: 0)"),
            "Reset to Defaults should reset status-item persistence into a fresh autosave namespace and recreate live menu bar items immediately"
        )
    }

    func testRecoveryRewireWarmsGeometryAndAccessibilityCaches() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/MenuBarManager.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let setupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStatusItemSetupWorkflow.swift")
        let setupSource = try String(contentsOf: setupURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func schedulePostRecoveryGeometryWarmup(restoreHiddenStateAfterWarmup: Bool = false)"),
            "MenuBarManager should define a dedicated post-recovery geometry warmup helper"
        )
        XCTAssertTrue(
            source.contains("AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)") &&
                source.contains("await self.geometryResolver.warmSeparatorPositionCache(maxAttempts: 32)") &&
                source.contains("await self.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 32)") &&
                source.contains("let separatorAnchorSource = self.geometryResolver.currentSeparatorAnchorSource()") &&
                source.contains("separatorAnchorSource == .live || separatorAnchorSource == .cached") &&
                setupSource.contains("manager.schedulePostRecoveryGeometryWarmup(restoreHiddenStateAfterWarmup: shouldRestoreHidden)") &&
                setupSource.contains("manager.schedulePostRecoveryVisibilityIntentReplay(reason: \"status-item-recreate\")") &&
                source.contains("func shouldRunVisibilityIntentEnforcement(reason: String) -> Bool") &&
                source.contains("snapshot.hasTrustworthyBootstrapAnchors") &&
                source.contains("visibilityIntentReplayTask = Task { @MainActor [weak self] in") &&
                source.contains("for attempt in 1 ... Self.maxVisibilityIntentReplayAttempts") &&
                source.contains("await self.alwaysHiddenPinWorkflow.enforce(") &&
                source.contains("mode: .auditOnly") &&
                source.contains("alwaysHiddenAnchorsNeedReplayRetry()") &&
                source.contains("Visibility intent replay waiting for healthy always-hidden anchors") &&
                source.contains("let hideAllOtherEnforced = await self.hideAllOtherWorkflow.enforce(") &&
                source.contains("Visibility intent replay waiting for hide-all-other completion") &&
                source.contains("self.schedulePostRecoveryAutoRehideIfNeeded(reason: replayReason)") &&
                source.contains("func schedulePostRecoveryAutoRehideIfNeeded(reason: String)") &&
                source.contains("if reason.contains(\"wakeResume\") { isRevealPinned = false }") &&
                source.contains("hidingService.scheduleRehide(after: 0.5)") &&
                source.contains("self.appearanceService.refreshAfterStatusItemRecovery()"),
            "Structural recovery should re-warm separator geometry from a trustworthy anchor, replay persisted visibility intent, clear stale wake reveal pins, rearm auto-rehide after recovery movement cancels prior timers, then refresh appearance overlay visibility"
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

        XCTAssertTrue(
            source.contains("var shouldRetryVisibilityReplay = false") &&
                source.contains("await self.alwaysHiddenPinWorkflow.enforce(") &&
                source.contains("mode: .auditOnly") &&
                source.contains("let hideAllOtherEnforced = await self.hideAllOtherWorkflow.enforce(") &&
                source.contains("Visibility intent replay waiting for hide-all-other completion") &&
                source.contains("if shouldRetryVisibilityReplay") &&
                source.contains("snapshot.geometryConfidence == .live || snapshot.geometryConfidence == .cached"),
            "Replay should still audit the regular Hidden allow-list when Always Hidden needs another retry, retry incomplete hide-all-other checks, avoid stale geometry, and avoid background physical cursor-moving drags"
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
                source.contains("guard Self.hideAllOtherMoveNeeded(initialZone: initialZone, shouldShow: shouldShow)") &&
                source.contains("if shouldShow, isCurrentlyAlwaysHidden") &&
                source.contains("let isCurrentlyAlwaysHidden = initialZone == .alwaysHidden") &&
                source.contains("moveIconAlwaysHiddenAndWait(") &&
                source.contains("for pass in 1 ... 2") &&
                source.contains("let verificationItems = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()") &&
                source.contains("hideAllOtherFinalMoveNeeded(currentZone: currentZone, shouldShow: shouldShow)") &&
                source.contains("if shouldShow, currentZone == .alwaysHidden") &&
                source.contains("failedMoveUniqueIds.formUnion(finalMoveFailedUniqueIds)") &&
                source.contains("var failedMoveUniqueIds = Set<String>()") &&
                source.contains("var finalMoveFailedUniqueIds = Set<String>()") &&
                source.contains("failedMoveUniqueIds.insert(app.uniqueId)") &&
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

    func testAlwaysHiddenPinEnforcementDoesNotRemoveItsOwnPin() throws {
        let alwaysHiddenSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenPinWorkflow.swift"),
            encoding: .utf8
        )
        let queueSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveQueueWorkflow.swift"),
            encoding: .utf8
        )
        let standardSource = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            alwaysHiddenSource.contains("clearAlwaysHiddenPinAfterMove: false") &&
                alwaysHiddenSource.contains("mode: MenuBarVisibilityIntentMode = .auditOnly") &&
                alwaysHiddenSource.contains("physicalMoveOrigin: MenuBarPhysicalMoveOrigin? = nil") &&
                alwaysHiddenSource.contains("Physical menu bar moves rejected without an explicit user/automation origin") &&
                alwaysHiddenSource.contains("Always-hidden pin enforcement audited without physical moves") &&
                alwaysHiddenSource.contains("mode: .auditOnly") &&
                queueSource.contains("clearAlwaysHiddenPinAfterMove: Bool = true") &&
                standardSource.contains("context.request.clearAlwaysHiddenPinAfterMove") &&
                alwaysHiddenSource.contains("@discardableResult") &&
                alwaysHiddenSource.contains("return false") &&
                alwaysHiddenSource.contains("failedMoveUniqueIds.insert(uniqueId)") &&
                alwaysHiddenSource.contains("Always-hidden pin enforcement incomplete"),
            "Always Hidden pin replay should move pinned items without clearing the persisted pin it is enforcing, but scheduled recovery must not perform background physical cursor-moving drags"
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
            source.contains("manager.shouldRunVisibilityIntentEnforcement(reason: \"enableHideAllOther\")") &&
                source.contains("refreshKnownClassifiedApps()") &&
                !source.contains("SearchService.shared.cachedClassifiedApps().visible") &&
                !source.contains("self.settings.hideAllOtherMenuBarItems = false") &&
                !source.contains("self.settings.hideAllOtherVisibleItemIds = []") &&
                !source.contains("manager.settings.hideAllOtherVisibleItemIds = []") &&
                !source.contains("settings.hideAllOtherVisibleItemIds = []"),
            "Hide-all-other setup should seed from a fresh, healthy menu bar snapshot without erasing the existing allow-list on transient geometry failures"
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
                source.contains("Hide-all-other seeded baseline did not settle before wake proof") &&
                source.contains("!item[:bundle_id].to_s.start_with?('com.apple.')") &&
                source.contains("park_pointer_away_from_menu_bar!(label: 'hidden wake')") &&
                source.contains("Wake probe requires cliclick on the Mini to park the pointer away from the menu bar") &&
                source.contains("autoRehideBlockReason'] != 'mouse-in-menu-bar-interaction-region'") &&
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
        let dragURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityMenuBarDragService.swift")
        let dragSource = try String(contentsOf: dragURL, encoding: .utf8)
        let policyURL = projectRootURL().appendingPathComponent("Core/Services/AccessibilityInteractionPolicy.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)

        XCTAssertTrue(
            dragSource.contains("Move direction mismatch: expected rightward visible move"),
            "Move verification should reject stale-boundary false positives when visible moves drift left"
        )
        XCTAssertTrue(
            policySource.contains("return max(separatorX + 1, min(separatorX + moveOffset, boundary - 2))"),
            "Visible move targeting should stay between the divider and SaneBar icon instead of overshooting into the system area"
        )
    }

}
