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

# === ERROR PATTERNS ===

ERROR_PATTERNS = [
  /error/i,
  /failed/i,
  /exception/i,
  /cannot/i,
  /unable/i,
  /denied/i,
  /not found/i,
  /no such/i,
].freeze

# These are workflow guidance, not actual failures - don't count them
GUIDANCE_PATTERNS = [
  /File has not been read yet/i,
  /Read it first before/i,
  /must read.*before/i,
].freeze

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

def track_failure(tool_name, tool_response)
  return unless FAILURE_TOOLS.include?(tool_name)

  response_str = tool_response.to_s

  # Skip workflow guidance - these aren't real failures, just instructions
  is_guidance = GUIDANCE_PATTERNS.any? { |p| response_str.match?(p) }
  return if is_guidance

  is_failure = ERROR_PATTERNS.any? { |p| response_str.match?(p) }
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
  # Successful tool use resets failure count AND tripped state
  # This rewards compliance - if you do what was asked, breaker resets
  # Read is included because "read first" guidance should reset when obeyed
  compliance_tools = FAILURE_TOOLS + %w[Read]
  return unless compliance_tools.include?(tool_name)

  cb = StateManager.get(:circuit_breaker)
  return if cb[:failures] == 0 && !cb[:tripped]

  StateManager.update(:circuit_breaker) do |c|
    c[:failures] = 0
    c[:last_error] = nil
    c[:tripped] = false  # Reset tripped state on success
    c[:tripped_at] = nil
    c
  end
end

def track_enforcement_block(tool_name, blocked_reason)
  return unless blocked_reason

  signature = blocked_reason.lines.first&.strip || 'UNKNOWN'

  StateManager.update(:enforcement) do |e|
    e[:blocks] ||= []
    e[:blocks] << {
      signature: signature,
      tool: tool_name,
      at: Time.now.iso8601
    }

    # Keep only last 10 blocks
    e[:blocks] = e[:blocks].last(10)

    # Check for enforcement loop (5x same block)
    recent = e[:blocks].last(5)
    if recent.length >= 5
      sigs = recent.map { |b| b[:signature] }
      if sigs.uniq.length == 1
        e[:halted] = true
        e[:halted_at] = Time.now.iso8601
        e[:halted_reason] = "5x consecutive: #{sigs.first}"
      end
    end

    e
  end
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

def process_result(tool_name, tool_input, tool_response)
  response_str = tool_response.to_s

  # Check if this was an error
  is_error = ERROR_PATTERNS.any? { |p| response_str.match?(p) }

  if is_error
    track_failure(tool_name, tool_response)
    log_action(tool_name, 'failure')
  else
    reset_failure_count(tool_name)
    track_edit(tool_name, tool_input, tool_response)
    log_action(tool_name, 'success')
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
