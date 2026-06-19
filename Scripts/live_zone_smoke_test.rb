#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'rbconfig'
require_relative 'live_zone_smoke'

class LiveZoneSmokeTest < Minitest::Test
  def build_smoke(required_ids: [])
    smoke = LiveZoneSmoke.allocate
    smoke.instance_variable_set(:@require_always_hidden, false)
    smoke.instance_variable_set(:@require_all_candidates, false)
    smoke.instance_variable_set(:@required_candidate_ids, required_ids)
    smoke.instance_variable_set(:@app_pid, Process.pid)
    smoke.instance_variable_set(:@active_avg_cpu_max, LiveZoneSmoke::DEFAULT_ACTIVE_AVG_CPU_MAX)
    smoke.instance_variable_set(:@active_avg_rss_mb_max, LiveZoneSmoke::DEFAULT_ACTIVE_AVG_RSS_MB_MAX)
    smoke.instance_variable_set(:@post_move_zone_stability_seconds, LiveZoneSmoke::DEFAULT_POST_MOVE_ZONE_STABILITY_SECONDS)
    smoke.send(:reset_resource_watchdog_state)
    smoke
  end

  def test_normal_candidate_pool_keeps_move_denylist
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.menuextra.focusmode',
        unique_id: 'com.apple.menuextra.focusmode::axid:7',
        name: 'Focus'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_normal_candidate_pool_excludes_menumeters_even_with_bundle_whitespace
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: ' com.yujitach.MenuMeters ',
        unique_id: 'com.yujitach.MenuMeters::statusItem:3',
        name: 'MenuMeters'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_normal_candidate_pool_excludes_unreliable_setapp_helpers
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sindresorhus.Lungo-setapp',
        unique_id: 'com.sindresorhus.Lungo-setapp::statusItem:0',
        name: 'Lungo'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.setapp.DesktopClient.SetappLauncher',
        unique_id: 'com.setapp.DesktopClient.SetappLauncher::axid:Setapp-MenuBar-Item',
        name: 'SetappLauncher'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.ameba.SwiftBar',
        unique_id: 'com.ameba.SwiftBar::statusItem:0',
        name: 'SwiftBar'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_normal_candidate_pool_excludes_codex_controller_status_item
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.openai.codex',
        unique_id: 'com.openai.codex::statusItem:0',
        name: 'Codex'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_required_candidate_bypasses_move_denylist
    required_id = 'com.apple.menuextra.focusmode::axid:7'
    smoke = build_smoke(required_ids: [required_id])
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.menuextra.focusmode',
        unique_id: required_id,
        name: 'Focus'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal [required_id], candidates.map { |candidate| candidate[:unique_id] }
  end

  def test_required_candidate_mode_rejects_single_same_bundle_fallback_before_action
    required_id = 'com.example.shared::axid:required'
    smoke = build_smoke(required_ids: [required_id])
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.shared',
      unique_id: required_id,
      name: 'Shared Item'
    }
    live_zones = [
      candidate.merge(unique_id: 'com.example.shared::axid:sibling')
    ]
    smoke.define_singleton_method(:list_icon_zones) { live_zones }

    error = assert_raises(RuntimeError) do
      smoke.send(:resolve_live_move_identifier, candidate)
    end

    assert_match(/Required exact move candidate missing before action/, error.message)
    assert_match(/requested=#{Regexp.escape(required_id)}/, error.message)
  end

  def test_required_candidate_mode_does_not_match_single_same_bundle_after_move
    required_id = 'com.example.shared::axid:required'
    smoke = build_smoke(required_ids: [required_id])
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.shared',
      unique_id: required_id,
      name: 'Shared Item'
    }
    live_zones = [
      candidate.merge(unique_id: 'com.example.shared::axid:sibling')
    ]

    matched = smoke.send(:matched_move_candidate, live_zones, required_id, candidate)

    assert_nil matched
  end

  def test_non_required_candidate_mode_keeps_single_same_bundle_fallback
    smoke = build_smoke
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.shared',
      unique_id: 'com.example.shared::axid:original',
      name: 'Shared Item'
    }
    live_zones = [
      candidate.merge(unique_id: 'com.example.shared::axid:replacement')
    ]
    smoke.define_singleton_method(:list_icon_zones) { live_zones }

    assert_equal(
      'com.example.shared::axid:replacement',
      smoke.send(:resolve_live_move_identifier, candidate)
    )
    assert_equal(
      'com.example.shared::axid:replacement',
      smoke.send(:matched_move_candidate, live_zones, candidate[:unique_id], candidate)[:unique_id]
    )
  end

  def test_top_strip_capture_uses_official_mini_gui_runner_without_raw_terminal_script
    source = File.read(File.join(__dir__, 'lib', 'live_zone_smoke_browse_visual.rb'))
    fullscreen_source = File.read(File.join(__dir__, 'lib', 'live_zone_smoke_screenshots_fullscreen.rb'))

    assert_includes source, 'capture2e_with_timeout('
    assert_includes source, 'runner,'
    assert_includes source, "'SaneBar Top Strip Capture'"
    assert_includes source, "'--log-file'"
    assert_includes source, "'--status-file'"
    assert_includes source, "'--restore-frontmost'"
    assert_includes source, "'--restore-bundle-id'"
    assert_includes source, "'--close-window'"
    assert_includes source, "'/usr/sbin/screencapture'"
    assert_includes source, "'-x'"
    assert_includes source, '"-R#{screencapture_rect}"'
    assert_includes source, 'prune_top_strip_capture_workdir!'
    assert_includes source, 'top_strip_capture_debug_details'
    assert_includes source, ".join(' && ')"
    refute_includes source, "'/usr/bin/sips'"
    refute_includes source, "'--cropOffset'"
    refute_includes source, 'screen-full-'
    refute_includes source, 'resolve_peekaboo_capture_tool'
    refute_includes source, "'--reclaim-all'"
    refute_includes source, ".join(\"\\n\")"
    assert_includes fullscreen_source, 'resolve_mini_gui_runner_tool'
    assert_includes fullscreen_source, 'mini-gui-run.sh'
    assert_includes fullscreen_source, 'assert_frontmost_probe_surface!'
    assert_includes fullscreen_source, 'transition_probe_target_index_script'
    assert_includes fullscreen_source, 'set URL of current tab of front window'
    assert_includes fullscreen_source, 'Safari probe URL did not load'
    assert_includes fullscreen_source, 'sanebar_visible_window_titles'
    assert_includes fullscreen_source, 'close_visible_sanebar_customer_windows_safely'
    assert_includes fullscreen_source, 'perform action "AXPress" of button 1 of candidateWindow'
    assert_includes fullscreen_source, 'windowSubrole is "AXSystemDialog"'
    assert_includes fullscreen_source, '(item 1 of windowSize) >= 1000'
    assert_includes fullscreen_source, '(item 2 of windowSize) <= 80'
    refute_includes source, 'capture_customer_visible_screen_via_mini_helper'
    refute_includes source, 'SANEBAR_MINI_SCREENSHOT_HELPER'
    refute_includes source, 'capture-mini-screenshot.sh'
    refute_includes source, 'tell application "Terminal"'
    refute_includes source, 'do script item 1'
    refute_includes fullscreen_source, 'make new document with properties {URL:'
    refute_includes fullscreen_source, 'close_terminal_capture_host'
  end

  def test_top_strip_capture_workdir_prune_keeps_recent_bounded_artifacts
    smoke = build_smoke

    Dir.mktmpdir('sanebar-top-strip-prune') do |dir|
      smoke.define_singleton_method(:top_strip_capture_workdir) { dir }
      old_path = File.join(dir, 'old-artifact.log')
      File.write(old_path, 'old')
      old_time = Time.now - LiveZoneSmoke::TOP_STRIP_CAPTURE_ARTIFACT_RETENTION_SECONDS - 60
      File.utime(old_time, old_time, old_path)

      newest_path = nil
      (LiveZoneSmoke::TOP_STRIP_CAPTURE_MAX_ARTIFACTS + 5).times do |index|
        path = File.join(dir, "recent-#{index}.log")
        File.write(path, index.to_s)
        file_time = Time.now - index
        File.utime(file_time, file_time, path)
        newest_path = path if index.zero?
      end

      smoke.send(:prune_top_strip_capture_workdir!)

      remaining = Dir.children(dir)
      refute_includes remaining, File.basename(old_path)
      assert_includes remaining, File.basename(newest_path)
      assert_operator remaining.length, :<=, LiveZoneSmoke::TOP_STRIP_CAPTURE_MAX_ARTIFACTS
    end
  end

  def test_top_strip_capture_retries_missing_runner_status_once
    smoke = build_smoke
    status_class = Class.new do
      def initialize(success)
        @success = success
      end

      def success?
        @success
      end
    end

    Dir.mktmpdir('sanebar-top-strip-retry') do |dir|
      output_path = File.join(dir, 'top-strip.png')
      calls = []
      smoke.define_singleton_method(:top_strip_capture_workdir) { dir }
      smoke.define_singleton_method(:resolve_mini_gui_runner_tool) { '/runner' }
      smoke.define_singleton_method(:main_display_top_strip_rect) { [0, 0, 100, 40] }
      smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| nil }
      smoke.define_singleton_method(:await_screenshot_file) do |path|
        File.exist?(path) ? path : nil
      end
      smoke.define_singleton_method(:capture2e_with_timeout) do |*args, timeout:|
        calls << [args, timeout]
        if calls.length == 1
          ['mini-gui-run: command finished without a status file', status_class.new(false)]
        else
          File.write(output_path, 'png')
          ["#{output_path}\n", status_class.new(true)]
        end
      end

      result = smoke.send(:capture_customer_visible_top_strip_via_mini_gui, 'baseline', output_path: output_path)

      assert_equal output_path, result
      assert_equal 2, calls.length
      assert_includes calls[1][0], '--status-file'
      assert_includes calls[1][0].last, '/usr/sbin/screencapture -x -R0,0,100,40'
      assert Dir.children(dir).grep(/retry2/).any?
    end
  end

  def test_top_strip_capture_can_restore_exact_probe_bundle
    smoke = build_smoke
    status_class = Class.new do
      def success?
        true
      end
    end

    Dir.mktmpdir('sanebar-top-strip-bundle-restore') do |dir|
      output_path = File.join(dir, 'top-strip.png')
      calls = []
      smoke.define_singleton_method(:top_strip_capture_workdir) { dir }
      smoke.define_singleton_method(:resolve_mini_gui_runner_tool) { '/runner' }
      smoke.define_singleton_method(:main_display_top_strip_rect) { [0, 0, 100, 40] }
      smoke.define_singleton_method(:await_screenshot_file) { |path| path }
      smoke.define_singleton_method(:capture2e_with_timeout) do |*args, timeout:|
        calls << [args, timeout]
        File.write(output_path, 'png')
        ["#{output_path}\n", status_class.new]
      end

      result = smoke.send(
        :capture_customer_visible_top_strip_via_mini_gui,
        'safari-fullscreen-enter',
        output_path: output_path,
        restore_bundle_id: 'com.apple.Safari'
      )

      assert_equal output_path, result
      assert_includes calls.first[0], '--restore-bundle-id'
      assert_includes calls.first[0], 'com.apple.Safari'
      refute_includes calls.first[0], '--restore-frontmost'
    end
  end

  def test_safari_transition_probe_uses_one_canonical_file_url
    smoke_source = File.read(File.join(__dir__, 'live_zone_smoke.rb'))
    fullscreen_source = File.read(File.join(__dir__, 'lib', 'live_zone_smoke_screenshots_fullscreen.rb'))

    assert_includes smoke_source, "VISIBLE_TRANSITION_PROBE_HTML_PATH = '/tmp/sanebar-fullscreen-probe.html'"
    assert_includes smoke_source, 'VISIBLE_TRANSITION_PROBE_URL = "file://#{VISIBLE_TRANSITION_PROBE_HTML_PATH}"'
    assert_includes fullscreen_source, 'File.write('
    assert_includes fullscreen_source, 'VISIBLE_TRANSITION_PROBE_HTML_PATH'
    assert_operator fullscreen_source.scan('VISIBLE_TRANSITION_PROBE_URL').length, :>=, 3
    refute_includes fullscreen_source, "File.join(Dir.tmpdir, 'sanebar-fullscreen-probe.html')"
    refute_includes fullscreen_source, '"file:///tmp/sanebar-fullscreen-probe.html"'
  end

  def test_capture_timeout_helper_interrupts_chatty_output
    smoke = build_smoke
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    error = assert_raises(RuntimeError) do
      smoke.send(
        :capture2e_with_timeout,
        '/bin/sh',
        '-c',
        'while true; do printf x; sleep 0.01; done',
        timeout: 0.2
      )
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 2.0
    assert_includes error.message, 'AppleScript timeout after 0.2s'
  end

  def test_capture_timeout_helper_normalizes_binary_output_chunks
    smoke = build_smoke
    out, status = smoke.send(
      :capture2e_with_timeout,
      RbConfig.ruby,
      '-e',
      'STDOUT.binmode; STDOUT.write([0xff, 0x48, 0x69].pack("C*"))',
      timeout: 2
    )

    assert status.success?
    assert out.valid_encoding?
    assert_includes out, '?Hi'
  end

  def test_probe_surface_ready_requires_expected_frontmost_bundle_and_fullscreen_state
    smoke = build_smoke
    probe = { bundle: 'com.apple.Safari' }

    assert smoke.send(
      :probe_surface_ready?,
      probe,
      fullscreen_expected: true,
      state: { 'bundleId' => 'com.apple.Safari' },
      fullscreen_states: ['true']
    )
    refute smoke.send(
      :probe_surface_ready?,
      probe,
      fullscreen_expected: true,
      state: { 'bundleId' => 'com.apple.finder' },
      fullscreen_states: ['true']
    )
    refute smoke.send(
      :probe_surface_ready?,
      probe,
      fullscreen_expected: true,
      state: { 'bundleId' => 'com.apple.Safari' },
      fullscreen_states: ['false']
    )
    assert smoke.send(
      :probe_surface_ready?,
      probe,
      fullscreen_expected: false,
      state: { 'bundleId' => 'com.apple.Safari' },
      fullscreen_states: ['false']
    )
  end

  def test_safari_transition_probe_focus_uses_existing_process_before_activation
    smoke = build_smoke
    safari_script = smoke.send(:transition_probe_focus_script, app: 'Safari', process: 'Safari')
    textedit_script = smoke.send(:transition_probe_focus_script, app: 'TextEdit', process: 'TextEdit')

    assert_includes safari_script, 'set didFocusExistingProcess to false'
    assert_includes safari_script, 'if exists process "Safari" then'
    assert_includes safari_script, 'tell process "Safari" to set frontmost to true'
    assert_includes safari_script, 'if didFocusExistingProcess is false then tell application "Safari" to activate'
    assert_equal 'tell application "TextEdit" to activate', textedit_script
  end

  def test_visible_fullscreen_transition_checks_probe_surface_before_pixel_evidence
    smoke = build_smoke
    smoke.instance_variable_set(:@require_visible_appearance_pixels, true)
    calls = []

    smoke.define_singleton_method(:open_visible_transition_probe_window) { |probe| calls << [:open, probe[:label]] }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }
    smoke.define_singleton_method(:set_fullscreen_probe_window) { |probe, enabled| calls << [:set_fullscreen, probe[:label], enabled] }
    smoke.define_singleton_method(:ensure_visible_transition_probe_window_available!) { |probe| calls << [:ensure_probe, probe[:label]] }
    smoke.define_singleton_method(:assert_fullscreen_probe_window_state!) { |probe, expected| calls << [:fullscreen_state, probe[:label], expected] }
    smoke.define_singleton_method(:assert_frontmost_probe_surface!) do |probe, label, fullscreen_expected:|
      calls << [:surface, probe[:label], label, fullscreen_expected]
    end
    smoke.define_singleton_method(:assert_appearance_overlay_hidden_after_fullscreen_settle!) { |label| calls << [:overlay_hidden, label] }
    smoke.define_singleton_method(:assert_customer_visible_top_strip_tint!) do |label, expected_visible:, restore_bundle_id: nil|
      calls << [:top_strip, label, expected_visible, restore_bundle_id]
    end
    smoke.define_singleton_method(:assert_appearance_overlay_restored_after_fullscreen_settle!) { |label| calls << [:overlay_restored, label] }
    smoke.define_singleton_method(:mark_fullscreen_matrix_scenario) { |name| calls << [:scenario, name] }
    smoke.define_singleton_method(:close_visible_transition_probe_window_safely) { |probe| calls << [:close, probe[:label]] }

    smoke.send(:exercise_visible_fullscreen_transition_pixel_check)

    safari_surface_enter = calls.index([:surface, 'safari', 'safari fullscreen enter', true])
    safari_top_strip_enter = calls.index([:top_strip, 'safari-fullscreen-enter', false, 'com.apple.Safari'])
    safari_exit_reacquire = calls.index([:ensure_probe, 'safari'])
    safari_surface_exit = calls.index([:surface, 'safari', 'safari fullscreen exit', false])
    safari_top_strip_exit = calls.index([:top_strip, 'safari-fullscreen-exit', true, 'com.apple.Safari'])

    refute_nil safari_surface_enter
    refute_nil safari_top_strip_enter
    refute_nil safari_exit_reacquire
    refute_nil safari_surface_exit
    refute_nil safari_top_strip_exit
    assert_operator safari_surface_enter, :<, safari_top_strip_enter
    assert_operator safari_top_strip_enter, :<, safari_exit_reacquire
    assert_operator safari_exit_reacquire, :<, safari_surface_exit
    assert_operator safari_surface_exit, :<, safari_top_strip_exit
  end

  def test_exit_surface_reopens_safari_probe_when_window_disappears
    smoke = build_smoke
    probe = { app: 'Safari', process: 'Safari', bundle: 'com.apple.Safari', label: 'safari' }
    calls = []
    activation_attempts = 0

    smoke.define_singleton_method(:ensure_visible_transition_probe_window_available!) do |_probe, force: false|
      calls << [:ensure_probe, force]
    end
    smoke.define_singleton_method(:activate_transition_probe_window) do |_probe|
      activation_attempts += 1
      if activation_attempts == 1
        raise 'Could not activate Safari transition probe window: No Safari target window available for fullscreen probe'
      end
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }
    smoke.define_singleton_method(:frontmost_app_state) { { 'bundleId' => 'com.apple.Safari' } }
    smoke.define_singleton_method(:fullscreen_probe_window_states) { |_probe| ['false'] }

    smoke.send(:assert_frontmost_probe_surface!, probe, 'safari fullscreen exit', fullscreen_expected: false)

    assert_equal 2, activation_attempts
    assert_includes calls, [:ensure_probe, true]
  end

  def test_exit_fullscreen_state_reopens_safari_probe_when_window_disappears
    smoke = build_smoke
    probe = { app: 'Safari', process: 'Safari', bundle: 'com.apple.Safari', label: 'safari' }
    calls = []
    reads = 0

    smoke.define_singleton_method(:ensure_visible_transition_probe_window_available!) do |_probe, force: false|
      calls << [:ensure_probe, force]
    end
    smoke.define_singleton_method(:fullscreen_probe_window_states) do |_probe|
      reads += 1
      raise 'Could not read Safari fullscreen state: No Safari fullscreen probe window' if reads == 1

      ['false']
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }

    smoke.send(:assert_fullscreen_probe_window_state!, probe, false)

    assert_equal 2, reads
    assert_includes calls, [:ensure_probe, true]
  end

  def test_exit_fullscreen_state_uses_native_toggle_when_ax_exit_does_not_settle
    smoke = build_smoke
    probe = { app: 'Safari', process: 'Safari', bundle: 'com.apple.Safari', label: 'safari' }
    states = [%w[true], %w[false]]
    calls = []

    smoke.define_singleton_method(:ensure_visible_transition_probe_window_available!) do |_probe, force: false|
      calls << [:ensure_probe, force]
    end
    smoke.define_singleton_method(:fullscreen_probe_window_states) { |_probe| states.shift || %w[false] }
    smoke.define_singleton_method(:request_fullscreen_exit_fallback!) do |_probe, attempt:|
      calls << [:exit_fallback, attempt]
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }

    smoke.send(:assert_fullscreen_probe_window_state!, probe, false)

    assert_includes calls, [:exit_fallback, 0]
  end

  def test_fullscreen_exit_fallback_uses_native_macos_shortcut_before_ax_retry
    smoke = build_smoke
    probe = { app: 'Safari', process: 'Safari', bundle: 'com.apple.Safari', label: 'safari' }
    status = Class.new do
      def success?
        true
      end
    end.new
    scripts = []
    ax_retries = []

    smoke.define_singleton_method(:capture2e_with_timeout) do |*args, timeout:|
      scripts << args.join("\n")
      ['', status]
    end
    smoke.define_singleton_method(:set_fullscreen_probe_window) do |_probe, enabled|
      ax_retries << enabled
    end

    smoke.send(:request_fullscreen_exit_fallback!, probe, attempt: 0)
    smoke.send(:request_fullscreen_exit_fallback!, probe, attempt: 1)

    assert_includes scripts.join("\n"), 'keystroke "f" using {control down, command down}'
    assert_equal [false], ax_retries
  end

  def test_disabling_fullscreen_does_not_require_stale_safari_probe_window_index
    smoke = build_smoke
    status = Class.new do
      def success?
        true
      end
    end.new
    scripts = []
    smoke.define_singleton_method(:capture2e_with_timeout) do |*args, timeout:|
      scripts << args.join("\n")
      ['', status]
    end

    smoke.send(:set_fullscreen_probe_window, { app: 'Safari', process: 'Safari' }, false)

    script = scripts.join("\n")
    assert_includes script, 'tell process "Safari" to set frontmost to true'
    assert_includes script, 'repeat with candidateWindow in windows'
    assert_includes script, 'set value of attribute "AXFullScreen" of candidateWindow to false'
    refute_includes script, 'No Safari target window available for fullscreen probe'
    refute_includes script, 'transition_probe_target_index_script'
  end

  def test_fullscreen_state_read_focuses_safari_before_reading_ax_state
    smoke = build_smoke
    status = Class.new do
      def success?
        true
      end
    end.new
    scripts = []
    smoke.define_singleton_method(:capture2e_with_timeout) do |*args, timeout:|
      scripts << args.join("\n")
      ['false', status]
    end

    assert_equal ['false'], smoke.send(:fullscreen_probe_window_states, app: 'Safari', process: 'Safari')

    script = scripts.join("\n")
    assert_includes script, 'tell process "Safari" to set frontmost to true'
    assert_includes script, 'return ((value of attribute "AXFullScreen" of targetWindow) as text)'
  end

  def test_close_settings_window_for_visual_probe_waits_for_customer_windows_to_close
    smoke = build_smoke
    titles = [['SaneBar Settings'], []]
    calls = []

    smoke.define_singleton_method(:close_settings_window_safely) { calls << :close_settings }
    smoke.define_singleton_method(:close_visible_sanebar_customer_windows_safely) { calls << :close_visible_windows }
    smoke.define_singleton_method(:sanebar_visible_window_titles) do
      calls << :read_windows
      titles.shift || []
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }

    smoke.send(:close_settings_window_for_visual_probe!, 'fullscreen setup')

    assert_equal [:close_settings, :close_visible_windows, :read_windows, [:sleep, 0.2], :read_windows], calls
  end

  def test_close_settings_window_for_visual_probe_handles_untitled_customer_windows
    smoke = build_smoke
    titles = [['<untitled>'], []]
    calls = []

    smoke.define_singleton_method(:close_settings_window_safely) { calls << :close_settings }
    smoke.define_singleton_method(:close_visible_sanebar_customer_windows_safely) { calls << :close_visible_windows }
    smoke.define_singleton_method(:sanebar_visible_window_titles) do
      calls << :read_windows
      titles.shift || []
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }

    smoke.send(:close_settings_window_for_visual_probe!, 'fullscreen setup')

    assert_equal [:close_settings, :close_visible_windows, :read_windows, [:sleep, 0.2], :read_windows], calls
  end

  def test_required_ids_require_exact_unique_id_match
    smoke = build_smoke(required_ids: ['com.apple.menuextra.siri'])
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.menuextra.siri',
        unique_id: 'com.apple.menuextra.siri::axid:3',
        name: 'Siri'
      }
    ]

    error = assert_raises(RuntimeError) { smoke.send(:selected_candidates, zones) }
    assert_includes error.message, 'Required icon(s) missing from list icon zones: com.apple.menuextra.siri'
  end

  def test_required_shared_fixture_remains_available_for_exact_id_move_smoke
    required_id = 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A'
    smoke = build_smoke(required_ids: [required_id])
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: required_id,
        name: 'SaneBarSharedFixture'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal [required_id], candidates.map { |candidate| candidate[:unique_id] }
  end

  def test_prepare_zones_reseeds_always_hidden_after_visual_checks
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible.one', unique_id: 'visible-one', name: 'Visible One' },
      { zone: 'visible', movable: true, bundle: 'com.example.visible.two', unique_id: 'visible-two', name: 'Visible Two' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.one', unique_id: 'hidden-one', name: 'Hidden One' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.two', unique_id: 'hidden-two', name: 'Hidden Two' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah.one', unique_id: 'ah-one', name: 'AH One' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah.two', unique_id: 'ah-two', name: 'AH Two' }
    ]
    calls = []

    smoke.define_singleton_method(:close_browse_panel_safely) {}
    smoke.define_singleton_method(:close_settings_window_safely) {}
    smoke.define_singleton_method(:prepare_layout_baseline) {}
    smoke.define_singleton_method(:wait_for_stable_layout_snapshot) {}
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) { zones }
    smoke.define_singleton_method(:move_and_verify) do |command, donor, expected_zone|
      calls << [command, donor[:unique_id], expected_zone]
      zones.find { |item| item[:unique_id] == donor[:unique_id] }[:zone] = expected_zone
    end

    prepared = smoke.send(:prepare_zones_for_move_checks)
    prepared_counts = smoke.send(:candidate_pool, prepared).group_by { |item| item[:zone] }.transform_values(&:length)

    assert_equal 3, prepared_counts['alwaysHidden']
    assert_equal 1, calls.length
    assert_equal 'move icon to always hidden', calls.first[0]
    assert_equal 'alwaysHidden', calls.first[2]
  end

  def test_required_ids_enable_focused_smoke_mode
    smoke = build_smoke(required_ids: ['com.apple.menuextra.focusmode'])

    assert smoke.send(:focused_required_id_mode?)
  end

  def test_matching_process_requires_no_keychain_when_requested
    smoke = build_smoke
    smoke.instance_variable_set(:@process_path, '/Applications/SaneBar.app/Contents/MacOS/SaneBar')
    smoke.instance_variable_set(:@require_no_keychain_process, true)

    assert smoke.send(
      :matching_app_process?,
      '/Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain'
    )
    refute smoke.send(
      :matching_app_process?,
      '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    )
  end

  def test_default_smoke_does_not_require_move_candidates
    smoke = build_smoke

    refute smoke.send(:move_candidates_required?)
  end

  def test_required_id_smoke_requires_move_candidates
    smoke = build_smoke(required_ids: ['com.apple.menuextra.focusmode'])

    assert smoke.send(:move_candidates_required?)
  end

  def test_all_zone_smoke_rejects_empty_always_hidden_candidate_lane
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.visible',
        unique_id: 'com.example.visible::statusItem:0',
        name: 'Visible'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.hidden',
        unique_id: 'com.example.hidden::statusItem:0',
        name: 'Hidden'
      }
    ]

    error = assert_raises(RuntimeError) do
      smoke.send(:require_representative_zone_candidates!, zones)
    end

    assert_includes error.message, 'three representative movable always-hidden candidates'
  end

  def test_all_zone_smoke_selects_three_always_hidden_candidates_for_action_matrix
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.visible',
        unique_id: 'com.example.visible::statusItem:0',
        name: 'Visible'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.hidden',
        unique_id: 'com.example.hidden::statusItem:0',
        name: 'Hidden'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.example.always',
        unique_id: 'com.example.always::statusItem:0',
        name: 'Always'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.example.always2',
        unique_id: 'com.example.always2::statusItem:0',
        name: 'Always 2'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.example.always3',
        unique_id: 'com.example.always3::statusItem:0',
        name: 'Always 3'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal %w[visible hidden alwaysHidden alwaysHidden alwaysHidden], candidates.map { |candidate| candidate[:zone] }
    assert smoke.send(:strict_candidate_mode?)
    assert smoke.send(:representative_action_matrix_mode?)
  end

  def test_all_zone_smoke_prefers_shared_fixture_for_visible_and_hidden_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.pxkan.pipit2', unique_id: 'pipit-id', name: 'Pipit' },
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'fixture-visible-id', name: 'SaneBarSharedFixture' },
      { zone: 'hidden', movable: true, bundle: 'com.apple.weather.menu', unique_id: 'weather-id', name: 'WeatherMenu' },
      { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'fixture-hidden-id', name: 'SaneBarSharedFixture' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal 'fixture-visible-id', candidates[0][:unique_id]
    assert_equal 'fixture-hidden-id', candidates[1][:unique_id]
  end

  def test_representative_action_matrix_tests_all_direct_zone_moves
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id ah2-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['move icon to visible', 'ah1-id', 'visible'],
      ['move icon to hidden', 'ah2-id', 'hidden'],
      ['hidden-visible-sequence', 'ah1-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_refreshes_live_candidates_when_visible_drops_out
    smoke = build_smoke
    stale_candidates = [
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    refreshed_candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    calls = []
    smoke.define_singleton_method(:list_icon_zones) { calls << :list_zones; refreshed_candidates }
    smoke.define_singleton_method(:require_representative_zone_candidates!) do |zones|
      calls << [:require_zones, zones]
      refreshed_candidates
    end
    smoke.define_singleton_method(:selected_candidates) do |zones|
      calls << [:selected_candidates, zones]
      refreshed_candidates
    end

    assert_same refreshed_candidates, smoke.send(:refresh_representative_move_action_matrix_candidates, stale_candidates)
    assert_equal [
      :list_zones,
      [:require_zones, refreshed_candidates],
      [:selected_candidates, refreshed_candidates]
    ], calls
  end

  def test_representative_action_matrix_reserves_shared_fixture_for_always_hidden_to_hidden
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'fixture-ah-id', name: 'SaneBarSharedFixture' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.apple.weather.menu', unique_id: 'weather-id', name: 'WeatherMenu' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id fixture-ah-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['move icon to visible', 'ah1-id', 'visible'],
      ['move icon to hidden', 'fixture-ah-id', 'hidden'],
      ['hidden-visible-sequence', 'ah1-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_stages_visible_candidate_when_ah_to_visible_candidates_fail
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:exercise_matrix_move_with_fallback) do |label, candidates_for_label, command, expected_zone|
      raise 'all AH->Visible candidates failed' if label == 'AH->Visible'

      calls << [label, candidates_for_label.first[:unique_id], command, expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidates_for_label.first[:unique_id] }
      live[:zone] = expected_zone if live
      candidates_for_label.first
    end
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[visible-id ah1-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['move icon to always hidden', 'visible-id', 'alwaysHidden'],
      ['move icon to visible', 'visible-id', 'visible'],
      ['AH->Hidden', 'ah1-id', 'move icon to hidden', 'hidden'],
      ['hidden-visible-sequence', 'visible-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_stages_hidden_candidate_when_ah_to_hidden_candidates_fail
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:exercise_matrix_move_with_fallback) do |label, candidates_for_label, command, expected_zone|
      raise 'all AH->Hidden candidates failed' if label == 'AH->Hidden'

      calls << [label, candidates_for_label.first[:unique_id], command, expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidates_for_label.first[:unique_id] }
      live[:zone] = expected_zone if live
      candidates_for_label.first
    end
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id hidden-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['AH->Visible', 'ah1-id', 'move icon to visible', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden'],
      ['move icon to hidden', 'hidden-id', 'hidden'],
      ['hidden-visible-sequence', 'ah1-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_falls_back_when_hidden_visible_candidate_fails
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
      raise 'candidate-specific visible drag failed' if candidate[:unique_id] == 'ah1-id'
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id ah2-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_includes calls, ['hidden-visible-sequence', 'ah1-id', 'visible']
    assert_includes calls, ['hidden-visible-sequence', 'visible-id', 'visible']
  end

  def test_strict_candidate_mode_can_require_minimum_passing_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@min_passing_candidates, 1)

    assert_equal 1, smoke.send(:strict_candidate_minimum, 3)
  end

  def test_exact_required_candidate_mode_ignores_minimum_passing_override
    smoke = build_smoke(required_ids: %w[required-a required-b])
    smoke.instance_variable_set(:@min_passing_candidates, 1)

    assert_equal 2, smoke.send(:strict_candidate_minimum, 2)
  end

  def test_require_all_candidates_mode_ignores_minimum_passing_override
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_candidates, true)
    smoke.instance_variable_set(:@min_passing_candidates, 1)

    assert_equal 3, smoke.send(:strict_candidate_minimum, 3)
  end

  def test_strict_candidate_mode_defaults_to_every_candidate
    smoke = build_smoke

    assert_equal 3, smoke.send(:strict_candidate_minimum, 3)
  end

  def test_representative_action_matrix_strict_minimum_uses_matrix_result
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    smoke.instance_variable_set(:@required_candidate_ids, [])
    smoke.instance_variable_set(:@require_all_candidates, false)

    assert smoke.send(:representative_action_matrix_mode?)
    assert_equal 1, smoke.send(:strict_candidate_minimum, 5)
  end

  def test_default_smoke_does_not_require_browse_activation_candidates
    smoke = build_smoke

    refute smoke.send(:browse_activation_candidates_required?)
  end

  def test_required_candidate_smoke_does_not_require_browse_activation_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@require_candidate, true)

    refute smoke.send(:browse_activation_candidates_required?)
  end

  def test_required_browse_activation_candidate_smoke_requires_browse_activation_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@require_browse_activation_candidate, true)

    assert smoke.send(:browse_activation_candidates_required?)
  end

  def test_browse_activation_candidates_prefer_precise_non_apple_before_apple_fixtures
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.precise',
        unique_id: 'com.example.precise::statusItem:2',
        name: 'Widget'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.yujitach.MenuMeters',
        unique_id: 'com.yujitach.MenuMeters::statusItem:3',
        name: 'MenuMeters'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.SSMenuAgent',
        unique_id: 'com.apple.SSMenuAgent',
        name: 'SSMenuAgent'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.Spotlight',
        unique_id: 'com.apple.menuextra.spotlight',
        name: 'Spotlight'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'com.example.precise::statusItem:2', candidate_ids.first
    assert_includes candidate_ids, 'com.yujitach.MenuMeters::statusItem:3'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
    refute_includes candidate_ids, 'com.apple.SSMenuAgent'
    refute_includes candidate_ids, 'com.apple.menuextra.spotlight'
  end

  def test_browse_activation_candidates_exclude_unreliable_setapp_helpers
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sindresorhus.Lungo-setapp',
        unique_id: 'com.sindresorhus.Lungo-setapp::statusItem:0',
        name: 'Lungo'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.setapp.DesktopClient.SetappLauncher',
        unique_id: 'com.setapp.DesktopClient.SetappLauncher::axid:Setapp-MenuBar-Item',
        name: 'SetappLauncher'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    refute_includes candidate_ids, 'com.sindresorhus.Lungo-setapp::statusItem:0'
    refute_includes candidate_ids, 'com.setapp.DesktopClient.SetappLauncher::axid:Setapp-MenuBar-Item'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_exclude_codex_controller_status_item
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.openai.codex',
        unique_id: 'com.openai.codex::statusItem:0',
        name: 'Codex'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    refute_includes candidate_ids, 'com.openai.codex::statusItem:0'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_exclude_unreliable_audio_video_extra
    smoke = build_smoke
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.audiovideo',
        name: 'Audio and Video Controls'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'findIcon',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    refute_includes candidate_ids, 'com.apple.menuextra.audiovideo'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_allow_shared_fixture
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A',
        name: 'SaneBarSharedFixture'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_includes candidate_ids, 'com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_find_icon_right_click_candidates_prefer_precise_non_apple_before_apple_fixtures
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.precise',
        unique_id: 'com.example.precise::statusItem:2',
        name: 'Widget'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.SSMenuAgent',
        unique_id: 'com.apple.SSMenuAgent',
        name: 'SSMenuAgent'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'findIcon',
      activation_command: 'right click browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'com.example.precise::statusItem:2', candidate_ids.first
    refute_includes candidate_ids, 'com.apple.SSMenuAgent'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_prefer_coarse_non_apple_before_apple_fixtures
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'org.p0deje.Maccy',
        unique_id: 'org.p0deje.Maccy',
        name: 'Maccy'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.SSMenuAgent',
        unique_id: 'com.apple.SSMenuAgent',
        name: 'SSMenuAgent'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'right click browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'org.p0deje.Maccy', candidate_ids.first
    refute_includes candidate_ids, 'com.apple.SSMenuAgent'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_focus_revert_guard_accepts_observable_successful_browse_click
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:frontmost_app_state) do
      { 'bundleId' => 'com.apple.finder', 'windowTitle' => 'Desktop' }
    end
    smoke.define_singleton_method(:current_browse_activation_diagnostics) do
      "finalOutcome: click succeeded\nwindowVisible: true\ncurrentMode: secondMenuBar"
    end

    assert_nil smoke.send(
      :assert_frontmost_did_not_revert_to,
      { 'bundleId' => 'com.apple.finder', 'windowTitle' => 'Desktop' },
      'right click browse icon'
    )
  end

  def test_browse_activation_pool_drops_coarse_duplicate_when_precise_rows_exist
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.widget',
        unique_id: 'com.example.widget',
        name: 'Widget'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.widget',
        unique_id: 'com.example.widget::statusItem:1',
        name: 'Widget'
      }
    ]

    candidates = smoke.send(:browse_activation_pool, zones)
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal ['com.example.widget::statusItem:1'], candidate_ids
  end

  def test_prepare_layout_baseline_hides_expanded_runtime
    smoke = build_smoke
    called = []

    smoke.define_singleton_method(:close_browse_panel_safely) { called << :close_browse }
    smoke.define_singleton_method(:close_settings_window_safely) { called << :close_settings }
    smoke.define_singleton_method(:park_pointer_away_from_menu_bar_safely) { called << :park_pointer }
    smoke.define_singleton_method(:layout_snapshot) { { 'hidingState' => 'expanded' } }
    smoke.define_singleton_method(:supports_applescript_command?) { |command| command == 'hide items' }
    smoke.define_singleton_method(:app_script) { |statement| called << statement }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| called << [:sleep, seconds] }

    smoke.send(:prepare_layout_baseline)

    assert_includes called, :close_browse
    assert_includes called, :close_settings
    assert_includes called, :park_pointer
    assert_includes called, 'hide items'
  end

  def test_prepare_layout_baseline_reapplies_hide_when_hidden_layout_is_unstable
    smoke = build_smoke
    called = []

    smoke.define_singleton_method(:close_browse_panel_safely) { called << :close_browse }
    smoke.define_singleton_method(:close_settings_window_safely) { called << :close_settings }
    smoke.define_singleton_method(:park_pointer_away_from_menu_bar_safely) { called << :park_pointer }
    smoke.define_singleton_method(:layout_snapshot) do
      {
        'hidingState' => 'hidden',
        'separatorBeforeMain' => true,
        'mainNearControlCenter' => false
      }
    end
    smoke.define_singleton_method(:supports_applescript_command?) { |command| command == 'hide items' }
    smoke.define_singleton_method(:app_script) { |statement| called << statement }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| called << [:sleep, seconds] }

    smoke.send(:prepare_layout_baseline)

    assert_includes called, :park_pointer
    assert_includes called, 'hide items'
  end

  def test_wait_for_stable_layout_snapshot_parks_pointer_when_menu_bar_hover_blocks_stabilization
    smoke = build_smoke
    calls = []
    snapshots = [
      {
        'hidingState' => 'hidden',
        'hoverMouseInMenuBar' => true,
        'separatorBeforeMain' => true,
        'mainNearControlCenter' => false
      },
      {
        'hidingState' => 'hidden',
        'hoverMouseInMenuBar' => false,
        'separatorBeforeMain' => true,
        'mainNearControlCenter' => true
      }
    ]

    smoke.define_singleton_method(:check_resource_watchdog!) {}
    smoke.define_singleton_method(:layout_snapshot) { snapshots.shift }
    smoke.define_singleton_method(:park_pointer_away_from_menu_bar_safely) { calls << :park_pointer }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }

    result = smoke.send(:wait_for_stable_layout_snapshot)

    assert_equal true, result['mainNearControlCenter']
    assert_equal [:park_pointer, [:sleep, LiveZoneSmoke::LAYOUT_STABILIZE_POLL_SECONDS]], calls
  end

  def test_pointer_parking_uses_cliclick_at_safe_desktop_center
    smoke = build_smoke
    status_class = Class.new do
      def success?
        true
      end
    end
    calls = []

    smoke.define_singleton_method(:resolve_cliclick_tool) { '/usr/local/bin/cliclick' }
    smoke.define_singleton_method(:desktop_bounds) { [0, 0, 1920, 1080] }
    smoke.define_singleton_method(:capture2e_with_timeout) do |*args, timeout:|
      calls << [args, timeout]
      ['', status_class.new]
    end

    assert smoke.send(:park_pointer_away_from_menu_bar_safely)
    assert_equal [[['/usr/local/bin/cliclick', 'm:960,540'], LiveZoneSmoke::APPLESCRIPT_TIMEOUT_SECONDS]], calls
  end

  def test_pointer_parking_skips_safely_without_cliclick
    smoke = build_smoke
    smoke.define_singleton_method(:resolve_cliclick_tool) { nil }
    smoke.define_singleton_method(:capture2e_with_timeout) { raise 'should not run' }

    refute smoke.send(:park_pointer_away_from_menu_bar_safely)
  end

  def test_diagnostics_reads_use_heavy_applescript_timeout
    smoke = build_smoke

    assert_equal LiveZoneSmoke::APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'browse panel diagnostics')
    assert_equal LiveZoneSmoke::APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'activation diagnostics')
  end

  def test_activation_commands_use_extended_applescript_timeout
    smoke = build_smoke

    assert_equal LiveZoneSmoke::APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'activate browse icon "com.example.app::statusItem:1"')
    assert_equal LiveZoneSmoke::APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'right click browse icon "com.example.app::statusItem:1"')
  end

  def test_transient_process_missing_is_tolerated_while_pid_is_still_alive
    smoke = build_smoke

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
    refute smoke.send(:resource_watchdog_failure)
  end

  def test_zone_api_ready_retries_empty_zone_snapshots
    smoke = build_smoke
    attempts = 0
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.ready',
        unique_id: 'com.example.ready::statusItem:0',
        name: 'Ready'
      }
    ]

    smoke.define_singleton_method(:check_resource_watchdog!) {}
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) do
      attempts += 1
      raise 'No icons returned from list icon zones.' if attempts == 1

      zones
    end

    assert_equal zones, smoke.send(:wait_for_zone_api_ready)
    assert_equal 2, attempts
  end

  def test_post_move_zone_stability_rejects_delayed_zone_drift
    smoke = build_smoke
    candidate = {
      zone: 'visible',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end

    error = assert_raises(RuntimeError) do
      smoke.send(
        :assert_zone_stays_stable_after_move,
        'com.example.widget::statusItem:0',
        candidate,
        'visible'
      )
    end
    assert_match(/Post-settle move verification drifted/, error.message)
  end

  def test_post_move_zone_stability_accepts_same_zone_after_settle
    smoke = build_smoke
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'hidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end

    assert smoke.send(
      :assert_zone_stays_stable_after_move,
      'com.example.widget::statusItem:0',
      candidate,
      'hidden'
    )
  end

  def test_move_and_verify_retries_failed_move_after_settle
    smoke = build_smoke
    candidate = {
      zone: 'alwaysHidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    calls = []
    sleeps = []
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end
    smoke.define_singleton_method(:app_script) do |statement|
      calls << statement
      raise 'AppleScript failed: Icon failed to move to hidden.' if calls.length == 1

      "true\n"
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| sleeps << seconds }
    smoke.define_singleton_method(:wait_for_move_ready_state) { true }
    smoke.define_singleton_method(:wait_for_zone) { |_icon_unique_id, _candidate, _expected_zone| true }
    smoke.define_singleton_method(:assert_zone_stays_stable_after_move) { |_icon_unique_id, _candidate, _expected_zone| true }

    smoke.send(:move_and_verify, 'move icon to hidden', candidate, 'hidden')

    assert_equal 2, calls.length
    assert_includes sleeps, 1.2
  end

  def test_move_readiness_waits_for_browse_and_menu_teardown
    smoke = build_smoke
    snapshots = [
      {
        'isMoveInProgress' => false,
        'isBrowseVisible' => true,
        'isBrowseSessionActive' => true,
        'isMenuOpen' => false
      },
      {
        'isMoveInProgress' => false,
        'isBrowseVisible' => false,
        'isBrowseSessionActive' => false,
        'isMenuOpen' => false
      }
    ]
    closed = []
    sleeps = []
    smoke.define_singleton_method(:close_browse_panel_safely) { closed << :browse }
    smoke.define_singleton_method(:close_settings_window_safely) { closed << :settings }
    smoke.define_singleton_method(:layout_snapshot) { snapshots.shift }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| sleeps << seconds }

    assert smoke.send(:wait_for_move_ready_state)
    assert_equal [:browse, :settings], closed
    assert_equal [0.25], sleeps
  end

  def test_always_hidden_outbound_move_gets_extra_settle
    smoke = build_smoke
    candidate = {
      zone: 'alwaysHidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    sleeps = []
    ready_calls = 0
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end
    smoke.define_singleton_method(:wait_for_move_ready_state) { ready_calls += 1 }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| sleeps << seconds }

    assert smoke.send(:settle_before_always_hidden_outbound_move, candidate[:unique_id], candidate, 'hidden')
    assert_includes sleeps, LiveZoneSmoke::ALWAYS_HIDDEN_OUTBOUND_SETTLE_SECONDS
    assert_equal 1, ready_calls
  end

  def test_always_hidden_inbound_move_skips_extra_settle
    smoke = build_smoke
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    smoke.define_singleton_method(:list_icon_zones) { raise 'should not inspect zones for inbound AH move' }
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| raise 'should not sleep for inbound AH move' }

    assert smoke.send(:settle_before_always_hidden_outbound_move, candidate[:unique_id], candidate, 'alwaysHidden')
  end

  def test_prepare_zones_for_move_checks_refreshes_live_zone_state
    smoke = build_smoke
    calls = []
    refreshed_zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.visible',
        unique_id: 'com.example.visible::statusItem:0',
        name: 'Visible'
      }
    ]
    verified_zones = refreshed_zones + [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.hidden',
        unique_id: 'com.example.hidden::statusItem:0',
        name: 'Hidden'
      }
    ]
    smoke.define_singleton_method(:close_browse_panel_safely) { calls << :close_browse }
    smoke.define_singleton_method(:close_settings_window_safely) { calls << :close_settings }
    smoke.define_singleton_method(:prepare_layout_baseline) { calls << :prepare_layout }
    smoke.define_singleton_method(:wait_for_stable_layout_snapshot) { calls << :wait_layout }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }
    smoke.define_singleton_method(:list_icon_zones) { calls << :list_zones; refreshed_zones }
    smoke.define_singleton_method(:require_representative_zone_candidates!) do |zones|
      calls << [:require_zones, zones]
      verified_zones
    end

    assert_same verified_zones, smoke.send(:prepare_zones_for_move_checks)
    assert_equal [
      :close_browse,
      :close_settings,
      :prepare_layout,
      :wait_layout,
      [:sleep, 1.5],
      :list_zones,
      [:require_zones, refreshed_zones]
    ], calls
  end

  def test_representative_requirement_returns_reseeded_zone_snapshot
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    stale_zones = [
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    reseeded_zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:reseed_missing_zone_candidates) { |_zones| reseeded_zones }

    returned = smoke.send(:require_representative_zone_candidates!, stale_zones)

    assert_same reseeded_zones, returned
  end

  def test_hidden_always_hidden_round_trip_uses_exact_customer_sequence
    smoke = build_smoke
    candidate = {
      zone: 'visible',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    calls = []
    smoke.define_singleton_method(:move_and_verify) do |command, move_candidate, expected_zone|
      calls << [command, move_candidate.fetch(:unique_id), expected_zone]
    end

    smoke.send(:exercise_hidden_always_hidden_round_trip, candidate)

    assert_equal [
      ['move icon to hidden', 'com.example.widget::statusItem:0', 'hidden'],
      ['move icon to always hidden', 'com.example.widget::statusItem:0', 'alwaysHidden'],
      ['move icon to hidden', 'com.example.widget::statusItem:0', 'hidden']
    ], calls
  end

  def test_launch_idle_budget_accepts_small_peak_only_cpu_spike
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:capture_resource_window) do |sample_seconds:, interval_seconds:|
      {
        avg_cpu: 3.9,
        peak_cpu: 16.9,
        avg_rss_mb: 57.6,
        peak_rss_mb: 57.6
      }
    end

    smoke.send(
      :assert_idle_budget!,
      label: 'launch',
      settle_seconds: 0,
      sample_seconds: 3.0,
      cpu_avg_max: 5.0,
      cpu_peak_max: 15.0,
      rss_mb_max: 128.0
    )
  end

  def test_launch_idle_budget_still_rejects_sustained_cpu_overrun
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:capture_resource_window) do |sample_seconds:, interval_seconds:|
      {
        avg_cpu: 5.5,
        peak_cpu: 16.9,
        avg_rss_mb: 57.6,
        peak_rss_mb: 57.6
      }
    end

    assert_raises(RuntimeError) do
      smoke.send(
        :assert_idle_budget!,
        label: 'launch',
        settle_seconds: 0,
        sample_seconds: 3.0,
        cpu_avg_max: 5.0,
        cpu_peak_max: 15.0,
        rss_mb_max: 128.0
      )
    end
  end

  def test_launch_idle_budget_can_be_skipped_for_focused_exact_id_lanes
    smoke = build_smoke
    smoke.instance_variable_set(:@skip_launch_idle_budget, true)
    called = false
    smoke.define_singleton_method(:assert_idle_budget!) do |**_kwargs|
      called = true
    end

    out, = capture_io do
      smoke.send(:check_launch_idle_budget!)
    end

    refute called
    assert_includes out, 'skipped for focused exact-ID move-only lane'
  end

  def test_post_smoke_idle_budget_accepts_rss_cache_when_physical_footprint_is_within_budget
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:capture_resource_window) do |sample_seconds:, interval_seconds:|
      {
        avg_cpu: 0.3,
        peak_cpu: 0.5,
        avg_rss_mb: 196.7,
        peak_rss_mb: 196.7
      }
    end
    smoke.define_singleton_method(:current_physical_footprint_mb) { 129.0 }

    smoke.send(
      :assert_idle_budget!,
      label: 'post-smoke',
      settle_seconds: 0,
      sample_seconds: 4.0,
      cpu_avg_max: 5.0,
      cpu_peak_max: 20.0,
      rss_mb_max: 160.0
    )
  end

  def test_active_average_budget_skips_too_few_samples
    smoke = build_smoke
    state = smoke.instance_variable_get(:@resource_watchdog_state)
    state[:sample_count] = LiveZoneSmoke::DEFAULT_ACTIVE_AVG_MIN_SAMPLES - 1
    state[:total_cpu] = 999.0
    state[:total_rss_mb] = 999.0

    smoke.send(:assert_active_average_budget!)
  end

  def test_active_average_budget_rejects_sustained_cpu_after_minimum_samples
    smoke = build_smoke
    state = smoke.instance_variable_get(:@resource_watchdog_state)
    state[:sample_count] = LiveZoneSmoke::DEFAULT_ACTIVE_AVG_MIN_SAMPLES
    state[:total_cpu] = (LiveZoneSmoke::DEFAULT_ACTIVE_AVG_CPU_MAX + 1.0) * state[:sample_count]
    state[:total_rss_mb] = 50.0 * state[:sample_count]

    assert_raises(RuntimeError) do
      smoke.send(:assert_active_average_budget!)
    end
  end

  def test_repeated_process_missing_stops_after_tolerance
    smoke = build_smoke

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
    refute smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
  end

  def test_process_missing_is_tolerated_when_same_pid_is_still_visible_in_full_process_table
    smoke = build_smoke
    smoke.define_singleton_method(:app_process_still_alive?) { false }
    smoke.define_singleton_method(:current_app_process_visible?) { true }

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
  end

  def test_process_missing_is_not_tolerated_when_pid_is_gone_everywhere
    smoke = build_smoke
    smoke.define_singleton_method(:app_process_still_alive?) { false }
    smoke.define_singleton_method(:current_app_process_visible?) { false }

    refute smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
  end

  def test_process_missing_diagnostic_includes_expected_path_and_last_sample
    smoke = build_smoke
    smoke.instance_variable_set(:@app_pid, 4242)
    smoke.instance_variable_set(:@process_path, '/Applications/SaneBar.app/Contents/MacOS/SaneBar')
    smoke.define_singleton_method(:current_matching_process_summary) { 'none' }
    state = smoke.instance_variable_get(:@resource_watchdog_state)
    state[:last_sample] = {
      pid: 4242,
      elapsed: '01:23',
      cpu: 4.2,
      rss_mb: 88.5
    }

    detail = smoke.send(:process_monitor_error_detail, RuntimeError.new('process_missing'))

    assert_includes detail, 'process_missing pid=4242'
    assert_includes detail, 'expected=/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    assert_includes detail, 'lastElapsed=01:23'
    assert_includes detail, 'lastCpu=4.2%'
    assert_includes detail, 'lastRss=88.5MB'
    assert_includes detail, 'currentMatches=none'
  end
end
