#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'time'

class WakeLayoutProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  SNAPSHOT_DELAYS = [1.0, 5.0, 15.0].freeze
  BLOCKED_LOG_PATTERNS = [
    /Status item remained off-menu-bar/i,
    /Bumping autosave version .*status item recovery/i,
    /Status item recovery stopped after/i,
    /geometry drift detected/i
  ].freeze
  REQUIRED_WAKE_PATTERNS = [
    /System did wake/i,
    /Screens did wake/i
  ].freeze

  def initialize
    @app_path = ENV.fetch('SANEBAR_SMOKE_APP_PATH', '').strip
    @log_path = ENV.fetch('SANEBAR_WAKE_PROBE_LOG_PATH', '/tmp/sanebar_wake_layout_probe.log')
    @artifact_path = ENV.fetch('SANEBAR_WAKE_PROBE_ARTIFACT_PATH', '/tmp/sanebar_wake_layout_probe.json')
    @display_sleep_seconds = ENV.fetch('SANEBAR_WAKE_PROBE_DISPLAY_SLEEP_SECONDS', '3').to_f
    @wake_assertion_seconds = ENV.fetch('SANEBAR_WAKE_PROBE_WAKE_ASSERTION_SECONDS', '2').to_i
    @workspace = Dir.mktmpdir('sanebar-wake-probe')
    @settings_backup_path = File.join(@workspace, 'settings.json')
    @lines = []
    @cases = []
    @bundle_id = nil
    @app_name = nil
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

    app_script('hide items')
    baseline = wait_for_snapshot(label: 'hidden baseline') do |snapshot|
      snapshot['hidingState'] == 'hidden' && snapshot_healthy?(snapshot)
    end

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    snapshots = snapshots_after_wake(wake_time, label: 'hidden')
    snapshots.each do |entry|
      assert_snapshot_state!(entry[:snapshot], expected_state: 'hidden', label: "hidden #{entry[:delay]}s")
    end
    log_scan = scan_logs_since(case_started_at)

    quit_app

    {
      name: 'hidden state survives display sleep wake',
      baseline: baseline,
      wake_time: wake_time.iso8601,
      snapshots: snapshots,
      log_scan: log_scan
    }
  end

  def run_expanded_case
    configure_settings!(auto_rehide: false)
    launch_app

    app_script('show hidden')
    baseline = wait_for_snapshot(label: 'expanded baseline') do |snapshot|
      snapshot['hidingState'] == 'expanded' && snapshot_healthy?(snapshot)
    end

    case_started_at = Time.now.utc
    wake_time = trigger_display_sleep_cycle!
    snapshots = snapshots_after_wake(wake_time, label: 'expanded')
    snapshots.each do |entry|
      assert_snapshot_state!(entry[:snapshot], expected_state: 'expanded', label: "expanded #{entry[:delay]}s")
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

  def trigger_display_sleep_cycle!
    raise 'Display sleep duration must be positive' unless @display_sleep_seconds.positive?

    log("Triggering display sleep for #{@display_sleep_seconds}s")
    out, status = capture('pmset', 'displaysleepnow')
    raise "Failed to trigger display sleep: #{out}" unless status.success?

    sleep @display_sleep_seconds

    log("Triggering wake assertion for #{@wake_assertion_seconds}s")
    out, status = capture('caffeinate', '-u', '-t', @wake_assertion_seconds.to_s)
    raise "Failed to trigger wake assertion: #{out}" unless status.success?

    Time.now.utc
  end

  def snapshots_after_wake(wake_time, label:)
    SNAPSHOT_DELAYS.map do |delay|
      remaining = (wake_time + delay) - Time.now.utc
      sleep remaining if remaining.positive?
      snapshot = read_layout_snapshot!
      log(
        "#{label} snapshot after #{delay}s: hidingState=#{snapshot['hidingState']} " \
        "mainRightGap=#{snapshot['mainRightGap']} separatorBeforeMain=#{snapshot['separatorBeforeMain']}"
      )
      { delay: delay, snapshot: snapshot }
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

    raise "Wake probe hit destructive recovery logs: #{blocked_hits.first(3).join(' | ')}" unless blocked_hits.empty?

    {
      observed_logs: out.lines.any? { |line| line.match?(/^\d{4}-\d{2}-\d{2}/) },
      observed_wake_logs: !wake_hits.empty?,
      wake_hits: wake_hits.first(6),
      blocked_hits: blocked_hits
    }
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
  end

  def snapshot_healthy?(snapshot)
    snapshot['geometryAvailable'] && snapshot['separatorBeforeMain'] && snapshot['mainNearControlCenter']
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
    out, status = capture('open', @app_path)
    raise "Failed to launch #{@app_path}: #{out}" unless status.success?

    deadline = Time.now + 20
    until Time.now >= deadline
      break if app_running? && layout_snapshot_available?
      sleep 0.25
    end

    raise "Timed out waiting for #{@app_name} launch" unless app_running? && layout_snapshot_available?
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

exit(WakeLayoutProbe.new.run ? 0 : 1) if __FILE__ == $PROGRAM_NAME
