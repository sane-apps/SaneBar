#!/usr/bin/env ruby
# frozen_string_literal: true

# SOP Mapper / SaneLoop Checkpoint Hook
#
# Enforces periodic check-ins to prevent autopilot coding.
# Triggers when:
# 1. No rule mapping exists (first warning after 2 edits)
# 2. Rule mapping is stale (>30 min old)
# 3. Every 15 tool calls (SaneLoop checkpoint)
#
# To satisfy: Create .claude/sop_state.json with current task/rules

require 'json'
require 'time'
require 'fileutils'
require_relative 'rule_tracker'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
STATE_FILE = File.join(PROJECT_DIR, '.claude', 'sop_state.json')
TOOL_COUNT_FILE = File.join(PROJECT_DIR, '.claude', 'tool_count.json')
STALE_THRESHOLD_MINUTES = 30
CHECKPOINT_INTERVAL = 15

def ensure_claude_dir
  FileUtils.mkdir_p(File.join(PROJECT_DIR, '.claude'))
end

def read_state
  return nil unless File.exist?(STATE_FILE)

  JSON.parse(File.read(STATE_FILE))
rescue JSON::ParserError
  nil
end

def read_tool_count
  return { 'count' => 0, 'session' => nil } unless File.exist?(TOOL_COUNT_FILE)

  JSON.parse(File.read(TOOL_COUNT_FILE))
rescue StandardError
  { 'count' => 0, 'session' => nil }
end

def increment_tool_count(session_id)
  data = read_tool_count

  # Reset on new session
  data = { 'count' => 0, 'session' => session_id, 'last_checkpoint' => 0, 'warned_no_mapping' => false } if data['session'] != session_id

  data['count'] += 1
  File.write(TOOL_COUNT_FILE, JSON.pretty_generate(data))
  data
end

def mark_warned_no_mapping(tool_data)
  tool_data['warned_no_mapping'] = true
  File.write(TOOL_COUNT_FILE, JSON.pretty_generate(tool_data))
end

def state_is_fresh?(state)
  return false unless state && state['timestamp']

  timestamp = Time.parse(state['timestamp'])
  age_minutes = (Time.now - timestamp) / 60
  age_minutes < STALE_THRESHOLD_MINUTES
rescue StandardError
  false
end

def output_checkpoint_form(reason, state, tool_count)
  task = state ? (state['task'] || 'unknown') : 'unknown'
  rules = state ? (state['rules']&.join(', ') || 'none') : 'none'
  warn ''
  warn "📋 SOP CHECK (#{reason}) | Task: #{task} | Rules: #{rules}"
  warn ''
  warn ''
end

def main
  ensure_claude_dir

  # Read tool input from stdin (Claude Code standard)
  input = begin
    JSON.parse($stdin.read)
  rescue StandardError
    {}
  end

  tool_name = input['tool_name'] || ''
  session_id = input['session_id'] || 'unknown'

  # Only check for Edit and Write tools
  return unless %w[Edit Write].include?(tool_name)

  # Skip for plan files and state files
  file_path = input.dig('tool_input', 'file_path') || ''
  return if file_path.include?('plans/')
  return if file_path.include?('.claude/')

  # Track tool calls
  tool_data = increment_tool_count(session_id)
  tool_count = tool_data['count']
  last_checkpoint = tool_data['last_checkpoint'] || 0

  # Check if checkpoint is due (every CHECKPOINT_INTERVAL tool calls)
  checkpoint_due = (tool_count - last_checkpoint) >= CHECKPOINT_INTERVAL

  # First 2 edits get a pass
  return if tool_count <= 2 && !checkpoint_due

  # Check SOP state
  state = read_state

  # Determine if we need to show the checkpoint
  reason = nil
  already_warned = tool_data['warned_no_mapping']

  if state.nil? && tool_count > 2 && !already_warned
    # First warning about no mapping - only warn once per session
    reason = 'No rule mapping found (first warning)'
    mark_warned_no_mapping(tool_data)
  elsif state && !state['rules_mapped'] && !already_warned
    reason = 'Rules not marked as mapped'
    mark_warned_no_mapping(tool_data)
  elsif state && !state_is_fresh?(state)
    age = begin
      ((Time.now - Time.parse(state['timestamp'])) / 60).round
    rescue StandardError
      999
    end
    reason = "Rule mapping stale (#{age} min old)"
  elsif checkpoint_due
    reason = "Periodic checkpoint (#{tool_count} tool calls)"
    # Update last checkpoint
    tool_data['last_checkpoint'] = tool_count
    File.write(TOOL_COUNT_FILE, JSON.pretty_generate(tool_data))
  end

  return unless reason

  RuleTracker.log_enforcement(rule: 0, hook: 'sop_mapper', action: 'checkpoint', details: reason)
  output_checkpoint_form(reason, state, tool_count)
end

main if __FILE__ == $PROGRAM_NAME
