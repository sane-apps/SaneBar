#!/usr/bin/env ruby
# frozen_string_literal: true

# Circuit Breaker Hook - Blocks tool calls after N consecutive failures
# Prevents runaway AI loops (learned from 700+ iteration failure 2026-01-02)
#
# Behavior:
# - Tracks consecutive failures in .claude/circuit_breaker.json
# - At 3 failures: BLOCKS Edit, Bash, Write tools
# - Requires manual reset: ./Scripts/SaneMaster.rb reset_breaker
#
# Exit codes:
# - 0: Tool call allowed
# - 1: Tool call BLOCKED (breaker tripped)

require 'json'
require 'fileutils'

STATE_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'circuit_breaker.json')
DEFAULT_THRESHOLD = 3
BLOCKED_TOOLS = %w[Edit Bash Write].freeze

def load_state
  return default_state unless File.exist?(STATE_FILE)

  JSON.parse(File.read(STATE_FILE), symbolize_names: true)
rescue JSON::ParserError
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

# Get tool name from environment
tool_name = ENV['CLAUDE_TOOL_NAME']
exit 0 if tool_name.nil? || tool_name.empty?

# Check if this tool should be blocked
exit 0 unless BLOCKED_TOOLS.include?(tool_name)

# Load circuit breaker state
state = load_state

# If breaker is tripped, BLOCK the tool call
if state[:tripped]
  warn ''
  warn '=' * 60
  warn '🔴 CIRCUIT BREAKER OPEN - TOOL CALL BLOCKED'
  warn '=' * 60
  warn ''
  warn "   Breaker tripped at: #{state[:tripped_at]}"
  warn "   Reason: #{state[:trip_reason] || 'Unknown'}"
  warn "   Total failures: #{state[:failures]}"
  warn "   Blocked tools: #{BLOCKED_TOOLS.join(', ')}"
  warn ''
  warn '   This safety mechanism prevents runaway AI loops.'
  warn '   (Learned from 700+ iteration failure on 2026-01-02)'
  warn ''
  warn '   To reset:'
  warn '     ./Scripts/SaneMaster.rb reset_breaker'
  warn ''
  warn '   Then investigate what caused the failures before continuing.'
  warn ''
  warn '=' * 60
  exit 1
end

# Breaker not tripped - allow the call
# Warn if getting close to threshold
if state[:failures] > 0
  remaining = state[:threshold] - state[:failures]
  if remaining == 1
    warn "⚠️  WARNING: Circuit breaker at #{state[:failures]}/#{state[:threshold]} failures!"
    warn '   One more failure will BLOCK all Edit/Bash/Write tools.'
    warn '   Consider stopping to investigate before continuing.'
  elsif remaining <= 2
    warn "⚠️  Circuit breaker: #{state[:failures]}/#{state[:threshold]} failures"
  end
end

exit 0
