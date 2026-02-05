#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneMaster Standalone: Build & Development Tools for SaneBar
# ==============================================================================
# This standalone version runs when SaneProcess infra is not available
# (e.g. external contributors who cloned just SaneBar).
#
# Full version: ~/SaneApps/infra/SaneProcess/scripts/SaneMaster.rb
# ==============================================================================

require 'open3'
require 'json'

# Load all available modules from local sanemaster/
require_relative 'sanemaster/base'
require_relative 'sanemaster/memory'
require_relative 'sanemaster/dependencies'
require_relative 'sanemaster/generation'
require_relative 'sanemaster/diagnostics'
require_relative 'sanemaster/bootstrap'
require_relative 'sanemaster/test_mode'
require_relative 'sanemaster/verify'
require_relative 'sanemaster/quality'
require_relative 'sanemaster/sop_loop'
require_relative 'sanemaster/export'
require_relative 'sanemaster/md_export'
require_relative 'sanemaster/meta'
require_relative 'sanemaster/session'
require_relative 'sanemaster/circuit_breaker_state'

class SaneMaster
  include SaneMasterModules::Base
  include SaneMasterModules::Memory
  include SaneMasterModules::Dependencies
  include SaneMasterModules::Generation
  include SaneMasterModules::Diagnostics
  include SaneMasterModules::Bootstrap
  include SaneMasterModules::TestMode
  include SaneMasterModules::Verify
  include SaneMasterModules::Quality
  include SaneMasterModules::SOPLoop
  include SaneMasterModules::Export
  include SaneMasterModules::MdExport
  include SaneMasterModules::Meta
  include SaneMasterModules::Session

  COMMANDS = {
    build: {
      desc: 'Build, test, and validate code',
      commands: {
        'verify' => { args: '[--ui] [--clean]', desc: 'Build and run tests' },
        'clean' => { args: '[--nuclear]', desc: 'Wipe build cache and test states' },
        'lint' => { args: '', desc: 'Run SwiftLint and auto-fix issues' },
        'audit' => { args: '', desc: 'Scan for missing accessibility identifiers' }
      }
    },
    gen: {
      desc: 'Generate code, mocks, and assets',
      commands: {
        'gen_test' => { args: '[options]', desc: 'Generate test file from template' },
        'gen_mock' => { args: '', desc: 'Generate mocks using Mockolo' },
        'gen_assets' => { args: '', desc: 'Generate test video assets' }
      }
    },
    check: {
      desc: 'Static analysis and validation',
      commands: {
        'verify_api' => { args: '<API> [Framework]', desc: 'Verify API exists in SDK' },
        'dead_code' => { args: '', desc: 'Find unused code (Periphery)' },
        'deprecations' => { args: '', desc: 'Scan for deprecated API usage' },
        'swift6' => { args: '', desc: 'Verify Swift 6 concurrency compliance' },
        'check_docs' => { args: '', desc: 'Check docs are in sync with code' },
        'test_scan' => { args: '[-v]', desc: 'Scan tests for tautologies' }
      }
    },
    debug: {
      desc: 'Debugging and crash analysis',
      commands: {
        'test_mode' => { args: '(or tm)', desc: 'Kill → Build → Launch → Logs workflow' },
        'logs' => { args: '[--follow]', desc: 'Show application logs' },
        'launch' => { args: '', desc: 'Launch the app' },
        'crashes' => { args: '[--recent]', desc: 'Analyze crash reports' },
        'diagnose' => { args: '[path]', desc: 'Analyze .xcresult bundle' }
      }
    },
    env: {
      desc: 'Environment and setup',
      commands: {
        'doctor' => { args: '', desc: 'Check environment health' },
        'health' => { args: '', desc: 'Quick health check' },
        'meta' => { args: '', desc: 'Audit SaneMaster tooling itself' },
        'bootstrap' => { args: '[--check-only]', desc: 'Full environment setup' },
        'versions' => { args: '', desc: 'Check tool versions' }
      }
    },
    export: {
      desc: 'Export and documentation',
      commands: {
        'export' => { args: '[--highlight]', desc: 'Export code to PDF' },
        'md_export' => { args: '<file.md>', desc: 'Convert markdown to PDF' },
        'deps' => { args: '[--dot]', desc: 'Show dependency graph' }
      }
    }
  }.freeze

  QUICK_START = [
    { cmd: 'verify', desc: 'Build + run tests' },
    { cmd: 'test_mode', desc: 'Kill → Build → Launch → Logs' },
    { cmd: 'doctor', desc: 'Check environment health' },
    { cmd: 'export', desc: 'Export code to PDF' }
  ].freeze

  def initialize
    @bundle_id = detect_bundle_id
  end

  def detect_bundle_id
    # Try project.yml first (XcodeGen)
    if File.exist?('project.yml')
      begin
        require 'yaml'
        config = YAML.safe_load(File.read('project.yml'))
        bid = config.dig('settings', 'PRODUCT_BUNDLE_IDENTIFIER')
        return bid if bid

        config['targets']&.each do |_name, target|
          bid = target.dig('settings', 'PRODUCT_BUNDLE_IDENTIFIER')
          return bid if bid && !bid.include?('Tests')
        end
      rescue StandardError
        # Fall through
      end
    end

    # Try xcodeproj build settings
    xcodeprojs = Dir.glob('*.xcodeproj')
    if xcodeprojs.any?
      scheme = detect_scheme(xcodeprojs.first)
      output, status = Open3.capture2e('xcodebuild', '-project', xcodeprojs.first, '-scheme', scheme, '-showBuildSettings')
      if status.success? && output =~ /PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)/
        return ::Regexp.last_match(1)
      end
    end

    # Fallback
    "com.sanebar.app"
  end

  def detect_scheme(project_path)
    output, status = Open3.capture2e('xcodebuild', '-list', '-json', '-project', project_path)
    return File.basename(project_path, '.xcodeproj') unless status.success?

    json = JSON.parse(output)
    schemes = json.dig('project', 'schemes') || []
    schemes.find { |name| !name.include?('Tests') } || schemes.first || File.basename(project_path, '.xcodeproj')
  rescue JSON::ParserError, StandardError
    File.basename(project_path, '.xcodeproj')
  end

  def run(args)
    if args.empty?
      print_help
      return
    end

    command = args.shift

    if command == 'help'
      category = args.shift
      category ? print_category_help(category.to_sym) : print_help
      return
    end

    dispatch_command(command, args)
  end

  private

  def dispatch_command(command, args)
    case command
    # Build & Test
    when 'verify'          then verify(args)
    when 'clean'           then clean(args)
    when 'lint'            then run_lint
    when 'quality'         then run_quality_report
    when 'audit'           then audit_project

    # Environment
    when 'doctor'          then doctor
    when 'health', 'h'     then run_health(args)
    when 'meta'            then run_meta(args)
    when 'bootstrap', 'env' then run_bootstrap(args)
    when 'versions'        then check_latest_versions(args)

    # Diagnostics
    when 'diagnose'
      da = parse_diagnose_args(args)
      diagnose(da[:path], dump: da[:dump])
    when 'crashes'         then analyze_crashes(args)

    # Interactive
    when 'launch', 'run'   then launch_app(args)
    when 'logs'            then show_app_logs(args)
    when 'test_mode', 'tm' then enter_test_mode(args)

    # Permissions
    when 'reset'           then reset_permissions

    # Generation
    when 'gen_test'        then generate_test_file(args)
    when 'gen_mock'        then generate_mocks(args)
    when 'gen_assets'      then generate_test_assets
    when 'verify_api'      then verify_api(args)

    # Quality
    when 'dead_code'       then find_dead_code
    when 'deprecations'    then check_deprecations
    when 'swift6'          then swift6_check
    when 'test_scan'       then run_test_scan(args)
    when 'check_docs'      then verify_documentation_sync
    when 'check_binary'    then check_binary

    # Export
    when 'export', 'pdf'   then export_pdf(args)
    when 'md_export'       then export_markdown(args)
    when 'deps'            then show_dependency_graph(args)

    # Memory
    when 'mc'              then show_memory_context(args)

    # Circuit breaker
    when 'reset_breaker'   then SaneMasterModules::CircuitBreakerState.reset!

    # Not available in standalone
    when 'release'
      warn "❌ 'release' requires SaneProcess infrastructure."
      warn '   This command is not available in standalone mode.'
      exit 1

    else
      puts "❌ Unknown command: #{command}"
      print_help
    end
  end

  def parse_diagnose_args(args)
    path = nil
    dump = false
    args.each_with_index do |arg, i|
      if arg == '--path'
        path = args[i + 1]
      elsif arg == '--dump'
        dump = true
      elsif !arg.start_with?('-') && path.nil?
        path = arg
      end
    end
    { path: path, dump: dump }
  end

  def print_help
    puts <<~HEADER
      ┌─────────────────────────────────────────────────────────────┐
      │  SaneMaster - Build & Development Tools for SaneBar        │
      │  (standalone mode)                                         │
      └─────────────────────────────────────────────────────────────┘

      Quick Start:
    HEADER

    QUICK_START.each do |item|
      puts "        #{item[:cmd].ljust(12)} #{item[:desc]}"
    end

    puts "\n      Categories (use 'help <category>' for details):"
    puts '      ─────────────────────────────────────────────────'

    COMMANDS.each do |cat, data|
      cmd_list = data[:commands].keys.take(3).join(', ')
      cmd_list += ', ...' if data[:commands].size > 3
      puts "        #{cat.to_s.ljust(10)} #{data[:desc]}"
      puts "                   └─ #{cmd_list}"
    end

    puts <<~FOOTER

      Examples:
        ./scripts/SaneMaster.rb verify          # Build + test
        ./scripts/SaneMaster.rb help build      # Show build commands
        ./scripts/SaneMaster.rb doctor          # Check environment
    FOOTER
  end

  def print_category_help(category)
    unless COMMANDS.key?(category)
      puts "❌ Unknown category: #{category}"
      puts "   Available: #{COMMANDS.keys.join(', ')}"
      return
    end

    data = COMMANDS[category]
    puts "\n  #{category.to_s.upcase}: #{data[:desc]}\n\n"
    data[:commands].each do |cmd, info|
      args = info[:args].empty? ? '' : " #{info[:args]}"
      puts "    #{cmd}#{args}"
      puts "      #{info[:desc]}\n\n"
    end
  end
end

# --- Main Entry Point ---
SaneMaster.new.run(ARGV) if __FILE__ == $PROGRAM_NAME
