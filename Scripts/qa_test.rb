#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative 'qa'
require_relative 'live_zone_smoke'

class ProjectQATest < Minitest::Test
  def setup
    @qa = ProjectQA.new
  end
  def qa_source
    @qa_source ||= source_bundle('qa.rb', 'project_qa_*.rb')
  end
  def live_zone_smoke_source
    @live_zone_smoke_source ||= source_bundle('live_zone_smoke.rb', 'live_zone_smoke_*.rb')
  end
  def source_bundle(entrypoint, partial_pattern)
    paths = [
      File.join(__dir__, entrypoint),
      *Dir.glob(File.join(__dir__, 'lib', partial_pattern)).sort
    ]
    paths.map { |path| File.read(path) }.join("\n")
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
  def test_release_runtime_smoke_requires_tint_pixel_evidence_by_default
    source = qa_source
    fullscreen_source = File.read(File.join(ProjectQA::PROJECT_ROOT, 'scripts', 'lib', 'live_zone_smoke_screenshots_fullscreen.rb'))
    assert_includes source, "ENV.fetch('SANEBAR_RELEASE_SMOKE_SCREENSHOTS', '1')"
    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TINT_PIXELS' => capture_runtime_smoke_screenshots ? '1' : '0'"
    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_VISIBLE_APPEARANCE_PIXELS' => capture_runtime_smoke_screenshots ? '1' : '0'"
    assert_includes source, "missing << 'fullscreen-overlay-restore' if fullscreen_restore_screenshots.empty?"
    assert_includes source, "runtime_fullscreen_matrix_artifact_passed?"
    assert_includes source, "'app activation keeps dark custom tint visible'"
    assert_includes source, "'useLiquidGlass' => true"
    assert_includes source, "set_runtime_smoke_reduce_transparency!(true)"
    assert_includes fullscreen_source, 'fullscreen_probe_window_states'
    assert_includes fullscreen_source, 'repeat with candidateWindow in windows'
    assert_includes fullscreen_source, 'set value of attribute "AXFullScreen" of candidateWindow to false'
    assert_includes fullscreen_source, "last_states.any? { |state| state.casecmp('true').zero? }"
    assert_includes fullscreen_source, 'out.scan(/true|false|no-window/i).map(&:downcase)'
    refute_includes source, "ENV['SANEBAR_RELEASE_SMOKE_SCREENSHOTS'] == '1'"
    refute_includes source, "'useLiquidGlass' => false"
  end
  def test_live_zone_smoke_checks_activation_tint_stability
    source = live_zone_smoke_source
    assert_includes source, 'exercise_app_activation_tint_stability_check'
    assert_includes source, 'activation-immediate'
    assert_includes source, 'activation-settled'
    assert_includes source, 'app activation keeps dark custom tint visible'
  end
  def test_release_hygiene_guardrails_cover_changelog_privacy_and_local_artifacts
    source = qa_source
    assert_includes source, 'check_release_hygiene_guardrails'
    assert_includes source, 'changelog_duplicate_heading_failures'
    assert_includes source, 'Duplicate CHANGELOG version heading'
    assert_includes source, 'privacy_manifest_failures'
    assert_includes source, 'settings_docs_parity_failures'
    assert_includes source, 'README settings table missing tab'
    assert_includes source, 'NSPrivacyAccessedAPICategoryUserDefaults'
    assert_includes source, 'CA92.1'
    assert_includes source, 'NSPrivacyAccessedAPICategoryFileTimestamp'
    assert_includes source, 'attributesOfItem'
    assert_includes source, 'C617.1'
    assert_includes source, 'large_local_artifact_warnings'
  end
  def test_release_hygiene_runs_shared_saneui_guard
    source = qa_source
    assert_includes source, 'check_saneui_guardrails'
    assert_includes source, "'saneui_guard', PROJECT_ROOT"
    assert_includes source, 'SaneUI guard warnings'
    assert_includes source, 'shared settings UI drift'
  end
  def test_privacy_manifest_declares_required_reasons
    manifest = File.read(File.join(ProjectQA::PROJECT_ROOT, 'SaneBar', 'PrivacyInfo.xcprivacy'))
    assert_includes manifest, 'NSPrivacyAccessedAPICategoryUserDefaults'
    assert_includes manifest, 'CA92.1'
    assert_includes manifest, 'NSPrivacyAccessedAPICategoryFileTimestamp'
    assert_includes manifest, 'C617.1'
    assert_includes manifest, '3B52.1'
  end

  def test_live_zone_smoke_rejects_black_appearance_snapshot_pixels
    Tempfile.create(['black-tint', '.bmp']) do |file|
      write_test_bmp(file.path, Array.new(25) { [0, 0, 0, 96] })
      stats = LiveZoneSmoke.appearance_tint_pixel_stats(file.path)
      refute LiveZoneSmoke.orange_tint_pixel_stats?(stats)
    end
  end

  def test_live_zone_smoke_accepts_orange_appearance_snapshot_pixels
    Tempfile.create(['orange-tint', '.bmp']) do |file|
      write_test_bmp(file.path, Array.new(25) { [255, 85, 0, 96] })
      stats = LiveZoneSmoke.appearance_tint_pixel_stats(file.path)
      assert LiveZoneSmoke.orange_tint_pixel_stats?(stats)
    end
  end

  def write_test_bmp(path, rgba_pixels)
    width = Math.sqrt(rgba_pixels.length).to_i
    height = width
    raise "Test BMP requires square pixels" unless width * height == rgba_pixels.length
    bits_per_pixel = 32
    pixel_offset = 54
    row_stride = width * 4
    image_size = row_stride * height
    file_size = pixel_offset + image_size
    header = +'BM'
    header << [file_size, 0, 0, pixel_offset].pack('VvvV')
    header << [40, width, height, 1, bits_per_pixel, 0, image_size, 2835, 2835, 0, 0].pack('VllvvVVllVV')
    # Positive-height BMP stores rows bottom-up.
    rows = rgba_pixels.each_slice(width).to_a.reverse
    pixel_data = rows.flatten(1).map { |r, g, b, a| [b, g, r, a].pack('C4') }.join
    File.binwrite(path, header + pixel_data)
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

  def test_patched_pending_with_fresh_negative_blocks_without_current_release_evidence
    issue = patched_pending_issue_with_fresh_negative
    @qa.define_singleton_method(:open_regression_release_evidence_text) { '' }

    assert @qa.send(:open_issue_blocks_release?, issue)
  end

  def test_patched_pending_with_fresh_negative_allows_current_verified_release_evidence
    issue = patched_pending_issue_with_fresh_negative
    today = Date.today.strftime('%Y-%m-%d')
    @qa.define_singleton_method(:open_regression_release_evidence_text) do
      <<~MARKDOWN
        ## SaneBar issue #147 release evidence | Updated: #{today}
        - Trigger: GitHub #147 latest evidence reported a helper-owned item such as Lungo moving from Hidden to Visible after wake.
        - #147 local root cause: wake/display replay could prove generic anchors while missing helper-specific Hidden-zone drift.
        - Current patch addresses the pending release by requiring helper-specific Hidden-zone proof before release.
        - Current proof: Mini ./scripts/SaneMaster.rb verify --timeout 900 passed and the wake layout probe passed with dynamic helper required IDs.
      MARKDOWN
    end

    refute @qa.send(:open_issue_blocks_release?, issue)
  end

  def test_patched_pending_with_fresh_negative_requires_recent_release_evidence
    issue = patched_pending_issue_with_fresh_negative
    stale_date = (Date.today - 30).strftime('%Y-%m-%d')
    @qa.define_singleton_method(:open_regression_release_evidence_text) do
      <<~MARKDOWN
        ## SaneBar issue #147 release evidence | Updated: #{stale_date}
        - #147 local root cause: old recovery hypothesis.
        - Current patch addresses the pending release.
        - Current proof: Mini verify passed.
      MARKDOWN
    end

    assert @qa.send(:open_issue_blocks_release?, issue)
  end

  def patched_pending_issue_with_fresh_negative
    {
      'number' => 147,
      'title' => 'Icons jumping from shown to hidden',
      'labels' => [{ 'name' => 'bug' }, { 'name' => 'release:patched-pending' }],
      'comments' => [
        {
          'authorAssociation' => 'OWNER',
          'createdAt' => '2026-05-20T10:00:00Z',
          'body' => 'Fixed in the next release build.'
        },
        {
          'authorAssociation' => 'NONE',
          'createdAt' => '2026-05-20T12:00:00Z',
          'body' => 'The same issue is still reproducing with fresh logs.'
        }
      ]
    }
  end

  def test_open_regression_query_requests_labels_for_blocking_policy
    source = qa_source

    assert_includes source, "'--json', 'number,title,url,labels,createdAt,updatedAt,comments'"
  end

  def test_post_closure_regression_query_requests_labels_for_release_disposition
    source = qa_source

    assert_includes source, "'--json', 'number,title,closedAt,updatedAt,url,labels'"
  end

  def test_release_disposition_labels_are_source_controlled
    source = qa_source

    assert_includes source, 'release:blocker'
    assert_includes source, 'release:patched-pending'
    assert_includes source, 'release:compat-limited'
    assert_includes source, 'release:needs-evidence'
  end

  def test_appcast_download_url_check_avoids_filter_map_for_old_ruby
    source = qa_source

    refute_includes source, 'filter_map do |url|'
    assert_includes source, 'urls.each_with_index do |url, index|'
  end

  def test_customer_facing_copy_guardrails_exist
    source = qa_source

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

  def test_live_zone_smoke_waits_for_slow_release_zone_api_warmup
    source = live_zone_smoke_source
    timeout = source[/ZONE_API_READY_TIMEOUT_SECONDS = (\d+)/, 1].to_i

    assert_operator timeout, :>=, 25
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

  def test_runtime_smoke_requires_startup_and_wake_layout_probes
    source = qa_source

    assert_includes source, "startup_probe_script = File.join(SCRIPTS_DIR, 'startup_layout_probe.rb')"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH"
    assert_includes source, 'startup_probe_env.merge!(runtime_probe_no_keychain_env(target))'
    assert_includes source, "runtime startup layout probe"
    assert_includes source, "wake_probe_script = File.join(SCRIPTS_DIR, 'wake_layout_probe.rb')"
    assert_includes source, "'SANEBAR_WAKE_PROBE_LOG_PATH' => RUNTIME_WAKE_PROBE_LOG_PATH"
    assert_includes source, "'SANEBAR_WAKE_PROBE_ARTIFACT_PATH' => RUNTIME_WAKE_PROBE_ARTIFACT_PATH"
    assert_includes source, "dynamic_helper_ids = ensure_runtime_dynamic_helper_wake_fixture!(target)"
    assert_includes source, "'SANEBAR_WAKE_PROBE_DYNAMIC_HELPER_IDS' => dynamic_helper_ids.join(',')"
    assert_includes source, "visible_dynamic_helper_ids = ensure_runtime_visible_dynamic_helper_wake_fixture!(target)"
    assert_includes source, "'SANEBAR_WAKE_PROBE_REQUIRED_VISIBLE_IDS' => visible_dynamic_helper_ids.join(',')"
    assert_includes source, 'wake_probe_env.merge!(runtime_probe_no_keychain_env(target))'
    assert_includes source, "'SANEBAR_PROBE_FORCE_NO_KEYCHAIN' => '1'"
    assert_includes source, 'Lungo-style Hidden-to-Visible wake drift is release-blocking'
    assert_includes source, 'SwiftBar-style Visible-to-Hidden wake drift is release-blocking'
    assert_includes source, "runtime wake layout probe"
  end

  def test_runtime_smoke_builds_lungo_style_dynamic_helper_fixture
    source = qa_source

    assert_includes source, "RUNTIME_DYNAMIC_HELPER_FIXTURE_ID = 'com.sindresorhus.Lungo-setapp'"
    assert_includes source, "RUNTIME_DYNAMIC_HELPER_FIXTURE_IDS = %w[\n    com.sindresorhus.Lungo-setapp::statusItem:0"
    assert_includes source, 'prelaunch_runtime_dynamic_helper_fixture!'
    assert_includes source, 'prelaunch_skipped=external-helper-running'
    assert_includes source, 'runtime_dynamic_helper_external_process_detail'
    assert_includes source, 'def ensure_runtime_dynamic_helper_wake_fixture!(target)'
    assert_includes source, 'NSImage(systemSymbolName: name'
    assert_includes source, "symbol_name: 'moon.fill'"
    assert_includes source, '<key>CFBundleIconFile</key>'
    assert_includes source, 'NSApp.applicationIconImage = fixtureImage("moon.fill")'
    assert_includes source, 'statusItem.button?.image = fixtureImage("moon.fill")'
    assert_includes source, 'statusItem.button?.title = "Lungo"'
    assert_includes source, 'cleanup_runtime_dynamic_helper_fixture!'
  end

  def test_runtime_smoke_builds_swiftbar_style_visible_dynamic_helper_fixture
    source = qa_source

    assert_includes source, "RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_ID = 'com.ameba.SwiftBar'"
    assert_includes source, "RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_IDS = %w[\n    com.ameba.SwiftBar::statusItem:0"
    assert_includes source, 'prelaunch_runtime_visible_dynamic_helper_fixture!'
    assert_includes source, 'def ensure_runtime_visible_dynamic_helper_wake_fixture!(target)'
    assert_includes source, "symbol_name: 'timer'"
    assert_includes source, 'NSApp.applicationIconImage = fixtureImage("timer")'
    assert_includes source, 'statusItem.button?.image = fixtureImage("timer")'
    assert_includes source, 'item?.button?.image = fixtureImage(tickCount.isMultiple(of: 2) ? "timer" : "timer.circle.fill")'
    assert_includes source, 'statusItem.button?.title = "11"'
    assert_includes source, 'SwiftBar dynamic counter'
  end

  def test_runtime_smoke_shared_and_host_fixtures_render_template_images
    source = qa_source

    assert_includes source, 'def write_runtime_fixture_bundle_icon!'
    assert_includes source, '/usr/bin/iconutil'
    assert_includes source, "symbol_name: 'target'"
    assert_includes source, "symbol_name: 'square.grid.2x2.fill'"
    assert_includes source, 'statusItem.button?.image = fixtureImage("target")'
    assert_includes source, 'NSApp.applicationIconImage = fixtureImage("target")'
    assert_includes source, 'NSApp.applicationIconImage = fixtureImage(for: "SBF-A")'
    assert_includes source, 'case "SBF-A": symbolName = "circle.grid.2x2.fill"'
    assert_includes source, 'case "SBF-B": symbolName = "square.grid.2x2.fill"'
    assert_includes source, 'default: symbolName = "diamond.grid.3x3.fill"'
    assert_includes source, 'item.button?.image = fixtureImage(for: title)'
    assert_includes source, 'image?.isTemplate = true'
  end

  def test_preflight_mode_accepts_saneprocess_env_names
    source = qa_source

    assert_includes source, "ENV['SANEPROCESS_RELEASE_PREFLIGHT'] == '1'"
    assert_includes source, "ENV['SANEPROCESS_RUN_STABILITY_SUITE'] == '1'"
  end

  def test_runtime_smoke_bootstraps_pro_for_always_hidden_checks
    source = qa_source

    assert_includes source, 'runtime_smoke_host_allowed?'
    assert_includes source, 'SANE_APPROVE_LOCAL_UI_ON_AIR'
    assert_includes source, 'ensure_runtime_smoke_representative_zones_ready!(target)'
    assert_includes source, 'representative_zone_settle_error = ensure_runtime_smoke_representative_zones_ready!(target)'
    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN' => '1'"
    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_ALL_ZONES' => '1'"
    assert_includes source, "'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '0'"
    assert_includes source, 'always_hidden_setup_error = ensure_runtime_smoke_always_hidden_ready!(target)'
    assert_includes source, "target[:no_keychain] = true"
    assert_includes source, "Runtime smoke requires a Pro-enabled target for Always Hidden checks;"
  end

  def test_runtime_smoke_seeds_missing_representative_always_hidden_zone
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.one', unique_id: 'com.example.hidden.one::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.two', unique_id: 'com.example.hidden.two::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.three', unique_id: 'com.example.hidden.three::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.four', unique_id: 'com.example.hidden.four::statusItem:0' }
    ]
    calls = []
    status = Object.new
    status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
    @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, unique_id|
      calls << [command, unique_id]
      zones.find { |item| item[:unique_id] == unique_id }[:zone] = 'alwaysHidden'
      ["true\n", status]
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:ensure_runtime_smoke_representative_zones_ready!, { app_path: '/Applications/SaneBar.app' })

    assert_nil error
    assert_equal [
      ['move icon to always hidden', 'com.example.hidden.one::statusItem:0'],
      ['move icon to always hidden', 'com.example.hidden.two::statusItem:0'],
      ['move icon to always hidden', 'com.example.hidden.three::statusItem:0']
    ], calls
  end

  def test_runtime_smoke_retries_representative_zone_seeding_after_transient_move_failure
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.one', unique_id: 'com.example.hidden.one::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.two', unique_id: 'com.example.hidden.two::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.three', unique_id: 'com.example.hidden.three::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.four', unique_id: 'com.example.hidden.four::statusItem:0' }
    ]
    calls = []
    fail_status = Object.new
    fail_status.define_singleton_method(:success?) { false }
    pass_status = Object.new
    pass_status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
    @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, unique_id|
      calls << [command, unique_id]
      if calls.length == 1
        ["transient launch timing failure\n", fail_status]
      else
        zones.find { |item| item[:unique_id] == unique_id }[:zone] = 'alwaysHidden'
        ["true\n", pass_status]
      end
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:ensure_runtime_smoke_representative_zones_ready!, { app_path: '/Applications/SaneBar.app' })

    assert_nil error
    assert_equal 4, calls.length
    assert_equal ['move icon to always hidden', 'com.example.hidden.one::statusItem:0'], calls.first
    assert_equal ['move icon to always hidden', 'com.example.hidden.two::statusItem:0'], calls[1]
    assert_equal ['move icon to always hidden', 'com.example.hidden.three::statusItem:0'], calls.last
  end

  def test_runtime_smoke_retries_representative_zone_seeding_when_success_does_not_change_zone
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.one', unique_id: 'com.example.hidden.one::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.two', unique_id: 'com.example.hidden.two::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.three', unique_id: 'com.example.hidden.three::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.four', unique_id: 'com.example.hidden.four::statusItem:0' }
    ]
    calls = []
    status = Object.new
    status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
    @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, unique_id|
      calls << [command, unique_id]
      zones.find { |item| item[:unique_id] == unique_id }[:zone] = 'alwaysHidden' unless calls.length == 1
      ["true\n", status]
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:ensure_runtime_smoke_representative_zones_ready!, { app_path: '/Applications/SaneBar.app' })

    assert_nil error
    assert_equal [
      ['move icon to always hidden', 'com.example.hidden.one::statusItem:0'],
      ['move icon to always hidden', 'com.example.hidden.two::statusItem:0'],
      ['move icon to always hidden', 'com.example.hidden.one::statusItem:0'],
      ['move icon to always hidden', 'com.example.hidden.three::statusItem:0']
    ], calls
  end

  def test_runtime_smoke_seeds_preferred_shared_fixture_into_always_hidden_before_filling_minimum
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::statusItem:1' },
      { zone: 'hidden', movable: true, bundle: 'com.knollsoft.Rectangle', unique_id: 'com.knollsoft.Rectangle::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.another', unique_id: 'com.example.another::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.example.another2', unique_id: 'com.example.another2::statusItem:0' }
    ]
    calls = []
    status = Object.new
    status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
    @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, unique_id|
      calls << [command, unique_id]
      zones.find { |item| item[:unique_id] == unique_id }[:zone] = 'alwaysHidden'
      ["true\n", status]
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:ensure_runtime_smoke_representative_zones_ready!, { app_path: '/Applications/SaneBar.app' })

    assert_nil error
    assert_equal [
      ['move icon to always hidden', 'com.sanebar.sharedfixture::statusItem:1'],
      ['move icon to always hidden', 'com.knollsoft.Rectangle::statusItem:0'],
      ['move icon to always hidden', 'com.example.another::statusItem:0']
    ], calls
  end

  def test_runtime_smoke_generic_seeding_uses_deterministic_shared_fixture_before_system_donors
    apple_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.apple.weather.menu')
    shared_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.sanebar.sharedfixture')

    assert_operator shared_rank, :<, apple_rank
  end

  def test_runtime_smoke_rebalances_hidden_zone_from_always_hidden_surplus
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::statusItem:0' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.knollsoft.Rectangle', unique_id: 'com.knollsoft.Rectangle::statusItem:0' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.apple.weather.menu', unique_id: 'com.apple.weather.menu::statusItem:0' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.another', unique_id: 'com.example.another::statusItem:0' }
    ]
    calls = []
    status = Object.new
    status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
    @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, unique_id|
      calls << [command, unique_id]
      zones.find { |item| item[:unique_id] == unique_id }[:zone] = command.end_with?('always hidden') ? 'alwaysHidden' : 'hidden'
      ["true\n", status]
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:ensure_runtime_smoke_representative_zones_ready!, { app_path: '/Applications/SaneBar.app' })

    assert_nil error
    assert_equal [
      ['move icon to hidden', 'com.knollsoft.Rectangle::statusItem:0']
    ], calls
  end

