#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'time'

class StartupLayoutProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  SNAPSHOT_DELAYS = [2.0, 5.0].freeze

  def initialize
    @app_path = ENV.fetch('SANEBAR_SMOKE_APP_PATH', '').strip
    @log_path = ENV.fetch('SANEBAR_STARTUP_PROBE_LOG_PATH', '/tmp/sanebar_startup_layout_probe.log')
    @artifact_path = ENV.fetch('SANEBAR_STARTUP_PROBE_ARTIFACT_PATH', '/tmp/sanebar_startup_layout_probe.json')
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
    auto_rehide_case = run_auto_rehide_false_case

    @cases << poisoned_backup_case
    @cases << auto_rehide_case

    restore_state!
    @state_restored = true

    write_artifact!(
      status: 'pass',
      bundle_id: @bundle_id,
      app_path: @app_path,
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

    t2 = snapshot_after_delay(2.0)
    t5 = snapshot_after_delay(5.0)
    restored_main = numeric_default(main_key)
    restored_separator = numeric_default(separator_key)
    assert_close!(restored_main, backup_main, label: 'restored main preferred position')
    assert_close!(restored_separator, backup_separator, label: 'restored separator preferred position')
    assert_snapshot_healthy!(t2, label: 'poisoned-startup T+2s')
    assert_snapshot_healthy!(t5, label: 'poisoned-startup T+5s')

    quit_app
    launch_app

    replay = snapshot_after_delay(2.0)
    replay_main = numeric_default(main_key)
    replay_separator = numeric_default(separator_key)
    assert_close!(replay_main, backup_main, label: 'restart replay main preferred position')
    assert_close!(replay_separator, backup_separator, label: 'restart replay separator preferred position')
    assert_snapshot_healthy!(replay, label: 'restart replay T+2s')

    {
      name: 'current-width backup beats ordinal seeds',
      width_bucket: width_bucket,
      backup_main: backup_main,
      backup_separator: backup_separator,
      restored_main: restored_main,
      restored_separator: restored_separator,
      snapshots: {
        t2: t2,
        t5: t5,
        replay_t2: replay
      }
    }
  end

  def run_auto_rehide_false_case
    settings = load_settings_json
    settings['autoRehide'] = false

    quit_app
    save_settings_json(settings)
    log('Updated settings.json for startup probe: autoRehide=false')
    launch_app

    t2 = snapshot_after_delay(2.0)
    t5 = snapshot_after_delay(5.0)
    unless t2['autoRehideEnabled'] == false && t5['autoRehideEnabled'] == false
      raise "autoRehide=false probe did not stick (T+2=#{t2['autoRehideEnabled'].inspect}, T+5=#{t5['autoRehideEnabled'].inspect})"
    end
    unless t2['hidingState'] == 'expanded' && t5['hidingState'] == 'expanded'
      raise "autoRehide=false probe rehid the bar (T+2=#{t2['hidingState'].inspect}, T+5=#{t5['hidingState'].inspect})"
    end
    assert_snapshot_healthy!(t2, label: 'autoRehide=false T+2s')
    assert_snapshot_healthy!(t5, label: 'autoRehide=false T+5s')

    {
      name: 'autoRehide=false prevents launch hide',
      snapshots: {
        t2: t2,
        t5: t5
      }
    }
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

  def snapshot_after_delay(delay_seconds)
    sleep delay_seconds
    snapshot = read_layout_snapshot!
    log("Snapshot after #{delay_seconds}s: hidingState=#{snapshot['hidingState']} mainRightGap=#{snapshot['mainRightGap']} separatorBeforeMain=#{snapshot['separatorBeforeMain']}")
    snapshot
  end

  def assert_snapshot_healthy!(snapshot, label:)
    raise "#{label}: geometry unavailable" unless snapshot['geometryAvailable']
    raise "#{label}: separator not before main" unless snapshot['separatorBeforeMain']
    raise "#{label}: main icon not near Control Center" unless snapshot['mainNearControlCenter']
  end

  def assert_close!(actual, expected, label:, epsilon: 0.001)
    raise "#{label}: missing actual value" if actual.nil?
    raise "#{label}: expected #{expected}, got #{actual}" if (actual - expected).abs > epsilon
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
end

exit(StartupLayoutProbe.new.run ? 0 : 1) if __FILE__ == $PROGRAM_NAME
