#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneMaster: Professional Automation Suite for SaneBar
# ==============================================================================
# Modular architecture - see Scripts/sanemaster/ for implementations:
#   base.rb        - Shared constants and utilities
#   memory.rb      - Memory MCP integration
#   dependencies.rb - Version checking, dependency graphs
#   generation.rb   - Test/mock generation, templates
#   diagnostics.rb  - Crash analysis, xcresult diagnosis
#   bootstrap.rb    - Environment setup, auto-update
#   test_mode.rb    - Interactive debugging workflow
#   verify.rb       - Build, test execution, permissions
#   quality.rb      - Dead code, deprecations, Swift 6 compliance
# ==============================================================================

# Load all modules
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

  # ═══════════════════════════════════════════════════════════════════════════
  # COMMAND REFERENCE - Organized by category for easy discovery
  # ═══════════════════════════════════════════════════════════════════════════
  COMMANDS = {
    build: {
      desc: 'Build, test, and validate code',
      commands: {
        'verify' => { args: '[--ui] [--clean]', desc: 'Build and run tests (unit by default, --ui for UI)' },
        'clean' => { args: '[--nuclear]', desc: 'Wipe build cache and test states' },
        'lint' => { args: '', desc: 'Run SwiftLint and auto-fix issues' },
        'audit' => { args: '', desc: 'Scan for missing accessibility identifiers' }
      }
    },
    gen: {
      desc: 'Generate code and mocks',
      commands: {
        'gen_test' => { args: '[options]', desc: 'Generate test file from template' },
        'gen_mock' => { args: '', desc: 'Generate mocks using Mockolo' },
        'template' => { args: '[save|apply|list] [name]', desc: 'Manage configuration templates' }
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
        'check_binary' => { args: '', desc: 'Audit binary for security issues' }
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
        'health' => { args: '', desc: 'Quick health check (< 100ms)' },
        'meta' => { args: '', desc: 'Audit SaneMaster tooling itself' },
        'bootstrap' => { args: '[--check-only]', desc: 'Full environment setup' },
        'setup' => { args: '', desc: 'Install gems and dependencies' },
        'versions' => { args: '', desc: 'Check tool versions' },
        'reset' => { args: '', desc: 'Reset TCC permissions' },
        'restore' => { args: '', desc: 'Fix Xcode/Launch Services issues' },
        'clean_system' => { args: '[--dry-run]', desc: 'Remove orphaned UserDefaults, stale DerivedData, mounted DMGs' }
      }
    },
    memory: {
      desc: 'Cross-session memory (MCP)',
      commands: {
        'mc' => { args: '', desc: 'Show memory context' },
        'mr' => { args: '<type> <name>', desc: 'Record new entity' },
        'mp' => { args: '[--dry-run]', desc: 'Prune stale entities' },
        'mh' => { args: '', desc: 'Memory health check (entity/token counts)' },
        'mcompact' => { args: '[--dry-run] [--aggressive]', desc: 'Compact memory (trim verbose, dedupe)' },
        'mcleanup' => { args: '(pipe JSON)', desc: 'Analyze MCP memory, generate cleanup commands' },
        'session_end' => { args: '[--skip-prompts]', desc: 'End session with insight extraction' },
        'reset_breaker' => { args: '', desc: 'Reset circuit breaker (unblock tools)' },
        'breaker_status' => { args: '', desc: 'Show circuit breaker status' },
        'breaker_errors' => { args: '', desc: 'Show recent failure messages' }
      }
    },
    export: {
      desc: 'Export and documentation',
      commands: {
        'export' => { args: '[--highlight]', desc: 'Export code to PDF (~/Downloads)' },
        'md_export' => { args: '<file.md>', desc: 'Convert markdown to PDF' },
        'deps' => { args: '[--dot]', desc: 'Show dependency graph' },
        'quality' => { args: '', desc: 'Generate Ruby quality report' }
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
    @bundle_id = resolve_bundle_id
  end

  def resolve_bundle_id
    env_id = ENV['SANEBAR_BUNDLE_ID']
    return env_id if env_id && !env_id.empty?

    project_yml = File.join(Dir.pwd, 'project.yml')
    return 'com.sanebar.app' unless File.exist?(project_yml)

    begin
      data = YAML.load_file(project_yml)
      debug_id = data.dig('targets', 'SaneBar', 'settings', 'configs', 'Debug', 'PRODUCT_BUNDLE_IDENTIFIER')
      base_id = data.dig('targets', 'SaneBar', 'settings', 'base', 'PRODUCT_BUNDLE_IDENTIFIER')
      debug_id || base_id || 'com.sanebar.app'
    rescue StandardError
      'com.sanebar.app'
    end
  end

  def run(args)
    if args.empty?
      print_help
      return
    end

    command = args.shift

    # Handle 'help <category>' specially
    if command == 'help'
      category = args.shift
      if category
        print_category_help(category.to_sym)
      else
        print_help
      end
      return
    end

    dispatch_command(command, args)
  end

  private

  def dispatch_command(command, args)
    # Check for --help flag on any command
    if args.include?('--help') || args.include?('-h')
      print_command_detail(command)
      return
    end

    case command
    # Diagnostics
    when 'diagnose'
      diagnose_args = parse_diagnose_args(args)
      diagnose(diagnose_args[:path], dump: diagnose_args[:dump])
    when 'crash_report', 'crashes'
      analyze_crashes(args)

    # Environment & Health
    when 'doctor'
      doctor
    when 'health', 'h'
      run_health(args)
    when 'meta', 'tooling', 'audit-self'
      run_meta(args)
    when 'bootstrap', 'preflight', 'env'
      run_bootstrap(args)
    when 'setup'
      setup_environment
    when 'restore'
      restore_xcode
    when 'clean_system', 'cs'
      clean_system(args)

    # Build & Test
    when 'verify'
      verify(args)
    when 'clean'
      clean(args)
    when 'lint'
      run_lint
    when 'quality'
      run_quality_report
    when 'audit'
      audit_project
    when 'validate_test_references', 'validate-tests'
      validate_test_references

    # Permissions
    when 'reset'
      reset_permissions
    when 'check_permissions'
      check_permission_status

    # Generation & Verification
    when 'gen_test'
      generate_test_file(args)
    when 'gen_mock'
      generate_mocks(args)
    when 'check_xcodegen'
      check_xcodegen(args)
    when 'verify_api'
      verify_api(args)
    when 'verify_mocks'
      verify_mocks
    when 'check_protocol_changes'
      check_protocol_changes(args)
    when 'check_docs'
      verify_documentation_sync
    when 'template'
      manage_templates(args)

    # Quality Analysis
    when 'dead_code', 'find_dead_code'
      find_dead_code
    when 'check_deprecations', 'deprecations'
      check_deprecations
    when 'swift6_check', 'swift6', 'concurrency_check'
      swift6_check
    when 'test_suite', 'suite'
      run_test_suite(args)
    when 'check_binary'
      check_binary

    # Dependencies & Versions
    when 'version_check', 'versions'
      check_latest_versions(args)
    when 'deps', 'dependencies'
      show_dependency_graph(args)
    when 'verify_mcps'
      verify_mcps

    # Interactive Debugging
    when 'launch', 'run'
      launch_app(args)
    when 'logs'
      show_app_logs(args)
    when 'test_mode', 'tm'
      enter_test_mode(args)

    # Memory MCP
    when 'memory_context', 'mc'
      show_memory_context(args)
    when 'memory_record', 'mr'
      record_memory_entity(args)
    when 'memory_prune', 'mp'
      prune_memory_entities(args)
    when 'memory_health', 'mh'
      memory_health(args)
    when 'memory_compact', 'mcompact'
      memory_compact(args)
    when 'memory_cleanup', 'mcleanup'
      memory_cleanup(args)
    when 'session_end', 'se'
      session_end(args)
    when 'reset_breaker', 'rb'
      SaneMasterModules::CircuitBreakerState.reset!
    when 'breaker_status', 'bs'
      show_breaker_status
    when 'breaker_errors', 'be'
      show_breaker_errors
    when 'compliance', 'cr'
      require_relative 'sanemaster/compliance_report'
      SaneMasterModules::ComplianceReport.generate

    # SOP Loop (Two-Fix Rule Compliant)
    when 'verify_gate', 'vg'
      verify_gate(args)
    when 'sop_loop', 'sop'
      start_sop_loop(args)
    when 'reset_escalation', 're'
      reset_escalation(args)

    # Debug Console
    when 'console'
      require 'pry'
      # rubocop:disable Lint/Debugger
      binding.pry
    # rubocop:enable Lint/Debugger

    # Export
    when 'export', 'pdf', 'export_pdf'
      export_pdf(args)
    when 'md_export', 'mdpdf'
      export_markdown(args)

    else
      puts "❌ Unknown command: #{command}"
      print_help
    end
  end

  def show_breaker_status
    status = SaneMasterModules::CircuitBreakerState.status
    puts '🔌 --- [ CIRCUIT BREAKER STATUS ] ---'
    puts ''
    if status[:status] == 'OPEN'
      puts "   Status: 🔴 #{status[:status]} (TOOLS BLOCKED)"
      puts "   #{status[:message]}"
      puts "   Reason: #{status[:trip_reason]}" if status[:trip_reason]
      puts "   Blocked: #{status[:blocked_tools].join(', ')}"
      puts ''
      puts '   To see errors: ./Scripts/SaneMaster.rb breaker_errors'
      puts '   To reset: ./Scripts/SaneMaster.rb reset_breaker'
    else
      puts "   Status: 🟢 #{status[:status]}"
      puts "   #{status[:message]}"
    end
    puts ''
  end

  def show_breaker_errors
    state = SaneMasterModules::CircuitBreakerState.load_state
    puts '🔌 --- [ CIRCUIT BREAKER ERRORS ] ---'
    puts ''

    messages = state[:failure_messages] || []
    if messages.empty?
      puts '   No failure messages recorded.'
    else
      puts "   Recent failures (#{messages.count}):"
      puts ''
      messages.each_with_index do |msg, i|
        puts "   #{i + 1}. #{msg}"
      end
    end

    # Show error signatures if any
    signatures = state[:error_signatures] || {}
    if signatures.any?
      puts ''
      puts '   Error patterns detected:'
      signatures.sort_by { |_, v| -v }.first(5).each do |sig, count|
        puts "   - #{count}x: #{sig[0, 60]}#{'...' if sig.length > 60}"
      end
    end

    puts ''
    puts '   Use this information to research the problem and create a plan.'
    puts ''
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

  def check_binary
    puts '🛡️ --- [ SANEMASTER BINARY AUDIT ] ---'

    puts 'Searching for production binary...'
    build_settings = `xcodebuild -scheme SaneBar -showBuildSettings 2>/dev/null`
    target_build_dir = build_settings.match(/TARGET_BUILD_DIR = (.*)/)&.[](1)
    executable_path = build_settings.match(/EXECUTABLE_PATH = (.*)/)&.[](1)

    unless target_build_dir && executable_path
      puts '❌ Error: Could not determine binary path. Build the app first.'
      return
    end

    full_path = File.join(target_build_dir, executable_path)
    unless File.exist?(full_path)
      puts "❌ Error: Binary not found at #{full_path}. Run 'SaneMaster verify' first."
      return
    end

    audit_binary_symbols(full_path)
    audit_binary_architectures(full_path)

    puts '✅ Binary audit complete.'
  end

  def audit_binary_symbols(full_path)
    print '  Checking for debug symbols... '
    `nm -u "#{full_path}" 2>&1`
    debug_indicators = `nm "#{full_path}" 2>&1`

    if debug_indicators.include?('DEBUG') || debug_indicators.include?('assertions')
      puts '⚠️  POTENTIAL UNSTRIPPED SYMBOLS FOUND'
    else
      puts '✅'
    end
  end

  def audit_binary_architectures(full_path)
    print '  Verifying architectures... '
    archs = `lipo -info "#{full_path}"`
    puts "✅ (#{archs.strip.split(': ').last})"
  end

  def print_help
    puts <<~HEADER
      ┌─────────────────────────────────────────────────────────────┐
      │  SaneMaster - Professional Automation Suite for SaneBar    │
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
        ./Scripts/SaneMaster.rb verify          # Build + test
        ./Scripts/SaneMaster.rb help build      # Show build commands
        ./Scripts/SaneMaster.rb help check      # Show analysis commands

      Aliases: sm = ./Scripts/SaneMaster.rb (if configured)
    FOOTER
  end

  def print_category_help(category)
    unless COMMANDS.key?(category)
      puts "❌ Unknown category: #{category}"
      puts "   Available: #{COMMANDS.keys.join(', ')}"
      return
    end

    data = COMMANDS[category]
    puts <<~HEADER
      ┌─────────────────────────────────────────────────────────────┐
      │  #{category.to_s.upcase.center(57)}  │
      │  #{data[:desc].center(57)}  │
      └─────────────────────────────────────────────────────────────┘

      Commands:
    HEADER

    data[:commands].each do |cmd, info|
      args = info[:args].empty? ? '' : " #{info[:args]}"
      puts "        #{cmd}#{args}"
      puts "          #{info[:desc]}"
      puts
    end
  end

  # Extended help information for each command
  # rubocop:disable Lint/UselessConstantScoping
  COMMAND_DETAILS = {
    'verify' => {
      usage: 'verify [--ui] [--clean]',
      description: 'Build the project and run tests',
      flags: {
        '--ui' => 'Run UI tests instead of unit tests',
        '--clean' => 'Clean build before testing'
      },
      examples: [
        'verify           # Run unit tests',
        'verify --ui      # Run UI tests',
        'verify --clean   # Clean build first'
      ]
    },
    'clean' => {
      usage: 'clean [--nuclear]',
      description: 'Wipe build cache and test state files',
      flags: {
        '--nuclear' => 'Also remove DerivedData and reset Xcode state'
      },
      examples: ['clean', 'clean --nuclear']
    },
    'test_mode' => {
      usage: 'test_mode (or tm) [--fresh]',
      description: 'Interactive debugging workflow: Kill → Build → Launch → Logs',
      flags: {
        '--fresh' => 'Clear all app data, settings, and UserDefaults before launching'
      },
      examples: ['test_mode', 'tm --fresh']
    },
    'launch' => {
      usage: 'launch [--fresh] [--force] [--logs]',
      description: 'Launch the application',
      flags: {
        '--fresh' => 'Clear all app data, settings, and UserDefaults before launching',
        '--force' => 'Skip stale build detection',
        '--logs' => 'Capture logs to stdout (blocks)'
      },
      examples: ['launch', 'launch --fresh']
    },
    'doctor' => {
      usage: 'doctor',
      description: 'Check environment health and tool versions',
      flags: {},
      examples: ['doctor']
    },
    'export' => {
      usage: 'export [--highlight] [--include-tests] [--output <dir>]',
      description: 'Export source code to PDF for review',
      flags: {
        '--highlight' => 'Enable syntax highlighting (larger file)',
        '--include-tests' => 'Include test files in export',
        '--output <dir>' => 'Custom output directory (default: ~/Downloads)'
      },
      examples: [
        'export                    # Basic export',
        'export --highlight        # With syntax highlighting',
        'export --include-tests    # Include test files'
      ]
    },
    'gen_test' => {
      usage: 'gen_test <name> [--type <unit|ui>] [--target <class>] [--async]',
      description: 'Generate test file from template',
      flags: {
        '--type' => 'Test type: unit (default) or ui',
        '--framework' => 'Testing framework: testing (default) or xctest',
        '--target' => 'Target class/service to test',
        '--async' => 'Include async/await patterns'
      },
      examples: [
        'gen_test MyFeatureTests --target MyFeature',
        'gen_test MyTests --async --framework xctest'
      ]
    },
    'gen_mock' => {
      usage: 'gen_mock [--target <dir>] [--protocol <name>]',
      description: 'Generate mocks using Mockolo',
      flags: {
        '--target' => 'Generate for all protocols in directory',
        '--protocol' => 'Generate for specific protocol',
        '--output' => 'Output directory (default: Tests/Mocks)'
      },
      examples: [
        'gen_mock --target Services/Camera',
        'gen_mock --protocol CameraServiceProtocol'
      ]
    },
    'verify_api' => {
      usage: 'verify_api <APIName> [Framework]',
      description: 'Verify API exists in macOS SDK',
      flags: {},
      examples: [
        'verify_api faceCaptureQuality Vision',
        'verify_api SCContentSharingPicker ScreenCaptureKit'
      ]
    },
    'dead_code' => {
      usage: 'dead_code',
      description: 'Find unused code using Periphery',
      flags: {},
      examples: ['dead_code']
    },
    'swift6' => {
      usage: 'swift6',
      description: 'Check Swift 6 concurrency compliance',
      flags: {},
      examples: ['swift6']
    },
    'logs' => {
      usage: 'logs [--follow]',
      description: 'Show application logs',
      flags: {
        '--follow' => 'Stream logs in real-time'
      },
      examples: ['logs', 'logs --follow']
    },
    'crashes' => {
      usage: 'crashes [--recent]',
      description: 'Analyze crash reports',
      flags: {
        '--recent' => 'Show only recent crashes'
      },
      examples: ['crashes', 'crashes --recent']
    },
    'mc' => {
      usage: 'mc',
      description: 'Show current Memory MCP context',
      flags: {},
      examples: ['mc']
    },
    'mr' => {
      usage: 'mr <type> <name>',
      description: 'Record new entity to Memory MCP',
      flags: {},
      examples: ['mr bug CrashOnExport', 'mr fix AudioSyncIssue']
    },
    'deps' => {
      usage: 'deps [--dot]',
      description: 'Show dependency graph',
      flags: {
        '--dot' => 'Output in DOT format for visualization'
      },
      examples: ['deps', 'deps --dot > graph.dot']
    },
    'session_end' => {
      usage: 'session_end [--skip-prompts]',
      description: 'End session with insight extraction (inspired by Auto-Claude)',
      flags: {
        '--skip-prompts' => 'Skip interactive prompts, show summary only'
      },
      examples: ['session_end', 'se', 'session_end --skip-prompts']
    }
  }.freeze
  # rubocop:enable Lint/UselessConstantScoping

  def print_command_detail(command)
    # Find command info from COMMANDS hash
    cmd_info = nil
    category = nil
    COMMANDS.each do |cat, data|
      data[:commands].each do |cmd, info|
        next unless cmd == command

        cmd_info = info
        category = cat
        break
      end
      break if cmd_info
    end

    # Check for alias mappings
    aliases = {
      'tm' => 'test_mode', 'crashes' => 'crash_report', 'versions' => 'version_check',
      'deprecations' => 'check_deprecations', 'pdf' => 'export'
    }
    command = aliases[command] if aliases.key?(command)

    details = COMMAND_DETAILS[command]

    puts <<~HEADER
      ┌─────────────────────────────────────────────────────────────┐
      │  #{command.upcase.center(57)}  │
      └─────────────────────────────────────────────────────────────┘

    HEADER

    if details
      puts "Usage: ./Scripts/SaneMaster.rb #{details[:usage]}"
      puts
      puts 'Description:'
      puts "  #{details[:description]}"

      if details[:flags].any?
        puts
        puts 'Flags:'
        details[:flags].each do |flag, desc|
          puts "  #{flag.ljust(20)} #{desc}"
        end
      end

      if details[:examples].any?
        puts
        puts 'Examples:'
        details[:examples].each { |ex| puts "  ./Scripts/SaneMaster.rb #{ex}" }
      end
    elsif cmd_info
      puts "Usage: ./Scripts/SaneMaster.rb #{command} #{cmd_info[:args]}"
      puts
      puts 'Description:'
      puts "  #{cmd_info[:desc]}"
      puts
      puts "Category: #{category}"
    else
      puts "No detailed help available for '#{command}'"
      puts
      puts "Run './Scripts/SaneMaster.rb' to see all available commands."
    end
  end
end

# --- Main Entry Point ---
SaneMaster.new.run(ARGV) if __FILE__ == $PROGRAM_NAME
