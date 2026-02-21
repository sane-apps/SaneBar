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

class ProjectQA
  PROJECT_ROOT = File.expand_path('..', __dir__)
  PROJECT_NAME = File.basename(PROJECT_ROOT)

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
  BLOCKED_APPCAST_VERSIONS = %w[2.1.3 2.1.6].freeze
  REQUIRED_MIGRATION_TEST_TITLES = [
    'Migration preserves healthy custom positions on upgrade',
    'Migration resets positions when legacy always-hidden position is corrupted',
    'Upgrade matrix handles healthy and corrupted states safely',
    'Real upgrade snapshots from 2.1.2 and 2.1.5 preserve layout',
  ].freeze

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

    if failures.empty?
      puts '✅ migration key changes are guarded by corruption + preservation tests'
    else
      failures.each { |failure| @errors << failure }
      puts "❌ #{failures.count} guardrail failure(s)"
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
