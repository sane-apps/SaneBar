#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'time'
require 'digest'
require 'securerandom'
require 'rexml/document'
require 'socket'

class StartupLayoutProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  RUNTIME_TARGET_LOCK_PATH = ENV['SANEBAR_RUNTIME_TARGET_LOCK_PATH'] ||
                             ENV['SANEMASTER_RUNTIME_PROBE_LOCK_PATH'] ||
                             '/tmp/sanebar_runtime_probe.lock'
  CURRENT_HOST_STATUS_ITEM_KEY_PATTERN = /\ANSStatusItem (?:Visible(?:CC)?|Preferred Position) SaneBar_/.freeze
  SNAPSHOT_DELAYS = [2.0, 5.0].freeze
  SNAPSHOT_SETTLE_TIMEOUT_SECONDS = 18.0
  SNAPSHOT_SETTLE_POLL_SECONDS = 0.5
  DEFAULT_MAIN_RIGHT_GAP_TOLERANCE = 80.0
  CAPTURE_LOG_OUTPUT_MAX_BYTES = 16_000
  DEFAULT_GRACEFUL_QUIT_TIMEOUT_SECONDS = 3.0
  DEFAULT_FORCE_QUIT_TIMEOUT_SECONDS = 2.0
  NO_KEYCHAIN_LAUNCH_REGISTRATION_GRACE_SECONDS = 1.5
  DEFAULT_RESOURCE_SOAK_SECONDS = 10 * 60
  AUTOMATION_QUIT_TOKEN_ENV = 'SANEBAR_AUTOMATION_QUIT_TOKEN'
  DEFAULT_AUTOMATION_QUIT_MARKER_PATH = '/tmp/sanebar_explicit_termination.token'

  def self.acquire_runtime_target_lock
    return nil if ENV['SANEBAR_RUNTIME_TARGET_LOCK_BYPASS'] == '1'

    raise Errno::ELOOP if File.symlink?(RUNTIME_TARGET_LOCK_PATH)

    2.times do
      cleanup_runtime_target_lock_file
      lock_file = publish_runtime_target_lock_file('startup-layout-probe')
      return lock_file if lock_file
    end

    holder = runtime_target_lock_holder_detail
    detail = holder.empty? ? '' : " (#{holder})"
    warn "Startup layout probe refused to run because the SaneBar runtime target is locked#{detail}."
    false
  rescue Errno::ELOOP
    warn "Startup layout probe refused to use unsafe symlink lock path: #{RUNTIME_TARGET_LOCK_PATH}"
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
    @log_path = ENV.fetch('SANEBAR_STARTUP_PROBE_LOG_PATH', '/tmp/sanebar_startup_layout_probe.log')
    @artifact_path = ENV.fetch('SANEBAR_STARTUP_PROBE_ARTIFACT_PATH', '/tmp/sanebar_startup_layout_probe.json')
    @main_right_gap_tolerance = ENV.fetch(
      'SANEBAR_STARTUP_PROBE_MAIN_RIGHT_GAP_TOLERANCE',
      DEFAULT_MAIN_RIGHT_GAP_TOLERANCE.to_s
    ).to_f
    @workspace = Dir.mktmpdir('sanebar-startup-probe')
    @defaults_backup_path = File.join(@workspace, 'defaults.plist')
    @settings_backup_path = File.join(@workspace, 'settings.json')
    @current_host_backup_path = File.join(@workspace, 'current-host-status-item-state.json')
    @lines = []
    @cases = []
    @bundle_id = nil
    @app_name = nil
    @force_no_keychain = false
    @probe_forced_no_keychain = false
    @had_defaults_domain = false
    @had_settings_file = false
    @was_running = false
    @state_restored = false
    @direct_launch_pids = []
    @automation_quit_token = nil
    @shared_fixture_helper = nil
    @seeded_shared_fixture_for_probe = false
  end

  def run
    validate_target!
    @bundle_id = bundle_identifier
    @app_name = File.basename(@app_path, '.app')
    @was_running = app_running?
    backup_state!
    prepare_startup_probe_settings!

    run_probe_case('current-width backup restore') { run_poisoned_backup_restore_case }
    run_probe_case('currentHost visibility cleanup') { run_current_host_visibility_override_case }
    run_probe_case('autoRehide=false startup') { run_auto_rehide_false_case }
    run_probe_case('#157 dirty reboot recovery') { run_dirty_reboot_recovery_case }
    run_probe_case('#155 Always Hidden dirty replay') { run_always_hidden_dirty_replay_outbound_case }

    restore_state!
    @state_restored = true

    write_artifact!(
      status: 'pass',
      bundle_id: @bundle_id,
      app_path: @app_path,
      candidate: runtime_candidate_metadata,
      runtime_provenance: runtime_provenance,
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
      candidate: runtime_candidate_metadata,
      runtime_provenance: runtime_provenance,
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
    cleanup_seeded_shared_fixture!
    FileUtils.remove_entry(@workspace) if @workspace && Dir.exist?(@workspace)
  end

  private

  def run_probe_case(label)
    puts "   ↳ startup probe: #{label}"
    result = yield
    @cases << result
    puts "   ✅ startup probe: #{label}"
    result
  rescue StandardError => e
    partial = {
      name: label,
      status: 'fail',
      error: e.message
    }
    begin
      partial[:last_snapshot] = read_layout_snapshot!
    rescue StandardError => snapshot_error
      partial[:last_snapshot_error] = "#{snapshot_error.class}: #{snapshot_error.message}"
    end
    @cases << partial
    raise
  end

  def validate_target!
    raise 'SANEBAR_SMOKE_APP_PATH is required' if @app_path.empty?
    raise "Target app missing: #{@app_path}" unless File.directory?(@app_path)
  end

  def backup_state!
    _out, status = capture('defaults', 'export', bundle_identifier, @defaults_backup_path)
    @had_defaults_domain = status.success? && File.exist?(@defaults_backup_path)
    if safe_existing_file?(SETTINGS_PATH)
      FileUtils.mkdir_p(File.dirname(@settings_backup_path))
      safe_copy_file(SETTINGS_PATH, @settings_backup_path)
      @had_settings_file = true
    end
    backup_current_host_status_item_state!
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

    restore_current_host_status_item_state!

    if @had_settings_file
      raise "Missing settings backup #{@settings_backup_path}" unless File.exist?(@settings_backup_path)

      FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
      safe_copy_file(@settings_backup_path, SETTINGS_PATH)
    else
      safe_remove_file(SETTINGS_PATH)
    end

    restore_original_launch_mode!
    launch_app if @was_running
    log('Restored startup probe state')
  end

  def run_poisoned_backup_restore_case
    width = numeric_default('SaneBar_CalibratedScreenWidth') || parsed_snapshot_value(read_layout_snapshot!, 'screenWidth')
    raise 'Missing calibrated screen width for startup probe' unless width

    width_bucket = width.to_i
    main_key, separator_key = preferred_position_keys
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
    restored_main_key, restored_separator_key = preferred_position_keys
    restored_main = resolved_preferred_position(restored_main_key)
    restored_separator = resolved_preferred_position(restored_separator_key)
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
    replay_main_key, replay_separator_key = preferred_position_keys
    replay_main = resolved_preferred_position(replay_main_key)
    replay_separator = resolved_preferred_position(replay_separator_key)
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
    main_key, separator_key = preferred_position_keys
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

    restored_main_key, restored_separator_key = preferred_position_keys
    restored_main = resolved_preferred_position(restored_main_key)
    restored_separator = resolved_preferred_position(restored_separator_key)
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
    ensure_pro_unlocked_for_always_hidden_moves!
    snapshot_after_delay(2.0, label: '#155 AH replay fixture launch T+2s')

    candidates = ensure_preferred_always_hidden_replay_candidates!
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
    resource_soak = run_resource_soak_after_155! if resource_soak_after_155_enabled?
    post_soak = nil
    if resource_soak
      post_soak = {
        hidden_zone: wait_for_icon_zone!(
          hidden_exit_candidate[:unique_id],
          'hidden',
          label: '#155 hidden-exit remains Hidden after resource soak'
        ),
        visible_zone: wait_for_icon_zone!(
          visible_exit_candidate[:unique_id],
          'visible',
          label: '#155 visible-exit remains Visible after resource soak'
        ),
        idle: assert_move_idle!('#155 dirty AH replay post-resource-soak')
      }
    end
    completed_scenarios = [
      '#155 dirty startup does not give up AH replay',
      '#155 dirty startup restores pinned icons into Always Hidden before outbound moves',
      '#155 pinned icon exits Always Hidden after dirty startup',
      '#155 Always Hidden outbound moves leave move state idle'
    ]
    if resource_soak
      completed_scenarios << '#155 dirty startup resource soak remains stable after outbound moves'
      completed_scenarios << '#155 outbound move state remains durable after resource soak'
    end

    result = {
      name: '#155 dirty startup AH replay allows outbound moves',
      completed_scenarios: completed_scenarios,
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
    result[:resource_soak] = resource_soak if resource_soak
    result[:post_soak] = post_soak if post_soak
    result
  ensure
    restore_current_host_defaults(original_visibility_values) if original_visibility_values
  end

  def resource_soak_after_155_enabled?
    ENV['SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_AFTER_155'] == '1'
  end

  def run_resource_soak_after_155!
    duration_seconds = resource_soak_duration_seconds
    min_duration_seconds = resource_soak_min_duration_seconds(duration_seconds)
    env = {
      'SANEMASTER_RESOURCE_SOAK_SECONDS' => duration_seconds.to_s,
      'SANEMASTER_RESOURCE_SOAK_MIN_SECONDS' => min_duration_seconds.to_s,
      'SANEMASTER_RESOURCE_SOAK_PROGRESS' => '0'
    }
    command = [
      File.join('.', 'scripts', 'SaneMaster.rb'),
      'resource_soak',
      '--adaptive',
      '--duration-seconds',
      duration_seconds.to_s,
      '--json'
    ]
    log(
      "#155 dirty AH replay starting resource soak " \
      "duration=#{duration_seconds}s min=#{min_duration_seconds}s"
    )
    out, status = capture_with_env(env, *command)
    report = parse_json_object_output(out, label: '#155 resource soak report')
    raise "#155 resource soak command failed: #{truncated_log_output(out)}" unless status.success?
    raise "#155 resource soak failed: #{Array(report['issues']).join('; ')}" unless report['ok']

    artifact_path = report['artifact_path'].to_s
    artifact = JSON.parse(safe_read_file(artifact_path))
    unless artifact['status'] == 'pass'
      raise "#155 resource soak artifact status is #{artifact['status'].inspect}, expected pass"
    end
    durable_artifact_path = durable_resource_soak_path(artifact_path)
    safe_copy_file(artifact_path, durable_artifact_path)
    log_path = report['log_path'].to_s
    durable_log_path = nil
    unless log_path.empty?
      safe_existing_file?(log_path)
      durable_log_path = durable_resource_soak_path(log_path)
      safe_copy_file(log_path, durable_log_path)
    end

    {
      status: 'pass',
      completed_scenarios: ['#155 dirty startup resource soak remains stable after outbound moves'],
      artifact_completed_scenarios: Array(artifact['completed_scenarios']),
      artifact_path: durable_artifact_path,
      log_path: durable_log_path,
      ephemeral_artifact_path: artifact_path,
      ephemeral_log_path: log_path,
      candidate: artifact['candidate'],
      duration_seconds: report['duration_seconds'],
      sample_count: report['sample_count'],
      adaptive_status: report['adaptive_status'],
      avg_cpu: report['avg_cpu'],
      peak_rss_mb: report['peak_rss_mb'],
      peak_physical_footprint_mb: report['peak_physical_footprint_mb']
    }
  end

  def durable_resource_soak_path(source)
    extension = File.extname(source.to_s)
    extension = '.txt' if extension.empty?
    base = File.basename(@artifact_path, File.extname(@artifact_path))
    File.join(File.dirname(@artifact_path), "#{base}_155_resource_soak#{extension}")
  end

  def resource_soak_duration_seconds
    Integer(
      ENV.fetch('SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_SECONDS', DEFAULT_RESOURCE_SOAK_SECONDS.to_s),
      10
    ).tap do |value|
      raise 'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_SECONDS must be positive' unless value.positive?
    end
  end

  def resource_soak_min_duration_seconds(duration_seconds)
    Integer(
      ENV.fetch('SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_MIN_SECONDS', duration_seconds.to_s),
      10
    ).tap do |value|
      raise 'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_MIN_SECONDS must be non-negative' if value.negative?
    end
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

  def prepare_startup_probe_settings!
    save_settings_json(dirty_reboot_settings(load_settings_json))
    log('Prepared post-onboarding settings for startup layout probe')
  end

  def preferred_always_hidden_replay_candidates
    preferred_bundles = [
      'com.sanebar.sharedfixture',
      'com.sanebar.hostsentinel'
    ]
    list_icon_zones
      .select { |item| item[:movable] && deterministic_replay_candidate_id?(item) }
      .select { |item| preferred_bundles.include?(item[:bundle].to_s) }
      .reject { |item| item[:bundle].to_s == bundle_identifier }
      .sort_by do |item|
        bundle_rank = preferred_bundles.index(item[:bundle].to_s) || 100
        zone_rank = item[:zone].to_s == 'alwaysHidden' ? 2 : 0
        [bundle_rank, zone_rank, item[:unique_id].to_s]
      end
  end

  def ensure_preferred_always_hidden_replay_candidates!
    candidates = preferred_always_hidden_replay_candidates
    return candidates if candidates.length >= 2

    log("Shared fixture candidates missing for #155 startup probe; seeding deterministic fixture")
    begin
      require_relative 'qa'
      @shared_fixture_helper = ProjectQA.new
      fixture_was_running = @shared_fixture_helper.send(:runtime_shared_bundle_fixture_running?)
      ids = @shared_fixture_helper.send(
        :ensure_runtime_shared_bundle_fixture!,
        { app_path: @app_path, no_keychain: no_keychain_launch? }
      )
      fixture_is_running = @shared_fixture_helper.send(:runtime_shared_bundle_fixture_running?)
      @seeded_shared_fixture_for_probe ||= !fixture_was_running && fixture_is_running
      log("Shared fixture seed resolved ids=#{ids.join(',')}")
    rescue StandardError => e
      log("Shared fixture seed failed: #{e.class}: #{e.message}")
    end

    deadline = Time.now + 35
    while Time.now < deadline
      candidates = preferred_always_hidden_replay_candidates
      return candidates if candidates.length >= 2

      sleep 0.5
    end

    candidates
  end

  def ensure_pro_unlocked_for_always_hidden_moves!
    snapshot = read_layout_snapshot!
    return if truthy?(snapshot['licenseIsPro'])

    seed_no_keychain_pro_defaults!
    @probe_forced_no_keychain = true
    @force_no_keychain = true
    log("Relaunching #{@app_name} with no-keychain Pro defaults for #155 move proof")
    quit_app
    launch_app

    pro_snapshot = wait_for_healthy_snapshot(label: '#155 no-keychain Pro relaunch')
    return if truthy?(pro_snapshot['licenseIsPro'])

    raise "#155 dirty replay probe requires Pro no-keychain runtime before moving icons; licenseIsPro=#{pro_snapshot['licenseIsPro'].inspect} #{fallback_pro_defaults_detail}"
  end

  def seed_no_keychain_pro_defaults!
    write_string_default('sane.no-keychain.com.sanebar.app.pro_license_key', 'early-adopter')
    write_string_default('sane.no-keychain.com.sanebar.app.pro_last_validation', Time.now.utc.iso8601)
  end

  def fallback_pro_defaults_detail
    key = 'sane.no-keychain.com.sanebar.app.pro_license_key'
    out, status = capture('defaults', 'read', bundle_identifier, key)
    value = status.success? ? out.strip : 'missing'
    "fallbackDefaults.#{key}=#{value}"
  rescue StandardError => e
    "fallbackDefaults=unavailable(#{e.class}: #{e.message})"
  end

  def deterministic_replay_candidate_id?(item)
    unique_id = item[:unique_id].to_s
    case item[:bundle].to_s
    when 'com.sanebar.sharedfixture'
      unique_id.include?('::statusItem:') || unique_id.include?('::axid:com.sanebar.sharedfixture.')
    when 'com.sanebar.hostsentinel'
      unique_id.include?('::statusItem:') || unique_id.include?('::axid:')
    else
      false
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

  def preferred_position_keys(version = autosave_version)
    [
      "NSStatusItem Preferred Position SaneBar_Main_v#{version}",
      "NSStatusItem Preferred Position SaneBar_Separator_v#{version}"
    ]
  end

  def current_host_preferred_position_key(app_key)
    app_key
      .sub('SaneBar_Main_', 'SaneBar_main_')
      .sub('SaneBar_Separator_', 'SaneBar_separator_') + '_v6'
  end

  def resolved_preferred_position(app_key)
    numeric_default(app_key) || numeric_current_host_default(current_host_preferred_position_key(app_key))
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
    override = ENV['SANEBAR_STARTUP_PROBE_QUIT_TIMEOUT_SECONDS']
    return override.to_f if override && !override.empty?

    return DEFAULT_GRACEFUL_QUIT_TIMEOUT_SECONDS if status&.success?

    0.5
  end

  def force_quit_timeout_seconds
    ENV.fetch('SANEBAR_STARTUP_PROBE_FORCE_QUIT_TIMEOUT_SECONDS', DEFAULT_FORCE_QUIT_TIMEOUT_SECONDS.to_s).to_f
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

  def cleanup_seeded_shared_fixture!
    return unless @seeded_shared_fixture_for_probe && @shared_fixture_helper

    @shared_fixture_helper.send(:cleanup_runtime_shared_bundle_fixture!)
    log('Cleaned up startup-probe seeded shared fixture')
  rescue StandardError => e
    log("Shared fixture cleanup failed: #{e.class}: #{e.message}")
  ensure
    @seeded_shared_fixture_for_probe = false
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

    launched = false
    deadline = Time.now + 20
    until Time.now >= deadline
      if target_process_ready? && layout_snapshot_available?
        launched = true
        break
      end
      sleep 0.25
    end

    raise "Timed out waiting for #{@app_name} launch" unless launched
  end

  def target_process_ready?
    ensure_single_target_process!('launch wait')
  rescue StandardError
    false
  end

  def no_keychain_launch?
    @force_no_keychain || no_keychain_env_requested?
  end

  def no_keychain_env_requested?
    ENV['SANEAPPS_DISABLE_KEYCHAIN'] == '1' || ENV['SANEBAR_PROBE_FORCE_NO_KEYCHAIN'] == '1'
  end

  def restore_original_launch_mode!
    return unless @probe_forced_no_keychain
    return if no_keychain_env_requested?

    @force_no_keychain = false
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
    safe_directory_path!(File.dirname(path))
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
    return unless safe_existing_file?(path)
    return unless safe_read_file(path).strip == @automation_quit_token

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
    if main > preferred_main_startup_zone_limit(width) + 0.001
      raise "#{label}: main outside healthy startup zone (restored=#{main}, limit=#{preferred_main_startup_zone_limit(width).round(2)})"
    end
    gap = separator - main
    minimum_gap = preferred_visible_lane_gap(width)
    # Autosave recovery may safely reanchor a wider backup toward Control
    # Center; the release invariant is enough usable visible lane, not the
    # exact old separator coordinate.
    return if gap + 0.001 >= minimum_gap

    raise "#{label}: visible lane too narrow after recovery (gap=#{gap.round(2)}, minimum=#{minimum_gap.round(2)})"
  end

  def preferred_main_startup_zone_limit(width)
    return 300.0 unless width.to_f.positive?

    [[width.to_f * 0.18, 300.0].max, 480.0].min
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

  def numeric_current_host_default(key)
    out, status = capture('defaults', '-currentHost', 'read', 'NSGlobalDomain', key.to_s)
    return nil unless status.success?

    Float(out.strip)
  rescue ArgumentError
    nil
  end

  def write_numeric_default(key, value)
    _out, status = capture('defaults', 'write', bundle_identifier, key.to_s, '-float', value.to_s)
    raise "Failed to write default #{key}=#{value}" unless status.success?
  end

  def write_string_default(key, value)
    _out, status = capture('defaults', 'write', bundle_identifier, key.to_s, '-string', value.to_s)
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

  def current_host_status_item_state
    out, status = Open3.capture2e('defaults', '-currentHost', 'export', 'NSGlobalDomain', '-')
    log('$ defaults -currentHost export NSGlobalDomain -')
    return {} unless status.success?

    state = parse_current_host_status_item_plist(out)
    log("Parsed #{state.length} currentHost SaneBar status-item key(s)")
    state
  rescue REXML::ParseException => e
    log("Could not parse currentHost defaults export: #{e.message}")
    {}
  end

  def parse_current_host_status_item_plist(plist)
    dict = REXML::Document.new(plist).elements['plist/dict']
    return {} unless dict

    state = {}
    elements = dict.elements.to_a
    index = 0
    while index < elements.length
      key_element = elements[index]
      value_element = elements[index + 1]
      index += 2
      next unless key_element&.name == 'key' && value_element

      key = key_element.text.to_s
      next unless key.match?(CURRENT_HOST_STATUS_ITEM_KEY_PATTERN)

      value = plist_value(value_element)
      state[key] = value unless value.nil?
    end
    state
  end

  def plist_value(element)
    case element.name
    when 'true'
      true
    when 'false'
      false
    when 'integer'
      element.text.to_i
    when 'real'
      element.text.to_f
    when 'string'
      element.text.to_s
    end
  end

  def backup_current_host_status_item_state!
    state = current_host_status_item_state
    safe_write_file(@current_host_backup_path, JSON.pretty_generate(state))
    log("Backed up #{state.length} currentHost SaneBar status-item key(s)")
  end

  def restore_current_host_status_item_state!
    original_state = if safe_existing_file?(@current_host_backup_path)
                       JSON.parse(safe_read_file(@current_host_backup_path))
                     else
                       {}
                     end

    current_host_status_item_state.keys.each { |key| delete_current_host_default(key) }
    original_state.each { |key, value| write_current_host_default_value(key, value) }
    log("Restored #{original_state.length} currentHost SaneBar status-item key(s)")
  rescue JSON::ParserError => e
    raise "Could not restore currentHost status-item state: #{e.message}"
  end

  def write_current_host_bool(key, value)
    _out, status = capture('defaults', '-currentHost', 'write', 'NSGlobalDomain', key, '-bool', value ? 'true' : 'false')
    raise "Failed to write currentHost default #{key}=#{value}" unless status.success?
  end

  def write_current_host_default_value(key, value)
    case value
    when true, false
      write_current_host_bool(key, value)
    when Integer
      _out, status = capture('defaults', '-currentHost', 'write', 'NSGlobalDomain', key, '-int', value.to_s)
      raise "Failed to restore currentHost default #{key}" unless status.success?
    when Numeric
      _out, status = capture('defaults', '-currentHost', 'write', 'NSGlobalDomain', key, '-float', value.to_s)
      raise "Failed to restore currentHost default #{key}" unless status.success?
    else
      _out, status = capture('defaults', '-currentHost', 'write', 'NSGlobalDomain', key, '-string', value.to_s)
      raise "Failed to restore currentHost default #{key}" unless status.success?
    end
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
        write_current_host_default_value(key, value)
      end
    end
  end

  def assert_current_host_default_cleared!(key)
    value = read_current_host_default(key)
    raise "currentHost visibility override still present after launch: #{key}=#{value.inspect}" unless value.nil?
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
    ensure_single_target_process!("AppleScript #{statement}")
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
    log_capture_output(out)
    [out, status]
  end

  def capture_with_env(env, *cmd)
    out, status = Open3.capture2e(env, *cmd)
    env_prefix = env.keys.sort.map { |key| "#{key}=#{env[key]}" }.join(' ')
    log("$ #{env_prefix} #{cmd.join(' ')}")
    log_capture_output(out)
    [out, status]
  end

  def parse_json_object_output(output, label:)
    text = output.to_s
    start_index = text.index('{')
    end_index = text.rindex('}')
    raise "#{label} did not include a JSON object" unless start_index && end_index && end_index >= start_index

    JSON.parse(text[start_index..end_index])
  rescue JSON::ParserError => e
    raise "#{label} returned invalid JSON: #{e.message}"
  end

  def log_capture_output(output)
    text = output.to_s.strip
    return if text.empty?

    log(truncated_log_output(text))
  end

  def truncated_log_output(text)
    return text if text.bytesize <= CAPTURE_LOG_OUTPUT_MAX_BYTES

    omitted = text.bytesize - CAPTURE_LOG_OUTPUT_MAX_BYTES
    prefix = text.byteslice(0, CAPTURE_LOG_OUTPUT_MAX_BYTES).to_s.scrub
    "#{prefix}\n... truncated #{omitted} byte(s) of command output ..."
  end

  def log(line)
    @lines << "[#{Time.now.utc.iso8601}] #{line}"
  end

  def persist_log!
    FileUtils.mkdir_p(File.dirname(@log_path))
    safe_write_file(@log_path, @lines.join("\n") + "\n")
  end

  def write_artifact!(payload)
    FileUtils.mkdir_p(File.dirname(@artifact_path))
    safe_write_file(@artifact_path, JSON.pretty_generate(payload) + "\n")
  end

  def runtime_provenance
    {
      mini_runtime: mini_runtime_host?,
      host: Socket.gethostname,
      generated_at: Time.now.utc.iso8601,
      app_path: @app_path,
      bundle_id: @bundle_id
    }
  end

  def runtime_candidate_metadata
    {
      app_path: @app_path,
      app_version: bundle_info_value('CFBundleShortVersionString'),
      app_build: bundle_info_value('CFBundleVersion')
    }
  end

  def bundle_info_value(key)
    info_plist = File.join(@app_path.to_s, 'Contents', 'Info.plist')
    return nil unless File.exist?(info_plist)

    out, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", info_plist)
    status.success? ? out.strip : nil
  end

  def mini_runtime_host?
    Socket.gethostname.to_s.downcase.include?('mini')
  rescue StandardError
    false
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

  def completed_scenarios_from_cases(cases)
    cases.flat_map do |entry|
      Array(entry[:completed_scenarios]) +
        Array(entry.dig(:cursor_proof, :completed_scenario)) +
        Array(entry.dig(:cursor_proofs)).map { |proof| proof[:completed_scenario] }
    end.compact.uniq
  end
end

if __FILE__ == $PROGRAM_NAME
  runtime_lock = StartupLayoutProbe.acquire_runtime_target_lock
  status = 75

  unless runtime_lock == false
    begin
      status = StartupLayoutProbe.new.run ? 0 : 1
    ensure
      StartupLayoutProbe.release_runtime_target_lock(runtime_lock)
    end
  end

  $stdout.flush
  $stderr.flush
  exit!(status)
end
