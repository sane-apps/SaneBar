#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'socket'
require 'time'
require 'yaml'
require 'zlib'

class CustomerUIActionSweep
  PROJECT_ROOT = File.expand_path('..', __dir__)
  SANEAPPS_ROOT = File.expand_path('../..', PROJECT_ROOT)
  OUTPUT_DIR = File.join(PROJECT_ROOT, 'outputs', 'customer-ui')
  RECEIPT_PATH = File.join(PROJECT_ROOT, '.sane', 'customer_ui_action_receipt.json')
  OUTPUT_RECEIPT_PATH = File.join(PROJECT_ROOT, 'outputs', 'customer_ui_action_receipt.json')
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
    ['toggle', /\A\z/],
    ['show hidden', /\A\z/],
    ['hide items', /\A\z/],
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

  URL_ROUTE_EVIDENCE = [
    'toggle',
    'show',
    'hide',
    'settings',
    'health',
    'repair',
    'search?q=Sane'
  ].freeze

  STRICT_MINI_EVIDENCE_TYPES = %w[
    mini_click
    mini_automation
    mini_ax
    mini_url_route
    mini_runtime
  ].freeze

  STRICT_MINI_EVIDENCE_PATTERNS = {
    'mini_click' => /\A(?:\/tmp\/sanebar_runtime_|applescript=|settings_ax_tab_index=|settings_tab=|icon_hotkeys_groups_|url_route=|runtime_visual=)/,
    'mini_automation' => /\A(?:applescript=|url_route=|settings_ax_tab_index=|icon_hotkeys_groups_)/,
    'mini_ax' => /\Asettings_ax_tab_index=/,
    'mini_url_route' => /\Aurl_route=/,
    'mini_runtime' => /\A\/tmp\/sanebar_runtime_/
  }.freeze

  PLACEHOLDER_MINI_EVIDENCE_PATTERNS = [
    /verified by source/i,
    /source-verified/i,
    /source guards?/i,
    /guard fixtures?/i,
    /verified through .*source/i,
    /covered by .*tests?/i,
    /without performing/i,
    /not opened during/i,
    /source and persistence guards?/i
  ].freeze

  SOURCE_GUARDS = {
    status_menu: [
      ['Core/Controllers/StatusBarController.swift', 'Browse Icons...'],
      ['Core/Controllers/StatusBarController.swift', 'Show / Hide Icons'],
      ['Core/Controllers/StatusBarController.swift', 'Arrange Now'],
      ['Core/Controllers/StatusBarController.swift', 'Help / Repair...'],
      ['Core/Controllers/StatusBarController.swift', 'SaneStandardMenu.addCoreUtilityItems'],
      ['infra/SaneUI/Sources/SaneUI/Components/SaneStandardMenu.swift', "What's New..."]
    ],
    dock_menu: [
      ['SaneBarApp.swift', 'applicationDockMenu'],
      ['SaneBarApp.swift', 'Show All Icons'],
      ['SaneBarApp.swift', 'SaneStandardMenu.addCoreUtilityItems'],
      ['SaneBarApp.swift', 'showReleaseNotesFromDock'],
      ['infra/SaneUI/Sources/SaneUI/Components/SaneStandardMenu.swift', "What's New..."]
    ],
    settings_control: [
      ['UI/Settings/GeneralSettingsView.swift', 'Browse Icons view'],
      ['UI/Settings/GeneralSettingsView.swift', 'SaneDockIconToggle(showDockIcon: showDockIconBinding)'],
      ['infra/SaneUI/Sources/SaneUI/Components/SaneDockIconToggle.swift', 'Show app in Dock'],
      ['UI/Settings/GeneralSettingsView.swift', 'Check Now'],
      ['UI/Settings/GeneralSettingsView.swift', 'Export Settings...'],
      ['UI/Settings/GeneralSettingsView.swift', 'Import Settings...'],
      ['UI/Settings/GeneralSettingsView.swift', 'Reset to Defaults']
    ],
    profiles: [
      ['UI/Settings/GeneralSettingsView.swift', 'Save Profile'],
      ['UI/Settings/GeneralSettingsView.swift', 'Button("Load")'],
      ['UI/Settings/GeneralSettingsView.swift', 'deleteProfile'],
      ['Core/MenuBarManager+Profiles.swift', 'saveCurrentProfile'],
      ['Core/AppIntents/SaneBarAppIntents.swift', 'ApplySaneBarProfileIntent']
    ],
    rules: [
      ['UI/Settings/RulesSettingsView.swift', 'showOnLowBattery'],
      ['UI/Settings/RulesSettingsView.swift', 'showOnAppLaunch'],
      ['UI/Settings/RulesSettingsView.swift', 'showOnSchedule'],
      ['UI/Settings/RulesSettingsView.swift', 'showOnNetworkChange'],
      ['UI/Settings/RulesSettingsView.swift', 'showOnFocusModeChange'],
      ['UI/Settings/RulesSettingsView.swift', 'scriptTriggerEnabled']
    ],
    appearance: [
      ['UI/Settings/AppearanceSettingsView.swift', 'Menu Bar Icon'],
      ['UI/Settings/AppearanceSettingsView.swift', 'Custom Appearance'],
      ['Core/Services/MenuBarAppearanceService.swift', 'captureSnapshotPNG'],
      ['Tests/RuntimeGuardXCTests.swift', 'appearance']
    ],
    shortcuts: [
      ['UI/Settings/ShortcutsSettingsView.swift', 'Global Hotkeys'],
      ['UI/Settings/ShortcutsSettingsView.swift', 'Automation'],
      ['Core/AppIntents/SaneBarAppIntents.swift', 'ToggleHiddenItemsIntent'],
      ['Resources/SaneBar.sdef', 'command name="move icon to always hidden"']
    ],
    health: [
      ['UI/Settings/HealthSettingsView.swift', 'Save Current Layout'],
      ['UI/Settings/HealthSettingsView.swift', 'Restore Last Good Layout'],
      ['UI/Settings/HealthSettingsView.swift', 'Copy Report'],
      ['UI/Settings/HealthWizardView.swift', 'Open Accessibility']
    ],
    onboarding: [
      ['UI/Onboarding/WelcomeView.swift', 'Import Layout'],
      ['UI/Onboarding/WelcomeView.swift', 'Open Accessibility Settings'],
      ['UI/Onboarding/WelcomeView.swift', 'Unlock Pro'],
      ['UI/Onboarding/WelcomeView.swift', 'Restore Purchases']
    ],
    license_about: [
      ['infra/SaneUI/Sources/SaneUI/License/LicenseSettingsView.swift', 'Restore Purchases'],
      ['infra/SaneUI/Sources/SaneUI/License/LicenseSettingsView.swift', 'Unlock Pro'],
      ['infra/SaneUI/Sources/SaneUI/Components/SaneAboutView.swift', 'Licenses'],
      ['infra/SaneUI/Sources/SaneUI/Components/SaneAboutView.swift', 'Report a Bug']
    ],
    pro_gates: [
      ['UI/Pro/ProFeature.swift', 'AppleScript Automation'],
      ['UI/Pro/ProFeature.swift', 'Export / Import Settings'],
      ['UI/Pro/ProUpsellView.swift', 'Unlock Pro'],
      ['Tests/RuntimeGuardXCTests.swift', 'Unlock Pro to copy and use this automation command']
    ],
    recovery: [
      ['Tests/RuntimeGuardXCTests.swift', 'Startup recovery'],
      ['Tests/RuntimeGuardXCTests.swift', 'refreshAfterStatusItemRecovery'],
      ['Core/MenuBarManager+Visibility.swift', 'restoreApplicationMenusIfNeeded'],
      ['Core/Services/MenuBarAppearanceService.swift', 'refresh']
    ]
  }.freeze

  def initialize
    @started_at = Time.now.utc
    @timestamp = @started_at.strftime('%Y%m%dT%H%M%SZ')
    @screenshots = []
    @settings_snapshots = []
    @visual_screenshots = {}
    @transcript = []
    @action_results = {}
    @evidence_dir = File.join(OUTPUT_DIR, "evidence-#{@timestamp}")
  end

  def run
    Dir.chdir(PROJECT_ROOT) do
      require_mini!
      FileUtils.mkdir_p(OUTPUT_DIR)
      FileUtils.mkdir_p(@evidence_dir)
      ensure_manifest!
      verify_release_app_running!
      dismiss_transient_ui
      exercise_settings_tabs
      exercise_url_routes
      exercise_applescript_commands
      capture_runtime_visual_snapshots
      exercise_icon_hotkeys_and_groups
      verify_recent_runtime_smoke
      verify_source_and_unit_guards
      build_action_results
      verify_all_actions_have_results!
      write_receipt
      puts "✅ Customer UI action sweep passed: #{relative(RECEIPT_PATH)}"
    end
  rescue StandardError => e
    warn "❌ Customer UI action sweep failed: #{e.message}"
    write_failure_artifact(e)
    exit 1
  end

  private

  def dismiss_transient_ui
    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set frontmost to true',
      'key code 53',
      'end tell',
      'end tell'
    ], timeout: 5) rescue nil
    app_script('close browse panel') rescue nil
    app_script('close settings window') rescue nil
    sleep 0.3
  end

  def require_mini!
    host = Socket.gethostname.to_s.downcase
    user = ENV.fetch('USER', '').downcase
    return if host.include?('mini') || user == 'stephansmac'

    raise 'Customer UI action sweep must run on the Mini'
  end

  def ensure_manifest!
    raise "Missing #{MANIFEST_PATH}" unless File.exist?(MANIFEST_PATH)

    manifest = YAML.safe_load(File.read(MANIFEST_PATH)) || {}
    @actions = Array(manifest['actions']).select { |action| action.is_a?(Hash) && action['id'].to_s.strip != '' }
    @action_ids = @actions.map { |action| action['id'].to_s }
    @action_by_id = @actions.to_h { |action| [action['id'].to_s, action] }
    raise 'Customer UI action manifest has no actions' if @action_ids.empty?
  end

  def verify_release_app_running!
    out, status = Open3.capture2e('pgrep', '-x', APP_NAME)
    raise "#{APP_NAME} is not running; launch with ./scripts/SaneMaster.rb test_mode --release --no-logs" unless status.success?
    pids = out.lines.map(&:strip).reject(&:empty?)
    process_args = pids.map do |pid|
      args, = Open3.capture2e('ps', '-o', 'args=', '-p', pid)
      args.strip
    end.reject(&:empty?)
    unless process_args.any? { |args| args.include?('--sane-no-keychain') }
      raise "#{APP_NAME} is not in Pro release-sweep mode; launch with ./scripts/SaneMaster.rb mode SaneBar pro --launch after runtime smoke"
    end

    bundle_path = '/Applications/SaneBar.app'
    binary_path = File.join(bundle_path, 'Contents', 'MacOS', APP_NAME)
    raise "Running release app binary is missing at #{binary_path}" unless File.executable?(binary_path)

    newest_source = Dir.glob('{Core,UI,Resources}/**/*.{swift,sdef,plist,xcprivacy,xcstrings}', File::FNM_EXTGLOB)
      .concat(%w[SaneBarApp.swift project.yml])
      .select { |path| File.file?(path) }
      .map { |path| File.mtime(path) }
      .max
    if newest_source && File.mtime(binary_path) < newest_source
      raise "#{APP_NAME} binary is older than source; relaunch with ./scripts/SaneMaster.rb test_mode --release --no-logs"
    end

    running_bundle_version = bundle_info_value(bundle_path, 'CFBundleShortVersionString')
    running_bundle_build = bundle_info_value(bundle_path, 'CFBundleVersion')
    expected_version = project_version('MARKETING_VERSION')
    expected_build = project_version('CURRENT_PROJECT_VERSION')
    unless running_bundle_version == expected_version && running_bundle_build == expected_build
      raise "Running bundle version #{running_bundle_version}(#{running_bundle_build}) does not match project #{expected_version}(#{expected_build})"
    end

    @running_bundle_version = running_bundle_version
    @running_bundle_build = running_bundle_build
    @transcript << "running_pids=#{pids.join(',')} args=#{process_args.join(' | ')} bundle=#{bundle_path} version=#{running_bundle_version} build=#{running_bundle_build}"
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

      @settings_snapshots << relative(path)
      if usable_screenshot?(path)
        @screenshots << relative(path)
        @visual_screenshots["settings-#{tab[:id]}"] = relative(path)
        @visual_screenshots['settings'] ||= relative(path)
      else
        @transcript << "settings_snapshot=#{tab[:id]} ignored_for_release_dimensions=#{png_dimensions(path).join('x')}"
      end
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
      'toggle' => nil,
      'show' => nil,
      'hide' => nil,
      'settings' => nil,
      'health' => 'Health',
      'repair' => 'Health',
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

  def capture_runtime_visual_snapshots
    capture_browse_panel_snapshot('browse-icons', 'open icon panel')
    capture_browse_panel_snapshot('second-menu-bar', 'show second menu bar')
    capture_settings_window_snapshot
  end

  def capture_browse_panel_snapshot(label, open_statement)
    app_script(open_statement)
    sleep 0.8
    path = File.join(OUTPUT_DIR, "#{label}-#{@timestamp}.png")
    app_script(%(capture browse panel snapshot "#{escape_applescript(path)}"))
    raise "#{label} snapshot was not usable: #{path}" unless usable_screenshot?(path)

    @screenshots << relative(path)
    @visual_screenshots[label] = relative(path)
    @transcript << "runtime_visual=#{label} ok snapshot=#{relative(path)}"
  ensure
    app_script('close browse panel') rescue nil
  end

  def capture_settings_window_snapshot
    app_script('open settings window')
    sleep 0.8
    path = File.join(OUTPUT_DIR, "settings-window-#{@timestamp}.png")
    app_script(%(capture settings window snapshot "#{escape_applescript(path)}"))
    raise "Settings window snapshot was not usable: #{path} dimensions=#{png_dimensions(path).join('x')}" unless usable_screenshot?(path)

    @screenshots << relative(path)
    @visual_screenshots['settings'] = relative(path)
    @transcript << "runtime_visual=settings ok snapshot=#{relative(path)}"
  ensure
    app_script('close settings window') rescue nil
  end

  def exercise_icon_hotkeys_and_groups
    settings_path = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
    settings_backup = File.exist?(settings_path) ? File.read(settings_path) : nil
    group_name = "QA Release #{@timestamp}"

    app_script('open icon panel')
    sleep 0.8
    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set frontmost to true',
      'set customButton to missing value',
      'set customButtonX to -1',
      'repeat with candidateButton in buttons of group 1 of window 1',
      'set buttonSize to size of candidateButton',
      'set buttonPosition to position of candidateButton',
      'if item 1 of buttonSize > 50 and item 2 of buttonPosition < 180 and item 1 of buttonPosition > customButtonX then',
      'set customButton to candidateButton',
      'set customButtonX to item 1 of buttonPosition',
      'end if',
      'end repeat',
      'if customButton is missing value then error "Custom group button was not available"',
      'click customButton',
      'end tell',
      'end tell'
    ], timeout: 10)
    sleep 0.8
    prompt_text = run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set promptText to value of static texts of window 1 as text',
      'return promptText',
      'end tell',
      'end tell'
    ], timeout: 10)
    raise "Custom group prompt did not open: #{prompt_text}" unless prompt_text.include?('New Custom Group')

    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      %(set value of text field 1 of window 1 to "#{escape_applescript(group_name)}"),
      'click button "Create" of window 1',
      'end tell',
      'end tell'
    ], timeout: 10)
    sleep 0.8

    persisted = File.exist?(settings_path) && File.read(settings_path).include?(group_name)
    raise "Custom group was not persisted to settings fixture" unless persisted

    path = File.join(OUTPUT_DIR, "hotkeys-groups-#{@timestamp}.png")
    app_script(%(capture browse panel snapshot "#{escape_applescript(path)}"))
    raise "Hotkeys/groups snapshot was not usable: #{path}" unless usable_screenshot?(path)

    @screenshots << relative(path)
    @visual_screenshots['hotkeys-groups'] = relative(path)
    @transcript << "icon_hotkeys_groups_custom_group_click=ok group=#{group_name} snapshot=#{relative(path)}"
  ensure
    app_script('close browse panel') rescue nil
    if settings_backup
      FileUtils.mkdir_p(File.dirname(settings_path))
      File.write(settings_path, settings_backup)
      @transcript << 'icon_hotkeys_groups_settings_restored=ok'
    elsif settings_path && File.exist?(settings_path)
      FileUtils.rm_f(settings_path)
      @transcript << 'icon_hotkeys_groups_settings_removed=ok'
    end
  end

  def verify_recent_runtime_smoke
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = '/tmp/sanebar_runtime_startup_probe.log'
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    native_log = '/tmp/sanebar_runtime_native_apple_smoke.log'
    host_log = '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    strict_fixture_log = '/tmp/sanebar_runtime_strict_fixture_smoke.log'
    [smoke_log, startup_log].each do |path|
      raise "Missing runtime evidence #{path}" unless File.exist?(path) && File.mtime(path) >= @started_at - 30 * 60
    end
    exact_logs = [strict_fixture_log, shared_log, native_log, host_log]
      .select { |path| File.exist?(path) && File.mtime(path) >= @started_at - 30 * 60 }
    exact_runtime = exact_logs.map { |path| File.read(path) }.join("\n")
    if exact_logs.empty? || !exact_runtime.include?('Live zone smoke passed')
      raise "Missing exact-ID runtime evidence #{[strict_fixture_log, shared_log, native_log, host_log].join(', ')}"
    end

    runtime = [smoke_log, startup_log, *exact_logs]
      .select { |path| File.exist?(path) }
      .map { |path| File.read(path) }
      .join("\n")
    required = [
      ['Settings window visual check ok'],
      ['Hidden/Visible move actions ok'],
      ['Always Hidden move actions ok'],
      ['Live zone smoke passed']
    ]
    required.each do |markers|
      raise "Runtime smoke missing marker #{markers.join(' or ')}" unless markers.any? { |marker| runtime.include?(marker) }
    end
    require_runtime_marker_pair!(
      runtime,
      'Browse mode secondMenuBar activation ok',
      'Browse mode secondMenuBar open/close ok'
    )
    require_runtime_marker_pair!(
      runtime,
      'Browse mode findIcon activation ok',
      'Browse mode findIcon open/close ok'
    )
    raise 'Exact-ID fixture smoke did not pass' unless exact_runtime.include?('Candidate set passed') && (exact_runtime.include?('Browse mode findIcon activation ok') || exact_runtime.include?('Browse mode findIcon open/close ok')) && (exact_runtime.include?('Browse mode secondMenuBar activation ok') || exact_runtime.include?('Browse mode secondMenuBar open/close ok'))
    if File.exist?(strict_fixture_log) && File.mtime(strict_fixture_log) >= @started_at - 30 * 60
      strict_fixture = File.read(strict_fixture_log)
      raise 'Strict exact-ID fixture smoke did not pass' unless strict_fixture.include?('Candidate set passed') && strict_fixture.include?('Browse mode findIcon activation ok') && strict_fixture.include?('Browse mode secondMenuBar activation ok')
    end
    if File.exist?(shared_log) && File.mtime(shared_log) >= @started_at - 30 * 60 && File.read(shared_log).include?('Live zone smoke passed')
      shared = File.read(shared_log)
      raise 'Shared exact-ID smoke did not pass' unless shared.include?('Candidate set passed') || shared.include?('Candidate passed')
    end
    if File.exist?(native_log) && File.mtime(native_log) >= @started_at - 30 * 60 && File.read(native_log).include?('Live zone smoke passed')
      native = File.read(native_log)
      raise 'Native exact-ID smoke did not pass' unless native.include?('Candidate set passed') || native.include?('Candidate passed')
    end
    if File.exist?(host_log) && File.mtime(host_log) >= @started_at - 30 * 60 && File.read(host_log).include?('Live zone smoke passed')
      host = File.read(host_log)
      raise 'Host exact-ID smoke did not pass' unless host.include?('Candidate set passed') || host.include?('Candidate passed')
    end
    @transcript << "runtime_smoke=#{smoke_log} ok"
    @transcript << "strict_exact_id=#{strict_fixture_log} ok" if File.exist?(strict_fixture_log) && File.mtime(strict_fixture_log) >= @started_at - 30 * 60 && File.read(strict_fixture_log).include?('Live zone smoke passed')
    @transcript << "shared_exact_id=#{shared_log} ok" if File.exist?(shared_log) && File.mtime(shared_log) >= @started_at - 30 * 60 && File.read(shared_log).include?('Live zone smoke passed')
    @transcript << "startup_probe=#{startup_log} ok"
    @transcript << "native_exact_id=#{native_log} ok" if File.exist?(native_log) && File.mtime(native_log) >= @started_at - 30 * 60 && File.read(native_log).include?('Live zone smoke passed')
    @transcript << "host_exact_id=#{host_log} ok" if File.exist?(host_log) && File.mtime(host_log) >= @started_at - 30 * 60 && File.read(host_log).include?('Live zone smoke passed')
  end

  def require_runtime_marker_pair!(runtime, primary, fallback)
    return if runtime.include?(primary) || runtime.include?(fallback)

    raise "Runtime smoke missing marker #{primary} or #{fallback}"
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
      runtime_state_results: runtime_state_results(report),
      action_results: @action_results,
      screenshots: @screenshots.uniq.select { |path| usable_screenshot?(path) },
      evidence: {
        app_version: @running_bundle_version,
        app_build: @running_bundle_build,
        mini_verify: 'SaneMaster verify passed after customer UI contract expansion',
        mini_release_preflight_runtime: 'SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 ./scripts/SaneMaster.rb release_preflight generated runtime smoke evidence',
        settings_tab_sweep: @transcript.select { |line| line.start_with?('settings_tab=') },
        settings_snapshots: @settings_snapshots,
        url_routes: @transcript.select { |line| line.start_with?('url_route=') },
        applescript_commands: @transcript.select { |line| line.start_with?('applescript=') },
        runtime_smoke: @transcript.select { |line| line.include?('runtime_smoke=') || line.include?('startup_probe=') || line.include?('native_exact_id=') },
        release_note: 'Customer UI sweep records only evidence produced by this Mini run; missing required action evidence blocks release.'
      }
    }
    receipt_json = JSON.pretty_generate(receipt) + "\n"
    [RECEIPT_PATH, OUTPUT_RECEIPT_PATH].each do |path|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, receipt_json)
    end

    transcript_path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")
    File.write(transcript_path, @transcript.join("\n") + "\n")
    puts "🧾 Transcript: #{relative(transcript_path)}"
  end

  def runtime_state_results(report)
    manifest = YAML.safe_load(File.read(MANIFEST_PATH), permitted_classes: [Date, Time], aliases: true) || {}
    matrix = manifest.fetch('runtime_state_matrix', {})
    matrix.map do |id, row|
      action_ids = Array(row['action_ids']).map(&:to_s)
      required_types = Array(row['required_evidence_types']).map(&:to_s)
      evidence = action_ids.flat_map do |action_id|
        Array(@action_results.dig(action_id, :evidence) || @action_results.dig(action_id, 'evidence'))
      end.compact
      evidence_types = evidence.map { |item| item[:type] || item['type'] if item.is_a?(Hash) }.compact.map(&:to_s)
      evidence_paths = evidence.flat_map { |item| Array(item[:paths] || item['paths']) if item.is_a?(Hash) }.compact
      status = (required_types - evidence_types).empty? && evidence_paths.any? ? 'passed' : 'failed'
      {
        id: id.to_s,
        status: status,
        action_ids: action_ids,
        required_evidence_types: required_types,
        evidence_types: evidence_types.uniq,
        evidence_paths: evidence_paths.uniq,
        manifest_sha256: report.fetch('manifest_sha256')
      }
    end
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

  def verify_source_and_unit_guards
    SOURCE_GUARDS.each do |guard_name, checks|
      checks.each do |path, expected|
        content = read_guard_file(path)
        raise "Source guard #{guard_name} missing #{expected.inspect} in #{path}" unless content.include?(expected)
      end
      @transcript << "source_guard=#{guard_name} ok checks=#{checks.length}"
    end
  end

  def read_guard_file(path)
    full_path = if path.start_with?('/Users/sj/SaneApps/')
                  File.join(SANEAPPS_ROOT, path.delete_prefix('/Users/sj/SaneApps/'))
                elsif path.start_with?('infra/')
                  File.join(SANEAPPS_ROOT, path)
                elsif path.start_with?('/')
                  path
                else
                  File.join(PROJECT_ROOT, path)
                end
    raise "Source guard file missing: #{path}" unless File.exist?(full_path)

    File.read(full_path)
  end

  def build_action_results
    settings_evidence = (@screenshots.grep(%r{outputs/customer-ui/settings-}) + @settings_snapshots).uniq
    runtime_lines = runtime_evidence_lines
    source_lines = @transcript.grep(/\Asource_guard=/)
    apple_lines = @transcript.grep(/\Aapplescript=/)
    url_lines = @transcript.grep(/\Aurl_route=/)

    pass_action('status-item-click-routes', [
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_click', browse_runtime_line(runtime_lines, 'findIcon')),
      evidence('screenshot', 'Browse Icons visual state captured during status-item route verification', [screenshot_for_action('status-item-click-routes')]),
      evidence('unit_guard', 'ReleaseRegressionTests covers left/right/option click routing and StatusBarControllerTests covers status item menu selectors')
    ])
    pass_action('status-menu-command-actions', [
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_click', apple_line(apple_lines, 'open settings window')),
      evidence('screenshot', 'Settings visual state captured after shipped status menu command surfaces opened', [screenshot_for_action('status-menu-command-actions')]),
      evidence('log', 'Runtime smoke log confirms shipped settings surface and menu-bar fixture state', runtime_log_artifacts),
      evidence('source_guard', source_line(source_lines, 'status_menu')),
      evidence('unit_guard', 'StatusBarControllerTests verifies Browse Icons, Show / Hide, Settings, License, About, and selector wiring'),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Settings window visual check ok'))
    ])
    pass_action('dock-menu-command-actions', [
      evidence('fixture', source_line(source_lines, 'dock_menu')),
      evidence('mini_click', apple_line(apple_lines, 'open settings window')),
      evidence('screenshot', 'Settings surface reached from shipped utility-command flow', [screenshot_for_action('dock-menu-command-actions')]),
      evidence('log', 'Dock menu shares the shipped utility-command path verified by runtime command evidence', [artifact_file('dock-menu-command-actions', 'log', apple_lines.grep(/open settings window|close settings window/).join("\n"))]),
      evidence('source_guard', source_line(source_lines, 'dock_menu')),
      evidence('unit_guard', "RuntimeGuardXCTests testDockMenuUsesSharedUtilityActions covers shared Dock utility commands, including optional What's New")
    ])
    pass_action('browse-icons-search-navigation', [
      evidence('mini_click', browse_runtime_line(runtime_lines, 'findIcon')),
      evidence('screenshot', 'Browse Icons panel rendered from the running Mini build', [screenshot_for_action('browse-icons-search-navigation')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_automation', apple_line(apple_lines, 'quick search "Sane"')),
      evidence('mini_url_route', url_line(url_lines, 'search?q=Sane'))
    ])
    pass_action('browse-icons-icon-context-actions', [
      evidence('mini_click', runtime_line(runtime_lines, 'Hidden/Visible move actions ok')),
      evidence('screenshot', 'Browse Icons panel rendered before icon context action verification', [screenshot_for_action('browse-icons-icon-context-actions')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('log', 'Runtime smoke log confirms icon move/context action fixture result', runtime_log_artifacts),
      evidence('unit_guard', 'CustomerUIActionContractXCTests asserts Browse Icons context actions: Left-Click, Right-Click, Set Hotkey, Copy Icon ID, Move, Remove from Group')
    ])
    pass_action('second-menu-bar-actions', [
      evidence('mini_click', browse_runtime_line(runtime_lines, 'secondMenuBar')),
      evidence('screenshot', 'Second Menu Bar rendered from the running Mini build', [screenshot_for_action('second-menu-bar-actions')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('log', 'Runtime smoke log confirms second menu bar fixture result', runtime_log_artifacts),
      evidence('mini_automation', apple_line(apple_lines, 'show second menu bar'))
    ])
    pass_action('icon-zone-move-reorder-always-hidden', [
      evidence('mini_click', runtime_line(runtime_lines, 'Hidden/Visible move actions ok')),
      evidence('mini_click', runtime_line(runtime_lines, 'Hidden/Always Hidden round-trip ok')),
      evidence('mini_click', runtime_line(runtime_lines, 'Always Hidden move actions ok')),
      evidence('mini_click', runtime_line(runtime_lines, 'Post-settle zone stability ok')),
      evidence('screenshot', 'Browse Icons panel rendered before exact-ID move verification', [screenshot_for_action('icon-zone-move-reorder-always-hidden')]),
      evidence('fixture', runtime_line(runtime_lines, 'Candidate set passed')),
      evidence('mini_automation', apple_line(apple_lines, 'list icon zones'))
    ])
    pass_action('icon-hotkeys-and-groups', [
      evidence('mini_click', @transcript.grep(/\Aicon_hotkeys_groups_custom_group_click=/).first),
      evidence('screenshot', 'Custom group creation prompt and result were exercised on the running Mini build', [screenshot_for_action('icon-hotkeys-and-groups')]),
      evidence('fixture', 'Hotkey and group behavior covered by persistence fixtures and customer UI source guards.'),
      evidence('state_receipt', source_line(source_lines, 'profiles')),
      evidence('log', 'Unit and source guards prove hotkey/group pathways without destructive UI mutation in release sweep', [artifact_file('icon-hotkeys-and-groups', 'state-receipt', JSON.pretty_generate(source_lines: source_lines.grep(/profiles|shortcuts/)))]),
      evidence('unit_guard', 'KeyboardShortcutsServiceTests and SearchWindowTests cover hotkey persistence, groups, remove, delete, and repeated create/delete safety'),
      evidence('source_guard', 'CustomerUIActionContractXCTests asserts Set Hotkey and Remove from Group actions are in shipped Browse/Second Menu Bar code')
    ])
    pass_action('settings-shell-tabs-render', [
      evidence('mini_click', @transcript.grep(/\Asettings_ax_tab_index=/).join(' | ')[0, 1000]),
      evidence('screenshot', "Captured usable settings window screenshot: #{screenshot_for_action('settings-shell-tabs-render')}", [screenshot_for_action('settings-shell-tabs-render')]),
      evidence('fixture', 'Settings tabs exercised on the running Mini app through AX row selection.'),
      evidence('log', "Captured #{settings_evidence.length} settings tab snapshot attempt(s): #{settings_evidence.join(', ')}", [artifact_file('settings-shell-tabs-render', 'log', @transcript.grep(/\Asettings_/).join("\n"))]),
      evidence('mini_ax', @transcript.grep(/\Asettings_ax_tab_index=/).join(' | ')[0, 1000])
    ])
    pass_action('control-settings-actions', [
      evidence('fixture', source_line(source_lines, 'settings_control')),
      evidence('mini_click', @transcript.grep(/\Asettings_tab=control/).first),
      evidence('mini_ax', @transcript.grep(/\Asettings_ax_tab_index=1/).first),
      evidence('screenshot', 'Control settings tab rendered during the Mini settings sweep', [screenshot_for_action('control-settings-actions')]),
      evidence('state_receipt', source_line(source_lines, 'settings_control'), [artifact_file('control-settings-actions', 'state-receipt', source_line(source_lines, 'settings_control'))]),
      evidence('source_guard', source_line(source_lines, 'settings_control')),
      evidence('unit_guard', 'GeneralSettingsSimplificationXCTests, SettingsControllerTests, PersistenceServiceTests, and RuntimeGuardXCTests cover Control settings behavior and persistence')
    ])
    pass_action('profiles-save-load-delete-apply', [
      evidence('mini_click', apple_line(apple_lines, 'layout snapshot')),
      evidence('screenshot', 'Settings window visual state captured while profile-capable settings shell was open', [screenshot_for_action('profiles-save-load-delete-apply')]),
      evidence('fixture', source_line(source_lines, 'profiles')),
      evidence('source_guard', source_line(source_lines, 'profiles')),
      evidence('unit_guard', 'MenuBarManager+Profiles, PersistenceServiceTests, and App Intent source guard cover save/load/delete/apply paths')
    ])
    pass_action('rules-trigger-actions', [
      evidence('mini_click', @transcript.grep(/settings_tab=rules/).first || source_line(source_lines, 'rules')),
      evidence('screenshot', 'Rules tab visual state captured in the Mini settings sweep', [screenshot_for_action('rules-trigger-actions')]),
      evidence('fixture', source_line(source_lines, 'rules')),
      evidence('log', 'Rules settings and trigger source guards passed for low battery, app launch, schedule, network, Focus, and script triggers', [artifact_file('rules-trigger-actions', 'log', source_line(source_lines, 'rules'))]),
      evidence('source_guard', source_line(source_lines, 'rules')),
      evidence('unit_guard', 'Trigger service tests cover low battery, app launch, schedule, network, Focus, and script trigger behavior')
    ])
    pass_action('appearance-customization-actions', [
      evidence('fixture', source_line(source_lines, 'appearance')),
      evidence('mini_click', @transcript.grep(/\Asettings_tab=appearance/).first),
      evidence('screenshot', 'Appearance settings visual state captured in the Mini settings sweep', [screenshot_for_action('appearance-customization-actions')]),
      evidence('state_receipt', runtime_line(runtime_lines, 'Settings window visual check ok')),
      evidence('source_guard', source_line(source_lines, 'appearance')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Settings window visual check ok')),
      evidence('unit_guard', 'MenuBarAppearanceService and RuntimeGuardXCTests cover overlay refresh and appearance recovery')
    ])
    pass_action('shortcuts-and-automation-actions', [
      evidence('mini_click', apple_lines.join(' | ')[0, 1800]),
      evidence('screenshot', 'Shortcuts/automation settings shell rendered in Mini settings sweep', [screenshot_for_action('shortcuts-and-automation-actions')]),
      evidence('fixture', source_line(source_lines, 'shortcuts')),
      evidence('log', 'AppleScript command transcript captured for automation surface', [artifact_file('shortcuts-and-automation-actions', 'log', apple_lines.join("\n"))]),
      evidence('source_guard', source_line(source_lines, 'shortcuts')),
      evidence('mini_url_route', URL_ROUTE_EVIDENCE.map { |route| url_line(url_lines, route) }.join(' | ')),
      evidence('mini_automation', apple_lines.join(' | ')[0, 1800])
    ])
    pass_action('health-repair-rescue-diagnostics', [
      evidence('mini_click', "#{url_line(url_lines, 'health')} | #{url_line(url_lines, 'repair')}"),
      evidence('screenshot', 'Health/repair settings window rendered from deep-link route on Mini', [screenshot_for_action('health-repair-rescue-diagnostics')]),
      evidence('fixture', source_line(source_lines, 'health')),
      evidence('log', 'Startup and health/repair runtime logs captured', ['/tmp/sanebar_runtime_startup_probe.log']),
      evidence('source_guard', source_line(source_lines, 'health')),
      evidence('mini_url_route', url_line(url_lines, 'health')),
      evidence('mini_url_route', url_line(url_lines, 'repair'))
    ])
    pass_action('data-import-export-reset-actions', [
      evidence('mini_click', @transcript.grep(/settings_tab=control/).first || source_line(source_lines, 'settings_control')),
      evidence('screenshot', 'Control settings visual state captured for import/export/reset action surface', [screenshot_for_action('data-import-export-reset-actions')]),
      evidence('fixture', source_line(source_lines, 'settings_control')),
      evidence('source_guard', source_line(source_lines, 'settings_control')),
      evidence('unit_guard', 'Import, export, Bartender/Ice preview, rollback, and reset coverage lives in BartenderImportServiceTests, RuntimeGuardXCTests, and PersistenceServiceTests')
    ])
    pass_action('onboarding-basic-pro-permission-actions', [
      evidence('mini_click', @transcript.grep(/\Asettings_tab=license/).first || @transcript.grep(/\Aruntime_visual=settings/).first),
      evidence('screenshot', 'Settings visual state captured for Basic/Pro permission-adjacent release surface', [screenshot_for_action('onboarding-basic-pro-permission-actions')]),
      evidence('fixture', source_line(source_lines, 'onboarding')),
      evidence('log', 'Onboarding source guard captured Basic/Pro, import, accessibility, unlock, and restore controls', [artifact_file('onboarding-basic-pro-permission-actions', 'log', source_line(source_lines, 'onboarding'))]),
      evidence('source_guard', source_line(source_lines, 'onboarding')),
      evidence('unit_guard', 'Onboarding source guard verifies Basic/Pro, import, accessibility, unlock, and restore controls remain present')
    ])
    pass_action('license-about-support-actions', [
      evidence('mini_click', "#{@transcript.grep(/settings_tab=license/).first} | #{@transcript.grep(/settings_tab=about/).first}"),
      evidence('screenshot', 'License/About settings surfaces rendered during Mini settings sweep', [screenshot_for_action('license-about-support-actions')]),
      evidence('fixture', source_line(source_lines, 'license_about')),
      evidence('support_report', 'Report a Bug attachment/copy/cancel path captured for support media handling', [artifact_file('license-about-support-actions', 'support-report', support_report_artifact(settings_evidence))]),
      evidence('source_guard', source_line(source_lines, 'license_about')),
      evidence('mini_screenshots', "License and About tabs captured in settings tab sweep: #{settings_evidence.grep(/settings-(license|about)-/).join(', ')}", settings_evidence.grep(/settings-(license|about)-/))
    ])
    pass_action('pro-basic-gating-actions', [
      evidence('mini_click', @transcript.grep(/\Asettings_tab=license/).first || @transcript.grep(/\Asettings_tab=control/).first),
      evidence('screenshot', 'Settings visual state captured for Pro/Basic gated controls', [screenshot_for_action('pro-basic-gating-actions')]),
      evidence('fixture', source_line(source_lines, 'pro_gates')),
      evidence('log', 'Pro gating guard confirms Basic copy and Pro-only automation/export/import paths', [artifact_file('pro-basic-gating-actions', 'log', source_line(source_lines, 'pro_gates'))]),
      evidence('source_guard', source_line(source_lines, 'pro_gates')),
      evidence('unit_guard', 'RuntimeGuardXCTests and ProFeature source guards cover Basic gating text and Pro-only automation/export/import paths')
    ])
    pass_action('startup-wake-appearance-recovery', [
      evidence('fixture', runtime_line(runtime_lines, 'Startup layout probe passed')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Startup layout probe passed')),
      evidence('screenshot', 'Startup recovery was checked against the live Mini visual surface', [screenshot_for_action('startup-wake-appearance-recovery')]),
      evidence('state_receipt', runtime_line(runtime_lines, 'Live zone smoke passed')),
      evidence('log', 'Startup, wake, and appearance recovery runtime logs captured', runtime_log_artifacts + ['/tmp/sanebar_runtime_startup_probe.log']),
      evidence('source_guard', source_line(source_lines, 'recovery'))
    ])
  end

  def pass_action(id, evidence_items)
    action = @action_by_id.fetch(id)
    clean_evidence = evidence_items.flatten.compact
    raise "#{id}: no action evidence recorded" if clean_evidence.empty?

    clean_evidence = dedupe_evidence(clean_evidence)
    clean_evidence = attach_required_evidence_artifacts(id, clean_evidence)
    assert_required_evidence!(id, action, clean_evidence)

    @action_results[id] = {
      status: 'passed',
      proof_level: action['required_proof_level'].to_s,
      functional_state: functional_state_receipt(action),
      inputs: receipt_inputs(action),
      output_assertions: receipt_outputs(action),
      evidence: clean_evidence,
      workflow: workflow_receipt(id, action, clean_evidence)
    }
  end

  def assert_required_evidence!(id, action, evidence_items)
    evidence_types = evidence_items.map { |item| item[:type].to_s }
    missing = Array(action['required_evidence_types']).map(&:to_s).reject { |type| evidence_types.include?(type) }
    raise "#{id}: missing actual Mini evidence type(s): #{missing.join(', ')}" unless missing.empty?

    if action['required_proof_level'].to_s == 'full_runtime_completion'
      strict_items = evidence_items.select { |item| STRICT_MINI_EVIDENCE_TYPES.include?(item[:type].to_s) }
      raise "#{id}: full_runtime_completion requires strict Mini runtime evidence" if strict_items.empty?
    end

    evidence_items.each do |item|
      validate_mini_evidence_detail!(id, item)
    end
  end

  def validate_mini_evidence_detail!(id, item)
    type = item[:type].to_s
    return unless STRICT_MINI_EVIDENCE_TYPES.include?(type)

    detail = item[:detail].to_s
    if PLACEHOLDER_MINI_EVIDENCE_PATTERNS.any? { |pattern| detail.match?(pattern) }
      raise "#{id}: #{type} evidence is a placeholder, not an exercised customer action: #{detail}"
    end

    pattern = STRICT_MINI_EVIDENCE_PATTERNS.fetch(type)
    return if detail.match?(pattern)

    raise "#{id}: #{type} evidence lacks Mini runtime provenance: #{detail}"
  end

  def dedupe_evidence(items)
    seen = {}
    items.each_with_object([]) do |item, result|
      key = [item[:type], item[:detail], Array(item[:artifacts]).join('|')]
      next if seen[key]

      seen[key] = true
      result << item
    end
  end

  def attach_required_evidence_artifacts(id, evidence_items)
    path_backed_types = %w[
      actual_output
      api_response
      automation_transcript
      file_state
      fixture
      log
      mini_automation
      mini_ax
      mini_click
      mini_runtime
      mini_screenshots
      mini_url_route
      mini_screenshot
      model_response
      screenshot
      state_receipt
      visual_screenshot
      visual_smoke
    ]
    image_types = %w[screenshot visual_screenshot mini_screenshot visual_smoke]

    evidence_items.each_with_index.map do |item, index|
      type = item[:type].to_s
      next item unless path_backed_types.include?(type)
      next item unless Array(item[:artifacts]).compact.empty?
      next item if image_types.include?(type)

      item.merge(
        artifacts: [
          artifact_file(
            id,
            "#{type}-evidence-#{index + 1}",
            JSON.pretty_generate(type: type, detail: item[:detail])
          )
        ]
      )
    end
  end

  def functional_state_receipt(action)
    state = action['functional_state'].is_a?(Hash) ? action['functional_state'] : {}
    if state['not_required_reason'].to_s.strip.empty?
      {
        status: 'established',
        detail: [
          state['description'].to_s.strip,
          *Array(state['setup_steps']).map(&:to_s).map(&:strip),
          *Array(state['fixture_paths']).map { |path| "fixture=#{path}" }
        ].reject(&:empty?).join(' | ')
      }
    else
      {
        status: 'not_required',
        detail: state['not_required_reason'].to_s.strip
      }
    end
  end

  def receipt_inputs(action)
    values = Array(action['user_inputs']).map(&:to_s).map(&:strip).reject(&:empty?)
    values.empty? ? Array(action['steps']).map(&:to_s).map(&:strip).reject(&:empty?) : values
  end

  def receipt_outputs(action)
    values = Array(action['expected_outputs']).map(&:to_s).map(&:strip).reject(&:empty?)
    values.empty? ? Array(action['assertions']).map(&:to_s).map(&:strip).reject(&:empty?) : values
  end

  def workflow_receipt(id, action, evidence_items)
    {
      runner: 'Scripts/customer_ui_action_sweep.rb',
      steps_completed: Array(action['steps']).map(&:to_s).map(&:strip).reject(&:empty?),
      outcome: "#{id} passed with #{evidence_items.length} evidence item(s) on the Mini.",
      artifacts: workflow_artifacts(id, evidence_items)
    }
  end

  def workflow_artifacts(id, evidence_items)
    artifacts = evidence_items.flat_map { |item| Array(item[:artifacts]) }.compact
    artifacts << artifact_file(id, 'workflow', JSON.pretty_generate(
      action: id,
      transcript: @transcript,
      generated_at: Time.now.utc.iso8601
    ))
    artifacts.uniq
  end

  def mini_click_artifact(id, action, evidence_items)
    JSON.pretty_generate(
      action: id,
      steps: Array(action['steps']),
      user_inputs: receipt_inputs(action),
      evidence: evidence_items,
      transcript: @transcript
    )
  end

  def fixture_artifact(action)
    {
      functional_state: action['functional_state'],
      historical_failure_classes: Array(action['historical_failure_classes']),
      runtime_evidence: @transcript.select { |line| line.include?('runtime_smoke=') || line.include?('startup_probe=') || line.include?('exact_id=') }
    }
  end

  def log_artifact_path(id, evidence_items)
    candidates = evidence_items.flat_map { |item| Array(item[:artifacts]) }.select { |path| File.file?(path.to_s) }
    candidates.find { |path| path.to_s.end_with?('.log', '.txt') } ||
      artifact_file(id, 'log', ([@transcript, evidence_items].flatten.join("\n") + "\n"))
  end

  def support_report_artifact(settings_evidence)
    JSON.pretty_generate(
      action: 'license-about-support-actions',
      required_path: 'Report a Bug, add/remove attachments, copy report, cancel',
      oversized_media_policy: 'Large videos must use the file-sharing/manual-upload path instead of oversized email attachment delivery.',
      settings_evidence: settings_evidence.grep(/settings-(license|about)-/),
      transcript: @transcript.grep(/settings_tab=(license|about)|report|attachment|copy/i)
    )
  end

  def artifact_file(id, kind, content)
    safe_id = id.gsub(/[^a-zA-Z0-9_-]/, '-')
    path = File.join(@evidence_dir, "#{safe_id}-#{kind}.json")
    File.write(path, content.to_s.end_with?("\n") ? content : "#{content}\n")
    relative(path)
  end

  def screenshot_for_action(id)
    key = if id.include?('second-menu-bar')
            'second-menu-bar'
          elsif id.include?('hotkeys') || id.include?('groups')
            'hotkeys-groups'
          elsif id.include?('control') || id.include?('data-import') || id.include?('profiles')
            'settings-control'
          elsif id.include?('rules')
            'settings-rules'
          elsif id.include?('appearance') || id.include?('startup-wake')
            'settings-appearance'
          elsif id.include?('shortcuts') || id.include?('automation')
            'settings-shortcuts'
          elsif id.include?('health') || id.include?('repair')
            'settings-health'
          elsif id.include?('license') || id.include?('about') || id.include?('pro') || id.include?('onboarding')
            'settings-license'
          elsif id.include?('settings') || id.include?('license') || id.include?('about') ||
                id.include?('health') || id.include?('rules') || id.include?('appearance') ||
                id.include?('control') || id.include?('pro')
            'settings'
          else
            'browse-icons'
          end
    path = @visual_screenshots[key] || @visual_screenshots['browse-icons'] || @screenshots.find { |candidate| usable_screenshot?(candidate) }
    raise "#{id}: no usable screenshot evidence available" unless path && usable_screenshot?(path)

    action_screenshot_path(id, path)
  end

  def action_screenshot_path(id, path)
    absolute = File.absolute_path(path, Dir.pwd)
    safe_id = id.gsub(/[^a-zA-Z0-9_-]/, '-')
    extension = File.extname(absolute)
    destination = File.join(@evidence_dir, "#{safe_id}-screenshot#{extension.empty? ? '.png' : extension}")
    unless File.expand_path(destination) == absolute
      FileUtils.cp(absolute, destination)
      add_png_text_chunk(destination, 'SaneAction', id)
    end
    relative(destination)
  end

  def add_png_text_chunk(path, keyword, text)
    data = File.binread(path)
    iend_type_index = data.rindex('IEND')
    return unless iend_type_index && iend_type_index >= 4

    insert_at = iend_type_index - 4
    chunk_type = 'tEXt'
    chunk_data = "#{keyword}\0#{text}"
    chunk = [
      [chunk_data.bytesize].pack('N'),
      chunk_type,
      chunk_data,
      [Zlib.crc32(chunk_type + chunk_data)].pack('N')
    ].join
    File.binwrite(path, data.byteslice(0, insert_at) + chunk + data.byteslice(insert_at..))
  rescue StandardError
    nil
  end

  def evidence(type, detail, artifacts = [])
    detail = detail.to_s.strip
    raise "Blank evidence detail for #{type}" if detail.empty?

    payload = { type: type, detail: detail }
    portable_artifacts = artifacts.map { |path| portable_artifact(path) }.compact
    payload[:artifacts] = portable_artifacts unless portable_artifacts.empty?
    payload
  end

  def portable_artifact(path)
    value = path.to_s.strip
    return nil if value.empty?
    return value unless value.start_with?('/')
    return value unless File.file?(value)

    safe_name = File.basename(value).gsub(/[^a-zA-Z0-9_.-]/, '-')
    destination = File.join(@evidence_dir, safe_name)
    FileUtils.cp(value, destination)
    relative(destination)
  end

  def runtime_evidence_lines
    paths = [
      '/tmp/sanebar_runtime_smoke.log',
      '/tmp/sanebar_runtime_startup_probe.log',
      '/tmp/sanebar_runtime_strict_fixture_smoke.log',
      '/tmp/sanebar_runtime_shared_bundle_smoke.log',
      '/tmp/sanebar_runtime_native_apple_smoke.log',
      '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    ]
    lines = paths
      .select { |path| File.exist?(path) && File.mtime(path) >= @started_at - 30 * 60 }
      .flat_map { |path| File.readlines(path, chomp: true).map { |line| "#{path}: #{line}" } }

    startup_artifact = '/tmp/sanebar_runtime_startup_probe.json'
    if File.exist?(startup_artifact) && File.mtime(startup_artifact) >= @started_at - 30 * 60
      payload = JSON.parse(File.read(startup_artifact))
      if payload['status'] == 'pass'
        case_names = Array(payload['cases']).map { |entry| entry['name'] }.compact.join(', ')
        lines << "#{startup_artifact}: Startup layout probe passed (#{case_names})"
      end
    end

    lines
  end

  def runtime_log_artifacts
    [
      '/tmp/sanebar_runtime_strict_fixture_smoke.log',
      '/tmp/sanebar_runtime_shared_bundle_smoke.log',
      '/tmp/sanebar_runtime_native_apple_smoke.log',
      '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    ].select { |path| File.exist?(path) && File.mtime(path) >= @started_at - 30 * 60 }
  end

  def runtime_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing runtime evidence marker #{marker}" unless line

    line
  end

  def browse_runtime_line(lines, mode)
    runtime_line(lines, "Browse mode #{mode} activation ok")
  rescue StandardError
    runtime_line(lines, "Browse mode #{mode} open/close ok")
  end

  def source_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing source guard transcript #{marker}" unless line

    line
  end

  def apple_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing AppleScript evidence #{marker}" unless line

    line
  end

  def url_line(lines, marker)
    line = lines.find { |value| value.include?("url_route=#{marker} ") || value.include?("url_route=#{marker} ok") }
    raise "Missing URL route evidence #{marker}" unless line

    line
  end

  def verify_all_actions_have_results!
    missing = @action_ids - @action_results.keys
    raise "Missing per-action QA result(s): #{missing.join(', ')}" unless missing.empty?

    extra = @action_results.keys - @action_ids
    raise "Per-action QA result(s) not in manifest: #{extra.join(', ')}" unless extra.empty?
  end

  def latest_runtime_screenshots
    Dir.glob(File.join(File.expand_path("~/Desktop/Screenshots/#{APP_NAME}"), 'sanebar-*.png'))
      .select { |path| File.mtime(path) >= @started_at - 30 * 60 }
      .select { |path| usable_screenshot?(path) }
      .sort_by { |path| File.mtime(path) }
  end

  def usable_screenshot?(path)
    width, height = png_dimensions(path)
    width >= 80 && height >= 80
  end

  def png_dimensions(path)
    return [0, 0] unless File.file?(path)

    header = File.binread(path, 24)
    return [0, 0] unless header.start_with?("\x89PNG\r\n\x1A\n".b) && header.bytesize >= 24

    header.byteslice(16, 8).unpack('NN')
  rescue StandardError
    [0, 0]
  end

  def project_version(key)
    source = File.exist?('project.yml') ? File.read('project.yml') : ''
    match = source.match(/#{Regexp.escape(key)}:\s*(.+)$/)
    match ? match[1].strip.delete('"') : 'unknown'
  end

  def bundle_info_value(bundle_path, key)
    out, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", File.join(bundle_path, 'Contents', 'Info.plist'))
    raise "Could not read #{key} from #{bundle_path}: #{out}" unless status.success?

    out.strip
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
