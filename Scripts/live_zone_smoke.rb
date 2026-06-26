#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
require 'time'
require 'tmpdir'

class LiveZoneSmoke
  APP_NAME = 'SaneBar'
  MAX_WAIT_SECONDS = 12
  POLL_SECONDS = 0.4
  RESOURCE_POLL_SECONDS = 1.0
  DEFAULT_MAX_CPU_PERCENT = 120.0
  DEFAULT_MAX_CPU_BREACH_SAMPLES = 4
  DEFAULT_EMERGENCY_CPU_PERCENT = 200.0
  DEFAULT_MAX_RSS_MB = 1024.0
  DEFAULT_MAX_RSS_BREACH_SAMPLES = 2
  DEFAULT_EMERGENCY_RSS_MB = 2048.0
  RESOURCE_SAMPLE_DURATION_SECONDS = 1
  RESOURCE_SAMPLE_INTERVAL_MS = 10
  DEFAULT_IDLE_SAMPLE_INTERVAL_SECONDS = 0.5
  DEFAULT_LAUNCH_IDLE_SETTLE_SECONDS = 2.0
  DEFAULT_LAUNCH_IDLE_SAMPLE_SECONDS = 3.0
  DEFAULT_LAUNCH_IDLE_CPU_AVG_MAX = 5.0
  DEFAULT_LAUNCH_IDLE_CPU_PEAK_MAX = 15.0
  DEFAULT_LAUNCH_IDLE_RSS_MB_MAX = 128.0
  # Opening browse/settings surfaces on external-display setups can leave a few
  # seconds of legitimate teardown and cache warmup before the app returns idle.
  DEFAULT_POST_SMOKE_IDLE_SETTLE_SECONDS = 15.0
  DEFAULT_POST_SMOKE_IDLE_SAMPLE_SECONDS = 4.0
  DEFAULT_POST_SMOKE_IDLE_CPU_AVG_MAX = 5.0
  DEFAULT_POST_SMOKE_IDLE_CPU_PEAK_MAX = 20.0
  DEFAULT_POST_SMOKE_IDLE_RSS_MB_MAX = 160.0
  DEFAULT_ACTIVE_AVG_CPU_MAX = 15.0
  DEFAULT_ACTIVE_AVG_RSS_MB_MAX = 192.0
  # Short focused exact-ID lanes can finish while screenshot capture and menu
  # teardown are still active. Keep peak watchdogs live for spikes, but only
  # enforce the active average once the sample window is long enough to reflect
  # sustained app behavior.
  DEFAULT_ACTIVE_AVG_MIN_SAMPLES = 15
  RESOURCE_WATCHDOG_PROCESS_MISSING_TOLERANCE = 2
  LAYOUT_STABILIZE_TIMEOUT_SECONDS = 10
  LAYOUT_STABILIZE_POLL_SECONDS = 0.25
  POINTER_PARK_MIN_MENU_BAR_CLEARANCE_Y = 240
  ZONE_API_READY_TIMEOUT_SECONDS = 25
  ZONE_API_READY_POLL_SECONDS = 0.5
  APPLESCRIPT_TIMEOUT_SECONDS = 8
  APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS = 20
  APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS = 25
  APPLESCRIPT_MOVE_TIMEOUT_SECONDS = 25
  APPLESCRIPT_RETRIES = 2
  BROWSE_PANEL_READY_TIMEOUT_SECONDS = 10
  BROWSE_PANEL_READY_POLL_SECONDS = 0.25
  BROWSE_ACTIVATION_COOLDOWN_SECONDS = 0.6
  SECOND_MENU_BAR_POST_ACTIVATION_VISIBILITY_SECONDS = 1.2
  RIGHT_CLICK_FOCUS_PROBE_SETTLE_SECONDS = 0.35
  FOCUS_PROBE_POLL_SECONDS = 0.2
  FOCUS_PROBE_TIMEOUT_SECONDS = 4.0
  FOCUS_PROBE_APP_NAME = 'Finder'
  FOCUS_PROBE_APP_BUNDLE = 'com.apple.finder'
  # Customer-visible move failures can appear only after delayed pin
  # reconciliation runs. Every runtime move must remain classified in the
  # requested zone after that settle window, not only immediately after drop.
  DEFAULT_POST_MOVE_ZONE_STABILITY_SECONDS = 2.2
  ALWAYS_HIDDEN_OUTBOUND_SETTLE_SECONDS = 5.0
  SCREENSHOT_CAPTURE_TIMEOUT_SECONDS = 20
  FULLSCREEN_APPEARANCE_SETTLE_SECONDS = 2.1
  CUSTOMER_VISIBLE_TOP_STRIP_HEIGHT = 40
  FULLSCREEN_MATRIX_ARTIFACT_PATH = '/tmp/sanebar_runtime_fullscreen_matrix.json'
  TOP_STRIP_CAPTURE_WORKDIR = '/tmp/sanebar-top-strip-capture'
  TOP_STRIP_CAPTURE_ARTIFACT_RETENTION_SECONDS = 24 * 60 * 60
  TOP_STRIP_CAPTURE_MAX_ARTIFACTS = 200
  VISIBLE_TRANSITION_PROBE_HTML_PATH = '/tmp/sanebar-fullscreen-probe.html'
  VISIBLE_TRANSITION_PROBE_URL = "file://#{VISIBLE_TRANSITION_PROBE_HTML_PATH}"
  FULLSCREEN_TRANSITION_PROBE_APPS = [
    { label: 'safari', app: 'Safari', process: 'Safari', bundle: 'com.apple.Safari', required: true },
    { label: 'textedit', app: 'TextEdit', process: 'TextEdit', bundle: 'com.apple.TextEdit', required: false }
  ].freeze
  APPLE_FALLBACK_BUNDLE_DENYLIST = %w[
    com.apple.controlcenter
    com.apple.systemuiserver
    com.apple.Spotlight
  ].freeze
  MOVE_CANDIDATE_BUNDLE_DENYLIST = (
    APPLE_FALLBACK_BUNDLE_DENYLIST + %w[
      com.apple.SSMenuAgent
      com.apple.menuextra.focusmode
      com.openai.codex
      com.setapp.DesktopClient.SetappLauncher
      com.ameba.SwiftBar
      com.sindresorhus.Lungo-setapp
      cc.ffitch.shottr
      com.yujitach.MenuMeters
      com.yonilevy.cryptoticker
    ]
  ).freeze
  MOVE_CANDIDATE_PREFERRED_BUNDLE_PREFIXES = %w[
    com.mrsane.
  ].freeze
  BROWSE_ACTIVATION_BUNDLE_DENYLIST = (
    APPLE_FALLBACK_BUNDLE_DENYLIST + %w[
      com.apple.SSMenuAgent
      com.apple.menuextra.focusmode
      com.openai.codex
      com.setapp.DesktopClient.SetappLauncher
      com.sindresorhus.Lungo-setapp
      com.yujitach.MenuMeters
    ]
  ).freeze
  BROWSE_ACTIVATION_UNRELIABLE_IDS = %w[
    com.apple.SSMenuAgent
    com.apple.menuextra.audiovideo
    com.apple.menuextra.focusmode
    com.apple.menuextra.spotlight
  ].freeze
  BROWSE_PANEL_COMMANDS = {
    'secondMenuBar' => 'show second menu bar',
    'findIcon' => 'open icon panel'
  }.freeze
  WINDOW_SCREENSHOT_TITLES = {
    'findIcon' => 'Icon Panel',
    'secondMenuBar' => nil,
    'settings' => 'SaneBar Settings'
  }.freeze
  PREFERRED_BROWSE_ACTIVATION_IDS = %w[
    com.apple.SSMenuAgent
    com.apple.menuextra.bluetooth
    com.apple.menuextra.display
    com.apple.menuextra.wifi
    com.apple.menuextra.clock
    com.apple.menuextra.spotlight
    com.apple.controlcenter
  ].freeze
  REQUIRED_REPRESENTATIVE_ZONES = %w[
    visible
    hidden
    alwaysHidden
  ].freeze
  STANDARD_APP_MENU_TITLES = %w[
    apple
    file
    edit
    view
    window
    help
  ].freeze

  def initialize
    @app_name = env_string('SANEBAR_SMOKE_APP_NAME') || APP_NAME
    @app_id = env_string('SANEBAR_SMOKE_APP_ID')
    @app_path = expand_env_path('SANEBAR_SMOKE_APP_PATH')
    @process_path = expand_env_path('SANEBAR_SMOKE_PROCESS_PATH')
    @require_no_keychain_process = ENV['SANEBAR_SMOKE_REQUIRE_NO_KEYCHAIN'] == '1'
    @watch_resources = ENV.fetch('SANEBAR_SMOKE_WATCH_RESOURCES', '1') != '0'
    @resource_poll_seconds = float_env('SANEBAR_SMOKE_RESOURCE_POLL_SECONDS') || RESOURCE_POLL_SECONDS
    @max_cpu_percent = float_env('SANEBAR_SMOKE_MAX_CPU_PERCENT') || DEFAULT_MAX_CPU_PERCENT
    @max_cpu_breach_samples = integer_env('SANEBAR_SMOKE_MAX_CPU_BREACH_SAMPLES') || DEFAULT_MAX_CPU_BREACH_SAMPLES
    @emergency_cpu_percent = float_env('SANEBAR_SMOKE_EMERGENCY_CPU_PERCENT') || DEFAULT_EMERGENCY_CPU_PERCENT
    @max_rss_mb = float_env('SANEBAR_SMOKE_MAX_RSS_MB') || DEFAULT_MAX_RSS_MB
    @max_rss_breach_samples = integer_env('SANEBAR_SMOKE_MAX_RSS_BREACH_SAMPLES') || DEFAULT_MAX_RSS_BREACH_SAMPLES
    @emergency_rss_mb = float_env('SANEBAR_SMOKE_EMERGENCY_RSS_MB') || DEFAULT_EMERGENCY_RSS_MB
    @idle_sample_interval_seconds = float_env('SANEBAR_SMOKE_IDLE_SAMPLE_INTERVAL_SECONDS') || DEFAULT_IDLE_SAMPLE_INTERVAL_SECONDS
    @launch_idle_settle_seconds = float_env('SANEBAR_SMOKE_LAUNCH_IDLE_SETTLE_SECONDS') || DEFAULT_LAUNCH_IDLE_SETTLE_SECONDS
    @launch_idle_sample_seconds = float_env('SANEBAR_SMOKE_LAUNCH_IDLE_SAMPLE_SECONDS') || DEFAULT_LAUNCH_IDLE_SAMPLE_SECONDS
    @launch_idle_cpu_avg_max = float_env('SANEBAR_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX') || DEFAULT_LAUNCH_IDLE_CPU_AVG_MAX
    @launch_idle_cpu_peak_max = float_env('SANEBAR_SMOKE_LAUNCH_IDLE_CPU_PEAK_MAX') || DEFAULT_LAUNCH_IDLE_CPU_PEAK_MAX
    @launch_idle_rss_mb_max = float_env('SANEBAR_SMOKE_LAUNCH_IDLE_RSS_MB_MAX') || DEFAULT_LAUNCH_IDLE_RSS_MB_MAX
    @skip_launch_idle_budget = ENV['SANEBAR_SMOKE_SKIP_LAUNCH_IDLE_BUDGET'] == '1'
    @post_smoke_idle_settle_seconds = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS') || DEFAULT_POST_SMOKE_IDLE_SETTLE_SECONDS
    @post_smoke_idle_sample_seconds = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS') || DEFAULT_POST_SMOKE_IDLE_SAMPLE_SECONDS
    @post_smoke_idle_cpu_avg_max = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_AVG_MAX') || DEFAULT_POST_SMOKE_IDLE_CPU_AVG_MAX
    @post_smoke_idle_cpu_peak_max = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX') || DEFAULT_POST_SMOKE_IDLE_CPU_PEAK_MAX
    @post_smoke_idle_rss_mb_max = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_RSS_MB_MAX') || DEFAULT_POST_SMOKE_IDLE_RSS_MB_MAX
    @active_avg_cpu_max = float_env('SANEBAR_SMOKE_ACTIVE_AVG_CPU_MAX') || DEFAULT_ACTIVE_AVG_CPU_MAX
    @active_avg_rss_mb_max = float_env('SANEBAR_SMOKE_ACTIVE_AVG_RSS_MB_MAX') || DEFAULT_ACTIVE_AVG_RSS_MB_MAX
    @resource_sample_path = expand_env_path('SANEBAR_SMOKE_RESOURCE_SAMPLE_PATH') || File.join(Dir.tmpdir, 'sanebar_runtime_resource_sample.txt')
    @require_always_hidden = ENV['SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN'] == '1'
    # FM-1 gate (#155/#156/#166): stage the SBF fixture into Always Hidden, drive the
    # separator into its GENUINELY hidden state (length ~10000), then issue the REAL
    # product outbound move and assert via zone delta that the icon LEFT Always Hidden
    # and STAYED there after the post-move settle. The pre-fix `length <= 1000` cap made
    # the move no-op silently; this gate fails iff the move no-ops or the icon snaps
    # back. (The gate is normally enabled default-on + release-blocking via
    # project_qa_runtime_preflight; this legacy env opt-in is still honored.)
    @require_hidden_outbound_ah = ENV['SANEBAR_SMOKE_REQUIRE_HIDDEN_OUTBOUND_AH'] == '1'
    @require_all_zones = ENV['SANEBAR_SMOKE_REQUIRE_ALL_ZONES'] == '1'
    @require_candidate = ENV['SANEBAR_SMOKE_REQUIRE_CANDIDATE'] == '1'
    @require_browse_activation_candidate = ENV['SANEBAR_SMOKE_REQUIRE_BROWSE_ACTIVATION_CANDIDATE'] == '1'
    @require_all_candidates = ENV['SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES'] == '1'
    @min_passing_candidates = integer_env('SANEBAR_SMOKE_MIN_PASSING_CANDIDATES') || 0
    @capture_screenshots = ENV.fetch('SANEBAR_SMOKE_CAPTURE_SCREENSHOTS', '1') != '0'
    @require_appearance_transitions = ENV['SANEBAR_SMOKE_REQUIRE_APPEARANCE_TRANSITIONS'] == '1'
    @require_appearance_tint_pixels = ENV['SANEBAR_SMOKE_REQUIRE_APPEARANCE_TINT_PIXELS'] == '1'
    @require_visible_appearance_pixels = ENV['SANEBAR_SMOKE_REQUIRE_VISIBLE_APPEARANCE_PIXELS'] == '1'
    @exact_id_move_only = ENV['SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY'] == '1'
    @skip_move_checks = ENV['SANEBAR_SMOKE_SKIP_MOVE_CHECKS'] == '1'
    @pin_required_browse_always_hidden = ENV['SANEBAR_SMOKE_PIN_REQUIRED_BROWSE_ALWAYS_HIDDEN'] == '1'
    @allow_notch_unsafe_required_skips = ENV['SANEBAR_SMOKE_ALLOW_NOTCH_UNSAFE_REQUIRED_SKIPS'] == '1'
    @post_move_zone_stability_seconds = float_env('SANEBAR_SMOKE_POST_MOVE_ZONE_STABILITY_SECONDS') || DEFAULT_POST_MOVE_ZONE_STABILITY_SECONDS
    @screenshot_dir = expand_env_path('SANEBAR_SMOKE_SCREENSHOT_DIR') || File.join(Dir.tmpdir, 'sanebar-smoke')
    @window_screenshot_tool = resolve_window_screenshot_tool
    @required_candidate_ids = ENV.fetch('SANEBAR_SMOKE_REQUIRED_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
    @fullscreen_matrix_scenarios = []
    @fullscreen_matrix_artifacts = []
    @supported_applescript_commands = detect_supported_applescript_commands
    reset_resource_watchdog_state
  end

  def run
    started_at = Time.now.utc
    puts '🔎 --- [ LIVE ZONE SMOKE ] ---'

    verify_single_process
    start_resource_watchdog
    prepare_layout_baseline
    snapshot = wait_for_stable_layout_snapshot
    check_layout_invariants(snapshot)
    check_always_hidden_preconditions(snapshot)
    wait_for_zone_api_ready
    check_launch_idle_budget!
    reset_resource_watchdog_window!

    zones = list_icon_zones
    zones = require_representative_zone_candidates!(zones)
    if @exact_id_move_only
      puts 'ℹ️ Focused exact-ID move-only smoke: skipping browse/settings/fullscreen visual surfaces already covered by default smoke.'
    else
      exercise_browse_modes(zones)
      zones = prepare_zones_for_move_checks
    end
    if @skip_move_checks
      puts 'ℹ️ Runtime visual smoke: skipping generic move checks; focused exact-ID lanes provide release-blocking move coverage.'
      assert_active_average_budget!
      duration = (Time.now.utc - started_at).round(2)
      assert_idle_budget!(
        label: 'post-smoke',
        settle_seconds: @post_smoke_idle_settle_seconds,
        sample_seconds: @post_smoke_idle_sample_seconds,
        cpu_avg_max: @post_smoke_idle_cpu_avg_max,
        cpu_peak_max: @post_smoke_idle_cpu_peak_max,
        rss_mb_max: @post_smoke_idle_rss_mb_max
      )
      stop_resource_watchdog
      puts resource_watchdog_report if @watch_resources
      puts "✅ Live zone smoke passed (#{duration}s)"
      return true
    end
    candidates = selected_candidates(zones)
    if candidates.empty?
      if move_candidates_required?
        raise 'No movable candidate icon found (need at least one hidden/visible icon).'
      else
        puts 'ℹ️ No movable candidate icon found on this setup; skipping move checks for this default smoke run.'
      end
    end

    failures = []
    skipped_candidates = []
    passed_candidates = []
    post_budget_restore_candidate = nil

    unless candidates.empty?
      if representative_action_matrix_mode?
        passed_candidates = exercise_representative_move_action_matrix(candidates)
      else
        candidates.each do |candidate|
          begin
            puts "🎯 Candidate: #{candidate[:name]} (#{candidate[:bundle]}) zone=#{candidate[:zone]}"
            exercise_hidden_visible_moves(candidate)
            exercise_hidden_always_hidden_round_trip(candidate)
            exercise_always_hidden_moves(candidate)
            passed_candidates << candidate
            post_budget_restore_candidate = candidate unless strict_candidate_mode?
            puts "✅ Candidate passed: #{candidate[:unique_id]}"
            break unless strict_candidate_mode?
          rescue StandardError => e
            if notch_unsafe_required_skip?(candidate, e)
              skipped_candidates << [candidate, e]
              puts "ℹ️ Candidate skipped because its live drag source is offscreen/notch-unsafe: #{candidate[:unique_id]} (#{e.message})"
            else
              failures << [candidate, e]
              puts "⚠️ Candidate failed: #{candidate[:bundle]} (#{e.message})"
            end
          ensure
            begin
              restore_zone(candidate) unless post_budget_restore_candidate&.[](:unique_id) == candidate[:unique_id]
            rescue StandardError
              # Keep trying other candidates; final failure will include last_error.
            end
          end
        end
      end

      if strict_candidate_mode?
        min_required = strict_candidate_minimum(candidates.length - skipped_candidates.length)
        if passed_candidates.length < min_required
          summary = candidate_failure_summary(failures)
          skip_summary = candidate_failure_summary(skipped_candidates)
          summary = [summary, ("Offscreen/notch-unsafe skips: #{skip_summary}" unless skip_summary.empty?)].compact.reject(&:empty?).join(' ')
          detail = summary.empty? ? '' : " Candidate failures: #{summary}"
          raise "#{passed_candidates.length}/#{min_required} candidates passed move action checks.#{detail}"
        end
        if failures.any? && @min_passing_candidates <= 0
          raise "Candidate failures: #{candidate_failure_summary(failures)}"
        elsif failures.any?
          puts "⚠️ Candidate failures tolerated after #{passed_candidates.length}/#{min_required} candidates passed: #{candidate_failure_summary(failures)}"
        end
        unless skipped_candidates.empty?
          puts "ℹ️ Offscreen/notch-unsafe required candidate skips: #{candidate_failure_summary(skipped_candidates)}"
        end
        if passed_candidates.empty?
          if all_required_candidates_skipped_as_notch_unsafe?(candidates, skipped_candidates, failures)
            puts 'ℹ️ All focused required candidates were skipped because their live drag sources are offscreen/notch-unsafe.'
          else
            raise 'No candidates passed move action checks.'
          end
        end

        puts "✅ Candidate set passed: #{passed_candidates.map { |candidate| candidate[:unique_id] }.join(', ')}"
      else
        last_failure = failures.last&.last
        raise(last_failure || 'No candidate passed move action checks.') if passed_candidates.empty?
      end
    end

    exercise_hidden_state_outbound_always_hidden_gate(zones, passed_candidates) if @require_hidden_outbound_ah

    begin
      assert_active_average_budget!
    ensure
      restore_zone(post_budget_restore_candidate) if post_budget_restore_candidate
    end
    duration = (Time.now.utc - started_at).round(2)
    assert_idle_budget!(
      label: 'post-smoke',
      settle_seconds: @post_smoke_idle_settle_seconds,
      sample_seconds: @post_smoke_idle_sample_seconds,
      cpu_avg_max: @post_smoke_idle_cpu_avg_max,
      cpu_peak_max: @post_smoke_idle_cpu_peak_max,
      rss_mb_max: @post_smoke_idle_rss_mb_max
    )
    stop_resource_watchdog
    puts resource_watchdog_report if @watch_resources
    puts "✅ Live zone smoke passed (#{duration}s)"
    true
  rescue StandardError => e
    stop_resource_watchdog
    puts resource_watchdog_report if @watch_resources
    puts "❌ Live zone smoke failed: #{e.message}"
    false
  ensure
    stop_resource_watchdog
  end

  def check_launch_idle_budget!
    if @skip_launch_idle_budget
      puts 'ℹ️ Idle budget launch: skipped for focused exact-ID move-only lane; default runtime smoke covers cold launch and watchdog/post-smoke budgets remain active.'
      return
    end

    assert_idle_budget!(
      label: 'launch',
      settle_seconds: @launch_idle_settle_seconds,
      sample_seconds: @launch_idle_sample_seconds,
      cpu_avg_max: @launch_idle_cpu_avg_max,
      cpu_peak_max: @launch_idle_cpu_peak_max,
      rss_mb_max: @launch_idle_rss_mb_max
    )
  end

  private

  def prepare_zones_for_move_checks
    close_browse_panel_safely
    close_settings_window_safely
    prepare_layout_baseline
    wait_for_stable_layout_snapshot
    sleep_with_watchdog(1.5)

    zones = list_icon_zones
    zones = seed_representative_always_hidden_candidates_for_move_checks(zones)
    zones = require_representative_zone_candidates!(zones)
    zones
  end

  def seed_representative_always_hidden_candidates_for_move_checks(zones)
    return zones unless @require_all_zones
    return zones if focused_required_id_mode?

    candidates = candidate_pool(zones)
    always_hidden_count = candidates.count { |candidate| candidate[:zone] == 'alwaysHidden' }
    return zones if always_hidden_count >= 3

    zone_counts = candidates.group_by { |candidate| candidate[:zone].to_s }.transform_values(&:length)
    attempted_donor_ids = {}

    8.times do
      candidates = candidate_pool(zones)
      always_hidden_count = candidates.count { |candidate| candidate[:zone] == 'alwaysHidden' }
      break if always_hidden_count >= 3

      zone_counts = candidates.group_by { |candidate| candidate[:zone].to_s }.transform_values(&:length)
      donor = prioritize_move_candidates(
        candidates.reject { |candidate| candidate[:zone] == 'alwaysHidden' }
                  .select { |candidate| zone_counts.fetch(candidate[:zone].to_s, 0) > 1 }
                  .reject { |candidate| attempted_donor_ids[candidate[:unique_id]] }
      ).first
      break unless donor

      attempted_donor_ids[donor[:unique_id]] = true

      begin
        puts "ℹ️ Reseeding representative Always Hidden candidate before move matrix: #{donor[:unique_id]}"
        move_and_verify('move icon to always hidden', donor, 'alwaysHidden')
        zones = list_icon_zones
      rescue StandardError => e
        puts "⚠️ Representative Always Hidden reseed failed for #{donor[:unique_id]}: #{e.message}"
      end
    end

    zones
  end

  def prepare_layout_baseline
    close_browse_panel_safely
    close_settings_window_safely
    park_pointer_away_from_menu_bar_safely

    snapshot = layout_snapshot
    return if snapshot['hidingState'] == 'hidden' && layout_invariants_satisfied?(snapshot)

    hide_command =
      if supports_applescript_command?('hide items')
        'hide items'
      elsif supports_applescript_command?('hide')
        'hide'
      end
    return unless hide_command

    app_script(hide_command)
    sleep_with_watchdog(0.35)
  rescue StandardError
    nil
  end

  def verify_single_process
    out, status = sh('ps ax -o pid=,command=')
    raise "#{@app_name} process list could not be read." unless status.success?

    matches = out.lines.map(&:strip).reject(&:empty?).each_with_object([]) do |line, result|
      pid, command = line.split(/\s+/, 2)
      next unless pid && command
      next unless matching_app_process?(command)

      result << "#{pid} #{command}"
    end

    raise "#{@app_name} is not running at #{expected_process_path || @app_name}." if matches.empty?

    if matches.length == 1
      @app_pid = matches.first.split(/\s+/, 2).first.to_i
      return
    end

    details = matches.join(' | ')
    raise "Expected 1 #{@app_name} process, found #{matches.length}: #{details}"
  end

  def layout_snapshot
    raw = app_script('layout snapshot')
    JSON.parse(raw)
  rescue JSON::ParserError
    raise "Invalid layout snapshot JSON: #{raw.inspect}"
  end

  def wait_for_stable_layout_snapshot
    deadline = Time.now + LAYOUT_STABILIZE_TIMEOUT_SECONDS
    attempts = 0
    last_snapshot = nil
    last_error = nil

    while Time.now < deadline
      attempts += 1
      check_resource_watchdog!
      begin
        last_snapshot = layout_snapshot
      rescue StandardError => e
        last_error = e
        raise unless layout_snapshot_retryable?(e)

        sleep_with_watchdog(LAYOUT_STABILIZE_POLL_SECONDS)
        next
      end
      return last_snapshot if layout_invariants_satisfied?(last_snapshot)

      park_pointer_away_from_menu_bar_safely if truthy?(last_snapshot['hoverMouseInMenuBar'])
      sleep_with_watchdog(LAYOUT_STABILIZE_POLL_SECONDS)
    end

    if last_error
      raise "Layout did not stabilize in #{LAYOUT_STABILIZE_TIMEOUT_SECONDS}s (attempts=#{attempts}, last_error=#{last_error.message}, snapshot=#{last_snapshot})"
    end

    raise "Layout did not stabilize in #{LAYOUT_STABILIZE_TIMEOUT_SECONDS}s (attempts=#{attempts}, snapshot=#{last_snapshot})"
  end

  def park_pointer_away_from_menu_bar_safely
    cliclick = resolve_cliclick_tool
    return false unless cliclick

    x, y = pointer_parking_coordinate
    out, status = capture2e_with_timeout(cliclick, "m:#{x},#{y}", timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    return true if status&.success?

    debug_cursor_park_skip("cliclick failed: #{out.strip}")
    false
  rescue StandardError => e
    debug_cursor_park_skip(e.message)
    false
  end

  def resolve_cliclick_tool
    ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick'].find { |path| File.executable?(path) }
  end

  def pointer_parking_coordinate
    values = desktop_bounds
    x1, y1, x2, y2 = values
    width = x2 - x1
    height = y2 - y1
    raise "Invalid desktop bounds for pointer parking: #{values.inspect}" unless width.positive? && height.positive?

    x = x1 + (width / 2)
    y = y1 + (height / 2)
    min_y = y1 + POINTER_PARK_MIN_MENU_BAR_CLEARANCE_Y
    y = min_y if y < min_y
    y = y2 - 10 if y >= y2
    [x, y]
  end

  def desktop_bounds
    # Finder's "bounds of window of desktop" can hang indefinitely on some macOS
    # builds (Stage Manager / Spaces / notch state), blowing APPLESCRIPT_TIMEOUT
    # and failing the smoke even though SaneBar is healthy. Read the main screen
    # frame via AppKit instead (instant, notch-safe); fall back to Finder only if
    # AppKit/JXA is unavailable.
    jxa = 'ObjC.import("AppKit"); var f = $.NSScreen.mainScreen.frame; ' \
          '"0 0 " + Math.round(f.size.width) + " " + Math.round(f.size.height)'
    out, status = capture2e_with_timeout('/usr/bin/osascript', '-l', 'JavaScript', '-e', jxa,
                                          timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    if status&.success?
      values = out.scan(/-?\d+/).map(&:to_i)
      return values.first(4) if values.length >= 4
    end

    script = 'tell application "Finder" to get bounds of window of desktop'
    out, status = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "Could not read desktop bounds for pointer parking: #{out.strip}" unless status&.success?

    values = out.scan(/-?\d+/).map(&:to_i)
    raise "Unexpected desktop bounds for pointer parking: #{out.inspect}" unless values.length >= 4

    values.first(4)
  end

  def debug_cursor_park_skip(message)
    return unless ENV['SANEBAR_SMOKE_DEBUG_CURSOR_PARK'] == '1'

    puts "⚠️ Cursor park skipped: #{message}"
  end

  def check_layout_invariants(snapshot)
    raise "Layout invariant failed after stabilization (snapshot=#{snapshot})" unless layout_invariants_satisfied?(snapshot)

    puts '✅ Layout invariants ok: separator/main order and launch proximity'
  end

  def check_always_hidden_preconditions(snapshot)
    return unless @require_always_hidden
    return if truthy?(snapshot['licenseIsPro'])

    raise 'Always Hidden smoke requires a Pro-enabled target (licenseIsPro=false).'
  end

  def layout_invariants_satisfied?(snapshot)
    return false unless truthy?(snapshot['separatorBeforeMain'])

    if truthy?(snapshot['alwaysHiddenGeometryReliable'])
      return false unless truthy?(snapshot['alwaysHiddenBeforeSeparator'])
    end

    truthy?(snapshot['mainNearControlCenter'])
  end

  def list_icon_zones
    raw = list_icon_zones_raw
    parser = icon_zone_geometry_listing_supported? ? :parse_icon_zone_geometry_line : :parse_legacy_icon_zone_line
    zones = raw.lines.map do |line|
      send(parser, line)
    end.compact

    raise 'No icons returned from list icon zones.' if zones.empty?

    zones
  end

  def list_icon_zones_raw
    command = icon_zone_geometry_listing_supported? ? 'list icon zone geometry' : 'list icon zones'
    app_script(command)
  end

  def icon_zone_geometry_listing_supported?
    Array(@supported_applescript_commands).include?('list icon zone geometry')
  end

  def parse_legacy_icon_zone_line(line)
    zone, movable, bundle, unique_id, name = line.strip.split("\t", 5)
    return nil if zone.nil? || unique_id.nil?

    {
      zone: zone,
      movable: movable == 'true',
      bundle: bundle.to_s,
      unique_id: unique_id,
      name: name.to_s
    }
  end

  def parse_icon_zone_geometry_line(line)
    zone, movable, bundle, unique_id, x_position, width, center_x, drag_source_safety, name = line.strip.split("\t", 9)
    return nil if zone.nil? || unique_id.nil?

    parse_legacy_icon_zone_line([zone, movable, bundle, unique_id, name].join("\t")).merge(
      x_position: parse_optional_float(x_position),
      width: parse_optional_float(width),
      center_x: parse_optional_float(center_x),
      drag_source_safety: drag_source_safety.to_s,
      drag_source_safe: drag_source_safe?(drag_source_safety)
    )
  end

  def parse_optional_float(value)
    return nil if value.to_s.empty? || value.to_s == 'unknown'

    Float(value)
  rescue ArgumentError
    nil
  end

  def wait_for_zone_api_ready
    deadline = Time.now + ZONE_API_READY_TIMEOUT_SECONDS
    last_error = nil

    while Time.now < deadline
      begin
        check_resource_watchdog!
        zones = list_icon_zones
        return zones unless zones.empty?
      rescue StandardError => e
        last_error = e
        raise unless zone_api_retryable?(e)
      end

      sleep_with_watchdog(ZONE_API_READY_POLL_SECONDS)
    end

    raise "Zone API did not become ready in #{ZONE_API_READY_TIMEOUT_SECONDS}s#{last_error ? " (last error: #{last_error.message})" : ''}"
  end

  def candidate_pool(zones, allow_denylisted: false)
    raw_candidates = zones.select do |item|
      item[:movable] &&
        !item[:bundle].start_with?('com.sanebar.app') &&
        %w[hidden visible alwaysHidden].include?(item[:zone])
    end
    excluded_app_menu_bundles = app_menu_bundle_ids(raw_candidates)
    candidates = raw_candidates.reject do |item|
      likely_standard_app_menu_candidate?(item) ||
        excluded_app_menu_bundles.include?(item[:bundle].to_s.downcase)
    end
    precise_bundles = candidates.reject { |item| coarse_bundle_fallback?(item) }.map { |item| item[:bundle] }.uniq
    candidates.reject! do |item|
      coarse_bundle_fallback?(item) && precise_bundles.include?(item[:bundle])
    end
    candidates.reject! { |item| move_candidate_denied?(item) } unless allow_denylisted
    unless representative_action_matrix_mode? || (focused_required_id_mode? && @allow_notch_unsafe_required_skips)
      candidates.reject! { |item| unsafe_always_hidden_drag_source?(item) }
    end

    # Prefer non-Apple extras first (typically more consistently movable),
    # then Apple fallbacks while avoiding known noisy bundles.
    preferred = candidates.reject { |item| item[:bundle].start_with?('com.apple.') }
    apple_fallback = candidates.select do |item|
      item[:bundle].start_with?('com.apple.') &&
        !APPLE_FALLBACK_BUNDLE_DENYLIST.include?(item[:bundle])
    end
    denied = candidates.select { |item| APPLE_FALLBACK_BUNDLE_DENYLIST.include?(item[:bundle]) }

    ordered = preferred + apple_fallback + denied
    zone_priority = if @require_always_hidden
                      { 'alwaysHidden' => 0, 'hidden' => 1, 'visible' => 2 }
                    else
                      { 'hidden' => 0, 'visible' => 1, 'alwaysHidden' => 2 }
                    end
    ordered.sort_by { |item| zone_priority.fetch(item[:zone], 3) }
  end

  def browse_activation_pool(zones)
    raw_candidates = zones.select do |item|
      item[:movable] &&
        !item[:bundle].start_with?('com.sanebar.app') &&
        %w[hidden visible].include?(item[:zone])
    end
    excluded_app_menu_bundles = app_menu_bundle_ids(raw_candidates)
    candidates = raw_candidates.reject do |item|
      likely_standard_app_menu_candidate?(item) ||
        excluded_app_menu_bundles.include?(item[:bundle].to_s.downcase)
    end
    precise_bundles = candidates.reject { |item| coarse_bundle_fallback?(item) }.map { |item| item[:bundle] }.uniq
    candidates.reject! do |item|
      coarse_bundle_fallback?(item) && precise_bundles.include?(item[:bundle])
    end
    candidates
  end

  def compact_precise_non_apple_bundle_candidates(candidates)
    seen_precise_non_apple_bundles = {}

    candidates.each_with_object([]) do |item, compacted|
      bundle = item[:bundle].to_s
      precise_non_apple = !bundle.start_with?('com.apple.') && !coarse_bundle_fallback?(item)

      if precise_non_apple
        next if seen_precise_non_apple_bundles[bundle]

        seen_precise_non_apple_bundles[bundle] = true
      end

      compacted << item
    end
  end

  def move_candidate_denied?(item)
    bundle = item[:bundle].to_s.strip.downcase
    MOVE_CANDIDATE_BUNDLE_DENYLIST.any? { |value| value.downcase == bundle }
  end

  def unsafe_always_hidden_drag_source?(item)
    item[:zone].to_s == 'alwaysHidden' && item.key?(:drag_source_safety) && !drag_source_safe?(item[:drag_source_safety])
  end

  def preferred_move_candidate_rank(bundle)
    bundle = bundle.to_s.downcase
    return 0 if bundle == 'com.sanebar.sharedfixture'
    return 0 if MOVE_CANDIDATE_PREFERRED_BUNDLE_PREFIXES.any? { |prefix| bundle.start_with?(prefix) }

    1
  end

  def app_menu_bundle_ids(candidates)
    candidates.group_by { |item| item[:bundle].to_s.downcase }.each_with_object([]) do |(bundle, bundle_candidates), excluded|
      next if bundle.empty? || bundle.start_with?('com.apple.')

      titles = bundle_candidates.map { |candidate| candidate[:name].to_s.strip.downcase }
      excluded << bundle if (titles & STANDARD_APP_MENU_TITLES).length >= 3
    end
  end

  def likely_standard_app_menu_candidate?(item)
    title = item[:name].to_s.strip.downcase
    return false unless STANDARD_APP_MENU_TITLES.include?(title)

    identifier = item[:unique_id].to_s.downcase
    bundle = item[:bundle].to_s.downcase
    !bundle.start_with?('com.apple.') && (identifier.include?('.menuextra.') || identifier.include?('::axid:'))
  end

  def selected_candidates(zones)
    ordered = candidate_pool(zones, allow_denylisted: !@required_candidate_ids.empty?)
    return representative_zone_candidates(ordered) if @required_candidate_ids.empty? && @require_all_zones
    return prioritize_move_candidates(ordered) if @required_candidate_ids.empty?

    selected = @required_candidate_ids.map do |required_id|
      resolve_required_candidate(required_id, ordered)
    end

    missing_ids = @required_candidate_ids.zip(selected).map do |required_id, candidate|
      required_id if candidate.nil?
    end.compact
    raise "Required icon(s) missing from list icon zones: #{missing_ids.join(', ')}" unless missing_ids.empty?

    selected
  end

  def prioritize_move_candidates(candidates)
    candidates.sort_by do |item|
      [
        preferred_move_candidate_rank(item[:bundle]),
        item[:bundle].start_with?('com.apple.') ? 1 : 0,
        coarse_bundle_fallback?(item) ? 1 : 0,
        item[:name].to_s.downcase
      ]
    end
  end

  REPRESENTATIVE_ZONE_MINIMUMS = {
    'alwaysHidden' => 3,
    'hidden' => 1,
    'visible' => 1
  }.freeze

  REPRESENTATIVE_ZONE_MOVE_COMMANDS = {
    'alwaysHidden' => 'move icon to always hidden',
    'hidden' => 'move icon to hidden',
    'visible' => 'move icon to visible'
  }.freeze

  # Deterministic shared-fixture (SBF) bundle used to self-heal the representative
  # baseline from any drifted starting layout. The preflight seeds these, but
  # repeated probe runs can shuffle every movable SBF item into hidden/always
  # hidden, leaving a zone with zero movable candidates. Rather than abort the
  # release-blocking gate at its own precondition, reset the SBF icons into a
  # canonical per-zone layout (using the same move path the smoke already uses)
  # before checking the precondition.
  SHARED_FIXTURE_BUNDLE_ID = 'com.sanebar.sharedfixture'
  # Canonical destination zone for each ordered SBF fixture. This satisfies the
  # representative minimums exactly: visible>=1, hidden>=1, alwaysHidden>=3.
  SHARED_FIXTURE_CANONICAL_ZONE_PLAN = %w[
    visible
    hidden
    alwaysHidden
    alwaysHidden
    alwaysHidden
  ].freeze
  SHARED_FIXTURE_RESET_MAX_PASSES = 3

  # The preflight seeds every zone, but later phases can shuffle the fixtures
  # out of one (all real items in it being deny-listed donors). Self-heal by
  # moving a surplus donor into the missing zone before concluding; the hard
  # checks below still fail the release if reseeding cannot converge.
  def reseed_missing_zone_candidates(zones)
    skipped_reseed_donor_ids = []
    6.times do
      candidates = candidate_pool(zones)
      counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
      missing = REQUIRED_REPRESENTATIVE_ZONES.select do |zone|
        counts.fetch(zone, 0) < REPRESENTATIVE_ZONE_MINIMUMS.fetch(zone, 1)
      end
      break if missing.empty?

      donor_moved = false
      missing.each do |zone|
        donor = prioritize_reseed_donors(
          zone,
          candidates.select do |item|
            donor_zone = item[:zone].to_s
            donor_zone != zone &&
              counts.fetch(donor_zone, 0) > REPRESENTATIVE_ZONE_MINIMUMS.fetch(donor_zone, 1) &&
              !skipped_reseed_donor_ids.include?(item[:unique_id]) &&
              !notch_unsafe_reseed_donor?(zone, item)
          end,
          counts
        ).first
        next unless donor

        begin
          puts "ℹ️ Reseeding representative #{zone} candidate before move matrix: #{donor[:unique_id]}"
          move_and_verify(REPRESENTATIVE_ZONE_MOVE_COMMANDS.fetch(zone), donor, zone)
          donor_moved = true
          zones = list_icon_zones
          candidates = candidate_pool(zones)
          counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
        rescue StandardError => e
          puts "⚠️ Representative #{zone} reseed failed for #{donor[:unique_id]}: #{e.message}"
          if e.message.include?('notch-unsafe drag source')
            skipped_reseed_donor_ids << donor[:unique_id]
            donor_moved = true
          end
          begin
            zones = list_icon_zones
            candidates = candidate_pool(zones)
            counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
          rescue StandardError
            # Keep the original error visible; the hard representative check below
            # will report the last usable snapshot if the refresh also fails.
          end
        end
      end
      break unless donor_moved
    end
    zones
  rescue StandardError
    zones
  end

  def notch_unsafe_reseed_donor?(target_zone, item)
    target_zone.to_s == 'visible' && item.key?(:drag_source_safety) && !drag_source_safe?(item[:drag_source_safety])
  end

  def prioritize_reseed_donors(target_zone, donors, counts)
    donors.sort_by do |item|
      donor_zone = item[:zone].to_s
      surplus = counts.fetch(donor_zone, 0) - REPRESENTATIVE_ZONE_MINIMUMS.fetch(donor_zone, 1)
      [
        donor_zone == 'alwaysHidden' && target_zone != 'alwaysHidden' ? 1 : 0,
        surplus > 1 ? 0 : 1,
        preferred_move_candidate_rank(item[:bundle]),
        item[:bundle].start_with?('com.apple.') ? 1 : 0,
        coarse_bundle_fallback?(item) ? 1 : 0,
        item[:name].to_s.downcase
      ]
    end
  end

  def require_representative_zone_candidates!(zones)
    return zones unless @require_all_zones
    return zones if focused_required_id_mode?

    # Self-heal FIRST: deterministically reset the shared-fixture (SBF) icons into
    # a canonical per-zone layout regardless of where prior probe runs left them.
    # This guarantees a movable candidate in visible, hidden, and always-hidden
    # before the precondition is checked, so a drifted fixture baseline can no
    # longer abort the release-blocking gate at setup.
    zones, reset_report = reset_shared_fixture_zone_layout!(zones)

    zones = reseed_missing_zone_candidates(zones)
    candidates = candidate_pool(zones)
    missing = REQUIRED_REPRESENTATIVE_ZONES.reject do |zone|
      candidates.any? { |candidate| candidate[:zone] == zone }
    end
    ah_count = candidates.count { |candidate| candidate[:zone] == 'alwaysHidden' }
    if ah_count < 3
      counts = zones.group_by { |item| item[:zone].to_s }.transform_values(&:length)
      candidate_counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
      raise "Runtime smoke requires three representative movable always-hidden candidates for outbound move coverage (raw=#{counts}, candidate=#{candidate_counts}). #{reset_report}"
    end
    if missing.empty?
      summary = REQUIRED_REPRESENTATIVE_ZONES.map do |zone|
        candidate = candidates.find { |item| item[:zone] == zone }
        "#{zone}=#{candidate[:unique_id]}"
      end.join(' ')
      puts "✅ Representative zone candidates ok: #{summary}"
      return zones
    end

    counts = zones.group_by { |item| item[:zone].to_s }.transform_values(&:length)
    candidate_counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
    raise "Runtime smoke requires representative movable candidates in every zone; missing #{missing.join(', ')} (raw=#{counts}, candidate=#{candidate_counts}). #{reset_report} Seed visible, hidden, and always-hidden fixture items before release verification."
  end

  # Deterministically redistribute the shared-fixture (SBF) icons into the
  # canonical layout (SHARED_FIXTURE_CANONICAL_ZONE_PLAN) from ANY drifted
  # starting state, reusing the same move_and_verify path the smoke uses for its
  # real assertions. Idempotent: if a fixture is already in its assigned zone the
  # move is skipped, so running the smoke twice in a row both establish the
  # baseline. Returns [zones, report] where report describes what the reset tried
  # (used in the hard-fail message when seeding genuinely cannot converge, e.g.
  # the fixture app is not running so there are no SBF icons to move).
  def reset_shared_fixture_zone_layout!(zones)
    fixtures = sorted_shared_fixture_candidates(zones)
    if fixtures.empty?
      return [zones, 'Shared-fixture reset: no com.sanebar.sharedfixture (SBF) icons present live; the shared-fixture app is not running on the target so the per-zone baseline cannot be seeded.']
    end

    plan = shared_fixture_zone_plan(fixtures)
    attempted = []
    moved = []
    failed = []

    SHARED_FIXTURE_RESET_MAX_PASSES.times do |pass|
      remaining = plan.reject do |unique_id, target_zone|
        live = list_icon_zones.find { |item| item[:unique_id] == unique_id }
        live && live[:zone].to_s == target_zone
      end
      break if remaining.empty?

      remaining.each do |unique_id, target_zone|
        live_zones = list_icon_zones
        candidate = live_zones.find { |item| item[:unique_id] == unique_id }
        next unless candidate # fixture vanished; topology check below reports it

        next if candidate[:zone].to_s == target_zone

        attempted << "#{unique_id}->#{target_zone}"
        # Outbound moves FROM Always Hidden can start from a drag source the
        # static safety check flags as notch-unsafe. The product reveal/repair
        # workflow handles that exactly as the representative matrix does, so mark
        # the move as a staged Always-Hidden outbound so settle_before_outbound_move
        # allows it instead of refusing the reset.
        move_candidate =
          if candidate[:zone].to_s == 'alwaysHidden' && target_zone != 'alwaysHidden'
            candidate.merge(staged_always_hidden_outbound: true)
          else
            candidate
          end
        begin
          puts "ℹ️ Shared-fixture reset (pass #{pass + 1}): #{unique_id} -> #{target_zone}"
          move_and_verify(REPRESENTATIVE_ZONE_MOVE_COMMANDS.fetch(target_zone), move_candidate, target_zone)
          moved << "#{unique_id}->#{target_zone}"
          zones = list_icon_zones
        rescue StandardError => e
          failed << "#{unique_id}->#{target_zone}: #{e.message}"
          puts "⚠️ Shared-fixture reset move failed for #{unique_id} -> #{target_zone}: #{e.message}"
          begin
            zones = list_icon_zones
          rescue StandardError
            # Keep the last usable snapshot; the precondition check reports it.
          end
        end
      end
    end

    final_counts = sorted_shared_fixture_candidates(zones)
                   .group_by { |item| item[:zone].to_s }
                   .transform_values(&:length)
    report = "Shared-fixture reset attempted #{attempted.length} move(s) toward canonical layout " \
             "(plan=#{plan.map { |id, zone| "#{id.split('.').last}=#{zone}" }.join(',')}; " \
             "moved=#{moved.length}; final SBF zone counts=#{final_counts}" \
             "#{failed.empty? ? '' : "; failures=#{failed.join(' | ')}"})."
    puts "ℹ️ #{report}"
    [zones, report]
  rescue StandardError => e
    # Never let the self-heal itself abort the gate; fall through to the existing
    # generic reseed + hard precondition, which reports the live snapshot.
    [zones, "Shared-fixture reset aborted early: #{e.message}."]
  end

  # SBF fixtures sorted by their stable SBF-A..SBF-E suffix so the canonical zone
  # assignment is deterministic across runs (SBF-A->visible, SBF-B->hidden,
  # SBF-C/D/E->alwaysHidden).
  def sorted_shared_fixture_candidates(zones)
    zones.select do |item|
      item[:movable] && item[:bundle].to_s == SHARED_FIXTURE_BUNDLE_ID
    end.sort_by { |item| item[:unique_id].to_s }
  end

  # Assign each ordered SBF fixture to its canonical destination zone. If fewer
  # than 5 SBF icons are live, the last plan entries (extra always-hidden) are
  # simply omitted; the precondition then still requires the minimums and reports
  # what was available.
  def shared_fixture_zone_plan(fixtures)
    fixtures.each_with_index.each_with_object({}) do |(item, index), plan|
      target_zone = SHARED_FIXTURE_CANONICAL_ZONE_PLAN[index] || 'alwaysHidden'
      plan[item[:unique_id]] = target_zone
    end
  end

  def representative_zone_candidates(candidates)
    by_zone = candidates.group_by { |candidate| candidate[:zone] }
    selected = REQUIRED_REPRESENTATIVE_ZONES.map do |zone|
      prioritize_move_candidates(Array(by_zone[zone])).first
    end.compact
    extra_always_hidden = prioritize_move_candidates(Array(by_zone['alwaysHidden']))
      .reject { |candidate| selected.any? { |item| item[:unique_id] == candidate[:unique_id] } }
      .take(2)
    selected.concat(extra_always_hidden)
    selected
  end

  def resolve_required_candidate(required_id, ordered)
    ordered.find { |candidate| candidate[:unique_id] == required_id }
  end




  def sh(command)
    Open3.capture2e(command)
  end


  def always_hidden_optional_failure?(error)
    message = error.message.to_s
    message.include?('failed to move to alwaysHidden') ||
      message.include?('to reach zone alwaysHidden')
  end

  def zone_api_retryable?(error)
    message = error.message.to_s
    message.include?('Connection is invalid') ||
      message.include?('No icons returned from list icon zones.') ||
      message.include?('Accessibility permission is required')
  end

  def retryable_zone_poll_error?(error)
    return true if zone_api_retryable?(error)

    error.message.include?('AppleScript timeout')
  end

  def layout_snapshot_retryable?(error)
    return true if retryable_zone_poll_error?(error)

    error.message.include?('layout snapshot')
  end

  def strict_candidate_mode?
    @require_all_candidates || @require_all_zones || !@required_candidate_ids.empty?
  end

  def strict_candidate_minimum(candidate_count)
    return 1 if representative_action_matrix_mode?
    return candidate_count if @require_all_candidates || focused_required_id_mode?

    min_passing = @min_passing_candidates.to_i
    return candidate_count if min_passing <= 0

    min_passing
  end

  def candidate_failure_summary(failures)
    failures.map do |candidate, error|
      "#{candidate[:unique_id]}: #{error.message}"
    end.join(' | ')
  end

  def drag_source_safe?(value)
    text = value.to_s
    return true if text.empty?

    text == 'safe'
  end

  def all_required_candidates_skipped_as_notch_unsafe?(candidates, skipped_candidates, failures)
    @allow_notch_unsafe_required_skips &&
      focused_required_id_mode? &&
      failures.empty? &&
      !candidates.empty? &&
      skipped_candidates.length == candidates.length
  end

  def notch_unsafe_required_skip?(candidate, error)
    return false unless @allow_notch_unsafe_required_skips
    return false unless focused_required_id_mode?
    return true if error.message.to_s.include?('notch-unsafe drag source')

    zones = list_icon_zones
    matched = matched_move_candidate(zones, candidate[:unique_id], candidate)
    matched && matched.key?(:drag_source_safety) && !drag_source_safe?(matched[:drag_source_safety])
  rescue StandardError
    false
  end

  def move_candidates_required?
    @require_candidate || strict_candidate_mode?
  end

  def browse_activation_candidates_required?
    @require_browse_activation_candidate || strict_candidate_mode?
  end

  def focused_required_id_mode?
    !@required_candidate_ids.empty?
  end

  def representative_action_matrix_mode?
    @require_all_zones && @required_candidate_ids.empty? && !@require_all_candidates
  end

  def escape_quotes(value)
    value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  end

  def env_string(name)
    value = ENV[name].to_s.strip
    value.empty? ? nil : value
  end

  def integer_env(name)
    value = env_string(name)
    return nil unless value

    Integer(value, 10)
  rescue ArgumentError
    nil
  end

  def float_env(name)
    value = env_string(name)
    return nil unless value

    Float(value)
  rescue ArgumentError
    nil
  end

  def expand_env_path(name)
    value = env_string(name)
    return nil unless value

    File.expand_path(value)
  end

  def expected_process_path
    return @process_path if @process_path
    return nil unless @app_path

    File.join(@app_path, 'Contents', 'MacOS', @app_name)
  end

  def matching_app_process?(command)
    binary = command.split(/\s+/, 2).first.to_s
    return false if binary.empty?

    expected = expected_process_path
    if expected
      return false unless File.expand_path(binary) == expected
      return false if @require_no_keychain_process && !command.include?('--sane-no-keychain')

      return true
    end

    return false if @require_no_keychain_process && !command.include?('--sane-no-keychain')

    binary.end_with?("/Contents/MacOS/#{@app_name}") || File.basename(binary) == @app_name
  end

  def apple_script_target
    if @app_id
      %(application id "#{escape_quotes(@app_id)}")
    else
      %(application "#{escape_quotes(@app_name)}")
    end
  end

  def apple_script_lines(statement)
    if @app_path
      [
        %(set appTarget to ((POSIX file "#{escape_quotes(@app_path)}" as alias) as text)),
        %(using terms from #{apple_script_target}),
        %(tell application appTarget to #{statement}),
        'end using terms from'
      ]
    else
      [%(tell #{apple_script_target} to #{statement})]
    end
  end
end


require_relative 'lib/live_zone_smoke_browse_visual'
require_relative 'lib/live_zone_smoke_screenshots_fullscreen'
require_relative 'lib/live_zone_smoke_moves'
require_relative 'lib/live_zone_smoke_resources'
require_relative 'lib/live_zone_smoke_hidden_outbound_gate'

if __FILE__ == $PROGRAM_NAME
  exit(LiveZoneSmoke.new.run ? 0 : 1)
end
