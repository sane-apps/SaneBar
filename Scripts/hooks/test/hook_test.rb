#!/usr/bin/env ruby
# frozen_string_literal: true

# Hook Unit Tests
# Run with: ruby scripts/hooks/test/hook_test.rb
#
# Tests all hooks for correct behavior:
# - Proper exit codes (0 = allow, 2 = block)
# - Correct stdin JSON parsing
# - Expected output messages

require 'json'
require 'open3'
require 'fileutils'

HOOKS_DIR = File.expand_path('..', __dir__)
TEST_PROJECT = '/tmp/saneprocess_hook_test'
PASS = '✅'
FAIL = '❌'

# Load state signer for creating properly signed state files
require_relative '../state_signer'

# Test tracking
@tests_run = 0
@tests_passed = 0
@failures = []

def setup
  FileUtils.rm_rf(TEST_PROJECT)
  FileUtils.mkdir_p("#{TEST_PROJECT}/.claude/rules")
  FileUtils.mkdir_p("#{TEST_PROJECT}/Views")
  FileUtils.mkdir_p("#{TEST_PROJECT}/Tests")
  FileUtils.mkdir_p("#{TEST_PROJECT}/Services")

  # Create a test file for size checks
  File.write("#{TEST_PROJECT}/test.swift", "line\n" * 100)

  # Create rules files for path_rules tests
  File.write("#{TEST_PROJECT}/.claude/rules/views.md", <<~MD)
    # SwiftUI View Rules

    ## Requirements

    1. **Extract if body > 50 lines** - Split into subviews
    2. **No business logic in views** - Views render state
  MD

  File.write("#{TEST_PROJECT}/.claude/rules/tests.md", <<~MD)
    # Test File Rules

    ## Requirements

    1. **Use Swift Testing** - #expect() not XCTAssert
    2. **No tautologies** - #expect(true) is useless
  MD

  File.write("#{TEST_PROJECT}/.claude/rules/services.md", <<~MD)
    # Service Layer Rules

    ## Requirements

    1. **Actor for shared mutable state** - Thread safety
    2. **Protocol-first** - Define interface before implementation
  MD
end

def teardown
  FileUtils.rm_rf(TEST_PROJECT)
end

def run_hook(hook_name, stdin_data, env = {})
  hook_path = File.join(HOOKS_DIR, hook_name)
  env_with_defaults = {
    'CLAUDE_PROJECT_DIR' => TEST_PROJECT
  }.merge(env)

  stdout, stderr, status = Open3.capture3(
    env_with_defaults,
    'ruby', hook_path,
    stdin_data: stdin_data.to_json
  )

  { stdout: stdout, stderr: stderr, exit_code: status.exitstatus }
end

def assert(condition, message)
  @tests_run += 1
  if condition
    @tests_passed += 1
    puts "  #{PASS} #{message}"
  else
    @failures << message
    puts "  #{FAIL} #{message}"
  end
end

def assert_exit_code(result, expected, message)
  assert(result[:exit_code] == expected, "#{message} (exit #{result[:exit_code]} vs expected #{expected})")
end

def assert_output_contains(result, pattern, message)
  combined = result[:stdout] + result[:stderr]
  assert(combined.match?(pattern), message)
end

def assert_output_not_contains(result, pattern, message)
  combined = result[:stdout] + result[:stderr]
  assert(!combined.match?(pattern), message)
end

# =============================================================================
# Circuit Breaker Tests
# =============================================================================

def test_circuit_breaker
  puts "\n🔌 Circuit Breaker Tests"

  # Test 1: Allow when not tripped
  result = run_hook('circuit_breaker.rb', { tool_name: 'Edit' })
  assert_exit_code(result, 0, 'Allows Edit when breaker not tripped')

  # Test 2: Skip non-blocked tools
  result = run_hook('circuit_breaker.rb', { tool_name: 'Read' })
  assert_exit_code(result, 0, 'Allows Read (not in blocked list)')

  # Test 3: Block when tripped (must use StateSigner for signed state files)
  breaker_file = "#{TEST_PROJECT}/.claude/circuit_breaker.json"
  StateSigner.write_signed(breaker_file, {
    'failures' => 5,
    'tripped' => true,
    'tripped_at' => Time.now.utc.iso8601,
    'trip_reason' => 'Test trip'
  })

  result = run_hook('circuit_breaker.rb', { tool_name: 'Edit' })
  assert_exit_code(result, 2, 'Blocks Edit when breaker tripped')
  assert_output_contains(result, /CIRCUIT BREAKER OPEN/, 'Shows breaker message')

  # Cleanup
  File.delete(breaker_file) if File.exist?(breaker_file)
end

# =============================================================================
# Edit Validator Tests
# =============================================================================

