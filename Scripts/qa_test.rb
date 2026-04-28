#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'qa'

class ProjectQATest < Minitest::Test
  def setup
    @qa = ProjectQA.new
  end

  def test_reporter_confirmation_accepts_plain_working_reply
    assert @qa.send(:reporter_confirmation_text?, "It's working. The updates are a bit slow in the UI but that's ok.")
  end

  def test_reporter_confirmation_rejects_negative_reply
    refute @qa.send(:reporter_confirmation_text?, "It's not working. The same problem is still happening.")
  end

  def test_reporter_negative_regression_text_catches_post_closure_repro
    assert @qa.send(
      :reporter_negative_regression_text?,
      'Reopening per your closure criterion: same invisible-icon failure, still reproducing with fresh traces.'
    )
  end

  def test_post_closure_negative_reporter_comments_flags_untrusted_late_repro
    comments = [
      {
        'authorAssociation' => 'NONE',
        'createdAt' => '2026-04-23T13:42:48Z',
        'body' => 'Reopening this: the same issue is still reproducing with fresh logs.'
      }
    ]

    flagged = @qa.send(
      :post_closure_negative_reporter_comments,
      comments,
      '2026-04-16T15:22:40Z'
    )

    assert_equal comments, flagged
  end

  def test_post_closure_negative_reporter_comments_ignores_owner_and_preclosure_comments
    comments = [
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-04-23T13:42:48Z',
        'body' => 'Still reproducing in my local test.'
      },
      {
        'authorAssociation' => 'NONE',
        'createdAt' => '2026-04-15T13:42:48Z',
        'body' => 'Still reproducing before closure.'
      }
    ]

    flagged = @qa.send(
      :post_closure_negative_reporter_comments,
      comments,
      '2026-04-16T15:22:40Z'
    )

    assert_empty flagged
  end

  def test_release_blocking_title_detection_catches_tint_build_and_update_bugs
    assert @qa.send(:regression_like_title?, 'When opening an app, the custom dark tint turns black')
    assert @qa.send(:regression_like_title?, "Can't build from source again")
    assert @qa.send(:regression_like_title?, 'App update direct to latest version')
    assert @qa.send(:regression_like_title?, '[Bug]: Status items invisible on macOS Tahoe')
  end

  def test_release_blocking_issue_detection_uses_labels_not_only_titles
    boringnotch_issue = {
      'title' => 'when running boringnotch as well the sanebar is barely working',
      'labels' => [{ 'name' => 'bug' }]
    }
    arrangement_issue = {
      'title' => 'Arrangement bug is back',
      'labels' => [{ 'name' => 'root:R3 persistence-reset' }]
    }
    question_issue = {
      'title' => 'Question about pricing',
      'labels' => [{ 'name' => 'question' }]
    }

    assert @qa.send(:open_issue_blocks_release?, boringnotch_issue)
    assert @qa.send(:open_issue_blocks_release?, arrangement_issue)
    refute @qa.send(:open_issue_blocks_release?, question_issue)
  end

  def test_release_disposition_allows_triaged_open_issues_to_stay_open
    patched_issue = {
      'title' => 'Status items invisible on macOS Tahoe',
      'labels' => [{ 'name' => 'bug' }, { 'name' => 'release:patched-pending' }]
    }
    compatibility_issue = {
      'title' => 'when running boringnotch as well the sanebar is barely working',
      'labels' => [{ 'name' => 'root:R3 persistence-reset' }, { 'name' => 'release:compat-limited' }]
    }
    needs_evidence_issue = {
      'title' => 'Drag does not function',
      'labels' => ['release:needs-evidence']
    }

    refute @qa.send(:open_issue_blocks_release?, patched_issue)
    refute @qa.send(:open_issue_blocks_release?, compatibility_issue)
    refute @qa.send(:open_issue_blocks_release?, needs_evidence_issue)
  end

  def test_release_blocker_disposition_wins_over_nonblocking_disposition
    issue = {
      'title' => 'Question about a future release',
      'labels' => [
        { 'name' => 'release:patched-pending' },
        { 'name' => 'release:blocker' }
      ]
    }

    assert @qa.send(:open_issue_blocks_release?, issue)
  end

  def test_open_regression_query_requests_labels_for_blocking_policy
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, "'--json', 'number,title,url,labels,createdAt,updatedAt'"
  end

  def test_post_closure_regression_query_requests_labels_for_release_disposition
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, "'--json', 'number,title,closedAt,updatedAt,url,labels'"
  end

  def test_release_disposition_labels_are_source_controlled
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, 'release:blocker'
    assert_includes source, 'release:patched-pending'
    assert_includes source, 'release:compat-limited'
    assert_includes source, 'release:needs-evidence'
  end

  def test_appcast_download_url_check_avoids_filter_map_for_old_ruby
    source = File.read(File.join(__dir__, 'qa.rb'))

    refute_includes source, 'filter_map do |url|'
    assert_includes source, 'urls.each do |url|'
  end

  def test_customer_facing_copy_guardrails_exist
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, 'def check_customer_facing_copy_guardrails'
    assert_includes source, '/works perfectly/i'
    assert_includes source, '/drag apps between/i'
    assert_includes source, '/no data collected/i'
  end

  def test_runtime_smoke_retryable_failure_matches_launch_idle_budget_spike
    assert @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: launch_idle_budget_exceeded peakCpu=15.9% > 15.0%')
  end

  def test_runtime_smoke_retryable_failure_matches_tiny_active_budget_overrun
    assert @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: active_budget_exceeded avgCpu=15.1% > 15.0%')
  end

  def test_runtime_smoke_retryable_failure_matches_empty_zone_snapshot_after_relaunch
    assert @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: No icons returned from list icon zones.')
  end

  def test_runtime_smoke_retryable_failure_uses_resource_watchdog_average_when_failure_line_is_rounded
    output = <<~LOG
      🫀 Resource watchdog: samples=75 avgCpu=15.6% peakCpu=47.4% avgRss=127.0MB peakRss=139.3MB
      ❌ Live zone smoke failed: active_budget_exceeded avgCpu=15.0% > 15.0%
    LOG

    assert @qa.send(:retryable_runtime_smoke_failure?, output)
  end

  def test_runtime_smoke_retryable_failure_rejects_large_active_budget_overrun
    refute @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: active_budget_exceeded avgCpu=15.8% > 15.0%')
  end

  def test_runtime_smoke_retryable_failure_rejects_real_smoke_failures
    refute @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: Required icon(s) missing from list icon zones')
  end

  def test_runtime_smoke_no_candidate_fixture_policy_matches_empty_default_pool
    assert @qa.send(
      :runtime_smoke_no_candidate_fixture_policy?,
      '❌ Live zone smoke failed: No movable candidate icon found (need at least one hidden/visible icon).'
    )
    assert @qa.send(
      :runtime_smoke_no_candidate_fixture_policy?,
      '❌ Live zone smoke failed: No browse activation candidate icon found.'
    )
  end

  def test_runtime_smoke_no_candidate_fixture_policy_rejects_real_smoke_failures
    refute @qa.send(
      :runtime_smoke_no_candidate_fixture_policy?,
      '❌ Live zone smoke failed: Candidate failures: com.apple.menuextra.display: Icon failed to move'
    )
  end

  def test_shared_bundle_runtime_smoke_retryable_failure_matches_identifier_miss_after_first_move
    output = <<~LOG
      ✅ Hidden/Visible move actions ok
      ⚠️ Candidate failed: com.apple.controlcenter (AppleScript failed (move icon to visible "com.apple.menuextra.display"): 146:196: execution error: SaneBar got an error: Icon 'com.apple.menuextra.display' not found. Use 'list icon zones' to see available identifiers. (-2700))
      ❌ Live zone smoke failed: Candidate failures: com.apple.menuextra.display: AppleScript failed (move icon to visible "com.apple.menuextra.display"): 146:196: execution error: SaneBar got an error: Icon 'com.apple.menuextra.display' not found. Use 'list icon zones' to see available identifiers. (-2700)
    LOG

    assert @qa.send(:retryable_shared_bundle_runtime_smoke_failure?, output)
  end

  def test_runtime_smoke_requires_startup_layout_probe
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, "startup_probe_script = File.join(__dir__, 'startup_layout_probe.rb')"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH"
    assert_includes source, "runtime startup layout probe"
  end

  def test_preflight_mode_accepts_saneprocess_env_names
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, "ENV['SANEPROCESS_RELEASE_PREFLIGHT'] == '1'"
    assert_includes source, "ENV['SANEPROCESS_RUN_STABILITY_SUITE'] == '1'"
  end

  def test_runtime_smoke_bootstraps_pro_for_always_hidden_checks
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, 'always_hidden_setup_error = ensure_runtime_smoke_always_hidden_ready!(target)'
    assert_includes source, "target[:no_keychain] = true"
    assert_includes source, "Runtime smoke requires a Pro-enabled target for Always Hidden checks;"
  end

  def test_startup_layout_probe_restores_state_before_marking_success
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "restore_state!\n    @state_restored = true\n\n    write_artifact!(\n      status: 'pass'"
  end

  def test_startup_layout_probe_persists_restore_failures
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "unless @state_restored"
    assert_includes source, 'log("⚠️ Restore failed: #{e.message}")'
    assert_includes source, "persist_log!"
  end

  def test_runtime_smoke_filters_always_hidden_required_ids_when_runtime_is_not_pro
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => false } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      { zone: 'hidden', unique_id: 'com.apple.menuextra.focusmode' },
      { zone: 'alwaysHidden', unique_id: 'com.apple.menuextra.display' }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_required_candidate_ids,
    target,
    required_ids: ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display']
  )

  assert_equal ['com.apple.menuextra.focusmode'], ids
