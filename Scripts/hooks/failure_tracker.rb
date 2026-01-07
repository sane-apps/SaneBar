#!/usr/bin/env ruby
# frozen_string_literal: true

# Failure Tracking Hook
# Tracks consecutive failures and enforces Two-Fix Rule escalation
# Also integrates with circuit breaker to trip after threshold failures
#
# This is a PostToolUse hook for Bash commands.

require 'json'
require 'fileutils'
require_relative 'rule_tracker'
require_relative 'state_signer'

# State file for failure tracking
STATE_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'failure_state.json')
BREAKER_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'circuit_breaker.json')

def default_state
  { 'consecutive_failures' => 0, 'last_failure_tool' => nil, 'session' => nil, 'escalated' => false }
end

def default_breaker_state
  { failures: 0, tripped: false, tripped_at: nil, threshold: 3 }
end

def load_state(file, default)
  # VULN-003 FIX: Use signed state files
  data = StateSigner.read_verified(file)
  return default.call if data.nil?

  # Keep string keys for compatibility
  data
rescue StandardError
  default.call
end

def save_state(file, state)
  # VULN-003 FIX: Sign state files to prevent tampering
  StateSigner.write_signed(file, state.transform_keys(&:to_s))
end

# Read hook input from stdin
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

tool_name = input['tool_name'] || 'unknown'
tool_output = input['tool_output'] || ''
session_id = input['session_id'] || 'unknown'

# Load state
state = load_state(STATE_FILE, method(:default_state))

# Reset if new session
state = default_state if state['session'] != session_id
state['session'] = session_id

# Detect failure patterns
failure_patterns = [
  /error:/i,
  /failed/i,
  /FAIL/,
  /cannot find/i,
  /no such file/i,
  /undefined/i,
  /not found/i,
  /compile error/i,
  /build failed/i
]

# Exclusion patterns (override failure detection when build actually succeeded)
success_patterns = [
  /no errors?/i,
  /0 errors?/i,
  /Build succeeded/i,
  /Test.*passed/i,
  /\*\* BUILD SUCCEEDED \*\*/,
  /error_handler/i,
  /ErrorType/i,
  /catch.*error/i
]

# Only count as failure if matches failure pattern and not success pattern
is_failure = failure_patterns.any? { |p| tool_output.match?(p) } &&
             success_patterns.none? { |p| tool_output.match?(p) }

if is_failure
  state['consecutive_failures'] += 1
  state['last_failure_tool'] = tool_name

  # Update circuit breaker
  breaker = load_state(BREAKER_FILE, method(:default_breaker_state))
  breaker[:failures] = (breaker[:failures] || 0) + 1

  if breaker[:failures] >= (breaker[:threshold] || 3) && !breaker[:tripped]
    breaker[:tripped] = true
    breaker[:tripped_at] = Time.now.iso8601
    breaker[:trip_reason] = "#{breaker[:failures]} consecutive failures"
    save_state(BREAKER_FILE, breaker)
    RuleTracker.log_violation(rule: 3, hook: 'failure_tracker', reason: "Circuit breaker tripped: #{breaker[:failures]} failures")
    warn '🔴 CIRCUIT BREAKER TRIPPED: All Edit/Bash/Write tools now BLOCKED.'
  else
    save_state(BREAKER_FILE, breaker)
  end

  # Enforce Two-Fix Rule
  if state['consecutive_failures'] >= 2 && !state['escalated']
    state['escalated'] = true
    RuleTracker.log_enforcement(rule: 3, hook: 'failure_tracker', action: 'warn', details: "#{state['consecutive_failures']} failures")
    warn "⚠️  TWO-FIX RULE: #{state['consecutive_failures']} failures. STOP GUESSING. Research before next fix."
  end
else
  # Success - reset counter
  state['consecutive_failures'] = 0
  state['escalated'] = false

  # Reset breaker failure count (but not tripped state)
  breaker = load_state(BREAKER_FILE, method(:default_breaker_state))
  breaker[:failures] = 0
  save_state(BREAKER_FILE, breaker)
end

# Save state
save_state(STATE_FILE, state)

puts({ 'result' => 'continue' }.to_json)
