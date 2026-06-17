#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'time'
require 'digest'

class StartupLayoutProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  SNAPSHOT_DELAYS = [2.0, 5.0].freeze
  SNAPSHOT_SETTLE_TIMEOUT_SECONDS = 18.0
  SNAPSHOT_SETTLE_POLL_SECONDS = 0.5
  DEFAULT_MAIN_RIGHT_GAP_TOLERANCE = 80.0

  def initialize
    @app_path = ENV.fetch('SANEBAR_SMOKE_APP_PATH', '').strip
    @log_path = ENV.fetch('SANEBAR_STARTUP_PROBE_LOG_PATH', '/tmp/sanebar_startup_layout_probe.log')
    @artifact_path = ENV.fetch('SANEBAR_STARTUP_PROBE_ARTIFACT_PATH', '/tmp/sanebar_startup_layout_probe.json')
    @main_right_gap_tolerance = ENV.fetch(
      'SANEBAR_STARTUP_PROBE_MAIN_RIGHT_GAP_TOLERANCE',
      DEFAULT_MAIN_RIGHT_GAP_TOLERANCE.to_s
    ).to_f
    @workspace = Dir.mktmpdir('sanebar-startup-probe')
    @defaults_backup_path = File.join(@workspace, 'defaults.plist')
    @settings_backup_path = File.join(@workspace, 'settings.json')
    @lines = []
    @cases = []
    @bundle_id = nil
    @app_name = nil
    @had_defaults_domain = false
    @had_settings_file = false
    @was_running = false
    @state_restored = false
  end

  def run
    validate_target!
    @bundle_id = bundle_identifier
    @app_name = File.basename(@app_path, '.app')
    @was_running = app_running?
    backup_state!

    poisoned_backup_case = run_poisoned_backup_restore_case
    current_host_visibility_case = run_current_host_visibility_override_case
    auto_rehide_case = run_auto_rehide_false_case
    dirty_reboot_case = run_dirty_reboot_recovery_case
    always_hidden_replay_case = run_always_hidden_dirty_replay_outbound_case

    @cases << poisoned_backup_case
    @cases << current_host_visibility_case
    @cases << auto_rehide_case
    @cases << dirty_reboot_case
    @cases << always_hidden_replay_case

    restore_state!
    @state_restored = true

    write_artifact!(
      status: 'pass',
      bundle_id: @bundle_id,
      app_path: @app_path,
      completed_scenarios: completed_scenarios_from_cases(@cases),
      cases: @cases
    )
    puts "✅ Startup layout probe passed (#{@cases.map { |entry| entry[:name] }.join(', ')})"
    true
  rescue StandardError => e
    write_artifact!(
      status: 'fail',
      bundle_id: @bundle_id,
      app_path: @app_path,
      error: e.message,
      backtrace: Array(e.backtrace).first(12),
      completed_scenarios: completed_scenarios_from_cases(@cases),
      cases: @cases
    )
    log("❌ Startup layout probe failed: #{e.message}")
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
    _out, status = capture('defaults', 'export', bundle_identifier, @defaults_backup_path)
    @had_defaults_domain = status.success? && File.exist?(@defaults_backup_path)
    if File.exist?(SETTINGS_PATH)
      FileUtils.mkdir_p(File.dirname(@settings_backup_path))
      FileUtils.cp(SETTINGS_PATH, @settings_backup_path)
      @had_settings_file = true
    end
    log("Backed up defaults domain=#{@had_defaults_domain} settings=#{@had_settings_file}")
  end

  def restore_state!
    quit_app

    if @had_defaults_domain && File.exist?(@defaults_backup_path)
      _out, status = capture('defaults', 'import', bundle_identifier, @defaults_backup_path)
      raise "Failed to restore defaults domain #{bundle_identifier}" unless status.success?
    else
      capture('defaults', 'delete', bundle_identifier)
    end

    if @had_settings_file
      raise "Missing settings backup #{@settings_backup_path}" unless File.exist?(@settings_backup_path)

      FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
      FileUtils.cp(@settings_backup_path, SETTINGS_PATH)
    else
      FileUtils.rm_f(SETTINGS_PATH)
    end

    launch_app if @was_running
    log('Restored startup probe state')
  end

  def run_poisoned_backup_restore_case
    width = numeric_default('SaneBar_CalibratedScreenWidth') || parsed_snapshot_value(read_layout_snapshot!, 'screenWidth')
    raise 'Missing calibrated screen width for startup probe' unless width

    width_bucket = width.to_i
    version = autosave_version
    main_key = "NSStatusItem Preferred Position SaneBar_Main_v#{version}"
    separator_key = "NSStatusItem Preferred Position SaneBar_Separator_v#{version}"
    backup_main_key = "SaneBar_Position_Backup_#{width_bucket}_main"
    backup_separator_key = "SaneBar_Position_Backup_#{width_bucket}_separator"
    backup_main, backup_separator = wait_for_current_width_backup(
      width_bucket: width_bucket,
      main_key: backup_main_key,
      separator_key: backup_separator_key
    )
    raise "Missing current-width backup for width #{width_bucket}" unless backup_main && backup_separator

    quit_app
    write_numeric_default(main_key, 0)
    write_numeric_default(separator_key, 1)
    write_numeric_default('SaneBar_CalibratedScreenWidth', width_bucket)

    log("Seeded poisoned startup prefs with backup width=#{width_bucket} main=#{backup_main} separator=#{backup_separator}")
    launch_app
    parked_startup_cursor = park_pointer_away_from_menu_bar!(label: 'poisoned startup')

    t2 = snapshot_after_delay(2.0, label: 'poisoned-startup T+2s')
    t5 = snapshot_after_delay(5.0, label: 'poisoned-startup T+5s')
    restored_main = numeric_default(main_key)
    restored_separator = numeric_default(separator_key)
    assert_restored_backup_pair!(
      main: restored_main,
      separator: restored_separator,
      backup_main: backup_main,
      backup_separator: backup_separator,
      width: width,
      label: 'restored preferred positions'
    )
    assert_snapshot_healthy!(t2, label: 'poisoned-startup T+2s')
    assert_snapshot_healthy!(t5, label: 'poisoned-startup T+5s')
    assert_main_right_gap_stable!(t2, t5, label: 'poisoned-startup T+2s→T+5s')
    startup_cursor_proof = assert_cursor_stable!(parked_startup_cursor, label: 'poisoned startup passive recovery')

    quit_app
    launch_app
    parked_replay_cursor = park_pointer_away_from_menu_bar!(label: 'restart replay')

    replay = snapshot_after_delay(2.0, label: 'restart replay T+2s')
    replay_main = numeric_default(main_key)
    replay_separator = numeric_default(separator_key)
    assert_restored_backup_pair!(
      main: replay_main,
      separator: replay_separator,
      backup_main: backup_main,
      backup_separator: backup_separator,
      width: width,
      label: 'restart replay preferred positions'
    )
    assert_snapshot_healthy!(replay, label: 'restart replay T+2s')
    assert_main_right_gap_stable!(t5, replay, label: 'poisoned-startup T+5s→restart replay T+2s')
    replay_cursor_proof = assert_cursor_stable!(parked_replay_cursor, label: 'restart replay passive recovery')

    {
      name: 'current-width backup beats ordinal seeds',
      width_bucket: width_bucket,
      backup_main: backup_main,
      backup_separator: backup_separator,
      restored_main: restored_main,
      restored_separator: restored_separator,
      cursor_proofs: [startup_cursor_proof, replay_cursor_proof],
      snapshots: {
        t2: t2,
        t5: t5,
        replay_t2: replay
      }
    }
  end

  def run_current_host_visibility_override_case
    version = autosave_version
    keys = current_host_visibility_keys(version)
    original_values = keys.to_h { |key| [key, read_current_host_default(key)] }

    quit_app
    keys.each { |key| write_current_host_bool(key, false) }
    log("Seeded currentHost visibility overrides for autosave version #{version}")
    launch_app
    parked_cursor = park_pointer_away_from_menu_bar!(label: 'currentHost visibility override startup')

    snapshot = snapshot_after_delay(2.0, label: 'currentHost visibility override T+2s')
    assert_snapshot_healthy!(snapshot, label: 'currentHost visibility override T+2s')
    keys.each { |key| assert_current_host_default_cleared!(key) }
    cursor_proof = assert_cursor_stable!(parked_cursor, label: 'currentHost visibility override passive startup cleanup')

    {
      name: 'currentHost visibility overrides are cleared on startup',
      seeded_keys: keys,
      cursor_proof: cursor_proof,
      snapshot: snapshot
    }
  ensure
    restore_current_host_defaults(original_values) if original_values
  end

  def run_auto_rehide_false_case
    settings = load_settings_json
    settings['autoRehide'] = false

    quit_app
    save_settings_json(settings)
    log('Updated settings.json for startup probe: autoRehide=false')
    launch_app
    parked_cursor = park_pointer_away_from_menu_bar!(label: 'autoRehide=false startup')

    t2 = snapshot_after_delay(2.0, label: 'autoRehide=false T+2s')
    t5 = snapshot_after_delay(5.0, label: 'autoRehide=false T+5s')
    unless t2['autoRehideEnabled'] == false && t5['autoRehideEnabled'] == false
      raise "autoRehide=false probe did not stick (T+2=#{t2['autoRehideEnabled'].inspect}, T+5=#{t5['autoRehideEnabled'].inspect})"
    end
    unless t2['hidingState'] == 'expanded' && t5['hidingState'] == 'expanded'
      raise "autoRehide=false probe rehid the bar (T+2=#{t2['hidingState'].inspect}, T+5=#{t5['hidingState'].inspect})"
    end
    assert_snapshot_healthy!(t2, label: 'autoRehide=false T+2s')
    assert_snapshot_healthy!(t5, label: 'autoRehide=false T+5s')
    assert_main_right_gap_stable!(t2, t5, label: 'autoRehide=false T+2s→T+5s')
    cursor_proof = assert_cursor_stable!(parked_cursor, label: 'autoRehide=false passive startup')

    {
      name: 'autoRehide=false prevents launch hide',
      cursor_proof: cursor_proof,
      snapshots: {
        t2: t2,
        t5: t5
      }
    }
  end

  def run_dirty_reboot_recovery_case
    width = numeric_default('SaneBar_CalibratedScreenWidth') || parsed_snapshot_value(read_layout_snapshot!, 'screenWidth')
    raise 'Missing calibrated screen width for dirty reboot probe' unless width

    width_bucket = width.to_i
    version = autosave_version
    main_key = "NSStatusItem Preferred Position SaneBar_Main_v#{version}"
    separator_key = "NSStatusItem Preferred Position SaneBar_Separator_v#{version}"
    backup_main_key = "SaneBar_Position_Backup_#{width_bucket}_main"
    backup_separator_key = "SaneBar_Position_Backup_#{width_bucket}_separator"
    backup_main, backup_separator = wait_for_current_width_backup(
      width_bucket: width_bucket,
      main_key: backup_main_key,
      separator_key: backup_separator_key
    )
    raise "Missing current-width backup for dirty reboot probe width #{width_bucket}" unless backup_main && backup_separator

    visibility_keys = current_host_visibility_keys(version)
    original_visibility_values = visibility_keys.to_h { |key| [key, read_current_host_default(key)] }

    quit_app
    save_settings_json(dirty_reboot_settings(load_settings_json))
    visibility_keys.each { |key| write_current_host_bool(key, false) }
    write_numeric_default(main_key, 0)
    write_numeric_default(separator_key, 1)
    write_numeric_default('SaneBar_CalibratedScreenWidth', width_bucket)

    log(
      "Seeded #157 dirty reboot prefs width=#{width_bucket} " \
      "backup_main=#{backup_main} backup_separator=#{backup_separator}"
    )
    launch_app
    parked_startup_cursor = park_pointer_away_from_menu_bar!(label: '#157 dirty reboot startup')

    first_t2 = snapshot_after_delay(2.0, label: '#157 dirty reboot T+2s')
    first_t5 = snapshot_after_delay(5.0, label: '#157 dirty reboot T+5s')
    assert_snapshot_healthy!(first_t2, label: '#157 dirty reboot T+2s')
    assert_snapshot_healthy!(first_t5, label: '#157 dirty reboot T+5s')
    assert_hidden_after_auto_rehide!(first_t5, label: '#157 dirty reboot T+5s')
    assert_main_right_gap_stable!(first_t2, first_t5, label: '#157 dirty reboot T+2s→T+5s')
    first_cursor_proof = assert_cursor_stable!(parked_startup_cursor, label: '#157 dirty reboot passive recovery')
    visibility_keys.each { |key| assert_current_host_default_cleared!(key) }

    restored_main = numeric_default(main_key)
    restored_separator = numeric_default(separator_key)
    assert_restored_backup_pair!(
      main: restored_main,
      separator: restored_separator,
      backup_main: backup_main,
      backup_separator: backup_separator,
      width: width,
      label: '#157 dirty reboot restored preferred positions'
    )

    quit_app
    launch_app
    parked_replay_cursor = park_pointer_away_from_menu_bar!(label: '#157 dirty reboot relaunch')

    replay_t2 = snapshot_after_delay(2.0, label: '#157 dirty reboot relaunch T+2s')
    replay_t5 = snapshot_after_delay(5.0, label: '#157 dirty reboot relaunch T+5s')
    assert_snapshot_healthy!(replay_t2, label: '#157 dirty reboot relaunch T+2s')
    assert_snapshot_healthy!(replay_t5, label: '#157 dirty reboot relaunch T+5s')
    assert_hidden_after_auto_rehide!(replay_t5, label: '#157 dirty reboot relaunch T+5s')
    assert_main_right_gap_stable!(first_t5, replay_t5, label: '#157 dirty reboot T+5s→relaunch T+5s')
    replay_cursor_proof = assert_cursor_stable!(parked_replay_cursor, label: '#157 dirty reboot relaunch passive recovery')

    {
      name: '#157 dirty reboot recovery keeps live anchors before hiding',
      completed_scenarios: [
        '#157 dirty startup recovers poisoned autosave defaults',
        '#157 dirty startup clears currentHost visibility overrides',
        '#157 dirty startup waits for valid status-item windows before auto-hide',
        '#157 dirty startup remains passive and does not move the cursor'
      ],
      width_bucket: width_bucket,
      backup_main: backup_main,
      backup_separator: backup_separator,
      restored_main: restored_main,
      restored_separator: restored_separator,
      cursor_proofs: [first_cursor_proof, replay_cursor_proof],
      snapshots: {
        first_t2: first_t2,
        first_t5: first_t5,
        replay_t2: replay_t2,
        replay_t5: replay_t5
      }
    }
  ensure
    restore_current_host_defaults(original_visibility_values) if original_visibility_values
  end

  def run_always_hidden_dirty_replay_outbound_case
    width = numeric_default('SaneBar_CalibratedScreenWidth') || parsed_snapshot_value(read_layout_snapshot!, 'screenWidth')
    raise 'Missing calibrated screen width for #155 dirty replay probe' unless width

    width_bucket = width.to_i
    version = autosave_version
    main_key = "NSStatusItem Preferred Position SaneBar_Main_v#{version}"
    separator_key = "NSStatusItem Preferred Position SaneBar_Separator_v#{version}"
    always_hidden_key = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator_v#{version}"
    visibility_keys = current_host_visibility_keys(version)
    original_visibility_values = visibility_keys.to_h { |key| [key, read_current_host_default(key)] }

    quit_app
    settings = dirty_reboot_settings(load_settings_json).merge(
      'alwaysHiddenSectionEnabled' => true,
      'requireAuthToShowHiddenIcons' => false
    )
    save_settings_json(settings)
    launch_app
    snapshot_after_delay(2.0, label: '#155 AH replay fixture launch T+2s')

    candidates = preferred_always_hidden_replay_candidates
    raise "#155 dirty replay probe needs two deterministic exact-ID candidates, found #{candidates.length}" if candidates.length < 2

    hidden_exit_candidate, visible_exit_candidate = candidates.first(2)
    move_icon_and_expect!(
      hidden_exit_candidate[:unique_id],
      command: 'move icon to always hidden',
      expected_zone: 'alwaysHidden',
      label: '#155 seed hidden-exit candidate'
    )
    move_icon_and_expect!(
      visible_exit_candidate[:unique_id],
      command: 'move icon to always hidden',
      expected_zone: 'alwaysHidden',
      label: '#155 seed visible-exit candidate'
    )

    pinned_settings = load_settings_json.merge(
      'alwaysHiddenSectionEnabled' => true,
      'requireAuthToShowHiddenIcons' => false
    )
    pinned_ids = Array(pinned_settings['alwaysHiddenPinnedItemIds'])
    pinned_settings['alwaysHiddenPinnedItemIds'] = (pinned_ids + candidates.first(2).map { |item| item[:unique_id] }).uniq
    save_settings_json(pinned_settings)

    quit_app
    visibility_keys.each { |key| write_current_host_bool(key, false) }
    write_numeric_default(main_key, 0)
    write_numeric_default(separator_key, 1)
    write_numeric_default(always_hidden_key, 10_000)

    log("Seeded #155 dirty AH replay width=#{width_bucket} fixture_candidates=2")
    launch_app
    parked_cursor = park_pointer_away_from_menu_bar!(label: '#155 dirty AH replay startup')
    replay_t2 = snapshot_after_delay(2.0, label: '#155 dirty AH replay T+2s')
    replay_t5 = snapshot_after_delay(5.0, label: '#155 dirty AH replay T+5s')
    assert_snapshot_healthy!(replay_t2, label: '#155 dirty AH replay T+2s')
    assert_snapshot_healthy!(replay_t5, label: '#155 dirty AH replay T+5s')
    hidden_replay_zone = wait_for_icon_zone!(
      hidden_exit_candidate[:unique_id],
      'alwaysHidden',
      label: '#155 hidden-exit starts in AH after dirty startup'
    )
    visible_replay_zone = wait_for_icon_zone!(
      visible_exit_candidate[:unique_id],
      'alwaysHidden',
      label: '#155 visible-exit starts in AH after dirty startup'
    )
    cursor_proof = assert_cursor_stable!(parked_cursor, label: '#155 dirty AH replay passive startup')

    hidden_move = move_icon_and_expect!(
      hidden_exit_candidate[:unique_id],
      command: 'move icon to hidden',
      expected_zone: 'hidden',
      label: '#155 AH-to-Hidden after dirty startup'
    )
    visible_move = move_icon_and_expect!(
      visible_exit_candidate[:unique_id],
      command: 'move icon to visible',
      expected_zone: 'visible',
      label: '#155 AH-to-Visible after dirty startup'
    )
    idle_snapshot = assert_move_idle!('#155 dirty AH replay outbound moves')

    {
      name: '#155 dirty startup AH replay allows outbound moves',
      completed_scenarios: [
        '#155 dirty startup does not give up AH replay',
        '#155 dirty startup restores pinned icons into Always Hidden before outbound moves',
        '#155 pinned icon exits Always Hidden after dirty startup',
        '#155 Always Hidden outbound moves leave move state idle'
      ],
      width_bucket: width_bucket,
      candidates: [
        sanitized_replay_candidate(hidden_exit_candidate, role: 'hidden_exit', observed_zone: hidden_replay_zone),
        sanitized_replay_candidate(visible_exit_candidate, role: 'visible_exit', observed_zone: visible_replay_zone)
      ],
      moves: [hidden_move, visible_move].map { |move| sanitized_move_result(move) },
      cursor_proof: cursor_proof,
      snapshots: {
        replay_t2: replay_t2,
        replay_t5: replay_t5,
        idle: idle_snapshot
      }
    }
  ensure
    restore_current_host_defaults(original_visibility_values) if original_visibility_values
  end

  def dirty_reboot_settings(settings)
    settings.merge(
      'hasCompletedOnboarding' => true,
      'hasSeenFreemiumIntro' => true,
      'hasCompletedHealthWizard' => true,
      'autoRehide' => true,
      'rehideDelay' => 0.5,
      'showOnHover' => false,
      'showOnScroll' => false,
      'showOnClick' => false,
      'showOnUserDrag' => false,
      'disableOnExternalMonitor' => false,
      'hideApplicationMenusOnInlineReveal' => false,
      'leftClickOpensBrowseIcons' => false
    )
  end

  def preferred_always_hidden_replay_candidates
    preferred_bundles = [
      'com.sanebar.hostsentinel',
      'com.sanebar.sharedfixture'
    ]
    list_icon_zones
      .select { |item| item[:movable] && item[:unique_id].to_s.include?('::statusItem:') }
      .select { |item| preferred_bundles.include?(item[:bundle].to_s) }
      .reject { |item| item[:bundle].to_s == bundle_identifier }
      .sort_by do |item|
        bundle_rank = preferred_bundles.index(item[:bundle].to_s) || 100
        zone_rank = item[:zone].to_s == 'alwaysHidden' ? 2 : 0
        [bundle_rank, zone_rank, item[:unique_id].to_s]
      end
  end

  def sanitized_replay_candidate(item, role:, observed_zone:)
    {
      role: role,
      fixture: sane_fixture_label(item[:bundle]),
      initial_zone: item[:zone],
      observed_zone: observed_zone,
      unique_id_hash: Digest::SHA256.hexdigest(item[:unique_id].to_s)[0, 12]
    }
  end

  def sanitized_move_result(move)
    move
      .reject { |key, _| key == :unique_id }
      .merge(unique_id_hash: Digest::SHA256.hexdigest(move[:unique_id].to_s)[0, 12])
  end

  def sane_fixture_label(bundle)
    case bundle.to_s
    when 'com.sanebar.hostsentinel'
      'hostsentinel'
    when 'com.sanebar.sharedfixture'
      'sharedfixture'
    else
      'unknown'
    end
  end

  def list_icon_zones
    out, status = applescript_command('list icon zones')
    raise "list icon zones failed: #{out}" unless status.success?

    out.lines.map do |line|
      zone, movable, bundle, unique_id, name = line.strip.split("\t", 5)
      next nil if unique_id.nil? || unique_id.empty?

      {
        zone: zone,
        movable: movable == 'true',
        bundle: bundle,
        unique_id: unique_id,
        name: name
      }
    end.compact
  end

  def move_icon_and_expect!(unique_id, command:, expected_zone:, label:)
    wait_for_move_idle!(label)
    escaped_id = escape_applescript(unique_id)
    out, status = applescript_command(%(#{command} "#{escaped_id}"))
    raise "#{label}: #{command} failed for #{unique_id}: #{out}" unless status.success?

    zone = wait_for_icon_zone!(unique_id, expected_zone, label: label)
    idle_snapshot = assert_move_idle!(label)
    {
      label: label,
      command: command,
      unique_id: unique_id,
      expected_zone: expected_zone,
      observed_zone: zone,
      idle_snapshot: idle_snapshot
    }
  end

  def wait_for_icon_zone!(unique_id, expected_zone, label:)
    deadline = Time.now + 8.0
    last_zone = nil

    loop do
      match = list_icon_zones.find { |item| item[:unique_id] == unique_id }
      last_zone = match && match[:zone]
      return last_zone if last_zone == expected_zone

      break if Time.now >= deadline

      sleep 0.35
    end

    raise "#{label}: #{unique_id} did not reach #{expected_zone} (last=#{last_zone.inspect})"
  end

  def wait_for_move_idle!(label, timeout: 6.0)
    deadline = Time.now + timeout
    last_snapshot = nil

    loop do
      last_snapshot = read_layout_snapshot!
      return last_snapshot unless truthy?(last_snapshot['isMoveInProgress'])

      break if Time.now >= deadline

      sleep 0.25
    end

    raise "#{label}: move state did not become idle before command dispatch (last snapshot: #{last_snapshot.inspect})"
  end

  def assert_move_idle!(label)
    snapshot = wait_for_move_idle!(label)
    raise "#{label}: move state remained active after command return" if truthy?(snapshot['isMoveInProgress'])

    snapshot
  end

  def wait_for_current_width_backup(width_bucket:, main_key:, separator_key:, timeout: 8.0)
    deadline = Time.now + timeout
    last_snapshot = nil

    loop do
      main = numeric_default(main_key)
      separator = numeric_default(separator_key)
      return [main, separator] if main && separator

      break if Time.now >= deadline

      begin
        last_snapshot = read_layout_snapshot!
      rescue StandardError
        last_snapshot = nil
      end
      sleep 0.25
    end

    log("Timed out waiting for current-width backup width=#{width_bucket} snapshot=#{last_snapshot}")
    [nil, nil]
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

  def autosave_version
    (numeric_default('SaneBar_AutosaveVersion') || 7).to_i
  end

  def app_running?
    !app_pids.empty?
  end

  def quit_app
    return unless @app_name
    return unless app_running?

    capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to quit")
    deadline = Time.now + ENV.fetch('SANEBAR_STARTUP_PROBE_QUIT_TIMEOUT_SECONDS', '20').to_f
    while app_running? && Time.now < deadline
      sleep 0.2
    end
    if app_running?
      capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to quit")
      deadline = Time.now + 5
      while app_running? && Time.now < deadline
        sleep 0.2
      end
    end
    app_pids.each do |pid|
      log("Force terminating lingering #{@app_name} test process pid=#{pid}")
      Process.kill('TERM', pid)
    rescue Errno::ESRCH
      nil
    end
    deadline = Time.now + 3
    while app_running? && Time.now < deadline
      sleep 0.2
    end
    raise "Timed out waiting for #{@app_name} to quit" if app_running?
  end

  def app_pids
    return [] unless @app_name

    process_path = File.join(@app_path, 'Contents', 'MacOS', @app_name)
    out, status = Open3.capture2e('ps', '-axo', 'pid=,command=')
    return [] unless status.success?

    out.lines.map do |line|
      next unless line.include?(process_path)

      line.split.first.to_i
    end.compact.select(&:positive?)
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
        out: '/tmp/sanebar_startup_probe_launch.log',
        err: '/tmp/sanebar_startup_probe_launch.log'
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

  def snapshot_after_delay(delay_seconds, label:)
    sleep delay_seconds
    wait_for_healthy_snapshot(label: label)
  end

  def cliclick_path
    cliclick = ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick']
      .find { |path| File.executable?(path) }
    raise 'Startup probe requires cliclick on the Mini to prove passive recovery does not move the cursor' unless cliclick
    cliclick
  end

  def cursor_position
    out, status = capture(cliclick_path, 'p')
    raise "Could not read pointer position: #{out}" unless status.success?

    match = out.strip.match(/\A(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)\z/)
    raise "Could not parse pointer position: #{out.inspect}" unless match

    { x: match[1].to_f, y: match[2].to_f }
  end

  def park_pointer_away_from_menu_bar!(label:)
    out, status = capture(cliclick_path, 'm:400,400')
    raise "Pointer parking failed for #{label}: #{out}" unless status.success?

    snapshot = wait_for_healthy_snapshot(label: "#{label} pointer parked")
    log("#{label} pointer parked before passive startup proof: autoRehideBlockReason=#{snapshot['autoRehideBlockReason']}")
    cursor_position
  end

  def assert_cursor_stable!(baseline, label:, tolerance: 3.0)
    current = cursor_position
    drift = Math.sqrt(((current[:x] - baseline[:x])**2) + ((current[:y] - baseline[:y])**2))
    if drift > tolerance
      raise "Passive startup recovery moved cursor during #{label}: #{baseline.inspect} → #{current.inspect} (#{drift.round(2)}px)"
    end

    {
      status: 'passed',
      baseline: baseline,
      current: current,
      tolerance: tolerance,
      completed_scenario: 'passive startup recovery did not physically move the cursor'
    }
  end

  def assert_snapshot_healthy!(snapshot, label:)
    error = snapshot_health_error(snapshot, label: label)
    raise error if error
  end

  def assert_hidden_after_auto_rehide!(snapshot, label:)
    unless snapshot['autoRehideEnabled'] == true
      raise "#{label}: dirty startup probe expected autoRehide=true, got #{snapshot['autoRehideEnabled'].inspect}"
    end
    return if snapshot['hidingState'] == 'hidden'

    raise "#{label}: dirty startup did not hide after live-anchor recovery (state=#{snapshot['hidingState'].inspect})"
  end

  def wait_for_healthy_snapshot(label:)
    deadline = Time.now + SNAPSHOT_SETTLE_TIMEOUT_SECONDS
    last_snapshot = nil
    last_error = nil

    loop do
      last_snapshot = read_layout_snapshot!
      last_error = snapshot_health_error(last_snapshot, label: label)
      log(
        "#{label} snapshot: hidingState=#{last_snapshot['hidingState']} " \
        "mainRightGap=#{last_snapshot['mainRightGap']} separatorBeforeMain=#{last_snapshot['separatorBeforeMain']} " \
        "startupItemsValid=#{last_snapshot['startupItemsValid']} " \
        "suppression=#{last_snapshot['possibleSystemMenuBarSuppression']}"
      )
      return last_snapshot unless last_error

      break if Time.now >= deadline

      sleep SNAPSHOT_SETTLE_POLL_SECONDS
    end

    raise "#{last_error} (last snapshot: #{last_snapshot.inspect})"
  end

  def snapshot_health_error(snapshot, label:)
    return "#{label}: geometry unavailable" unless snapshot['geometryAvailable']
    return "#{label}: separator not before main" unless snapshot['separatorBeforeMain']
    return "#{label}: main icon not near Control Center" unless snapshot['mainNearControlCenter']
    if snapshot.key?('startupItemsValid') && !truthy?(snapshot['startupItemsValid'])
      return "#{label}: status items are not attached to valid menu bar windows"
    end
    if truthy?(snapshot['possibleSystemMenuBarSuppression'])
      return "#{label}: macOS may be suppressing SaneBar in System Settings > Menu Bar > Allow in Menu Bar"
    end

    nil
  end

  def assert_main_right_gap_stable!(baseline, current, label:)
    baseline_gap = numeric_snapshot_value(baseline, 'mainRightGap')
    current_gap = numeric_snapshot_value(current, 'mainRightGap')
    return unless baseline_gap && current_gap

    drift = (current_gap - baseline_gap).abs
    return if drift <= @main_right_gap_tolerance

    raise "#{label}: mainRightGap drifted by #{drift.round(2)}px (#{baseline_gap} → #{current_gap})"
  end

  def assert_close!(actual, expected, label:, epsilon: 0.001)
    raise "#{label}: missing actual value" if actual.nil?
    raise "#{label}: expected #{expected}, got #{actual}" if (actual - expected).abs > epsilon
  end

  def assert_restored_backup_pair!(main:, separator:, backup_main:, backup_separator:, width:, label:)
    raise "#{label}: missing restored main value" if main.nil?
    raise "#{label}: missing restored separator value" if separator.nil?
    raise "#{label}: separator is not after main (main=#{main}, separator=#{separator})" unless separator > main
    if main > backup_main + 0.001
      raise "#{label}: main moved away from Control Center (backup=#{backup_main}, restored=#{main})"
    end
    if separator < backup_separator - 0.001
      raise "#{label}: separator narrowed the visible lane (backup=#{backup_separator}, restored=#{separator})"
    end

    gap = separator - main
    minimum_gap = preferred_visible_lane_gap(width)
    return if gap + 0.001 >= minimum_gap

    raise "#{label}: visible lane too narrow after recovery (gap=#{gap.round(2)}, minimum=#{minimum_gap.round(2)})"
  end

  def preferred_visible_lane_gap(width)
    return 120.0 unless width.to_f.positive?

    [[width.to_f * 0.09, 180.0].max, 240.0].min
  end

  def numeric_default(key)
    out, status = capture('defaults', 'read', bundle_identifier, key.to_s)
    return nil unless status.success?

    Float(out.strip)
  rescue ArgumentError
    nil
  end

  def write_numeric_default(key, value)
    _out, status = capture('defaults', 'write', bundle_identifier, key.to_s, '-float', value.to_s)
    raise "Failed to write default #{key}=#{value}" unless status.success?
  end

  def current_host_visibility_keys(version)
    [
      "NSStatusItem Visible SaneBar_Main_v#{version}",
      "NSStatusItem VisibleCC SaneBar_Main_v#{version}",
      "NSStatusItem Visible SaneBar_Separator_v#{version}",
      "NSStatusItem VisibleCC SaneBar_Separator_v#{version}"
    ]
  end

  def read_current_host_default(key)
    out, status = capture('defaults', '-currentHost', 'read', 'NSGlobalDomain', key)
    return nil unless status.success?

    out.strip
  end

  def write_current_host_bool(key, value)
    _out, status = capture('defaults', '-currentHost', 'write', 'NSGlobalDomain', key, '-bool', value ? 'true' : 'false')
    raise "Failed to write currentHost default #{key}=#{value}" unless status.success?
  end

  def delete_current_host_default(key)
    capture('defaults', '-currentHost', 'delete', 'NSGlobalDomain', key)
  end

  def restore_current_host_defaults(values)
    values.each do |key, value|
      if value.nil?
        delete_current_host_default(key)
      elsif %w[1 true yes].include?(value.downcase)
        write_current_host_bool(key, true)
      elsif %w[0 false no].include?(value.downcase)
        write_current_host_bool(key, false)
      else
        _out, status = capture('defaults', '-currentHost', 'write', 'NSGlobalDomain', key, value)
        raise "Failed to restore currentHost default #{key}" unless status.success?
      end
    end
  end

  def assert_current_host_default_cleared!(key)
    value = read_current_host_default(key)
    raise "currentHost visibility override still present after launch: #{key}=#{value.inspect}" unless value.nil?
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

  def parsed_snapshot_value(snapshot, key)
    value = snapshot[key]
    return value.to_f if value.is_a?(Numeric)

    nil
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

  def applescript_command(statement)
    capture(
      'osascript',
      '-e',
      %(set appTarget to ((POSIX file "#{@app_path}" as alias) as text)),
      '-e',
      %(using terms from application id "#{bundle_identifier}"),
      '-e',
      %(tell application appTarget to #{statement}),
      '-e',
      'end using terms from'
    )
  end

  def escape_applescript(value)
    value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
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

  def write_artifact!(payload)
    FileUtils.mkdir_p(File.dirname(@artifact_path))
    File.write(@artifact_path, JSON.pretty_generate(payload) + "\n")
  end

  def completed_scenarios_from_cases(cases)
    cases.flat_map do |entry|
      Array(entry[:completed_scenarios]) +
        Array(entry.dig(:cursor_proof, :completed_scenario)) +
        Array(entry.dig(:cursor_proofs)).map { |proof| proof[:completed_scenario] }
    end.compact.uniq
  end
end

exit(StartupLayoutProbe.new.run ? 0 : 1) if __FILE__ == $PROGRAM_NAME