end

  def test_runtime_smoke_keeps_always_hidden_required_ids_when_runtime_is_pro
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => true } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      { zone: 'hidden', unique_id: 'com.apple.menuextra.focusmode' },
      { zone: 'alwaysHidden', unique_id: 'com.apple.menuextra.display' }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_required_candidate_ids,
    target,
    required_ids: ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display']
  )

  assert_equal ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display'], ids
end

  def test_runtime_smoke_list_icon_zones_targets_exact_app_path
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, 'set appTarget to ((POSIX file "#{target[:app_path]}" as alias) as text)'
    assert_includes source, 'using terms from application id "#{expected_bundle_id}"'
    assert_includes source, "tell application appTarget to list icon zones"
  end

  def test_runtime_smoke_tracks_native_apple_and_host_exact_id_lanes
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, 'RUNTIME_NATIVE_APPLE_IDS = %w['
    assert_includes source, 'com.apple.menuextra.siri'
    assert_includes source, 'com.apple.menuextra.spotlight'
    assert_includes source, 'RUNTIME_HOST_EXACT_ID_SENTINEL_IDS = %w['
    assert_includes source, 'at.obdev.littlesnitch.networkmonitor'
    assert_includes source, 'at.obdev.littlesnitch.agent'
    assert_includes source, "lane_name: 'native-apple exact-id'"
    assert_includes source, "lane_name: 'host exact-id'"
  end

  def test_runtime_smoke_status_snapshot_records_all_exact_id_lanes
    source = File.read(File.join(__dir__, 'qa.rb'))

    assert_includes source, 'runtimeSmokeFocusedExactIdSets: ['
    assert_includes source, "lane: 'shared-bundle'"
    assert_includes source, "lane: 'native-apple'"
    assert_includes source, "lane: 'host-exact-id'"
  end

  def test_live_zone_smoke_second_menu_bar_prefers_precise_non_apple_candidates
    source = File.read(File.join(__dir__, 'live_zone_smoke.rb'))

    assert_includes source, "if expected_mode == 'secondMenuBar'"
    assert_includes source, 'precise_non_apple + coarse_non_apple + exact_apple + preferred + fallback'
    assert_includes source, 'BROWSE_ACTIVATION_UNRELIABLE_IDS = %w['
  end

  def test_live_zone_smoke_allows_exact_menumeters_fixture_for_browse_activation
    source = File.read(File.join(__dir__, 'live_zone_smoke.rb'))

    assert_includes source, "item[:bundle].casecmp('com.yujitach.MenuMeters').zero?"
    assert_includes source, 'Exact MenuMeters rows are stable browse fixtures on the Mini in both'
  end

  def test_stability_suite_retryable_failure_matches_generic_xcodebuild_flake
    output = <<~LOG
      2026-03-13 15:16:31.112 xcodebuild[30284:7266800] [MT] IDETestOperationsObserverDebug: 16.440 elapsed -- Testing started completed.
      ** TEST FAILED **
      Testing started
    LOG

    assert @qa.send(:retryable_stability_suite_failure?, output)
  end

  def test_stability_suite_retryable_failure_rejects_real_test_failure_output
    output = <<~LOG
      ** TEST FAILED **
      Testing started
      /tmp/foo.swift:12: error: -[SaneBarTests.RuntimeGuardXCTests testExample] : XCTAssertTrue failed
    LOG

    refute @qa.send(:retryable_stability_suite_failure?, output)
  end
end
