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

  def test_stale_open_regression_after_release_when_quiet_for_five_days
    release = { 'tagName' => 'v2.1.26', 'publishedAt' => '2026-03-01T12:00:00Z' }
    issue = {
      'number' => 94,
      'createdAt' => '2026-02-28T17:44:05Z',
      'updatedAt' => '2026-03-01T11:59:59Z'
    }

    assert @qa.send(:stale_open_regression_after_release?, issue, release, now: Time.parse('2026-03-06T12:00:01Z'))
  end

  def test_stale_open_regression_waits_until_five_day_mark
    release = { 'tagName' => 'v2.1.26', 'publishedAt' => '2026-03-01T12:00:00Z' }
    issue = {
      'number' => 94,
      'createdAt' => '2026-02-28T17:44:05Z',
      'updatedAt' => '2026-03-01T11:59:59Z'
    }

    refute @qa.send(:stale_open_regression_after_release?, issue, release, now: Time.parse('2026-03-05T23:59:59Z'))
  end

  def test_stale_open_regression_rejects_issue_updated_after_release
    release = { 'tagName' => 'v2.1.26', 'publishedAt' => '2026-03-01T12:00:00Z' }
    issue = {
      'number' => 94,
      'createdAt' => '2026-02-28T17:44:05Z',
      'updatedAt' => '2026-03-02T09:00:00Z'
    }

    refute @qa.send(:stale_open_regression_after_release?, issue, release, now: Time.parse('2026-03-07T12:00:00Z'))
  end

  def test_release_blocking_title_detection_catches_tint_build_and_update_bugs
    assert @qa.send(:regression_like_title?, 'When opening an app, the custom dark tint turns black')
    assert @qa.send(:regression_like_title?, "Can't build from source again")
    assert @qa.send(:regression_like_title?, 'App update direct to latest version')
  end

  def test_appcast_download_url_check_avoids_filter_map_for_old_ruby
    source = File.read(File.join(__dir__, 'qa.rb'))

    refute_includes source, 'filter_map do |url|'
    assert_includes source, 'urls.each do |url|'
  end

  def test_runtime_smoke_retryable_failure_matches_launch_idle_budget_spike
    assert @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: launch_idle_budget_exceeded peakCpu=15.9% > 15.0%')
  end

  def test_runtime_smoke_retryable_failure_matches_tiny_active_budget_overrun
    assert @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: active_budget_exceeded avgCpu=15.1% > 15.0%')
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
  end

  def test_runtime_smoke_no_candidate_fixture_policy_rejects_real_smoke_failures
    refute @qa.send(
      :runtime_smoke_no_candidate_fixture_policy?,
      '❌ Live zone smoke failed: Candidate failures: com.apple.menuextra.display: Icon failed to move'
    )
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
