#!/usr/bin/env ruby
# frozen_string_literal: true

# Hook/launchd shells often run with a C locale, which makes Ruby default to
# US-ASCII and crash on UTF-8 sources and release artifacts. Force UTF-8.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

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

require 'uri'
require 'json'
require 'open3'
require 'time'
require 'date'
require 'fileutils'
require 'socket'
require 'tmpdir'

class ProjectQA
  PROJECT_ROOT = File.expand_path('..', __dir__)
  SCRIPTS_DIR = __dir__
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
  SETTINGS_PATH = File.expand_path("~/Library/Application Support/#{PROJECT_NAME}/settings.json")
  STATUS_BAR_POSITION_STORE_SWIFT = File.join(PROJECT_ROOT, 'Core', 'Services', 'StatusBarPositionStore.swift')
  STATUS_BAR_POSITION_TESTS = [
    File.join(PROJECT_ROOT, 'Tests', 'StatusBarControllerMigrationTests.swift'),
    File.join(PROJECT_ROOT, 'Tests', 'StatusBarControllerLifecycleTests.swift'),
    File.join(PROJECT_ROOT, 'Tests', 'StatusBarControllerResetRecoveryTests.swift')
  ].freeze
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
    'Migration reanchors positions when legacy always-hidden position is corrupted',
    'Upgrade matrix handles healthy and corrupted states safely',
    'Real upgrade snapshots from 2.1.2 and 2.1.5 preserve layout'
  ].freeze
  REQUIRED_STATUS_RECOVERY_TEST_TITLES = [
    'Autosave names use stored autosave version',
    'Recreate with bumped version updates autosave namespace',
    'Init clears persisted status-item visibility overrides'
  ].freeze
  PRIVACY_REQUIRED_REASON_PATTERNS = {
    'NSPrivacyAccessedAPICategoryUserDefaults' => {
      patterns: [/\bUserDefaults\b/],
      reason: 'CA92.1'
    },
    'NSPrivacyAccessedAPICategoryFileTimestamp' => {
      patterns: [
        /\.creationDate\b/,
        /\.modificationDate\b/,
        /contentModificationDateKey/,
        /creationDateKey/,
        /fileModificationDate/,
        /attributesOfItem\s*\(/,
        /\b(?:stat|lstat|fstat|fstatat|getattrlist|getattrlistbulk|fgetattrlist|getattrlistat)\s*\(/
      ],
      reason: 'C617.1'
    },
    'NSPrivacyAccessedAPICategoryDiskSpace' => {
      patterns: [
        /volumeAvailableCapacity/,
        /volumeTotalCapacity/,
        /volumeAvailableCapacityForImportantUsageKey/,
        /volumeAvailableCapacityForOpportunisticUsageKey/,
        /\b(?:statfs|fstatfs)\s*\(/
      ],
      reason: nil
    },
    'NSPrivacyAccessedAPICategorySystemBootTime' => {
      patterns: [
        /\bsystemUptime\b/,
        /\bmach_absolute_time\s*\(/
      ],
      reason: nil
    }
  }.freeze
  STABILITY_TEST_TARGETS = [
    'SaneBarTests/IconMovingTests',
    'SaneBarTests/SearchWindowTests',
    'SaneBarTests/StatusBarControllerTests',
    'SaneBarTests/ReleaseRegressionTests',
    'SaneBarTests/SecondMenuBarTests',
    'SaneBarTests/SecondMenuBarDropXCTests',
    'SaneBarTests/MenuBarSearchDropXCTests',
    'SaneBarTests/RuntimeGuardXCTests',
    'SaneBarTests/MenuExtraIdentifierNormalizationTests'
  ].freeze
  STABILITY_SUITE_RETRIES = 1
  EXPECTED_TEST_MODE_APPS = %w[
    SaneBar SaneClip SaneClick SaneHosts SaneSales SaneSync SaneVideo
  ].freeze
  RUNTIME_SMOKE_LOG_PATH = '/tmp/sanebar_runtime_smoke.log'
  RUNTIME_LAUNCH_LOG_PATH = '/tmp/sanebar_runtime_launch.log'
  RUNTIME_STARTUP_PROBE_LOG_PATH = '/tmp/sanebar_runtime_startup_probe.log'
  RUNTIME_STARTUP_PROBE_ARTIFACT_PATH = '/tmp/sanebar_runtime_startup_probe.json'
  RUNTIME_WAKE_PROBE_LOG_PATH = '/tmp/sanebar_runtime_wake_probe.log'
  RUNTIME_WAKE_PROBE_ARTIFACT_PATH = '/tmp/sanebar_runtime_wake_probe.json'
  RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
  RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH = '/tmp/sanebar_runtime_shared_bundle_fixture.log'
  RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH = '/tmp/SaneBarSharedFixture.app'
  RUNTIME_SHARED_BUNDLE_FIXTURE_SOURCE_PATH = '/tmp/sanebar_shared_fixture.swift'
  RUNTIME_SHARED_BUNDLE_FIXTURE_ID = 'com.sanebar.sharedfixture'
  RUNTIME_SHARED_BUNDLE_FIXTURE_IDS = %w[
    com.sanebar.sharedfixture::statusItem:0
    com.sanebar.sharedfixture::statusItem:1
    com.sanebar.sharedfixture::statusItem:2
  ].freeze
  RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH = '/tmp/sanebar_runtime_host_exact_id_fixture.log'
  RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH = '/tmp/SaneBarHostExactIDFixture.app'
  RUNTIME_HOST_EXACT_ID_FIXTURE_SOURCE_PATH = '/tmp/sanebar_host_exact_id_fixture.swift'
  RUNTIME_HOST_EXACT_ID_FIXTURE_ID = 'com.sanebar.hostsentinel'
  RUNTIME_HOST_EXACT_ID_FIXTURE_IDS = %w[
    com.sanebar.hostsentinel::statusItem:0
  ].freeze
  RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH = '/tmp/sanebar_runtime_dynamic_helper_fixture.log'
  RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH = '/tmp/SaneBarDynamicHelperFixture.app'
  RUNTIME_DYNAMIC_HELPER_FIXTURE_SOURCE_PATH = '/tmp/sanebar_dynamic_helper_fixture.swift'
  RUNTIME_DYNAMIC_HELPER_FIXTURE_ID = 'com.sindresorhus.Lungo-setapp'
  RUNTIME_DYNAMIC_HELPER_FIXTURE_IDS = %w[
    com.sindresorhus.Lungo-setapp::statusItem:0
  ].freeze
  RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH = '/tmp/sanebar_runtime_visible_dynamic_helper_fixture.log'
  RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH = '/tmp/SaneBarVisibleDynamicHelperFixture.app'
  RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_SOURCE_PATH = '/tmp/sanebar_visible_dynamic_helper_fixture.swift'
  RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_ID = 'com.ameba.SwiftBar'
  RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_IDS = %w[
    com.ameba.SwiftBar::statusItem:0
  ].freeze
  RUNTIME_NATIVE_APPLE_SMOKE_LOG_PATH = '/tmp/sanebar_runtime_native_apple_smoke.log'
  RUNTIME_HOST_EXACT_ID_SMOKE_LOG_PATH = '/tmp/sanebar_runtime_host_exact_id_smoke.log'
  RUNTIME_SMOKE_PASSES = 1
  RUNTIME_SMOKE_RETRIES_PER_PASS = 1
  RUNTIME_SMOKE_HEARTBEAT_SECONDS = 8
  RUNTIME_SHARED_BUNDLE_IDS = %w[
    com.apple.menuextra.wifi
    com.apple.menuextra.battery
    com.apple.menuextra.focusmode
    com.apple.menuextra.display
    com.apple.menuextra.controlcenter
    com.apple.menuextra.clock
  ].freeze
  RUNTIME_NATIVE_APPLE_IDS = %w[
    com.apple.menuextra.siri
    com.apple.menuextra.spotlight
  ].freeze
  RUNTIME_HOST_EXACT_ID_SENTINEL_IDS = %w[
    com.sanebar.hostsentinel::statusItem:0
    at.obdev.littlesnitch.networkmonitor
    at.obdev.littlesnitch.agent
  ].freeze
  OPEN_RELEASE_BLOCKING_LABELS = %w[
    bug
    high-priority
  ].freeze
  OPEN_RELEASE_BLOCKING_LABEL_PREFIXES = %w[
    root:
  ].freeze
  OPEN_RELEASE_BLOCKING_DISPOSITION_LABELS = %w[
    release:blocker
  ].freeze
  OPEN_RELEASE_NONBLOCKING_DISPOSITION_LABELS = %w[
    release:patched-pending
    release:compat-limited
    release:needs-evidence
    release:deferred
  ].freeze
  OPEN_REGRESSION_RELEASE_EVIDENCE_FILES = [
    File.join(PROJECT_ROOT, 'SESSION_HANDOFF.md'),
    File.join(PROJECT_ROOT, '.claude', 'research.md'),
    File.join(PROJECT_ROOT, 'DEVELOPMENT.md')
  ].freeze
  OPEN_REGRESSION_RELEASE_EVIDENCE_TTL_DAYS = 14
  OPEN_REGRESSION_ADDRESSING_PATTERNS = [
    /local root cause/i,
    /current patch/i,
    /current fix/i,
    /pending (?:build|release|patch)/i,
    /release candidate/i,
    /fix(?:es|ed)?\b/i,
    /address(?:es|ed|ing)?\b/i
  ].freeze
  OPEN_REGRESSION_PROOF_PATTERNS = [
    /current proof/i,
    /verification/i,
    /verified/i,
    /passed \d+ tests/i,
    /release preflight/i,
    /runtime smoke/i,
    /customer ui/i,
    /wake layout probe/i,
    /fullscreen/i,
    /mini\b/i
  ].freeze
  RUNTIME_SMOKE_MAX_CPU_PERCENT = 120.0
  RUNTIME_SMOKE_MAX_CPU_BREACH_SAMPLES = 4
  RUNTIME_SMOKE_EMERGENCY_CPU_PERCENT = 200.0
  RUNTIME_SMOKE_MAX_RSS_MB = 1024.0
  RUNTIME_SMOKE_MAX_RSS_BREACH_SAMPLES = 2
  RUNTIME_SMOKE_EMERGENCY_RSS_MB = 2048.0
  RUNTIME_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX = 5.0
  RUNTIME_SMOKE_LAUNCH_IDLE_CPU_PEAK_MAX = 15.0
  RUNTIME_SMOKE_LAUNCH_IDLE_RSS_MB_MAX = 128.0
  RUNTIME_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS = 15.0
  RUNTIME_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS = 4.0
  RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_AVG_MAX = 5.0
  RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX = 20.0
  RUNTIME_SMOKE_POST_SMOKE_IDLE_RSS_MB_MAX = 160.0
  RUNTIME_SMOKE_ACTIVE_AVG_CPU_MAX = 15.0
  RUNTIME_SMOKE_ACTIVE_AVG_RSS_MB_MAX = 192.0
  RECURRING_REGRESSION_TEST_MARKERS = {
    'Tests/IconMovingVisibleRegressionTests.swift' => [
      'REGRESSION: #93-style geometry avoids boundary-hugging target',
      'REGRESSION: Hidden→visible must use showAll(), not show()',
      'REGRESSION: Drag uses 20 steps, not 6'
    ],
    'Tests/SearchWindowDiscoveryTests.swift' => [
      'Move verification classification does not collapse always-hidden into hidden'
    ],
    'Tests/MenuBarSearchDropXCTests.swift' => [
      'testAllTabBoundaryPrefersSeparatorRightEdge',
      'testSourceResolutionUsesAllModeZoneClassifierOnFallback'
    ],
    'Tests/RuntimeGuardStartupRecoveryXCTests.swift' => [
      'testStartupHideContinuesWhenAccessibilityPermissionIsMissing'
    ],
    'Tests/RuntimeGuardQAAndLicensingXCTests.swift' => [
      'testIconPanelDoesNotForceAlwaysHiddenForFreeUsers'
    ],
    'Tests/RuntimeGuardQASmokeXCTests.swift' => [
      'Post-settle move verification drifted',
      'Hidden/Always Hidden round-trip ok'
    ],
    'Tests/RuntimeGuardMoveQueueXCTests.swift' => [
      'The move engine should keep queued zone-move planning'
    ],
    'Scripts/live_zone_smoke.rb' => [
      'assert_zone_stays_stable_after_move',
      'exercise_hidden_always_hidden_round_trip',
      'Post-settle move verification drifted',
      'Hidden/Always Hidden round-trip ok'
    ],
    'Tests/SecondMenuBarTests.swift' => [
      'Each item belongs to exactly one zone',
      'Duplicate pin is idempotent',
      'Item at separator edge respects margin'
    ],
    'Tests/ReleaseRegressionTests.swift' => [
      'Blocked versions are never offered in appcast',
      'Appcast newest entry matches current project marketing version'
    ]
  }.freeze
  RELEASE_SOAK_HOURS = 24
  REGRESSION_CONFIRMATION_WINDOW_HOURS = 48
  POST_CLOSE_REGRESSION_COMMENT_WINDOW_DAYS = 30

  def initialize
    @errors = []
    @warnings = []
  end

  def run
    puts '═══════════════════════════════════════════════════════════════'
    puts "                  #{PROJECT_NAME} QA Check"
    puts '═══════════════════════════════════════════════════════════════'
    puts

    check_sanemaster_wrapper
    check_script_syntax_rb
    check_script_syntax_swift
    check_script_syntax_sh
    check_code_rules
    check_version_consistency
    check_release_hygiene_guardrails
    check_saneui_guardrails
    check_appcast_guardrails
    check_appcast_download_urls
    check_migration_guardrails
    check_test_mode_tooling_guardrails
    check_runtime_release_smoke
    check_recurring_regression_coverage_guardrails
    check_release_cadence_guardrails
    check_open_regression_guardrails
    check_regression_confirmation_guardrails
    check_customer_facing_copy_guardrails
    run_stability_suite
    check_urls

    puts
    puts '═══════════════════════════════════════════════════════════════'

    exit_code = if @errors.empty? && @warnings.empty?
      puts '✅ All checks passed!'
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
    ENV['SANEPROCESS_RELEASE_PREFLIGHT'] == '1' ||
      ENV['SANEPROCESS_RUN_STABILITY_SUITE'] == '1' ||
      ENV['SANEBAR_RELEASE_PREFLIGHT'] == '1' ||
      ENV['SANEBAR_RUN_STABILITY_SUITE'] == '1'
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

  def runtime_smoke_host_allowed?
    running_on_mini_host? ||
      ENV['SANE_APPROVE_LOCAL_UI_ON_AIR'] == 'MR. SANE APPROVES LOCAL UI ON AIR'
  end

  def manual_override_phrase(gate:)
    'approved'
  end

  def legacy_manual_override_phrase(gate:)
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

  def manual_override_approved?(value, gate:, phrase:)
    normalized = value.to_s.strip.downcase
    normalized == phrase || normalized == legacy_manual_override_phrase(gate: gate).downcase
  end

  def request_manual_override(gate:, summary:)
    phrase = manual_override_phrase(gate: gate)

    env_override = manual_override_from_env(gate)
    return [true, phrase] if manual_override_approved?(env_override, gate: gate, phrase: phrase)

    return [false, phrase] unless $stdin.tty? && $stdout.tty?

    puts
    puts "⚠️  Manual approval required: #{summary}"
    puts 'Type exactly to continue:'
    puts phrase
    print '> '
    response = $stdin.gets&.strip

    [manual_override_approved?(response, gate: gate, phrase: phrase), phrase]
  end

  def manual_override_from_env(gate)
    case gate
    when :release_cadence
      ENV['SANEPROCESS_APPROVE_FAST_RELEASE'] || ENV['SANEBAR_APPROVE_FAST_RELEASE']
    when :open_regression_release
      ENV['SANEPROCESS_APPROVE_OPEN_REGRESSION_RELEASE'] || ENV['SANEBAR_APPROVE_OPEN_REGRESSION_RELEASE']
    when :unconfirmed_regression_close
      ENV['SANEPROCESS_APPROVE_UNCONFIRMED_REGRESSION_CLOSE'] || ENV['SANEBAR_APPROVE_UNCONFIRMED_REGRESSION_CLOSE']
    when :post_closure_regression_evidence
      ENV['SANEPROCESS_APPROVE_POST_CLOSURE_REGRESSION_EVIDENCE'] || ENV['SANEBAR_APPROVE_POST_CLOSURE_REGRESSION_EVIDENCE']
    else
      nil
    end
  end

  def check_sanemaster_wrapper
    print 'Checking SaneMaster wrapper... '

    unless File.exist?(SANEMASTER_CLI)
      @errors << 'SaneMaster.rb not found'
      puts '❌ Missing'
      return
    end

    # Verify wrapper syntax (it's a bash script)
    result = `bash -n #{SANEMASTER_CLI} 2>&1`
    unless $?.success?
      @errors << 'SaneMaster.rb has invalid bash syntax'
      puts '❌ Invalid syntax'
      return
    end

    # Verify it references SaneProcess infra
    content = File.read(SANEMASTER_CLI)
    unless content.include?('SaneProcess')
      @errors << 'SaneMaster.rb does not reference SaneProcess infra'
      puts '❌ Missing SaneProcess delegation'
      return
    end

    # Verify infra exists
    infra_path = File.expand_path(INFRA_SANEMASTER)
    unless File.exist?(infra_path)
      @warnings << "SaneProcess infra not found at #{infra_path}"
      puts '⚠️  Infra not found (standalone mode only)'
      return
    end

    # Verify standalone fallback exists
    unless File.exist?(SANEMASTER_STANDALONE)
      @errors << 'SaneMaster_standalone.rb not found'
      puts '❌ Missing standalone'
      return
    end

    result = `ruby -c #{SANEMASTER_STANDALONE} 2>&1`
    unless $?.success?
      @errors << 'SaneMaster_standalone.rb has invalid syntax'
      puts '❌ Standalone invalid'
      return
    end

    puts '✅ Wrapper + standalone + infra delegation OK'
  end

  def check_script_syntax_rb
    print 'Checking Ruby script syntax... '

    rb_files = Dir.glob(File.join(__dir__, '**', '*.rb'))
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
    print 'Checking Swift script syntax... '

    swift_files = Dir.glob(File.join(__dir__, '*.swift'))
    if swift_files.empty?
      puts '⚠️  No Swift scripts found'
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
    print 'Checking shell script syntax... '

    sh_files = Dir.glob(File.join(__dir__, '*.sh'))
    if sh_files.empty?
      puts '⚠️  No shell scripts found'
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
    print 'Checking .claude/rules/ ... '

    unless Dir.exist?(RULES_DIR)
      @warnings << '.claude/rules/ directory not found'
      puts '⚠️  Not found'
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
    print 'Checking version consistency... '

    versions = {}

    # Check project.yml for MARKETING_VERSION
    if File.exist?(PROJECT_YML)
      content = File.read(PROJECT_YML)
      if (match = content.match(/MARKETING_VERSION:\s*["']?(\d+\.\d+\.\d+)/))
        versions['project.yml'] = match[1]
      end
      if (match = content.match(/CURRENT_PROJECT_VERSION:\s*["']?(\d+)["']?/))
        versions['project.yml build'] = match[1]
      end
    end

    pbxproj = File.join(PROJECT_XCODEPROJ, 'project.pbxproj')
    if File.exist?(pbxproj)
      content = File.read(pbxproj)
      marketing_versions = content.scan(/MARKETING_VERSION\s*=\s*([0-9]+\.[0-9]+\.[0-9]+);/).flatten.uniq
      build_versions = content.scan(/CURRENT_PROJECT_VERSION\s*=\s*(\d+);/).flatten.uniq
      versions['xcodeproj'] = marketing_versions.join('/') unless marketing_versions.empty?
      versions['xcodeproj build'] = build_versions.join('/') unless build_versions.empty?
    end

    # Check README.md
    if File.exist?(README)
      content = File.read(README)
      if (match = content.match(/#{PROJECT_NAME}\s+v?(\d+\.\d+\.\d+)/i))
        versions['README.md'] = match[1]
      end
    end

    if versions.empty?
      @warnings << 'No version strings found in project.yml or README.md'
      puts '⚠️  No versions found'
      return
    end

    marketing_versions = versions.reject { |key, _| key.end_with?(' build') }
    build_versions = versions.select { |key, _| key.end_with?(' build') }
    unique_marketing_versions = marketing_versions.values.uniq
    unique_build_versions = build_versions.values.uniq
    if unique_marketing_versions.count <= 1 && unique_build_versions.count <= 1
      puts "✅ Version #{unique_marketing_versions.first || 'consistent'}"
    else
      details = versions.map { |f, v| "#{f}=v#{v}" }.join(', ')
      @errors << "Version mismatch: #{details}. Run xcodegen generate after bumping project.yml."
      puts "❌ Mismatch: #{details}"
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
      runtimeSmokeResourceWatchdog: {
        maxCpuPercent: RUNTIME_SMOKE_MAX_CPU_PERCENT,
        maxCpuBreachSamples: RUNTIME_SMOKE_MAX_CPU_BREACH_SAMPLES,
        emergencyCpuPercent: RUNTIME_SMOKE_EMERGENCY_CPU_PERCENT,
        maxRssMB: RUNTIME_SMOKE_MAX_RSS_MB,
        maxRssBreachSamples: RUNTIME_SMOKE_MAX_RSS_BREACH_SAMPLES,
        emergencyRssMB: RUNTIME_SMOKE_EMERGENCY_RSS_MB
      },
      runtimeSmokePerformanceBudget: {
        launchIdleCpuAvgMax: RUNTIME_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX,
        launchIdleCpuPeakMax: RUNTIME_SMOKE_LAUNCH_IDLE_CPU_PEAK_MAX,
        launchIdleRssMBMax: RUNTIME_SMOKE_LAUNCH_IDLE_RSS_MB_MAX,
        postSmokeIdleSettleSeconds: RUNTIME_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS,
        postSmokeIdleSampleSeconds: RUNTIME_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS,
        postSmokeIdleCpuAvgMax: RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_AVG_MAX,
        postSmokeIdleCpuPeakMax: RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX,
        postSmokeIdleRssMBMax: RUNTIME_SMOKE_POST_SMOKE_IDLE_RSS_MB_MAX,
        activeAvgCpuMax: RUNTIME_SMOKE_ACTIVE_AVG_CPU_MAX,
        activeAvgRssMBMax: RUNTIME_SMOKE_ACTIVE_AVG_RSS_MB_MAX
      },
      runtimeSmokeFocusedExactIdSets: [
        {
          lane: 'shared-bundle',
          requiredIds: RUNTIME_SHARED_BUNDLE_IDS,
          logPath: RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH
        },
        {
          lane: 'native-apple',
          requiredIds: RUNTIME_NATIVE_APPLE_IDS,
          logPath: RUNTIME_NATIVE_APPLE_SMOKE_LOG_PATH
        },
        {
          lane: 'host-exact-id',
          requiredIds: RUNTIME_HOST_EXACT_ID_SENTINEL_IDS,
          logPath: RUNTIME_HOST_EXACT_ID_SMOKE_LOG_PATH
        }
      ],
      errorCount: @errors.count,
      warningCount: @warnings.count,
      errors: @errors,
      warnings: @warnings
    }

    FileUtils.mkdir_p(File.dirname(QA_STATUS_PATH))
    File.write(QA_STATUS_PATH, JSON.pretty_generate(payload))
  rescue StandardError => e
    @warnings << "Failed to write QA status snapshot: #{e.message}"
  end
end


require_relative 'lib/project_qa_release_guardrails'
require_relative 'lib/project_qa_runtime_preflight'
require_relative 'lib/project_qa_runtime_fixtures'
require_relative 'lib/project_qa_runtime_visible_dynamic_fixture'
require_relative 'lib/project_qa_runtime_helpers'
require_relative 'lib/project_qa_regression_guardrails'
require_relative 'lib/project_qa_stability_urls'

# Run if executed directly
ProjectQA.new.run if __FILE__ == $PROGRAM_NAME
