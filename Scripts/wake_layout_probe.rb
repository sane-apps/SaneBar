#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'time'
require 'set'
require 'securerandom'
require 'socket'

class WakeLayoutProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  RUNTIME_TARGET_LOCK_PATH = ENV['SANEBAR_RUNTIME_TARGET_LOCK_PATH'] ||
                             ENV['SANEMASTER_RUNTIME_PROBE_LOCK_PATH'] ||
                             '/tmp/sanebar_runtime_probe.lock'
  SNAPSHOT_DELAYS = [1.0, 5.0, 15.0].freeze
  SNAPSHOT_SETTLE_TIMEOUT_SECONDS = 18.0
  SNAPSHOT_SETTLE_POLL_SECONDS = 0.5
  HIDDEN_BASELINE_TIMEOUT_SECONDS = 45.0
  DEFAULT_MAIN_RIGHT_GAP_TOLERANCE = 80.0
  CAPTURE_LOG_OUTPUT_MAX_BYTES = 16_000
  PARKED_CURSOR_X = 400.0
  PARKED_CURSOR_Y = 400.0
  PARKED_CURSOR_TOLERANCE = 3.0
  PARKED_CURSOR_SETTLE_TIMEOUT_SECONDS = 6.0
  PARKED_CURSOR_SETTLE_POLL_SECONDS = 0.25
  REQUIRED_VISIBLE_ID_LIMIT = 6
  REQUIRED_HIDDEN_ID_LIMIT = 6
  DEFAULT_GRACEFUL_QUIT_TIMEOUT_SECONDS = 3.0
  DEFAULT_FORCE_QUIT_TIMEOUT_SECONDS = 2.0
  NO_KEYCHAIN_LAUNCH_REGISTRATION_GRACE_SECONDS = 1.5
  AUTOMATION_QUIT_TOKEN_ENV = 'SANEBAR_AUTOMATION_QUIT_TOKEN'
  DEFAULT_AUTOMATION_QUIT_MARKER_PATH = '/tmp/sanebar_explicit_termination.token'
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

  def self.acquire_runtime_target_lock
    return nil if ENV['SANEBAR_RUNTIME_TARGET_LOCK_BYPASS'] == '1'

    raise Errno::ELOOP if File.symlink?(RUNTIME_TARGET_LOCK_PATH)

    2.times do
      cleanup_runtime_target_lock_file
      lock_file = publish_runtime_target_lock_file('wake-layout-probe')
      return lock_file if lock_file
    end

    holder = runtime_target_lock_holder_detail
    detail = holder.empty? ? '' : " (#{holder})"
    warn "Wake layout probe refused to run because the SaneBar runtime target is locked#{detail}."
    false
  rescue Errno::ELOOP
    warn "Wake layout probe refused to use unsafe symlink lock path: #{RUNTIME_TARGET_LOCK_PATH}"
    false
  end

  def self.release_runtime_target_lock(lock_file)
    return unless lock_file

    begin
      lock_file.flock(File::LOCK_UN)
    rescue StandardError
      nil
    end
    begin
      lock_file.close unless lock_file.closed?
    rescue StandardError
      nil
    end
    cleanup_runtime_target_lock_file
  end

  def self.open_runtime_target_lock
    File.open(RUNTIME_TARGET_LOCK_PATH, runtime_target_lock_open_flags, 0o600)
  end

  def self.publish_runtime_target_lock_file(command)
    FileUtils.mkdir_p(File.dirname(RUNTIME_TARGET_LOCK_PATH))
    temp_path = runtime_target_lock_temp_path
    published = false
    lock_file = File.open(temp_path, runtime_target_lock_publish_flags, 0o600)
    lock_file.flock(File::LOCK_EX)
    lock_file.write("pid=#{Process.pid} started=#{Time.now.utc.iso8601} command=#{command}\n")
    lock_file.flush
    File.link(temp_path, RUNTIME_TARGET_LOCK_PATH)
    published = true
    lock_file
  rescue Errno::EEXIST
    nil
  ensure
    FileUtils.rm_f(temp_path) if temp_path && File.exist?(temp_path)
    unless published
      begin
        lock_file&.flock(File::LOCK_UN)
      rescue StandardError
        nil
      end
      begin
        lock_file&.close unless lock_file&.closed?
      rescue StandardError
        nil
      end
    end
  end

  def self.runtime_target_lock_temp_path
    dir = File.dirname(RUNTIME_TARGET_LOCK_PATH)
    base = File.basename(RUNTIME_TARGET_LOCK_PATH)
    File.join(dir, ".#{base}.#{Process.pid}.#{rand(1_000_000)}.tmp")
  end

  def self.runtime_target_lock_publish_flags
    flags = File::RDWR | File::CREAT | File::EXCL
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def self.runtime_target_lock_open_flags
    flags = File::RDWR | File::CREAT
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def self.cleanup_runtime_target_lock_file
    return unless File.exist?(RUNTIME_TARGET_LOCK_PATH)

    cleanup_lock = open_runtime_target_lock
    return unless cleanup_lock

    return unless cleanup_lock.flock(File::LOCK_EX | File::LOCK_NB)

    FileUtils.rm_f(RUNTIME_TARGET_LOCK_PATH)
  rescue Errno::ENOENT, Errno::ELOOP
    nil
  ensure
    if cleanup_lock
      begin
        cleanup_lock.flock(File::LOCK_UN)
      rescue StandardError
        nil
      end
      begin
        cleanup_lock.close unless cleanup_lock.closed?
      rescue StandardError
        nil
      end
    end
  end

  def self.runtime_target_lock_holder_detail
    return '' unless File.exist?(RUNTIME_TARGET_LOCK_PATH)

    File.open(RUNTIME_TARGET_LOCK_PATH, runtime_target_lock_read_flags) do |file|
      file.read.to_s.strip
    end
  rescue Errno::ENOENT
    ''
  end

  def self.runtime_target_lock_read_flags
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

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
    @seeded_explicit_divider_keys = nil
    @direct_launch_pids = []
    @automation_quit_token = nil
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
    @cases << run_explicit_divider_survival_case if explicit_divider_survival_enabled?
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
  rescue SignalException => e
    write_artifact!(
      status: 'fail',
      bundle_id: @bundle_id,
      app_path: @app_path,
      error: "Wake probe interrupted by #{e.class}: #{e.message}",
      signal: e.signo,
      backtrace: Array(e.backtrace).first(12),
      cases: @cases
    )
    log("❌ Wake layout probe interrupted: #{e.class} #{e.message}")
    warn "Wake probe interrupted by #{e.class}: #{e.message}"
    false
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
    if safe_existing_file?(SETTINGS_PATH)
      FileUtils.mkdir_p(File.dirname(@settings_backup_path))
      safe_copy_file(SETTINGS_PATH, @settings_backup_path)
      @had_settings_file = true
    end
    log("Backed up settings file=#{@had_settings_file}")
  end
  def restore_state!
    quit_app
    clear_seeded_explicit_divider_defaults!
    if @had_settings_file
      raise "Missing settings backup #{@settings_backup_path}" unless File.exist?(@settings_backup_path)
      FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
      safe_copy_file(@settings_backup_path, SETTINGS_PATH)
    else
      safe_remove_file(SETTINGS_PATH)
    end
    launch_app if @was_running
    log('Restored wake probe state')
  end

  # The FM-2 case seeds explicit preferred-position defaults; remove them on
  # teardown so the probe leaves no persisted divider behind. The app re-seeds
  # ordinal defaults on next launch when these are absent.
  def clear_seeded_explicit_divider_defaults!
    return unless @seeded_explicit_divider_keys

    @seeded_explicit_divider_keys.each do |key|
      capture('defaults', 'delete', bundle_identifier, key)
    end
    @seeded_explicit_divider_keys = nil
  rescue StandardError => e
    log("⚠️ Could not clear seeded explicit divider defaults: #{e.message}")
  end

  def run_hidden_case
    configure_settings!(auto_rehide: true)
    launch_app
    wait_for_configured_launch_baseline(label: 'hidden launch baseline', auto_rehide: true)

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
      wait_for_hide_all_other_zone_settle!(seeded_visible_ids)
      visible_baseline = capture_visible_zone_baseline!(required_override: seeded_visible_ids)
    end
    hidden_baseline = capture_hidden_zone_baseline!

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    parked_cursor = park_pointer_away_from_menu_bar!(label: 'hidden wake')
    snapshots = snapshots_after_wake(wake_time, label: 'hidden', expected_state: 'hidden')
    snapshots.each do |entry|
      assert_snapshot_state!(entry[:snapshot], expected_state: 'hidden', label: "hidden #{entry[:delay]}s")
      assert_main_right_gap_stable!(baseline, entry[:snapshot], label: "hidden #{entry[:delay]}s")
      assert_visible_zone_persistence!(visible_baseline, entry[:delay])
      assert_hidden_zone_persistence!(hidden_baseline, entry[:delay])
    end
    cursor_proof = assert_cursor_stable!(parked_cursor, label: 'hidden passive wake recovery')
    log_scan = scan_logs_since(case_started_at)

    quit_app

    {
      name: 'hidden state survives display sleep wake',
      baseline: baseline,
      visible_zone_persistence: @visible_zone_proofs,
      hidden_zone_persistence: @hidden_zone_proofs,
      cursor_proof: cursor_proof,
      wake_time: wake_time.iso8601,
      snapshots: snapshots,
      log_scan: log_scan
    }
  end

  def run_expanded_case
    configure_settings!(auto_rehide: false)
    launch_app
    wait_for_configured_launch_baseline(label: 'expanded launch baseline', auto_rehide: false)

    app_script('show hidden')
    baseline = wait_for_snapshot(label: 'expanded baseline') do |snapshot|
      snapshot['hidingState'] == 'expanded' && snapshot_healthy?(snapshot)
    end

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    parked_cursor = park_pointer_away_from_menu_bar!(label: 'expanded wake')
    snapshots = snapshots_after_wake(wake_time, label: 'expanded', expected_state: 'expanded')
    snapshots.each do |entry|
      assert_snapshot_state!(entry[:snapshot], expected_state: 'expanded', label: "expanded #{entry[:delay]}s")
      assert_main_right_gap_stable!(baseline, entry[:snapshot], label: "expanded #{entry[:delay]}s")
    end
    cursor_proof = assert_cursor_stable!(parked_cursor, label: 'expanded passive wake recovery')
    log_scan = scan_logs_since(case_started_at)

    quit_app

    {
      name: 'expanded state stays stable through display sleep wake',
      baseline: baseline,
      cursor_proof: cursor_proof,
      wake_time: wake_time.iso8601,
      snapshots: snapshots,
      log_scan: log_scan
    }
  end

  # FM-2 runtime regression gate (#136/#168).
  #
  # Root failure mode: an EXPLICIT user divider that is set far from Control Center
  # gets silently reanchored TOWARD Control Center during ordinary steady-state
  # validation (wake / Space change / app activation), because the recovery action
  # selector (`shouldResetPersistentStateForStatusItemRecovery`) was context-blind
  # and forced a destructive reset for transient `.missingCoordinates` /
  # `.invalidGeometry` reasons that fire during ordinary validation on macOS 26/27.
  #
  # Why the prior probes missed it: every existing wake/layout case asserts
  # `snapshot_healthy?`, which REQUIRES `mainNearControlCenter == true`. They could
  # never observe the reanchor because their baseline already had the divider near
  # Control Center — exactly where the bug would move it. This case instead seeds an
  # explicit FAR-from-Control-Center divider, drives a real `wakeResume` validation
  # pass (pmset displaysleepnow + caffeinate), and asserts the persisted divider did
  # NOT move toward Control Center and did NOT flip `mainNearControlCenter` true.
  #
  # Determinism: the explicit divider is written directly to the persisted
  # preferred-position pair (resolved against the live autosave version), so no
  # drag / third-party app / Space-switch is needed. The wake cycle is the same
  # deterministic mechanism the existing wake cases already rely on.
  def run_explicit_divider_survival_case
    configure_settings!(auto_rehide: true)
    seed_explicit_far_divider!
    launch_app
    baseline = wait_for_explicit_divider_baseline!

    persisted_main_before = numeric_snapshot_value(baseline, 'persistedMainPreferredPosition')
    persisted_separator_before = numeric_snapshot_value(baseline, 'persistedSeparatorPreferredPosition')
    right_gap_before = numeric_snapshot_value(baseline, 'mainRightGap')
    log(
      "explicit divider baseline: persistedMain=#{persisted_main_before.inspect} " \
      "persistedSeparator=#{persisted_separator_before.inspect} mainRightGap=#{right_gap_before.inspect} " \
      "mainNearControlCenter=#{baseline['mainNearControlCenter']}"
    )
    assert_explicit_divider_baseline_is_far!(baseline, persisted_main_before: persisted_main_before)

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    park_pointer_away_from_menu_bar!(label: 'explicit divider wake')

    snapshots = explicit_divider_snapshots_after_wake(wake_time)
    snapshots.each do |entry|
      assert_explicit_divider_survived!(
        entry[:snapshot],
        persisted_main_before: persisted_main_before,
        persisted_separator_before: persisted_separator_before,
        label: "explicit divider #{entry[:delay]}s"
      )
    end
    log_scan = scan_logs_since(case_started_at)

    quit_app

    {
      name: 'explicit far-from-control-center divider survives wake validation',
      baseline: {
        'persistedMainPreferredPosition' => persisted_main_before,
        'persistedSeparatorPreferredPosition' => persisted_separator_before,
        'mainRightGap' => right_gap_before
      },
      wake_time: wake_time.iso8601,
      snapshots: snapshots,
      log_scan: log_scan
    }
  end

  def explicit_divider_survival_enabled?
    ENV.fetch('SANEBAR_WAKE_PROBE_EXPLICIT_DIVIDER_SURVIVAL', '1') != '0'
  end

  # The gate is only meaningful if the explicit far divider actually survived cold
  # launch (a far-but-fittable position must be preserved per invariant #5; only
  # genuinely off-screen/unfittable positions legitimately reset at startup). If
  # launch already pulled it near Control Center, the wake assertion would be a
  # false green — fail loudly instead. This also catches a launch-path regression.
  EXPLICIT_DIVIDER_BASELINE_MIN_FAR_POSITION = 400

  def assert_explicit_divider_baseline_is_far!(baseline, persisted_main_before:)
    if truthy?(baseline['mainNearControlCenter'])
      raise 'FM-2 gate baseline invalid: the explicit far divider was pulled near Control Center at COLD LAUNCH (mainNearControlCenter=true). Either the seed did not take or the launch path reanchored a fittable explicit divider (a launch-path regression of invariant #5).'
    end

    if persisted_main_before && persisted_main_before < EXPLICIT_DIVIDER_BASELINE_MIN_FAR_POSITION
      raise "FM-2 gate baseline invalid: seeded explicit divider did not survive cold launch (persistedMain=#{persisted_main_before}, expected >= #{EXPLICIT_DIVIDER_BASELINE_MIN_FAR_POSITION}). The wake-survival assertion would be a false green."
    end
  end

  # Seed an explicit pixel divider intentionally LEFT of the launch-safe limit
  # (genuine far-from-Control-Center user layout). main is the icon distance from
  # the right edge; separator must sit to the right of main. These values are large
  # enough that `mainNearControlCenter` is false and any reanchor toward Control
  # Center is unambiguous.
  EXPLICIT_FAR_DIVIDER_MAIN_POSITION = 900
  EXPLICIT_FAR_DIVIDER_SEPARATOR_POSITION = 940

  def seed_explicit_far_divider!
    quit_app
    version = resolved_autosave_version
    main_key = "NSStatusItem Preferred Position SaneBar_Main_v#{version}"
    separator_key = "NSStatusItem Preferred Position SaneBar_Separator_v#{version}"

    write_default_float(main_key, EXPLICIT_FAR_DIVIDER_MAIN_POSITION)
    write_default_float(separator_key, EXPLICIT_FAR_DIVIDER_SEPARATOR_POSITION)
    @seeded_explicit_divider_keys = [main_key, separator_key]
    log("Seeded explicit far divider: #{main_key}=#{EXPLICIT_FAR_DIVIDER_MAIN_POSITION} #{separator_key}=#{EXPLICIT_FAR_DIVIDER_SEPARATOR_POSITION}")
  end

  def resolved_autosave_version
    out, status = capture('defaults', 'read', bundle_identifier, 'SaneBar_AutosaveVersion')
    return out.strip.to_i if status.success? && out.strip.to_i.positive?

    7
  end

  def write_default_float(key, value)
    out, status = capture('defaults', 'write', bundle_identifier, key, '-float', value.to_s)
    raise "Could not seed default #{key}: #{out}" unless status.success?
  end

  def wait_for_explicit_divider_baseline!
    wait_for_snapshot(label: 'explicit divider launch baseline', timeout: HIDDEN_BASELINE_TIMEOUT_SECONDS) do |snapshot|
      snapshot['geometryAvailable'] &&
        snapshot.key?('persistedMainPreferredPosition') &&
        !numeric_snapshot_value(snapshot, 'persistedMainPreferredPosition').nil? &&
        (!snapshot.key?('startupItemsValid') || truthy?(snapshot['startupItemsValid'])) &&
        !truthy?(snapshot['possibleSystemMenuBarSuppression'])
    end
  end

  def explicit_divider_snapshots_after_wake(wake_time)
    SNAPSHOT_DELAYS.map do |delay|
      remaining = (wake_time + delay) - Time.now.utc
      sleep remaining if remaining.positive?
      snapshot = wait_for_snapshot(
        label: "explicit divider #{delay}s",
        timeout: SNAPSHOT_SETTLE_TIMEOUT_SECONDS,
        interval: SNAPSHOT_SETTLE_POLL_SECONDS
      ) do |candidate|
        candidate['geometryAvailable'] && candidate.key?('persistedMainPreferredPosition')
      end
      { delay: delay, snapshot: snapshot }
    end
  end

  # Tolerance for legitimate sub-pixel float round-trips. A reanchor toward Control
  # Center moves the persisted main position by hundreds of points, so a tight
  # tolerance reliably catches the regression without flaking on noise.
  EXPLICIT_DIVIDER_PERSIST_TOLERANCE = 8.0

  def assert_explicit_divider_survived!(snapshot, persisted_main_before:, persisted_separator_before:, label:)
    main_after = numeric_snapshot_value(snapshot, 'persistedMainPreferredPosition')
    separator_after = numeric_snapshot_value(snapshot, 'persistedSeparatorPreferredPosition')

    if persisted_main_before && main_after
      drift = (main_after - persisted_main_before).abs
      if drift > EXPLICIT_DIVIDER_PERSIST_TOLERANCE
        raise "#{label}: FM-2 ROOT CAUSE DETECTED — explicit persisted divider (main) reanchored by #{drift.round(2)}pt during wake validation (#{persisted_main_before} → #{main_after}). The user's divider was silently overwritten toward Control Center (#136/#168)."
      end
    end

    if persisted_separator_before && separator_after
      drift = (separator_after - persisted_separator_before).abs
      if drift > EXPLICIT_DIVIDER_PERSIST_TOLERANCE
        raise "#{label}: FM-2 ROOT CAUSE DETECTED — explicit persisted divider (separator) reanchored by #{drift.round(2)}pt during wake validation (#{persisted_separator_before} → #{separator_after})."
      end
    end

    if truthy?(snapshot['mainNearControlCenter'])
      raise "#{label}: FM-2 ROOT CAUSE DETECTED — divider snapped to Control Center (mainNearControlCenter flipped true) after wake validation, despite an explicit far-from-Control-Center user layout."
    end

    log("#{label}: explicit divider survived (persistedMain=#{main_after.inspect}, persistedSeparator=#{separator_after.inspect})")
  end

  def configure_settings!(auto_rehide:)
    settings = wake_probe_settings(load_settings_json, auto_rehide: auto_rehide)
    quit_app
    save_settings_json(settings)
    log("Updated settings.json for wake probe: autoRehide=#{auto_rehide}")
  end

  def wake_probe_settings(settings, auto_rehide:)
    settings.merge(
      'hasCompletedOnboarding' => true,
      'hasSeenFreemiumIntro' => true,
      'hasCompletedHealthWizard' => true,
      'autoRehide' => auto_rehide,
      'showOnHover' => false,
      'showOnScroll' => false,
      'showOnClick' => false,
      'showOnUserDrag' => false,
      'rehideOnAppChange' => false,
      'disableOnExternalMonitor' => false,
      'hideApplicationMenusOnInlineReveal' => false,
      'leftClickOpensBrowseIcons' => false,
      'alwaysHiddenPinnedItemIds' => [],
      'hideAllOtherMenuBarItems' => false,
      'hideAllOtherVisibleItemIds' => []
    )
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
    wait_for_configured_launch_baseline(label: 'hide-all-other seeded launch baseline', auto_rehide: true)
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
    last_error = nil

    while Time.now < deadline
      begin
        by_id = icon_zone_lookup(read_icon_zones!)
        missing = @dynamic_helper_ids.reject { |identifier| by_id.key?(identifier) }
        return if missing.empty?
      rescue StandardError => e
        last_error = e.message
        log("Dynamic helper icon-zone inventory unavailable while waiting: #{e.message}")
      end

      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    detail = last_error ? " last_inventory_error=#{last_error.inspect}" : ''
    raise "Dynamic helper IDs did not appear before wake proof: #{missing.join(', ')}#{detail}"
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
    out, status = capture(cliclick_path, "m:#{PARKED_CURSOR_X.to_i},#{PARKED_CURSOR_Y.to_i}")
    raise "Pointer parking failed after #{label}: #{out}" unless status.success?

    parked_cursor = wait_for_parked_cursor!(label: label)
    snapshot = wait_for_snapshot(
      label: "#{label} pointer parked",
      timeout: SNAPSHOT_SETTLE_TIMEOUT_SECONDS,
      interval: 0.25
    ) do |candidate|
      candidate['autoRehideBlockReason'] != 'mouse-in-menu-bar-interaction-region'
    end
    log("#{label} pointer parked outside menu-bar interaction region: autoRehideBlockReason=#{snapshot['autoRehideBlockReason']}")
    parked_cursor
  end

  def wait_for_parked_cursor!(label:)
    deadline = Time.now + PARKED_CURSOR_SETTLE_TIMEOUT_SECONDS
    last_position = nil
    loop do
      last_position = cursor_position
      return last_position if cursor_near_park_target?(last_position)

      break if Time.now >= deadline

      sleep PARKED_CURSOR_SETTLE_POLL_SECONDS
    end

    raise(
      "Pointer parking did not settle after #{label}: expected " \
      "#{PARKED_CURSOR_X.to_i},#{PARKED_CURSOR_Y.to_i}±#{PARKED_CURSOR_TOLERANCE}px, " \
      "actual=#{last_position.inspect}"
    )
  end

  def cursor_near_park_target?(position)
    (position[:x] - PARKED_CURSOR_X).abs <= PARKED_CURSOR_TOLERANCE &&
      (position[:y] - PARKED_CURSOR_Y).abs <= PARKED_CURSOR_TOLERANCE
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
    else
      zones = wait_for_required_visible_baseline!(required, initial_zones: zones)
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

  def wait_for_required_visible_baseline!(required, initial_zones: nil)
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    zones = initial_zones
    last_problem = nil

    while Time.now < deadline
      begin
        zones ||= read_icon_zones!
      rescue StandardError => e
        last_problem = "zone_read_error:#{e.message}"
        log("Required visible baseline inventory unavailable: #{e.message}")
        sleep SNAPSHOT_SETTLE_POLL_SECONDS
        next
      end

      by_id = icon_zone_lookup(zones)
      non_visible = required.select { |identifier| by_id[identifier].nil? || by_id[identifier][:zone] != 'visible' }
      return zones if non_visible.empty?

      seed_required_visible_ids!(non_visible)
      last_problem = non_visible.join(', ')
      zones = nil
      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "Wake visible-zone proof required IDs are not visible at baseline: #{last_problem}"
  end

  def wait_for_hide_all_other_zone_settle!(visible_ids)
    required = Array(visible_ids).map(&:to_s).reject(&:empty?)
    allowed = required.to_set
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    last_problem = nil

    while Time.now < deadline
      begin
        zones = read_icon_zones!
      rescue StandardError => e
        last_problem = { zone_read_error: e.message }
        log("Hide-all-other zone settle inventory unavailable: #{e.message}")
        sleep SNAPSHOT_SETTLE_POLL_SECONDS
        next
      end
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

      seed_required_visible_ids!(missing_visible) unless missing_visible.empty?

      last_problem = {
        missing_visible: missing_visible,
        exposed_unallowed: exposed_unallowed.map { |item| "#{item[:unique_id]}:#{item[:zone]}" }
      }
      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "Hide-all-other seeded baseline did not settle before wake proof: #{last_problem.inspect}"
  end

  def seed_required_visible_ids!(identifiers)
    Array(identifiers).map(&:to_s).reject(&:empty?).uniq.each do |identifier|
      result = app_script(%(move icon to visible "#{escape_quotes(identifier)}")).strip.downcase
      unless %w[true 1].include?(result)
        log("Required visible seed returned #{result.inspect} for #{identifier}")
      end
    rescue StandardError => e
      log("Required visible seed failed for #{identifier}: #{e.message}")
    end
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
        .reject { |item| hidden_baseline_skip_item?(item) }
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

  def hidden_baseline_skip_item?(item)
    bundle_id = item[:bundle_id].to_s
    unique_id = item[:unique_id].to_s
    bundle_id.start_with?('com.sanebar') ||
      unique_id.start_with?('com.sanebar') ||
      bundle_id.start_with?('com.apple.') ||
      unique_id.start_with?('com.apple.menuextra.')
  end

  def wait_for_icon_zone_persistence!(required, expected_zone:, delay:, failure_prefix:)
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    last_moved = []

    while Time.now < deadline
      begin
        zones = read_icon_zones!
      rescue StandardError => e
        last_moved = ["zone_read_error:#{e.message}"]
        log("#{failure_prefix} inventory unavailable while waiting: #{e.message}")
        sleep SNAPSHOT_SETTLE_POLL_SECONDS
        next
      end
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
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    raw = +''
    zones = []

    loop do
      raw = app_script('list authoritative icon zones')
      zones = parse_icon_zone_rows(raw)
      return zones unless zones.empty?

      break if Time.now >= deadline

      log('list authoritative icon zones returned no parseable rows; retrying within settle window')
      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "list authoritative icon zones returned no parseable rows: #{raw.inspect}"
  end

  def parse_icon_zone_rows(raw)
    raw.each_line.map do |line|
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
      '--predicate', predicate,
      timeout: 30
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

  def wait_for_configured_launch_baseline(label:, auto_rehide:)
    snapshot = wait_for_healthy_snapshot(label: label)
    return snapshot if snapshot['autoRehideEnabled'] == auto_rehide

    raise "#{label}: autoRehideEnabled did not match configured value (expected=#{auto_rehide}, actual=#{snapshot['autoRehideEnabled'].inspect})"
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
    !app_pids.empty?
  end

  def quit_app
    return unless @app_name
    unless app_running?
      reap_direct_launch_children!
      return
    end

    begin
      write_automation_quit_marker!
      out, status = capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to quit")
      deadline = Time.now + graceful_quit_timeout_seconds(status)
      while app_running? && Time.now < deadline
        sleep 0.2
      end
      if app_running?
        log("Graceful quit did not exit #{@app_name}; status=#{status.exitstatus.inspect} output=#{truncated_log_output(out.to_s.strip)}")
      end
      terminate_lingering_app_processes_until_gone!(
        timeout: force_quit_timeout_seconds,
        signal: 'TERM'
      )
      terminate_lingering_app_processes_until_gone!(
        timeout: force_quit_timeout_seconds,
        signal: 'KILL'
      ) if app_running?
      raise "Timed out waiting for #{@app_name} to quit" if app_running?
    ensure
      remove_matching_automation_quit_marker!
      reap_direct_launch_children!
    end
  end

  def graceful_quit_timeout_seconds(status)
    override = ENV['SANEBAR_WAKE_PROBE_QUIT_TIMEOUT_SECONDS']
    return override.to_f if override && !override.empty?

    return DEFAULT_GRACEFUL_QUIT_TIMEOUT_SECONDS if status&.success?

    0.5
  end

  def force_quit_timeout_seconds
    ENV.fetch('SANEBAR_WAKE_PROBE_FORCE_QUIT_TIMEOUT_SECONDS', DEFAULT_FORCE_QUIT_TIMEOUT_SECONDS.to_s).to_f
  end

  def terminate_lingering_app_processes_until_gone!(timeout:, signal:)
    deadline = Time.now + timeout
    while app_running? && Time.now < deadline
      app_pids.each do |pid|
        log("Force terminating lingering #{@app_name} test process pid=#{pid} signal=#{signal}")
        Process.kill(signal, pid)
      rescue Errno::ESRCH
        nil
      end
      sleep 0.25
    end
  end

  def app_pids
    app_processes.map { |process| process[:pid] }
  end

  def app_processes
    return [] unless @app_name
    process_path = File.join(@app_path, 'Contents', 'MacOS', @app_name)
    out, status = Open3.capture2e('ps', '-axo', 'pid=,command=')
    return [] unless status.success?

    out.lines.each_with_object([]) do |line, result|
      stripped = line.strip
      pid, command = stripped.split(/\s+/, 2)
      next unless pid && command
      next unless command.split(/\s+/, 2).first.to_s == process_path

      numeric_pid = pid.to_i
      result << { pid: numeric_pid, command: command } if numeric_pid.positive?
    end
  end

  def ensure_single_target_process!(context)
    processes = app_processes
    raise "#{context}: #{@app_name} test target is not running" if processes.empty?

    if processes.length > 1
      raise "#{context}: duplicate #{@app_name} test processes: #{format_app_processes(processes)}"
    end

    process = processes.first
    if no_keychain_launch? && !process[:command].include?('--sane-no-keychain')
      raise "#{context}: expected no-keychain #{@app_name} process, got #{format_app_processes(processes)}"
    end

    true
  end

  def format_app_processes(processes)
    processes.map { |process| "#{process[:pid]} #{process[:command]}" }.join(' | ')
  end

  def launch_app
    if no_keychain_launch?
      launch_app_direct
      sleep NO_KEYCHAIN_LAUNCH_REGISTRATION_GRACE_SECONDS
    else
      out, status = capture('open', @app_path)
      raise "Failed to launch #{@app_path}: #{out}" unless status.success?
    end

    deadline = Time.now + 20
    until Time.now >= deadline
      break if target_process_ready? && layout_snapshot_available?
      sleep 0.25
    end

    raise "Timed out waiting for #{@app_name} launch" unless target_process_ready? && layout_snapshot_available?
  end

  def target_process_ready?
    ensure_single_target_process!('launch wait')
  rescue StandardError
    false
  end

  def no_keychain_launch?
    ENV['SANEAPPS_DISABLE_KEYCHAIN'] == '1' || ENV['SANEBAR_PROBE_FORCE_NO_KEYCHAIN'] == '1'
  end

  def launch_app_direct
    binary = File.join(@app_path, 'Contents', 'MacOS', @app_name)
    raise "Executable missing for #{@app_path}" unless File.executable?(binary)

    remove_matching_automation_quit_marker!
    @automation_quit_token = SecureRandom.hex(24)
    log("Launching #{@app_name} directly with --sane-no-keychain")
    pid = Process.spawn(
      { 'SANEAPPS_DISABLE_KEYCHAIN' => '1', AUTOMATION_QUIT_TOKEN_ENV => @automation_quit_token },
      binary,
      '--sane-no-keychain',
      out: File::NULL,
      err: File::NULL
    )
    @direct_launch_pids << pid
    pid
  rescue StandardError => e
    raise "Failed to launch #{@app_path} directly: #{e.message}"
  end

  def automation_quit_marker_path
    ENV['SANEBAR_AUTOMATION_QUIT_MARKER_PATH'] || DEFAULT_AUTOMATION_QUIT_MARKER_PATH
  end

  def write_automation_quit_marker!
    return if @automation_quit_token.to_s.empty?

    path = automation_quit_marker_path
    temp_path = "#{path}.#{Process.pid}.tmp"
    File.open(temp_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
      file.write("#{@automation_quit_token}\n")
    end
    File.chmod(0o600, temp_path)
    File.rename(temp_path, path)
  ensure
    FileUtils.rm_f(temp_path) if temp_path && File.exist?(temp_path)
  end

  def remove_matching_automation_quit_marker!
    return if @automation_quit_token.to_s.empty?

    path = automation_quit_marker_path
    return unless File.file?(path)
    return unless File.read(path).strip == @automation_quit_token

    FileUtils.rm_f(path)
  rescue Errno::ENOENT
    nil
  end

  def reap_direct_launch_children!
    @direct_launch_pids.delete_if do |pid|
      begin
        !Process.waitpid(pid, Process::WNOHANG).nil?
      rescue Errno::ECHILD
        true
      end
    end
  end

  def layout_snapshot_available?
    read_layout_snapshot!
    true
  rescue StandardError
    false
  end

  def read_layout_snapshot!
    ensure_single_target_process!('layout snapshot')
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
    return {} unless safe_existing_file?(SETTINGS_PATH)

    JSON.parse(safe_read_file(SETTINGS_PATH))
  rescue JSON::ParserError => e
    raise "Could not parse #{SETTINGS_PATH}: #{e.message}"
  end

  def save_settings_json(payload)
    FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
    safe_write_file(SETTINGS_PATH, JSON.pretty_generate(payload) + "\n")
  end

  def safe_write_file(path, content)
    safe_directory_path!(File.dirname(path))
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, safe_file_write_flags, 0o600) do |file|
      file.write(content)
    end
  end

  def safe_copy_file(source, destination)
    safe_write_file(destination, safe_read_file(source))
  end

  def safe_read_file(path)
    safe_directory_path!(File.dirname(path))
    File.open(path, safe_file_read_flags) do |file|
      file.read
    end
  end

  def safe_remove_file(path)
    return unless safe_existing_file?(path)

    FileUtils.rm_f(path)
  end

  def safe_existing_file?(path)
    safe_directory_path!(File.dirname(path))
    stat = File.lstat(path)
    raise "Unsafe symlink settings path: #{path}" if stat.symlink?
    raise "Unsafe non-file settings path: #{path}" unless stat.file?

    true
  rescue Errno::ENOENT
    false
  end

  def safe_file_write_flags
    flags = File::WRONLY | File::CREAT | File::TRUNC
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def safe_file_read_flags
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def safe_directory_path!(path)
    expanded = File.expand_path(path)
    current = expanded.start_with?(File::SEPARATOR) ? File::SEPARATOR : Dir.pwd
    expanded.split(File::SEPARATOR).reject(&:empty?).each do |component|
      current = current == File::SEPARATOR ? File.join(current, component) : File.join(current, component)
      next unless File.exist?(current)

      stat = File.lstat(current)
      if stat.symlink?
        real = File.realpath(current) rescue nil
        next if allowed_system_temp_directory_symlink?(current, real)

        raise "Unsafe symlink directory path: #{current}"
      end
      raise "Unsafe non-directory path: #{current}" unless stat.directory?
    end
    true
  end

  def allowed_system_temp_directory_symlink?(path, real)
    expanded = File.expand_path(path)
    canonical = File.expand_path(real.to_s)
    return true if expanded == '/tmp' && canonical == '/private/tmp'
    return true if expanded == '/var' && canonical == '/private/var'

    expanded == File.expand_path(Dir.tmpdir) && canonical == File.realpath(Dir.tmpdir)
  rescue StandardError
    false
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

end
require_relative 'lib/wake_layout_probe_artifacts'

if __FILE__ == $PROGRAM_NAME
  runtime_lock = WakeLayoutProbe.acquire_runtime_target_lock
  status = 75

  unless runtime_lock == false
    begin
      status = WakeLayoutProbe.new.run ? 0 : 1
    ensure
      WakeLayoutProbe.release_runtime_target_lock(runtime_lock)
    end
  end

  $stdout.flush
  $stderr.flush
  exit!(status)
end
