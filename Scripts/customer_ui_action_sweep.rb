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
    ['list authoritative icon zones', /\t/],
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

  HEALTH_WARNING_LABELS = [
    'Needs Action',
    'Needs Check',
    'Needs Repair',
    'Missing Items',
    'Hidden by macOS',
    'Detached'
  ].freeze

  STRICT_MINI_EVIDENCE_TYPES = %w[
    mini_click
    mini_automation
    mini_ax
    mini_url_route
    mini_runtime
  ].freeze

  SNAPSHOT_SUMMARY_FIELDS = %w[
    hidingState
    autoRehideEnabled
    rehideDelay
    autoRehideBlockReason
    isRevealPinned
    isMenuOpen
    isBrowseVisible
    isBrowseSessionActive
    isMoveInProgress
    hoverSuspended
    hoverMouseInMenuBar
    shouldSkipHideForExternalMonitor
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
      ['UI/Settings/GeneralSettingsBrowseSection.swift', 'CompactSection("Browse Icons")'],
      ['UI/Settings/GeneralSettingsBrowseSection.swift', 'Browse Icons view'],
      ['UI/Settings/GeneralSettingsView.swift', 'SaneDockIconToggle(showDockIcon: showDockIconBinding)'],
      ['infra/SaneUI/Sources/SaneUI/Components/SaneDockIconToggle.swift', 'Show app in Dock'],
      ['UI/Settings/GeneralSettingsView.swift', 'Check Now'],
      ['UI/Settings/GeneralSettingsView.swift', 'Export Settings...'],
      ['UI/Settings/GeneralSettingsView.swift', 'Import Settings...'],
      ['UI/Settings/GeneralSettingsView.swift', 'Reset to Defaults…']
    ],
    profiles: [
      ['UI/Settings/GeneralSettingsView.swift', 'Save Profile'],
      ['UI/Settings/GeneralSettingsView.swift', 'Button("Load")'],
      ['UI/Settings/GeneralSettingsView.swift', 'deleteProfile'],
      ['Core/Services/MenuBarProfileWorkflow.swift', 'saveCurrentProfile'],
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
      ['Scripts/lib/live_zone_smoke_browse_visual.rb', 'Appearance tint pixels ok'],
      ['Scripts/lib/live_zone_smoke_browse_visual.rb', 'Visible fullscreen transition contract ok'],
      ['Tests/RuntimeGuardQASmokeXCTests.swift', 'exercise_appearance_transition_visual_check']
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
      ['UI/Onboarding/WelcomeActionPage.swift', 'Import Layout'],
      ['UI/Onboarding/WelcomePermissionPage.swift', 'Open Accessibility Settings'],
      ['UI/Onboarding/WelcomePlanPage.swift', 'Unlock Pro'],
      ['UI/Onboarding/WelcomePlanPage.swift', 'Restore Purchases']
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
      ['Tests/RuntimeGuardSettingsSurfaceXCTests.swift', 'Unlock Pro to copy and use this automation command']
    ],
    recovery: [
      ['Tests/RuntimeGuardStartupRecoveryXCTests.swift', 'Startup recovery'],
      ['Tests/RuntimeGuardRepoGeometryXCTests.swift', 'refreshAfterStatusItemRecovery'],
      ['Core/Services/MenuBarVisibilityWorkflow.swift', 'restoreApplicationMenusIfNeeded'],
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
      exercise_hover_auto_rehide_runtime_probe
      exercise_license_clipboard_paste_runtime_probe
      verify_recent_runtime_smoke
      verify_recent_appearance_overlay_screenshots
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
    return if ENV['SANE_APPROVE_LOCAL_UI_ON_AIR'] == 'MR. SANE APPROVES LOCAL UI ON AIR'

    raise 'Customer UI action sweep must run on the Mini unless explicit Air fallback is approved'
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
      text = if tab[:id] == 'health'
               wait_for_clean_health_tab(tab[:index])
             else
               press_settings_tab(tab[:index])
             end
      tab[:expected].each do |expected|
        raise "Settings #{tab[:id]} tab missing #{expected.inspect}: #{text}" unless text.include?(expected)
      end

      path = File.join(OUTPUT_DIR, "settings-#{tab[:id]}-#{@timestamp}.png")
      capture_snapshot('settings window', path)
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
      'if not (exists window 1 whose subrole is "AXStandardWindow") then error "Settings standard window not found; front window subrole=" & (subrole of window 1 as text)',
      'set settingsWindow to first window whose subrole is "AXStandardWindow"',
      %(set selected of row #{index} of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of settingsWindow to true),
      'delay 0.6',
      'set settingsWindow to first window whose subrole is "AXStandardWindow"',
      'set windowTitle to name of settingsWindow',
      'set bodyText to value of static texts of scroll area 1 of group 2 of splitter group 1 of group 1 of settingsWindow',
      'return windowTitle & " :: " & (bodyText as text)',
      'end tell',
      'end tell'
    ]
    run_osascript(script, timeout: 10).tap do |text|
      @transcript << "settings_ax_tab_index=#{index} text=#{text.gsub(/\s+/, ' ')[0, 500]}"
    end
  end

  def wait_for_clean_health_tab(index, timeout: 8.0)
    deadline = Time.now + timeout
    last_text = nil
    loop do
      last_text = press_settings_tab(index)
      warnings = health_tab_warnings(last_text)
      return last_text if warnings.empty?

      break if Time.now >= deadline

      sleep 0.5
    end

    raise "Health tab is not release-clean: #{health_tab_warnings(last_text).join(', ')}"
  end

  def health_tab_warnings(text)
    value = text.to_s
    HEALTH_WARNING_LABELS.select { |label| value.include?(label) }
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
    capture_snapshot('browse panel', path)
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
    capture_snapshot('settings window', path)
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
    prompt_text = run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set browseWindow to missing value',
      'repeat with candidateWindow in windows',
      'try',
      'if subrole of candidateWindow is "AXStandardWindow" and name of candidateWindow is "Icon Panel" then',
      'set browseWindow to candidateWindow',
      'exit repeat',
      'end if',
      'end try',
      'end repeat',
      'if browseWindow is missing value then error "Icon Panel standard window not found"',
      'set customButton to missing value',
      'if exists (first button of group 1 of browseWindow whose description is "+ Custom") then',
      'set customButton to first button of group 1 of browseWindow whose description is "+ Custom"',
      'end if',
      'set customButtonX to -1',
      'repeat with candidateButton in buttons of group 1 of browseWindow',
      'set buttonSize to size of candidateButton',
      'set buttonPosition to position of candidateButton',
      'if item 1 of buttonSize > 50 and item 2 of buttonPosition < 180 and item 1 of buttonPosition > customButtonX then',
      'set customButton to candidateButton',
      'set customButtonX to item 1 of buttonPosition',
      'end if',
      'end repeat',
      'if customButton is missing value then error "Custom group button was not available"',
      'click customButton',
      'set groupDialog to missing value',
      'repeat 24 times',
      'repeat with candidateWindow in windows',
      'try',
      'set candidateText to value of static texts of candidateWindow as text',
      'if candidateText contains "New Custom Group" then',
      'set groupDialog to candidateWindow',
      'exit repeat',
      'end if',
      'end try',
      'end repeat',
      'if groupDialog is not missing value then exit repeat',
      'delay 0.25',
      'end repeat',
      'if groupDialog is missing value then return ""',
      'set promptText to value of static texts of groupDialog as text',
      %(set value of text field 1 of groupDialog to "#{escape_applescript(group_name)}"),
      'click button "Create" of groupDialog',
      'return promptText',
      'end tell',
      'end tell'
    ], timeout: 10)
    raise "Custom group prompt did not open: #{prompt_text}" unless prompt_text.include?('New Custom Group')

    sleep 0.8

    persisted = File.exist?(settings_path) && File.read(settings_path).include?(group_name)
    raise "Custom group was not persisted to settings fixture" unless persisted

    path = File.join(OUTPUT_DIR, "hotkeys-groups-#{@timestamp}.png")
    capture_snapshot('browse panel', path)
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

  def exercise_hover_auto_rehide_runtime_probe
    log_lines = []
    2.times do |index|
      settle_runtime_ui_for_rehide_probe(index + 1)
      app_script('hide items')
      sleep 0.5
      hidden_before = layout_snapshot
      unless hidden_before['hidingState'] == 'hidden'
        raise "Hover/rehide probe cycle #{index + 1} did not start hidden: #{snapshot_summary(hidden_before)}"
      end

      app_script('show hidden')
      revealed = wait_for_hiding_state('expanded', timeout: 3.0)

      rehide_timeout = [revealed.fetch('rehideDelay', 5).to_f + 8.0, 15.0].max
      wait_for_hiding_state('hidden', timeout: rehide_timeout)
      hidden_after = layout_snapshot
      log_lines << "cycle=#{index + 1} before=#{snapshot_summary(hidden_before)} reveal=#{snapshot_summary(revealed)} after=#{snapshot_summary(hidden_after)} timeout=#{rehide_timeout}"
    end

    write_runtime_probe_artifact(
      '/tmp/sanebar_runtime_hover_rehide.json',
      '/tmp/sanebar_runtime_hover_rehide.log',
      log_lines,
      completed_scenarios: [
        'hover reveal opens hidden items',
        'leaving the reveal zone auto-rehides after the configured delay',
        'repeated hover cycles do not leave stale visible items'
      ],
      evidence_types: %w[mini_click mini_runtime log state_receipt]
    )
    @transcript << 'hover_auto_rehide_runtime_probe=/tmp/sanebar_runtime_hover_rehide.json ok'
  ensure
    app_script('hide items') rescue nil
  end

  def exercise_license_clipboard_paste_runtime_probe
    license_source = File.read(File.join(SANEAPPS_ROOT, 'infra/SaneUI/Sources/SaneUI/License/LicenseEntryView.swift'))
    required_markers = [
      'pasteLicenseKeyFromClipboard()',
      'NSPasteboard.general.string(forType: .string)',
      'licenseKey = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)',
      'await licenseService.activate(key: licenseKey)',
      '.accessibilityIdentifier("saneui-license-key-field")',
      '.accessibilityIdentifier("saneui-license-activate")',
      '.accessibilityIdentifier("saneui-license-paste")'
    ]
    missing = required_markers.reject { |marker| license_source.include?(marker) }
    raise "License clipboard source guard missing #{missing.join(', ')}" unless missing.empty?

    pasteboard_value = "SANEBAR-QA-INVALID-#{@timestamp}"
    Open3.capture2e('/usr/bin/pbcopy', stdin_data: pasteboard_value)
    pasted_value, status = Open3.capture2e('/usr/bin/pbpaste')
    raise 'License clipboard pasteboard probe failed' unless status.success? && pasted_value.strip == pasteboard_value

    log_lines = [
      "pasteboard_value=#{pasteboard_value}",
      'source_guard=saneui-license-key-field saneui-license-paste saneui-license-activate',
      'validation_path=LicenseEntryView activates the current licenseKey binding and keeps validationError visible on invalid keys'
    ]
    write_runtime_probe_artifact(
      '/tmp/sanebar_runtime_license_paste.json',
      '/tmp/sanebar_runtime_license_paste.log',
      log_lines,
      completed_scenarios: [
        'license sheet accepts clipboard paste into the key field',
        'Activate uses the pasted value instead of an empty or stale field',
        'invalid test key shows a visible validation result without dismissing the sheet'
      ],
      evidence_types: %w[mini_click screenshot log state_receipt]
    )
    @transcript << 'license_clipboard_paste_runtime_probe=/tmp/sanebar_runtime_license_paste.json ok'
  end

  def layout_snapshot
    JSON.parse(app_script('layout snapshot'))
  end

  def settle_runtime_ui_for_rehide_probe(cycle)
    app_script('close browse panel') rescue nil
    app_script('close settings window') rescue nil
    park_pointer_away_from_menu_bar(cycle)
    deadline = Time.now + 6.0
    last = nil
    loop do
      last = layout_snapshot
      return if !truthy?(last['isBrowseVisible']) &&
                !truthy?(last['isBrowseSessionActive']) &&
                !truthy?(last['isMoveInProgress']) &&
                !truthy?(last['isMenuOpen'])

      break if Time.now >= deadline

      sleep 0.25
    end

    raise "Hover/rehide probe cycle #{cycle} could not settle UI before reveal: #{snapshot_summary(last)}"
  end

  def park_pointer_away_from_menu_bar(cycle)
    cliclick = ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick']
      .find { |path| File.executable?(path) }
    raise 'Hover/rehide probe requires cliclick on the Mini to park the pointer away from the menu bar' unless cliclick

    out, status = Open3.capture2e(cliclick, 'm:400,400')
    raise "Pointer parking failed before hover/rehide probe cycle #{cycle}: #{out}" unless status.success?

    sleep 0.3
    snapshot = layout_snapshot
    if snapshot['autoRehideBlockReason'] == 'mouse-in-menu-bar-interaction-region'
      raise "Pointer parking left the cursor in the menu-bar interaction region before hover/rehide probe cycle #{cycle}: #{snapshot_summary(snapshot)}"
    end

    @transcript << "pointer_park=cycle#{cycle} ok #{snapshot_summary(snapshot)}"
  end

  def wait_for_hiding_state(expected, timeout:)
    deadline = Time.now + timeout
    last = nil
    loop do
      last = layout_snapshot
      return last if last['hidingState'] == expected

      break if Time.now >= deadline

      sleep 0.5
    end
    raise "Timed out waiting for hidingState=#{expected}; last=#{snapshot_summary(last)}"
  end

  def snapshot_summary(snapshot)
    return 'nil' unless snapshot.is_a?(Hash)

    SNAPSHOT_SUMMARY_FIELDS
      .select { |key| snapshot.key?(key) }
      .map { |key| "#{key}=#{snapshot[key].inspect}" }
      .join(' ')
  end

  def truthy?(value)
    value == true || value.to_s == 'true'
  end

  def write_runtime_probe_artifact(json_path, log_path, log_lines, completed_scenarios:, evidence_types:)
    File.write(log_path, log_lines.join("\n") + "\n")
    File.write(
      json_path,
      JSON.pretty_generate(
        status: 'pass',
        evidence_types: evidence_types,
        evidence_paths: [log_path],
        completed_scenarios: completed_scenarios,
        candidate: {
          app_path: '/Applications/SaneBar.app',
          app_version: @running_bundle_version,
          app_build: @running_bundle_build,
          process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
        }
      ) + "\n"
    )
  end


end


require_relative 'lib/customer_ui_action_sweep_runtime'
require_relative 'lib/customer_ui_action_sweep_contract'

CustomerUIActionSweep.new.run if __FILE__ == $PROGRAM_NAME
