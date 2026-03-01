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
  RECURRING_REGRESSION_TEST_MARKERS = {
    'Tests/IconMovingTests.swift' => [
      'REGRESSION: #93-style geometry avoids boundary-hugging target',
      'REGRESSION: Hidden→visible must use showAll(), not show()',
      'REGRESSION: Drag uses 16 steps, not 6',
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
    check_recurring_regression_coverage_guardrails
    check_release_cadence_guardrails
    check_open_regression_guardrails
    check_regression_confirmation_guardrails
    run_stability_suite
    check_urls

    puts
    puts "═══════════════════════════════════════════════════════════════"

    if @errors.empty? && @warnings.empty?
      puts "✅ All checks passed!"
      exit 0
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
        exit 1
      end

      exit 0
    end
  end

  private

  def preflight_mode?
    ENV['SANEBAR_RELEASE_PREFLIGHT'] == '1' || ENV['SANEBAR_RUN_STABILITY_SUITE'] == '1'
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
    trusted_associations = %w[MEMBER OWNER COLLABORATOR]
    confirmation_pattern = /(fixed|works|working now|resolved|confirmed|looks good|thank you)/i
    comments.any? do |comment|
      association = comment['authorAssociation'].to_s.upcase
      next false if trusted_associations.include?(association)

      body = comment['body'].to_s
      body.match?(confirmation_pattern)
    end
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
    regression_issues.each do |issue|
      details_json, details_status = Open3.capture2e(
        'gh', 'issue', 'view', issue['number'].to_s,
        '--repo', 'sane-apps/SaneBar',
        '--json', 'comments'
      )
      next unless details_status.success?

      comments = (JSON.parse(details_json)['comments'] rescue []) || []
      unconfirmed << issue['number'] unless reporter_confirmation?(comments)
    end

    if unconfirmed.empty?
      puts "✅ #{regression_issues.count} closed regression issue(s) have reporter confirmation"
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

        response = http.head(uri.request_uri)
        unless response.code.to_i < 400 || (response.code.to_i == 404 && entry[:url].include?('raw.githubusercontent'))
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
end

# Run if executed directly
ProjectQA.new.run if __FILE__ == $PROGRAM_NAME
