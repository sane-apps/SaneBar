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
  FULLSCREEN_TRANSITION_PROBE_APPS = [
    { label: 'safari', app: 'Safari', process: 'Safari', required: true },
    { label: 'textedit', app: 'TextEdit', process: 'TextEdit', required: false }
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
    @post_smoke_idle_settle_seconds = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS') || DEFAULT_POST_SMOKE_IDLE_SETTLE_SECONDS
    @post_smoke_idle_sample_seconds = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS') || DEFAULT_POST_SMOKE_IDLE_SAMPLE_SECONDS
    @post_smoke_idle_cpu_avg_max = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_AVG_MAX') || DEFAULT_POST_SMOKE_IDLE_CPU_AVG_MAX
    @post_smoke_idle_cpu_peak_max = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX') || DEFAULT_POST_SMOKE_IDLE_CPU_PEAK_MAX
    @post_smoke_idle_rss_mb_max = float_env('SANEBAR_SMOKE_POST_SMOKE_IDLE_RSS_MB_MAX') || DEFAULT_POST_SMOKE_IDLE_RSS_MB_MAX
    @active_avg_cpu_max = float_env('SANEBAR_SMOKE_ACTIVE_AVG_CPU_MAX') || DEFAULT_ACTIVE_AVG_CPU_MAX
    @active_avg_rss_mb_max = float_env('SANEBAR_SMOKE_ACTIVE_AVG_RSS_MB_MAX') || DEFAULT_ACTIVE_AVG_RSS_MB_MAX
    @resource_sample_path = expand_env_path('SANEBAR_SMOKE_RESOURCE_SAMPLE_PATH') || File.join(Dir.tmpdir, 'sanebar_runtime_resource_sample.txt')
    @require_always_hidden = ENV['SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN'] == '1'
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
    assert_idle_budget!(
      label: 'launch',
      settle_seconds: @launch_idle_settle_seconds,
      sample_seconds: @launch_idle_sample_seconds,
      cpu_avg_max: @launch_idle_cpu_avg_max,
      cpu_peak_max: @launch_idle_cpu_peak_max,
      rss_mb_max: @launch_idle_rss_mb_max
    )
    reset_resource_watchdog_window!

    zones = list_icon_zones
    require_representative_zone_candidates!(zones)
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
            failures << [candidate, e]
            puts "⚠️ Candidate failed: #{candidate[:bundle]} (#{e.message})"
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
        min_required = strict_candidate_minimum(candidates.length)
        if passed_candidates.length < min_required
          summary = candidate_failure_summary(failures)
          detail = summary.empty? ? '' : " Candidate failures: #{summary}"
          raise "#{passed_candidates.length}/#{min_required} candidates passed move action checks.#{detail}"
        end
        if failures.any? && @min_passing_candidates <= 0
          raise "Candidate failures: #{candidate_failure_summary(failures)}"
        elsif failures.any?
          puts "⚠️ Candidate failures tolerated after #{passed_candidates.length}/#{min_required} candidates passed: #{candidate_failure_summary(failures)}"
        end
        raise 'No candidates passed move action checks.' if passed_candidates.empty?

        puts "✅ Candidate set passed: #{passed_candidates.map { |candidate| candidate[:unique_id] }.join(', ')}"
      else
        last_failure = failures.last&.last
        raise(last_failure || 'No candidate passed move action checks.') if passed_candidates.empty?
      end
    end

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

  private

  def prepare_zones_for_move_checks
    close_browse_panel_safely
    close_settings_window_safely
    prepare_layout_baseline
    wait_for_stable_layout_snapshot
    sleep_with_watchdog(1.5)

    zones = list_icon_zones
    zones = seed_representative_always_hidden_candidates_for_move_checks(zones)
    require_representative_zone_candidates!(zones)
    zones
  end

  def seed_representative_always_hidden_candidates_for_move_checks(zones)
    return zones unless @require_all_zones
    return zones if focused_required_id_mode?

    candidates = candidate_pool(zones)
    always_hidden_count = candidates.count { |candidate| candidate[:zone] == 'alwaysHidden' }
    return zones if always_hidden_count >= 3

    zone_counts = candidates.group_by { |candidate| candidate[:zone].to_s }.transform_values(&:length)
    donors = prioritize_move_candidates(
      candidates.reject { |candidate| candidate[:zone] == 'alwaysHidden' }
                .select { |candidate| zone_counts.fetch(candidate[:zone].to_s, 0) > 1 }
    )
    return zones if donors.empty?

    donors.each do |donor|
      break if always_hidden_count >= 3

      begin
        puts "ℹ️ Reseeding representative Always Hidden candidate before move matrix: #{donor[:unique_id]}"
        move_and_verify('move icon to always hidden', donor, 'alwaysHidden')
        zones = list_icon_zones
        candidates = candidate_pool(zones)
        always_hidden_count = candidates.count { |candidate| candidate[:zone] == 'alwaysHidden' }
      rescue StandardError => e
        puts "⚠️ Representative Always Hidden reseed failed for #{donor[:unique_id]}: #{e.message}"
      end
    end

    zones
  end

  def prepare_layout_baseline
    close_browse_panel_safely
    close_settings_window_safely

    snapshot = layout_snapshot
    return if snapshot['hidingState'] == 'hidden'
    return unless supports_applescript_command?('hide')

    app_script('hide')
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

      sleep_with_watchdog(LAYOUT_STABILIZE_POLL_SECONDS)
    end

    if last_error
      raise "Layout did not stabilize in #{LAYOUT_STABILIZE_TIMEOUT_SECONDS}s (attempts=#{attempts}, last_error=#{last_error.message}, snapshot=#{last_snapshot})"
    end

    raise "Layout did not stabilize in #{LAYOUT_STABILIZE_TIMEOUT_SECONDS}s (attempts=#{attempts}, snapshot=#{last_snapshot})"
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
    zones = raw.lines.map do |line|
      zone, movable, bundle, unique_id, name = line.strip.split("\t", 5)
      next nil if zone.nil? || unique_id.nil?

      {
        zone: zone,
        movable: movable == 'true',
        bundle: bundle.to_s,
        unique_id: unique_id,
        name: name.to_s
      }
    end.compact

    raise 'No icons returned from list icon zones.' if zones.empty?

    zones
  end

  def list_icon_zones_raw
    app_script('list icon zones')
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

  def require_representative_zone_candidates!(zones)
    return unless @require_all_zones
    return if focused_required_id_mode?

    candidates = candidate_pool(zones)
    missing = REQUIRED_REPRESENTATIVE_ZONES.reject do |zone|
      candidates.any? { |candidate| candidate[:zone] == zone }
    end
    ah_count = candidates.count { |candidate| candidate[:zone] == 'alwaysHidden' }
    if ah_count < 3
      counts = zones.group_by { |item| item[:zone].to_s }.transform_values(&:length)
      candidate_counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
      raise "Runtime smoke requires three representative movable always-hidden candidates for outbound move coverage (raw=#{counts}, candidate=#{candidate_counts})."
    end
    if missing.empty?
      summary = REQUIRED_REPRESENTATIVE_ZONES.map do |zone|
        candidate = candidates.find { |item| item[:zone] == zone }
        "#{zone}=#{candidate[:unique_id]}"
      end.join(' ')
      puts "✅ Representative zone candidates ok: #{summary}"
      return
    end

    counts = zones.group_by { |item| item[:zone].to_s }.transform_values(&:length)
    candidate_counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
    raise "Runtime smoke requires representative movable candidates in every zone; missing #{missing.join(', ')} (raw=#{counts}, candidate=#{candidate_counts}). Seed visible, hidden, and always-hidden fixture items before release verification."
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
    exact = ordered.find { |candidate| candidate[:unique_id] == required_id }
    return exact if exact

    bundle_id = required_id.split('::', 2).first
    return nil if bundle_id.nil? || bundle_id.empty?

    bundle_matches = ordered.select { |candidate| candidate[:bundle] == bundle_id }
    return bundle_matches.first if bundle_matches.length == 1

    nil
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

    min_passing = @min_passing_candidates.to_i
    return candidate_count if min_passing <= 0

    min_passing
  end

  def candidate_failure_summary(failures)
    failures.map do |candidate, error|
      "#{candidate[:unique_id]}: #{error.message}"
    end.join(' | ')
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

if __FILE__ == $PROGRAM_NAME
  exit(LiveZoneSmoke.new.run ? 0 : 1)
end
