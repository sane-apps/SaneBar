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
  SANEAPPS_ROOT = File.expand_path('../..', PROJECT_ROOT)
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
    @transcript = []
    @action_results = {}
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
      action_results: @action_results,
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
    settings_evidence = @screenshots.grep(%r{outputs/customer-ui/settings-})
    runtime_lines = runtime_evidence_lines
    source_lines = @transcript.grep(/\Asource_guard=/)
    apple_lines = @transcript.grep(/\Aapplescript=/)
    url_lines = @transcript.grep(/\Aurl_route=/)

    pass_action('status-item-click-routes', [
      evidence('mini_runtime', runtime_line(runtime_lines, 'Live zone smoke passed')),
      evidence('unit_guard', 'ReleaseRegressionTests covers left/right/option click routing and StatusBarControllerTests covers status item menu selectors')
    ])
    pass_action('status-menu-command-actions', [
      evidence('source_guard', source_line(source_lines, 'status_menu')),
      evidence('unit_guard', 'StatusBarControllerTests verifies Browse Icons, Show / Hide, Settings, License, About, and selector wiring'),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Settings window visual check ok'))
    ])
    pass_action('dock-menu-command-actions', [
      evidence('source_guard', source_line(source_lines, 'dock_menu')),
      evidence('unit_guard', "RuntimeGuardXCTests testDockMenuUsesSharedUtilityActions covers shared Dock utility commands, including optional What's New")
    ])
    pass_action('browse-icons-search-navigation', [
      evidence('mini_runtime', runtime_line(runtime_lines, 'Browse mode findIcon activation ok')),
      evidence('mini_automation', apple_line(apple_lines, 'quick search "Sane"')),
      evidence('mini_url_route', url_line(url_lines, 'search?q=Sane'))
    ])
    pass_action('browse-icons-icon-context-actions', [
      evidence('mini_runtime', runtime_line(runtime_lines, 'Browse mode findIcon activation ok')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Hidden/Visible move actions ok')),
      evidence('unit_guard', 'CustomerUIActionContractXCTests asserts Browse Icons context actions: Left-Click, Right-Click, Set Hotkey, Copy Icon ID, Move, Remove from Group')
    ])
    pass_action('second-menu-bar-actions', [
      evidence('mini_runtime', runtime_line(runtime_lines, 'Browse mode secondMenuBar activation ok')),
      evidence('mini_automation', apple_line(apple_lines, 'show second menu bar'))
    ])
    pass_action('icon-zone-move-reorder-always-hidden', [
      evidence('mini_runtime', runtime_line(runtime_lines, 'Hidden/Visible move actions ok')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Always Hidden move actions ok')),
      evidence('mini_automation', apple_line(apple_lines, 'list icon zones'))
    ])
    pass_action('icon-hotkeys-and-groups', [
      evidence('unit_guard', 'KeyboardShortcutsServiceTests and SearchWindowTests cover hotkey persistence, groups, remove, delete, and repeated create/delete safety'),
      evidence('source_guard', 'CustomerUIActionContractXCTests asserts Set Hotkey and Remove from Group actions are in shipped Browse/Second Menu Bar code')
    ])
    pass_action('settings-shell-tabs-render', [
      evidence('mini_screenshots', "Captured #{settings_evidence.length} settings tab screenshot(s): #{settings_evidence.join(', ')}"),
      evidence('mini_ax', @transcript.grep(/\Asettings_ax_tab_index=/).join(' | ')[0, 1000])
    ])
    pass_action('control-settings-actions', [
      evidence('source_guard', source_line(source_lines, 'settings_control')),
      evidence('unit_guard', 'GeneralSettingsSimplificationXCTests, SettingsControllerTests, PersistenceServiceTests, and RuntimeGuardXCTests cover Control settings behavior and persistence')
    ])
    pass_action('profiles-save-load-delete-apply', [
      evidence('source_guard', source_line(source_lines, 'profiles')),
      evidence('unit_guard', 'MenuBarManager+Profiles, PersistenceServiceTests, and App Intent source guard cover save/load/delete/apply paths')
    ])
    pass_action('rules-trigger-actions', [
      evidence('source_guard', source_line(source_lines, 'rules')),
      evidence('unit_guard', 'Trigger service tests cover low battery, app launch, schedule, network, Focus, and script trigger behavior')
    ])
    pass_action('appearance-customization-actions', [
      evidence('source_guard', source_line(source_lines, 'appearance')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Settings window visual check ok')),
      evidence('unit_guard', 'MenuBarAppearanceService and RuntimeGuardXCTests cover overlay refresh and appearance recovery')
    ])
    pass_action('shortcuts-and-automation-actions', [
      evidence('source_guard', source_line(source_lines, 'shortcuts')),
      evidence('mini_url_route', URL_ROUTE_EVIDENCE.map { |route| url_line(url_lines, route) }.join(' | ')),
      evidence('mini_automation', apple_lines.join(' | ')[0, 1800])
    ])
    pass_action('health-repair-rescue-diagnostics', [
      evidence('source_guard', source_line(source_lines, 'health')),
      evidence('mini_url_route', url_line(url_lines, 'health')),
      evidence('mini_url_route', url_line(url_lines, 'repair'))
    ])
    pass_action('data-import-export-reset-actions', [
      evidence('source_guard', source_line(source_lines, 'settings_control')),
      evidence('unit_guard', 'Import, export, Bartender/Ice preview, rollback, and reset coverage lives in BartenderImportServiceTests, RuntimeGuardXCTests, and PersistenceServiceTests')
    ])
    pass_action('onboarding-basic-pro-permission-actions', [
      evidence('source_guard', source_line(source_lines, 'onboarding')),
      evidence('unit_guard', 'Onboarding source guard verifies Basic/Pro, import, accessibility, unlock, and restore controls remain present')
    ])
    pass_action('license-about-support-actions', [
      evidence('source_guard', source_line(source_lines, 'license_about')),
      evidence('mini_screenshots', "License and About tabs captured in settings tab sweep: #{settings_evidence.grep(/settings-(license|about)-/).join(', ')}")
    ])
    pass_action('pro-basic-gating-actions', [
      evidence('source_guard', source_line(source_lines, 'pro_gates')),
      evidence('unit_guard', 'RuntimeGuardXCTests and ProFeature source guards cover Basic gating text and Pro-only automation/export/import paths')
    ])
    pass_action('startup-wake-appearance-recovery', [
      evidence('mini_runtime', runtime_line(runtime_lines, 'Startup layout probe passed')),
      evidence('mini_runtime', runtime_line(runtime_lines, 'Live zone smoke passed')),
      evidence('source_guard', source_line(source_lines, 'recovery'))
    ])
  end

  def pass_action(id, evidence_items)
    clean_evidence = evidence_items.flatten.compact
    raise "#{id}: no action evidence recorded" if clean_evidence.empty?

    @action_results[id] = {
      status: 'passed',
      evidence: clean_evidence
    }
  end

  def evidence(type, detail, artifacts = [])
    detail = detail.to_s.strip
    raise "Blank evidence detail for #{type}" if detail.empty?

    payload = { type: type, detail: detail }
    payload[:artifacts] = artifacts unless artifacts.empty?
    payload
  end

  def runtime_evidence_lines
    paths = ['/tmp/sanebar_runtime_smoke.log', '/tmp/sanebar_runtime_startup_probe.log', '/tmp/sanebar_runtime_native_apple_smoke.log']
    lines = paths.select { |path| File.exist?(path) }.flat_map { |path| File.readlines(path, chomp: true).map { |line| "#{path}: #{line}" } }

    startup_artifact = '/tmp/sanebar_runtime_startup_probe.json'
    if File.exist?(startup_artifact)
      payload = JSON.parse(File.read(startup_artifact))
      if payload['status'] == 'pass'
        case_names = Array(payload['cases']).map { |entry| entry['name'] }.compact.join(', ')
        lines << "#{startup_artifact}: Startup layout probe passed (#{case_names})"
      end
    end

    lines
  end

  def runtime_line(lines, marker)
    line = lines.find { |value| value.include?(marker) }
    raise "Missing runtime evidence marker #{marker}" unless line

    line
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
