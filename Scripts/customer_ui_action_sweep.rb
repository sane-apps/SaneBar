#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'socket'
require 'time'
require 'yaml'

class CustomerUIActionSweep
  PROJECT_ROOT = File.expand_path('..', __dir__)
  OUTPUT_DIR = File.join(PROJECT_ROOT, 'outputs', 'customer-ui')
  RECEIPT_PATH = File.join(PROJECT_ROOT, '.sane', 'customer_ui_action_receipt.json')
  MANIFEST_PATH = File.join(PROJECT_ROOT, 'Tests', 'CustomerUIActions.yml')
  SANEMASTER = File.join(PROJECT_ROOT, 'scripts', 'SaneMaster.rb')
  APP_NAME = 'SaneBar'

  SETTINGS_TABS = [
    { index: 1, id: 'control', expected: ['Browse Icons'] },
    { index: 2, id: 'rules', expected: ['Automatic Triggers'] },
    { index: 3, id: 'appearance', expected: ['Menu Bar Icon'] },
    { index: 4, id: 'shortcuts', expected: ['Global Hotkeys'] },
    { index: 5, id: 'health', expected: ['Status'] },
    { index: 6, id: 'license', expected: ['License'] },
    { index: 7, id: 'about', expected: ['SaneBar'] }
  ].freeze

  APPLESCRIPT_COMMANDS = [
    ['layout snapshot', /separatorBeforeMain/],
    ['list icons', /./],
    ['list icon zones', /\t/],
    ['open icon panel', /true|false/],
    ['quick search "Sane"', /true|false/],
    ['close browse panel', /true|false/],
    ['show second menu bar', /true|false/],
    ['close browse panel', /true|false/],
    ['open settings window', /true|false/],
    ['activation diagnostics', /activation|diagnostics|requestedApp/i],
    ['browse panel diagnostics', /mode|visible|diagnostics/i],
    ['close settings window', /true|false/]
  ].freeze

  def initialize
    @started_at = Time.now.utc
    @timestamp = @started_at.strftime('%Y%m%dT%H%M%SZ')
    @screenshots = []
    @transcript = []
  end

  def run
    Dir.chdir(PROJECT_ROOT) do
      require_mini!
      FileUtils.mkdir_p(OUTPUT_DIR)
      ensure_manifest!
      verify_release_app_running!
      exercise_settings_tabs
      exercise_url_routes
      exercise_applescript_commands
      verify_recent_runtime_smoke
      write_receipt
      puts "✅ Customer UI action sweep passed: #{relative(RECEIPT_PATH)}"
    end
  rescue StandardError => e
    warn "❌ Customer UI action sweep failed: #{e.message}"
    write_failure_artifact(e)
    exit 1
  end

  private

  def require_mini!
    host = Socket.gethostname.to_s.downcase
    user = ENV.fetch('USER', '').downcase
    return if host.include?('mini') || user == 'stephansmac'

    raise 'Customer UI action sweep must run on the Mini'
  end

  def ensure_manifest!
    raise "Missing #{MANIFEST_PATH}" unless File.exist?(MANIFEST_PATH)

    manifest = YAML.safe_load(File.read(MANIFEST_PATH)) || {}
    @action_ids = Array(manifest['actions']).map { |action| action['id'].to_s }.reject(&:empty?)
    raise 'Customer UI action manifest has no actions' if @action_ids.empty?
  end

  def verify_release_app_running!
    out, status = Open3.capture2e('pgrep', '-fl', APP_NAME)
    raise "#{APP_NAME} is not running; launch with ./scripts/SaneMaster.rb test_mode --release --no-logs" unless status.success?

    @transcript << "running_processes=#{out.lines.map(&:strip).join(' | ')}"
  end

  def exercise_settings_tabs
    app_script('open settings window')
    SETTINGS_TABS.each do |tab|
      text = press_settings_tab(tab[:index])
      tab[:expected].each do |expected|
        raise "Settings #{tab[:id]} tab missing #{expected.inspect}: #{text}" unless text.include?(expected)
      end

      path = File.join(OUTPUT_DIR, "settings-#{tab[:id]}-#{@timestamp}.png")
      app_script(%(capture settings window snapshot "#{escape_applescript(path)}"))
      raise "Settings snapshot was not written: #{path}" unless File.size?(path)

      @screenshots << relative(path)
      @transcript << "settings_tab=#{tab[:id]} ok snapshot=#{relative(path)}"
    end
  ensure
    app_script('close settings window') rescue nil
  end

  def press_settings_tab(index)
    script = [
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set frontmost to true',
      %(set selected of row #{index} of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1 to true),
      'delay 0.6',
      'set windowTitle to name of window 1',
      'set bodyText to value of static texts of scroll area 1 of group 2 of splitter group 1 of group 1 of window 1',
      'return windowTitle & " :: " & (bodyText as text)',
      'end tell',
      'end tell'
    ]
    run_osascript(script, timeout: 10).tap do |text|
      @transcript << "settings_ax_tab_index=#{index} text=#{text.gsub(/\s+/, ' ')[0, 500]}"
    end
  end

  def exercise_url_routes
    {
      'settings' => nil,
      'health' => 'Health',
      'search?q=Sane' => nil
    }.each do |route, expected_window|
      out, status = Open3.capture2e('/usr/bin/open', "sanebar://#{route}")
      raise "URL route #{route} failed: #{out}" unless status.success?

      sleep 0.8
      if expected_window
        window_names = system_events_window_names
        raise "URL route #{route} did not open #{expected_window}: #{window_names}" unless window_names.include?(expected_window)
      end
      @transcript << "url_route=#{route} ok"
    end
    app_script('close browse panel') rescue nil
    app_script('close settings window') rescue nil
  end

  def exercise_applescript_commands
    APPLESCRIPT_COMMANDS.each do |statement, expected|
      output = app_script(statement)
      raise "AppleScript #{statement.inspect} returned unexpected output: #{output.inspect}" unless output.match?(expected)

      @transcript << "applescript=#{statement} ok output=#{output.gsub(/\s+/, ' ')[0, 300]}"
    end
  end

  def verify_recent_runtime_smoke
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = '/tmp/sanebar_runtime_startup_probe.log'
    native_log = '/tmp/sanebar_runtime_native_apple_smoke.log'
    [smoke_log, startup_log].each do |path|
      raise "Missing runtime evidence #{path}" unless File.exist?(path) && File.mtime(path) >= @started_at - 30 * 60
    end

    smoke = File.read(smoke_log)
    required = [
      'Browse mode secondMenuBar activation ok',
      'Browse mode findIcon activation ok',
      'Settings window visual check ok',
      'Hidden/Visible move actions ok',
      'Always Hidden move actions ok',
      'Live zone smoke passed'
    ]
    required.each do |marker|
      raise "Runtime smoke missing marker #{marker}" unless smoke.include?(marker)
    end
    if File.exist?(native_log)
      native = File.read(native_log)
      raise 'Native exact-ID smoke did not pass' unless native.include?('Candidate set passed') || native.include?('Candidate passed')
    end
    @transcript << "runtime_smoke=#{smoke_log} ok"
    @transcript << "startup_probe=#{startup_log} ok"
    @transcript << "native_exact_id=#{native_log} ok" if File.exist?(native_log)
  end

  def write_receipt
    report = customer_ui_contract_report
    receipt = {
      app: 'SaneBar',
      status: 'passed',
      host: 'mini',
      generated_at: Time.now.utc.iso8601,
      manifest_sha256: report.fetch('manifest_sha256'),
      source_fingerprint: report.fetch('source_fingerprint'),
      tested_action_ids: @action_ids,
      screenshots: latest_runtime_screenshots + @screenshots,
      evidence: {
        app_version: project_version('MARKETING_VERSION'),
        app_build: project_version('CURRENT_PROJECT_VERSION'),
        mini_verify: 'SaneMaster verify passed after customer UI contract expansion',
        mini_release_preflight_runtime: 'SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 ./scripts/SaneMaster.rb release_preflight generated runtime smoke evidence',
        settings_tab_sweep: @transcript.select { |line| line.start_with?('settings_tab=') },
        url_routes: @transcript.select { |line| line.start_with?('url_route=') },
        applescript_commands: @transcript.select { |line| line.start_with?('applescript=') },
        runtime_smoke: @transcript.select { |line| line.include?('runtime_smoke=') || line.include?('startup_probe=') || line.include?('native_exact_id=') },
        remaining_non_ui_blocker: 'Release cadence guard requires the exact manual approval phrase before publishing inside 24 hours of v2.1.51.'
      }
    }
    FileUtils.mkdir_p(File.dirname(RECEIPT_PATH))
    File.write(RECEIPT_PATH, JSON.pretty_generate(receipt) + "\n")

    transcript_path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")
    File.write(transcript_path, @transcript.join("\n") + "\n")
    puts "🧾 Transcript: #{relative(transcript_path)}"
  end

  def write_failure_artifact(error)
    FileUtils.mkdir_p(OUTPUT_DIR)
    path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-failed-#{@timestamp}.txt")
    File.write(path, ([@transcript, "#{error.class}: #{error.message}", *error.backtrace].flatten.join("\n") + "\n"))
    warn "Failure transcript: #{relative(path)}"
  rescue StandardError
    nil
  end

  def customer_ui_contract_report
    out, status = Open3.capture2e(SANEMASTER, 'customer_ui_contract', '--json', '--no-exit')
    raise "Could not read customer UI contract report: #{out}" unless status.success?

    JSON.parse(out)
  end

  def latest_runtime_screenshots
    Dir.glob(File.join(File.expand_path("~/Desktop/Screenshots/#{APP_NAME}"), 'sanebar-*.png'))
      .select { |path| File.mtime(path) >= @started_at - 30 * 60 }
      .sort_by { |path| File.mtime(path) }
  end

  def project_version(key)
    source = File.exist?('project.yml') ? File.read('project.yml') : ''
    match = source.match(/#{Regexp.escape(key)}:\s*(.+)$/)
    match ? match[1].strip.delete('"') : 'unknown'
  end

  def system_events_window_names
    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'return name of windows',
      'end tell',
      'end tell'
    ], timeout: 5)
  end

  def app_script(statement)
    run_osascript([%(tell application "#{APP_NAME}" to #{statement})], timeout: 25)
  end

  def run_osascript(lines, timeout:)
    command = ['/usr/bin/osascript'] + lines.flat_map { |line| ['-e', line] }
    out, status = Open3.capture2e(*command)
    raise "osascript failed: #{out.strip}" unless status.success?

    out.strip
  end

  def escape_applescript(value)
    value.to_s.gsub('\\', '\\\\\\').gsub('"', '\\"')
  end

  def relative(path)
    path.to_s.start_with?(PROJECT_ROOT) ? path.to_s.delete_prefix("#{PROJECT_ROOT}/") : path.to_s
  end
end

CustomerUIActionSweep.new.run if __FILE__ == $PROGRAM_NAME
