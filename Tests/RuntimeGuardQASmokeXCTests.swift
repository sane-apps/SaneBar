@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardQASmokeXCTests: RuntimeGuardTestCase {
    func testIconPanelOnlyAdvertisesRealZoneDropTargets() throws {
        let iconPanelURL = projectRootURL().appendingPathComponent("UI/SearchWindow/MenuBarSearchView.swift")
        let source = try String(contentsOf: iconPanelURL, encoding: .utf8)
        let toolbarURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelToolbarViews.swift")
        let toolbarSource = try String(contentsOf: toolbarURL, encoding: .utf8)
        let gridURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowseAppGridView.swift")
        let gridSource = try String(contentsOf: gridURL, encoding: .utf8)
        let dragMonitorURL = projectRootURL().appendingPathComponent("UI/SearchWindow/BrowsePanelModeStripDragMonitor.swift")
        let dragMonitorSource = try String(contentsOf: dragMonitorURL, encoding: .utf8)

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
            "Icon panel should retain drag-session state for deciding which existing tabs can accept drops"
        )
        XCTAssertFalse(
            source.contains("Text(\"Move to\")") ||
                toolbarSource.contains("Text(\"Move to\")") ||
                source.contains(".move(edge: .leading)") ||
                toolbarSource.contains(".move(edge: .leading)") ||
                source.contains(".scaleEffect(isTargeted"),
            "Dragging over Hidden, Visible, or Always Hidden must not insert visible labels, slide tabs, or resize target tabs"
        )
        XCTAssertTrue(
            toolbarSource.contains("modeSegment(segmentMode)") &&
                !source.contains("moveDestinationChip(") &&
                !toolbarSource.contains("moveDestinationChip("),
            "Drag destinations should stay in the existing stable tab row with no duplicate destination strip"
        )
        XCTAssertTrue(
            source.contains("@State private var isModeStripDropActive = false"),
            "Icon panel should track drag-session state so the temporary destination rail only appears during drag"
        )
        XCTAssertTrue(
            source.contains("installModeStripDragEndMonitors()") &&
                dragMonitorSource.contains("addLocalMonitorForEvents"),
            "Icon panel drag affordance should clean itself up when the drag session ends"
        )
        XCTAssertTrue(
            source.contains("@State private var activeModeStripSourceZone: AppZone?"),
            "Icon panel should track the dragged icon's actual source zone so it can suppress the current zone in the destination strip"
        )
        XCTAssertTrue(
            source.contains("private func modeAcceptsCurrentDrag(_ mode: Mode) -> Bool") &&
                toolbarSource.contains("let isValidMoveTarget = shouldShowMoveHint && moveHintModes.contains(segmentMode)") &&
                toolbarSource.contains(".dropDestination(for: String.self)") &&
                toolbarSource.contains("if isValidMoveTarget"),
            "Icon panel should centralize whether a tab can accept the current drag and only attach drop handling to valid destination tabs"
        )
        XCTAssertTrue(
            source.contains("return originMode != mode"),
            "Origin zone should not glow as a destination during drag"
        )
        XCTAssertTrue(
            gridSource.contains("noteDragStarted(appZone(app))"),
            "Drag state should capture the source app's real zone at drag start"
        )
        XCTAssertFalse(
            source.contains("dash: showsDropAffordance ? [4, 3] : []"),
            "Filter tabs should no longer use the old dashed-outline destination treatment"
        )
    }

    func testProjectQABlocksProjectYmlXcodeprojVersionDrift() throws {
        let qaURL = projectRootURL().appendingPathComponent("Scripts/qa.rb")
        let source = try String(contentsOf: qaURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("PROJECT_XCODEPROJ") &&
                source.contains("MARKETING_VERSION\\s*=\\s*") &&
                source.contains("CURRENT_PROJECT_VERSION\\s*=\\s*") &&
                source.contains("Run xcodegen generate after bumping project.yml") &&
                source.contains("@errors << \"Version mismatch:"),
            "Project QA should fail, not warn, when project.yml and the generated xcodeproj disagree on version/build"
        )
    }

    func testLiveSmokeCoversBothBrowseModesWithScreenshots() throws {
        let source = try scriptSource(entrypoint: "live_zone_smoke.rb", partialPrefix: "live_zone_smoke")

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
            source.contains("exercise_settings_window_visual_check") &&
                source.contains("capture_settings_screenshot") &&
                source.contains("exercise_appearance_transition_visual_check"),
            "Live smoke should also open settings, capture it, exercise appearance transitions, and close it as part of standard visual QA"
        )
        XCTAssertTrue(
            source.contains("capture_internal_browse_screenshot") &&
                source.contains("capture browse panel snapshot") &&
                source.contains("queue browse panel snapshot") &&
                source.contains("capture settings window snapshot") &&
                source.contains("queue settings window snapshot"),
            "Live smoke should prefer the app's internal browse and settings snapshot commands before falling back to host capture"
        )
        XCTAssertTrue(
            source.contains("capture appearance overlay snapshot") &&
                source.contains("open_full_width_transition_probe_window") &&
                source.contains("FULLSCREEN_TRANSITION_PROBE_APPS") &&
                source.contains("set_fullscreen_probe_window") &&
                source.contains("AXFullScreen") &&
                source.contains("assert_fullscreen_probe_window_state!") &&
                source.contains("assert_appearance_overlay_hidden_after_fullscreen_settle!") &&
                source.contains("assert_appearance_overlay_restored_after_fullscreen_settle!") &&
                source.contains("assert_customer_visible_top_strip_tint!") &&
                source.contains("FULLSCREEN_MATRIX_ARTIFACT_PATH") &&
                source.contains("@require_appearance_transitions"),
            "Live smoke should prove custom appearance survives maximized desktop windows, verifies real AX fullscreen state, hides in fullscreen, captures customer-visible top-strip proof, and restores after fullscreen exit before release"
        )
        XCTAssertTrue(
            source.contains("capture_window_screenshot") &&
                source.contains("WINDOW_SCREENSHOT_TITLES") &&
                !source.contains("screencapture -x"),
            "Live smoke should keep a window-level screenshot fallback for hosts where direct browse-panel snapshots are unavailable, without full-display capture"
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
                source.contains("%w[hidden visible].include?(item[:zone])") &&
                source.contains("compact_precise_non_apple_bundle_candidates") &&
                source.contains("precise_non_apple") &&
                source.contains("exact_apple") &&
                source.contains("coarse_non_apple") &&
                source.contains("prepare_layout_baseline") &&
                source.contains("browse_activation_pool(zones)") &&
                source.contains("com.yujitach.MenuMeters") &&
                source.contains("if expected_mode == 'secondMenuBar'") &&
                source.contains("precise_non_apple + coarse_non_apple + exact_apple + preferred + fallback") &&
                source.contains("precise_non_apple + coarse_non_apple + preferred + fallback") &&
                source.contains("com.apple.menuextra.bluetooth") &&
                source.contains("browse_activation_denied?(item, expected_mode: expected_mode)") &&
                source.contains("item[:bundle].start_with?('com.apple.')") &&
                source.contains("Exact MenuMeters rows are stable browse fixtures on the Mini in both") &&
                source.contains("candidate_order.uniq { |item| item[:unique_id] }.take(3)"),
            "Live smoke should prioritize precise non-Apple browse fixtures, keep second-menu-bar exact Apple coverage behind them, and avoid noisy coarse browse candidates until later fallback"
        )
        XCTAssertTrue(
            source.contains("MOVE_CANDIDATE_BUNDLE_DENYLIST") &&
                source.contains("cc.ffitch.shottr") &&
                source.contains("com.yonilevy.cryptoticker") &&
                source.contains("com.yujitach.MenuMeters") &&
                source.contains("candidates.reject! { |item| move_candidate_denied?(item) }") &&
                source.contains("bundle = item[:bundle].to_s.strip.downcase") &&
                source.contains("MOVE_CANDIDATE_BUNDLE_DENYLIST.any? { |value| value.downcase == bundle }") &&
                source.contains("MOVE_CANDIDATE_PREFERRED_BUNDLE_PREFIXES") &&
                source.contains("com.mrsane.") &&
                source.contains("return prioritize_move_candidates(ordered) if @required_candidate_ids.empty?") &&
                source.contains("preferred_move_candidate_rank(item[:bundle])") &&
                source.contains("if @require_always_hidden") &&
                source.contains("{ 'alwaysHidden' => 0, 'hidden' => 1, 'visible' => 2 }"),
            "Live smoke should prefer stable first-party move fixtures and exclude known noisy edge-case bundles when always-hidden moves are required"
        )
        XCTAssertTrue(
            source.contains("check_always_hidden_preconditions(snapshot)") &&
                source.contains("Always Hidden smoke requires a Pro-enabled target (licenseIsPro=false)."),
            "Live smoke should fail clearly when an Always Hidden smoke is pointed at a free-mode runtime target"
        )
        XCTAssertTrue(
            source.contains("!non_idempotent_app_script?(statement)") &&
                source.contains("statement.start_with?('activate browse icon ')"),
            "Live smoke should not blindly retry side-effectful browse activation AppleScript commands after a timeout"
        )
        XCTAssertTrue(
            source.contains("APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS = 25") &&
                source.contains("APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS = 20") &&
                source.contains("return APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS if activation_app_script?(statement)") &&
                source.contains("statement == 'browse panel diagnostics'") &&
                source.contains("statement == 'activation diagnostics'"),
            "Live smoke should give browse activation commands a longer timeout and treat diagnostics reads as heavy read-only AppleScript"
        )
        XCTAssertTrue(
            source.contains("Salvaging timed-out move command via zone verification") &&
                source.contains("timed_out_move_command?"),
            "Live smoke should verify the final zone before failing a move command whose AppleScript reply timed out"
        )
        XCTAssertTrue(
            source.contains("DEFAULT_POST_MOVE_ZONE_STABILITY_SECONDS") &&
                source.contains("@post_move_zone_stability_seconds") &&
                source.contains("assert_zone_stays_stable_after_move(icon_unique_id, candidate, expected_zone)") &&
                source.contains("Post-settle move verification drifted") &&
                source.contains("Post-settle zone stability ok"),
            "Live smoke should catch customer-visible move drift after delayed pin reconciliation, not only immediate move success"
        )
        XCTAssertTrue(
            source.contains("exercise_hidden_always_hidden_round_trip(candidate)") &&
                source.contains("def exercise_hidden_always_hidden_round_trip(candidate)") &&
                source.contains("move_and_verify('move icon to hidden', candidate, 'hidden')") &&
                source.contains("move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')") &&
                source.contains("Hidden/Always Hidden round-trip ok"),
            "Live smoke should gate the exact Hidden to Always Hidden to Hidden customer workflow, not infer it from visible-only moves"
        )
        XCTAssertTrue(
            source.contains("current_physical_footprint_mb") &&
                source.contains("phys_footprint:") &&
                source.contains("accepting RSS-only breach because physical footprint settled"),
            "Live smoke should corroborate RSS-only idle-memory failures with physical footprint before failing the host"
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
            source.contains("label: 'launch'") &&
                source.contains("reset_resource_watchdog_window!") &&
                source.contains("begin\n      assert_active_average_budget!\n    ensure\n      restore_zone(post_budget_restore_candidate) if post_budget_restore_candidate\n    end"),
            "Live smoke should reset the active resource window after launch-idle validation so the interaction budget is not polluted by startup settling"
        )
        XCTAssertTrue(
            source.contains("📉 Idle budget ") &&
                source.contains("peakCpu=") &&
                source.contains("peakRss=") &&
                source.contains("🫀 Resource watchdog: samples=") &&
                source.contains("avgCpu=") &&
                source.contains("avgRss="),
            "Live smoke should print both idle-budget and whole-pass performance summaries so the numbers are reviewable in smoke logs"
        )
        XCTAssertTrue(
            source.contains("'/usr/bin/sample'") &&
                source.contains("ps',") &&
                source.contains("'pid=,%cpu=,rss=,etime=,command='"),
            "Live smoke should monitor the staged process with native macOS tooling and sample it when thresholds are breached"
        )
        XCTAssertTrue(
            source.contains("match = out.lines") &&
                source.contains("@app_pid = pid.to_i if pid.to_i.positive?"),
            "Live smoke should refresh the tracked app PID when the same staged app is still visible after a transient process handoff"
        )
        XCTAssertTrue(
            source.contains("if @app_path") &&
                source.contains("set appTarget to ((POSIX file") &&
                source.contains("using terms from") &&
                source.contains("tell application appTarget to"),
            "Live smoke AppleScript should target the exact staged app path when SANEBAR_SMOKE_APP_PATH is provided"
        )
    }

}
