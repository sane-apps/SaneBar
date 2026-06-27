#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tempfile'
require_relative 'qa'
require_relative 'live_zone_smoke'
require_relative 'startup_layout_probe'

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
  def startup_layout_probe_source
    @startup_layout_probe_source ||= File.read(File.join(__dir__, 'startup_layout_probe.rb'))
  end
  def project_doc(path)
    File.read(File.join(ProjectQA::PROJECT_ROOT, path))
  end
  def source_bundle(entrypoint, partial_pattern)
    paths = [
      File.join(__dir__, entrypoint),
      *Dir.glob(File.join(__dir__, 'lib', partial_pattern)).sort
    ]
    paths.map { |path| File.read(path) }.join("\n")
  end

  def with_startup_layout_probe
    probe = StartupLayoutProbe.new
    yield probe
  ensure
    workspace = probe&.instance_variable_get(:@workspace)
    FileUtils.remove_entry(workspace) if workspace && File.directory?(workspace)
  end

  def with_stubbed_process_table(process_table)
    original_capture2e = Open3.method(:capture2e)
    status = Object.new
    status.define_singleton_method(:success?) { true }
    Open3.define_singleton_method(:capture2e) do |*args|
      if args == ['ps', 'ax', '-o', 'pid=,comm=,command='] ||
         args == ['ps', 'ax', '-o', 'pid=,command=']
        [process_table, status]
      else
        original_capture2e.call(*args)
      end
    end
    yield
  ensure
    Open3.define_singleton_method(:capture2e) { |*args| original_capture2e.call(*args) }
  end

  def with_file_backup(path)
    existed = File.exist?(path)
    content = File.binread(path) if existed
    yield
  ensure
    if existed
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    else
      FileUtils.rm_f(path)
    end
  end

  def test_reporter_confirmation_accepts_plain_working_reply
    assert @qa.send(:reporter_confirmation_text?, "It's working. The updates are a bit slow in the UI but that's ok.")
  end

  def test_qa_script_refuses_overlapping_runs_before_runtime_fixtures_launch
    assert_includes qa_source, 'QA_LOCK_PATH'
    assert_includes qa_source, 'def self.acquire_process_lock!'
    assert_includes qa_source, 'flock(File::LOCK_EX | File::LOCK_NB)'
    assert_includes qa_source, 'Refusing overlapping QA because it corrupts runtime fixture/menu-bar state'
    assert_includes qa_source, 'ProjectQA.acquire_process_lock!'
  end

  def test_reporter_confirmation_rejects_negative_reply
    refute @qa.send(:reporter_confirmation_text?, "It's not working. The same problem is still happening.")
  end
  def test_stale_patched_pending_closure_exempts_after_five_business_days
    comments = [
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-06-06T13:36:33Z',
        'body' => 'Please update and try the same flow again.'
      },
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-06-16T14:38:49Z',
        'body' => 'Closing this as fixed by the current patched-pending policy; there has been no newer report after the retest request. Please reopen or file a fresh in-app report if the same flow still fails on the current build.'
      }
    ]

    assert_equal(
      'stale patched-pending closure',
      @qa.send(:closed_regression_confirmation_exemption_reason, comments, issue: { 'closedAt' => '2026-06-16T14:38:49Z' })
    )
  end
  def test_stale_patched_pending_closure_requires_five_business_days
    comments = [
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-06-12T13:36:33Z',
        'body' => 'Please update and try the same flow again.'
      },
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-06-16T14:38:49Z',
        'body' => 'Closing this as fixed by the current patched-pending policy; there has been no newer report after the retest request. Please reopen or file a fresh in-app report if the same flow still fails on the current build.'
      }
    ]

    refute @qa.send(:closed_regression_confirmation_exemption_reason, comments, issue: { 'closedAt' => '2026-06-16T14:38:49Z' })
  end
  def test_stale_patched_pending_closure_rejects_reporter_reply_after_retest
    comments = [
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-06-06T13:36:33Z',
        'body' => 'Please update and try the same flow again.'
      },
      {
        'authorAssociation' => 'NONE',
        'createdAt' => '2026-06-10T13:36:33Z',
        'body' => 'Still broken after the update.'
      },
      {
        'authorAssociation' => 'MEMBER',
        'createdAt' => '2026-06-16T14:38:49Z',
        'body' => 'Closing this as fixed by the current patched-pending policy; there has been no newer report after the retest request. Please reopen or file a fresh in-app report if the same flow still fails on the current build.'
      }
    ]

    refute @qa.send(:closed_regression_confirmation_exemption_reason, comments, issue: { 'closedAt' => '2026-06-16T14:38:49Z' })
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
    # fullscreen-overlay-restore screenshot requirement retired with the fullscreen probes (owner direction 2026-06-26)
    assert_includes source, "runtime_fullscreen_matrix_artifact_passed?"
    assert_includes source, "'app activation keeps dark custom tint visible'"
    assert_includes source, "'hidden and visible icon zones persist across fullscreen Space transition'"
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

  def test_release_runtime_smoke_children_have_hard_timeouts
    source = qa_source

    assert_includes source, 'RUNTIME_SMOKE_PASS_TIMEOUT_SECONDS = 420'
    assert_includes source, 'RUNTIME_SMOKE_FOCUSED_PASS_TIMEOUT_SECONDS = 300'
    assert_includes source, 'timeout: RUNTIME_SMOKE_PASS_TIMEOUT_SECONDS'
    assert_includes source, 'timeout: focused_runtime_smoke_timeout_seconds(exact_ids)'
    assert_includes source, 'terminate_runtime_command_child(wait_thr)'
  end

  def test_focused_runtime_smoke_timeout_scales_with_required_ids
    assert_equal 300, @qa.send(:focused_runtime_smoke_timeout_seconds, ['one'])
    assert_equal 540, @qa.send(:focused_runtime_smoke_timeout_seconds, %w[one two three])
  end

  def test_live_zone_smoke_checks_activation_tint_stability
    source = live_zone_smoke_source
    assert_includes source, 'exercise_app_activation_tint_stability_check'
    assert_includes source, 'activation-immediate'
    assert_includes source, 'activation-settled'
    assert_includes source, 'app activation keeps dark custom tint visible'
    assert_includes source, 'capture_fullscreen_space_transition_zone_baseline!'
    assert_includes source, 'assert_fullscreen_space_transition_zone_persistence!'
    assert_includes source, 'hidden and visible icon zones persist across fullscreen Space transition'
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

  def test_sanemaster_wrapper_stays_thin_and_sources_shared_prelude
    source = qa_source
    wrapper_source = File.read(File.join(ProjectQA::PROJECT_ROOT, 'scripts', 'SaneMaster.rb'))

    assert_includes source, 'wrapper policy requires a thin shared-prelude delegate'
    assert_includes source, 'sanemaster-wrapper-prelude.sh'
    assert_includes source, 'forbidden_local_policy'
    assert_includes wrapper_source, 'sanemaster-wrapper-prelude.sh'
    assert_operator wrapper_source.lines.count, :<=, 90
    refute_includes wrapper_source, 'security find-identity'
    refute_includes wrapper_source, 'set-key-partition-list'
  end

  def test_shared_sanemaster_wrapper_prelude_owns_signing_policy
    prelude_path = File.expand_path('../../infra/SaneProcess/scripts/sanemaster-wrapper-prelude.sh', ProjectQA::PROJECT_ROOT)
    prelude_source = File.read(prelude_path)

    assert_includes prelude_source, 'saneprocess_prepare_signing_keychain'
    assert_includes prelude_source, 'saneprocess_enforce_signing_preflight'
    assert_includes prelude_source, 'SANEMASTER_KEYCHAIN_PASSWORD'
    assert_includes prelude_source, 'SANEBAR_KEYCHAIN_PASSWORD'
  end

  def test_durable_docs_match_direct_zip_distribution_and_macos_metadata
    manifest = project_doc('.saneprocess')
    readme = project_doc('README.md')
    architecture = project_doc('ARCHITECTURE.md')
    development = project_doc('DEVELOPMENT.md')
    scripts_readme = project_doc('Scripts/README.md')

    min_system_version = manifest[/min_system_version:\s*"([^"]+)"/, 1]
    assert_equal '14.0', min_system_version
    assert_includes readme, 'macOS 14.0+ (Sonoma or later), Apple Silicon (arm64) only'
    assert_includes readme, 'macOS-14.0%2B'
    refute_match(/macOS 15(?:\.0)?\+|macOS 15 Sequoia|macOS-15/, readme)

    [architecture, development, scripts_readme].each do |doc|
      assert_match(%r{ZIP-first direct-download/Sparkle}, doc)
    end
    assert_includes development, 'dist.sanebar.com/updates/SaneBar-X.Y.Z.zip'
    assert_includes architecture, 'Sparkle appcast enclosures and website download routes must point to the same versioned ZIP'
  end
  def test_durable_docs_capture_live_anchor_recovery_and_current_proof_contract
    architecture = project_doc('ARCHITECTURE.md')
    development = project_doc('DEVELOPMENT.md')
    scripts_readme = project_doc('Scripts/README.md')

    assert_includes architecture, 'Live-Anchor Structural Recovery Contract'
    assert_includes architecture, 'main SaneBar status item and separator status-item anchors are live'
    assert_includes architecture, 'cached geometry alone'
    assert_includes architecture, 'open the Health fallback'

    assert_includes development, '### Rollback and Current Proof'
    assert_includes development, 'Summary-only handoff prose is not enough release proof'
    assert_includes development, 'completed scenarios proving live main and'
    assert_includes scripts_readme, 'live-anchor structural recovery contract'
  end
  def test_scripts_readme_inventory_matches_present_scripts_and_casing
    scripts_readme = project_doc('Scripts/README.md')
    shared_section = scripts_readme[/## Shared Scripts.*?## Project-Specific Scripts/m]
    project_section = scripts_readme[/## Project-Specific Scripts.*?Run the live browse smoke directly:/m]
    listed_scripts = [shared_section, project_section].compact.flat_map do |section|
      section.scan(/^\| `([^`]+)` \|/).flatten
    end

    assert_includes scripts_readme, 'Canonical checked-in path is `Scripts/`'
    refute_includes scripts_readme, './scripts/'
    refute_includes scripts_readme, '20L'
    assert_operator File.readlines(File.join(ProjectQA::SCRIPTS_DIR, 'SaneMaster.rb')).count, :>, 20
    refute_includes listed_scripts, 'publish_website.sh'
    refute_includes listed_scripts, 'post_release.rb'

    listed_scripts.each do |script|
      assert File.exist?(File.join(ProjectQA::SCRIPTS_DIR, script)), "Scripts/README.md lists missing script #{script}"
    end

    %w[
      SaneMaster.rb
      SaneMaster_standalone.rb
      qa.rb
      customer_ui_action_sweep.rb
      live_zone_smoke.rb
      startup_layout_probe.rb
      wake_layout_probe.rb
    ].each do |script|
      assert_includes listed_scripts, script
    end
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
  def test_curl_url_status_uses_bounded_runtime_timeout_helper
    calls = []
    ok_status = Object.new
    ok_status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:capture2e_with_runtime_timeout) do |*args, timeout:, label:|
      calls << { args: args, timeout: timeout, label: label }
      ['204', ok_status]
    end

    code = @qa.send(
      :curl_url_status,
      'https://example.com/download.zip',
      head: true,
      connect_timeout: '1',
      max_time: '4'
    )

    assert_equal 204, code
    assert_equal 1, calls.count
    assert_includes calls.first[:args], '--head'
    assert_includes calls.first[:args], 'https://example.com/download.zip'
    assert_equal 7.0, calls.first[:timeout]
    assert_equal 'HEAD URL status', calls.first[:label]
  end
  def test_curl_url_status_no_longer_uses_raw_open3_capture2e
    stability_source = File.read(File.join(__dir__, 'lib', 'project_qa_stability_urls.rb'))

    assert_includes stability_source, 'capture2e_with_runtime_timeout('
    assert_includes stability_source, 'timeout: max_time.to_f + 3.0'
    refute_includes stability_source, 'output, status = Open3.capture2e(*args)'
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

  def test_runtime_smoke_retryable_failure_matches_target_loss_after_applescript_race
    output = <<~LOG
      ⚠️ Candidate failed: com.sanebar.hostsentinel (runtime_target_lost during AppleScript move icon to hidden "com.sanebar.hostsentinel::statusItem:0": AppleScript failed; process_missing pid=54650 expected=/Applications/SaneBar.app/Contents/MacOS/SaneBar currentMatches=none)
      ❌ Live zone smoke failed: Candidate failures: com.sanebar.hostsentinel::statusItem:0: runtime_target_lost during AppleScript move icon to hidden "com.sanebar.hostsentinel::statusItem:0": AppleScript failed; process_missing pid=54650 expected=/Applications/SaneBar.app/Contents/MacOS/SaneBar currentMatches=none
    LOG

    assert @qa.send(:retryable_runtime_smoke_failure?, output)
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

  def test_shared_bundle_runtime_smoke_retries_missing_fixture_id
    output = <<~LOG
      required_ids=com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A,com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B,com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-C
      ❌ Live zone smoke failed: Required icon(s) missing from list icon zones: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-C
    LOG

    refute @qa.send(:retryable_runtime_smoke_failure?, output)
    assert @qa.send(:retryable_shared_bundle_runtime_smoke_failure?, output)
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

  def test_shared_bundle_runtime_smoke_retries_single_post_settle_drift_after_partial_pass
    output = <<~LOG
      ✅ Candidate passed: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B
      ✅ Candidate passed: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-C
      ❌ Live zone smoke failed: 2/3 candidates passed move action checks. Candidate failures: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A: Post-settle move verification drifted: com.sanebar.sharedfixture (SaneBarSharedFixture) expected visible, got hidden
    LOG

    assert @qa.send(:retryable_shared_bundle_runtime_smoke_failure?, output)
  end

  def test_shared_bundle_runtime_smoke_retries_observed_full_candidate_drift
    output = <<~LOG
      ❌ Live zone smoke failed: 0/3 candidates passed move action checks. Candidate failures: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A: Post-settle move verification drifted: com.sanebar.sharedfixture (SaneBarSharedFixture) expected visible, got hidden | com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B: Menu bar did not become move-ready before action (snapshot=) | com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-C: Menu bar did not become move-ready before action (snapshot=)
    LOG

    assert @qa.send(:retryable_shared_bundle_runtime_smoke_failure?, output)
  end

  def test_shared_bundle_runtime_smoke_retry_reseeds_fixture_before_pro_precheck
    source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_fixtures.rb'))

    assert_includes source, 'prepare_focused_runtime_smoke_retry!'
    assert_includes source, 'cleanup_runtime_shared_bundle_fixture!'
    assert_includes source, 'resolved_ids = ensure_runtime_shared_bundle_fixture!(target)'
    assert_includes source, 'missing_ids = exact_ids - resolved_ids'
    assert_operator source.index('prepare_focused_runtime_smoke_retry!'), :<, source.index('focused_runtime_smoke_pro_error(target, "#{lane_name} retry")')
  end

  def test_runtime_smoke_requires_startup_and_wake_layout_probes
    source = qa_source
    preflight_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_preflight.rb'))

    assert_includes source, "startup_probe_script = File.join(SCRIPTS_DIR, 'startup_layout_probe.rb')"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH"
    assert_includes source, 'startup_probe_env.merge!(runtime_probe_no_keychain_env(target))'
    assert_includes source, "runtime startup layout probe"
    assert_includes source, 'startup_probe_started_at = Time.now'
    assert_includes source, 'timeout: startup_probe_timeout_seconds(startup_resource_soak_required, startup_resource_soak_seconds)'
    assert_includes source, 'startup_probe_artifact_contract_error(started_at: startup_probe_started_at)'
    assert_includes preflight_source, 'startup_probe_artifact_contract_error'
    assert_includes preflight_source, 'stale_runtime_artifact?'
    assert_includes preflight_source, '#157 dirty reboot recovery keeps live anchors before hiding'
    assert_includes preflight_source, '#157 dirty startup waits for valid status-item windows before auto-hide'
    assert_includes preflight_source, '#155 dirty startup AH replay allows outbound moves'
    assert_includes preflight_source, '#155 dirty startup restores pinned icons into Always Hidden before outbound moves'
    assert_includes preflight_source, '#155 pinned icon exits Always Hidden after dirty startup'
    assert_includes preflight_source, '#155 Always Hidden outbound moves leave move state idle'
    assert_includes preflight_source, '#155 dirty startup resource soak remains stable after outbound moves'
    assert_includes preflight_source, 'runtime_probe_candidate_matches_project?'
    assert_includes source, "wake_probe_script = File.join(SCRIPTS_DIR, 'wake_layout_probe.rb')"
    assert_includes source, "'SANEBAR_WAKE_PROBE_LOG_PATH' => RUNTIME_WAKE_PROBE_LOG_PATH"
    assert_includes source, "'SANEBAR_WAKE_PROBE_ARTIFACT_PATH' => RUNTIME_WAKE_PROBE_ARTIFACT_PATH"
    assert_includes source, "dynamic_helper_ids = ensure_runtime_dynamic_helper_wake_fixture!(target)"
    assert_includes source, "'SANEBAR_WAKE_PROBE_DYNAMIC_HELPER_IDS' => dynamic_helper_ids.join(',')"
    assert_includes source, "visible_dynamic_helper_ids = ensure_runtime_visible_dynamic_helper_wake_fixture!(target)"
    assert_includes source, "'SANEBAR_WAKE_PROBE_REQUIRED_VISIBLE_IDS' => visible_dynamic_helper_ids.join(',')"
    assert_includes source, 'wake_probe_env.merge!(runtime_probe_no_keychain_env(target))'
    assert_includes source, "'SANEBAR_PROBE_FORCE_NO_KEYCHAIN' => '1'"
    assert_includes source, 'wake_probe_started_at = Time.now'
    assert_includes source, 'timeout: 240'
    assert_includes source, 'wake_probe_artifact_contract_error(started_at: wake_probe_started_at)'
    assert_includes preflight_source, 'wake_probe_mini_runtime_provenance_error'
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
    assert_includes source, 'case "SBF-D": symbolName = "circle.hexagongrid.fill"'
    assert_includes source, 'default: symbolName = "diamond.grid.3x3.fill"'
    assert_includes source, 'item.button?.image = fixtureImage(for: title)'
    assert_includes source, 'func fixtureMenu(for title: String) -> NSMenu'
    assert_includes source, 'Activation Probe \\\\(title)'
    assert_includes source, 'item.menu = fixtureMenu(for: title)'
    assert_includes source, 'image?.isTemplate = true'
  end

  def test_preflight_mode_accepts_saneprocess_env_names
    source = qa_source

    assert_includes source, "ENV['SANEPROCESS_RELEASE_PREFLIGHT'] == '1'"
    assert_includes source, "ENV['SANEPROCESS_RUN_STABILITY_SUITE'] == '1'"
    assert_includes source, "ENV['SANEPROCESS_RELEASE_POLICY_ONLY'] == '1'"
    assert_includes source, "ENV['SANEPROCESS_REUSE_CUSTOMER_UI_RUNTIME_PROOF'] == '1'"
    assert_includes source, 'policyOnlyMode: release_policy_only_mode?'
  end

  def test_runtime_smoke_requires_real_pro_access_for_always_hidden_checks
    source = qa_source

    assert_includes source, 'runtime_smoke_host_allowed?'
    assert_includes source, 'SANE_APPROVE_LOCAL_UI_ON_AIR'
    assert_includes source, 'SANE_MINI_UNAVAILABLE'
    assert_includes source, 'ensure_runtime_smoke_representative_zones_ready!(target)'
    assert_includes source, 'representative_zone_settle_error = ensure_runtime_smoke_representative_zones_ready!(target)'
    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN' => '1'"
    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_ALL_ZONES' => '1'"
    assert_includes source, "'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '0'"
    assert_includes source, 'always_hidden_setup_error = ensure_runtime_smoke_always_hidden_ready!(target)'
    assert_includes source, "settings['hasSeenFreemiumIntro'] = true"
    assert_includes source, "settings['hasCompletedHealthWizard'] = true"
    assert_includes source, "Runtime smoke requires a paid license or active Pro trial for Always Hidden checks;"
  end

  def test_runtime_smoke_locks_shared_runtime_target_against_overlapping_probes
    source = qa_source
    preflight_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_preflight.rb'))

    assert_includes preflight_source, "RUNTIME_TARGET_LOCK_PATH = ENV['SANEBAR_RUNTIME_TARGET_LOCK_PATH']"
    assert_includes preflight_source, "ENV['SANEMASTER_RUNTIME_PROBE_LOCK_PATH']"
    assert_includes preflight_source, 'def acquire_runtime_target_lock'
    assert_includes preflight_source, 'flock(File::LOCK_EX | File::LOCK_NB)'
    assert_includes preflight_source, 'runtime_probe_conflict_error'
    assert_includes preflight_source, "'Scripts/startup_layout_probe.rb'"
    assert_includes preflight_source, "'Scripts/wake_layout_probe.rb'"
    assert_includes preflight_source, "'SANEBAR_RUNTIME_TARGET_LOCK_BYPASS' => '1'"
    assert_includes preflight_source, 'File::NOFOLLOW'
    assert_includes preflight_source, 'File::EXCL'
    assert_includes preflight_source, 'File.link(temp_path, RUNTIME_TARGET_LOCK_PATH)'
    assert_includes preflight_source, 'safe_write_runtime_file'
    assert_includes preflight_source, 'cleanup_runtime_target_lock_file'
    assert_includes preflight_source, 'runtime_target_lock_holder_detail'
    assert_includes preflight_source, 'FileUtils.rm_f(RUNTIME_TARGET_LOCK_PATH)'
    assert_includes source, 'release_runtime_target_lock(runtime_lock)'
  end

  def test_wake_probe_artifact_contract_rejects_nested_failures
    path = ProjectQA::RUNTIME_WAKE_PROBE_ARTIFACT_PATH
    visible_scenarios = [
      'baseline visible icon-zone snapshot before display sleep',
      'fresh authoritative icon-zone snapshot at 1s after wake',
      'fresh authoritative icon-zone snapshot at 5s after wake',
      'fresh authoritative icon-zone snapshot at 15s after wake',
      'visible required IDs remain visible and are not moved into Hidden or Always Hidden'
    ]
    hidden_scenarios = [
      'baseline hidden icon-zone snapshot before display sleep',
      'fresh authoritative icon-zone snapshot at 1s after wake',
      'fresh authoritative icon-zone snapshot at 5s after wake',
      'fresh authoritative icon-zone snapshot at 15s after wake',
      'hidden required IDs remain hidden and are not moved into Visible or Always Hidden'
    ]
    dynamic_scenarios = [
      'dynamic helper required IDs are present before wake',
      'dynamic helper required IDs remain in intended zones after wake',
      'helper-specific Hidden to Visible drift is rejected as a release blocker'
    ]
    artifact = {
      'status' => 'pass',
      'app_path' => '/Applications/SaneBar.app',
      'candidate' => {
        'app_path' => '/Applications/SaneBar.app',
        'app_version' => @qa.send(:project_yml_setting, 'MARKETING_VERSION'),
        'app_build' => @qa.send(:project_yml_setting, 'CURRENT_PROJECT_VERSION')
      },
      'runtime_provenance' => {
        'mini_runtime' => true,
        'host' => 'mini',
        'generated_at' => Time.now.utc.iso8601,
        'app_path' => '/Applications/SaneBar.app'
      },
      'visible_zone_persistence' => {
        'status' => 'pass',
        'completed_scenarios' => visible_scenarios
      },
      'hidden_zone_persistence' => {
        'status' => 'fail',
        'completed_scenarios' => hidden_scenarios
      },
      'dynamic_helper_wake_drift' => {
        'status' => 'pass',
        'completed_scenarios' => dynamic_scenarios
      }
    }

    with_file_backup(path) do
      File.write(path, JSON.pretty_generate(artifact) + "\n")
      assert_match(/Wake layout probe artifact failed proof section\(s\): hidden_zone_persistence/, @qa.send(:wake_probe_artifact_contract_error))

      artifact['hidden_zone_persistence']['status'] = 'pass'
      File.write(path, JSON.pretty_generate(artifact) + "\n")
      assert_nil @qa.send(:wake_probe_artifact_contract_error)
    end
  end

  def test_startup_layout_probe_restores_current_host_status_item_state
    source = startup_layout_probe_source

    assert_includes source, 'CURRENT_HOST_STATUS_ITEM_KEY_PATTERN'
    assert_includes source, 'backup_current_host_status_item_state!'
    assert_includes source, 'restore_current_host_status_item_state!'
    assert_includes source, "defaults', '-currentHost', 'export', 'NSGlobalDomain', '-'"
    assert_includes source, 'parse_current_host_status_item_plist'
    assert_includes source, "current_host_status_item_state.keys.each { |key| delete_current_host_default(key) }"
    assert_includes source, 'write_current_host_default_value(key, value)'
    refute_includes source, "'plutil'"
  end

  def test_startup_layout_probe_current_host_parser_ignores_non_status_item_data
    with_startup_layout_probe do |probe|
      plist = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>com.apple.gms.availability.unifiedReasons</key>
          <data>YnBsaXN0MDDRAQJUaW5mbw==</data>
          <key>NSStatusItem Preferred Position SaneBar_main_v39_v6</key>
          <real>144</real>
          <key>NSStatusItem Visible SaneBar_Main_v32</key>
          <false/>
          <key>NSStatusItem VisibleCC SaneBar_Separator_v32</key>
          <true/>
        </dict>
        </plist>
      XML

      state = probe.send(:parse_current_host_status_item_plist, plist)

      assert_equal 144.0, state['NSStatusItem Preferred Position SaneBar_main_v39_v6']
      assert_equal false, state['NSStatusItem Visible SaneBar_Main_v32']
      assert_equal true, state['NSStatusItem VisibleCC SaneBar_Separator_v32']
      refute_includes state.keys, 'com.apple.gms.availability.unifiedReasons'
    end
  end

  def test_startup_layout_probe_quit_escalates_after_failed_graceful_quit
    with_startup_layout_probe do |probe|
      failed = Object.new
      failed.define_singleton_method(:success?) { false }
      failed.define_singleton_method(:exitstatus) { 1 }
      running = true
      signals = []

      probe.instance_variable_set(:@app_name, 'SaneBar')
      probe.instance_variable_set(:@bundle_id, 'com.sanebar.app')
      probe.define_singleton_method(:app_running?) { running }
      probe.define_singleton_method(:capture) { |_cmd, *_args| ['User canceled', failed] }
      probe.define_singleton_method(:graceful_quit_timeout_seconds) { |_status| 0.0 }
      probe.define_singleton_method(:force_quit_timeout_seconds) { 0.0 }
      probe.define_singleton_method(:terminate_lingering_app_processes_until_gone!) do |timeout:, signal:|
        signals << [signal, timeout]
        running = false if signal == 'TERM'
      end
      probe.define_singleton_method(:reap_direct_launch_children!) {}

      probe.send(:quit_app)

      assert_equal [['TERM', 0.0]], signals
    end
  end

  def test_startup_layout_probe_marks_explicit_automation_quit_before_apple_event
    Tempfile.create('sanebar-startup-quit-marker') do |file|
      marker_path = file.path
      File.unlink(marker_path)
      old_marker = ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH']
      ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH'] = marker_path

      with_startup_layout_probe do |probe|
        succeeded = Object.new
        succeeded.define_singleton_method(:success?) { true }
        succeeded.define_singleton_method(:exitstatus) { 0 }
        running = true
        marker_seen_during_quit = false

        probe.instance_variable_set(:@app_name, 'SaneBar')
        probe.instance_variable_set(:@bundle_id, 'com.sanebar.app')
        probe.instance_variable_set(:@automation_quit_token, 'startup-token')
        probe.define_singleton_method(:app_running?) { running }
        probe.define_singleton_method(:capture) do |_cmd, *_args|
          marker_seen_during_quit = File.read(marker_path).strip == 'startup-token'
          running = false
          ['', succeeded]
        end
        probe.define_singleton_method(:terminate_lingering_app_processes_until_gone!) { |timeout:, signal:| }
        probe.define_singleton_method(:reap_direct_launch_children!) {}

        probe.send(:quit_app)

        assert marker_seen_during_quit
        refute File.exist?(marker_path), 'Startup probe should remove its explicit quit marker after cleanup'
      end
    ensure
      ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH'] = old_marker
      FileUtils.rm_f(marker_path) if marker_path
    end
  end

  def test_startup_layout_probe_cleans_up_fixture_it_seeds
    with_startup_layout_probe do |probe|
      helper = Object.new
      cleaned = false
      helper.define_singleton_method(:send) do |method_name, *_args|
        cleaned = true if method_name == :cleanup_runtime_shared_bundle_fixture!
      end
      probe.instance_variable_set(:@shared_fixture_helper, helper)
      probe.instance_variable_set(:@seeded_shared_fixture_for_probe, true)

      probe.send(:cleanup_seeded_shared_fixture!)

      assert cleaned
      refute probe.instance_variable_get(:@seeded_shared_fixture_for_probe)
    end
  end

  def test_runtime_smoke_test_mode_launch_uses_progress_capture
    source = qa_source

    assert_includes source, "launch_out, launch_status = capture2e_with_progress("
    assert_includes source, "heartbeat_label: 'runtime smoke test_mode launch'"
    assert_includes source, 'def capture2e_with_progress(env, *cmd, heartbeat_label:, timeout: nil)'
    assert_includes source, 'terminate_runtime_command_child(wait_thr)'
    assert_includes source, 'runtime_command_failed_status'
    refute_includes source, "launch_out, launch_status = Open3.capture2e(\n        { 'SANEMASTER_ALLOW_UNSIGNED_FALLBACK' => '0' }"
  end

  def test_runtime_smoke_reapplies_appearance_fixture_after_test_mode_cleanup
    source = qa_source
    launch_index = source.index("heartbeat_label: 'runtime smoke test_mode launch'")
    reapply_index = source.index("prepare_runtime_smoke_appearance_settings!\n        target = target.merge(relaunch: true)")
    ensure_index = source.index('unless ensure_runtime_smoke_target_running!(target)', reapply_index)

    refute_nil launch_index
    refute_nil reapply_index
    refute_nil ensure_index
    assert_operator launch_index, :<, reapply_index
    assert_operator reapply_index, :<, ensure_index
  end

  def test_runtime_smoke_target_running_requires_nonempty_process_match
    checks = 0
    launches = 0
    terminations = 0
    target = {
      app_path: '/Applications/SaneBar.app',
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar',
      relaunch: true,
      no_keychain: true
    }

    @qa.define_singleton_method(:sleep) { |_seconds| }
    @qa.define_singleton_method(:terminate_runtime_smoke_target_processes!) do |_target|
      terminations += 1
      true
    end
    @qa.define_singleton_method(:launch_runtime_smoke_target!) do |_target|
      launches += 1
      true
    end
    @qa.define_singleton_method(:runtime_smoke_target_processes) do |_target, require_no_keychain: true|
      checks += 1 if require_no_keychain
      checks >= 2 ? ['123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain'] : []
    end

    assert @qa.send(:ensure_runtime_smoke_target_running!, target)
    assert_equal 1, launches
    assert_equal 1, terminations
    assert_operator checks, :>=, 2
    refute target[:relaunch], 'successful ensure should not keep relaunching on later snapshot reads'
  end

  def test_runtime_smoke_target_running_waits_for_exclusive_no_keychain_process
    target = {
      app_path: '/Applications/SaneBar.app',
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar',
      relaunch: false,
      no_keychain: true
    }
    checks = 0

    @qa.define_singleton_method(:sleep) { |_seconds| }
    @qa.define_singleton_method(:runtime_smoke_target_processes) do |_target, require_no_keychain: true|
      checks += 1
      if checks < 3
        require_no_keychain ? ['123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain'] : [
          '123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain',
          '124 /Applications/SaneBar.app/Contents/MacOS/SaneBar'
        ]
      else
        ['123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain']
      end
    end

    assert @qa.send(:ensure_runtime_smoke_target_running!, target)
    refute target[:relaunch]
    assert_operator checks, :>=, 3
  end

  def test_runtime_smoke_target_running_rejects_duplicate_processes
    target = {
      app_path: '/Applications/SaneBar.app',
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar',
      relaunch: false,
      no_keychain: true
    }

    @qa.define_singleton_method(:sleep) { |_seconds| }
    @qa.define_singleton_method(:runtime_smoke_target_processes) do |_target, require_no_keychain: true|
      next [] unless require_no_keychain

      [
        '123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain',
        '124 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain'
      ]
    end

    refute @qa.send(:ensure_runtime_smoke_target_running!, target)
  end

  def test_runtime_smoke_layout_snapshot_retries_until_app_command_is_ready
    target = {
      app_path: '/Applications/SaneBar.app',
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar',
      relaunch: false,
      no_keychain: true
    }
    attempts = 0
    requested_timeouts = []
    requested_labels = []
    failed = Object.new
    failed.define_singleton_method(:success?) { false }
    passed = Object.new
    passed.define_singleton_method(:success?) { true }

    @qa.define_singleton_method(:sleep) { |_seconds| }
    @qa.define_singleton_method(:ensure_runtime_smoke_target_running!) { |_probe_target| true }
    @qa.define_singleton_method(:runtime_smoke_target_processes) do |_probe_target, require_no_keychain: true|
      ['123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain']
    end
    @qa.define_singleton_method(:capture2e_with_runtime_timeout) do |*_cmd, timeout:, label:|
      attempts += 1
      requested_timeouts << timeout
      requested_labels << label
      if attempts == 1
        ['AppleScript layout snapshot timeout', failed]
      else
        ['{"licenseIsPro":true,"startupItemsValid":true}', passed]
      end
    end

    snapshot = @qa.send(:runtime_smoke_layout_snapshot, target)

    assert_equal true, snapshot['licenseIsPro']
    assert_equal true, snapshot['startupItemsValid']
    assert_equal 2, attempts
    assert_equal [4, 4], requested_timeouts
    assert_equal ['AppleScript layout snapshot', 'AppleScript layout snapshot'], requested_labels
  end

  def test_runtime_smoke_layout_snapshot_relaunches_after_basic_duplicate_snapshot
    target = {
      app_path: '/Applications/SaneBar.app',
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar',
      relaunch: false,
      no_keychain: true
    }
    attempts = 0
    relaunch_checks = 0
    passed = Object.new
    passed.define_singleton_method(:success?) { true }

    @qa.define_singleton_method(:sleep) { |_seconds| }
    @qa.define_singleton_method(:ensure_runtime_smoke_target_running!) do |probe_target|
      relaunch_checks += 1 if probe_target[:relaunch]
      probe_target[:relaunch] = false
      true
    end
    @qa.define_singleton_method(:runtime_smoke_target_processes) do |_target, require_no_keychain: true|
      require_no_keychain ? ['123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain'] : ['123 /Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain']
    end
    @qa.define_singleton_method(:capture2e_with_runtime_timeout) do |*_cmd, timeout:, label:|
      attempts += 1
      if attempts == 1
        ['{"licenseIsPro":false}', passed]
      else
        ['{"licenseIsPro":true,"startupItemsValid":true}', passed]
      end
    end

    snapshot = @qa.send(:runtime_smoke_layout_snapshot, target)

    assert_equal true, snapshot['licenseIsPro']
    assert_equal true, snapshot['startupItemsValid']
    assert_equal 2, attempts
    assert_equal 1, relaunch_checks
  end

  def test_runtime_smoke_relaunch_force_terminates_exact_target_processes
    source = qa_source

    assert_includes source, 'def terminate_runtime_smoke_target_processes!(target)'
    assert_includes source, "signal_runtime_smoke_target_pids(pids, 'TERM')"
    assert_includes source, "signal_runtime_smoke_target_pids(pids, 'KILL')"
    assert_includes source, 'matches.length == 1'
    refute_includes source, "system('killall', PROJECT_NAME"
  end

  def test_runtime_smoke_no_keychain_relaunch_uses_direct_executable
    source = qa_source

    assert_includes source, 'def launch_runtime_smoke_target!(target)'
    assert_includes source, "if target[:no_keychain]"
    assert_includes source, "Process.spawn("
    assert_includes source, "'SANEAPPS_DISABLE_KEYCHAIN' => '1'"
    assert_includes source, "'--sane-no-keychain'"
    assert_includes source, 'launch_runtime_smoke_target!(target)'
    assert_includes source, 'matches.length == 1'
    assert_includes source, 'return false if matches.length > 1'
    refute_includes source, 'return true if matches'
  end

  def test_runtime_fixture_process_detail_ignores_diagnostic_shell_mentions
    process_table = <<~PS
      123 /bin/zsh /bin/zsh -c tail /tmp/log; pgrep -fl SaneBarHostExactIDFixture
      124 /usr/bin/grep grep SaneBarHostExactIDFixture
    PS

    with_stubbed_process_table(process_table) do
      detail = @qa.send(
        :runtime_fixture_process_detail,
        'SaneBarHostExactIDFixture',
        app_path: '/tmp/SaneBarHostExactIDFixture.app'
      )

      assert_equal 'none', detail
      owned_detail = @qa.send(
        :owned_runtime_fixture_process_detail,
        'SaneBarHostExactIDFixture',
        app_path: '/tmp/SaneBarHostExactIDFixture.app'
      )
      assert_equal 'none', owned_detail
    end
  end

  def test_runtime_fixture_process_detail_matches_exact_fixture_executable
    executable = '/tmp/SaneBarHostExactIDFixture.app/Contents/MacOS/SaneBarHostExactIDFixture'
    process_table = "321 #{executable} #{executable}\n"

    with_stubbed_process_table(process_table) do
      detail = @qa.send(
        :runtime_fixture_process_detail,
        'SaneBarHostExactIDFixture',
        app_path: '/tmp/SaneBarHostExactIDFixture.app'
      )

      assert_includes detail, "321 #{executable}"
      owned_detail = @qa.send(
        :owned_runtime_fixture_process_detail,
        'SaneBarHostExactIDFixture',
        app_path: '/tmp/SaneBarHostExactIDFixture.app'
      )
      assert_includes owned_detail, "321 #{executable}"
    end
  end

  def test_focused_exact_id_lanes_skip_duplicate_launch_idle_budget
    source = qa_source

    assert_includes source, "focused_env['SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY'] = '1'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_SKIP_LAUNCH_IDLE_BUDGET'] = '1'"
    assert_includes live_zone_smoke_source, 'default runtime smoke covers cold launch and watchdog/post-smoke budgets remain active'
  end

  def test_visible_dynamic_process_detail_uses_loaded_owned_helper
    process_table = "456 /bin/zsh /bin/zsh -c echo SaneBarVisibleDynamicHelperFixture\n"

    with_stubbed_process_table(process_table) do
      detail = @qa.send(:runtime_visible_dynamic_helper_fixture_process_detail)

      assert_equal 'none', detail
    end
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

  def test_runtime_smoke_zone_seed_stops_when_retry_snapshot_sees_target_populated
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A' },
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B' },
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-C' },
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-D' },
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-E' },
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'visible', movable: true, bundle: 'com.example.visible2', unique_id: 'com.example.visible2::statusItem:0' }
    ]
    calls = []
    stale_count_reads = 0
    status = Object.new
    status.define_singleton_method(:success?) { true }
    @qa.define_singleton_method(:runtime_smoke_representative_zone_candidates) { |_target| zones }
    @qa.define_singleton_method(:runtime_smoke_representative_zone_counts) do |_target|
      stale_count_reads += 1
      next({ 'visible' => 7, 'hidden' => 0 }) if stale_count_reads == 1

      zones.group_by { |item| item[:zone] }.transform_values(&:length)
    end
    @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, unique_id|
      calls << [command, unique_id]
      zones.find { |item| item[:unique_id] == unique_id }[:zone] = 'hidden'
      ["true\n", status]
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:seed_runtime_smoke_zone!, { app_path: '/Applications/SaneBar.app' }, 'hidden')

    assert_nil error
    assert_equal 1, calls.length
    assert_equal({ 'visible' => 6, 'hidden' => 1 }, zones.group_by { |item| item[:zone] }.transform_values(&:length))
  end

  def test_runtime_smoke_seeds_preferred_shared_fixture_into_always_hidden_before_filling_minimum
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B' },
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
      ['move icon to always hidden', 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B'],
      ['move icon to always hidden', 'com.knollsoft.Rectangle::statusItem:0'],
      ['move icon to always hidden', 'com.example.another::statusItem:0']
    ], calls
  end

  def test_runtime_smoke_generic_seeding_uses_deterministic_shared_fixture_before_system_donors
    apple_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.apple.weather.menu')
    shared_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.sanebar.sharedfixture')

    assert_operator shared_rank, :<, apple_rank
  end

  def test_runtime_smoke_generic_seeding_keeps_visible_dynamic_fixture_as_last_donor
    shared_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.sanebar.sharedfixture')
    stable_third_party_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.example.stable')
    apple_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.apple.weather.menu')
    visible_dynamic_rank = @qa.send(:runtime_smoke_seed_donor_rank, bundle: 'com.ameba.SwiftBar')

    assert_operator shared_rank, :<, stable_third_party_rank
    assert_operator stable_third_party_rank, :<, visible_dynamic_rank
    assert_operator apple_rank, :<, visible_dynamic_rank
  end

  def test_runtime_smoke_rebalances_hidden_zone_from_always_hidden_surplus
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A' },
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

  def test_runtime_smoke_relaunches_once_when_representative_pool_loses_target
    target = { app_path: '/Applications/SaneBar.app' }
    candidate = { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'com.example.visible::statusItem:0' }
    candidate_calls = 0
    ensure_calls = []
    warmed = false

    @qa.define_singleton_method(:runtime_smoke_representative_zone_candidates) do |_probe_target|
      candidate_calls += 1
      warmed ? [candidate] : []
    end
    @qa.define_singleton_method(:ensure_runtime_smoke_target_running!) do |probe_target|
      ensure_calls << probe_target.dup
      probe_target[:relaunch] == true
    end
    @qa.define_singleton_method(:warm_runtime_smoke_candidate_pool!) { |_probe_target| warmed = true }
    @qa.define_singleton_method(:runtime_smoke_target_process_detail) { |_probe_target| 'none' }
    @qa.define_singleton_method(:sleep) { |_seconds| }

    error = @qa.send(:recover_runtime_smoke_candidate_pool_if_target_exited!, target, stage: 'representative setup')

    assert_nil error
    assert_operator candidate_calls, :>=, 1
    assert_equal [nil, true], ensure_calls.map { |entry| entry[:relaunch] }
  end

  def test_runtime_smoke_warm_pool_reensures_shared_fixture_when_starved
    target = { app_path: '/Applications/SaneBar.app' }
    status = Object.new
    status.define_singleton_method(:exitstatus) { 0 }
    fixture_ensured = false
    refresh_calls = 0

    @qa.define_singleton_method(:runtime_smoke_representative_zone_candidates) do |_probe_target|
      if fixture_ensured
        [
          { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'sbf-b' },
          { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'sbf-a' }
        ]
      else
        []
      end
    end
    @qa.define_singleton_method(:ensure_runtime_shared_bundle_fixture!) do |_probe_target|
      fixture_ensured = true
      ['sbf-a', 'sbf-b']
    end
    @qa.define_singleton_method(:refresh_runtime_smoke_icon_inventory) do |_probe_target|
      refresh_calls += 1
      ["", status]
    end
    @qa.define_singleton_method(:sleep) { |_seconds| }

    @qa.send(:warm_runtime_smoke_candidate_pool!, target, minimum_candidates: 2, attempts: 2)

    assert fixture_ensured
    assert_equal 1, refresh_calls
  end

  def test_runtime_smoke_candidate_pool_summary_includes_raw_rows_when_filter_starves
    target = { app_path: '/Applications/SaneBar.app' }

    @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_probe_target|
      [
        {
          zone: 'hidden',
          movable: true,
          bundle: 'com.openai.codex',
          unique_id: 'com.openai.codex::statusItem:0',
          name: 'Codex'
        }
      ]
    end

    summary = @qa.send(:runtime_smoke_candidate_pool_summary, target)

    assert_includes summary, 'filtered=empty'
    assert_includes summary, 'hidden:movable:com.openai.codex:com.openai.codex::statusItem:0'
  end

  def test_runtime_smoke_representative_readiness_accepts_complete_counts
    target = { app_path: '/Applications/SaneBar.app' }

    error = @qa.send(
      :runtime_smoke_representative_zone_readiness_error,
      target,
      counts: { 'visible' => 1, 'hidden' => 1, 'alwaysHidden' => 3 }
    )

    assert_nil error
  end

  def test_runtime_smoke_representative_readiness_reports_under_minimum_with_pool
    target = { app_path: '/Applications/SaneBar.app' }
    @qa.define_singleton_method(:runtime_smoke_representative_zone_candidates) do |_probe_target|
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.sanebar.sharedfixture',
          unique_id: 'sbf-a',
          name: 'SaneBarSharedFixture'
        }
      ]
    end

    error = @qa.send(
      :runtime_smoke_representative_zone_readiness_error,
      target,
      counts: { 'visible' => 1, 'hidden' => 1, 'alwaysHidden' => 2 }
    )

    assert_includes error, 'minimum representative candidates'
    assert_includes error, 'pool=alwaysHidden:sbf-a'
  end

  def test_runtime_smoke_post_settle_uses_lightweight_readiness_before_reseeding
    preflight_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_preflight.rb'))

    assert_includes preflight_source, 'representative_zone_setup_error = runtime_smoke_representative_zone_readiness_error(target)'
    assert_includes preflight_source, 'representative candidate pool already ready'
    assert_includes preflight_source, 'representative candidate pool incomplete; seeding fixtures'
    assert_includes preflight_source, 'settle_readiness_error = runtime_smoke_representative_zone_readiness_error(target)'
    assert_includes preflight_source, "representative setup drifted after settle; reseeding once"
  end

  def test_runtime_smoke_representative_setup_has_progress_and_timeout
    helper_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_helpers.rb'))
    source = qa_source

    assert_includes source, 'RUNTIME_SMOKE_REPRESENTATIVE_SETUP_TIMEOUT_SECONDS = 90'
    assert_includes helper_source, 'warming representative runtime candidate pool'
    assert_includes helper_source, 'representative candidates after warm'
    assert_includes helper_source, 'Runtime smoke representative setup exceeded'
    assert_includes helper_source, 'setup_deadline: setup_deadline'
  end

  def test_runtime_smoke_representative_setup_timeout_reports_pool
    target = { app_path: '/Applications/SaneBar.app' }
    @qa.define_singleton_method(:runtime_smoke_candidate_pool_summary) { |_probe_target| 'hidden:fixture-one' }

    error = @qa.send(:seed_runtime_smoke_zone!, target, 'alwaysHidden', setup_deadline: Time.now - 1)

    assert_includes error, 'Runtime smoke representative setup exceeded'
    assert_includes error, 'seeding alwaysHidden'
    assert_includes error, 'pool=hidden:fixture-one'
  end

  def test_runtime_smoke_reports_target_loss_when_representative_pool_relaunch_fails
    target = { app_path: '/Applications/SaneBar.app' }
    @qa.define_singleton_method(:runtime_smoke_representative_zone_candidates) { |_probe_target| [] }
    @qa.define_singleton_method(:ensure_runtime_smoke_target_running!) { |_probe_target| false }
    @qa.define_singleton_method(:runtime_smoke_target_process_detail) { |_probe_target| 'process detail: none' }

    error = @qa.send(:recover_runtime_smoke_candidate_pool_if_target_exited!, target, stage: 'representative setup')

    assert_includes error, 'Runtime smoke target exited during representative setup'
    assert_includes error, 'process detail: none'
  end

def test_runtime_smoke_cleanup_includes_host_exact_id_fixture
  preflight_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_preflight.rb'))
  fixture_source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_fixtures.rb'))

  assert_includes fixture_source, "def cleanup_runtime_host_exact_id_fixture!"
  assert_includes fixture_source, "killall', 'SaneBarHostExactIDFixture'"
  assert_includes fixture_source, 'for title in ["SBF-A", "SBF-B", "SBF-C", "SBF-D", "SBF-E"]'
  assert_includes fixture_source, 'item.menu = fixtureMenu(for: title)'
  assert_includes preflight_source, "cleanup_runtime_host_exact_id_fixture!"
end

def test_owned_runtime_fixture_detection_uses_exact_executable_paths
  source = qa_source

  assert_includes source, 'def owned_runtime_fixture_processes'
  assert_includes source, "Open3.capture2e('ps', 'ax', '-o', 'pid=,command=')"
  assert_includes source, 'File.realpath(path)'
  assert_includes source, "owned_runtime_fixture_process_detail(\n      'SaneBarHostExactIDFixture'"
  assert_includes source, "owned_runtime_fixture_process_detail(\n      'SaneBarVisibleDynamicHelperFixture'"
  refute_includes source, "pgrep', '-fl', 'SaneBarHostExactIDFixture'"
  refute_includes source, "pgrep', '-fl', 'SaneBarVisibleDynamicHelperFixture'"
end

  def test_startup_layout_probe_restores_state_before_marking_success
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "restore_state!\n    @state_restored = true\n\n    write_artifact!(\n      status: 'pass'"
  end

  def test_startup_layout_probe_artifact_records_mini_runtime_provenance
    source = startup_layout_probe_source

    assert_includes source, "require 'socket'"
    assert_includes source, 'runtime_provenance: runtime_provenance'
    assert_includes source, 'def runtime_provenance'
    assert_includes source, 'mini_runtime: mini_runtime_host?'
    assert_includes source, 'def mini_runtime_host?'
    assert_includes source, "Socket.gethostname.to_s.downcase.include?('mini')"
    assert_includes source, 'Socket.gethostname'
    refute_includes source, 'pid: Process.pid'
    refute_includes source, "ENV.fetch('USER'"
    refute_includes source, 'cwd: Dir.pwd'
  end

  def test_runtime_preflight_rejects_startup_probe_artifact_without_mini_runtime_provenance
    valid_artifact = {
      'app_path' => '/Applications/SaneBar.app',
      'candidate' => {
        'app_path' => '/Applications/SaneBar.app',
        'app_version' => @qa.send(:project_yml_setting, 'MARKETING_VERSION'),
        'app_build' => @qa.send(:project_yml_setting, 'CURRENT_PROJECT_VERSION')
      },
      'runtime_provenance' => {
        'mini_runtime' => true,
        'host' => 'mini',
        'generated_at' => Time.now.utc.iso8601,
        'app_path' => '/Applications/SaneBar.app'
      }
    }

    assert_nil @qa.send(:startup_probe_mini_runtime_provenance_error, valid_artifact)
    assert_includes(
      @qa.send(:startup_probe_mini_runtime_provenance_error, valid_artifact.merge('runtime_provenance' => nil)),
      'missing Mini runtime provenance'
    )
    assert_includes(
      @qa.send(:startup_probe_mini_runtime_provenance_error, valid_artifact.merge('runtime_provenance' => valid_artifact['runtime_provenance'].merge('app_path' => '/tmp/Other.app'))),
      'does not match artifact app_path'
    )
    assert_includes(
      @qa.send(:startup_probe_mini_runtime_provenance_error, valid_artifact.merge('runtime_provenance' => valid_artifact['runtime_provenance'].merge('host' => 'macbook-air'))),
      'is not the Mini'
    )
  end

  def test_runtime_preflight_rejects_wake_probe_artifact_without_mini_runtime_provenance
    valid_artifact = {
      'app_path' => '/Applications/SaneBar.app',
      'candidate' => {
        'app_path' => '/Applications/SaneBar.app',
        'app_version' => @qa.send(:project_yml_setting, 'MARKETING_VERSION'),
        'app_build' => @qa.send(:project_yml_setting, 'CURRENT_PROJECT_VERSION')
      },
      'runtime_provenance' => {
        'mini_runtime' => true,
        'host' => 'mini',
        'generated_at' => Time.now.utc.iso8601,
        'app_path' => '/Applications/SaneBar.app'
      }
    }

    assert_nil @qa.send(:wake_probe_mini_runtime_provenance_error, valid_artifact)
    assert_includes(
      @qa.send(:wake_probe_mini_runtime_provenance_error, valid_artifact.merge('runtime_provenance' => nil)),
      'missing Mini runtime provenance'
    )
    assert_includes(
      @qa.send(:wake_probe_mini_runtime_provenance_error, valid_artifact.merge('runtime_provenance' => valid_artifact['runtime_provenance'].merge('host' => 'macbook-air'))),
      'is not the Mini'
    )
  end

  def test_startup_layout_probe_prepares_post_onboarding_settings_before_first_case
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "backup_state!\n    prepare_startup_probe_settings!\n\n    run_probe_case"
    assert_includes source, 'def prepare_startup_probe_settings!'
    assert_includes source, "run_probe_case('current-width backup restore')"
    assert_includes source, "run_probe_case('#155 Always Hidden dirty replay')"
    assert_includes source, 'puts "   ↳ startup probe: #{label}"'
    assert_includes source, '@cases << result'
    assert_includes source, '@cases << partial'
    assert_includes source, 'partial[:last_snapshot] = read_layout_snapshot!'
    assert_includes source, "save_settings_json(dirty_reboot_settings(load_settings_json))"
  end

  def test_startup_layout_probe_saves_settings_with_safe_write_file
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'def save_settings_json(payload)'
    assert_includes source, 'safe_write_file(SETTINGS_PATH, JSON.pretty_generate(payload) + "\n")'
    assert_includes source, 'def safe_copy_file(source, destination)'
    assert_includes source, 'def safe_read_file(path)'
    assert_includes source, 'File.lstat(path)'
    assert_includes source, 'File::NOFOLLOW'
    refute_includes source, 'File.write(SETTINGS_PATH'
    refute_includes source, 'FileUtils.cp'
  end

  def test_startup_layout_probe_refuses_symlinked_settings_paths
    Dir.mktmpdir('sanebar-settings-symlink') do |dir|
      target = File.join(dir, 'target.json')
      symlink = File.join(dir, 'settings.json')
      destination = File.join(dir, 'backup.json')
      File.write(target, '{"autoRehide":true}')
      File.symlink(target, symlink)

      with_startup_layout_probe do |probe|
        error = assert_raises(RuntimeError) { probe.send(:safe_existing_file?, symlink) }
        assert_includes error.message, 'Unsafe symlink settings path'
        assert_raises(Errno::ELOOP, RuntimeError) { probe.send(:safe_copy_file, symlink, destination) }
        refute_path_exists destination
        assert_equal '{"autoRehide":true}', File.read(target)
      end
    end
  end

  def test_startup_layout_probe_refuses_symlinked_parent_directories
    Dir.mktmpdir('sanebar-settings-parent-symlink') do |dir|
      real_dir = File.join(dir, 'real')
      link_dir = File.join(dir, 'link')
      FileUtils.mkdir_p(real_dir)
      File.symlink(real_dir, link_dir)

      with_startup_layout_probe do |probe|
        error = assert_raises(RuntimeError) do
          probe.send(:safe_write_file, File.join(link_dir, 'settings.json'), '{"changed":true}')
        end
        assert_includes error.message, 'Unsafe symlink directory path'
        refute_path_exists File.join(real_dir, 'settings.json')

        tmp_path = File.join('/tmp', "sanebar-startup-safe-dir-#{Process.pid}.json")
        probe.send(:safe_write_file, tmp_path, '{"ok":true}')
        assert_equal '{"ok":true}', probe.send(:safe_read_file, tmp_path)
      ensure
        FileUtils.rm_f(tmp_path) if tmp_path
      end
    end
  end

  def test_runtime_preflight_refuses_symlinked_settings_paths
    Dir.mktmpdir('sanebar-runtime-settings-symlink') do |dir|
      target = File.join(dir, 'target.json')
      symlink = File.join(dir, 'settings.json')
      File.write(target, '{"autoRehide":true}')
      File.symlink(target, symlink)

      original = ProjectQA::SETTINGS_PATH
      ProjectQA.send(:remove_const, :SETTINGS_PATH)
      ProjectQA.const_set(:SETTINGS_PATH, symlink)

      error = assert_raises(RuntimeError) { @qa.send(:safe_runtime_settings_exist?) }
      assert_includes error.message, 'Unsafe symlink settings path'
      assert_raises(Errno::ELOOP, RuntimeError) { @qa.send(:safe_runtime_settings_read) }
      assert_raises(Errno::ELOOP, RuntimeError) { @qa.send(:safe_runtime_settings_write, '{"changed":true}') }
      assert_equal '{"autoRehide":true}', File.read(target)
    ensure
      ProjectQA.send(:remove_const, :SETTINGS_PATH) if ProjectQA.const_defined?(:SETTINGS_PATH)
      ProjectQA.const_set(:SETTINGS_PATH, original) if original
    end
  end

  def test_wake_layout_probe_refuses_symlinked_settings_paths
    require_relative 'wake_layout_probe'

    Dir.mktmpdir('sanebar-wake-settings-symlink') do |dir|
      target = File.join(dir, 'target.json')
      symlink = File.join(dir, 'settings.json')
      destination = File.join(dir, 'backup.json')
      File.write(target, '{"autoRehide":true}')
      File.symlink(target, symlink)

      probe = WakeLayoutProbe.new
      error = assert_raises(RuntimeError) { probe.send(:safe_existing_file?, symlink) }
      assert_includes error.message, 'Unsafe symlink settings path'
      assert_raises(Errno::ELOOP, RuntimeError) { probe.send(:safe_copy_file, symlink, destination) }
      refute_path_exists destination
      assert_equal '{"autoRehide":true}', File.read(target)
    ensure
      workspace = probe&.instance_variable_get(:@workspace)
      FileUtils.remove_entry(workspace) if workspace && File.directory?(workspace)
    end
  end

  def test_runtime_preflight_startup_probe_artifact_uses_durable_output_dir
    assert_equal(
      File.join(ProjectQA::PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.json'),
      ProjectQA::RUNTIME_STARTUP_PROBE_ARTIFACT_PATH
    )
    assert_equal(
      File.join(ProjectQA::PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.log'),
      ProjectQA::RUNTIME_STARTUP_PROBE_LOG_PATH
    )
    refute ProjectQA::RUNTIME_STARTUP_PROBE_ARTIFACT_PATH.start_with?('/tmp/')
  end

  def test_customer_ui_action_sweep_retains_runtime_artifacts_without_following_symlinks
    source = source_bundle('customer_ui_action_sweep.rb', 'customer_ui_action_sweep_*.rb')

    assert_includes source, 'def safe_regular_artifact_file?(path)'
    assert_includes source, 'safe_artifact_directory_path!(File.dirname(path))'
    assert_includes source, 'def safe_artifact_directory_path!(path)'
    assert_includes source, 'allowed_system_temp_directory_symlink?'
    assert_includes source, 'File.lstat(path)'
    assert_includes source, 'def safe_copy_artifact(source, destination)'
    assert_includes source, 'def safe_copy_artifact_content(destination, content)'
    assert_includes source, 'safe_read_artifact(path)'
    assert_includes source, 'File::NOFOLLOW'
    assert_includes source, 'IO.copy_stream(input, output)'
    assert_includes source, 'safe_copy_artifact(staged, destination)'
    assert_includes source, 'safe_copy_artifact(path, durable_path)'
    assert_includes source, 'safe_copy_artifact(path, destination)'
    assert_includes source, "File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.log')"
    refute_includes source, 'FileUtils.cp'
  end

  def test_customer_ui_action_sweep_binds_runtime_states_to_candidate_build
    source = source_bundle('customer_ui_action_sweep.rb', 'customer_ui_action_sweep_*.rb')

    assert_includes source, 'def current_runtime_candidate'
    assert_includes source, "app_path: '/Applications/SaneBar.app'"
    assert_includes source, 'app_version: @running_bundle_version'
    assert_includes source, 'app_build: @running_bundle_build'
    assert_includes source, 'if runtime_artifact && runtime_artifact[:candidate]'
    assert_includes source, "elsif id.to_s == 'resource_soak_growth'"
    assert_includes source, 'current_runtime_candidate'
    assert_includes source, 'failure_reasons << \'missing runtime candidate metadata\''
  end

  def test_startup_layout_probe_persists_restore_failures
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "unless @state_restored"
    assert_includes source, 'log("⚠️ Restore failed: #{e.message}")'
    assert_includes source, "persist_log!"
  end

  def test_startup_layout_probe_refuses_overlapping_runtime_target_lock
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "RUNTIME_TARGET_LOCK_PATH = ENV['SANEBAR_RUNTIME_TARGET_LOCK_PATH']"
    assert_includes source, "ENV['SANEMASTER_RUNTIME_PROBE_LOCK_PATH']"
    assert_includes source, "return nil if ENV['SANEBAR_RUNTIME_TARGET_LOCK_BYPASS'] == '1'"
    assert_includes source, 'flock(File::LOCK_EX | File::LOCK_NB)'
    assert_includes source, 'Startup layout probe refused to run because the SaneBar runtime target is locked'
    assert_includes source, 'status = 75'
    assert_includes source, 'StartupLayoutProbe.release_runtime_target_lock(runtime_lock)'
    assert_includes source, '$stdout.flush'
    assert_includes source, '$stderr.flush'
    assert_includes source, 'exit!(status)'
    assert_includes source, 'File::NOFOLLOW'
    assert_includes source, 'File::EXCL'
    assert_includes source, 'File.link(temp_path, RUNTIME_TARGET_LOCK_PATH)'
    assert_includes source, 'safe_write_file'
    assert_includes source, 'cleanup_runtime_target_lock_file'
    assert_includes source, 'runtime_target_lock_holder_detail'
    assert_includes source, 'FileUtils.rm_f(RUNTIME_TARGET_LOCK_PATH)'
    assert_includes source, '@direct_launch_pids = []'
    assert_includes source, '@direct_launch_pids << pid'
    assert_includes source, 'reap_direct_launch_children!'
    assert_includes source, 'Process.waitpid(pid, Process::WNOHANG)'
    assert_includes source, 'CAPTURE_LOG_OUTPUT_MAX_BYTES'
    assert_includes source, 'log_capture_output'
    assert_includes source, 'truncated_log_output'
    refute_includes source, 'Process.detach('
    refute_includes source, '/tmp/sanebar_startup_probe_launch.log'
  end

  def test_startup_layout_probe_quit_cleanup_scopes_to_staged_app_path
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, "def app_pids"
    assert_includes source, "def app_processes"
    assert_includes source, "def ensure_single_target_process!(context)"
    assert_includes source, "process_path = File.join(@app_path, 'Contents', 'MacOS', @app_name)"
    assert_includes source, "ps', '-axo', 'pid=,command='"
    assert_includes source, "command.split(/\\s+/, 2).first.to_s == process_path"
    assert_includes source, "process[:command].include?('--sane-no-keychain')"
    assert_includes source, 'terminate_lingering_app_processes_until_gone!(timeout:'
    assert_includes source, "signal: 'TERM'"
    assert_includes source, "signal: 'KILL'"
    assert_includes source, 'while app_running? && Time.now < deadline'
    assert_includes source, 'Process.kill(signal, pid)'
    refute_includes source, "pgrep', '-x', @app_name.to_s"
    assert_includes source, 'Force terminating lingering #{@app_name} test process pid=#{pid} signal=#{signal}'
  end

  def test_startup_layout_probe_requires_visible_lane_after_recovery
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'assert_restored_backup_pair!'
    assert_includes source, 'visible lane too narrow after recovery'
    assert_includes source, 'preferred_visible_lane_gap'
  end

  def test_startup_layout_probe_accepts_safe_reanchored_separator_below_backup
    with_startup_layout_probe do |probe|
      assert_nil probe.send(
        :assert_restored_backup_pair!,
        main: 144.0,
        separator: 324.0,
        backup_main: 144.0,
        backup_separator: 400.0,
        width: 1920.0,
        label: 'restored preferred positions'
      )
    end
  end

  def test_startup_layout_probe_accepts_safe_main_canonicalization_above_backup
    with_startup_layout_probe do |probe|
      assert_nil probe.send(
        :assert_restored_backup_pair!,
        main: 194.0,
        separator: 374.0,
        backup_main: 144.0,
        backup_separator: 364.0,
        width: 1920.0,
        label: 'restored preferred positions'
      )
    end
  end

  def test_startup_layout_probe_rejects_main_outside_healthy_startup_zone
    with_startup_layout_probe do |probe|
      error = assert_raises(RuntimeError) do
        probe.send(
          :assert_restored_backup_pair!,
          main: 500.0,
          separator: 680.0,
          backup_main: 144.0,
          backup_separator: 324.0,
          width: 1920.0,
          label: 'restored preferred positions'
        )
      end

      assert_includes error.message, 'main outside healthy startup zone'
    end
  end

  def test_startup_layout_probe_rejects_reanchored_separator_when_lane_is_too_narrow
    with_startup_layout_probe do |probe|
      error = assert_raises(RuntimeError) do
        probe.send(
          :assert_restored_backup_pair!,
          main: 144.0,
          separator: 260.0,
          backup_main: 144.0,
          backup_separator: 400.0,
          width: 1920.0,
          label: 'restored preferred positions'
        )
      end

      assert_includes error.message, 'visible lane too narrow after recovery'
    end
  end

  def test_startup_layout_probe_reads_recovered_autosave_namespace
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'def preferred_position_keys(version = autosave_version)'
    assert_includes source, 'main_key, separator_key = preferred_position_keys'
    assert_includes source, 'restored_main_key, restored_separator_key = preferred_position_keys'
    assert_includes source, 'replay_main_key, replay_separator_key = preferred_position_keys'
  end

  def test_startup_layout_probe_self_seeds_shared_fixture_candidates
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'ensure_preferred_always_hidden_replay_candidates!'
    assert_includes source, "require_relative 'qa'"
    assert_includes source, ':ensure_runtime_shared_bundle_fixture!'
    assert_includes source, '::axid:com.sanebar.sharedfixture.'
    refute_includes source, "item[:unique_id].to_s.include?('::statusItem:') }"
  end

  def test_startup_layout_probe_prefers_shared_fixture_candidates_before_host_sentinel
    with_startup_layout_probe do |probe|
      probe.define_singleton_method(:bundle_identifier) { 'com.sanebar.app' }
      probe.define_singleton_method(:list_icon_zones) do
        [
          {
            zone: 'hidden',
            movable: true,
            bundle: 'com.sanebar.hostsentinel',
            unique_id: 'com.sanebar.hostsentinel::statusItem:0'
          },
          {
            zone: 'hidden',
            movable: true,
            bundle: 'com.sanebar.sharedfixture',
            unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B'
          },
          {
            zone: 'visible',
            movable: true,
            bundle: 'com.sanebar.sharedfixture',
            unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A'
          }
        ]
      end

      candidates = probe.send(:preferred_always_hidden_replay_candidates)

      assert_equal [
        'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A',
        'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B'
      ], candidates.first(2).map { |candidate| candidate[:unique_id] }
    end
  end

  def test_startup_layout_probe_requires_real_pro_runtime
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'ensure_pro_unlocked_for_always_hidden_moves!'
    assert_includes source, 'paid license or active Pro trial'
    refute_includes source, "write_string_default('sane.no-keychain.com.sanebar.app.pro_license_key'"
    refute_includes source, "write_string_default('sane.no-keychain.com.sanebar.app.pro_last_validation'"
    refute_includes source, '@probe_forced_no_keychain = true'
    assert_includes source, "AUTOMATION_QUIT_TOKEN_ENV = 'SANEBAR_AUTOMATION_QUIT_TOKEN'"
    assert_includes source, 'write_automation_quit_marker!'
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
    assert_includes source, 'launched = false'
    assert_includes source, 'NO_KEYCHAIN_LAUNCH_REGISTRATION_GRACE_SECONDS'
    assert_includes source, 'target_process_ready? && layout_snapshot_available?'
    assert_includes source, "ensure_single_target_process!('layout snapshot')"
    assert_includes source, 'duplicate #{@app_name} test processes'
    refute_includes source, 'raise "Timed out waiting for #{@app_name} launch" unless app_running? && layout_snapshot_available?'
  end

  def test_startup_layout_probe_covers_dirty_reboot_recovery_contract
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'run_dirty_reboot_recovery_case'
    assert_includes source, '#157 dirty reboot recovery keeps live anchors before hiding'
    assert_includes source, 'write_current_host_bool(key, false)'
    assert_includes source, "'autoRehide' => true"
    assert_includes source, 'assert_hidden_after_auto_rehide!'
    assert_includes source, '#157 dirty startup waits for valid status-item windows before auto-hide'
    assert_includes source, 'completed_scenarios_from_cases'
  end

  def test_startup_layout_probe_covers_always_hidden_dirty_replay_contract
    source = File.read(File.join(__dir__, 'startup_layout_probe.rb'))

    assert_includes source, 'run_always_hidden_dirty_replay_outbound_case'
    assert_includes source, '#155 dirty startup AH replay allows outbound moves'
    assert_includes source, '#155 dirty startup does not give up AH replay'
    assert_includes source, '#155 dirty startup restores pinned icons into Always Hidden before outbound moves'
    assert_includes source, '#155 pinned icon exits Always Hidden after dirty startup'
    assert_includes source, '#155 Always Hidden outbound moves leave move state idle'
    assert_includes source, 'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_AFTER_155'
    assert_includes source, 'run_resource_soak_after_155!'
    assert_includes source, '#155 dirty startup resource soak remains stable after outbound moves'
    assert_includes source, '#155 outbound move state remains durable after resource soak'
    assert_includes source, '#155 hidden-exit remains Hidden after resource soak'
    assert_includes source, '#155 visible-exit remains Visible after resource soak'
    assert_includes source, 'durable_resource_soak_path'
    assert_includes source, 'ephemeral_artifact_path'
    assert_includes source, 'SANEMASTER_RESOURCE_SOAK_MIN_SECONDS'
    assert_includes source, 'FileUtils.mkdir_p(File.dirname(path))'
    assert_includes source, 'preferred_always_hidden_replay_candidates'
    assert_includes source, "preferred_bundles.include?(item[:bundle].to_s)"
    assert_includes source, 'sanitized_replay_candidate'
    assert_includes source, 'sanitized_move_result'
    assert_includes source, '#155 hidden-exit starts in AH after dirty startup'
    assert_includes source, '#155 visible-exit starts in AH after dirty startup'
    assert_includes source, 'move_icon_and_expect!'
    assert_includes source, 'assert_move_idle!'
  end

  def test_release_preflight_requires_dirty_replay_resource_soak_with_bounded_timeout
    source = File.read(File.join(__dir__, 'lib', 'project_qa_runtime_preflight.rb'))

    assert_includes source, 'startup_probe_resource_soak_required?'
    assert_includes source, "'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_AFTER_155' => '1'"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_SECONDS' => startup_resource_soak_seconds.to_s"
    assert_includes source, "'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_MIN_SECONDS' => startup_resource_soak_seconds.to_s"
    assert_includes source, 'timeout: startup_probe_timeout_seconds(startup_resource_soak_required, startup_resource_soak_seconds)'
    assert_includes source, 'return 300 unless resource_soak_required'
    assert_includes source, '[resource_soak_seconds + 300, 900].max'
    assert_includes source, '#155 dirty startup resource soak remains stable after outbound moves'
    assert_includes source, '#155 outbound move state remains durable after resource soak'
    assert_includes source, 'startup_probe_resource_soak_contract_error'
    assert_includes source, 'Startup layout probe #155 resource proof missing candidate metadata.'
    assert_includes source, 'Startup layout probe #155 resource proof did not re-check icon zones and idle move state after soak.'
    assert_includes source, 'preflight_mode?'
  end

  def test_release_preflight_validates_dirty_replay_resource_soak_artifact_contract
    Dir.mktmpdir('sanebar-155-resource-proof') do |dir|
      artifact_path = File.join(dir, 'resource-soak.json')
      log_path = File.join(dir, 'resource-soak.log')
      File.write(log_path, "status=pass\n")
      expected_version = @qa.send(:project_yml_setting, 'MARKETING_VERSION')
      expected_build = @qa.send(:project_yml_setting, 'CURRENT_PROJECT_VERSION')
      File.write(
        artifact_path,
        JSON.pretty_generate(
          'status' => 'pass',
          'candidate' => {
            'app_path' => '/Applications/SaneBar.app',
            'app_version' => expected_version,
            'app_build' => expected_build
          }
        )
      )
      startup_artifact = {
        'cases' => [
          {
            'name' => '#155 dirty startup AH replay allows outbound moves',
            'post_soak' => {
              'hidden_zone' => 'hidden',
              'visible_zone' => 'visible',
              'idle' => { 'isMoveInProgress' => false }
            },
            'resource_soak' => {
              'artifact_path' => artifact_path,
              'log_path' => log_path
            }
          }
        ]
      }

      assert_nil @qa.send(:startup_probe_resource_soak_contract_error, startup_artifact)

      startup_artifact['cases'][0]['post_soak']['visible_zone'] = 'alwaysHidden'
      assert_includes(
        @qa.send(:startup_probe_resource_soak_contract_error, startup_artifact),
        'did not re-check icon zones'
      )
    end
  end

  def test_wake_layout_probe_waits_for_launch_ready_status_items_before_actions
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, "wait_for_configured_launch_baseline(label: 'hidden launch baseline', auto_rehide: true)"
    assert_includes source, "wait_for_configured_launch_baseline(label: 'expanded launch baseline', auto_rehide: false)"
    assert_includes source, "wait_for_configured_launch_baseline(label: 'hide-all-other seeded launch baseline', auto_rehide: true)"
    assert_includes source, "'hasCompletedOnboarding' => true"
    assert_includes source, "'hasSeenFreemiumIntro' => true"
    assert_includes source, "'hasCompletedHealthWizard' => true"
    assert_includes source, "'hideAllOtherMenuBarItems' => false"
    assert_includes source, 'autoRehideEnabled did not match configured value'
    assert_includes source, "(!snapshot.key?('startupItemsValid') || truthy?(snapshot['startupItemsValid']))"
    assert_includes source, "!truthy?(snapshot['possibleSystemMenuBarSuppression'])"
    assert_includes source, 'SANEBAR_WAKE_PROBE_QUIT_TIMEOUT_SECONDS'
    assert_includes source, 'wait_for_parked_cursor!(label: label)'
    assert_includes source, 'Pointer parking did not settle after'
    assert_includes source, 'cursor_near_park_target?'
    assert_includes source, 'Passive wake recovery moved cursor'
    assert_includes source, "completed_scenario: 'passive wake recovery did not physically move the cursor'"
  end

  def test_wake_layout_probe_refuses_overlapping_runtime_target_lock
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, "RUNTIME_TARGET_LOCK_PATH = ENV['SANEBAR_RUNTIME_TARGET_LOCK_PATH']"
    assert_includes source, "ENV['SANEMASTER_RUNTIME_PROBE_LOCK_PATH']"
    assert_includes source, "return nil if ENV['SANEBAR_RUNTIME_TARGET_LOCK_BYPASS'] == '1'"
    assert_includes source, 'flock(File::LOCK_EX | File::LOCK_NB)'
    assert_includes source, 'Wake layout probe refused to run because the SaneBar runtime target is locked'
    assert_includes source, 'status = 75'
    assert_includes source, 'WakeLayoutProbe.release_runtime_target_lock(runtime_lock)'
    assert_includes source, '$stdout.flush'
    assert_includes source, '$stderr.flush'
    assert_includes source, 'exit!(status)'
    assert_includes source, 'File::NOFOLLOW'
    assert_includes source, 'File::EXCL'
    assert_includes source, 'File.link(temp_path, RUNTIME_TARGET_LOCK_PATH)'
    assert_includes source, 'safe_write_file'
    assert_includes source, 'cleanup_runtime_target_lock_file'
    assert_includes source, 'runtime_target_lock_holder_detail'
    assert_includes source, '@direct_launch_pids = []'
    assert_includes source, '@direct_launch_pids << pid'
    assert_includes source, 'reap_direct_launch_children!'
    assert_includes source, 'Process.waitpid(pid, Process::WNOHANG)'
    assert_includes source, 'CAPTURE_LOG_OUTPUT_MAX_BYTES'
    assert_includes source, 'log_capture_output'
    assert_includes source, 'truncated_log_output'
    refute_includes source, 'Process.detach('
    refute_includes source, '/tmp/sanebar_wake_probe_launch.log'
  end

  def test_wake_layout_probe_writes_fail_artifact_when_interrupted
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, 'rescue SignalException => e'
    assert_includes source, 'error: "Wake probe interrupted by #{e.class}: #{e.message}"'
    assert_includes source, 'signal: e.signo'
    assert_includes source, 'log("❌ Wake layout probe interrupted: #{e.class} #{e.message}")'
  end

  def test_wake_layout_probe_reseeds_required_visible_ids_before_wake
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, 'seed_required_visible_ids!(missing_visible)'
    assert_includes source, 'wait_for_required_visible_baseline!'
    assert_includes source, 'seed_required_visible_ids!(non_visible)'
    assert_includes source, 'def seed_required_visible_ids!'
    assert_includes source, 'move icon to visible'
    assert_includes source, 'Required visible seed failed'
    assert_includes source, 'Required visible baseline inventory unavailable'
    assert_includes source, 'zone_read_error'
    assert_includes source, 'inventory unavailable while waiting'
    assert_includes source, 'Hide-all-other seeded baseline did not settle before wake proof'
    assert_operator source.scan('wait_for_hide_all_other_zone_settle!(seeded_visible_ids)').length, :>=, 2
  end

  def test_wake_layout_probe_capture_timeout_returns_failed_status
    require_relative 'wake_layout_probe'

    probe = WakeLayoutProbe.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, status = probe.send(
      :capture,
      '/bin/sh',
      '-c',
      'sleep 2',
      timeout: 0.1
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    refute status.success?
    assert_operator elapsed, :<, 2.0
    assert_includes output, 'wake probe command timeout after 0.1s'
  end

  def test_wake_layout_probe_quit_cleanup_scopes_to_staged_app_path
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, "def app_pids"
    assert_includes source, "def app_processes"
    assert_includes source, "def ensure_single_target_process!(context)"
    assert_includes source, "process_path = File.join(@app_path, 'Contents', 'MacOS', @app_name)"
    assert_includes source, "ps', '-axo', 'pid=,command='"
    assert_includes source, "command.split(/\\s+/, 2).first.to_s == process_path"
    assert_includes source, "process[:command].include?('--sane-no-keychain')"
    assert_includes source, 'target_process_ready? && layout_snapshot_available?'
    assert_includes source, "ensure_single_target_process!('layout snapshot')"
    refute_includes source, "pgrep', '-x', @app_name.to_s"
    assert_includes source, 'terminate_lingering_app_processes_until_gone!(timeout:'
    assert_includes source, "signal: 'TERM'"
    assert_includes source, "signal: 'KILL'"
    assert_includes source, 'Process.kill(signal, pid)'
    assert_includes source, 'Force terminating lingering #{@app_name} test process pid=#{pid} signal=#{signal}'
  end

  def test_wake_layout_probe_quit_escalates_after_failed_graceful_quit
    require_relative 'wake_layout_probe'

    probe = WakeLayoutProbe.new
    failed = Object.new
    failed.define_singleton_method(:success?) { false }
    failed.define_singleton_method(:exitstatus) { 1 }
    running = true
    signals = []

    probe.instance_variable_set(:@app_name, 'SaneBar')
    probe.instance_variable_set(:@bundle_id, 'com.sanebar.app')
    probe.define_singleton_method(:app_running?) { running }
    probe.define_singleton_method(:capture) { |_cmd, *_args| ['User canceled', failed] }
    probe.define_singleton_method(:graceful_quit_timeout_seconds) { |_status| 0.0 }
    probe.define_singleton_method(:force_quit_timeout_seconds) { 0.0 }
    probe.define_singleton_method(:terminate_lingering_app_processes_until_gone!) do |timeout:, signal:|
      signals << [signal, timeout]
      running = false if signal == 'TERM'
    end
    probe.define_singleton_method(:reap_direct_launch_children!) {}

    probe.send(:quit_app)

    assert_equal [['TERM', 0.0]], signals
  end

  def test_wake_layout_probe_marks_explicit_automation_quit_before_apple_event
    require_relative 'wake_layout_probe'

    Tempfile.create('sanebar-wake-quit-marker') do |file|
      marker_path = file.path
      File.unlink(marker_path)
      old_marker = ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH']
      ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH'] = marker_path

      probe = WakeLayoutProbe.new
      succeeded = Object.new
      succeeded.define_singleton_method(:success?) { true }
      succeeded.define_singleton_method(:exitstatus) { 0 }
      running = true
      marker_seen_during_quit = false

      probe.instance_variable_set(:@app_name, 'SaneBar')
      probe.instance_variable_set(:@bundle_id, 'com.sanebar.app')
      probe.instance_variable_set(:@automation_quit_token, 'wake-token')
      probe.define_singleton_method(:app_running?) { running }
      probe.define_singleton_method(:capture) do |_cmd, *_args|
        marker_seen_during_quit = File.read(marker_path).strip == 'wake-token'
        running = false
        ['', succeeded]
      end
      probe.define_singleton_method(:terminate_lingering_app_processes_until_gone!) { |timeout:, signal:| }
      probe.define_singleton_method(:reap_direct_launch_children!) {}

      probe.send(:quit_app)

      assert marker_seen_during_quit
      refute File.exist?(marker_path), 'Wake probe should remove its explicit quit marker after cleanup'
    ensure
      ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH'] = old_marker
      FileUtils.rm_f(marker_path) if marker_path
    end
  end

  def test_wake_layout_probe_settings_are_self_contained_post_onboarding
    require_relative 'wake_layout_probe'

    settings = WakeLayoutProbe.new.send(
      :wake_probe_settings,
      {
        'autoRehide' => true,
        'hasCompletedOnboarding' => false,
        'hideAllOtherMenuBarItems' => true,
        'hideAllOtherVisibleItemIds' => ['com.example'],
        'alwaysHiddenPinnedItemIds' => ['com.example']
      },
      auto_rehide: false
    )

    assert_equal false, settings['autoRehide']
    assert_equal true, settings['hasCompletedOnboarding']
    assert_equal true, settings['hasSeenFreemiumIntro']
    assert_equal true, settings['hasCompletedHealthWizard']
    assert_equal false, settings['hideAllOtherMenuBarItems']
    assert_empty settings['hideAllOtherVisibleItemIds']
    assert_empty settings['alwaysHiddenPinnedItemIds']
  end

  def test_wake_layout_probe_uses_bounded_capture_for_probe_commands
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    refute_includes source, 'Open3.capture2e(*cmd)'
    assert_includes source, 'Open3.popen2e(*cmd)'
    assert_includes source, 'reader.report_on_exception = false'
    assert_includes source, "ENV.fetch('SANEBAR_WAKE_PROBE_COMMAND_TIMEOUT_SECONDS', '8')"
    assert_includes source, 'wake probe command timeout after'
    assert_includes source, "Process.kill('TERM', pid)"
  end

  def test_wake_layout_probe_retries_blank_icon_zone_inventory
    source = source_bundle('wake_layout_probe.rb', 'wake_layout_probe_*.rb')

    assert_includes source, 'def parse_icon_zone_rows(raw)'
    assert_includes source, 'deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS'
    assert_includes source, 'list authoritative icon zones returned no parseable rows; retrying within settle window'
    assert_includes source, 'raise "list authoritative icon zones returned no parseable rows: #{raw.inspect}"'
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

def test_runtime_smoke_icon_zone_geometry_parser_keeps_drag_source_safety
  zones = @qa.send(
    :parse_runtime_smoke_icon_zones,
    "alwaysHidden\ttrue\tcom.example.widget\twidget-id\t695.00\t22.00\t706.00\tunsafe\tWidget\n" \
      "alwaysHidden\ttrue\tcom.example.unknown\tunknown-id\tunknown\tunknown\tunknown\tunknown\tUnknown\n",
    geometry: true
  )

  assert_equal 2, zones.length
  assert_equal 'widget-id', zones[0][:unique_id]
  assert_equal 'unsafe', zones[0][:drag_source_safety]
  assert_equal 706.0, zones[0][:center_x]
  refute zones[0][:drag_source_safe]
  assert_equal 'unknown-id', zones[1][:unique_id]
  assert_equal 'unknown', zones[1][:drag_source_safety]
  assert_nil zones[1][:center_x]
  refute zones[1][:drag_source_safe]
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
  @qa.define_singleton_method(:runtime_visible_dynamic_helper_fixture_running?) { false }
  @qa.define_singleton_method(:runtime_visible_dynamic_helper_external_running?) { false }
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

def test_representative_runtime_smoke_accepts_owned_visible_dynamic_fixture
  target = { app_path: '/Applications/SaneBar.app' }
  @qa.define_singleton_method(:runtime_visible_dynamic_helper_fixture_running?) { true }
  @qa.define_singleton_method(:runtime_visible_dynamic_helper_external_running?) { false }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) do |_target|
    [
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.ameba.SwiftBar',
        unique_id: 'com.ameba.SwiftBar::statusItem:0',
        name: 'SwiftBar dynamic counter'
      }
    ]
  end

  candidates = @qa.send(:runtime_smoke_representative_zone_candidates, target)

  assert_equal ['com.ameba.SwiftBar::statusItem:0'], candidates.map { |item| item[:unique_id] }
end

def test_visible_dynamic_helper_wake_fixture_moves_owned_fixture_to_visible_before_probe
  target = { app_path: '/Applications/SaneBar.app' }
  fixture_id = 'com.ameba.SwiftBar::statusItem:0'
  zones = [
    {
      zone: 'hidden',
      movable: true,
      bundle: 'com.ameba.SwiftBar',
      unique_id: fixture_id,
      name: 'SwiftBar dynamic counter'
    }
  ]
  move_calls = []
  successful_status = Class.new do
    def success?
      true
    end
  end.new

  @qa.define_singleton_method(:runtime_visible_dynamic_helper_external_running?) { false }
  @qa.define_singleton_method(:runtime_visible_dynamic_helper_fixture_running?) { true }
  @qa.define_singleton_method(:wait_for_runtime_visible_dynamic_helper_fixture_ids) do |_target, fixture_log|
    fixture_log << "resolved_ids=#{fixture_id}"
    [fixture_id]
  end
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
  @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, identifier|
    move_calls << [command, identifier]
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.ameba.SwiftBar',
        unique_id: fixture_id,
        name: 'SwiftBar dynamic counter'
      }
    ]
    ["true\n", successful_status]
  end

  ids = @qa.send(:ensure_runtime_visible_dynamic_helper_wake_fixture!, target)

  assert_equal [fixture_id], ids
  assert_equal [['move icon to visible', fixture_id]], move_calls
end

def test_visible_dynamic_helper_wake_fixture_retries_failed_visible_move
  target = { app_path: '/Applications/SaneBar.app' }
  fixture_id = 'com.ameba.SwiftBar::statusItem:0'
  zones = [
    {
      zone: 'hidden',
      movable: true,
      bundle: 'com.ameba.SwiftBar',
      unique_id: fixture_id,
      name: 'SwiftBar dynamic counter'
    }
  ]
  move_calls = []
  status_class = Class.new do
    def initialize(success)
      @success = success
    end

    def success?
      @success
    end
  end

  @qa.define_singleton_method(:runtime_visible_dynamic_helper_external_running?) { false }
  @qa.define_singleton_method(:runtime_visible_dynamic_helper_fixture_running?) { true }
  @qa.define_singleton_method(:wait_for_runtime_visible_dynamic_helper_fixture_ids) { |_target, _fixture_log| [fixture_id] }
  @qa.define_singleton_method(:runtime_smoke_list_icon_zones) { |_target| zones }
  @qa.define_singleton_method(:runtime_smoke_move_icon) do |_target, command, identifier|
    move_calls << [command, identifier]
    if move_calls.length == 1
      ["failed\n", status_class.new(false)]
    else
      zones = [
        {
          zone: 'visible',
          movable: true,
          bundle: 'com.ameba.SwiftBar',
          unique_id: fixture_id,
          name: 'SwiftBar dynamic counter'
        }
      ]
      ["true\n", status_class.new(true)]
    end
  end

  ids = @qa.send(:ensure_runtime_visible_dynamic_helper_wake_fixture!, target)

  assert_equal [fixture_id], ids
  assert_equal(
    [['move icon to visible', fixture_id], ['move icon to visible', fixture_id]],
    move_calls
  )
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
        unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A'
      }
    ]
  end

  ids = @qa.send(
    :runtime_smoke_available_shared_bundle_candidate_ids,
    target,
    required_ids: [
      'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A',
      'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B'
    ]
  )

  assert_equal [
    'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A',
    'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B'
  ], ids
end

  def test_runtime_smoke_list_icon_zones_targets_exact_app_path
    source = qa_source

    assert_includes source, 'set appTarget to ((POSIX file "#{target[:app_path]}" as alias) as text)'
    assert_includes source, 'using terms from application id "#{expected_bundle_id}"'
    assert_includes source, "runtime_smoke_icon_zone_output(target, 'list authoritative icon zones')"
    assert_includes source, 'tell application appTarget to #{command}'
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

  def test_release_policy_guardrails_fail_before_expensive_runtime_smoke
    source = qa_source
    run_body = source[/def run\n.*?\n  private/m]

    policy_index = run_body.index('check_release_cadence_guardrails')
    runtime_index = run_body.index('check_runtime_release_smoke', policy_index)
    url_index = run_body.index('check_urls')
    policy_only_index = run_body.index('if release_policy_only_mode?')
    skip_index = run_body.index('Skipping release runtime smoke and stability suite because release policy guardrails already failed.')
    runtime_failed_skip_index = run_body.index('Skipping stability suite and URL checks because release runtime smoke failed.')

    assert policy_index && runtime_index && policy_index < runtime_index
    assert skip_index && skip_index < runtime_index
    assert runtime_failed_skip_index && runtime_index < runtime_failed_skip_index
    assert policy_only_index && policy_only_index < runtime_index
    assert url_index && policy_only_index < url_index
    assert_includes run_body, 'Checking appcast download URLs... ⏭️  skipped in policy-only mode'
    assert_includes run_body, 'Policy-only release guardrails complete; skipping runtime smoke, stability suite, and URL checks.'
    assert_includes run_body, 'Skipping stability suite and URL checks because release runtime smoke failed.'
  end

  def test_reused_customer_ui_runtime_proof_skips_duplicate_runtime_smoke_but_keeps_stability
    source = qa_source
    run_body = source[/def run\n.*?\n  private/m]

    reuse_index = run_body.index('if runtime_smoke_reused?')
    runtime_index = run_body.index('check_runtime_release_smoke', reuse_index)
    stability_index = run_body.index('run_stability_suite', reuse_index)
    url_index = run_body.index('check_urls', reuse_index)

    assert reuse_index && runtime_index && stability_index && url_index
    assert reuse_index < runtime_index
    assert runtime_index < stability_index
    assert stability_index < url_index
    assert_includes run_body, 'Running release runtime smoke... ⏭️  skipped (fresh customer UI runtime proof reused)'
    assert_includes source, 'def runtime_smoke_reused?'
    assert_includes source, "ENV['SANEPROCESS_REUSE_CUSTOMER_UI_RUNTIME_PROOF'] == '1'"
    assert_includes source, "ENV['SANEBAR_REUSE_CUSTOMER_UI_RUNTIME_PROOF'] == '1'"
  end

  def test_runtime_smoke_only_mode_refreshes_runtime_without_release_policy_gates
    source = qa_source
    run_body = source[/def run\n.*?\n  private/m]

    runtime_only_index = run_body.index('if runtime_smoke_only_mode?')
    runtime_smoke_index = run_body.index('check_runtime_release_smoke', runtime_only_index)
    syntax_index = run_body.index('check_script_syntax_swift')
    policy_index = run_body.index('check_release_cadence_guardrails')

    assert runtime_only_index && runtime_smoke_index && syntax_index && policy_index
    assert runtime_only_index < runtime_smoke_index
    assert runtime_smoke_index < syntax_index
    assert runtime_smoke_index < policy_index
    assert_includes source, "ENV['SANEPROCESS_RUNTIME_SMOKE_ONLY'] == '1'"
    assert_includes source, "ENV['SANEBAR_RUNTIME_SMOKE_ONLY'] == '1'"
    assert_includes source, 'runtime_smoke_only_mode? ||'
  end

  def test_runtime_smoke_resume_phase_runs_move_matrix_only_after_setup
    source = qa_source

    assert_includes source, 'def runtime_smoke_resume_phase'
    assert_includes source, "ENV['SANEPROCESS_RUNTIME_SMOKE_RESUME_PHASE']"
    assert_includes source, "ENV['SANEBAR_RUNTIME_SMOKE_RESUME_PHASE']"
    assert_includes source, "%w[move_matrix shared_bundle native_apple].include?(resume_phase)"
    assert_includes source, 'resuming runtime smoke at move matrix'
    assert_includes source, 'resuming runtime smoke at shared-bundle exact-ID lane'
    assert_includes source, 'resuming runtime smoke at native Apple exact-ID lane'
    assert_includes source, "runtime_passes = %w[shared_bundle native_apple].include?(resume_phase) ? 0 : RUNTIME_SMOKE_PASSES"
    assert_includes source, "unless resume_phase == 'native_apple'"
    assert_includes source, "return if resume_phase == 'shared_bundle'"
    assert_includes source, "return if resume_phase == 'native_apple'"
    assert_includes source, "'SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY' => '1'"
    assert_includes source, "'SANEBAR_SMOKE_SKIP_LAUNCH_IDLE_BUDGET' => '1'"
    assert_includes source, 'ensure_runtime_smoke_representative_zones_ready!'
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
  assert_includes source, 'Runtime smoke had no deterministic shared-bundle exact-id fixture candidates'
  assert_includes source, 'requiredIds: RUNTIME_SHARED_BUNDLE_FIXTURE_IDS'
  assert_includes source, 'Shared-bundle move regressions are release-blocking'
  refute_includes source, 'required_ids: RUNTIME_SHARED_BUNDLE_IDS'
  refute_includes source, 'requiredIds: RUNTIME_SHARED_BUNDLE_IDS'
  refute_includes source, 'shared-bundle focused smoke skipped'
end

def test_runtime_fixture_inventory_uses_bounded_applescript_refresh
  source = qa_source

  assert_includes source, 'def capture2e_with_runtime_timeout(*cmd, timeout:, label:)'
  assert_includes source, 'capture2e_with_runtime_timeout('
  assert_includes source, 'tell #{script_target} to list authoritative icon zones'
  assert_includes source, 'timeout: 8'
  assert_includes source, "label: 'AppleScript inventory'"
  assert_includes source, "label: 'AppleScript icon-zone list'"
  assert_includes source, 'label: "AppleScript icon move #{command}"'
  assert_includes source, "label: 'AppleScript dark-mode read'"
  assert_includes source, "label: 'AppleScript dark-mode write'"
  assert_includes source, 'terminate_runtime_command_child(wait_thr)'
  assert_includes source, 'Open3.popen2e(*cmd, pgroup: true)'
  assert_includes source, 'max_drain_seconds: 0.4'
  assert_includes source, "Process.kill('TERM', -wait_thr.pid)"
  assert_includes source, "Process.kill('KILL', -wait_thr.pid)"
  refute_includes source, 'def capture2e_with_runtime_inventory_timeout'
  refute_includes source, 'terminate_runtime_inventory_child'
  refute_includes source, 'Open3.capture2e(\'/usr/bin/osascript\', \'-e\', "tell #{script_target} to list authoritative icon zones")'
  refute_includes source, "Open3.capture2e('/usr/bin/osascript', '-e', script)"
  refute_includes source, 'loop { output << normalize_output_chunk(stdout_err.read_nonblock(4096)) }'
end

def test_runtime_smoke_progress_streaming_is_best_effort
  source = qa_source

  assert_includes source, 'def write_runtime_progress(chunk)'
  assert_includes source, 'return if chunk.to_s.empty? || @runtime_progress_output_closed'
  assert_includes source, 'output << chunk'
  assert_includes source, 'write_runtime_progress(chunk)'
  assert_includes source, 'rescue Errno::EPIPE, IOError'
  assert_includes source, '@runtime_progress_output_closed = true'
  refute_includes source, "print chunk\n            $stdout.flush"
end

def test_runtime_timeout_helper_returns_failed_status_on_timeout
  output, status = @qa.send(
    :capture2e_with_runtime_timeout,
    '/bin/sh',
    '-c',
    'sleep 2',
    timeout: 0.1,
    label: 'test command'
  )

  refute status.success?
  assert_includes output, 'test command timeout after 0.1s'
end

def test_runtime_timeout_helper_interrupts_chatty_output
  started_at = Time.now
  output, status = @qa.send(
    :capture2e_with_runtime_timeout,
    '/bin/sh',
    '-c',
    'while true; do printf x; sleep 0.01; done',
    timeout: 0.2,
    label: 'chatty command'
  )

  elapsed = Time.now - started_at
  refute status.success?
  assert_includes output, 'chatty command timeout after 0.2s'
  assert_operator elapsed, :<, 2.0
end

def test_focused_exact_id_runtime_smoke_uses_move_only_no_keychain_guard
  source = qa_source

    assert_includes source, "'SANEBAR_SMOKE_REQUIRE_NO_KEYCHAIN' => target[:no_keychain] ? '1' : '0'"
    assert_includes source, "'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '0'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY'] = '1'"
    refute_includes source, "else\n      focused_env['SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY'] = '1'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_PIN_REQUIRED_BROWSE_ALWAYS_HIDDEN'] = '1'"
    assert_includes source, "focused_env['SANEBAR_SMOKE_ALLOW_NOTCH_UNSAFE_REQUIRED_SKIPS'] = '1'"
    refute_includes source, "SANEBAR_SMOKE_MIN_PASSING_CANDIDATES"
    assert_includes source, 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-C'
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