def test_edit_validator
  puts "\n📝 Edit Validator Tests"

  # Test 1: Allow project path
  result = run_hook('edit_validator.rb', {
    tool_input: { file_path: "#{TEST_PROJECT}/test.swift" }
  })
  assert_exit_code(result, 0, 'Allows edits within project')

  # Test 2: Block dangerous path
  result = run_hook('edit_validator.rb', {
    tool_input: { file_path: '/etc/passwd' }
  })
  assert_exit_code(result, 2, 'Blocks /etc/passwd')
  assert_output_contains(result, /Dangerous path/i, 'Shows dangerous path warning')

  # Test 3: Block ~/.ssh
  result = run_hook('edit_validator.rb', {
    tool_input: { file_path: File.expand_path('~/.ssh/id_rsa') }
  })
  assert_exit_code(result, 2, 'Blocks ~/.ssh paths')

  # Test 4: Warn on cross-project (but allow)
  result = run_hook('edit_validator.rb', {
    tool_input: { file_path: File.expand_path('~/other_project/file.swift') }
  })
  assert_exit_code(result, 0, 'Allows cross-project with warning')
  assert_output_contains(result, /Cross-project edit/, 'Shows cross-project warning')
end

# =============================================================================
# Test Quality Checker Tests
# =============================================================================

def test_quality_checker
  puts "\n🧪 Test Quality Checker Tests"

  # Test 1: Warn on #expect(true)
  result = run_hook('test_quality_checker.rb', {
    tool_input: {
      file_path: "#{TEST_PROJECT}/Tests/MyTests.swift",
      new_string: '#expect(true)'
    }
  })
  assert_exit_code(result, 0, 'Does not block (warns only)')
  assert_output_contains(result, /TAUTOLOGY TEST/, 'Warns on #expect(true)')

  # Test 2: No warning on valid assertion
  result = run_hook('test_quality_checker.rb', {
    tool_input: {
      file_path: "#{TEST_PROJECT}/Tests/MyTests.swift",
      new_string: '#expect(result.count == 3)'
    }
  })
  assert_output_not_contains(result, /TAUTOLOGY/, 'No warning on valid assertion')

  # Test 3: Skip non-test files
  result = run_hook('test_quality_checker.rb', {
    tool_input: {
      file_path: "#{TEST_PROJECT}/Views/MyView.swift",
      new_string: '#expect(true)'
    }
  })
  assert_output_not_contains(result, /TAUTOLOGY/, 'Skips non-test files')
end

# =============================================================================
# Failure Tracker Tests
# =============================================================================

def test_failure_tracker
  puts "\n📊 Failure Tracker Tests"

  # Test 1: Track failure
  result = run_hook('failure_tracker.rb', {
    tool_name: 'Bash',
    tool_output: 'error: Build failed',
    session_id: 'test_session'
  })
  assert_exit_code(result, 0, 'Continues after tracking failure')
  assert_output_contains(result, /"result".*"continue"/, 'Returns continue JSON')

  # Test 2: Track success (reset counter)
  result = run_hook('failure_tracker.rb', {
    tool_name: 'Bash',
    tool_output: 'Build succeeded',
    session_id: 'test_session'
  })
  assert_exit_code(result, 0, 'Continues after success')

  # Cleanup
  File.delete("#{TEST_PROJECT}/.claude/failure_state.json") rescue nil
  File.delete("#{TEST_PROJECT}/.claude/circuit_breaker.json") rescue nil
end

# =============================================================================
# Path Rules Tests
# =============================================================================

def test_path_rules
  puts "\n📋 Path Rules Tests"

  # Test 1: Show view rules for View file
  result = run_hook('path_rules.rb', {
    tool_name: 'Edit',
    tool_input: { file_path: "#{TEST_PROJECT}/Views/TestView.swift" }
  })
  assert_exit_code(result, 0, 'Exits cleanly for view file')
  assert_output_contains(result, /SwiftUI View Rules/, 'Shows view rules')

  # Test 2: Show test rules for test file
  result = run_hook('path_rules.rb', {
    tool_name: 'Edit',
    tool_input: { file_path: "#{TEST_PROJECT}/Tests/MyTests.swift" }
  })
  assert_output_contains(result, /Test File Rules/, 'Shows test rules')

  # Test 3: Show service rules
  result = run_hook('path_rules.rb', {
    tool_name: 'Edit',
    tool_input: { file_path: "#{TEST_PROJECT}/Services/CameraService.swift" }
  })
  assert_output_contains(result, /Service Layer Rules/, 'Shows service rules')
end

# =============================================================================
# Audit Logger Tests
# =============================================================================

def test_audit_logger
  puts "\n📝 Audit Logger Tests"

  audit_file = "#{TEST_PROJECT}/.claude/audit.jsonl"

  # Test 1: Log a tool call
  result = run_hook('audit_logger.rb', {
    tool_name: 'Edit',
    tool_input: { file_path: "#{TEST_PROJECT}/test.swift" },
    session_id: 'test_session'
  })
  assert_exit_code(result, 0, 'Exits cleanly')
  assert(File.exist?(audit_file), 'Creates audit log file')

  if File.exist?(audit_file)
    log_entry = JSON.parse(File.readlines(audit_file).last)
    assert(log_entry['tool'] == 'Edit', 'Logs tool name')
    assert(log_entry['session_id'] == 'test_session', 'Logs session ID')
  end

  # Cleanup
  File.delete(audit_file) rescue nil
