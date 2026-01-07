#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneTrack - PostToolUse Hook
# ==============================================================================
# Tracks tool results after execution. Updates state based on outcomes.
#
# Exit codes:
#   0 = success (tool already executed)
#   2 = error message for Claude (tool already executed)
#
# What this tracks:
#   1. Edit counts and unique files
#   2. Tool failures (for circuit breaker)
#   3. Research quality (meaningful output validation)
#   4. Patterns for learning
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'core/state_manager'

LOG_FILE = File.expand_path('../../.claude/sanetrack.log', __dir__)

# === TOOL CLASSIFICATION ===

EDIT_TOOLS = %w[Edit Write NotebookEdit].freeze
FAILURE_TOOLS = %w[Bash Edit Write].freeze  # Tools that can fail and trigger circuit breaker

# === MCP VERIFICATION TOOLS ===
# Map MCP names to their read-only verification tools
MCP_VERIFICATION_PATTERNS = {
  memory: /^mcp__memory__(read_graph|search_nodes|open_nodes)$/,
  apple_docs: /^mcp__apple-docs__/,
  context7: /^mcp__context7__/,
  github: /^mcp__github__(search_|get_|list_)/
}.freeze

# === RESEARCH TRACKING ===
# Patterns to detect which research category a Task agent is completing
RESEARCH_PATTERNS = {
  memory: /memory|mcp__memory/i,
  docs: /context7|apple-docs|documentation|mcp__context7|mcp__apple-docs/i,
  web: /web.*search|websearch|mcp__.*web/i,
  github: /github|mcp__github/i,
  local: /grep|glob|read|explore|codebase/i
}.freeze

# === TAUTOLOGY PATTERNS (Rule #7 - consolidated from test_quality_checker.rb) ===
# Detects tests that always pass (useless tests)
TAUTOLOGY_PATTERNS = [
  # Literal boolean assertions
  /#expect\s*\(\s*true\s*\)/i,
  /#expect\s*\(\s*false\s*\)/i,
  /XCTAssertTrue\s*\(\s*true\s*\)/i,
  /XCTAssertFalse\s*\(\s*false\s*\)/i,
  /XCTAssert\s*\(\s*true\s*\)/i,
  # Boolean tautology (always true)
  /#expect\s*\([^)]+==\s*true\s*\|\|\s*[^)]+==\s*false\s*\)/i,
  # TODO placeholders
  /XCTAssert.*TODO/i,
  /#expect.*TODO/i,
  # M9 additions: Self-comparison (always true)
  /#expect\s*\(\s*(\w+)\s*==\s*\1\s*\)/,
  /XCTAssertEqual\s*\(\s*(\w+)\s*,\s*\1\s*\)/,
  # M9: Trivial non-nil check (need context to be sure, but flag for review)
  /#expect\s*\([^)]+\s*!=\s*nil\s*\)\s*$/, # Standalone != nil often tautology
  /XCTAssertNotNil\s*\(\s*\w+\s*\)\s*$/,  # Just variable, no setup context
  # M9: Always-true comparisons
  /#expect\s*\([^)]+\.count\s*>=\s*0\s*\)/i,      # count >= 0 always true
  /XCTAssertGreaterThanOrEqual\s*\([^,]+\.count\s*,\s*0\s*\)/i,
  # M9: Empty assertion (no actual check)
  /#expect\s*\(\s*\)/,
  /XCTAssert\s*\(\s*\)/
].freeze

# === TEST FILE PATTERN ===
TEST_FILE_PATTERN = %r{(Tests?/|Specs?/|_test\.|_spec\.|Tests?\.swift|Spec\.swift)}i.freeze

# === TAUTOLOGY DETECTION (Rule #7) ===
def check_tautologies(tool_name, tool_input)
  return nil unless EDIT_TOOLS.include?(tool_name)

  file_path = tool_input['file_path'] || tool_input[:file_path] || ''
  return nil unless file_path.match?(TEST_FILE_PATTERN)

  new_string = tool_input['new_string'] || tool_input[:new_string] || ''
  return nil if new_string.empty?

  matches = TAUTOLOGY_PATTERNS.select { |pattern| new_string.match?(pattern) }
  return nil if matches.empty?

  # Build warning message
  "RULE #7 WARNING: Test contains tautology (always passes)\n" \
  "   File: #{File.basename(file_path)}\n" \
  "   Found: #{matches.length} suspicious pattern(s)\n" \
  "   Fix: Replace with meaningful assertions that test actual behavior"