def test_runtime_smoke_cleanup_includes_host_exact_id_fixture
  preflight_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_preflight.rb'))
  fixture_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_fixtures.rb'))

  assert_includes fixture_source, "def cleanup_runtime_host_exact_id_fixture!"
  assert_includes fixture_source, "killall', 'SaneBarHostExactIDFixture'"
  assert_includes fixture_source, 'for title in ["SBF-A", "SBF-B", "SBF-C"]'
  assert_includes preflight_source, "cleanup_runtime_host_exact_id_fixture!"
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

  def test_startup_layout_probe_quit_cleanup_scopes_to_staged_app_path
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "def app_pids"
    assert_includes source, "process_path = File.join(@app_path, 'Contents', 'MacOS', @app_name)"
    assert_includes source, "ps', '-axo', 'pid=,command='"
    refute_includes source, "pgrep', '-x', @app_name.to_s"
    assert_includes source, 'Force terminating lingering #{@app_name} test process pid=#{pid}'
  end

  def test_startup_layout_probe_requires_visible_lane_after_recovery
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'assert_restored_backup_pair!'
    assert_includes source, 'visible lane too narrow after recovery'
    assert_includes source, 'preferred_visible_lane_gap'
  end

  def test_startup_layout_probe_waits_through_bounded_status_item_attachment_recovery
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'SNAPSHOT_SETTLE_TIMEOUT_SECONDS'
    assert_includes source, 'wait_for_healthy_snapshot(label:'
    assert_includes source, 'snapshot_health_error(last_snapshot, label: label)'
    assert_includes source, 'startupItemsValid=#{last_snapshot[\'startupItemsValid\']}'
    assert_includes source, 'possibleSystemMenuBarSuppression'
    assert_includes source, 'SANEBAR_STARTUP_PROBE_QUIT_TIMEOUT_SECONDS'
    assert_includes source, 'Startup probe requires cliclick on the Mini to prove passive recovery does not move the cursor'
    assert_includes source, 'Passive startup recovery moved cursor'
    assert_includes source, "completed_scenario: 'passive startup recovery did not physically move the cursor'"
  end

  def test_wake_layout_probe_waits_for_launch_ready_status_items_before_actions
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, "wait_for_healthy_snapshot(label: 'hidden launch baseline')"
    assert_includes source, "wait_for_healthy_snapshot(label: 'expanded launch baseline')"
    assert_includes source, "wait_for_healthy_snapshot(label: 'hide-all-other seeded launch baseline')"
    assert_includes source, "(!snapshot.key?('startupItemsValid') || truthy?(snapshot['startupItemsValid']))"
    assert_includes source, "!truthy?(snapshot['possibleSystemMenuBarSuppression'])"
    assert_includes source, 'SANEBAR_WAKE_PROBE_QUIT_TIMEOUT_SECONDS'
    assert_includes source, 'Passive wake recovery moved cursor'
    assert_includes source, "completed_scenario: 'passive wake recovery did not physically move the cursor'"
  end

  def test_wake_layout_probe_quit_cleanup_scopes_to_staged_app_path
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, "def app_pids"
    assert_includes source, "process_path = File.join(@app_path, 'Contents', 'MacOS', @app_name)"
    assert_includes source, "ps', '-axo', 'pid=,command='"
    refute_includes source, "pgrep', '-x', @app_name.to_s"
    assert_includes source, 'Force terminating lingering #{@app_name} test process pid=#{pid}'
  end

  def test_runtime_smoke_filters_always_hidden_required_ids_when_runtime_is_not_pro
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => false } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      { zone: 'hidden', movable: true, unique_id: 'com.apple.menuextra.focusmode' },
      { zone: 'alwaysHidden', movable: true, unique_id: 'com.apple.menuextra.display' }
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
      { zone: 'hidden', movable: true, unique_id: 'com.apple.menuextra.focusmode' },
      { zone: 'alwaysHidden', movable: true, unique_id: 'com.apple.menuextra.display' }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_required_candidate_ids,
    target,
    required_ids: ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display']
  )

  assert_equal ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display'], ids