end

# =============================================================================
# Session Start Tests
# =============================================================================

def test_session_start
  puts "\n🚀 Session Start Tests"

  # Create a tripped breaker to test VULN-007 behavior (should NOT auto-reset)
  breaker_file = "#{TEST_PROJECT}/.claude/circuit_breaker.json"
  StateSigner.write_signed(breaker_file, {
    'failures' => 5,
    'tripped' => true,
    'tripped_at' => Time.now.utc.iso8601
  })

  result = run_hook('session_start.rb', {})
  assert_exit_code(result, 0, 'Exits cleanly')
  # VULN-007: Session start warns about tripped breaker, does NOT reset it
  assert_output_contains(result, /STILL TRIPPED|session started/i, 'Shows status message')

  # VULN-007 FIX: Breaker should REMAIN tripped (prevents bypass by session restart)
  if File.exist?(breaker_file)
    breaker = StateSigner.read_verified(breaker_file) || JSON.parse(File.read(breaker_file))
    assert(breaker['tripped'] == true, 'VULN-007: Breaker stays tripped on session start')
  end
end

# =============================================================================
# Process Enforcer Tests (VULN-002 Bash bypass detection)
# =============================================================================

def test_process_enforcer
  puts "\n🛡️ Process Enforcer Tests"

  # Set up requirements file
  reqs_file = "#{TEST_PROJECT}/.claude/prompt_requirements.json"
  File.write(reqs_file, JSON.generate({
    requested: %w[saneloop plan],
    satisfied: [],
    modifiers: []
  }))

  # Test 1: Blocks Edit when saneloop not active
  result = run_hook('process_enforcer.rb', {
    tool_name: 'Edit',
    tool_input: { file_path: "#{TEST_PROJECT}/test.swift" }
  })
  assert_exit_code(result, 2, 'Blocks Edit when saneloop required (exit 2)')
  assert_output_contains(result, /SANELOOP_REQUIRED/, 'Shows saneloop required message')

  # Test 2: Detects Bash file write bypass (echo >>)
  result = run_hook('process_enforcer.rb', {
    tool_name: 'Bash',
    tool_input: { command: 'echo "bypass" >> /tmp/test.txt' }
  })
  assert_exit_code(result, 2, 'Blocks Bash echo redirect')
  assert_output_contains(result, /BASH_FILE_WRITE_BYPASS/, 'Detects echo bypass')

  # Test 3: Detects Bash file write bypass (sed -i)
  result = run_hook('process_enforcer.rb', {
    tool_name: 'Bash',
    tool_input: { command: "sed -i '' 's/a/b/' file.txt" }
  })
  assert_exit_code(result, 2, 'Blocks Bash sed -i')
  assert_output_contains(result, /BASH_FILE_WRITE_BYPASS/, 'Detects sed bypass')

  # Test 4: VULN-002 FIX - Bash file writes to .claude/ are now BLOCKED
  # Hooks write via Ruby, not Bash - if Claude uses Bash, it's bypassing
  result = run_hook('process_enforcer.rb', {
    tool_name: 'Bash',
    tool_input: { command: 'echo "{}" > .claude/state.json' }
  })
  # VULN-002: Should block BOTH saneloop AND bash file write
  assert_exit_code(result, 2, 'VULN-002: Blocks .claude writes via Bash')
  assert_output_contains(result, /BASH_FILE_WRITE_BYPASS|SANELOOP/, 'Detects bypass attempt')

  # Test 5: Allows saneloop start command (bootstrap fix)
  result = run_hook('process_enforcer.rb', {
    tool_name: 'Bash',
    tool_input: { command: './Scripts/SaneMaster.rb saneloop start "test"' }
  })
  assert_exit_code(result, 0, 'Allows saneloop start command')

  # Test 6: Blocks subagent editing bypass
  result = run_hook('process_enforcer.rb', {
    tool_name: 'Task',
    tool_input: { prompt: 'Edit the file and add a line' }
  })
  assert_exit_code(result, 2, 'Blocks Task for editing')
  assert_output_contains(result, /SUBAGENT_BYPASS/, 'Detects subagent bypass')

  # Cleanup
  File.delete(reqs_file) rescue nil
end

# =============================================================================
# Run All Tests
# =============================================================================

puts '=' * 60
puts 'SaneProcess Hook Unit Tests'
puts '=' * 60

setup

begin
  test_circuit_breaker
  test_edit_validator
  test_quality_checker
  test_failure_tracker
  test_path_rules
  test_audit_logger
  test_session_start
  test_process_enforcer
ensure
  teardown
end

puts ''
puts '=' * 60
puts "Results: #{@tests_passed}/#{@tests_run} passed"
puts '=' * 60

if @failures.any?
  puts ''
  puts 'Failures:'
  @failures.each { |f| puts "  #{FAIL} #{f}" }
  exit 1
else
  puts ''
  puts "#{PASS} All tests passed!"
  exit 0
end
