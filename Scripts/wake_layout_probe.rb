#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'time'
require 'set'

class WakeLayoutProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  SNAPSHOT_DELAYS = [1.0, 5.0, 15.0].freeze
  SNAPSHOT_SETTLE_TIMEOUT_SECONDS = 18.0
  SNAPSHOT_SETTLE_POLL_SECONDS = 0.5
  HIDDEN_BASELINE_TIMEOUT_SECONDS = 45.0
  DEFAULT_MAIN_RIGHT_GAP_TOLERANCE = 80.0
  REQUIRED_VISIBLE_ID_LIMIT = 6
  REQUIRED_HIDDEN_ID_LIMIT = 6
  BLOCKED_LOG_PATTERNS = [
    /Status item remained off-menu-bar/i,
    /Falling back to separator-only hidden move target without always-hidden boundary/i,
    /Regular hidden move target resolution failed without/i,
    /Bumping autosave version .*status item recovery/i,
    /Status item recovery stopped after/i,
    /geometry drift detected/i
  ].freeze
  REQUIRED_WAKE_PATTERNS = [
    /System did wake/i,
    /Screens did wake/i
  ].freeze
  REQUIRED_POWER_WAKE_PATTERNS = [
    /Display is turned off/i,
    /Display is turned on/i
  ].freeze

  def initialize
    @app_path = ENV.fetch('SANEBAR_SMOKE_APP_PATH', '').strip
    @log_path = ENV.fetch('SANEBAR_WAKE_PROBE_LOG_PATH', '/tmp/sanebar_wake_layout_probe.log')
    @artifact_path = ENV.fetch('SANEBAR_WAKE_PROBE_ARTIFACT_PATH', '/tmp/sanebar_wake_layout_probe.json')
    @display_sleep_seconds = ENV.fetch('SANEBAR_WAKE_PROBE_DISPLAY_SLEEP_SECONDS', '3').to_f
    @wake_assertion_seconds = ENV.fetch('SANEBAR_WAKE_PROBE_WAKE_ASSERTION_SECONDS', '2').to_i
    @main_right_gap_tolerance = ENV.fetch(
      'SANEBAR_WAKE_PROBE_MAIN_RIGHT_GAP_TOLERANCE',
      DEFAULT_MAIN_RIGHT_GAP_TOLERANCE.to_s
    ).to_f
    @workspace = Dir.mktmpdir('sanebar-wake-probe')
    @settings_backup_path = File.join(@workspace, 'settings.json')
    @lines = []
    @cases = []
    @bundle_id = nil
    @app_name = nil
    @had_settings_file = false
    @was_running = false
    @state_restored = false
    @visible_zone_proofs = []
    @hidden_zone_proofs = []
    @dynamic_helper_ids = ENV.fetch('SANEBAR_WAKE_PROBE_DYNAMIC_HELPER_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
  end

  def run
    validate_target!
    @bundle_id = bundle_identifier
    @app_name = File.basename(@app_path, '.app')
    @was_running = app_running?
    backup_state!

    @cases << run_hidden_case
    @cases << run_expanded_case

    restore_state!
    @state_restored = true

    write_artifact!(
      status: 'pass',
      bundle_id: @bundle_id,
      app_path: @app_path,
      cases: @cases
    )
    puts "✅ Wake layout probe passed (#{@cases.map { |entry| entry[:name] }.join(', ')})"
    true
  rescue StandardError => e
    write_artifact!(
      status: 'fail',
      bundle_id: @bundle_id,
      app_path: @app_path,
      error: e.message,
      backtrace: Array(e.backtrace).first(12),
      cases: @cases
    )
    log("❌ Wake layout probe failed: #{e.message}")
    warn e.message
    false
  ensure
    unless @state_restored
      begin
        restore_state!
      rescue StandardError => e
        log("⚠️ Restore failed: #{e.message}")
      end
    end
    persist_log!
    FileUtils.remove_entry(@workspace) if @workspace && Dir.exist?(@workspace)
  end

  private

  def validate_target!
    raise 'SANEBAR_SMOKE_APP_PATH is required' if @app_path.empty?
    raise "Target app missing: #{@app_path}" unless File.directory?(@app_path)
  end

  def backup_state!
    if File.exist?(SETTINGS_PATH)
      FileUtils.mkdir_p(File.dirname(@settings_backup_path))
      FileUtils.cp(SETTINGS_PATH, @settings_backup_path)
      @had_settings_file = true
    end
    log("Backed up settings file=#{@had_settings_file}")
  end

  def restore_state!
    quit_app

    if @had_settings_file
      raise "Missing settings backup #{@settings_backup_path}" unless File.exist?(@settings_backup_path)

      FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
      FileUtils.cp(@settings_backup_path, SETTINGS_PATH)
    else
      FileUtils.rm_f(SETTINGS_PATH)
    end

    launch_app if @was_running
    log('Restored wake probe state')
  end

  def run_hidden_case
    configure_settings!(auto_rehide: true)
    launch_app
    wait_for_healthy_snapshot(label: 'hidden launch baseline')

    app_script('hide items')
    baseline = wait_for_snapshot(label: 'hidden baseline', timeout: HIDDEN_BASELINE_TIMEOUT_SECONDS) do |snapshot|
      snapshot['hidingState'] == 'hidden' && snapshot_healthy?(snapshot)
    end
    seed_dynamic_helper_hidden_ids!
    visible_baseline = capture_visible_zone_baseline!
    if seed_hide_all_other_allowlist?
      seeded_visible_ids = seed_hide_all_other_allowlist!(visible_baseline[:required_visible_ids])
      wait_for_hide_all_other_zone_settle!(seeded_visible_ids)
      app_script('hide items')
      baseline = wait_for_snapshot(label: 'hidden seeded baseline', timeout: HIDDEN_BASELINE_TIMEOUT_SECONDS) do |snapshot|
        snapshot['hidingState'] == 'hidden' && snapshot_healthy?(snapshot)
      end
      visible_baseline = capture_visible_zone_baseline!(required_override: seeded_visible_ids)
    end
    hidden_baseline = capture_hidden_zone_baseline!

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    park_pointer_away_from_menu_bar!(label: 'hidden wake')
    snapshots = snapshots_after_wake(wake_time, label: 'hidden', expected_state: 'hidden')
    snapshots.each do |entry|
      assert_snapshot_state!(entry[:snapshot], expected_state: 'hidden', label: "hidden #{entry[:delay]}s")
      assert_main_right_gap_stable!(baseline, entry[:snapshot], label: "hidden #{entry[:delay]}s")
      assert_visible_zone_persistence!(visible_baseline, entry[:delay])
      assert_hidden_zone_persistence!(hidden_baseline, entry[:delay])
    end
    log_scan = scan_logs_since(case_started_at)

    quit_app

    {
      name: 'hidden state survives display sleep wake',
      baseline: baseline,
      visible_zone_persistence: @visible_zone_proofs,
      hidden_zone_persistence: @hidden_zone_proofs,
      wake_time: wake_time.iso8601,
      snapshots: snapshots,
      log_scan: log_scan
    }
  end

  def run_expanded_case
    configure_settings!(auto_rehide: false)
    launch_app
    wait_for_healthy_snapshot(label: 'expanded launch baseline')

    app_script('show hidden')
    baseline = wait_for_snapshot(label: 'expanded baseline') do |snapshot|
      snapshot['hidingState'] == 'expanded' && snapshot_healthy?(snapshot)
    end

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    park_pointer_away_from_menu_bar!(label: 'expanded wake')
    snapshots = snapshots_after_wake(wake_time, label: 'expanded', expected_state: 'expanded')
    snapshots.each do |entry|
      assert_snapshot_state!(entry[:snapshot], expected_state: 'expanded', label: "expanded #{entry[:delay]}s")
      assert_main_right_gap_stable!(baseline, entry[:snapshot], label: "expanded #{entry[:delay]}s")
    end
    log_scan = scan_logs_since(case_started_at)

    quit_app

    {
      name: 'expanded state stays stable through display sleep wake',
      baseline: baseline,
      wake_time: wake_time.iso8601,
      snapshots: snapshots,
      log_scan: log_scan
    }
  end

  def configure_settings!(auto_rehide:)
    settings = load_settings_json
    settings['autoRehide'] = auto_rehide
    quit_app
    save_settings_json(settings)
    log("Updated settings.json for wake probe: autoRehide=#{auto_rehide}")
  end

  def seed_hide_all_other_allowlist?
    ENV.fetch('SANEBAR_WAKE_PROBE_SEED_HIDE_ALL_OTHER', '1') != '0'
  end

  def seed_hide_all_other_allowlist!(visible_ids)
    required = Array(visible_ids).map(&:to_s).reject(&:empty?).uniq
    raise 'Wake visible-zone proof cannot seed an empty hide-all-other allow-list' if required.empty?

    settings = load_settings_json
    settings['hideAllOtherMenuBarItems'] = true
    settings['hideAllOtherVisibleItemIds'] = required
    quit_app
    save_settings_json(settings)
    log("Seeded hide-all-other visible allow-list for wake probe: #{required.join(', ')}")
    launch_app
    wait_for_healthy_snapshot(label: 'hide-all-other seeded launch baseline')
    required
  end

  def seed_dynamic_helper_hidden_ids!
    return if @dynamic_helper_ids.empty?

    wait_for_dynamic_helper_ids!
    @dynamic_helper_ids.each do |identifier|
      zone = icon_zone_lookup(read_icon_zones!)[identifier]
      next if zone && zone[:zone] == 'hidden'

      escaped_identifier = escape_quotes(identifier)
      result = app_script(%(move icon to hidden "#{escaped_identifier}")).strip.downcase
      raise "Dynamic helper hidden seed failed for #{identifier}: #{result}" unless %w[true 1].include?(result)
    end
    wait_for_icon_zone_persistence!(
      @dynamic_helper_ids,
      expected_zone: 'hidden',
      delay: 0,
      failure_prefix: 'Dynamic helper hidden seed failed'
    )
    log("Seeded dynamic helper hidden IDs: #{@dynamic_helper_ids.join(', ')}")
  end

  def wait_for_dynamic_helper_ids!
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    missing = @dynamic_helper_ids

    while Time.now < deadline
      by_id = icon_zone_lookup(read_icon_zones!)
      missing = @dynamic_helper_ids.reject { |identifier| by_id.key?(identifier) }
      return if missing.empty?

      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "Dynamic helper IDs did not appear before wake proof: #{missing.join(', ')}"
  end

  def trigger_display_sleep_cycle!
    raise 'Display sleep duration must be positive' unless @display_sleep_seconds.positive?

    puts "ℹ️ Wake probe will turn the Mini display off for #{@display_sleep_seconds}s, then wake it for regression proof."
    log("Triggering display sleep for #{@display_sleep_seconds}s")
    out, status = capture('pmset', 'displaysleepnow')
    raise "Failed to trigger display sleep: #{out}" unless status.success?

    sleep @display_sleep_seconds

    log("Triggering wake assertion for #{@wake_assertion_seconds}s")
    out, status = capture('caffeinate', '-u', '-t', @wake_assertion_seconds.to_s)
    raise "Failed to trigger wake assertion: #{out}" unless status.success?

    Time.now.utc
  end

  def snapshots_after_wake(wake_time, label:, expected_state:)
    SNAPSHOT_DELAYS.map do |delay|
      remaining = (wake_time + delay) - Time.now.utc
      sleep remaining if remaining.positive?
      snapshot = wait_for_snapshot(
        label: "#{label} #{delay}s",
        timeout: SNAPSHOT_SETTLE_TIMEOUT_SECONDS,
        interval: SNAPSHOT_SETTLE_POLL_SECONDS
      ) do |candidate|
        candidate['hidingState'] == expected_state && snapshot_healthy?(candidate) &&
          (!candidate.key?('startupItemsValid') || truthy?(candidate['startupItemsValid'])) &&
          !truthy?(candidate['possibleSystemMenuBarSuppression'])
      end
      log(
        "#{label} snapshot after #{delay}s: hidingState=#{snapshot['hidingState']} " \
        "mainRightGap=#{snapshot['mainRightGap']} separatorBeforeMain=#{snapshot['separatorBeforeMain']} " \
        "startupItemsValid=#{snapshot['startupItemsValid']}"
      )
      { delay: delay, snapshot: snapshot }
    end
  end

  def park_pointer_away_from_menu_bar!(label:)
    cliclick = ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick']
      .find { |path| File.executable?(path) }
    raise 'Wake probe requires cliclick on the Mini to park the pointer away from the menu bar' unless cliclick

    out, status = capture(cliclick, 'm:400,400')
    raise "Pointer parking failed after #{label}: #{out}" unless status.success?

    snapshot = wait_for_snapshot(
      label: "#{label} pointer parked",
      timeout: SNAPSHOT_SETTLE_TIMEOUT_SECONDS,
      interval: 0.25
    ) do |candidate|
      candidate['autoRehideBlockReason'] != 'mouse-in-menu-bar-interaction-region'
    end
    log("#{label} pointer parked outside menu-bar interaction region: autoRehideBlockReason=#{snapshot['autoRehideBlockReason']}")
  end

  def capture_visible_zone_baseline!(required_override: nil)
    zones = read_icon_zones!
    visible = zones.select { |item| item[:zone] == 'visible' }
    required = Array(required_override).map(&:to_s).map(&:strip).reject(&:empty?)
    required = ENV.fetch('SANEBAR_WAKE_PROBE_REQUIRED_VISIBLE_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?) if required.empty?
    if required.empty?
      required = visible
        .reject { |item| item[:bundle_id].to_s.start_with?('com.sanebar') || item[:unique_id].to_s.start_with?('com.sanebar') }
        .map { |item| item[:unique_id].to_s.empty? ? item[:bundle_id] : item[:unique_id] }
        .compact
        .reject(&:empty?)
        .first(REQUIRED_VISIBLE_ID_LIMIT)
    end
    raise 'Wake visible-zone proof could not find any baseline visible IDs' if required.empty?

    proof = {
      status: 'baseline',
      delay: 0,
      required_visible_ids: required,
      zones: zones,
      completed_scenario: 'baseline visible icon-zone snapshot before display sleep'
    }
    @visible_zone_proofs << proof
    log("Visible-zone baseline IDs: #{required.join(', ')}")
    proof
  end

  def wait_for_hide_all_other_zone_settle!(visible_ids)
    required = Array(visible_ids).map(&:to_s).reject(&:empty?)
    allowed = required.to_set
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    last_problem = nil

    while Time.now < deadline
      zones = read_icon_zones!
      by_id = icon_zone_lookup(zones)
      missing_visible = required.select { |identifier| by_id[identifier].nil? || by_id[identifier][:zone] != 'visible' }
      exposed_unallowed = zones.select do |item|
        item[:zone] == 'visible' &&
          item[:movable].to_s == 'true' &&
          !item[:bundle_id].to_s.start_with?('com.sanebar') &&
          !item[:unique_id].to_s.start_with?('com.sanebar') &&
          !item[:bundle_id].to_s.start_with?('com.apple.') &&
          !allowed.include?(item[:unique_id].to_s) &&
          !allowed.include?(item[:bundle_id].to_s)
      end

      if missing_visible.empty? && exposed_unallowed.empty?
        log("Hide-all-other seeded icon zones settled with visible allow-list: #{required.join(', ')}")
        return zones
      end

      last_problem = {
        missing_visible: missing_visible,
        exposed_unallowed: exposed_unallowed.map { |item| "#{item[:unique_id]}:#{item[:zone]}" }
      }
      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "Hide-all-other seeded baseline did not settle before wake proof: #{last_problem.inspect}"
  end

  def assert_visible_zone_persistence!(baseline, delay)
    required = Array(baseline[:required_visible_ids])
    zones = wait_for_icon_zone_persistence!(
      required,
      expected_zone: 'visible',
      delay: delay,
      failure_prefix: 'Visible-zone persistence failed'
    )

    scenario = case delay.to_f
               when 1.0 then 'fresh authoritative icon-zone snapshot at 1s after wake'
               when 5.0 then 'fresh authoritative icon-zone snapshot at 5s after wake'
               when 15.0 then 'fresh authoritative icon-zone snapshot at 15s after wake'
               else "fresh authoritative icon-zone snapshot at #{delay}s after wake"
               end
    proof = {
      status: 'passed',
      delay: delay,
      required_visible_ids: required,
      zones: zones,
      completed_scenarios: [
        scenario,
        'visible required IDs remain visible and are not moved into Hidden or Always Hidden'
      ]
    }
    @visible_zone_proofs << proof
    log("Visible-zone persistence ok after #{delay}s for #{required.join(', ')}")
  end

  def capture_hidden_zone_baseline!
    zones = read_icon_zones!
    hidden = zones.select { |item| item[:zone] == 'hidden' }
    required = ENV.fetch('SANEBAR_WAKE_PROBE_REQUIRED_HIDDEN_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
    required |= @dynamic_helper_ids
    if required.empty?
      required = hidden
        .reject { |item| item[:bundle_id].to_s.start_with?('com.sanebar') || item[:unique_id].to_s.start_with?('com.sanebar') }
        .map { |item| item[:unique_id].to_s.empty? ? item[:bundle_id] : item[:unique_id] }
        .compact
        .reject(&:empty?)
        .first(REQUIRED_HIDDEN_ID_LIMIT)
    end
    raise 'Wake hidden-zone proof could not find any baseline hidden IDs' if required.empty?

    proof = {
      status: 'baseline',
      delay: 0,
      required_hidden_ids: required,
      dynamic_helper_ids: @dynamic_helper_ids,
      zones: zones,
      completed_scenarios: [
        'baseline hidden icon-zone snapshot before display sleep',
        (@dynamic_helper_ids.empty? ? nil : 'dynamic helper required IDs are present before wake')
      ].compact
    }
    @hidden_zone_proofs << proof
    log("Hidden-zone baseline IDs: #{required.join(', ')}")
    proof
  end

  def assert_hidden_zone_persistence!(baseline, delay)
    required = Array(baseline[:required_hidden_ids])
    zones = wait_for_icon_zone_persistence!(
      required,
      expected_zone: 'hidden',
      delay: delay,
      failure_prefix: 'Hidden-zone persistence failed'
    )
    by_id = icon_zone_lookup(zones)
    missing = required.select { |identifier| by_id[identifier].nil? }
    present_hidden = required - missing
    if present_hidden.empty?
      raise "Hidden-zone persistence could not prove any baseline hidden IDs stayed present after #{delay}s"
    end

    scenario = case delay.to_f
               when 1.0 then 'fresh authoritative icon-zone snapshot at 1s after wake'
               when 5.0 then 'fresh authoritative icon-zone snapshot at 5s after wake'
               when 15.0 then 'fresh authoritative icon-zone snapshot at 15s after wake'
               else "fresh authoritative icon-zone snapshot at #{delay}s after wake"
               end
    proof = {
      status: 'passed',
      delay: delay,
      required_hidden_ids: required,
      dynamic_helper_ids: @dynamic_helper_ids,
      missing_hidden_ids: missing,
      zones: zones,
      completed_scenarios: [
        scenario,
        'hidden required IDs remain hidden and are not moved into Visible or Always Hidden',
        (@dynamic_helper_ids.empty? ? nil : 'dynamic helper required IDs remain in intended zones after wake'),
        (@dynamic_helper_ids.empty? ? nil : 'helper-specific Hidden to Visible drift is rejected as a release blocker')
      ].compact
    }
    @hidden_zone_proofs << proof
    log("Hidden-zone persistence ok after #{delay}s for #{present_hidden.join(', ')}")
  end

  def wait_for_icon_zone_persistence!(required, expected_zone:, delay:, failure_prefix:)
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    last_moved = []

    while Time.now < deadline
      zones = read_icon_zones!
      by_id = icon_zone_lookup(zones)
      moved = required.map do |identifier|
        item = by_id[identifier]
        if item.nil?
          "#{identifier}:missing"
        elsif item[:zone] != expected_zone
          "#{identifier}:#{item[:zone]}"
        end
      end.compact
      return zones if moved.empty?

      last_moved = moved
      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "#{failure_prefix} after #{delay}s: #{last_moved.join(', ')}"
  end

  def read_icon_zones!
    raw = app_script('list authoritative icon zones')
    zones = raw.each_line.map do |line|
      parts = line.strip.split("\t", 5)
      next if parts.length < 5

      {
        zone: parts[0],
        movable: parts[1],
        bundle_id: parts[2],
        unique_id: parts[3],
        name: parts[4]
      }
    end.compact
    raise "list authoritative icon zones returned no parseable rows: #{raw.inspect}" if zones.empty?

    zones
  end

  def icon_zone_lookup(zones)
    zones.each_with_object({}) do |item, by_id|
      [item[:unique_id], item[:bundle_id]].each do |identifier|
        next if identifier.to_s.empty?

        by_id[identifier] = item
      end
    end
  end

  def scan_logs_since(started_at)
    predicate = "process == \"#{@app_name}\""
    start_arg = started_at.utc.strftime('%Y-%m-%d %H:%M:%S')
    out, status = capture(
      'log', 'show',
      '--style', 'compact',
      '--info',
      '--start', start_arg,
      '--predicate', predicate
    )
    raise "Could not read logs for #{@app_name}" unless status.success?

    blocked_hits = out.each_line.select do |line|
      BLOCKED_LOG_PATTERNS.any? { |pattern| line.match?(pattern) }
    end.map(&:strip)
    wake_hits = out.each_line.select do |line|
      REQUIRED_WAKE_PATTERNS.any? { |pattern| line.match?(pattern) }
    end.map(&:strip)
    power_wake_hits = scan_power_wake_events_since(started_at)

    raise "Wake probe hit destructive recovery logs: #{blocked_hits.first(3).join(' | ')}" unless blocked_hits.empty?
    if wake_hits.empty? && !power_wake_hits[:observed_display_cycle]
      raise 'Wake probe did not observe app wake logs or system display off/on events'
    end

    {
      observed_logs: out.lines.any? { |line| line.match?(/^\d{4}-\d{2}-\d{2}/) },
      observed_wake_logs: !wake_hits.empty?,
      wake_hits: wake_hits.first(6),
      observed_power_wake_events: power_wake_hits[:observed_display_cycle],
      power_wake_hits: power_wake_hits[:hits].first(6),
      blocked_hits: blocked_hits
    }
  end

  def scan_power_wake_events_since(started_at)
    out, status = Open3.capture2e('pmset', '-g', 'log')
    log('$ pmset -g log')
    raise 'Could not read pmset logs for wake proof' unless status.success?

    start_arg = started_at.getlocal.strftime('%Y-%m-%d %H:%M:%S')
    hits = out.each_line.select do |line|
      line >= start_arg && REQUIRED_POWER_WAKE_PATTERNS.any? { |pattern| line.match?(pattern) }
    end.map(&:strip)
    {
      observed_display_cycle: hits.any? { |line| line.match?(/Display is turned off/i) } &&
        hits.any? { |line| line.match?(/Display is turned on/i) },
      hits: hits
    }.tap { log("Power wake proof hits: #{hits.join(' | ')}") }
  end

  def wait_for_snapshot(label:, timeout: 20.0, interval: 0.5)
    deadline = Time.now + timeout
    last_snapshot = nil

    while Time.now < deadline
      last_snapshot = read_layout_snapshot!
      if yield(last_snapshot)
        log("#{label} ready: hidingState=#{last_snapshot['hidingState']} mainRightGap=#{last_snapshot['mainRightGap']}")
        return last_snapshot
      end
      sleep interval
    end

    raise "#{label} did not stabilize before timeout: #{last_snapshot.inspect}"
  end

  def assert_snapshot_state!(snapshot, expected_state:, label:)
    raise "#{label}: unexpected hidingState #{snapshot['hidingState'].inspect}" unless snapshot['hidingState'] == expected_state
    raise "#{label}: autoRehide flag missing" unless snapshot.key?('autoRehideEnabled')
    raise "#{label}: geometry unavailable" unless snapshot_healthy?(snapshot)
    raise "#{label}: status items are not attached to valid menu bar windows" if snapshot.key?('startupItemsValid') && !truthy?(snapshot['startupItemsValid'])
    if truthy?(snapshot['possibleSystemMenuBarSuppression'])
      raise "#{label}: macOS may be suppressing SaneBar in System Settings > Menu Bar > Allow in Menu Bar"
    end
  end

  def snapshot_healthy?(snapshot)
    snapshot['geometryAvailable'] && snapshot['separatorBeforeMain'] && snapshot['mainNearControlCenter']
  end

  def wait_for_healthy_snapshot(label:)
    wait_for_snapshot(
      label: label,
      timeout: HIDDEN_BASELINE_TIMEOUT_SECONDS,
      interval: SNAPSHOT_SETTLE_POLL_SECONDS
    ) do |snapshot|
      snapshot_healthy?(snapshot) &&
        (!snapshot.key?('startupItemsValid') || truthy?(snapshot['startupItemsValid'])) &&
        !truthy?(snapshot['possibleSystemMenuBarSuppression'])
    end
  end

  def assert_main_right_gap_stable!(baseline, current, label:)
    baseline_gap = numeric_snapshot_value(baseline, 'mainRightGap')
    current_gap = numeric_snapshot_value(current, 'mainRightGap')
    return unless baseline_gap && current_gap

    drift = (current_gap - baseline_gap).abs
    return if drift <= @main_right_gap_tolerance

    raise "#{label}: mainRightGap drifted by #{drift.round(2)}px (#{baseline_gap} → #{current_gap})"
  end

  def bundle_identifier
    return @bundle_id if @bundle_id

    info_plist = File.join(@app_path, 'Contents', 'Info.plist')
    out, status = capture('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', info_plist)
    raise "Could not read bundle identifier from #{info_plist}" unless status.success?

    value = out.strip
    raise "Empty bundle identifier for #{@app_path}" if value.empty?

    @bundle_id = value
  end

  def app_running?
    _out, status = capture('pgrep', '-x', @app_name.to_s)
    status.success?
  end

  def quit_app
    return unless @app_name
    return unless app_running?

    capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to quit")
    deadline = Time.now + 10
    while app_running? && Time.now < deadline
      sleep 0.2
    end
    raise "Timed out waiting for #{@app_name} to quit" if app_running?
  end

  def launch_app
    if no_keychain_launch?
      launch_app_direct
    else
      out, status = capture('open', @app_path)
      raise "Failed to launch #{@app_path}: #{out}" unless status.success?
    end

    deadline = Time.now + 20
    until Time.now >= deadline
      break if app_running? && layout_snapshot_available?
      sleep 0.25
    end

    raise "Timed out waiting for #{@app_name} launch" unless app_running? && layout_snapshot_available?
  end

  def no_keychain_launch?
    ENV['SANEAPPS_DISABLE_KEYCHAIN'] == '1' || ENV['SANEBAR_PROBE_FORCE_NO_KEYCHAIN'] == '1'
  end

  def launch_app_direct
    binary = File.join(@app_path, 'Contents', 'MacOS', @app_name)
    raise "Executable missing for #{@app_path}" unless File.executable?(binary)

    log("Launching #{@app_name} directly with --sane-no-keychain")
    Process.detach(
      Process.spawn(
        { 'SANEAPPS_DISABLE_KEYCHAIN' => '1' },
        binary,
        '--sane-no-keychain',
        out: '/tmp/sanebar_wake_probe_launch.log',
        err: '/tmp/sanebar_wake_probe_launch.log'
      )
    )
  rescue StandardError => e
    raise "Failed to launch #{@app_path} directly: #{e.message}"
  end

  def layout_snapshot_available?
    read_layout_snapshot!
    true
  rescue StandardError
    false
  end

  def read_layout_snapshot!
    out, status = capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to layout snapshot")
    raise "layout snapshot failed: #{out}" unless status.success?

    JSON.parse(out)
  rescue JSON::ParserError => e
    raise "layout snapshot returned invalid JSON: #{e.message}"
  end

  def app_script(statement)
    out, status = capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to #{statement}")
    raise "AppleScript failed (#{statement}): #{out.strip}" unless status.success?

    out
  end

  def escape_quotes(value)
    value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  end

  def load_settings_json
    return {} unless File.exist?(SETTINGS_PATH)

    JSON.parse(File.read(SETTINGS_PATH))
  rescue JSON::ParserError => e
    raise "Could not parse #{SETTINGS_PATH}: #{e.message}"
  end

  def save_settings_json(payload)
    FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
    File.write(SETTINGS_PATH, JSON.pretty_generate(payload) + "\n")
  end

  def numeric_snapshot_value(snapshot, key)
    value = snapshot[key]
    return value.to_f if value.is_a?(Numeric)
    return Float(value) if value.is_a?(String)

    nil
  rescue ArgumentError
    nil
  end

  def truthy?(value)
    value == true || value.to_s.downcase == 'true'
  end

  def capture(*cmd)
    out, status = Open3.capture2e(*cmd)
    log("$ #{cmd.join(' ')}")
    log(out.strip) unless out.strip.empty?
    [out, status]
  end

  def log(line)
    @lines << "[#{Time.now.utc.iso8601}] #{line}"
  end

  def persist_log!
    FileUtils.mkdir_p(File.dirname(@log_path))
    File.write(@log_path, @lines.join("\n") + "\n")
  end

end


require_relative 'lib/wake_layout_probe_artifacts'

exit(WakeLayoutProbe.new.run ? 0 : 1) if __FILE__ == $PROGRAM_NAME