end

  def test_shared_bundle_runtime_smoke_requires_at_least_two_same_bundle_items
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => true } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'visible',
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.focusmode'
      },
      {
        zone: 'visible',
        bundle: 'com.apple.Spotlight',
        unique_id: 'com.apple.menuextra.spotlight'
      }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_shared_bundle_candidate_ids,
    target,
    required_ids: ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display']
  )

  assert_empty ids
end

def test_shared_bundle_runtime_smoke_uses_only_the_present_same_bundle_group
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => true } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.focusmode'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display'
      },
      {
        zone: 'visible',
        bundle: 'com.apple.Spotlight',
        unique_id: 'com.apple.menuextra.spotlight'
      }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_shared_bundle_candidate_ids,
    target,
    required_ids: [
      'com.apple.menuextra.focusmode',
      'com.apple.menuextra.display',
      'com.apple.menuextra.spotlight'
    ]
  )

  assert_equal ['com.apple.menuextra.focusmode', 'com.apple.menuextra.display'], ids
end

def test_shared_bundle_runtime_smoke_rejects_nonmovable_control_center_clock_cluster
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => true } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.focusmode'
      },
      {
        zone: 'visible',
        movable: false,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.controlcenter'
      },
      {
        zone: 'visible',
        movable: false,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.clock'
      }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_shared_bundle_candidate_ids,
    target,
    required_ids: [
      'com.apple.menuextra.wifi',
      'com.apple.menuextra.battery',
      'com.apple.menuextra.focusmode',
      'com.apple.menuextra.display',
      'com.apple.menuextra.controlcenter',
      'com.apple.menuextra.clock'
    ]
  )

  assert_empty ids
