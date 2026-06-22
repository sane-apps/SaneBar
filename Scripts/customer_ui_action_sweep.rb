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
  RUNTIME_PREFLIGHT_DIR = File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight')
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

  DURABLE_RUNTIME_PREFLIGHT_EVIDENCE_PATTERN =
    "\\A#{Regexp.escape(RUNTIME_PREFLIGHT_DIR)}/sanebar_runtime_(?:startup_probe|wake_probe|hover_rehide|license_paste)\\.(?:json|log)(?::|\\z)"

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
    'mini_click' => /\A(?:\/tmp\/sanebar_runtime_|#{DURABLE_RUNTIME_PREFLIGHT_EVIDENCE_PATTERN}|applescript=|settings_ax_tab_index=|settings_tab=|icon_hotkeys_groups_|url_route=|runtime_visual=)/,
    'mini_automation' => /\A(?:applescript=|url_route=|settings_ax_tab_index=|icon_hotkeys_groups_)/,
    'mini_ax' => /\Asettings_ax_tab_index=/,
    'mini_url_route' => /\Aurl_route=/,
    'mini_runtime' => /(?:\A\/tmp\/sanebar_runtime_|#{DURABLE_RUNTIME_PREFLIGHT_EVIDENCE_PATTERN})/
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
      verify_recent_runtime_smoke
      if ENV['SANEBAR_CUSTOMER_UI_RESUME_TRANSCRIPT'].to_s.strip != ''
        run_from_resume_transcript(ENV.fetch('SANEBAR_CUSTOMER_UI_RESUME_TRANSCRIPT'))
        return
      end
      dismiss_transient_ui
      exercise_settings_tabs
      exercise_url_routes
      exercise_applescript_commands
      capture_runtime_visual_snapshots
      exercise_icon_hotkeys_and_groups
      exercise_hover_auto_rehide_runtime_probe
      exercise_license_clipboard_paste_runtime_probe
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

  def run_from_resume_transcript(path)
    load_resume_transcript!(path)
    dismiss_transient_ui
    exercise_hover_auto_rehide_runtime_probe
    exercise_license_clipboard_paste_runtime_probe
    verify_recent_appearance_overlay_screenshots
    verify_source_and_unit_guards
    build_action_results
    verify_all_actions_have_results!
    write_receipt
    puts "✅ Customer UI action sweep resumed from #{relative(path)} and passed: #{relative(RECEIPT_PATH)}"
  end

  def load_resume_transcript!(path)
    full_path = File.absolute_path(path, PROJECT_ROOT)
    raise "Resume transcript missing: #{path}" unless File.file?(full_path)

    lines = File.readlines(full_path, chomp: true)
    usable_lines = lines.take_while { |line| !line.start_with?('RuntimeError:') && !line.start_with?('scripts/') }
    @transcript.concat(usable_lines.reject(&:empty?))
    usable_lines.each { |line| import_resume_transcript_artifact(line) }
    @transcript << "resume_transcript=#{relative(full_path)} ok"
  end

  def import_resume_transcript_artifact(line)
    case line
    when /\Asnapshot_staged=(\S+)/
      register_resume_screenshot(Regexp.last_match(1))
    when /\Aruntime_visual=([a-z-]+) ok snapshot=(\S+)/
      register_resume_screenshot(Regexp.last_match(2), key: Regexp.last_match(1))
    when /\Asettings_tab=([a-z]+) ok snapshot=(\S+)/
      register_resume_screenshot(Regexp.last_match(2), key: "settings-#{Regexp.last_match(1)}", settings: true)
    when /\Aicon_hotkeys_groups_.* snapshot=(\S+)/
      register_resume_screenshot(Regexp.last_match(1), key: 'hotkeys-groups')
    end
  end

  def register_resume_screenshot(path, key: nil, settings: false)
    relative_path = relative(path)
    return unless File.file?(relative_path)
    return unless usable_screenshot?(relative_path)

    @screenshots << relative_path
    if settings || File.basename(relative_path).start_with?('settings-')
      @settings_snapshots << relative_path
    end
    if key
      @visual_screenshots[key] = relative_path
    elsif File.basename(relative_path).start_with?('settings-')
      key_id = File.basename(relative_path).sub(/\A(settings-[^-]+)-.*/, '\1')
      @visual_screenshots[key_id] = relative_path
      @visual_screenshots['settings'] ||= relative_path
    end
  end

  def dismiss_transient_ui
    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set frontmost to true',
      'repeat with candidateWindow in windows',
      'try',
      'if (subrole of candidateWindow is "AXSystemDialog") or ((name of candidateWindow as text) contains "Health") then',
      'set closeButton to value of attribute "AXCloseButton" of candidateWindow',
      'perform action "AXPress" of closeButton',
      'end if',
      'end try',
      'end repeat',
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
    bundle_path = '/Applications/SaneBar.app'
    binary_path = File.join(bundle_path, 'Contents', 'MacOS', APP_NAME)
    raise "Running release app binary is missing at #{binary_path}" unless File.executable?(binary_path)
    @release_binary_path = binary_path
    ensure_release_sweep_pro_unlocked!(pids, binary_path)

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

  def ensure_release_sweep_pro_unlocked!(pids, binary_path)
    onboarding_open = release_sweep_onboarding_window_open?
    snapshot = release_sweep_layout_snapshot
    return if truthy?(snapshot && snapshot['licenseIsPro']) && !onboarding_open && Array(pids).length == 1

    mark_release_sweep_onboarding_complete!
    terminate_release_sweep_processes(pids)
    launch_release_sweep_app(binary_path)

    deadline = Time.now + 15.0
    last = snapshot
    until Time.now >= deadline
      sleep 0.5
      last = release_sweep_layout_snapshot
      return if truthy?(last && last['licenseIsPro'])
    end

    raise "#{APP_NAME} release sweep requires a paid license or active Pro trial; licenseIsPro=#{last && last['licenseIsPro'].inspect}"
  end

  def ensure_pro_state_for_pro_only_action!(label)
    pids = current_release_sweep_pids(label)
    binary_path = @release_binary_path || File.join('/Applications/SaneBar.app', 'Contents', 'MacOS', APP_NAME)
    ensure_release_sweep_pro_unlocked!(pids, binary_path)
    snapshot = release_sweep_layout_snapshot
    raise "#{label} requires paid license or active Pro trial; licenseIsPro=#{snapshot && snapshot['licenseIsPro'].inspect}" unless truthy?(snapshot && snapshot['licenseIsPro'])

    @transcript << "pro_only_action=#{label} pro_state=ok"
  end

  def current_release_sweep_pids(label)
    out, status = Open3.capture2e('pgrep', '-x', APP_NAME)
    raise "#{label} requires #{APP_NAME} to be running" unless status.success?

    out.lines.map(&:strip).reject(&:empty?)
  end

  def release_sweep_layout_snapshot
    JSON.parse(app_script('layout snapshot'))
  rescue JSON::ParserError, StandardError
    nil
  end

  def release_sweep_onboarding_window_open?
    run_osascript([
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'repeat with candidateWindow in windows',
      'try',
      'set candidateText to value of static texts of candidateWindow as text',
      'if candidateText contains "Welcome to SaneBar" then return "true"',
      'end try',
      'end repeat',
      'return "false"',
      'end tell',
      'end tell'
    ], timeout: 5).strip == 'true'
  rescue StandardError
    false
  end

  def mark_release_sweep_onboarding_complete!
    settings_path = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
    settings = if File.exist?(settings_path)
                 JSON.parse(File.read(settings_path))
               else
                 {}
               end
    settings['hasCompletedOnboarding'] = true
    settings['hasSeenFreemiumIntro'] = true
    FileUtils.mkdir_p(File.dirname(settings_path))
    File.write(settings_path, JSON.pretty_generate(settings))
  rescue JSON::ParserError
    FileUtils.mkdir_p(File.dirname(settings_path))
    File.write(settings_path, JSON.pretty_generate(
      'hasCompletedOnboarding' => true,
      'hasSeenFreemiumIntro' => true
    ))
  end

  def terminate_release_sweep_processes(pids)
    ids = Array(pids).map(&:to_i).select(&:positive?).uniq
    ids.each do |pid|
      Process.kill('TERM', pid.to_i)
    rescue Errno::ESRCH, ArgumentError
      nil
    end
    deadline = Time.now + 5.0
    while Time.now < deadline && ids.any? { |pid| process_alive?(pid) }
      sleep 0.2
    end
    ids.each do |pid|
      Process.kill('KILL', pid) if process_alive?(pid)
    rescue Errno::ESRCH, ArgumentError
      nil
    end
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, ArgumentError
    false
  end

  def launch_release_sweep_app(binary_path)
    Process.detach(
      Process.spawn(
        binary_path,
        '--sane-skip-app-move',
        out: File::NULL,
        err: File::NULL
      )
    )
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
      'set settingsWindow to missing value',
      'repeat with candidateWindow in windows',
      'try',
      'set _ to splitter group 1 of group 1 of candidateWindow',
      'set settingsWindow to candidateWindow',
      'exit repeat',
      'end try',
      'end repeat',
      'if settingsWindow is missing value then error "Settings standard window not found; front window subrole=" & (subrole of window 1 as text)',
      %(set selected of row #{index} of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of settingsWindow to true),
      'delay 0.6',
      'set settingsWindow to missing value',
      'repeat with candidateWindow in windows',
      'try',
      'set _ to splitter group 1 of group 1 of candidateWindow',
      'set settingsWindow to candidateWindow',
      'exit repeat',
      'end try',
      'end repeat',
      'if settingsWindow is missing value then error "Settings standard window not found after tab selection"',
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

  def wait_for_clean_health_tab(index, timeout: 30.0)
    deadline = Time.now + timeout
    last_text = nil
    repair_triggered = false
    loop do
      last_text = press_settings_tab(index)
      warnings = health_tab_warnings(last_text)
      return last_text if warnings.empty?

      break if Time.now >= deadline

      unless repair_triggered
        trigger_health_repair_route(warnings)
        repair_triggered = true
      end
      sleep 0.5
    end

    append_health_runtime_snapshot
    raise "Health tab is not release-clean: #{health_tab_warnings(last_text).join(', ')}"
  end

  def health_tab_warnings(text)
    value = text.to_s
    HEALTH_WARNING_LABELS.select { |label| value.include?(label) }
  end

  def trigger_health_repair_route(warnings)
    out, status = Open3.capture2e('/usr/bin/open', 'sanebar://repair')
    raise "Health repair route failed after warnings #{warnings.join(', ')}: #{out}" unless status.success?

    @transcript << "health_warning_repair_route=triggered warnings=#{warnings.join('|')}"
  end

  def append_health_runtime_snapshot
    snapshot = app_script('layout snapshot')
    @transcript << "health_runtime_snapshot=#{snapshot.gsub(/\s+/, ' ')[0, 1200]}"
  rescue StandardError => e
    @transcript << "health_runtime_snapshot_error=#{e.class}: #{e.message}"
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

    ensure_pro_state_for_pro_only_action!('custom group creation')
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
    restore_hover_setting = ensure_hover_reveal_enabled_for_probe
    2.times do |index|
      park_pointer_away_from_menu_bar(index + 1)
      settle_runtime_ui_for_rehide_probe(index + 1)
      app_script('hide items')
      sleep 0.5
      hidden_before = layout_snapshot
      unless hidden_before['hidingState'] == 'hidden'
        raise "Hover/rehide probe cycle #{index + 1} did not start hidden: #{snapshot_summary(hidden_before)}"
      end

      move_pointer_to_menu_bar_for_hover_probe(index + 1)
      revealed = wait_for_hiding_state('expanded', timeout: 3.0)
      park_pointer_away_from_menu_bar(index + 1)

      rehide_timeout = [revealed.fetch('rehideDelay', 5).to_f + 8.0, 15.0].max
      wait_for_hiding_state('hidden', timeout: rehide_timeout)
      hidden_after = layout_snapshot
      log_lines << "cycle=#{index + 1} pointer_hover=menu_bar before=#{snapshot_summary(hidden_before)} reveal=#{snapshot_summary(revealed)} after=#{snapshot_summary(hidden_after)} timeout=#{rehide_timeout}"
    end

    json_path = runtime_probe_artifact_path('hover_rehide', 'json')
    log_path = runtime_probe_artifact_path('hover_rehide', 'log')
    write_runtime_probe_artifact(
      json_path,
      log_path,
      log_lines,
      completed_scenarios: [
        'hover reveal opens hidden items',
        'leaving the reveal zone auto-rehides after the configured delay',
        'repeated hover cycles do not leave stale visible items'
      ],
      evidence_types: %w[mini_click mini_runtime log state_receipt]
    )
    @transcript << "hover_auto_rehide_runtime_probe=#{relative(json_path)} ok"
  ensure
    app_script('hide items') rescue nil
    restore_hover_setting.call if restore_hover_setting
  end

  def exercise_license_clipboard_paste_runtime_probe
    pasteboard_value = "SANEBAR-QA-INVALID-#{@timestamp}"
    Open3.capture2e('/usr/bin/pbcopy', stdin_data: pasteboard_value)
    pasted_value, status = Open3.capture2e('/usr/bin/pbpaste')
    raise 'License clipboard pasteboard probe failed' unless status.success? && pasted_value.strip == pasteboard_value

    ui_result = drive_license_clipboard_paste_ui(pasteboard_value)
    screenshot_path = runtime_probe_artifact_path('license_paste', 'png')
    capture_snapshot('settings window', screenshot_path)
    raise "License clipboard paste screenshot was not usable: #{screenshot_path}" unless usable_screenshot?(screenshot_path)

    log_lines = [
      "pasteboard_value=#{pasteboard_value}",
      "ui_result=#{ui_result.gsub(/\s+/, ' ')[0, 1200]}",
      "screenshot=#{relative(screenshot_path)}",
      'validation_path=real LicenseEntryView paste button populated the key field and Activate produced visible validation copy'
    ]
    json_path = runtime_probe_artifact_path('license_paste', 'json')
    log_path = runtime_probe_artifact_path('license_paste', 'log')
    write_runtime_probe_artifact(
      json_path,
      log_path,
      log_lines,
      completed_scenarios: [
        'license sheet accepts clipboard paste into the key field',
        'Activate uses the pasted value instead of an empty or stale field',
        'invalid test key shows a visible validation result without dismissing the sheet'
      ],
      evidence_types: %w[mini_click screenshot log state_receipt],
      evidence_paths: [log_path, screenshot_path]
    )
    @screenshots << relative(screenshot_path)
    @visual_screenshots['license-paste'] = relative(screenshot_path)
    @transcript << "license_clipboard_paste_runtime_probe=#{relative(json_path)} ok"
  end

  def drive_license_clipboard_paste_ui(expected_value)
    app_script('open settings window')
    press_settings_tab(6)
    run_osascript(system_events_recursive_helpers + [
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set frontmost to true',
      'set settingsWindow to first window whose subrole is "AXStandardWindow"',
      'set deactivateButton to my findElementByIdentifier(settingsWindow, "saneui-license-deactivate")',
      'if deactivateButton is missing value then set deactivateButton to my findButtonNamed(settingsWindow, "Deactivate Pro")',
      'if deactivateButton is missing value then set deactivateButton to my licenseActionButton(settingsWindow, 1)',
      'if deactivateButton is not missing value then',
      'click deactivateButton',
      'delay 0.8',
      'end if',
      'set entryButton to my findElementByIdentifier(settingsWindow, "saneui-license-enter-key")',
      'if entryButton is missing value then set entryButton to my findButtonNamed(settingsWindow, "Enter License Key")',
      'if entryButton is missing value then set entryButton to my findButtonNamed(settingsWindow, "I Have a License Key")',
      'if entryButton is missing value then set entryButton to my licenseActionButton(settingsWindow, 2)',
      'if entryButton is missing value then error "License entry button not found after opening License settings"',
      'click entryButton',
      'delay 0.8',
      'set pasteButton to my findElementByIdentifier(settingsWindow, "saneui-license-paste")',
      'if pasteButton is missing value then error "License paste button AXIdentifier not found"',
      'click pasteButton',
      'delay 0.4',
      'set keyField to my findElementByIdentifier(settingsWindow, "saneui-license-key-field")',
      'if keyField is missing value then error "License key field AXIdentifier not found"',
      'set pastedValue to value of keyField as text',
      %(if pastedValue is not "#{escape_applescript(expected_value)}" then error "License key field did not receive pasted value: " & pastedValue),
      'set activateButton to my findElementByIdentifier(settingsWindow, "saneui-license-activate")',
      'if activateButton is missing value then set activateButton to my findButtonNamed(settingsWindow, "Activate")',
      'if activateButton is missing value then error "License activate button not found"',
      'click activateButton',
      'set validationText to ""',
      'repeat 24 times',
      'delay 0.5',
      'try',
      'set validationText to my allStaticText(settingsWindow)',
      'repeat with candidateWindow in windows',
      'set validationText to validationText & my allStaticText(candidateWindow)',
      'end repeat',
      'end try',
      'if validationText contains "Invalid" or validationText contains "purchase server" or validationText contains "Please enter" or validationText contains "license_key not found" or validationText contains "not found" then',
      'return "pasted=" & pastedValue & " validation=" & validationText',
      'end if',
      'end repeat',
      'error "License validation text did not appear after Activate; last text=" & validationText',
      'end tell',
      'end tell'
    ], timeout: 25)
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

  def move_pointer_to_menu_bar_for_hover_probe(cycle)
    cliclick = ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick']
      .find { |path| File.executable?(path) }
    raise 'Hover/rehide probe requires cliclick on the Mini to move the pointer into the menu bar' unless cliclick

    x = hover_probe_x(layout_snapshot)
    out, status = Open3.capture2e(cliclick, "m:#{x},4")
    raise "Pointer hover move failed during hover/rehide probe cycle #{cycle}: #{out}" unless status.success?

    @transcript << "pointer_hover=cycle#{cycle} x=#{x} ok"
  end

  def hover_probe_x(snapshot)
    screen_width = snapshot['screenWidth'].to_f
    screen_width = 1920.0 unless screen_width.positive?
    candidates = [
      snapshot['mainIconLeftEdgeX'].to_f.positive? ? snapshot['mainIconLeftEdgeX'].to_f + 12.0 : nil,
      snapshot['separatorRightEdgeX'].to_f.positive? ? snapshot['separatorRightEdgeX'].to_f + 18.0 : nil,
      screen_width - 160.0
    ].compact
    if snapshot['notchRightSafeMinX'].to_f.positive?
      candidates.unshift(snapshot['notchRightSafeMinX'].to_f + 24.0)
    end
    bounded = candidates.find { |value| value >= 1 && value <= screen_width - 24 } || (screen_width - 160.0)
    [[bounded.round, 1].max, (screen_width - 24).round].min
  end

  def ensure_hover_reveal_enabled_for_probe
    app_script('open settings window')
    press_settings_tab(1)
    result = run_osascript(system_events_recursive_helpers + [
      'tell application "System Events"',
      %(tell process "#{APP_NAME}"),
      'set frontmost to true',
      'set settingsWindow to first window whose subrole is "AXStandardWindow"',
      'set hoverControl to my findElementNamed(settingsWindow, "Reveal hidden icons on hover")',
      'if hoverControl is missing value then error "Reveal hidden icons on hover control not found"',
      'set wasEnabled to false',
      'try',
      'set wasEnabled to ((value of hoverControl as integer) is 1)',
      'end try',
      'if wasEnabled is false then',
      'click hoverControl',
      'delay 0.5',
      'return "enabled_for_probe"',
      'end if',
      'return "already_enabled"',
      'end tell',
      'end tell'
    ], timeout: 12).strip
    @transcript << "hover_reveal_setting=#{result}"
    app_script('close settings window') rescue nil
    return nil unless result == 'enabled_for_probe'

    lambda do
      app_script('open settings window')
      press_settings_tab(1)
      run_osascript(system_events_recursive_helpers + [
        'tell application "System Events"',
        %(tell process "#{APP_NAME}"),
        'set frontmost to true',
        'set settingsWindow to first window whose subrole is "AXStandardWindow"',
        'set hoverControl to my findElementNamed(settingsWindow, "Reveal hidden icons on hover")',
        'if hoverControl is not missing value then click hoverControl',
        'end tell',
        'end tell'
      ], timeout: 12)
      app_script('close settings window') rescue nil
      @transcript << 'hover_reveal_setting=restored_disabled'
    rescue StandardError => e
      @transcript << "hover_reveal_setting_restore_failed=#{e.class}: #{e.message}"
    end
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

  def write_runtime_probe_artifact(json_path, log_path, log_lines, completed_scenarios:, evidence_types:, evidence_paths: nil)
    safe_write_runtime_probe_file(log_path, log_lines.join("\n") + "\n")
    safe_write_runtime_probe_file(
      json_path,
      JSON.pretty_generate(
        status: 'pass',
        evidence_types: evidence_types,
        evidence_paths: Array(evidence_paths || [log_path]),
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

  def runtime_probe_artifact_path(name, extension)
    safe_name = name.to_s.gsub(/[^a-zA-Z0-9_-]/, '-')
    safe_extension = extension.to_s.gsub(/[^a-zA-Z0-9]/, '')
    File.join(RUNTIME_PREFLIGHT_DIR, "sanebar_runtime_#{safe_name}.#{safe_extension}")
  end

  def safe_write_runtime_probe_file(path, content)
    expanded = File.expand_path(path)
    root = File.expand_path(PROJECT_ROOT)
    raise "Runtime probe artifact path must stay under project root: #{path}" unless expanded.start_with?("#{root}/")

    safe_runtime_probe_directory_path!(File.dirname(expanded))
    FileUtils.mkdir_p(File.dirname(expanded))
    safe_runtime_probe_directory_path!(File.dirname(expanded))
    flags = File::WRONLY | File::CREAT | File::TRUNC
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(expanded, flags, 0o600) do |file|
      file.write(content)
    end
  end

  def safe_runtime_probe_directory_path!(path)
    expanded = File.expand_path(path)
    root = File.expand_path(PROJECT_ROOT)
    raise "Unsafe runtime probe directory outside project root: #{path}" unless expanded == root || expanded.start_with?("#{root}/")

    current = File::SEPARATOR
    expanded.split(File::SEPARATOR).reject(&:empty?).each do |component|
      current = File.join(current, component)
      next unless File.exist?(current)

      stat = File.lstat(current)
      raise "Unsafe symlink runtime probe directory: #{current}" if stat.symlink?
      raise "Unsafe non-directory runtime probe path: #{current}" unless stat.directory?
    end
    true
  end

  def system_events_recursive_helpers
    [
      'on elementName(elementRef)',
      'try',
      'return name of elementRef as text',
      'on error',
      'return ""',
      'end try',
      'end elementName',
      'on elementIdentifier(elementRef)',
      'try',
      'tell application "System Events" to return value of attribute "AXIdentifier" of elementRef as text',
      'on error',
      'return ""',
      'end try',
      'end elementIdentifier',
      'on findElementByIdentifier(rootElement, targetIdentifier)',
      'if my elementIdentifier(rootElement) is targetIdentifier then return rootElement',
      'try',
      'tell application "System Events"',
      'repeat with childElement in UI elements of rootElement',
      'set foundElement to my findElementByIdentifier(childElement, targetIdentifier)',
      'if foundElement is not missing value then return foundElement',
      'end repeat',
      'end tell',
      'end try',
      'return missing value',
      'end findElementByIdentifier',
      'on findElementNamed(rootElement, targetName)',
      'if my elementName(rootElement) is targetName then return rootElement',
      'try',
      'tell application "System Events"',
      'repeat with childElement in UI elements of rootElement',
      'set foundElement to my findElementNamed(childElement, targetName)',
      'if foundElement is not missing value then return foundElement',
      'end repeat',
      'end tell',
      'end try',
      'return missing value',
      'end findElementNamed',
      'on findButtonNamed(rootElement, targetName)',
      'try',
      'tell application "System Events"',
      'if role of rootElement is "AXButton" and my elementName(rootElement) is targetName then return rootElement',
      'end tell',
      'end try',
      'try',
      'tell application "System Events"',
      'repeat with childElement in UI elements of rootElement',
      'set foundElement to my findButtonNamed(childElement, targetName)',
      'if foundElement is not missing value then return foundElement',
      'end repeat',
      'end tell',
      'end try',
      'return missing value',
      'end findButtonNamed',
      'on licenseActionButton(rootElement, ordinal)',
      'set matches to {}',
      'tell application "System Events"',
      'my collectLicenseActionButtons(rootElement, matches)',
      'end tell',
      'if (count of matches) < ordinal then return missing value',
      'return item ordinal of matches',
      'end licenseActionButton',
      'on allStaticText(rootElement)',
      'set collectedText to ""',
      'tell application "System Events"',
      'try',
      'if role of rootElement is "AXStaticText" then set collectedText to collectedText & (value of rootElement as text) & linefeed',
      'end try',
      'try',
      'repeat with childElement in UI elements of rootElement',
      'set collectedText to collectedText & my allStaticText(childElement)',
      'end repeat',
      'end try',
      'end tell',
      'return collectedText',
      'end allStaticText',
      'on collectLicenseActionButtons(rootElement, matches)',
      'tell application "System Events"',
      'try',
      'if role of rootElement is "AXButton" and description of rootElement is "button" then',
      'set buttonPosition to position of rootElement',
      'set buttonSize to size of rootElement',
      'if (item 1 of buttonPosition) > 850 and (item 2 of buttonPosition) > 180 and (item 2 of buttonPosition) < 360 and (item 1 of buttonSize) > 80 then set end of matches to rootElement',
      'end if',
      'end try',
      'try',
      'repeat with childElement in UI elements of rootElement',
      'my collectLicenseActionButtons(childElement, matches)',
      'end repeat',
      'end try',
      'end tell',
      'end collectLicenseActionButtons'
    ]
  end


end


require_relative 'lib/customer_ui_action_sweep_runtime'
require_relative 'lib/customer_ui_action_sweep_contract'

CustomerUIActionSweep.new.run if __FILE__ == $PROGRAM_NAME
