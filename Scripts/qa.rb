#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Project QA Script
# Automated product verification before release
#
# Usage: ruby scripts/qa.rb
#
# Checks:
# - SaneMaster wrapper delegates to SaneProcess correctly
# - SaneMaster_standalone.rb has valid syntax
# - All project-specific .rb scripts have valid Ruby syntax
# - All project-specific .swift scripts parse cleanly
# - Version consistency (project.yml, README, DEVELOPMENT.md)
# - URLs in docs are reachable
# - .claude/rules/ count matches expectations
#

require 'net/http'
require 'uri'
require 'json'
require 'open3'
require 'time'
require 'fileutils'
require 'socket'

class ProjectQA
  PROJECT_ROOT = File.expand_path('..', __dir__)
  SANEPROCESS_MANIFEST = File.join(PROJECT_ROOT, '.saneprocess')
  MANIFEST_METADATA = begin
    metadata = {}
    if File.exist?(SANEPROCESS_MANIFEST)
      File.foreach(SANEPROCESS_MANIFEST) do |line|
        raw = line.chomp
        stripped = raw.strip
        next if stripped.empty? || stripped.start_with?('#')
        next if raw.start_with?(' ', "\t")

        if (match = raw.match(/\A(name|scheme|project):\s*(.+)\z/))
          metadata[match[1]] = match[2].delete('"').strip
        end
      end
    end
    metadata
  end
  PROJECT_NAME = MANIFEST_METADATA['name'] || File.basename(PROJECT_ROOT)
  PROJECT_SCHEME = MANIFEST_METADATA['scheme'] || PROJECT_NAME
  PROJECT_XCODEPROJ = File.join(PROJECT_ROOT, MANIFEST_METADATA['project'] || "#{PROJECT_NAME}.xcodeproj")

  README = File.join(PROJECT_ROOT, 'README.md')
  DEVELOPMENT_MD = File.join(PROJECT_ROOT, 'DEVELOPMENT.md')
  PROJECT_YML = File.join(PROJECT_ROOT, 'project.yml')
  APPCAST_XML = File.join(PROJECT_ROOT, 'docs', 'appcast.xml')
  STATUS_BAR_CONTROLLER_SWIFT = File.join(PROJECT_ROOT, 'Core', 'Controllers', 'StatusBarController.swift')
  STATUS_BAR_CONTROLLER_TESTS = File.join(PROJECT_ROOT, 'Tests', 'StatusBarControllerTests.swift')
  SANEMASTER_CLI = File.join(__dir__, 'SaneMaster.rb')
  SANEMASTER_STANDALONE = File.join(__dir__, 'SaneMaster_standalone.rb')
  RULES_DIR = File.join(PROJECT_ROOT, '.claude', 'rules')
  QA_STATUS_PATH = File.join(PROJECT_ROOT, 'outputs', 'qa_status.json')

  # SaneProcess infra path (expected when running internally)
  INFRA_SANEMASTER = File.join(PROJECT_ROOT, '..', '..', 'infra', 'SaneProcess', 'scripts', 'SaneMaster.rb')

  # Number of Golden Rules in the global SOP (#0 through #16)
  EXPECTED_RULE_COUNT = 17

  # Number of .claude/rules/ files (code style rules)
  EXPECTED_CODE_RULE_COUNT = 8

  # Versions that must never be re-offered via Sparkle after regressions.
  BLOCKED_APPCAST_VERSIONS = %w[2.1.3 2.1.6 2.1.11 2.1.12].freeze
  REQUIRED_MIGRATION_TEST_TITLES = [
    'Migration preserves healthy custom positions on upgrade',
    'Migration resets positions when legacy always-hidden position is corrupted',
    'Upgrade matrix handles healthy and corrupted states safely',
    'Real upgrade snapshots from 2.1.2 and 2.1.5 preserve layout',
  ].freeze
  REQUIRED_STATUS_RECOVERY_TEST_TITLES = [
    'Autosave names use stored autosave version',
    'Recreate with bumped version updates autosave namespace',
    'Init clears persisted status-item visibility overrides',
  ].freeze
  STABILITY_TEST_TARGETS = [
    'SaneBarTests/StatusBarControllerTests',
    'SaneBarTests/ReleaseRegressionTests',
    'SaneBarTests/SecondMenuBarTests',
    'SaneBarTests/SecondMenuBarDropXCTests',
    'SaneBarTests/MenuBarSearchDropXCTests',
    'SaneBarTests/RuntimeGuardXCTests',
    'SaneBarTests/MenuExtraIdentifierNormalizationTests',
  ].freeze
  EXPECTED_TEST_MODE_APPS = %w[
    SaneBar SaneClip SaneClick SaneHosts SaneSales SaneSync SaneVideo
  ].freeze
  RUNTIME_SMOKE_LOG_PATH = '/tmp/sanebar_runtime_smoke.log'
  RUNTIME_LAUNCH_LOG_PATH = '/tmp/sanebar_runtime_launch.log'
  RUNTIME_SMOKE_PASSES = 2
  RUNTIME_SMOKE_HEARTBEAT_SECONDS = 8
  RECURRING_REGRESSION_TEST_MARKERS = {
    'Tests/IconMovingTests.swift' => [
      'REGRESSION: #93-style geometry avoids boundary-hugging target',
      'REGRESSION: Hidden→visible must use showAll(), not show()',
      'REGRESSION: Drag uses 20 steps, not 6',
    ],
    'Tests/MenuBarSearchDropXCTests.swift' => [
      'testAllTabBoundaryPrefersSeparatorRightEdge',
      'testSourceResolutionUsesAllModeZoneClassifierOnFallback',
    ],
    'Tests/RuntimeGuardXCTests.swift' => [
      'testStartupHideContinuesWhenAccessibilityPermissionIsMissing',
      'testIconPanelDoesNotForceAlwaysHiddenForFreeUsers',
    ],
    'Tests/SecondMenuBarTests.swift' => [
      'Each item belongs to exactly one zone',
      'Duplicate pin is idempotent',
      'Item at separator edge respects margin',
    ],
    'Tests/ReleaseRegressionTests.swift' => [
      'Blocked versions are never offered in appcast',
      'Appcast newest entry matches current project marketing version',
    ],
  }.freeze
  RELEASE_SOAK_HOURS = 24
  REGRESSION_CONFIRMATION_WINDOW_HOURS = 48

  def initialize
    @errors = []
    @warnings = []
  end

  def run
    puts "═══════════════════════════════════════════════════════════════"
    puts "                  #{PROJECT_NAME} QA Check"
    puts "═══════════════════════════════════════════════════════════════"
    puts

    check_sanemaster_wrapper
    check_script_syntax_rb
    check_script_syntax_swift
    check_script_syntax_sh
    check_code_rules
    check_version_consistency
    check_appcast_guardrails
    check_migration_guardrails
    check_test_mode_tooling_guardrails
    check_runtime_release_smoke
    check_recurring_regression_coverage_guardrails
    check_release_cadence_guardrails
    check_open_regression_guardrails
    check_regression_confirmation_guardrails
    run_stability_suite
    check_urls

    puts
    puts "═══════════════════════════════════════════════════════════════"

    exit_code = if @errors.empty? && @warnings.empty?
      puts "✅ All checks passed!"
      0
    else
      unless @warnings.empty?
        puts "⚠️  Warnings (#{@warnings.count}):"
        @warnings.each { |w| puts "   - #{w}" }
        puts
      end

      unless @errors.empty?
        puts "❌ Errors (#{@errors.count}):"
        @errors.each { |e| puts "   - #{e}" }
        puts
        1
      else
        0
      end
    end

    write_status_snapshot(exit_code: exit_code)
    exit exit_code
  end

  private

  def preflight_mode?
    ENV['SANEBAR_RELEASE_PREFLIGHT'] == '1' || ENV['SANEBAR_RUN_STABILITY_SUITE'] == '1'
  end

  def runtime_smoke_mode?
    preflight_mode? ||
      ENV['SANEPROCESS_RUN_RUNTIME_SMOKE'] == '1' ||
      ENV['SANEBAR_RUN_RUNTIME_SMOKE'] == '1'
  end

  def running_on_mini_host?
    host = Socket.gethostname.to_s.downcase
    user = ENV.fetch('USER', '').downcase
    host.include?('mini') || user == 'stephansmac'
  rescue StandardError
    false
  end

  def manual_override_phrase(gate:)
    case gate
    when :release_cadence
      'MR. SANE APPROVES FAST RELEASE'
    when :unconfirmed_regression_close
      'MR. SANE APPROVES UNCONFIRMED REGRESSION CLOSE'
    when :open_regression_release
      'MR. SANE APPROVES OPEN REGRESSION RELEASE'
    else
      'MR. SANE APPROVES OVERRIDE'
    end
  end

  def request_manual_override(gate:, summary:)
    phrase = manual_override_phrase(gate: gate)

    env_override = manual_override_from_env(gate)
    return [true, phrase] if env_override == phrase

    unless $stdin.tty? && $stdout.tty?
      return [false, phrase]
    end

    puts
    puts "⚠️  Manual approval required: #{summary}"
    puts 'Type exactly to continue:'
    puts phrase
    print '> '
    response = $stdin.gets&.strip

    [response == phrase, phrase]
  end

  def manual_override_from_env(gate)
    case gate
    when :release_cadence
      ENV['SANEPROCESS_APPROVE_FAST_RELEASE'] || ENV['SANEBAR_APPROVE_FAST_RELEASE']
    when :open_regression_release
      ENV['SANEPROCESS_APPROVE_OPEN_REGRESSION_RELEASE'] || ENV['SANEBAR_APPROVE_OPEN_REGRESSION_RELEASE']
    when :unconfirmed_regression_close
      ENV['SANEPROCESS_APPROVE_UNCONFIRMED_REGRESSION_CLOSE'] || ENV['SANEBAR_APPROVE_UNCONFIRMED_REGRESSION_CLOSE']
    else
      nil
    end
  end

  def check_sanemaster_wrapper
    print "Checking SaneMaster wrapper... "

    unless File.exist?(SANEMASTER_CLI)
      @errors << "SaneMaster.rb not found"
      puts "❌ Missing"
      return
    end

    # Verify wrapper syntax (it's a bash script)
    result = `bash -n #{SANEMASTER_CLI} 2>&1`
    unless $?.success?
      @errors << "SaneMaster.rb has invalid bash syntax"
      puts "❌ Invalid syntax"
      return
    end

    # Verify it references SaneProcess infra
    content = File.read(SANEMASTER_CLI)
    unless content.include?('SaneProcess')
      @errors << "SaneMaster.rb does not reference SaneProcess infra"
      puts "❌ Missing SaneProcess delegation"
      return
    end

    # Verify infra exists
    infra_path = File.expand_path(INFRA_SANEMASTER)
    unless File.exist?(infra_path)
      @warnings << "SaneProcess infra not found at #{infra_path}"
      puts "⚠️  Infra not found (standalone mode only)"
      return
    end

    # Verify standalone fallback exists
    unless File.exist?(SANEMASTER_STANDALONE)
      @errors << "SaneMaster_standalone.rb not found"
      puts "❌ Missing standalone"
      return
    end

    result = `ruby -c #{SANEMASTER_STANDALONE} 2>&1`
    unless $?.success?
      @errors << "SaneMaster_standalone.rb has invalid syntax"
      puts "❌ Standalone invalid"
      return
    end

    puts "✅ Wrapper + standalone + infra delegation OK"
  end

  def check_script_syntax_rb
    print "Checking Ruby script syntax... "

    rb_files = Dir.glob(File.join(__dir__, '*.rb'))
    # Skip SaneMaster.rb — it's a bash wrapper (already checked in check_sanemaster_wrapper)
    rb_files.reject! { |f| File.basename(f) == 'SaneMaster.rb' }
    invalid = []

    rb_files.each do |path|
      result = `ruby -c #{path} 2>&1`
      invalid << File.basename(path) unless $?.success?
    end

    if invalid.empty?
      puts "✅ #{rb_files.count} Ruby scripts valid"
    else
      @errors << "Invalid Ruby syntax: #{invalid.join(', ')}"
      puts "❌ Invalid: #{invalid.join(', ')}"
    end
  end

  def check_script_syntax_swift
    print "Checking Swift script syntax... "

    swift_files = Dir.glob(File.join(__dir__, '*.swift'))
    if swift_files.empty?
      puts "⚠️  No Swift scripts found"
      return
    end

    invalid = []
    swift_files.each do |path|
      result = `swift -parse #{path} 2>&1`
      invalid << File.basename(path) unless $?.success?
    end

    if invalid.empty?
      puts "✅ #{swift_files.count} Swift scripts valid"
    else
      # Swift scripts may import app modules — parse errors are warnings, not blockers
      invalid.each { |f| @warnings << "Swift parse issue: #{f} (may need app imports)" }
      puts "⚠️  #{invalid.count} with parse issues (may need app imports)"
    end
  end

  def check_script_syntax_sh
    print "Checking shell script syntax... "

    sh_files = Dir.glob(File.join(__dir__, '*.sh'))
    if sh_files.empty?
      puts "⚠️  No shell scripts found"
      return
    end

    invalid = []
    sh_files.each do |path|
      result = `bash -n #{path} 2>&1`
      invalid << File.basename(path) unless $?.success?
    end

    if invalid.empty?
      puts "✅ #{sh_files.count} shell scripts valid"
    else
      @errors << "Invalid shell syntax: #{invalid.join(', ')}"
      puts "❌ Invalid: #{invalid.join(', ')}"
    end
  end

  def check_code_rules
    print "Checking .claude/rules/ ... "

    unless Dir.exist?(RULES_DIR)
      @warnings << ".claude/rules/ directory not found"
      puts "⚠️  Not found"
      return
    end

    rule_files = Dir.glob(File.join(RULES_DIR, '*.md')).reject { |f| File.basename(f) == 'README.md' }
    count = rule_files.count

    if count == EXPECTED_CODE_RULE_COUNT
      puts "✅ #{count} code rule files"
    else
      @warnings << ".claude/rules/ has #{count} files, expected #{EXPECTED_CODE_RULE_COUNT}"
      puts "⚠️  #{count} files (expected #{EXPECTED_CODE_RULE_COUNT})"
    end
  end

  def check_version_consistency
    print "Checking version consistency... "

    versions = {}

    # Check project.yml for MARKETING_VERSION
    if File.exist?(PROJECT_YML)
      content = File.read(PROJECT_YML)
      if (match = content.match(/MARKETING_VERSION:\s*["']?(\d+\.\d+\.\d+)/))
        versions['project.yml'] = match[1]
      end
    end

    # Check README.md
    if File.exist?(README)
      content = File.read(README)
      if (match = content.match(/#{PROJECT_NAME}\s+v?(\d+\.\d+\.\d+)/i))
        versions['README.md'] = match[1]
      end
    end

    if versions.empty?
      @warnings << "No version strings found in project.yml or README.md"
      puts "⚠️  No versions found"
      return
    end

    unique_versions = versions.values.uniq
    if unique_versions.count <= 1
      puts "✅ Version #{unique_versions.first || 'consistent'}"
    else
      details = versions.map { |f, v| "#{f}=v#{v}" }.join(', ')
      @warnings << "Version mismatch: #{details}"
      puts "⚠️  Mismatch: #{details}"
    end
  end

  def check_appcast_guardrails
    print "Checking appcast guardrails... "

    unless File.exist?(APPCAST_XML)
      @warnings << "Appcast file not found at #{APPCAST_XML}"
      puts "⚠️  appcast.xml missing"
      return
    end

    content = File.read(APPCAST_XML)
    versions = content.scan(/sparkle:shortVersionString="(\d+\.\d+\.\d+)"/).flatten

    if versions.empty?
      @warnings << "No sparkle:shortVersionString entries found in appcast.xml"
      puts "⚠️  no versions found"
      return
    end

    blocked_present = versions & BLOCKED_APPCAST_VERSIONS
    unless blocked_present.empty?
      @errors << "Blocked appcast version(s) present: #{blocked_present.join(', ')}"
      puts "❌ blocked versions present: #{blocked_present.join(', ')}"
      return
    end

    puts "✅ no blocked versions (#{BLOCKED_APPCAST_VERSIONS.join(', ')})"
  end

  def check_migration_guardrails
    print "Checking migration guardrails... "

    unless File.exist?(STATUS_BAR_CONTROLLER_SWIFT) && File.exist?(STATUS_BAR_CONTROLLER_TESTS)
      @errors << "Migration guardrail files missing (StatusBarController or tests)"
      puts "❌ missing source/test file"
      return
    end

    source = File.read(STATUS_BAR_CONTROLLER_SWIFT)
    tests = File.read(STATUS_BAR_CONTROLLER_TESTS)
    failures = []

    stable_key_match = source.match(/stablePositionMigrationKey\s*=\s*"([^"]+)"/)
    unless stable_key_match
      failures << 'stablePositionMigrationKey constant not found in StatusBarController.swift'
      stable_key = nil
    else
      stable_key = stable_key_match[1]
    end

    unless source.match?(/if\s+shouldResetPositionsForKnownCorruption\(\)/)
      failures << 'migrateCorruptedPositionsIfNeeded must gate resets with shouldResetPositionsForKnownCorruption()'
    end

    unless source.match?(/private static func shouldResetPositionsForKnownCorruption\(\)/)
      failures << 'shouldResetPositionsForKnownCorruption() predicate is missing from StatusBarController.swift'
    end

    if stable_key && !tests.include?(stable_key)
      failures << "Tests missing stable migration key '#{stable_key}' — migration key changes must be paired with regression tests"
    end

    legacy_keys = source.scan(/"SaneBar_PositionMigration_v\d+"/).map { |value| value.delete('"') }.uniq
    missing_legacy = legacy_keys.reject { |key| tests.include?(key) }
    unless missing_legacy.empty?
      failures << "Tests missing legacy migration keys: #{missing_legacy.join(', ')}"
    end

    missing_titles = REQUIRED_MIGRATION_TEST_TITLES.reject { |title| tests.include?(title) }
    unless missing_titles.empty?
      failures << "Missing required migration regression test titles: #{missing_titles.join(' | ')}"
    end

    missing_recovery_titles = REQUIRED_STATUS_RECOVERY_TEST_TITLES.reject { |title| tests.include?(title) }
    unless missing_recovery_titles.empty?
      failures << "Missing required status-item recovery test titles: #{missing_recovery_titles.join(' | ')}"
    end

    if failures.empty?
      puts '✅ migration key changes are guarded by corruption + preservation tests'
    else
      failures.each { |failure| @errors << failure }
      puts "❌ #{failures.count} guardrail failure(s)"
    end
  end

  def check_test_mode_tooling_guardrails
    print 'Checking test-mode tooling guardrails... '

    script = File.expand_path('../../infra/SaneProcess/scripts/app_test_mode.sh', PROJECT_ROOT)
    unless File.exist?(script)
      @errors << "Test-mode script missing: #{script}"
      puts '❌ missing app_test_mode.sh'
      return
    end

    syntax_ok = system('bash', '-n', script, out: File::NULL, err: File::NULL)
    unless syntax_ok
      @errors << "Test-mode script has invalid shell syntax: #{script}"
      puts '❌ invalid shell syntax'
      return
    end

    list_out, list_status = Open3.capture2e(script, 'list')
    unless list_status.success?
      @errors << "Test-mode script failed to list apps: #{list_out.lines.last&.strip || 'unknown error'}"
      puts '❌ list command failed'
      return
    end

    listed_apps = list_out.lines.map(&:strip).reject(&:empty?)
    missing = EXPECTED_TEST_MODE_APPS - listed_apps
    extras = listed_apps - EXPECTED_TEST_MODE_APPS

    if missing.empty?
      extra_note = extras.empty? ? '' : " (+extra: #{extras.join(', ')})"
      puts "✅ list covers #{EXPECTED_TEST_MODE_APPS.count} apps#{extra_note}"
    else
      @errors << "Test-mode script missing app(s): #{missing.join(', ')}"
      puts "❌ missing: #{missing.join(', ')}"
    end
  end

  def check_runtime_release_smoke
    print 'Running release runtime smoke... '

    unless runtime_smoke_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1 or SANEBAR_RUN_RUNTIME_SMOKE=1)'
      return
    end

    unless running_on_mini_host?
      message = 'Runtime smoke must run on the mini via ./scripts/SaneMaster.rb so the local workspace syncs before release verification.'
      if preflight_mode?
        @errors << message
        puts '❌ not on mini'
      else
        @warnings << message
        puts '⚠️  not on mini'
      end
      return
    end

    smoke_script = File.join(__dir__, 'live_zone_smoke.rb')
    unless File.exist?(smoke_script)
      @errors << "Runtime smoke script missing: #{smoke_script}"
      puts '❌ missing live_zone_smoke.rb'
      return
    end

    restore_mode = nil

    begin
      restore_mode, mode_error = ensure_runtime_smoke_pro_mode!
      if mode_error
        @errors << mode_error
        puts '❌ could not seed Pro smoke mode'
        return
      end

      screenshot_dir = File.expand_path("~/Desktop/Screenshots/#{PROJECT_NAME}")
      FileUtils.mkdir_p(screenshot_dir)
      Dir.glob(File.join(screenshot_dir, 'sanebar-*.png')).each { |path| FileUtils.rm_f(path) }
      FileUtils.rm_f(RUNTIME_SMOKE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_LAUNCH_LOG_PATH)
      screenshot_capture_available = runtime_screenshot_capture_available?(screenshot_dir)

      launch_out, launch_status = Open3.capture2e(SANEMASTER_CLI, 'test_mode', '--release', '--no-logs')
      File.write(RUNTIME_LAUNCH_LOG_PATH, launch_out)
      unless launch_status.success?
        @errors << "Runtime smoke launch failed. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ launch failed (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      target = runtime_smoke_target(launch_output: launch_out)
      unless target
        @errors << "Runtime smoke could not determine launch target. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ unknown launch target (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      target_error = validate_runtime_smoke_target(target)
      if target_error
        @errors << "#{target_error} See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ invalid runtime smoke target (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      unless ensure_runtime_smoke_target_running!(target)
        @errors << "Runtime smoke could not launch target #{target[:app_path]}. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ target launch failed (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      puts
      puts "   ↳ smoke target: #{target[:app_path]}"
      puts "   ↳ #{target[:note]}" if target[:note]

      smoke_env = {
        'SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN' => '1',
        'SANEBAR_SMOKE_CAPTURE_SCREENSHOTS' => screenshot_capture_available ? '1' : '0',
        'SANEBAR_SMOKE_SCREENSHOT_DIR' => screenshot_dir,
        'SANEBAR_SMOKE_APP_PATH' => target[:app_path],
        'SANEBAR_SMOKE_PROCESS_PATH' => target[:process_path],
      }
      unless screenshot_capture_available
        puts '   ↳ screenshot capture unavailable on this host; continuing without smoke screenshots'
      end
      smoke_outputs = []
      RUNTIME_SMOKE_PASSES.times do |index|
        puts "   ↳ smoke pass #{index + 1}/#{RUNTIME_SMOKE_PASSES}"
        smoke_out, smoke_status = capture2e_with_progress(
          smoke_env,
          smoke_script,
          heartbeat_label: "runtime smoke pass #{index + 1}/#{RUNTIME_SMOKE_PASSES}"
        )
        smoke_outputs << "pass #{index + 1}/#{RUNTIME_SMOKE_PASSES}\n#{smoke_out}"
        next if smoke_status.success?

        File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
        @errors << "Runtime smoke failed on pass #{index + 1}/#{RUNTIME_SMOKE_PASSES}. See #{RUNTIME_SMOKE_LOG_PATH}"
        puts "❌ failed on pass #{index + 1}/#{RUNTIME_SMOKE_PASSES} (#{RUNTIME_SMOKE_LOG_PATH})"
        return
      end

      File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
      if screenshot_capture_available
        expected_screenshots = runtime_smoke_expected_modes(target).to_h do |mode|
          [mode, Dir.glob(File.join(screenshot_dir, "sanebar-#{mode}-*.png")).max_by { |path| File.mtime(path) }]
        end
        missing = expected_screenshots.select { |_mode, path| path.nil? }.keys
        unless missing.empty?
          @errors << "Runtime smoke missing screenshot artifact(s): #{missing.join(', ')}"
          puts "❌ missing screenshot(s): #{missing.join(', ')}"
          return
        end

        artifact_summary = expected_screenshots.map { |mode, path| "#{mode}=#{File.basename(path)}" }.join(', ')
        puts "✅ staged release browse smoke x#{RUNTIME_SMOKE_PASSES} (#{artifact_summary})"
      else
        puts "✅ staged release browse smoke x#{RUNTIME_SMOKE_PASSES} (screenshots skipped on this host)"
      end
    ensure
      restore_runtime_smoke_mode(restore_mode)
    end
  end

  def runtime_screenshot_capture_available?(screenshot_dir)
    probe_path = File.join(screenshot_dir, '.sanebar-runtime-smoke-probe.png')
    FileUtils.rm_f(probe_path)
    _out, status = Open3.capture2e('/usr/sbin/screencapture', '-x', probe_path)
    status.success? && File.exist?(probe_path) && !File.zero?(probe_path)
  ensure
    FileUtils.rm_f(probe_path) if probe_path
  end

  def runtime_smoke_mode_status
    output, status = Open3.capture2e(SANEMASTER_CLI, 'mode', 'status')
    return nil unless status.success?

    text = output.downcase
    return :pro if text.include?('mode: pro')
    return :basic if text.include?('mode: basic')

    nil
  rescue StandardError
    nil
  end

  def ensure_runtime_smoke_pro_mode!
    current_mode = runtime_smoke_mode_status
    return [nil, 'Runtime smoke could not determine the current fallback test mode.'] if current_mode.nil?
    return [nil, nil] if current_mode == :pro

    output, status = Open3.capture2e(SANEMASTER_CLI, 'mode', 'pro')
    return [:basic, nil] if status.success?

    [nil, "Runtime smoke could not switch fallback test mode to Pro: #{output.lines.last&.strip || output.strip}"]
  rescue StandardError => e
    [nil, "Runtime smoke could not switch fallback test mode to Pro: #{e.message}"]
  end

  def restore_runtime_smoke_mode(mode)
    return if mode.nil?

    Open3.capture2e(SANEMASTER_CLI, 'mode', mode.to_s)
  rescue StandardError
    nil
  end

  def runtime_smoke_target(launch_output:)
    launched_path = launch_output.lines.reverse.find { |line| line.include?('📱 Launching:') }
    launched_path = launched_path&.split('📱 Launching:', 2)&.last&.strip
    unsigned_fallback = launch_output.include?('Unsigned fallback active:')
    system_app_path = "/Applications/#{PROJECT_NAME}.app"
    system_process_path = File.join(system_app_path, 'Contents', 'MacOS', PROJECT_NAME)
    launched_target = nil

    unless launched_path.to_s.empty?
      launched_target = {
        app_path: launched_path,
        process_path: File.join(launched_path, 'Contents', 'MacOS', PROJECT_NAME),
        relaunch: false,
        note: 'using the app that test_mode just launched',
      }
    end

    if unsigned_fallback && File.exist?(system_app_path) && developer_id_signed?(system_app_path)
      if launched_target
        launched_meta = app_bundle_metadata(launched_target[:app_path])
        system_meta = app_bundle_metadata(system_app_path)

        if same_release_build?(launched_meta, system_meta)
          return {
            app_path: system_app_path,
            process_path: system_process_path,
            relaunch: true,
            note: "using installed signed app for smoke because unsigned fallback build #{format_bundle_metadata(launched_meta)} matches /Applications/#{PROJECT_NAME}.app",
          }
        end

        launched_target[:note] = "keeping the launched fallback app because /Applications/#{PROJECT_NAME}.app is #{format_bundle_metadata(system_meta)} and the launched build is #{format_bundle_metadata(launched_meta)}"
        return launched_target
      end

      return {
        app_path: system_app_path,
        process_path: system_process_path,
        relaunch: true,
        note: 'using installed signed app for smoke because test_mode did not report a launched app path',
      }
    end

    return launched_target if launched_target

    nil
  end

  def ensure_runtime_smoke_target_running!(target)
    if target[:relaunch]
      system('killall', PROJECT_NAME, out: File::NULL, err: File::NULL)
      sleep 1
      launched = system('open', target[:app_path], out: File::NULL, err: File::NULL)
      return false unless launched
    end

    deadline = Time.now + 8
    while Time.now < deadline
      processes, status = Open3.capture2e('ps', 'ax', '-o', 'pid=,command=')
      break unless status.success?

      matches = processes.lines.any? do |line|
        _pid, command = line.strip.split(/\s+/, 2)
        next false unless command

        command.split(/\s+/, 2).first.to_s == target[:process_path]
      end
      return true if matches

      sleep 0.5
    end

    false
  end

  def validate_runtime_smoke_target(target)
    metadata = app_bundle_metadata(target[:app_path])
    expected_bundle_id = 'com.sanebar.app'

    if metadata[:bundle_id].to_s != expected_bundle_id
      system_meta = app_bundle_metadata("/Applications/#{PROJECT_NAME}.app")
      detail = system_meta.empty? ? '' : " Signed /Applications target is #{format_bundle_metadata(system_meta)}."
      return "Runtime smoke requires signed release bundle #{expected_bundle_id}; got #{format_bundle_metadata(metadata)}.#{detail}"
    end

    auth_value = accessibility_auth_value_for(expected_bundle_id)
    return nil if auth_value == 2

    auth_detail = auth_value.nil? ? 'missing' : auth_value.to_s
    "Runtime smoke target #{expected_bundle_id} is not Accessibility-granted in TCC (auth_value=#{auth_detail})."
  end

  def runtime_smoke_expected_modes(target)
    commands = applescript_commands_for_app(target[:app_path])
    modes = []
    modes << 'secondMenuBar' if commands.include?('show second menu bar')
    modes << 'findIcon' if commands.include?('open icon panel')
    modes
  end

  def applescript_commands_for_app(app_path)
    sdef_path = File.join(app_path, 'Contents', 'Resources', "#{PROJECT_NAME}.sdef")
    return [] unless File.exist?(sdef_path)

    File.read(sdef_path).scan(/<command name="([^"]+)"/).flatten
  rescue StandardError
    []
  end

  def developer_id_signed?(app_path)
    output, status = Open3.capture2e('codesign', '-dv', '--verbose=2', app_path)
    return false unless status.success? || !output.to_s.empty?

    output.lines.any? { |line| line.start_with?('Authority=Developer ID Application:') }
  end

  def app_bundle_metadata(app_path)
    info_plist = File.join(app_path, 'Contents', 'Info.plist')
    return {} unless File.exist?(info_plist)

    {
      short_version: plist_value(info_plist, 'CFBundleShortVersionString'),
      build_version: plist_value(info_plist, 'CFBundleVersion'),
      bundle_id: plist_value(info_plist, 'CFBundleIdentifier'),
    }
  end

  def plist_value(info_plist, key)
    output, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", info_plist)
    return nil unless status.success?

    output.lines.last&.strip
  rescue StandardError
    nil
  end

  def accessibility_auth_value_for(bundle_id)
    db_paths = [
      '/Library/Application Support/com.apple.TCC/TCC.db',
      File.expand_path('~/Library/Application Support/com.apple.TCC/TCC.db')
    ]

    db_paths.each do |db_path|
      next unless File.exist?(db_path)

      escaped_bundle = bundle_id.gsub("'", "''")
      output, status = Open3.capture2e(
        'sqlite3',
        db_path,
        "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='#{escaped_bundle}' ORDER BY auth_value DESC;"
      )
      next unless status.success?

      value = output.lines.map(&:strip).find { |line| !line.empty? }
      return value.to_i unless value.nil?
    end

    nil
  rescue StandardError
    nil
  end

  def same_release_build?(left, right)
    left_short = left[:short_version].to_s
    left_build = left[:build_version].to_s
    right_short = right[:short_version].to_s
    right_build = right[:build_version].to_s

    return false if left_short.empty? || left_build.empty? || right_short.empty? || right_build.empty?

    left_short == right_short && left_build == right_build
  end

  def format_bundle_metadata(metadata)
    short = metadata[:short_version].to_s
    build = metadata[:build_version].to_s
    bundle = metadata[:bundle_id].to_s
    parts = []
    parts << (short.empty? ? 'unknown version' : "v#{short}")
    parts << (build.empty? ? 'unknown build' : "build #{build}")
    parts << (bundle.empty? ? 'unknown bundle id' : bundle)
    parts.join(', ')
  end

  def capture2e_with_progress(env, *cmd, heartbeat_label:)
    output = +''
    status = nil
    started_at = Time.now
    last_output_at = Time.now
    last_heartbeat_at = Time.at(0)

    Open3.popen2e(env, *cmd) do |_stdin, stdout_err, wait_thr|
      loop do
        ready = IO.select([stdout_err], nil, nil, 1)
        if ready
          begin
            chunk = normalize_output_chunk(stdout_err.read_nonblock(4096))
            output << chunk
            print chunk
            $stdout.flush
            last_output_at = Time.now unless chunk.empty?
          rescue IO::WaitReadable
            nil
          rescue EOFError
            nil
          end
        end

        if wait_thr.join(0)
          status = wait_thr.value
          break
        end

        next unless (Time.now - last_output_at) >= RUNTIME_SMOKE_HEARTBEAT_SECONDS
        next unless (Time.now - last_heartbeat_at) >= RUNTIME_SMOKE_HEARTBEAT_SECONDS

        elapsed = (Time.now - started_at).round(1)
        puts "   … #{heartbeat_label} still running (#{elapsed}s)"
        last_heartbeat_at = Time.now
      end

      loop do
        chunk = normalize_output_chunk(stdout_err.read_nonblock(4096))
        output << chunk
        print chunk
        $stdout.flush
      rescue IO::WaitReadable
        break
      rescue EOFError
        break
      end
    end

    [output, status]
  end

  def normalize_output_chunk(chunk)
    normalized = chunk.dup
    normalized.force_encoding(Encoding::UTF_8)
    return normalized if normalized.valid_encoding?

    chunk.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace, replace: '?')
  rescue StandardError
    chunk.to_s.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace, replace: '?')
  end

  def check_recurring_regression_coverage_guardrails
    print 'Checking recurring-regression coverage guardrails... '

    failures = []
    RECURRING_REGRESSION_TEST_MARKERS.each do |relative_path, markers|
      path = File.join(PROJECT_ROOT, relative_path)
      unless File.exist?(path)
        failures << "Missing regression test file: #{relative_path}"
        next
      end

      content = File.read(path)
      markers.each do |marker|
        failures << "Missing regression marker '#{marker}' in #{relative_path}" unless content.include?(marker)
      end
    end

    if failures.empty?
      puts "✅ #{RECURRING_REGRESSION_TEST_MARKERS.values.flatten.count} marker checks"
    else
      failures.each { |failure| @errors << failure }
      puts "❌ #{failures.count} missing marker(s)"
    end
  end

  def check_release_cadence_guardrails
    print 'Checking release cadence guardrails... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1)'
      return
    end

    gh_available = system('command -v gh >/dev/null 2>&1')
    unless gh_available
      @warnings << 'Release cadence check skipped (gh not installed)'
      puts '⚠️  gh missing'
      return
    end

    releases_json, status = Open3.capture2e(
      'gh', 'release', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--limit', '2',
      '--json', 'tagName,publishedAt'
    )

    unless status.success?
      @warnings << 'Release cadence check skipped (failed to query GitHub releases)'
      puts '⚠️  gh query failed'
      return
    end

    releases = JSON.parse(releases_json) rescue []
    if releases.empty?
      @warnings << 'Release cadence check skipped (no releases returned from GitHub)'
      puts '⚠️  no release data'
      return
    end

    latest = releases.max_by { |release| Time.parse(release.fetch('publishedAt', Time.now.utc.iso8601)) }
    latest_time = Time.parse(latest.fetch('publishedAt'))
    hours_since_latest = ((Time.now.utc - latest_time) / 3600.0).round(1)

    if hours_since_latest < RELEASE_SOAK_HOURS
      details = "#{hours_since_latest}h since #{latest['tagName']} (<#{RELEASE_SOAK_HOURS}h)"
      approved, phrase = request_manual_override(
        gate: :release_cadence,
        summary: "Release cadence guard tripped (#{details})"
      )

      if approved
        @warnings << "Manual override approved for release cadence (#{details})"
        puts "⚠️  #{details} (manual approval)"
      else
        @errors << "Release cadence guard: #{details}. Manual approval phrase required: \"#{phrase}\"."
        puts "❌ #{details}"
      end
    else
      puts "✅ #{hours_since_latest}h since #{latest['tagName']}"
    end
  end

  def check_open_regression_guardrails
    print 'Checking open regression guardrails... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1)'
      return
    end

    gh_available = system('command -v gh >/dev/null 2>&1')
    unless gh_available
      @warnings << 'Open regression check skipped (gh not installed)'
      puts '⚠️  gh missing'
      return
    end

    issues_json, list_status = Open3.capture2e(
      'gh', 'issue', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--state', 'open',
      '--limit', '100',
      '--json', 'number,title,url,createdAt'
    )

    unless list_status.success?
      @warnings << 'Open regression check skipped (failed to query open issues)'
      puts '⚠️  gh query failed'
      return
    end

    issues = JSON.parse(issues_json) rescue []
    blocking = issues.select { |issue| regression_like_title?(issue['title']) }

    if blocking.empty?
      puts '✅ no open regression-like issues'
      return
    end

    summary = blocking.first(5).map { |issue| "##{issue['number']}" }.join(', ')
    approved, phrase = request_manual_override(
      gate: :open_regression_release,
      summary: "Open regression issue(s) detected (#{summary})"
    )

    if approved
      @warnings << "Manual override approved for open regression issue(s): #{summary}"
      puts "⚠️  open regression issues present (manual approval): #{summary}"
    else
      details = blocking.map { |issue| "##{issue['number']} #{issue['title']}" }.join(' | ')
      @errors << "Open regression issue(s) block release: #{details}. Manual approval phrase required: \"#{phrase}\"."
      puts "❌ blocking issue(s): #{summary}"
    end
  end

  def regression_like_title?(title)
    text = title.to_s.downcase
    patterns = [
      /reset/,
      /persist/,
      /disappear/,
      /icons? gone/,
      /visible.*hidden|hidden.*visible/,
      /move.*visible|visible.*move/,
      /move.*hidden|hidden.*move/,
      /second menu bar/,
      /browse icons/,
      /drag and drop/,
      /drag/,
      /cursor|mouse/,
      /cannot open/,
      /does not function|doesn't function|doesnt function/,
      /nothing seems to happen|nothing happens/,
      /won't show|wont show/,
      /not working/,
      /broke/,
      /fails?/
    ]
    patterns.any? { |pattern| text.match?(pattern) }
  end

  def reporter_confirmation?(comments)
    confirmation_pattern = /(fixed|works|working now|resolved|confirmed|looks good|thank you)/i
    comments.any? do |comment|
      association = comment['authorAssociation'].to_s.upcase
      next false if trusted_issue_author_associations.include?(association)

      body = comment['body'].to_s
      body.match?(confirmation_pattern)
    end
  end

  def trusted_issue_author_associations
    %w[MEMBER OWNER COLLABORATOR]
  end

  def closed_regression_confirmation_exemption_reason(comments)
    trusted_comments = comments.select do |comment|
      trusted_issue_author_associations.include?(comment['authorAssociation'].to_s.upcase)
    end
    closing_note = trusted_comments.reverse.map { |comment| comment['body'].to_s.strip }.find { |body| !body.empty? }.to_s
    return nil if closing_note.empty?

    return 'duplicate closure' if closing_note.match?(/duplicate of #\d+/i)
    return 'superseded closure' if closing_note.match?(/superseded by/i)

    settings_mismatch = closing_note.match?(/settings mismatch/i)
    missing_diagnostics = closing_note.match?(/never got the requested diagnostics|no fresh repro/i)
    return 'settings-mismatch closure' if settings_mismatch || missing_diagnostics

    nil
  end

  def check_regression_confirmation_guardrails
    print 'Checking regression close confirmation guardrails... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1)'
      return
    end

    gh_available = system('command -v gh >/dev/null 2>&1')
    unless gh_available
      @warnings << 'Regression confirmation check skipped (gh not installed)'
      puts '⚠️  gh missing'
      return
    end

    cutoff_date = (Time.now.utc - (REGRESSION_CONFIRMATION_WINDOW_HOURS * 3600)).strftime('%Y-%m-%d')
    issues_json, list_status = Open3.capture2e(
      'gh', 'issue', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--state', 'closed',
      '--search', "closed:>=#{cutoff_date}",
      '--limit', '50',
      '--json', 'number,title,closedAt'
    )

    unless list_status.success?
      @warnings << 'Regression confirmation check skipped (failed to query closed issues)'
      puts '⚠️  gh query failed'
      return
    end

    issues = JSON.parse(issues_json) rescue []
    regression_issues = issues.select { |issue| regression_like_title?(issue['title']) }
    if regression_issues.empty?
      puts '✅ no recently closed regression-like issues'
      return
    end

    unconfirmed = []
    exempt = []
    regression_issues.each do |issue|
      details_json, details_status = Open3.capture2e(
        'gh', 'issue', 'view', issue['number'].to_s,
        '--repo', 'sane-apps/SaneBar',
        '--json', 'comments'
      )
      next unless details_status.success?

      comments = (JSON.parse(details_json)['comments'] rescue []) || []
      exemption_reason = closed_regression_confirmation_exemption_reason(comments)
      if exemption_reason
        exempt << "##{issue['number']} #{exemption_reason}"
        next
      end

      unconfirmed << issue['number'] unless reporter_confirmation?(comments)
    end

    if unconfirmed.empty?
      if exempt.empty?
        puts "✅ #{regression_issues.count} closed regression issue(s) have reporter confirmation"
      else
        puts "✅ #{regression_issues.count - exempt.count} closed regression issue(s) have reporter confirmation; #{exempt.count} exempt historical closure(s)"
      end
      return
    end

    details = "unconfirmed: #{unconfirmed.join(', ')}"
    approved, phrase = request_manual_override(
      gate: :unconfirmed_regression_close,
      summary: "Closed regression issue(s) without reporter confirmation (#{details})"
    )

    if approved
      @warnings << "Manual override approved for unconfirmed regression close(s): #{unconfirmed.join(', ')}"
      puts "⚠️  #{details} (manual approval)"
    else
      @errors << "Closed regression issue(s) without reporter confirmation: #{unconfirmed.join(', ')}. Manual approval phrase required: \"#{phrase}\"."
      puts "❌ #{details}"
    end
  end

  def run_stability_suite
    print 'Running dedicated stability suite... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1 or SANEBAR_RUN_STABILITY_SUITE=1)'
      return
    end

    unless File.exist?(PROJECT_XCODEPROJ)
      @errors << "Stability suite: missing xcodeproj at #{PROJECT_XCODEPROJ}"
      puts '❌ missing xcodeproj'
      return
    end

    # Duplicate instances (e.g. /Applications + DerivedData) cause test host bootstrap
    # failures and produce false negatives in preflight.
    Open3.capture2e('bash', '-lc', "killall #{PROJECT_NAME} >/dev/null 2>&1 || true")
    sleep 0.5

    cmd = [
      'xcodebuild',
      '-project', PROJECT_XCODEPROJ,
      '-scheme', PROJECT_SCHEME,
      '-destination', 'platform=macOS,arch=arm64',
      'CODE_SIGNING_ALLOWED=NO',
      'test',
      '-quiet'
    ]
    STABILITY_TEST_TARGETS.each do |target|
      cmd << '-only-testing'
      cmd << target
    end

    output, status = Open3.capture2e(*cmd)
    if status.success?
      puts "✅ #{STABILITY_TEST_TARGETS.count} targets"
    else
      log_path = '/tmp/sanebar_stability_suite.log'
      File.write(log_path, output)
      @errors << "Stability suite failed. See #{log_path}"
      puts "❌ failed (#{log_path})"
    end
  end

  def check_urls
    print "Checking URLs in docs... "

    urls_to_check = []

    # Collect URLs from key documentation files
    doc_files = [README, DEVELOPMENT_MD] + Dir.glob(File.join(PROJECT_ROOT, 'docs', '*.md'))

    doc_files.each do |file|
      next unless File.exist?(file)

      content = File.read(file)
      content.scan(%r{https?://[^\s\)\]"']+}).each do |url|
        next if url.include?('localhost')
        next if url.include?('example.com')
        next if url.include?('XXXX')
        next if url.include?('<')

        urls_to_check << { url: url.gsub(/[,\.]$/, ''), file: File.basename(file) }
      end
    end

    if urls_to_check.empty?
      puts "⚠️  No URLs found"
      return
    end

    bad_urls = []
    urls_to_check.uniq { |u| u[:url] }.each do |entry|
      begin
        uri = URI.parse(entry[:url])
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 5

        response = nil
        [Net::HTTP::Head, Net::HTTP::Get].each_with_index do |request_class, index|
          request = request_class.new(uri.request_uri)
          request['User-Agent'] = "#{PROJECT_NAME} QA URL Check"
          response = http.request(request)
          code = response.code.to_i
          break unless [401, 403, 405].include?(code) && index.zero?
        end

        response_code = response.code.to_i
        reachable = response_code < 400
        reachable ||= response_code == 404 && entry[:url].include?('raw.githubusercontent')
        reachable ||= [401, 403, 405].include?(response_code)
        unless reachable
          bad_urls << "#{entry[:url]} (#{response.code}) in #{entry[:file]}"
        end
      rescue StandardError => e
        bad_urls << "#{entry[:url]} (#{e.class.name}) in #{entry[:file]}"
      end
    end

    if bad_urls.empty?
      puts "✅ #{urls_to_check.uniq { |u| u[:url] }.count} URLs reachable"
    else
      bad_urls.each { |u| @warnings << "Unreachable URL: #{u}" }
      puts "⚠️  #{bad_urls.count} unreachable"
    end
  end

  def write_status_snapshot(exit_code:)
    payload = {
      generatedAt: Time.now.iso8601,
      projectName: PROJECT_NAME,
      exitCode: exit_code,
      status: exit_code.zero? ? (@warnings.empty? ? 'passed' : 'passed_with_warnings') : 'failed',
      preflightMode: preflight_mode?,
      runtimeSmokeMode: runtime_smoke_mode?,
      runtimeSmokePasses: RUNTIME_SMOKE_PASSES,
      errorCount: @errors.count,
      warningCount: @warnings.count,
      errors: @errors,
      warnings: @warnings,
    }

    FileUtils.mkdir_p(File.dirname(QA_STATUS_PATH))
    File.write(QA_STATUS_PATH, JSON.pretty_generate(payload))
  rescue StandardError => e
    @warnings << "Failed to write QA status snapshot: #{e.message}"
  end
end

# Run if executed directly
ProjectQA.new.run if __FILE__ == $PROGRAM_NAME
