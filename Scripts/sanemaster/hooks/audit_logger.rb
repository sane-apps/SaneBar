#!/usr/bin/env ruby
# frozen_string_literal: true

# Audit Logger Hook - Tracks all tool decisions for post-mortem analysis
#
# Logs every tool call with:
# - Timestamp
# - Tool name
# - File path (if applicable)
# - Session ID
# - Outcome (allowed/blocked)
#
# This is a PostToolUse hook that runs after every tool call.
# Logs are written to .claude/audit.jsonl (JSON Lines format).
#
# Exit codes:
# - 0: Always (logging should never block)

require 'json'
require 'fileutils'

AUDIT_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'audit.jsonl')
MAX_LOG_SIZE = 1_000_000 # 1MB - rotate after this

def rotate_if_needed
  return unless File.exist?(AUDIT_FILE) && File.size(AUDIT_FILE) > MAX_LOG_SIZE

  # Keep last 500KB of logs
  content = File.read(AUDIT_FILE)
  lines = content.lines
  half = lines.size / 2
  File.write(AUDIT_FILE, lines[half..].join)
end

def extract_file_path(tool_input)
  return nil unless tool_input.is_a?(Hash)

  tool_input['file_path'] || tool_input.dig('tool_input', 'file_path')
end

def determine_outcome(tool_output)
  return 'unknown' if tool_output.nil? || tool_output.empty?

  # Check for common error patterns
  if tool_output.match?(/BLOCKED|exit 1|error:/i)
    'blocked'
  elsif tool_output.match?(/WARNING/i)
    'warning'
  else
    'allowed'
  end
end

# Read hook input from stdin
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_name = input['tool_name'] || 'unknown'
tool_input = input['tool_input'] || {}
tool_output = input['tool_output'] || ''
session_id = input['session_id'] || ENV['CLAUDE_SESSION_ID'] || 'unknown'

# Build log entry
entry = {
  timestamp: Time.now.utc.iso8601,
  session_id: session_id,
  tool: tool_name,
  file: extract_file_path(tool_input),
  outcome: determine_outcome(tool_output)
}

# Add error snippet if blocked
if entry[:outcome] == 'blocked' && tool_output.is_a?(String)
  # Extract first line of error
  first_error = tool_output.lines.find { |l| l.match?(/BLOCKED|error:/i) }
  entry[:error] = first_error&.strip&.slice(0, 100)
end

# Write to audit log
begin
  FileUtils.mkdir_p(File.dirname(AUDIT_FILE))
  rotate_if_needed

  File.open(AUDIT_FILE, 'a') do |f|
    f.puts(JSON.generate(entry))
  end
rescue StandardError => e
  warn "⚠️  Audit logger error: #{e.message}"
end

exit 0