end

# === ERROR PATTERNS ===

ERROR_PATTERN = Regexp.union(
  /error/i,
  /failed/i,
  /exception/i,
  /cannot/i,
  /unable/i,
  /denied/i,
  /not found/i,
  /no such/i
).freeze

# === INTELLIGENCE: Error Signature Normalization ===
# Same underlying error should have same signature

ERROR_SIGNATURES = {
  'COMMAND_NOT_FOUND' => [/command not found/i, /not recognized as.*command/i],
  'PERMISSION_DENIED' => [/permission denied/i, /access denied/i, /not permitted/i],
  'FILE_NOT_FOUND' => [/no such file/i, /file not found/i, /doesn't exist/i],
  'BUILD_FAILED' => [/build failed/i, /compilation error/i, /compile error/i],
  'SYNTAX_ERROR' => [/syntax error/i, /parse error/i, /unexpected token/i],
  'TYPE_ERROR' => [/type.*error/i, /cannot convert/i, /type mismatch/i],
  'NETWORK_ERROR' => [/connection refused/i, /timeout/i, /network error/i],
  'MEMORY_ERROR' => [/out of memory/i, /memory error/i, /allocation failed/i],
}.freeze

# === INTELLIGENCE: Action Log for Pattern Learning ===
MAX_ACTION_LOG = 20

# === TRACKING FUNCTIONS ===

def track_edit(tool_name, tool_input, tool_response)
  return unless EDIT_TOOLS.include?(tool_name)

  file_path = tool_input['file_path'] || tool_input[:file_path]
  return unless file_path

  StateManager.update(:edits) do |e|
    e[:count] = (e[:count] || 0) + 1
    e[:unique_files] ||= []
    e[:unique_files] << file_path unless e[:unique_files].include?(file_path)
    e[:last_file] = file_path
    e
  end
end

# === MCP VERIFICATION TRACKING ===
# Track successful MCP tool calls to verify connectivity

def track_mcp_verification(tool_name, success)
  # Find which MCP this tool belongs to
  mcp_name = nil
  MCP_VERIFICATION_PATTERNS.each do |mcp, pattern|
    if tool_name.match?(pattern)
      mcp_name = mcp
      break
    end
  end

  return unless mcp_name

  StateManager.update(:mcp_health) do |health|
    health[:mcps] ||= {}
    health[:mcps][mcp_name] ||= { verified: false, last_success: nil, last_failure: nil, failure_count: 0 }

    if success
      health[:mcps][mcp_name][:verified] = true
      health[:mcps][mcp_name][:last_success] = Time.now.iso8601
      # Don't reset failure_count - it's historical data

      # Check if ALL MCPs are now verified
      all_verified = MCP_VERIFICATION_PATTERNS.keys.all? do |mcp|
        health[:mcps][mcp] && health[:mcps][mcp][:verified]
      end

      if all_verified && !health[:verified_this_session]
        health[:verified_this_session] = true
        health[:last_verified] = Time.now.iso8601
        warn '✅ ALL MCPs VERIFIED - edits now allowed'
      end
    else
      health[:mcps][mcp_name][:last_failure] = Time.now.iso8601
      health[:mcps][mcp_name][:failure_count] = (health[:mcps][mcp_name][:failure_count] || 0) + 1
    end

    health
  end
rescue StandardError => e
  warn "⚠️  MCP tracking error: #{e.message}"
end

def track_failure(tool_name, tool_response)
  return unless FAILURE_TOOLS.include?(tool_name)

  # Check if response indicates failure
  response_str = tool_response.to_s
  is_failure = response_str.match?(ERROR_PATTERN)

  return unless is_failure

  StateManager.update(:circuit_breaker) do |cb|
    cb[:failures] = (cb[:failures] || 0) + 1
    cb[:last_error] = response_str[0..200]

    # Trip breaker at 3 failures
    if cb[:failures] >= 3 && !cb[:tripped]
      cb[:tripped] = true
      cb[:tripped_at] = Time.now.iso8601
    end

    cb
  end
end

def reset_failure_count(tool_name)
  # Successful tool use resets failure count for that tool type
  return unless FAILURE_TOOLS.include?(tool_name)

  cb = StateManager.get(:circuit_breaker)
  return if cb[:failures] == 0

  StateManager.update(:circuit_breaker) do |c|
    c[:failures] = 0
    # Don't clear last_error if breaker is already tripped (preserves context)
    c[:last_error] = nil unless c[:tripped]
    c
  end
end

# === INTELLIGENCE: Error Signature Normalization ===

def normalize_error(response_str)
  return nil unless response_str.is_a?(String)

  ERROR_SIGNATURES.each do |signature, patterns|
    if patterns.any? { |p| response_str.match?(p) }
      return signature
    end
  end

  # Generic error if no specific signature
  return 'GENERIC_ERROR' if response_str.match?(ERROR_PATTERN)

  nil
end

def track_error_signature(signature, tool_name, response_str)
  return unless signature

  sig_key = signature.to_sym  # Use symbol for consistent hash access after JSON symbolize

  StateManager.update(:circuit_breaker) do |cb|
    cb[:error_signatures] ||= {}
    cb[:error_signatures][sig_key] = (cb[:error_signatures][sig_key] || 0) + 1

    # Trip if same signature 3x (even with other successes between)
    if cb[:error_signatures][sig_key] >= 3 && !cb[:tripped]
      cb[:tripped] = true
      cb[:tripped_at] = Time.now.iso8601
      cb[:last_error] = "#{signature} x#{cb[:error_signatures][sig_key]}: #{response_str[0..100]}"
    end

    cb
  end
end

# === INTELLIGENCE: Action Logging for Pattern Learning ===

def log_action_for_learning(tool_name, tool_input, success, error_sig = nil)
  StateManager.update(:action_log) do |log|
    log ||= []
    log << {
      tool: tool_name,
      timestamp: Time.now.iso8601,
      success: success,
      error_sig: error_sig,
      input_summary: summarize_input(tool_input)
    }
    log.last(MAX_ACTION_LOG)
  end
rescue StandardError
  # Don't fail on logging errors
end

def summarize_input(input)
  return nil unless input.is_a?(Hash)

  # Extract key info for correlation
  input['file_path'] || input[:file_path] ||
    input['command']&.to_s&.slice(0, 50) || input[:command]&.to_s&.slice(0, 50) ||
    input['prompt']&.to_s&.slice(0, 50) || input[:prompt]&.to_s&.slice(0, 50)
end

# === LOGGING ===

def log_action(tool_name, result_type)
  FileUtils.mkdir_p(File.dirname(LOG_FILE))
  entry = {
    timestamp: Time.now.iso8601,
    tool: tool_name,
    result: result_type,
    pid: Process.pid
  }
  File.open(LOG_FILE, 'a') { |f| f.puts(entry.to_json) }
rescue StandardError
  # Don't fail on logging errors
end

# === MAIN PROCESSING ===

# Detect actual tool failure vs text that just contains error-like words
# Key insight: "No such file" from ls is informational, not a failure
# Key insight: File content containing "type error" is NOT a tool error
def detect_actual_failure(tool_name, tool_response)
  return nil unless tool_response.is_a?(Hash)

  # Check for explicit error fields first (most reliable)
  if tool_response['error'] || tool_response[:error]
    error_text = (tool_response['error'] || tool_response[:error]).to_s
    return normalize_error(error_text) || 'GENERIC_ERROR'
  end

  # Check for stderr with actual error content
  stderr = tool_response['stderr'] || tool_response[:stderr]
  if stderr.is_a?(String) && !stderr.empty?
    sig = normalize_error(stderr)
    return sig if sig
  end

  # For Bash: check exit code and be smart about stdout
  if tool_name == 'Bash'
    exit_code = tool_response['exit_code'] || tool_response[:exit_code]
    return 'COMMAND_FAILED' if exit_code && exit_code != 0

    stdout = tool_response['stdout'] || tool_response[:stdout] || ''
    # "No such file" from ls/cat is informational when checking existence
    # Only flag if it's a command interpreter error (bash:, ruby:, etc.)
    if stdout.match?(/no such file|not found/i)
      return nil unless stdout.match?(/^(bash|sh|ruby|python|node):\s/i)
    end
  end

  # For Read: file not found comes through error field, not content
  # File content containing words like "error" is NOT a tool failure
  return nil if tool_name == 'Read'

  # For Edit/Write: actual errors come through error field
  return nil if %w[Edit Write].include?(tool_name)

  # For MCP tools: check error field only
  return nil if tool_name.start_with?('mcp__')

  # For Task: agent errors come through error field
  return nil if tool_name == 'Task'

  nil
end

def process_result(tool_name, tool_input, tool_response)
  # === INTELLIGENCE: Detect actual failures, not text matching ===
  error_sig = detect_actual_failure(tool_name, tool_response)
  is_error = !error_sig.nil?

  if is_error
    # Track failure (legacy count)
    track_failure(tool_name, tool_response)

    # === MCP VERIFICATION: Track failures for MCP tools ===
    track_mcp_verification(tool_name, false)

    # === INTELLIGENCE: Track by signature (3x same = trip, even with successes) ===
    response_str = tool_response.to_s[0..200]
    track_error_signature(error_sig, tool_name, response_str)

    # === INTELLIGENCE: Log action for pattern learning ===
    log_action_for_learning(tool_name, tool_input, false, error_sig)

    log_action(tool_name, 'failure')
  else
    reset_failure_count(tool_name)
    track_edit(tool_name, tool_input, tool_response)

    # === MCP VERIFICATION: Track successes for MCP tools ===
    track_mcp_verification(tool_name, true)

    # === RULE #7: Tautology detection for test files ===
    tautology_warning = check_tautologies(tool_name, tool_input)
    warn tautology_warning if tautology_warning

    # === INTELLIGENCE: Log action for pattern learning ===
    log_action_for_learning(tool_name, tool_input, true, nil)

    log_action(tool_name, 'success')

    # === GIT PUSH REMINDER ===
    # After successful git commit, check if push is needed
    if tool_name == 'Bash'
      command = tool_input['command'] || tool_input[:command] || ''
      if command.match?(/git\s+commit/i) && !command.match?(/git\s+push/i)
        # Check for unpushed commits
        ahead_check = `git status 2>/dev/null | grep -o "ahead of.*by [0-9]* commit"`
        unless ahead_check.empty?
          warn ''
          warn '🚨 GIT PUSH REMINDER 🚨'
          warn "   You committed but haven't pushed!"
          warn "   Status: #{ahead_check.strip}"
          warn ''
          warn '   → Run: git push'
          warn '   → READ ALL DOCUMENTATION before claiming done'
          warn '   → Verify README is accurate and up to date'
          warn ''
        end
      end
    end
  end

  0  # PostToolUse always returns 0 (tool already executed)
end

# === SELF-TEST ===

def self_test
  warn 'SaneTrack Self-Test'
  warn '=' * 40

  # Reset state
  StateManager.reset(:edits)
  StateManager.reset(:circuit_breaker)
  StateManager.update(:enforcement) { |e| e[:halted] = false; e[:blocks] = []; e }

  passed = 0
  failed = 0

  # Test 1: Track edit
  process_result('Edit', { 'file_path' => '/test/file1.swift' }, { 'success' => true })
  edits = StateManager.get(:edits)
  if edits[:count] == 1 && edits[:unique_files].include?('/test/file1.swift')
    passed += 1
    warn '  PASS: Edit tracking'
  else
    failed += 1
    warn '  FAIL: Edit tracking'
  end

  # Test 2: Track multiple edits to same file
  process_result('Edit', { 'file_path' => '/test/file1.swift' }, { 'success' => true })
  edits = StateManager.get(:edits)
  if edits[:count] == 2 && edits[:unique_files].length == 1
    passed += 1
    warn '  PASS: Unique file tracking'
  else
    failed += 1
    warn '  FAIL: Unique file tracking'
  end

  # Test 3: Track failure
  process_result('Bash', {}, { 'error' => 'command not found' })
  cb = StateManager.get(:circuit_breaker)
  if cb[:failures] == 1
    passed += 1
    warn '  PASS: Failure tracking'
  else
    failed += 1
    warn '  FAIL: Failure tracking'
  end

  # Test 4: Reset failure on success
  process_result('Bash', {}, { 'output' => 'success' })
  cb = StateManager.get(:circuit_breaker)
  if cb[:failures] == 0
    passed += 1
    warn '  PASS: Failure reset on success'
  else
    failed += 1
    warn '  FAIL: Failure reset on success'
  end

  # Test 5: Circuit breaker trips at 3 failures
  StateManager.reset(:circuit_breaker)
  process_result('Bash', {}, { 'error' => 'fail 1' })
  process_result('Bash', {}, { 'error' => 'fail 2' })
  process_result('Bash', {}, { 'error' => 'fail 3' })
  cb = StateManager.get(:circuit_breaker)
  if cb[:tripped]
    passed += 1
    warn '  PASS: Circuit breaker trips at 3 failures'
  else
    failed += 1
    warn '  FAIL: Circuit breaker should trip at 3 failures'
  end

  # === INTELLIGENCE TESTS ===

  # Test 6: Error signature normalization
  StateManager.reset(:circuit_breaker)
  sig1 = normalize_error('ruby: command not found')
  sig2 = normalize_error('bash: npm: command not found')
  if sig1 == 'COMMAND_NOT_FOUND' && sig2 == 'COMMAND_NOT_FOUND'
    passed += 1
    warn '  PASS: Error signature normalization (COMMAND_NOT_FOUND)'
  else
    failed += 1
    warn "  FAIL: Expected COMMAND_NOT_FOUND, got #{sig1}, #{sig2}"
  end

  # Test 7: Per-signature trip (3x same with successes between)
  StateManager.reset(:circuit_breaker)
  process_result('Bash', {}, { 'error' => 'command not found: ruby' })
  process_result('Bash', {}, { 'output' => 'success' })  # Success resets legacy, not signature
  process_result('Bash', {}, { 'error' => 'command not found: npm' })
  process_result('Bash', {}, { 'output' => 'success' })  # Success again
  process_result('Bash', {}, { 'error' => 'command not found: python' })
  cb = StateManager.get(:circuit_breaker)
  if cb[:tripped] && cb[:error_signatures] && cb[:error_signatures][:COMMAND_NOT_FOUND] == 3
    passed += 1
    warn '  PASS: Per-signature trip at 3x same (with successes between)'
  else
    failed += 1
    warn "  FAIL: Per-signature trip - tripped=#{cb[:tripped]}, signatures=#{cb[:error_signatures]}"
  end

  # Test 8: Action log for learning
  StateManager.update(:action_log) { |_| [] }  # Initialize empty
  process_result('Edit', { 'file_path' => '/test/file.swift' }, { 'success' => true })
  process_result('Bash', { 'command' => 'ruby test.rb' }, { 'error' => 'syntax error' })
  log = StateManager.get(:action_log)
  if log.is_a?(Array) && log.length >= 2
    first = log[-2]  # Second to last (Edit)
    last = log[-1]   # Last (Bash with error)
    if first && last && first[:tool] == 'Edit' && last[:error_sig] == 'SYNTAX_ERROR'
      passed += 1
      warn '  PASS: Action log for learning'
    else
      failed += 1
      warn "  FAIL: Action log content - first=#{first}, last=#{last}"
    end
  else
    failed += 1
    warn "  FAIL: Action log - got #{log.inspect[0..100]}"
  end

  # === JSON INTEGRATION TESTS ===
  warn ''
  warn 'Testing JSON parsing (integration):'

  require 'open3'

  # Test valid JSON with success response
  json_input = '{"tool_name":"Edit","tool_input":{"file_path":"/test/integrated.swift"},"tool_response":{"success":true}}'
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: json_input)
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Valid JSON parsed correctly (exit 0)'
  else
    failed += 1
    warn "  FAIL: Valid JSON should return exit 0, got #{status.exitstatus}"
  end

  # Test JSON with error response (still returns 0 - PostToolUse is tracking only)
  json_input = '{"tool_name":"Bash","tool_input":{"command":"test"},"tool_response":{"error":"command failed"}}'
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: json_input)
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Error response still returns exit 0 (PostToolUse is passive)'
  else
    failed += 1
    warn "  FAIL: PostToolUse should always exit 0, got #{status.exitstatus}"
  end

  # Test invalid JSON doesn't crash
  json_input = 'this is not valid json'
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: json_input)
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Invalid JSON returns exit 0 (fail safe)'
  else
    failed += 1
    warn "  FAIL: Invalid JSON should return exit 0, got #{status.exitstatus}"
  end

  # Test empty input doesn't crash
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: '')
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Empty input returns exit 0 (fail safe)'
  else
    failed += 1
    warn "  FAIL: Empty input should return exit 0, got #{status.exitstatus}"
  end

  # === DETECT ACTUAL FAILURE TESTS ===
  warn ''
  warn 'Testing failure detection (no false positives):'

  # Test: Read file content with error-like text is NOT a failure
  result = detect_actual_failure('Read', { 'content' => 'def handle_error: raise TypeError' })
  if result.nil?
    passed += 1
    warn '  PASS: Read file content with error text is not a failure'
  else
    failed += 1
    warn "  FAIL: Read content should not be flagged - got #{result}"
  end

  # Test: Bash with non-zero exit code IS a failure
  result = detect_actual_failure('Bash', { 'exit_code' => 1, 'stdout' => '' })
  if result == 'COMMAND_FAILED'
    passed += 1
    warn '  PASS: Bash non-zero exit code is a failure'
  else
    failed += 1
    warn "  FAIL: Expected COMMAND_FAILED, got #{result.inspect}"
  end

  # Test: MCP tool success is not a failure
  result = detect_actual_failure('mcp__memory__read_graph', { 'entities' => [] })
  if result.nil?
    passed += 1
    warn '  PASS: MCP success is not a failure'
  else
    failed += 1
    warn "  FAIL: MCP success should return nil, got #{result}"
  end

  # === TAUTOLOGY DETECTION TESTS (Rule #7) ===
  warn ''
  warn 'Testing tautology detection (Rule #7):'

  # Test: Detects #expect(true) in test file
  result = check_tautologies('Edit', {
    'file_path' => '/path/Tests/MyTests.swift',
    'new_string' => '@Test func bad() { #expect(true) }'
  })
  if result&.include?('RULE #7 WARNING')
    passed += 1
    warn '  PASS: Detects #expect(true) in test file'
  else
    failed += 1
    warn "  FAIL: Should detect tautology, got #{result.inspect}"
  end

  # Test: Ignores tautology in non-test file
  result = check_tautologies('Edit', {
    'file_path' => '/path/Sources/Main.swift',
    'new_string' => 'let x = true; #expect(true)'
  })
  if result.nil?
    passed += 1
    warn '  PASS: Ignores tautology in non-test file'
  else
    failed += 1
    warn "  FAIL: Should ignore non-test file, got #{result.inspect}"
  end

  # Test: Allows real assertions
  result = check_tautologies('Edit', {
    'file_path' => '/path/Tests/ValidTests.swift',
    'new_string' => '@Test func good() { #expect(result == 42) }'
  })
  if result.nil?
    passed += 1
    warn '  PASS: Allows real assertions in test file'
  else
    failed += 1
    warn "  FAIL: Real assertion should be allowed, got #{result.inspect}"
  end

  # === CLEANUP: Reset circuit breaker only (don't reset research - breaks normal ops) ===
  StateManager.reset(:circuit_breaker)
  StateManager.update(:enforcement) { |e| e[:halted] = false; e[:blocks] = []; e }

  warn ''
  warn "#{passed}/#{passed + failed} tests passed"

  if failed == 0
    warn ''
    warn 'ALL TESTS PASSED'
    exit 0
  else
    warn ''
    warn "#{failed} TESTS FAILED"
    exit 1
  end
end

def show_status
  edits = StateManager.get(:edits)
  cb = StateManager.get(:circuit_breaker)

  warn 'SaneTrack Status'
  warn '=' * 40
  warn ''
  warn 'Edits:'
  warn "  count: #{edits[:count]}"
  warn "  unique_files: #{edits[:unique_files]&.length || 0}"
  warn ''
  warn 'Circuit Breaker:'
  warn "  failures: #{cb[:failures]}"
  warn "  tripped: #{cb[:tripped]}"
  warn "  last_error: #{cb[:last_error]&.[](0..50)}" if cb[:last_error]

  exit 0
end

# === MAIN ===

if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('--self-test')
    self_test
  elsif ARGV.include?('--status')
    show_status
  else
    begin
      input = JSON.parse($stdin.read)
      tool_name = input['tool_name'] || 'unknown'
      tool_input = input['tool_input'] || {}
      tool_response = input['tool_response'] || {}
      exit process_result(tool_name, tool_input, tool_response)
    rescue JSON::ParserError, Errno::ENOENT
      exit 0  # Don't fail on parse errors
    end
  end
end
