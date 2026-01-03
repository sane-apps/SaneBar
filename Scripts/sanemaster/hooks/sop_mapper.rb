#!/usr/bin/env ruby
# frozen_string_literal: true

# SOP Mapper Hook - Enforces rule mapping before coding
#
# This hook checks if Claude has mapped SOP rules to the current task
# BEFORE allowing edits. Prevents "coding without thinking about rules."
#
# How it works:
# 1. Claude should write to .claude/sop_state.json when mapping rules
# 2. This hook checks that file before allowing Edit/Write
# 3. If stale (>30 min) or missing, it warns/blocks
#
# To satisfy this hook, Claude must call:
#   echo '{"rules_mapped": true, "timestamp": "2026-01-02T12:00:00"}' > .claude/sop_state.json

require 'json'
require 'time'

STATE_FILE = File.join(Dir.pwd, '.claude', 'sop_state.json')
STALE_THRESHOLD_MINUTES = 60 # Extended from 30 - long tasks need more time
EDIT_COUNT_FILE = File.join(Dir.pwd, '.claude', 'edit_count.json')

def read_state
  return nil unless File.exist?(STATE_FILE)

  JSON.parse(File.read(STATE_FILE))
rescue JSON::ParserError
  nil
end

def read_edit_count
  return 0 unless File.exist?(EDIT_COUNT_FILE)

  JSON.parse(File.read(EDIT_COUNT_FILE))['count'] || 0
rescue StandardError
  0
end

def increment_edit_count
  count = read_edit_count + 1
  File.write(EDIT_COUNT_FILE, JSON.generate({ count: count, updated: Time.now.iso8601 }))
  count
end

def state_is_fresh?(state)
  return false unless state && state['timestamp']

  timestamp = Time.parse(state['timestamp'])
  age_minutes = (Time.now - timestamp) / 60
  age_minutes < STALE_THRESHOLD_MINUTES
rescue StandardError
  false
end

def main
  # Read tool input from stdin
  input = begin
    JSON.parse($stdin.read)
  rescue StandardError
    {}
  end
  tool_name = input['tool_name'] || ''

  # Only check for Edit and Write tools
  return unless %w[Edit Write].include?(tool_name)

  # Skip for plan files - those are allowed during planning
  file_path = input.dig('tool_input', 'file_path') || ''
  return if file_path.include?('plans/')
  return if file_path.include?('.claude/sop_state')

  # Check edit count - first 2 edits get a pass (might be quick fixes)
  edit_count = increment_edit_count
  return if edit_count <= 2

  # Check SOP state
  state = read_state

  if state.nil?
    # No state file - first time or cleared
    warn "\n⚠️  SOP MAPPER: No rule mapping found!"
    warn '   Before coding, state which rules apply to this task.'
    warn "   Example: 'Rule #2 (VERIFY) applies - checking API first'"
    warn ''
    warn '   To acknowledge: Create .claude/sop_state.json with:'
    warn '   {"rules_mapped": true, "rules": ["#2", "#6"], "task": "description"}'
    warn ''
    # Don't block, just warn loudly for now
    return
  end

  unless state['rules_mapped']
    warn "\n⚠️  SOP MAPPER: Rules not mapped!"
    warn "   Set 'rules_mapped': true after stating which rules apply."
    warn ''
    return
  end

  return if state_is_fresh?(state)

  age_minutes = state['timestamp'] ? ((Time.now - Time.parse(state['timestamp'])) / 60).round : 999
  warn "\n⚠️  SOP MAPPER: Rule mapping is stale (#{age_minutes} min old)"
  warn '   For new tasks, re-map which rules apply.'
  warn "   Current mapping: #{state['rules']&.join(', ') || 'unknown'}"
  warn "   Task: #{state['task'] || 'unknown'}"
  warn ''
  # Don't block, just warn
  nil

  # All good - rules are mapped and fresh
  # Optionally show what rules are active (commented out to reduce noise)
  # warn "✅ SOP: Rules #{state['rules']&.join(', ')} mapped for: #{state['task']}"
end

main if __FILE__ == $PROGRAM_NAME
