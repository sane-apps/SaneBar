#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pattern Learner Hook (PostToolUse)
# ==============================================================================
# Learns from user corrections to build personalized understanding.
#
# How it works:
# 1. Logs what Claude did (tool calls, actions)
# 2. When prompt_analyzer detects correction, correlates with recent actions
# 3. Stores learned patterns: "when user says X, they mean Y (not Z)"
#
# Hook Type: PostToolUse (all tools)
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'rule_tracker'

ACTIONS_LOG_FILE = '.claude/recent_actions.json'
PATTERNS_FILE = '.claude/user_patterns.json'
PROMPT_LOG_FILE = '.claude/prompt_log.jsonl'
MAX_RECENT_ACTIONS = 20

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def load_recent_actions
  return [] unless File.exist?(ACTIONS_LOG_FILE)

  JSON.parse(File.read(ACTIONS_LOG_FILE), symbolize_names: true)
rescue StandardError
  []
end

def save_recent_actions(actions)
  FileUtils.mkdir_p(File.dirname(ACTIONS_LOG_FILE))
  # Keep only recent actions
  actions = actions.last(MAX_RECENT_ACTIONS)
  File.write(ACTIONS_LOG_FILE, JSON.pretty_generate(actions))
end

def load_patterns
  return { learned: [], corrections: 0, last_updated: nil } unless File.exist?(PATTERNS_FILE)

  JSON.parse(File.read(PATTERNS_FILE), symbolize_names: true)
rescue StandardError
  { learned: [], corrections: 0, last_updated: nil }
end

def save_patterns(patterns)
  FileUtils.mkdir_p(File.dirname(PATTERNS_FILE))
  File.write(PATTERNS_FILE, JSON.pretty_generate(patterns))
end

def get_last_user_prompt
  return nil unless File.exist?(PROMPT_LOG_FILE)

  # Read last line of prompt log
  lines = File.readlines(PROMPT_LOG_FILE)
  return nil if lines.empty?

  JSON.parse(lines.last, symbolize_names: true)
rescue StandardError
  nil
end

def summarize_action(tool_name, tool_input)
  case tool_name
  when 'Edit'
    file = tool_input['file_path'] || 'unknown'
    "Edited #{File.basename(file)}"
  when 'Write'
    file = tool_input['file_path'] || 'unknown'
    "Created #{File.basename(file)}"
  when 'Bash'
    cmd = tool_input['command'] || ''
    "Ran: #{cmd[0..50]}..."
  when 'Read'
    file = tool_input['file_path'] || 'unknown'
    "Read #{File.basename(file)}"
  when 'Task'
    desc = tool_input['description'] || 'task'
    "Spawned agent: #{desc}"
  else
    "Used #{tool_name}"
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_name = input['tool_name'] || 'unknown'
tool_input = input['tool_input'] || {}
tool_output = input['tool_output'] || ''
exit_code = input['tool_exit_code'] || 0

# Log this action
actions = load_recent_actions
action_summary = summarize_action(tool_name, tool_input)

actions << {
  timestamp: Time.now.iso8601,
  tool: tool_name,
  summary: action_summary,
  success: exit_code.zero?
}

save_recent_actions(actions)

# Check if the last user prompt had correction signals
# If so, we might need to learn from what we just did
last_prompt = get_last_user_prompt
if last_prompt && last_prompt[:frustration]&.any?
  patterns = load_patterns

  # Find actions since the correction
  correction_time = Time.parse(last_prompt[:timestamp]) rescue nil
  if correction_time
    recent = actions.select do |a|
      action_time = Time.parse(a[:timestamp]) rescue nil
      action_time && action_time > correction_time
    end

    # If we have recent actions after correction, this is what user wanted
    # The correction was about what we did BEFORE
    if recent.length >= 2
      # Log that we're learning
      RuleTracker.log_enforcement(
        rule: :pattern_learning,
        hook: 'pattern_learner',
        action: 'learn',
        details: "Correction followed by #{recent.length} new actions"
      )
    end
  end

  save_patterns(patterns)
end

exit 0
