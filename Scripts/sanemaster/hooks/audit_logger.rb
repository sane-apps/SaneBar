#!/usr/bin/env ruby
# frozen_string_literal: true

# Audit Logger Hook - Creates structured decision trail
#
# Logs all tool calls to .claude/audit_log.jsonl with:
# - Timestamp
# - Tool name
# - File path (if applicable)
# - Rule checks performed
# - Result (pass/warn/block)
#
# This is a PostToolUse hook for observability.

require 'json'
require 'fileutils'

LOG_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'audit_log.jsonl')

# Ensure directory exists
FileUtils.mkdir_p(File.dirname(LOG_FILE))

# Read hook input from stdin (PostToolUse format)
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

tool_name = input['tool_name'] || ENV['CLAUDE_TOOL_NAME'] || 'unknown'
tool_input = input['tool_input'] || {}
tool_output = input['tool_output'] || ''
session_id = input['session_id'] || 'unknown'

# Extract file path if present
file_path = tool_input['file_path'] || tool_input['path'] || nil
command = tool_input['command'] if tool_name == 'Bash'

# Determine which rules were checked based on tool type
rules_checked = []
result = 'pass'

case tool_name
when 'Edit'
  rules_checked << '#1:STAY_IN_LANE'
  rules_checked << '#10:FILE_SIZE'
  rules_checked << '#7:TEST_QUALITY' if file_path&.include?('/Tests/')
when 'Write'
  rules_checked << '#1:STAY_IN_LANE'
  rules_checked << '#7:TEST_QUALITY' if file_path&.include?('/Tests/')
when 'Bash'
  rules_checked << '#5:SANEMASTER' if command&.include?('SaneMaster')
  rules_checked << '#6:FULL_CYCLE' if command&.match?(/verify|test|build/)
when 'Skill'
  skill = tool_input['skill'] || ''
  rules_checked << '#RALPH:EXIT_CONDITION' if skill.include?('sane_loop')
end

# Check for warnings/blocks in stderr (captured by hooks)
# This is a heuristic - actual blocking happens in PreToolUse hooks
if tool_output.include?('BLOCKED')
  result = 'blocked'
elsif tool_output.include?('WARNING')
  result = 'warn'
end

# Build log entry
log_entry = {
  timestamp: Time.now.utc.iso8601,
  session: session_id,
  tool: tool_name,
  file: file_path,
  command: command&.slice(0, 100), # Truncate long commands
  rules_checked: rules_checked,
  result: result
}.compact

# Append to log file
File.open(LOG_FILE, 'a') do |f|
  f.puts(log_entry.to_json)
end

# Rotate log if too large (>1MB)
if File.exist?(LOG_FILE) && File.size(LOG_FILE) > 1_000_000
  # Keep last 500 entries
  lines = File.readlines(LOG_FILE)
  File.write(LOG_FILE, lines.last(500).join)
end

# Always continue (observability only, never blocks)
puts({ 'result' => 'continue' }.to_json)
