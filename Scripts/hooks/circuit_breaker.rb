#!/usr/bin/env ruby
# frozen_string_literal: true

# Circuit Breaker Hook - Blocks tool calls after N consecutive failures
# Prevents runaway AI loops (learned from 700+ iteration failure)
#
# Behavior:
# - Tracks consecutive failures in .claude/circuit_breaker.json
# - At 3 failures: BLOCKS Edit, Bash, Write tools
# - Requires manual reset: ./Scripts/<tool> reset_breaker
#
# Exit codes:
# - 0: Tool call allowed
# - 1: Tool call BLOCKED (breaker tripped)

require 'json'
require 'fileutils'
require_relative 'rule_tracker'
require_relative 'state_signer'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
STATE_FILE = File.join(PROJECT_DIR, '.claude', 'circuit_breaker.json')
BYPASS_FILE = File.join(PROJECT_DIR, '.claude/bypass_active.json')
DEFAULT_THRESHOLD = 3
BLOCKED_TOOLS = %w[Edit Bash Write].freeze

# Skip enforcement if bypass is active
exit 0 if File.exist?(BYPASS_FILE)

def load_state
  # VULN-003 FIX: Use signed state files
  data = StateSigner.read_verified(STATE_FILE)
  return default_state if data.nil?

  # Symbolize keys for compatibility
  data.transform_keys(&:to_sym)
rescue StandardError
  default_state
end

def default_state
  {
    failures: 0,
    tripped: false,
    tripped_at: nil,
    last_failure: nil,
    threshold: DEFAULT_THRESHOLD
  }
end

# Read hook input from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_name = input['tool_name'] || ENV.fetch('CLAUDE_TOOL_NAME', nil)
exit 0 if tool_name.nil? || tool_name.empty?

# Check if this tool should be blocked
exit 0 unless BLOCKED_TOOLS.include?(tool_name)

# Load circuit breaker state
state = load_state

# If breaker is tripped, BLOCK the tool call
if state[:tripped]
  RuleTracker.log_violation(rule: 3, hook: 'circuit_breaker', reason: "Blocked #{tool_name} - #{state[:failures]} failures")
  warn ''
  warn "🔴 CIRCUIT BREAKER OPEN | #{state[:failures]} failures | #{state[:trip_reason] || 'Unknown'}"
  warn '   Research the problem, present plan, get approval, then: ./Scripts/<tool> reset_breaker'
  warn ''
  exit 2 # Exit code 2 = BLOCK in Claude Code
end

# Breaker not tripped - allow the call
# Warn if getting close to threshold
if state[:failures].positive?
  remaining = state[:threshold] - state[:failures]
  if remaining == 1
    RuleTracker.log_enforcement(rule: 3, hook: 'circuit_breaker', action: 'warn', details: "#{state[:failures]}/#{state[:threshold]} failures")
    warn "⚠️  WARNING: Circuit breaker at #{state[:failures]}/#{state[:threshold]} failures!"
    warn '   One more failure will BLOCK all Edit/Bash/Write tools.'
    warn '   Consider stopping to investigate before continuing.'
  elsif remaining <= 2
    RuleTracker.log_enforcement(rule: 3, hook: 'circuit_breaker', action: 'remind', details: "#{state[:failures]}/#{state[:threshold]} failures")
    warn "⚠️  Circuit breaker: #{state[:failures]}/#{state[:threshold]} failures"
  end
end

exit 0