end

def test_required_runtime_smoke_rejects_nonmovable_dynamic_helper_fixture
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => true } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'visible',
        movable: false,
        bundle: 'com.sindresorhus.Lungo-setapp',
        unique_id: 'com.sindresorhus.Lungo-setapp::statusItem:0'
      }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_required_candidate_ids,
    target,
    required_ids: ['com.sindresorhus.Lungo-setapp::statusItem:0']
  )

  assert_empty ids
end

def test_representative_runtime_smoke_excludes_volatile_swiftbar_fixture_from_move_candidates
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.ameba.SwiftBar',
        unique_id: 'com.ameba.SwiftBar::statusItem:0',
        name: 'SwiftBar'
      }
    ]
  end

  candidates = @qa.send(:runtime_smoke_representative_zone_candidates, target)

  assert_empty candidates
end

def test_shared_bundle_runtime_smoke_accepts_deterministic_fixture_cluster
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_smoke_layout_snapshot) { |_target| { 'licenseIsPro' => true } }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: 'com.sanebar.sharedfixture::statusItem:1'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: 'com.sanebar.sharedfixture::statusItem:0'
      }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_shared_bundle_candidate_ids,
    target,
    required_ids: [
      'com.sanebar.sharedfixture::statusItem:0',
      'com.sanebar.sharedfixture::statusItem:1'
    ]
  )

  assert_equal [
    'com.sanebar.sharedfixture::statusItem:0',
    'com.sanebar.sharedfixture::statusItem:1'
  ], ids
