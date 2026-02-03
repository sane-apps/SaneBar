#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Project QA Script
# Automated product verification before release
#
# Usage: ruby scripts/qa.rb
#
# Checks:
# - All hooks exist and have valid Ruby syntax
# - init.sh downloads all hooks
# - README matches actual hook count
# - docs/SOP.md matches rule count
# - All URLs in docs are reachable
# - All hooks use stdin pattern (not ENV vars)
# - SaneMaster CLI and modules have valid syntax
# - Hook tests pass
#

require 'net/http'
require 'uri'
require 'json'

class ProjectQA
  # Auto-detect project name from directory
  PROJECT_ROOT = File.expand_path('..', __dir__)
  PROJECT_NAME = File.basename(PROJECT_ROOT)

  HOOKS_DIR = File.join(__dir__, 'hooks')
  INIT_SCRIPT = File.join(__dir__, 'init.sh')
  README = File.join(__dir__, '..', 'README.md')
  # Try project-specific SOP doc, fallback to generic
  SOP_DOC = Dir.glob(File.join(__dir__, '..', 'docs', '*.md')).first || File.join(__dir__, '..', 'docs', 'SOP.md')
  HOOKS_README = File.join(__dir__, 'hooks', 'README.md')
  SETTINGS_JSON = File.join(__dir__, '..', '.claude', 'settings.json')

  # Hooks that get registered in settings.json
  EXPECTED_HOOKS = %w[
    circuit_breaker.rb
    edit_validator.rb
    failure_tracker.rb
    test_quality_checker.rb
    path_rules.rb
    session_start.rb
    audit_logger.rb
    sop_mapper.rb
    two_fix_reminder.rb
    verify_reminder.rb
    version_mismatch.rb
    deeper_look_trigger.rb
    skill_validator.rb
    saneloop_enforcer.rb
    session_summary_validator.rb
    prompt_analyzer.rb
    pattern_learner.rb
    process_enforcer.rb
  ].freeze

  # Shared modules that hooks require (not registered, but must exist)
  SHARED_MODULES = %w[
    rule_tracker.rb
  ].freeze

  # All hook files that should exist
  ALL_HOOK_FILES = (EXPECTED_HOOKS + SHARED_MODULES).freeze

  EXPECTED_RULE_COUNT = 13

  SANEMASTER_CLI = File.join(__dir__, 'SaneMaster.rb')
  SANEMASTER_DIR = File.join(__dir__, 'sanemaster')

  EXPECTED_SANEMASTER_MODULES = %w[
    base.rb
    bootstrap.rb
    circuit_breaker_state.rb
    compliance_report.rb
    dependencies.rb
    diagnostics.rb
    export.rb
    generation.rb
    generation_mocks.rb
    generation_templates.rb
    md_export.rb
    memory.rb
    meta.rb
    quality.rb
    session.rb
    sop_loop.rb
    test_mode.rb
    verify.rb
  ].freeze

  def initialize
    @errors = []
    @warnings = []
    @skip_hooks_checks = false
  end

  def run
    puts "═══════════════════════════════════════════════════════════════"
    puts "                  #{PROJECT_NAME} QA Check"
    puts "═══════════════════════════════════════════════════════════════"
    puts

    check_hooks_exist
    check_hooks_syntax
    check_hooks_use_stdin
    check_hooks_registered
    check_sanemaster_syntax
    check_init_script
    check_readme_hook_count
    check_sop_doc_rule_count
    check_hooks_readme
    check_version_consistency
    check_urls
    run_hook_tests

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

  def check_hooks_exist
    print "Checking hooks exist... "

    unless Dir.exist?(HOOKS_DIR)
      @skip_hooks_checks = true
      @warnings << "Hooks managed by SaneProcess — skipping local hook checks"
      puts "⚠️  Hooks managed by SaneProcess"
      return
    end

    missing = ALL_HOOK_FILES.reject do |hook|
      File.exist?(File.join(HOOKS_DIR, hook))
    end

    if missing.empty?
      puts "✅ #{ALL_HOOK_FILES.count} hooks present"
    else
      @errors << "Missing hooks: #{missing.join(', ')}"
      puts "❌ Missing: #{missing.join(', ')}"
    end
  end

  def check_hooks_syntax
    return if @skip_hooks_checks

    print "Checking Ruby syntax... "

    invalid = []
    ALL_HOOK_FILES.each do |hook|
      path = File.join(HOOKS_DIR, hook)
      next unless File.exist?(path)

      result = `ruby -c #{path} 2>&1`
      invalid << hook unless $?.success?
    end

    if invalid.empty?
      puts "✅ All hooks have valid syntax"
    else
      @errors << "Invalid syntax in: #{invalid.join(', ')}"
      puts "❌ Invalid: #{invalid.join(', ')}"
    end
  end

  def check_hooks_use_stdin
    return if @skip_hooks_checks

    print "Checking hooks use stdin for input... "

    uses_env_for_input = []
    EXPECTED_HOOKS.each do |hook|
      path = File.join(HOOKS_DIR, hook)
      next unless File.exist?(path)

      content = File.read(path)
      # Check for deprecated patterns: ENV['CLAUDE_TOOL_INPUT'] or ENV['CLAUDE_TOOL_OUTPUT']
      # These should use stdin instead. CLAUDE_PROJECT_DIR and CLAUDE_SESSION_ID are OK.
      if content.match?(/ENV\[['"]CLAUDE_TOOL_INPUT/) ||
         content.match?(/ENV\.fetch\(['"]CLAUDE_TOOL_INPUT/) ||
         content.match?(/ENV\[['"]CLAUDE_TOOL_OUTPUT/) ||
         content.match?(/ENV\.fetch\(['"]CLAUDE_TOOL_OUTPUT/)
        uses_env_for_input << hook
      end
    end

    if uses_env_for_input.empty?
      puts "✅ All hooks use stdin"
    else
      @errors << "Hooks using ENV for tool input (should use stdin): #{uses_env_for_input.join(', ')}"
      puts "❌ Using ENV for input: #{uses_env_for_input.join(', ')}"
    end
  end

  def check_hooks_registered
    return if @skip_hooks_checks

    print "Checking hooks registered in settings.json... "

    unless File.exist?(SETTINGS_JSON)
      @errors << "settings.json not found"
      puts "❌ Missing"
      return
    end

    begin
      settings = JSON.parse(File.read(SETTINGS_JSON))
    rescue JSON::ParserError => e
      @errors << "settings.json is invalid JSON: #{e.message}"
      puts "❌ Invalid JSON"
      return
    end

    hooks_section = settings['hooks'] || {}

    # Extract all hook commands from settings.json
    registered_hooks = []
    %w[UserPromptSubmit SessionStart PreToolUse PostToolUse].each do |hook_type|
      entries = hooks_section[hook_type] || []
      entries.each do |entry|
        hook_list = entry['hooks'] || []
        hook_list.each do |hook|
          command = hook['command'] || ''
          # Extract hook filename from command like: ruby "$CLAUDE_PROJECT_DIR"/scripts/hooks/circuit_breaker.rb
          if (match = command.match(%r{hooks/([^/\s"]+\.rb)}))
            registered_hooks << match[1]
          end
        end
      end
    end

    registered_hooks.uniq!

    # Check which expected hooks are NOT registered
    not_registered = EXPECTED_HOOKS - registered_hooks

    if not_registered.empty?
      puts "✅ All #{EXPECTED_HOOKS.count} hooks registered"
    else
      @errors << "Hooks NOT registered in settings.json (invisible!): #{not_registered.join(', ')}"
      puts "❌ Not registered: #{not_registered.join(', ')}"
    end
  end

  def check_sanemaster_syntax
    print "Checking SaneMaster syntax... "

    invalid = []

    # Check main CLI
    if File.exist?(SANEMASTER_CLI)
      first_line = File.open(SANEMASTER_CLI, &:readline).strip rescue ''
      if first_line.start_with?('#!/bin/bash', '#!/usr/bin/env bash', '#!/bin/sh', '#!/usr/bin/env sh')
        result = `bash -n #{SANEMASTER_CLI} 2>&1`
        invalid << 'SaneMaster.rb (bash)' unless $?.success?
      else
        result = `ruby -c #{SANEMASTER_CLI} 2>&1`
        invalid << 'SaneMaster.rb' unless $?.success?
      end
    else
      @errors << "SaneMaster.rb not found"
      puts "❌ Missing"
      return
    end

    # Check all modules exist and have valid syntax
    missing_modules = []
    EXPECTED_SANEMASTER_MODULES.each do |mod|
      path = File.join(SANEMASTER_DIR, mod)
      unless File.exist?(path)
        missing_modules << mod
        next
      end

      result = `ruby -c #{path} 2>&1`
      invalid << mod unless $?.success?
    end

    if missing_modules.any?
      @errors << "Missing SaneMaster modules: #{missing_modules.join(', ')}"
      puts "❌ Missing modules: #{missing_modules.join(', ')}"
      return
    end

    if invalid.empty?
      puts "✅ SaneMaster + #{EXPECTED_SANEMASTER_MODULES.count} modules valid"
    else
      @errors << "Invalid syntax in SaneMaster: #{invalid.join(', ')}"
      puts "❌ Invalid: #{invalid.join(', ')}"
    end
  end

  def check_init_script
    return if @skip_hooks_checks

    print "Checking init.sh... "

    unless File.exist?(INIT_SCRIPT)
      @errors << "init.sh not found"
      puts "❌ Missing"
      return
    end

    content = File.read(INIT_SCRIPT)

    # Extract hooks from the HOOKS array in init.sh
    hooks_match = content.match(/HOOKS=\(\s*([\s\S]*?)\s*\)/)
    unless hooks_match
      @errors << "init.sh: Cannot find HOOKS array"
      puts "❌ HOOKS array not found"
      return
    end

    # Parse the hooks list
    init_hooks = hooks_match[1].scan(/"([^"]+)"/).flatten

    missing = ALL_HOOK_FILES - init_hooks
    extra = init_hooks - ALL_HOOK_FILES

    if missing.empty? && extra.empty?
      puts "✅ init.sh lists all #{ALL_HOOK_FILES.count} hooks"
    else
      @errors << "init.sh missing: #{missing.join(', ')}" unless missing.empty?
      @warnings << "init.sh has extra: #{extra.join(', ')}" unless extra.empty?
      puts "❌ Mismatch (missing: #{missing.count}, extra: #{extra.count})"
    end
  end

  def check_readme_hook_count
    return if @skip_hooks_checks

    print "Checking README.md hook count... "

    unless File.exist?(README)
      @warnings << "README.md not found"
      puts "⚠️  Not found"
      return
    end

    content = File.read(README)

    # Look for patterns like "11 SOP enforcement hooks" or "11 production-ready hooks"
    hook_counts = content.scan(/(\d+)\s+(?:SOP enforcement |production-ready )?hooks?/i).flatten.map(&:to_i)

    if hook_counts.empty?
      @warnings << "README.md: No hook count found"
      puts "⚠️  No count found"
      return
    end

    wrong_counts = hook_counts.reject { |c| c == ALL_HOOK_FILES.count }
    if wrong_counts.empty?
      puts "✅ Hook count correct (#{ALL_HOOK_FILES.count})"
    else
      @errors << "README.md says #{wrong_counts.first} hooks, should be #{ALL_HOOK_FILES.count}"
      puts "❌ Says #{wrong_counts.first}, should be #{ALL_HOOK_FILES.count}"
    end
  end

  def check_sop_doc_rule_count
    sop_basename = File.basename(SOP_DOC)
    print "Checking docs/#{sop_basename} rule count... "

    unless File.exist?(SOP_DOC)
      @warnings << "docs/#{sop_basename} not found"
      puts "⚠️  Not found"
      return
    end

    content = File.read(SOP_DOC)

    # Look for "13 Golden Rules" or "11 Golden Rules"
    rule_counts = content.scan(/(\d+)\s+Golden Rules?/i).flatten.map(&:to_i)

    if rule_counts.empty?
      @warnings << "docs/#{sop_basename}: No rule count found"
      puts "⚠️  No count found"
      return
    end

    wrong_counts = rule_counts.reject { |c| c == EXPECTED_RULE_COUNT }
    if wrong_counts.empty?
      puts "✅ Rule count correct (#{EXPECTED_RULE_COUNT})"
    else
      @errors << "#{sop_basename} says #{wrong_counts.first} rules, should be #{EXPECTED_RULE_COUNT}"
      puts "❌ Says #{wrong_counts.first}, should be #{EXPECTED_RULE_COUNT}"
    end
  end

  def check_hooks_readme
    return if @skip_hooks_checks

    print "Checking hooks/README.md... "

    unless File.exist?(HOOKS_README)
      @warnings << "hooks/README.md not found"
      puts "⚠️  Not found"
      return
    end

    content = File.read(HOOKS_README)

    # Check each expected hook is mentioned
    missing = ALL_HOOK_FILES.reject do |hook|
      content.include?(hook)
    end

    if missing.empty?
      puts "✅ All hooks documented"
    else
      @errors << "hooks/README.md missing: #{missing.join(', ')}"
      puts "❌ Missing docs: #{missing.join(', ')}"
    end
  end

  def check_version_consistency
    print "Checking version consistency... "

    versions = {}

    # Check README.md
    if File.exist?(README)
      content = File.read(README)
      if (match = content.match(/#{PROJECT_NAME} v(\d+\.\d+)/i))
        versions['README.md'] = match[1]
      end
    end

    # Check SOP doc
    if File.exist?(SOP_DOC)
      content = File.read(SOP_DOC)
      if (match = content.match(/#{PROJECT_NAME} v(\d+\.\d+)/i))
        versions[File.basename(SOP_DOC)] = match[1]
      end
    end

    # Check init.sh
    if File.exist?(INIT_SCRIPT)
      content = File.read(INIT_SCRIPT)
      if (match = content.match(/Version (\d+\.\d+)/i))
        versions['init.sh'] = match[1]
      end
    end

    if versions.empty?
      @warnings << "No version strings found"
      puts "⚠️  No versions found"
      return
    end

    unique_versions = versions.values.uniq
    if unique_versions.count == 1
      puts "✅ All files at v#{unique_versions.first}"
    else
      details = versions.map { |f, v| "#{f}=v#{v}" }.join(', ')
      @errors << "Version mismatch: #{details}"
      puts "❌ Mismatch: #{details}"
    end
  end

  def check_urls
    print "Checking URLs in docs... "

    urls_to_check = []

    # Collect URLs from key files
    [README, SOP_DOC, File.join(__dir__, '..', '.claude', 'SOP_CONTEXT.md')].each do |file|
      next unless File.exist?(file)

      content = File.read(file)
      # Extract URLs
      content.scan(%r{https?://[^\s\)\]"']+}).each do |url|
        # Skip localhost, example.com, placeholder URLs
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
        # Accept 2xx, 3xx, 404 for GitHub raw URLs that may not exist yet
        unless response.code.to_i < 400 || (response.code.to_i == 404 && entry[:url].include?('raw.githubusercontent'))
          bad_urls << "#{entry[:url]} (#{response.code}) in #{entry[:file]}"
        end
      rescue StandardError => e
        bad_urls << "#{entry[:url]} (#{e.class.name}) in #{entry[:file]}"
      end
    end

    if bad_urls.empty?
      puts "✅ #{urls_to_check.count} URLs reachable"
    else
      bad_urls.each { |u| @warnings << "Unreachable URL: #{u}" }
      puts "⚠️  #{bad_urls.count} unreachable"
    end
  end

  def run_hook_tests
    return if @skip_hooks_checks

    print "Running hook tests... "

    test_file = File.join(HOOKS_DIR, 'test', 'hook_test.rb')
    unless File.exist?(test_file)
      @warnings << "Hook tests not found at #{test_file}"
      puts "⚠️  Tests not found"
      return
    end

    result = `ruby #{test_file} 2>&1`
    if $?.success?
      # Extract test count from output
      if result.match?(/(\d+) tests.*0 failures/)
        puts "✅ All tests pass"
      else
        puts "✅ Tests pass"
      end
    else
      @errors << "Hook tests failed"
      puts "❌ Tests failed"
      puts result.lines.last(5).join if result.lines.count > 0
    end
  end
end

# Run if executed directly
ProjectQA.new.run if __FILE__ == $PROGRAM_NAME
