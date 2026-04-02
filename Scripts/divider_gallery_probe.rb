#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'time'
require 'tmpdir'

class DividerGalleryProbe
  SETTINGS_PATH = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
  STYLE_CASES = %w[slash pipe backslash pipeThin dot].freeze
  COLOR_CASES = %w[white blue green orange red pink].freeze
  BUNDLE_IDENTIFIER_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9.-]*\z/.freeze

  def initialize
    @app_path = ENV.fetch('SANEBAR_SMOKE_APP_PATH', '').strip
    @output_dir = ENV.fetch('SANEBAR_DIVIDER_GALLERY_OUTPUT_DIR', '/tmp/sanebar-divider-gallery')
    @workspace = Dir.mktmpdir('sanebar-divider-gallery')
    @settings_backup_path = File.join(@workspace, 'settings.json')
    @artifact_path = File.join(@output_dir, 'artifact.json')
    @log_path = File.join(@output_dir, 'probe.log')
    @bundle_id = nil
    @app_name = nil
    @had_settings_file = false
    @was_running = false
    @log_lines = []
    @cases = []
    @state_restored = false
  end

  def run
    validate_target!
    @bundle_id = bundle_identifier
    @app_name = File.basename(@app_path, '.app')
    @was_running = app_running?

    FileUtils.mkdir_p(@output_dir)
    backup_state!
    launch_app unless @was_running
    wait_for_app_ready!

    capture_matrix

    restore_state!
    @state_restored = true
    write_artifact(status: 'pass', cases: @cases)
    persist_log!
    puts "✅ Divider gallery probe passed (#{@cases.count} captures)"
    true
  rescue StandardError => e
    write_artifact(
      status: 'fail',
      error: e.message,
      backtrace: Array(e.backtrace).first(12),
      cases: @cases
    )
    log("❌ Divider gallery probe failed: #{e.message}")
    persist_log!
    warn e.message
    false
  ensure
    unless @state_restored
      begin
        restore_state!
      rescue StandardError => e
        log("⚠️ Restore failed: #{e.message}")
        persist_log!
      end
    end
    FileUtils.remove_entry(@workspace) if @workspace && Dir.exist?(@workspace)
  end

  private

  def validate_target!
    raise 'SANEBAR_SMOKE_APP_PATH is required' if @app_path.empty?
    raise "Target app missing: #{@app_path}" unless File.directory?(@app_path)
  end

  def backup_state!
    if File.exist?(SETTINGS_PATH)
      FileUtils.cp(SETTINGS_PATH, @settings_backup_path)
      @had_settings_file = true
    end
    log("Backed up settings file=#{@had_settings_file}")
  end

  def restore_state!
    restore_live_divider_settings!
    quit_app unless @was_running
    log('Restored divider gallery probe state')
  end

  def capture_matrix
    STYLE_CASES.each do |style|
      COLOR_CASES.each do |color|
        app_script(%(set divider style "#{escape_quotes(style)}"))
        app_script(%(set divider color "#{escape_quotes(color)}"))
        app_script('show hidden')
        snapshot = wait_for_snapshot(label: "#{style}-#{color}") do |current|
          current['hidingState'] == 'expanded' && snapshot_ready?(current, style: style, color: color)
        end

        path = File.join(@output_dir, "#{style}-#{color}.png")
        capture_region(snapshot, path)
        @cases << {
          style: style,
          color: color,
          path: path,
          snapshot: snapshot
        }
        log("Captured #{style}/#{color} -> #{path}")
      end
    end
  end

  def capture_region(_snapshot, path)
    statement = %(capture divider strip snapshot "#{escape_quotes(path)}")
    out, status = capture('osascript', '-e', "tell application id \"#{bundle_identifier}\" to #{statement}")
    raise "Failed to capture divider strip #{path}: #{out}" unless status.success?

    raise "Snapshot missing at #{path}" unless File.exist?(path)
  end

  def wait_for_snapshot(label:, timeout: 20.0, interval: 0.25)
    deadline = Time.now + timeout
    last_snapshot = nil

    until Time.now >= deadline
      last_snapshot = read_layout_snapshot!
      return last_snapshot if yield(last_snapshot)

      sleep interval
    end

    raise "#{label} did not stabilize before timeout: #{last_snapshot.inspect}"
  end

  def snapshot_ready?(snapshot, style:, color:)
    truthy?(snapshot['geometryAvailable']) &&
      truthy?(snapshot['dividerHasLiveWindow']) &&
      truthy?(snapshot['dividerHasLiveBounds']) &&
      snapshot['dividerRequestedStyle'] == style &&
      snapshot['dividerRequestedColor'] == color &&
      snapshot['dividerAppliedStyle'] == style &&
      snapshot['dividerAppliedColor'] == color &&
      truthy?(snapshot['separatorBeforeMain']) &&
      numeric(snapshot['separatorOriginX']) &&
      numeric(snapshot['mainIconLeftEdgeX'])
  end

  def numeric(value)
    return nil if value.nil?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def truthy?(value)
    value == true || value.to_s == 'true'
  end

  def bundle_identifier
    return @bundle_id if @bundle_id

    info_plist = File.join(@app_path, 'Contents', 'Info.plist')
    out, status = capture('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', info_plist)
    raise "Could not read bundle identifier from #{info_plist}" unless status.success?

    value = out.strip
    raise "Empty bundle identifier for #{@app_path}" if value.empty?
    raise "Unsafe bundle identifier #{value.inspect}" unless value.match?(BUNDLE_IDENTIFIER_PATTERN)

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

    wait_for_app_ready!
  end

  def wait_for_app_ready!
    deadline = Time.now + 20
    until Time.now >= deadline
      return true if app_running? && layout_snapshot_available?

      sleep 0.25
    end

    raise "Timed out waiting for #{@app_name} launch"
  end

  def restore_live_divider_settings!
    settings = load_backup_settings_json
    style = settings['dividerStyle']
    color = settings['dividerColor']

    app_script(%(set divider style "#{escape_quotes(style)}")) if style.is_a?(String) && STYLE_CASES.include?(style)
    app_script(%(set divider color "#{escape_quotes(color)}")) if color.is_a?(String) && COLOR_CASES.include?(color)
  rescue StandardError => e
    log("⚠️ Live divider restore failed: #{e.message}")
  end

  def layout_snapshot_available?
    read_layout_snapshot!
    true
  rescue StandardError => e
    log("layout snapshot not ready yet: #{e.message}")
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
    value.gsub('"', '\"')
  end

  def load_settings_json
    return {} unless File.exist?(SETTINGS_PATH)

    JSON.parse(File.read(SETTINGS_PATH))
  rescue JSON::ParserError => e
    raise "Could not parse #{SETTINGS_PATH}: #{e.message}"
  end

  def load_backup_settings_json
    return {} unless File.exist?(@settings_backup_path)

    JSON.parse(File.read(@settings_backup_path))
  rescue JSON::ParserError => e
    raise "Could not parse #{@settings_backup_path}: #{e.message}"
  end

  def capture(*cmd)
    out, status = Open3.capture2e(*cmd)
    log("$ #{cmd.join(' ')}")
    log(out.strip) unless out.strip.empty?
    [out, status]
  end

  def write_artifact(payload)
    FileUtils.mkdir_p(@output_dir)
    File.write(@artifact_path, JSON.pretty_generate(payload) + "\n")
  end

  def log(message)
    @log_lines << "[#{Time.now.utc.iso8601}] #{message}"
  end

  def persist_log!
    FileUtils.mkdir_p(@output_dir)
    File.write(@log_path, @log_lines.join("\n") + "\n")
  end
end

exit(DividerGalleryProbe.new.run ? 0 : 1)