end

  def test_runtime_smoke_list_icon_zones_targets_exact_app_path
    source = qa_source

    assert_includes source, 'set appTarget to ((POSIX file "#{target[:app_path]}" as alias) as text)'
    assert_includes source, 'using terms from application id "#{expected_bundle_id}"'
    assert_includes source, "tell application appTarget to list icon zones"
  end

  def test_runtime_smoke_tracks_native_apple_and_host_exact_id_lanes
    source = qa_source

    assert_includes source, 'RUNTIME_NATIVE_APPLE_IDS = %w['
    assert_includes source, 'com.apple.menuextra.siri'
    assert_includes source, 'com.apple.menuextra.spotlight'
    assert_includes source, 'RUNTIME_HOST_EXACT_ID_SENTINEL_IDS = %w['
    assert_includes source, 'com.sanebar.hostsentinel::statusItem:0'
    assert_includes source, "RUNTIME_HOST_EXACT_ID_FIXTURE_ID = 'com.sanebar.hostsentinel'"
    assert_includes source, 'at.obdev.littlesnitch.networkmonitor'
    assert_includes source, 'at.obdev.littlesnitch.agent'
    assert_includes source, "lane_name: 'native-apple exact-id'"
    assert_includes source, "lane_name: 'host exact-id'"
    assert_includes source, 'host_fixture_ids = ensure_runtime_host_exact_id_fixture!(target)'
    assert_includes source, 'statusItem.menu = menu'
    assert_includes source, 'host exact-id smoke unavailable'
    refute_includes source, 'host exact-id smoke skipped'
  end

  def test_focused_runtime_smoke_preserves_screenshot_setting
    source = qa_source

    assert_includes source, "'SANEBAR_SMOKE_CAPTURE_SCREENSHOTS' => capture_runtime_smoke_screenshots ? '1' : '0'"
    refute_includes source, "'SANEBAR_SMOKE_CAPTURE_SCREENSHOTS' => '0'"
  end

  def test_runtime_smoke_status_snapshot_records_all_exact_id_lanes
    source = qa_source

    assert_includes source, 'runtimeSmokeFocusedExactIdSets: ['
    assert_includes source, "lane: 'shared-bundle'"
    assert_includes source, "lane: 'native-apple'"
    assert_includes source, "lane: 'host-exact-id'"
    assert_includes source, "def manual_override_approved?"
    assert_includes source, "'approved'"
  end

  def test_runtime_smoke_candidate_lines_use_bundle_metadata_keys
    @qa.define_singleton_method(:app_bundle_metadata) do |_path|
      { short_version: '2.1.62', build_version: '2162' }
    end

    lines = @qa.send(
      :runtime_smoke_candidate_lines,
      app_path: '/Applications/SaneBar.app',
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    )

    assert_includes lines, 'candidate_app_version=2.1.62'
    assert_includes lines, 'candidate_app_build=2162'
  end

  def test_shared_bundle_exact_id_smoke_launches_fixture_instead_of_skipping
    source = qa_source

    assert_includes source, 'shared_bundle_ids = ensure_runtime_shared_bundle_fixture!(target)'
    assert_includes source, 'Shared-bundle move regressions are release-blocking'
    refute_includes source, 'shared-bundle focused smoke skipped'
  end

  def test_focused_exact_id_runtime_smoke_uses_move_only_no_keychain_guard
    source = qa_source

    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_NO_KEYCHAIN' => target[:no_keychain] ? '1' : '0'"
    assert_includes source, "'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '0'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY'] = '1'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_PIN_REQUIRED_BROWSE_ALWAYS_HIDDEN'] = '1'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_MIN_PASSING_CANDIDATES'] = '1' if lane_name == 'shared-bundle'"
    assert_includes source, 'com.sanebar.sharedfixture::statusItem:2'
  end

  def test_live_zone_smoke_second_menu_bar_prefers_precise_non_apple_candidates
    source = live_zone_smoke_source

    assert_includes source, "if expected_mode == 'secondMenuBar'"
    assert_includes source, 'precise_non_apple + coarse_non_apple + exact_apple + preferred + fallback'
    assert_includes source, 'BROWSE_ACTIVATION_UNRELIABLE_IDS = %w['
  end

  def test_live_zone_smoke_allows_exact_menumeters_fixture_for_browse_activation
    source = live_zone_smoke_source

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
