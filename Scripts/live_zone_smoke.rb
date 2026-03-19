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
  DEFAULT_POST_SMOKE_IDLE_SETTLE_SECONDS = 8.0
  DEFAULT_POST_SMOKE_IDLE_SAMPLE_SECONDS = 4.0
  DEFAULT_POST_SMOKE_IDLE_CPU_AVG_MAX = 5.0
  DEFAULT_POST_SMOKE_IDLE_CPU_PEAK_MAX = 20.0
  DEFAULT_POST_SMOKE_IDLE_RSS_MB_MAX = 128.0
  DEFAULT_ACTIVE_AVG_CPU_MAX = 15.0
  DEFAULT_ACTIVE_AVG_RSS_MB_MAX = 192.0
  LAYOUT_STABILIZE_TIMEOUT_SECONDS = 10
  LAYOUT_STABILIZE_POLL_SECONDS = 0.25
  ZONE_API_READY_TIMEOUT_SECONDS = 10
  ZONE_API_READY_POLL_SECONDS = 0.5
  APPLESCRIPT_TIMEOUT_SECONDS = 8
  APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS = 20
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
  SCREENSHOT_CAPTURE_TIMEOUT_SECONDS = 20
  APPLE_FALLBACK_BUNDLE_DENYLIST = %w[
    com.apple.controlcenter
    com.apple.systemuiserver
    com.apple.Spotlight
  ].freeze
  MOVE_CANDIDATE_BUNDLE_DENYLIST = (
    APPLE_FALLBACK_BUNDLE_DENYLIST + %w[
      com.apple.SSMenuAgent
      com.apple.menuextra.focusmode
      cc.ffitch.shottr
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
    ]
  ).freeze
  BROWSE_PANEL_COMMANDS = {
    'secondMenuBar' => 'show second menu bar',
    'findIcon' => 'open icon panel',
  }.freeze
  WINDOW_SCREENSHOT_TITLES = {
    'findIcon' => 'Icon Panel',
    'secondMenuBar' => nil,
  }.freeze
  PREFERRED_BROWSE_ACTIVATION_IDS = %w[
    com.apple.menuextra.bluetooth
    com.apple.menuextra.display
    com.apple.menuextra.wifi
    com.apple.menuextra.clock
    com.apple.menuextra.spotlight
    com.apple.SSMenuAgent
    com.apple.controlcenter
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
    @require_candidate = ENV['SANEBAR_SMOKE_REQUIRE_CANDIDATE'] == '1'
    @require_all_candidates = ENV['SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES'] == '1'
    @capture_screenshots = ENV.fetch('SANEBAR_SMOKE_CAPTURE_SCREENSHOTS', '1') != '0'
    @screenshot_dir = expand_env_path('SANEBAR_SMOKE_SCREENSHOT_DIR') || File.join(Dir.tmpdir, 'sanebar-smoke')
    @window_screenshot_tool = resolve_window_screenshot_tool
    @required_candidate_ids = ENV.fetch('SANEBAR_SMOKE_REQUIRED_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
    @supported_applescript_commands = detect_supported_applescript_commands
    reset_resource_watchdog_state
  end

  def run
    started_at = Time.now.utc
    puts "🔎 --- [ LIVE ZONE SMOKE ] ---"

    verify_single_process
    start_resource_watchdog
    snapshot = wait_for_stable_layout_snapshot
    check_layout_invariants(snapshot)
    wait_for_zone_api_ready
    assert_idle_budget!(
      label: 'launch',
      settle_seconds: @launch_idle_settle_seconds,
      sample_seconds: @launch_idle_sample_seconds,
      cpu_avg_max: @launch_idle_cpu_avg_max,
      cpu_peak_max: @launch_idle_cpu_peak_max,
      rss_mb_max: @launch_idle_rss_mb_max
    )

    zones = list_icon_zones
    exercise_browse_modes(zones)
    candidates = selected_candidates(zones)
    if candidates.empty?
      if move_candidates_required?
        raise "No movable candidate icon found (need at least one hidden/visible icon)."
      else
        puts 'ℹ️ No movable candidate icon found on this setup; skipping move checks for this default smoke run.'
      end
    end

    failures = []
    passed_candidates = []

    unless candidates.empty?
      candidates.each do |candidate|
        begin
          puts "🎯 Candidate: #{candidate[:name]} (#{candidate[:bundle]}) zone=#{candidate[:zone]}"
          exercise_hidden_visible_moves(candidate)
          exercise_always_hidden_moves(candidate)
          passed_candidates << candidate
          puts "✅ Candidate passed: #{candidate[:unique_id]}"
          break unless strict_candidate_mode?
        rescue StandardError => e
          failures << [candidate, e]
          puts "⚠️ Candidate failed: #{candidate[:bundle]} (#{e.message})"
        ensure
          begin
            restore_zone(candidate)
          rescue StandardError
            # Keep trying other candidates; final failure will include last_error.
          end
        end
      end

      if strict_candidate_mode?
        unless failures.empty?
          summary = failures.map do |candidate, error|
            "#{candidate[:unique_id]}: #{error.message}"
          end.join(' | ')
          raise "Candidate failures: #{summary}"
        end
        raise 'No candidates passed move action checks.' if passed_candidates.empty?
        puts "✅ Candidate set passed: #{passed_candidates.map { |candidate| candidate[:unique_id] }.join(', ')}"
      else
        last_failure = failures.last&.last
        raise(last_failure || 'No candidate passed move action checks.') if passed_candidates.empty?
      end
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
    assert_active_average_budget!
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
    unless layout_invariants_satisfied?(snapshot)
      raise "Layout invariant failed after stabilization (snapshot=#{snapshot})"
    end

    puts "✅ Layout invariants ok: separator/main order and launch proximity"
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
        name: name.to_s,
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
    candidates.reject! { |item| MOVE_CANDIDATE_BUNDLE_DENYLIST.include?(item[:bundle]) } unless allow_denylisted

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
        %w[hidden visible alwaysHidden].include?(item[:zone])
    end
    excluded_app_menu_bundles = app_menu_bundle_ids(raw_candidates)
    candidates = raw_candidates.reject do |item|
      likely_standard_app_menu_candidate?(item) ||
        excluded_app_menu_bundles.include?(item[:bundle].to_s.downcase)
    end
    precise_bundles = candidates.reject { |item| coarse_bundle_fallback?(item) }.map { |item| item[:bundle] }.uniq
    candidates.reject do |item|
      coarse_bundle_fallback?(item) && precise_bundles.include?(item[:bundle])
    end
  end

  def preferred_move_candidate_rank(bundle)
    bundle = bundle.to_s.downcase
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
        item[:name].to_s.downcase,
      ]
    end
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

  def exercise_browse_modes(zones)
    BROWSE_PANEL_COMMANDS.each do |expected_mode, command|
      unless supports_applescript_command?(command)
        puts "ℹ️ Skipping #{expected_mode}: running app does not expose '#{command}'"
        next
      end

      if full_browse_activation_supported? && !focused_required_id_mode?
        activation_candidates = browse_activation_candidates(zones)
        raise 'No browse activation candidate icon found.' if activation_candidates.empty?
        exercise_browse_mode(expected_mode: expected_mode, command: command, candidates: activation_candidates)
      else
        reason = focused_required_id_mode? ? 'focused required-id smoke' : 'activation diagnostics unavailable in running app'
        puts "ℹ️ Compatibility browse check for #{expected_mode}: #{reason}"
        exercise_compatibility_browse_mode(expected_mode: expected_mode, command: command)
      end
    end
  end

  def full_browse_activation_supported?
    [
      'browse panel diagnostics',
      'activate browse icon',
      'right click browse icon',
    ].all? { |command| supports_applescript_command?(command) }
  end

  def browse_activation_candidates(zones)
    ordered_pool = browse_activation_pool(zones).sort_by do |item|
      [
        browse_zone_priority(item[:zone]),
        coarse_bundle_fallback?(item) ? 1 : 0,
      ]
    end
    precise_non_apple = ordered_pool.reject do |item|
      coarse_bundle_fallback?(item) || item[:bundle].start_with?('com.apple.')
    end

    preferred = PREFERRED_BROWSE_ACTIVATION_IDS.map do |preferred_id|
      ordered_pool.find { |item| browse_candidate_matches?(item, preferred_id) }
    end.compact.reject { |item| browse_activation_denied?(item) }
      .uniq { |item| item[:unique_id] }

    fallback = ordered_pool.reject { |item| browse_activation_denied?(item) }

    (preferred + precise_non_apple + fallback).uniq { |item| item[:unique_id] }.take(3)
  end

  def browse_zone_priority(zone)
    case zone
    when 'visible' then 0
    when 'hidden' then 1
    else 2
    end
  end

  def coarse_bundle_fallback?(item)
    item[:unique_id].to_s == item[:bundle].to_s
  end

  def browse_candidate_matches?(item, preferred_id)
    values = [item[:unique_id], item[:bundle], item[:name]].compact.map(&:downcase)
    target = preferred_id.downcase
    values.any? { |value| value == target || value.include?(target) }
  end

  def browse_activation_denied?(item)
    return false if PREFERRED_BROWSE_ACTIVATION_IDS.any? { |preferred_id| browse_candidate_matches?(item, preferred_id) }

    BROWSE_ACTIVATION_BUNDLE_DENYLIST.include?(item[:bundle])
  end

  def exercise_browse_mode(expected_mode:, command:, candidates:)
    focus_probe_prior_state = seed_focus_probe_prior_app
    result = app_script(command).strip.downcase
    unless %w[true 1].include?(result)
      raise "#{command} returned '#{result}'"
    end

    wait_for_browse_panel(expected_mode)
    assert_browse_panel_anchor!(expected_mode)
    live_candidates = browse_activation_candidates(list_icon_zones)
    raise "No browse activation candidate icon found in #{expected_mode} after panel open." if live_candidates.empty?
    screenshot_path = capture_browse_screenshot(expected_mode) if @capture_screenshots
    puts "📸 #{expected_mode} screenshot: #{screenshot_path}" if screenshot_path

    exercise_browse_activation('activate browse icon', expected_mode, live_candidates)
    # SearchService debounces duplicate activation of the same icon for 450ms.
    # Leave enough headroom before immediately retrying that tile with right-click.
    sleep_with_watchdog(BROWSE_ACTIVATION_COOLDOWN_SECONDS)
    exercise_browse_activation(
      'right click browse icon',
      expected_mode,
      live_candidates,
      prior_frontmost_state: focus_probe_prior_state
    )
    close_browse_panel
    puts "✅ Browse mode #{expected_mode} activation ok"
  ensure
    close_browse_panel_safely
  end

  def exercise_compatibility_browse_mode(expected_mode:, command:)
    result = app_script(command).strip.downcase
    unless %w[true 1].include?(result)
      raise "#{command} returned '#{result}'"
    end

    wait_for_browse_panel(expected_mode)
    assert_browse_panel_anchor!(expected_mode)
    screenshot_path = capture_browse_screenshot(expected_mode) if @capture_screenshots
    puts "📸 #{expected_mode} screenshot: #{screenshot_path}" if screenshot_path
    close_browse_panel
    puts "✅ Browse mode #{expected_mode} open/close ok"
  ensure
    close_browse_panel_safely
  end

  def exercise_browse_activation(command, expected_mode, candidates, prior_frontmost_state: nil)
    failures = []

    candidates.each do |candidate|
      live_identifier = resolve_live_icon_identifier(candidate)
      baseline_diagnostics = current_browse_activation_diagnostics
      diagnostics = app_script(%(#{command} "#{escape_quotes(live_identifier)}"))
      if browse_activation_succeeded?(diagnostics, expected_mode)
        verify_post_activation_browse_state!(expected_mode)
        assert_frontmost_did_not_revert_to(prior_frontmost_state, command) unless prior_frontmost_state.nil?
        return
      end

      failures << "#{candidate[:unique_id]} => #{browse_activation_failure_summary(diagnostics)}"
    rescue StandardError => e
      salvaged = salvage_timed_out_browse_activation(
        live_identifier: live_identifier,
        baseline_diagnostics: baseline_diagnostics,
        error: e
      )
      return if salvaged && browse_activation_succeeded?(salvaged, expected_mode)

      failures << "#{candidate[:unique_id]} => #{e.message}"
    end

    raise "#{command} failed in #{expected_mode}: #{failures.join(' | ')}"
  end

  def browse_activation_succeeded?(diagnostics, expected_mode)
    expected_visible = expected_mode == 'secondMenuBar' ? 'windowVisible: true' : nil

    diagnostics.include?("origin: browsePanel") &&
      diagnostics.include?("finalOutcome: click succeeded") &&
      browse_activation_observably_verified?(diagnostics) &&
      diagnostics.include?("currentMode: #{expected_mode}") &&
      (expected_visible.nil? || diagnostics.include?(expected_visible))
  end

  def verify_post_activation_browse_state!(expected_mode)
    return unless expected_mode == 'secondMenuBar'

    sleep_with_watchdog(SECOND_MENU_BAR_POST_ACTIVATION_VISIBILITY_SECONDS)
    diagnostics = browse_panel_diagnostics
    return if diagnostics.include?('currentMode: secondMenuBar') &&
              diagnostics.include?('windowVisible: true')

    raise "second menu bar collapsed after activation: #{browse_activation_failure_summary(diagnostics)}"
  end

  def seed_focus_probe_prior_app
    out, code = capture2e_with_timeout(
      '/usr/bin/osascript',
      '-e',
      %(tell application "#{FOCUS_PROBE_APP_NAME}" to activate),
      timeout: APPLESCRIPT_TIMEOUT_SECONDS
    )
    raise "focus probe activation failed: #{out.strip}" unless code.success?

    deadline = Time.now + FOCUS_PROBE_TIMEOUT_SECONDS
    while Time.now < deadline
      current_state = frontmost_app_state
      return current_state if current_state['bundleId'] == FOCUS_PROBE_APP_BUNDLE

      sleep_with_watchdog(FOCUS_PROBE_POLL_SECONDS)
    end

    raise "focus probe did not reach #{FOCUS_PROBE_APP_BUNDLE}"
  rescue StandardError => e
    puts "ℹ️ Focus probe skipped: #{e.message}"
    nil
  end

  def assert_frontmost_did_not_revert_to(prior_frontmost_state, command)
    return if prior_frontmost_state.nil?
    prior_bundle = prior_frontmost_state['bundleId'].to_s
    return if prior_bundle.empty?

    sleep_with_watchdog(RIGHT_CLICK_FOCUS_PROBE_SETTLE_SECONDS)
    current_state = frontmost_app_state
    return unless current_state['bundleId'].to_s == prior_bundle

    diagnostics = current_browse_activation_diagnostics
    prior_window = prior_frontmost_state['windowTitle'].to_s
    current_window = current_state['windowTitle'].to_s
    detail =
      if !prior_window.empty? && !current_window.empty? && prior_window == current_window
        "prior app/window #{prior_bundle} / #{prior_window.inspect}"
      elsif !prior_window.empty? || !current_window.empty?
        "prior app #{prior_bundle} (priorWindow=#{prior_window.inspect}, currentWindow=#{current_window.inspect})"
      else
        "prior app #{prior_bundle}"
      end
    raise "#{command} reverted focus to #{detail}: #{browse_activation_failure_summary(diagnostics)}"
  end

  def frontmost_app_state
    script = <<~JXA
      ObjC.import('AppKit')
      function frontWindowTitle() {
        try {
          const se = Application('System Events')
          const processes = se.applicationProcesses.whose({ frontmost: true })()
          if (!processes.length) return ''
          const windows = processes[0].windows()
          if (!windows.length) return ''
          return windows[0].name() || ''
        } catch (error) {
          return ''
        }
      }
      const app = $.NSWorkspace.sharedWorkspace.frontmostApplication
      const payload = {
        bundleId: '',
        localizedName: '',
        pid: 0,
        windowTitle: frontWindowTitle()
      }
      if (app) {
        payload.bundleId = ObjC.unwrap(app.bundleIdentifier) || ''
        payload.localizedName = ObjC.unwrap(app.localizedName) || ''
        payload.pid = Number(app.processIdentifier) || 0
      }
      JSON.stringify(payload)
    JXA
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-l', 'JavaScript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "frontmost-app probe failed: #{out.strip}" unless code.success?

    JSON.parse(out.to_s)
  rescue JSON::ParserError => e
    raise "frontmost-app probe returned invalid JSON: #{e.message}"
  end

  def browse_activation_observably_verified?(diagnostics)
    diagnostics.lines.any? do |line|
      stripped = line.strip
      next false unless stripped.start_with?('firstAttempt:', 'retryAttempt:')

      stripped.include?('accepted=true') &&
        stripped.include?('verification=verified')
    end
  end

  def browse_activation_failure_summary(diagnostics)
    interesting = diagnostics.lines.map(&:strip).select do |line|
      line.start_with?('requestedApp:', 'firstAttempt:', 'retryAttempt:', 'finalOutcome:', 'currentMode:', 'windowVisible:', 'lastRelayoutReason:')
    end
    return interesting.join(' || ') unless interesting.empty?

    diagnostics.lines.last.to_s.strip
  end

  def wait_for_browse_panel(expected_mode)
    deadline = Time.now + BROWSE_PANEL_READY_TIMEOUT_SECONDS
    last_diagnostics = nil

    while Time.now < deadline
      check_resource_watchdog!
      last_diagnostics = browse_panel_diagnostics
      return if last_diagnostics.include?("currentMode: #{expected_mode}") &&
                last_diagnostics.include?('windowVisible: true')

      sleep_with_watchdog(BROWSE_PANEL_READY_POLL_SECONDS)
    end

    raise "Browse panel did not become ready for #{expected_mode}: #{last_diagnostics}"
  end

  def assert_browse_panel_anchor!(expected_mode)
    deadline = Time.now + BROWSE_PANEL_READY_TIMEOUT_SECONDS
    last_snapshot = nil

    while Time.now < deadline
      check_resource_watchdog!
      last_snapshot = layout_snapshot
      mode_ok = last_snapshot['browseWindowMode'].to_s == expected_mode
      visible_ok = truthy?(last_snapshot['isBrowseVisible'])
      anchor_ok = truthy?(last_snapshot['browseWindowAnchorValid'])
      return if mode_ok && visible_ok && anchor_ok

      sleep_with_watchdog(BROWSE_PANEL_READY_POLL_SECONDS)
    end

    raise "Browse panel anchor invalid for #{expected_mode}: frame=#{last_snapshot&.dig('browseWindowFrame')} deltaX=#{last_snapshot&.dig('browseWindowAnchorDeltaX')} deltaY=#{last_snapshot&.dig('browseWindowAnchorDeltaY')} snapshot=#{last_snapshot}"
  end

  def close_browse_panel
    result = app_script('close browse panel').strip.downcase
    unless %w[true 1].include?(result)
      raise "close browse panel returned '#{result}'"
    end

    unless supports_applescript_command?('browse panel diagnostics')
      sleep_with_watchdog(0.5)
      return
    end

    wait_for_browse_panel_close
  end

  def close_browse_panel_safely
    close_browse_panel
  rescue StandardError
    nil
  end

  def wait_for_browse_panel_close
    deadline = Time.now + BROWSE_PANEL_READY_TIMEOUT_SECONDS
    last_diagnostics = nil

    while Time.now < deadline
      check_resource_watchdog!
      last_diagnostics = browse_panel_diagnostics
      return if last_diagnostics.include?('windowVisible: false')

      sleep_with_watchdog(BROWSE_PANEL_READY_POLL_SECONDS)
    end

    raise "Browse panel did not close cleanly: #{last_diagnostics}"
  end

  def browse_panel_diagnostics
    app_script('browse panel diagnostics')
  end

  def detect_supported_applescript_commands
    sdef_path = @app_path && File.join(@app_path, 'Contents', 'Resources', 'SaneBar.sdef')
    return [] unless sdef_path && File.exist?(sdef_path)

    File.read(sdef_path).scan(/<command name="([^"]+)"/).flatten
  rescue StandardError
    []
  end

  def supports_applescript_command?(command_name)
    return true if @supported_applescript_commands.empty?

    @supported_applescript_commands.include?(command_name)
  end

  def capture_browse_screenshot(expected_mode)
    FileUtils.mkdir_p(@screenshot_dir)
    path = File.join(
      @screenshot_dir,
      "sanebar-#{expected_mode}-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.png"
    )
    internal_error = capture_internal_browse_screenshot(path)
    return await_screenshot_file(path) if internal_error.nil?

    display_error = capture_display_screenshot(path)
    return await_screenshot_file(path) if display_error.nil?

    window_error = capture_window_screenshot(expected_mode, path)
    return await_screenshot_file(path) if window_error.nil?

    disable_screenshot_capture!(
      [
        ("internal capture failed: #{internal_error}" unless internal_error.nil? || internal_error.empty?),
        ("display capture failed: #{display_error}" unless display_error.nil? || display_error.empty?),
        ("window capture failed: #{window_error}" unless window_error.nil? || window_error.empty?)
      ].compact.join(' | '),
      path
    )
    nil
  rescue StandardError => e
    disable_screenshot_capture!(e.message, path)
    nil
  end

  def capture_internal_browse_screenshot(path)
    escaped_path = escape_quotes(path)
    direct_result = app_script(%(capture browse panel snapshot "#{escaped_path}")).strip.downcase
    return nil if %w[true 1].include?(direct_result)

    queued_result = app_script(%(queue browse panel snapshot "#{escaped_path}")).strip.downcase
    return nil if %w[true 1].include?(queued_result)

    "capture command returned #{direct_result.inspect}; queue command returned #{queued_result.inspect}"
  rescue StandardError => e
    e.message
  end

  def resolve_window_screenshot_tool
    from_path = `command -v screenshot 2>/dev/null`.strip
    return from_path unless from_path.empty?

    %w[
      ~/Library/Python/3.13/bin/screenshot
      ~/Library/Python/3.12/bin/screenshot
      ~/Library/Python/3.11/bin/screenshot
      ~/Library/Python/3.10/bin/screenshot
      ~/Library/Python/3.9/bin/screenshot
    ].map { |candidate| File.expand_path(candidate) }.find { |candidate| File.executable?(candidate) }
  end

  def capture_display_screenshot(path)
    command = "screencapture -x #{Shellwords.escape(path)}"
    script = <<~APPLESCRIPT
      do shell script #{command.inspect}
    APPLESCRIPT

    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: SCREENSHOT_CAPTURE_TIMEOUT_SECONDS)
    return nil if code.success?

    FileUtils.rm_f(path)
    out.strip
  end

  def capture_window_screenshot(expected_mode, path)
    return 'window screenshot tool unavailable' unless @window_screenshot_tool && File.executable?(@window_screenshot_tool)

    title = WINDOW_SCREENSHOT_TITLES.fetch(expected_mode, nil)
    command = [@window_screenshot_tool, @app_name, '-s', '-f', path]
    command += ['-t', title] if title
    out, code = capture2e_with_timeout(*command, timeout: SCREENSHOT_CAPTURE_TIMEOUT_SECONDS)
    return nil if code.success?

    FileUtils.rm_f(path)
    out.strip
  end

  def await_screenshot_file(path)
    deadline = Time.now + SCREENSHOT_CAPTURE_TIMEOUT_SECONDS
    until File.exist?(path) && File.size?(path)
      check_resource_watchdog!
      if Time.now >= deadline
        disable_screenshot_capture!("Screenshot missing at #{path}", path)
        return nil
      end
      sleep_with_watchdog(0.2)
    end

    path
  end

  def disable_screenshot_capture!(reason, path = nil)
    @capture_screenshots = false
    FileUtils.rm_f(path) if path
    puts "⚠️ Screenshot capture unavailable: #{reason}. Continuing without screenshots."
  end

  def exercise_hidden_visible_moves(candidate)
    if candidate[:zone] == 'hidden'
      move_and_verify('move icon to visible', candidate, 'visible')
      move_and_verify('move icon to hidden', candidate, 'hidden')
    elsif candidate[:zone] == 'alwaysHidden'
      # Some stable test fixtures (e.g. SaneClick) may start in always-hidden.
      # Bring them into the normal flow before running hidden/visible checks.
      move_and_verify('move icon to visible', candidate, 'visible')
      move_and_verify('move icon to hidden', candidate, 'hidden')
    else
      move_and_verify('move icon to hidden', candidate, 'hidden')
      move_and_verify('move icon to visible', candidate, 'visible')
    end
    puts '✅ Hidden/Visible move actions ok'
  end

  def exercise_always_hidden_moves(candidate)
    move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
    move_and_verify('move icon to visible', candidate, 'visible')
    puts '✅ Always Hidden move actions ok'
  rescue StandardError => e
    raise if @require_always_hidden
    if always_hidden_optional_failure?(e)
      puts "ℹ️ Skipping always-hidden move check (likely free mode): #{e.message}"
      return
    end
    raise
  end

  def restore_zone(candidate)
    target = candidate[:zone]
    case target
    when 'hidden'
      move_and_verify('move icon to hidden', candidate, 'hidden')
    when 'alwaysHidden'
      move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
    else
      move_and_verify('move icon to visible', candidate, 'visible')
    end
  end

  def move_and_verify(command, candidate, expected_zone)
    icon_unique_id = resolve_live_move_identifier(candidate)
    icon = escape_quotes(icon_unique_id)
    begin
      result = app_script("#{command} \"#{icon}\"").strip.downcase
      unless %w[true 1].include?(result)
        raise "#{command} returned '#{result}' for #{candidate[:unique_id]}"
      end
    rescue StandardError => e
      raise unless timed_out_move_command?(command, e)

      puts "ℹ️ Salvaging timed-out move command via zone verification for #{icon_unique_id}"
    end

    wait_for_zone(icon_unique_id, candidate, expected_zone)
  end

  def wait_for_zone(icon_unique_id, candidate, expected_zone)
    deadline = Time.now + MAX_WAIT_SECONDS
    last_error = nil
    while Time.now < deadline
      begin
        zones = list_icon_zones
      rescue StandardError => e
        raise unless retryable_zone_poll_error?(e)

        last_error = e
        sleep_with_watchdog(POLL_SECONDS)
        next
      end

      if exact_move_identity_lost?(candidate, icon_unique_id, zones)
        live_ids = same_bundle_movable_candidates(zones, candidate).map { |item| item[:unique_id] }
        raise "Shared-bundle move verification lost exact identity: requested=#{icon_unique_id} bundle=#{candidate[:bundle]} live=#{live_ids.join(', ')}"
      end

      matched = matched_move_candidate(zones, icon_unique_id, candidate)
      return true if matched && matched[:zone] == expected_zone
      sleep_with_watchdog(POLL_SECONDS)
    end

    if last_error
      raise "Timeout waiting for #{candidate[:bundle]} (#{candidate[:name]}) to reach zone #{expected_zone} after transient poll failures: #{last_error.message}"
    end

    raise "Timeout waiting for #{candidate[:bundle]} (#{candidate[:name]}) to reach zone #{expected_zone}"
  end

  def same_bundle_movable_candidates(zones, candidate)
    zones.select { |item| item[:bundle] == candidate[:bundle] && item[:movable] }
  end

  def exact_move_identity_lost?(candidate, requested_unique_id, zones)
    return false unless same_bundle_movable_candidates(zones, candidate).length > 1

    zones.none? { |item| item[:unique_id] == requested_unique_id }
  end

  def matched_move_candidate(zones, requested_unique_id, candidate)
    exact = zones.find { |item| item[:unique_id] == requested_unique_id }
    return exact if exact

    same_bundle = same_bundle_movable_candidates(zones, candidate)
    return nil if same_bundle.length > 1

    zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] } ||
      same_bundle.first
  end

  def resolve_live_move_identifier(candidate)
    zones = list_icon_zones

    exact = zones.find { |item| item[:unique_id] == candidate[:unique_id] }
    return exact[:unique_id] if exact

    same_bundle = same_bundle_movable_candidates(zones, candidate)
    if same_bundle.length > 1
      live_ids = same_bundle.map { |item| item[:unique_id] }
      raise "Shared-bundle move candidate lost exact identity before action: requested=#{candidate[:unique_id]} bundle=#{candidate[:bundle]} live=#{live_ids.join(', ')}"
    end

    bundle_and_name = zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] }
    return bundle_and_name[:unique_id] if bundle_and_name
    return same_bundle.first[:unique_id] if same_bundle.length == 1

    candidate[:unique_id]
  end

  def resolve_live_icon_identifier(candidate)
    zones = list_icon_zones

    exact = zones.find { |item| item[:unique_id] == candidate[:unique_id] }
    return exact[:unique_id] if exact

    bundle_and_name = zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] }
    return bundle_and_name[:unique_id] if bundle_and_name

    bundle_matches = zones.select { |item| item[:bundle] == candidate[:bundle] && item[:movable] }
    return bundle_matches.first[:unique_id] if bundle_matches.length == 1

    candidate[:unique_id]
  end

  def app_script(statement)
    script = %(tell #{apple_script_target} to #{statement})
    attempts = 0
    timeout = app_script_timeout_for(statement)
    begin
      attempts += 1
      out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: timeout)
      raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?
      out
    rescue StandardError => e
      retryable = e.message.include?('timeout') || e.message.include?('failed')
      if attempts < APPLESCRIPT_RETRIES && retryable && !non_idempotent_app_script?(statement)
        sleep_with_watchdog(0.2)
        retry
      end
      raise
    end
  end

  def current_browse_activation_diagnostics
    [
      direct_app_script('activation diagnostics', timeout: 2.5),
      direct_app_script('browse panel diagnostics', timeout: 2.5)
    ].join("\n")
  rescue StandardError
    nil
  end

  def direct_app_script(statement, timeout:)
    script = %(tell #{apple_script_target} to #{statement})
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: timeout)
    raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?

    out
  end

  def salvage_timed_out_browse_activation(live_identifier:, baseline_diagnostics:, error:)
    return nil unless error.message.include?('AppleScript timeout')

    current = current_browse_activation_diagnostics
    return nil if current.nil? || current == baseline_diagnostics
    return nil unless current.include?('origin: browsePanel')
    return nil unless current.include?("requestedApp: id=#{live_identifier}")
    return nil unless current.include?('finalOutcome: click succeeded')
    return nil unless browse_activation_observably_verified?(current)

    puts "ℹ️ Salvaged timed-out browse activation via fresh diagnostics for #{live_identifier}"
    current
  end

  def non_idempotent_app_script?(statement)
    statement.start_with?('activate browse icon ') ||
      statement.start_with?('right click browse icon ')
  end

  def timed_out_move_command?(command, error)
    error.message.include?('AppleScript timeout') &&
      command.start_with?('move icon to ')
  end

  def app_script_timeout_for(statement)
    return APPLESCRIPT_MOVE_TIMEOUT_SECONDS if move_app_script?(statement)
    return APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS if heavy_read_app_script?(statement)

    APPLESCRIPT_TIMEOUT_SECONDS
  end

  def heavy_read_app_script?(statement)
    statement == 'list icon zones' || statement == 'list icons'
  end

  def move_app_script?(statement)
    statement.start_with?('move icon to ')
  end

  def capture2e_with_timeout(*cmd, timeout:)
    output = +''
    status = nil

    Open3.popen2e(*cmd) do |stdin, stdout, wait_thr|
      stdin.close
      reader = Thread.new { stdout.read.to_s }

      begin
        deadline = Time.now + timeout
        loop do
          check_resource_watchdog!
          if wait_thr.join(0.2)
            status = wait_thr.value
            output = reader.value
            break
          end

          raise "AppleScript timeout after #{timeout}s (#{cmd.join(' ')})" if Time.now >= deadline
        end
      rescue StandardError
        terminate_child_process(wait_thr)
        begin
          output = reader.value
        rescue StandardError
          output = ''
        end
        raise
      end
    end

    [output, status]
  end

  def sh(command)
    Open3.capture2e(command)
  end

  def start_resource_watchdog
    return unless @watch_resources
    return if @app_pid.to_i <= 0

    reset_resource_watchdog_state
    FileUtils.rm_f(@resource_sample_path)
    puts format(
      "🫀 Resource watchdog armed: cpu<=%.1f%% for %d sample(s), rss<=%.1fMB for %d sample(s)",
      @max_cpu_percent, @max_cpu_breach_samples, @max_rss_mb, @max_rss_breach_samples
    )
    @resource_watchdog_thread = Thread.new do
      loop do
        break if @resource_watchdog_stop

        sample = read_process_resource_sample
        record_resource_sample(sample)
        break if resource_watchdog_failure

        sleep @resource_poll_seconds
      rescue StandardError => e
        record_resource_watchdog_failure("resource_watchdog process_monitor_failed reason=#{e.message}")
        break
      end
    end
  end

  def stop_resource_watchdog
    @resource_watchdog_stop = true
    return unless @resource_watchdog_thread

    @resource_watchdog_thread.join(2)
    @resource_watchdog_thread = nil
  end

  def reset_resource_watchdog_state
    @resource_watchdog_stop = false
    @resource_watchdog_mutex = Mutex.new
    @resource_watchdog_state = {
      sample_count: 0,
      peak_cpu: 0.0,
      peak_rss_mb: 0.0,
      total_cpu: 0.0,
      total_rss_mb: 0.0,
      last_sample: nil,
      cpu_breach_samples: 0,
      rss_breach_samples: 0,
      failure: nil,
      sample_path: @resource_sample_path
    }
  end

  def record_resource_sample(sample)
    failure = nil

    @resource_watchdog_mutex.synchronize do
      state = @resource_watchdog_state
      state[:sample_count] += 1
      state[:last_sample] = sample
      state[:peak_cpu] = [state[:peak_cpu], sample[:cpu]].max
      state[:peak_rss_mb] = [state[:peak_rss_mb], sample[:rss_mb]].max
      state[:total_cpu] += sample[:cpu]
      state[:total_rss_mb] += sample[:rss_mb]
      state[:cpu_breach_samples] = sample[:cpu] >= @max_cpu_percent ? state[:cpu_breach_samples] + 1 : 0
      state[:rss_breach_samples] = sample[:rss_mb] >= @max_rss_mb ? state[:rss_breach_samples] + 1 : 0
      failure = resource_limit_failure(sample, state)
    end

    return unless failure

    sample_path = capture_resource_sample
    record_resource_watchdog_failure(format_resource_watchdog_failure(failure, sample, sample_path))
  end

  def resource_limit_failure(sample, state)
    if sample[:rss_mb] >= @emergency_rss_mb
      { key: 'peak_rss_exceeded', mode: 'emergency', limit: @emergency_rss_mb, samples: state[:rss_breach_samples] }
    elsif sample[:cpu] >= @emergency_cpu_percent
      { key: 'peak_cpu_exceeded', mode: 'emergency', limit: @emergency_cpu_percent, samples: state[:cpu_breach_samples] }
    elsif state[:rss_breach_samples] >= @max_rss_breach_samples
      { key: 'peak_rss_exceeded', mode: 'sustained', limit: @max_rss_mb, samples: state[:rss_breach_samples] }
    elsif state[:cpu_breach_samples] >= @max_cpu_breach_samples
      { key: 'peak_cpu_exceeded', mode: 'sustained', limit: @max_cpu_percent, samples: state[:cpu_breach_samples] }
    end
  end

  def format_resource_watchdog_failure(failure, sample, sample_path)
    current_value = failure[:key] == 'peak_cpu_exceeded' ? format('%.1f%%', sample[:cpu]) : format('%.1fMB', sample[:rss_mb])
    limit_value = failure[:key] == 'peak_cpu_exceeded' ? format('%.1f%%', failure[:limit]) : format('%.1fMB', failure[:limit])
    sample_label = sample_path && File.exist?(sample_path) ? sample_path : 'unavailable'
    "#{failure[:key]} mode=#{failure[:mode]} current=#{current_value} limit=#{limit_value} "\
      "sustainedSamples=#{failure[:samples]} pid=#{sample[:pid]} elapsed=#{sample[:elapsed]} sample=#{sample_label}"
  end

  def capture_resource_sample
    FileUtils.mkdir_p(File.dirname(@resource_sample_path))
    FileUtils.rm_f(@resource_sample_path)
    _out, status = Open3.capture2e(
      '/usr/bin/sample',
      @app_pid.to_s,
      RESOURCE_SAMPLE_DURATION_SECONDS.to_s,
      RESOURCE_SAMPLE_INTERVAL_MS.to_s,
      '-mayDie',
      '-file', @resource_sample_path
    )
    return @resource_sample_path if status.success? && File.exist?(@resource_sample_path) && !File.zero?(@resource_sample_path)

    nil
  rescue StandardError
    nil
  end

  def read_process_resource_sample
    output, status = Open3.capture2e(
      'ps',
      '-o', 'pid=,%cpu=,rss=,etime=,command=',
      '-p', @app_pid.to_s
    )
    raise 'process_missing' unless status.success?

    line = output.lines.map(&:strip).reject(&:empty?).last
    raise 'process_missing' if line.nil?

    pid, cpu, rss, elapsed, command = line.split(/\s+/, 5)
    raise "process_changed command=#{command}" unless matching_app_process?(command.to_s)

    {
      pid: pid.to_i,
      cpu: cpu.to_f,
      rss_kb: rss.to_i,
      rss_mb: rss.to_f / 1024.0,
      elapsed: elapsed.to_s,
      command: command.to_s
    }
  end

  def record_resource_watchdog_failure(message)
    @resource_watchdog_mutex.synchronize do
      @resource_watchdog_state[:failure] ||= message
    end
  end

  def resource_watchdog_failure
    return nil unless @watch_resources

    @resource_watchdog_mutex.synchronize { @resource_watchdog_state[:failure] }
  end

  def check_resource_watchdog!
    failure = resource_watchdog_failure
    raise failure if failure
  end

  def resource_watchdog_report
    state = @resource_watchdog_mutex.synchronize { @resource_watchdog_state.dup }
    return nil if state[:sample_count].zero? && state[:failure].nil?

    averages = resource_watchdog_averages(state)

    base = format(
      "🫀 Resource watchdog: samples=%d avgCpu=%.1f%% peakCpu=%.1f%% avgRss=%.1fMB peakRss=%.1fMB",
      state[:sample_count],
      averages[:avg_cpu],
      state[:peak_cpu],
      averages[:avg_rss_mb],
      state[:peak_rss_mb]
    )
    return "#{base} failure=#{state[:failure]}" if state[:failure]

    base
  end

  def resource_watchdog_averages(state)
    sample_count = state[:sample_count].to_i
    return { avg_cpu: 0.0, avg_rss_mb: 0.0 } if sample_count <= 0

    {
      avg_cpu: state[:total_cpu].to_f / sample_count,
      avg_rss_mb: state[:total_rss_mb].to_f / sample_count
    }
  end

  def assert_active_average_budget!
    state = @resource_watchdog_mutex.synchronize { @resource_watchdog_state.dup }
    return if state[:sample_count].zero?

    averages = resource_watchdog_averages(state)
    failures = []
    if averages[:avg_cpu] > @active_avg_cpu_max
      failures << format('avgCpu=%.1f%% > %.1f%%', averages[:avg_cpu], @active_avg_cpu_max)
    end
    if averages[:avg_rss_mb] > @active_avg_rss_mb_max
      failures << format('avgRss=%.1fMB > %.1fMB', averages[:avg_rss_mb], @active_avg_rss_mb_max)
    end
    return if failures.empty?

    raise "active_budget_exceeded #{failures.join(' ')}"
  end

  def assert_idle_budget!(label:, settle_seconds:, sample_seconds:, cpu_avg_max:, cpu_peak_max:, rss_mb_max:)
    sleep_with_watchdog(settle_seconds) if settle_seconds.positive?
    report = capture_resource_window(sample_seconds: sample_seconds, interval_seconds: @idle_sample_interval_seconds)
    puts format(
      "📉 Idle budget %s: avgCpu=%.1f%% peakCpu=%.1f%% avgRss=%.1fMB peakRss=%.1fMB",
      label,
      report[:avg_cpu],
      report[:peak_cpu],
      report[:avg_rss_mb],
      report[:peak_rss_mb]
    )

    failures = []
    if report[:avg_cpu] > cpu_avg_max
      failures << format('avgCpu=%.1f%% > %.1f%%', report[:avg_cpu], cpu_avg_max)
    end
    if report[:peak_cpu] > cpu_peak_max
      failures << format('peakCpu=%.1f%% > %.1f%%', report[:peak_cpu], cpu_peak_max)
    end
    if report[:peak_rss_mb] > rss_mb_max
      failures << format('peakRss=%.1fMB > %.1fMB', report[:peak_rss_mb], rss_mb_max)
    end
    return if failures.empty?

    raise "#{label}_idle_budget_exceeded #{failures.join(' ')}"
  end

  def capture_resource_window(sample_seconds:, interval_seconds:)
    started_at = Time.now
    samples = []
    while (Time.now - started_at) < sample_seconds
      check_resource_watchdog!
      samples << read_process_resource_sample
      sleep_with_watchdog(interval_seconds)
    end

    avg_cpu = samples.sum { |sample| sample[:cpu] } / samples.length
    avg_rss_mb = samples.sum { |sample| sample[:rss_mb] } / samples.length
    {
      sample_count: samples.length,
      avg_cpu: avg_cpu,
      peak_cpu: samples.map { |sample| sample[:cpu] }.max || 0.0,
      avg_rss_mb: avg_rss_mb,
      peak_rss_mb: samples.map { |sample| sample[:rss_mb] }.max || 0.0
    }
  end

  def sleep_with_watchdog(duration)
    deadline = Time.now + duration
    while Time.now < deadline
      check_resource_watchdog!
      remaining = deadline - Time.now
      break if remaining <= 0

      sleep([remaining, 0.1].min)
    end
    check_resource_watchdog!
  end

  def terminate_child_process(wait_thr)
    begin
      Process.kill('TERM', wait_thr.pid)
    rescue StandardError
      nil
    end
    return if wait_thr.join(1)

    begin
      Process.kill('KILL', wait_thr.pid)
    rescue StandardError
      nil
    end
    wait_thr.join
  end

  def truthy?(value)
    value == true || value.to_s.casecmp('true').zero?
  end

  def always_hidden_optional_failure?(error)
    message = error.message.to_s
    message.include?('failed to move to alwaysHidden') ||
      message.include?('to reach zone alwaysHidden')
  end

  def zone_api_retryable?(error)
    message = error.message.to_s
    message.include?('Connection is invalid') ||
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
    @require_all_candidates || !@required_candidate_ids.empty?
  end

  def move_candidates_required?
    @require_candidate || strict_candidate_mode?
  end

  def focused_required_id_mode?
    !@required_candidate_ids.empty?
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
    return File.expand_path(binary) == expected if expected

    binary.end_with?("/Contents/MacOS/#{@app_name}") || File.basename(binary) == @app_name
  end

  def apple_script_target
    return %(application id "#{escape_quotes(@app_id)}") if @app_id

    %(application "#{escape_quotes(@app_name)}")
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(LiveZoneSmoke.new.run ? 0 : 1)
end
