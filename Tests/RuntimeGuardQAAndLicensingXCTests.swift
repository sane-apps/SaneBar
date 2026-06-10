@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardQAAndLicensingXCTests: RuntimeGuardTestCase {
    func testQAGateTreatsDoesNotFunctionAsRegressionLikeIssue() throws {
        let source = try projectQASource()

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
        let source = try projectQASource()

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
        let source = try projectQASource()

        XCTAssertTrue(
            source.contains("def check_runtime_release_smoke"),
            "Project QA should expose a dedicated runtime smoke gate"
        )
        XCTAssertTrue(
            source.contains("Runtime smoke must run on the mini via ./scripts/SaneMaster.rb"),
            "Project QA should block local false-confidence runtime smoke runs"
        )
        XCTAssertTrue(
            source.contains("SANEMASTER_ALLOW_UNSIGNED_FALLBACK' => '0'") &&
                source.contains("'test_mode',") &&
                source.contains("'--release',") &&
                source.contains("'--no-logs'"),
            "Project QA should stage a signed release app before runtime smoke instead of falling back to an installed app"
        )
        XCTAssertTrue(
            source.contains("startup_probe_script = File.join(SCRIPTS_DIR, 'startup_layout_probe.rb')") &&
                source.contains("heartbeat_label: 'runtime startup layout probe'") &&
                source.contains("'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH") &&
                source.contains("'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH") &&
                source.contains("startup_probe_env.merge!(runtime_probe_no_keychain_env(target))"),
            "Project QA should run a dedicated startup layout probe after browse smoke so poisoned relaunch state is release-gated too"
        )
        XCTAssertTrue(
            source.contains("screenshot_capture_available = runtime_screenshot_capture_available?(screenshot_dir)") &&
                source.contains("release_smoke_screenshots_required = ENV.fetch('SANEBAR_RELEASE_SMOKE_SCREENSHOTS', '1') != '0'") &&
                source.contains("capture_runtime_smoke_screenshots = release_smoke_screenshots_required && screenshot_capture_available") &&
                source.contains("appearance_settings_backup = prepare_runtime_smoke_appearance_settings! if capture_runtime_smoke_screenshots") &&
                source.contains("'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TRANSITIONS' => capture_runtime_smoke_screenshots ? '1' : '0'") &&
                source.contains("'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TINT_PIXELS' => capture_runtime_smoke_screenshots ? '1' : '0'") &&
                source.contains("'SANEBAR_SMOKE_REQUIRE_VISIBLE_APPEARANCE_PIXELS' => capture_runtime_smoke_screenshots ? '1' : '0'") &&
                source.contains("restore_runtime_smoke_appearance_settings!(appearance_settings_backup)") &&
                source.contains("'SANEBAR_SMOKE_CAPTURE_SCREENSHOTS' => capture_runtime_smoke_screenshots ? '1' : '0'") &&
                !source.contains("screencapture"),
            "Project QA runtime smoke should require app/window-scoped screenshot and tint-pixel proof by default, seed custom appearance only for visual smoke, and restore settings"
        )
        XCTAssertTrue(
            source.contains("return true if internal_runtime_snapshot_supported?") &&
                source.contains("def internal_runtime_snapshot_supported?") &&
                source.contains("capture browse panel snapshot") &&
                source.contains("queue browse panel snapshot") &&
                source.contains("capture settings window snapshot") &&
                source.contains("queue settings window snapshot"),
            "Project QA runtime smoke should treat the staged app's internal browse and settings snapshot commands as the primary screenshot capability"
        )
        XCTAssertTrue(
            source.contains("resolve_runtime_screenshot_tool") &&
                source.contains("command -v screenshot"),
            "Project QA runtime smoke should retain a window-scoped screenshot fallback when in-app snapshot support is unavailable"
        )
        XCTAssertTrue(
            source.contains("Runtime smoke screenshot/tint evidence is required but unavailable on this host.") &&
                source.contains("runtime smoke screenshot/tint evidence unavailable"),
            "Project QA runtime smoke should fail clearly when required screenshot/tint proof cannot be captured"
        )
        XCTAssertTrue(
            source.contains("expected_screenshots = runtime_smoke_expected_modes(target).to_h"),
            "Project QA runtime smoke should still resolve screenshot artifacts for every required visual state when screenshot capture is explicitly enabled"
        )
        XCTAssertTrue(
            source.contains(#"Dir.glob(File.join(screenshot_dir, "sanebar-#{mode}-*.png"))"#),
            "Project QA runtime smoke should resolve screenshot artifacts by browse mode"
        )
        XCTAssertTrue(
            source.contains("modes << 'findIcon' if commands.include?('open icon panel')"),
            "Project QA runtime smoke should derive expected visual captures from the staged app's AppleScript support"
        )
        XCTAssertTrue(
            source.contains("modes << 'settings' if commands.include?('open settings window')"),
            "Project QA runtime smoke should require a settings screenshot when the staged app exposes the settings-window automation hooks"
        )
        XCTAssertTrue(
            source.contains("RUNTIME_SMOKE_PASSES = 1"),
            "Project QA runtime smoke should require a repeat pass to catch warm-state regressions"
        )
        XCTAssertTrue(
            source.contains("RUNTIME_SHARED_BUNDLE_IDS = %w[") &&
                source.contains("com.apple.menuextra.focusmode") &&
                source.contains("com.apple.menuextra.display"),
            "Project QA runtime smoke should keep a stable focused shared-bundle candidate set for high-risk Apple menu extras"
        )
        XCTAssertTrue(
            source.contains("RUNTIME_NATIVE_APPLE_IDS = %w[") &&
                source.contains("com.apple.menuextra.siri") &&
                source.contains("com.apple.menuextra.spotlight") &&
                source.contains("RUNTIME_HOST_EXACT_ID_SENTINEL_IDS = %w[") &&
                source.contains("at.obdev.littlesnitch.networkmonitor") &&
                source.contains("at.obdev.littlesnitch.agent"),
            "Project QA runtime smoke should also keep stable exact-id lanes for native Apple items and the higher-pressure host sentinel path"
        )
        XCTAssertTrue(
            source.contains("RUNTIME_DYNAMIC_HELPER_FIXTURE_ID = 'com.sindresorhus.Lungo-setapp'") &&
                source.contains("RUNTIME_DYNAMIC_HELPER_FIXTURE_IDS = %w[") &&
                source.contains("prelaunch_runtime_dynamic_helper_fixture!") &&
                source.contains("ensure_runtime_dynamic_helper_wake_fixture!(target)") &&
                source.contains("'SANEBAR_WAKE_PROBE_DYNAMIC_HELPER_IDS' => dynamic_helper_ids.join(',')") &&
                source.contains("Lungo-style Hidden-to-Visible wake drift is release-blocking"),
            "Project QA runtime smoke should build a deterministic Lungo-style helper fixture and require wake proof for that exact hidden ID"
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
            source.contains("if pass_number > 1") &&
                source.contains("Runtime smoke could not relaunch target") &&
                source.contains("relaunch failed before pass"),
            "Project QA runtime smoke should relaunch between passes so every launch-idle budget check measures a fresh app launch"
        )
        XCTAssertTrue(
            source.contains("retryable_runtime_smoke_failure?(smoke_out)") &&
                source.contains("relaunching after transient runtime smoke failure"),
            "Project QA runtime smoke should retry the narrow transient relaunch flake path before failing the release"
        )
        XCTAssertTrue(
            source.contains("def runtime_smoke_missing_apple_menu_extra_policy?(smoke_output)") &&
                source.contains("runtime_smoke_missing_apple_menu_extra_policy?(smoke_output)") &&
                source.contains("activate browse icon failed"),
            "Project QA runtime smoke should retry or defer volatile Apple menu-extra disappearance instead of reporting it as an app regression"
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
            source.contains("shared_bundle_ids = runtime_smoke_available_shared_bundle_candidate_ids(") &&
                source.contains("ensure_runtime_shared_bundle_fixture!(target)") &&
                source.contains("RUNTIME_SHARED_BUNDLE_FIXTURE_IDS = %w[") &&
                source.contains("def runtime_smoke_available_shared_bundle_candidate_ids(target, required_ids:)") &&
                source.contains("next unless zone[:movable]") &&
                source.contains("shared_group = grouped.values.find { |items| items.length >= 2 }") &&
                source.contains("Runtime smoke had no shared-bundle exact-id candidates.") &&
                source.contains("the deterministic shared-bundle fixture must launch") &&
                source.contains("run_focused_runtime_smoke_exact_ids(") &&
                source.contains("'SANEBAR_SMOKE_REQUIRED_IDS' => exact_ids.join(',')") &&
                source.contains("'SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES' => '1'") &&
                source.contains("lane_name: 'shared-bundle'") &&
                source.contains("retryable_failure_method: :retryable_shared_bundle_runtime_smoke_failure?"),
            "Project QA runtime smoke should always prove shared-bundle exact-ID movement with either host items or the deterministic fixture"
        )
        XCTAssertTrue(
            source.contains("native_apple_ids = runtime_smoke_available_required_candidate_ids(") &&
                source.contains("required_ids: RUNTIME_NATIVE_APPLE_IDS") &&
                source.contains("lane_name: 'native-apple exact-id'") &&
                source.contains("host_exact_id_ids = runtime_smoke_available_required_candidate_ids(") &&
                source.contains("required_ids: RUNTIME_HOST_EXACT_ID_SENTINEL_IDS") &&
                source.contains("lane_name: 'host exact-id'"),
            "Project QA runtime smoke should also run dedicated focused passes for native Apple items and the host exact-id sentinel when those IDs exist"
        )
        XCTAssertTrue(
            source.contains("runtime_smoke_no_candidate_fixture_policy?(smoke_out)") &&
                source.contains("default runtime fixture pool empty on this host; keeping browse/layout result and deferring coverage to shared-bundle exact-id smoke") &&
                source.contains("default_move_coverage_deferred = true"),
            "Project QA runtime smoke should treat an empty default fixture pool as fixture-policy fallout and hand coverage to focused exact-id passes"
        )
        XCTAssertTrue(
            source.contains("shared_bundle_exact_id_pool_empty=1") &&
                source.contains("Runtime smoke had no shared-bundle exact-id candidates.") &&
                source.contains("Shared-bundle move regressions are release-blocking") &&
                source.contains("shared-bundle exact-id smoke unavailable"),
            "Project QA runtime smoke should fail release QA when the shared-bundle exact-ID lane is unavailable"
        )
        XCTAssertTrue(
            source.contains("def runtime_smoke_relaunch_command(target)") &&
                source.contains("command = ['open', '--fresh']") &&
                source.contains("command += ['--env', 'SANEAPPS_DISABLE_KEYCHAIN=1']") &&
                source.contains("launch_args = ['--sane-skip-app-move']") &&
                source.contains("launch_args << '--sane-no-keychain' if target[:no_keychain]") &&
                source.contains("command += ['--args', *launch_args]") &&
                source.contains("def runtime_probe_no_keychain_env(target)") &&
                source.contains("wake_probe_env.merge!(runtime_probe_no_keychain_env(target))") &&
                source.contains("'SANEBAR_PROBE_FORCE_NO_KEYCHAIN' => '1'") &&
                source.contains("File.write(\"#{RUNTIME_WAKE_PROBE_LOG_PATH}.stdout\", wake_probe_out)") &&
                source.contains("system(*runtime_smoke_relaunch_command(target), out: File::NULL, err: File::NULL)"),
            "Project QA runtime smoke relaunches should mirror SaneMaster's fresh no-keychain launch shape so Pro-only checks do not silently downgrade or bind to a stale process"
        )
        XCTAssertTrue(
            source.contains("Runtime smoke requires a Pro-enabled target for Always Hidden checks; the mini runtime target stayed in free mode") &&
                source.contains("licenseIsPro=#{snapshot['licenseIsPro'].inspect}"),
            "Runtime smoke should fail loudly when the relaunch target still comes up in free mode"
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
        XCTAssertTrue(
            source.contains("runtimeSmokeFocusedExactIdSets: [") &&
                source.contains("lane: 'shared-bundle'") &&
                source.contains("lane: 'native-apple'") &&
                source.contains("lane: 'host-exact-id'"),
            "Project QA status snapshots should record every focused exact-id runtime lane that release preflight expects"
        )
    }

    func testReleasePreflightForwardsRuntimeSmokeToProjectQA() throws {
        let source = try readShared("infra/SaneProcess/scripts/sanemaster/release.rb")

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
        // The Verify module is split across partials (Rule #10); the guarded
        // behavior may live in any of them.
        let source = try [
            "infra/SaneProcess/scripts/sanemaster/verify.rb",
            "infra/SaneProcess/scripts/sanemaster/verify_support.rb",
            "infra/SaneProcess/scripts/sanemaster/verify_doctor.rb",
        ].map { try readShared($0) }.joined(separator: "\n")

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
        let source = try projectQASource()

        XCTAssertTrue(
            source.contains("'--connect-timeout', connect_timeout") &&
                source.contains("'--max-time', max_time") &&
                source.contains("def curl_url_status(url, head:, connect_timeout:, max_time:)") &&
                source.contains("attempts.times do |attempt|"),
            "QA URL checks should use bounded curl probes because Ruby DNS resolution can outlive Net::HTTP timeouts"
        )
        XCTAssertTrue(
            source.contains("Historical appcast enclosure could not be confirmed"),
            "Historical appcast URL flakes should warn while the latest enclosure remains release-blocking"
        )
        XCTAssertTrue(
            source.contains("head_code = curl_url_status(url, head: true, connect_timeout: connect_timeout, max_time: max_time)") &&
                source.contains("return head_code unless head_code == 405 || head_code.nil?") &&
                source.contains("curl_url_status(url, head: false, connect_timeout: connect_timeout, max_time: max_time)"),
            "QA URL checks should retry with GET when HEAD-only probing is blocked"
        )
        XCTAssertTrue(
            source.contains("[401, 403, 405].include?(response_code)"),
            "QA URL checks should treat anti-bot and auth-gated responses as reachable after fallback"
        )
        XCTAssertTrue(
            source.contains("reachable = response_code && response_code < 400"),
            "QA URL checks should report timed-out URL probes as errors instead of throwing NoMethodError"
        )
    }

    func testLiveSmokeReportsMeaningfulBrowseActivationFailures() throws {
        let source = try scriptSource(entrypoint: "live_zone_smoke.rb", partialPrefix: "live_zone_smoke")

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
        let qaSource = try projectQASource()
        XCTAssertTrue(
            qaSource.contains("QA_STATUS_PATH"),
            "Project QA should persist a latest-run status snapshot"
        )
        XCTAssertTrue(
            qaSource.contains("write_status_snapshot(exit_code: exit_code)"),
            "Project QA should record whether the latest gate passed or failed"
        )

        let validationSource = try readShared("infra/SaneProcess/scripts/validation_report.rb")
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

        let saneMasterSource = try readShared("infra/SaneProcess/scripts/SaneMaster.rb")
        XCTAssertTrue(
            saneMasterSource.contains("sync_outputs_from_mini!(Dir.pwd, execution_repo)"),
            "Mini-first routing should sync output artifacts back from the actual routed workspace so local reporting sees the same QA truth"
        )

        let releaseSource = try readShared("infra/SaneProcess/scripts/sanemaster/release.rb")
        XCTAssertTrue(
            releaseSource.contains("outputs', 'release_preflight_status.json"),
            "Shared release preflight should persist its own status snapshot so apps without custom qa.rb support still feed validation"
        )
        XCTAssertTrue(
            releaseSource.contains("write_release_status_snapshot("),
            "Shared release preflight should write a durable pass/fail snapshot before exiting"
        )
    }

    func testProjectQAGuardrailsTrackSplitArchitectureFiles() throws {
        let qaURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let source = try String(contentsOf: qaURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("StatusBarPositionStore.swift") &&
                source.contains("StatusBarControllerMigrationTests.swift") &&
                source.contains("StatusBarControllerLifecycleTests.swift") &&
                source.contains("StatusBarControllerResetRecoveryTests.swift") &&
                !source.contains("STATUS_BAR_CONTROLLER_TESTS = File.join(PROJECT_ROOT, 'Tests', 'StatusBarControllerTests.swift')"),
            "Project QA migration guardrails should follow the split position-store and migration/recovery test owners"
        )
        XCTAssertTrue(
            source.contains("IconMovingVisibleRegressionTests.swift") &&
                source.contains("SearchWindowDiscoveryTests.swift") &&
                source.contains("RuntimeGuardStartupRecoveryXCTests.swift") &&
                source.contains("RuntimeGuardQASmokeXCTests.swift") &&
                source.contains("RuntimeGuardMoveQueueXCTests.swift") &&
                source.contains("The move engine should keep queued zone-move planning") &&
                !source.contains("'Tests/IconMovingTests.swift'") &&
                !source.contains("'Tests/SearchWindowTests.swift'") &&
                !source.contains("'Tests/RuntimeGuardXCTests.swift'"),
            "Project QA recurring-regression guardrails should not require deleted god-test files after the architecture split"
        )
    }

    func testReleasePreflightDowngradesAuthNoiseToStructuredSkips() throws {
        let source = try readShared("infra/SaneProcess/scripts/sanemaster/release.rb")

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
        let movingURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarMoveQueueWorkflow.swift")
        let movingSource = try String(contentsOf: movingURL, encoding: .utf8)
        let standardURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
        let standardSource = try String(contentsOf: standardURL, encoding: .utf8)
        let alwaysHiddenURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenIconMoveWorkflow.swift")
        let alwaysHiddenSource = try String(contentsOf: alwaysHiddenURL, encoding: .utf8)
        XCTAssertTrue(
            standardSource.contains("let wasHidden = manager.hidingService.state == .hidden") &&
                alwaysHiddenSource.contains("let wasHidden = manager.hidingService.state == .hidden"),
            "Icon move flows should use live hidingService.state to avoid stale hidingState races during fast transitions"
        )
        XCTAssertFalse(
            movingSource.contains("let wasHidden = hidingState == .hidden") ||
                standardSource.contains("let wasHidden = manager.hidingState == .hidden") ||
                alwaysHiddenSource.contains("let wasHidden = manager.hidingState == .hidden"),
            "Icon move flows should not rely on cached hidingState for hidden/expanded checks"
        )

        let alwaysHiddenManagerURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarAlwaysHiddenPinWorkflow.swift")
        let alwaysHiddenManagerSource = try String(contentsOf: alwaysHiddenManagerURL, encoding: .utf8)
        XCTAssertTrue(
            alwaysHiddenManagerSource.contains("let wasHidden = manager.hidingService.state == .hidden"),
            "Always-hidden pin enforcement should use live hidingService.state for restore/hide decisions"
        )
        XCTAssertTrue(
            alwaysHiddenManagerSource.contains(
                "manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()"
            ),
            "Pin reconciliation should require a live AH boundary (right edge) so auto-pin/unpin decisions cannot use stale geometry"
        )
        XCTAssertTrue(
            alwaysHiddenManagerSource.contains("StatusBarController.recoverStartupPositions(") &&
                alwaysHiddenManagerSource.contains("referenceScreen: manager.currentRecoveryReferenceScreen()"),
            "Always-hidden hard recovery should reuse the live status-item screen so fallback repair does not reseed against the wrong display"
        )
        XCTAssertTrue(
            alwaysHiddenManagerSource.contains("manager.clearCachedSeparatorGeometry()") &&
                alwaysHiddenManagerSource.contains("await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)") &&
                alwaysHiddenManagerSource.contains("await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)"),
            "Always-hidden separator repair should clear stale geometry caches and re-warm live separator coordinates before judging the relayout"
        )
    }

    func testHiddenOriginMovePathUsesDirectHideBeforeRestoreFallback() throws {
        let movingURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarStandardIconMoveWorkflow.swift")
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
            source.contains("await manager.hidingService.restoreFromShowAll()"),
            "Restore fallback must remain for expanded-return paths and external-monitor skip-hide policy"
        )
    }

    func testIconPanelForcesAlwaysHiddenWhenNeeded() {
        XCTAssertTrue(
            SearchWindowLayoutPolicy.shouldForceAlwaysHiddenForIconPanel(
                mode: .findIcon,
                isPro: true,
                useSecondMenuBar: false,
                alwaysHiddenEnabled: false
            )
        )
    }

    func testIconPanelDoesNotForceAlwaysHiddenForFreeUsers() {
        XCTAssertFalse(
            SearchWindowLayoutPolicy.shouldForceAlwaysHiddenForIconPanel(
                mode: .findIcon,
                isPro: false,
                useSecondMenuBar: false,
                alwaysHiddenEnabled: false
            )
        )
    }

    func testSecondMenuBarDoesNotForceAlwaysHidden() {
        XCTAssertFalse(
            SearchWindowLayoutPolicy.shouldForceAlwaysHiddenForIconPanel(
                mode: .secondMenuBar,
                isPro: true,
                useSecondMenuBar: true,
                alwaysHiddenEnabled: false
            )
        )
    }

    func testBrowsePanelRestrictedActionsMapBasicUsersToUpsells() {
        XCTAssertEqual(
            BrowsePanelRestrictedAction.upsellFeature(for: .rightClick, isPro: false),
            .rightClickFromPanels
        )
        XCTAssertEqual(
            BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: false),
            .zoneMoves
        )
        XCTAssertEqual(
            BrowsePanelRestrictedAction.upsellFeature(for: .perIconHotkey, isPro: false),
            .perIconHotkeys
        )
        XCTAssertNil(BrowsePanelRestrictedAction.upsellFeature(for: .rightClick, isPro: true))
        XCTAssertNil(BrowsePanelRestrictedAction.upsellFeature(for: .zoneMove, isPro: true))
        XCTAssertNil(BrowsePanelRestrictedAction.upsellFeature(for: .perIconHotkey, isPro: true))
    }

    private func projectQASource() throws -> String {
        try scriptSource(entrypoint: "qa.rb", partialPrefix: "project_qa")
    }
}
