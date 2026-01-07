#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Stop Validator Hook
# ==============================================================================
# Runs when the main Claude agent finishes responding.
# Checks for issues that can't be caught pre-execution.
#
# NOTE: Stop hooks run AFTER the response is sent - can only WARN, not BLOCK.
# Exit code 2 would block Claude from stopping, but response is already shown.
#
# CHECKS:
#   1. Tables in output - tables bypass all PreToolUse hooks
#   2. Session summary status - warn if significant work without summary
#
# Hook Type: Stop
# Exit codes:
#   - 0: Allow Claude to stop (always used - this is post-response)
# ==============================================================================

require 'json'
require 'fileutils'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
EDIT_STATE_FILE = File.join(PROJECT_DIR, '.claude/edit_state.json')
SUMMARY_VALIDATED_FILE = File.join(PROJECT_DIR, '.claude/summary_validated.json')
SUMMARY_REQUIRED_AFTER_EDITS = 25

TABLE_HEADER_SEP = /\|[-:]+\|/
TABLE_ROW = /\|.*\|.*\|/

def get_edit_count
  return 0 unless File.exist?(EDIT_STATE_FILE)

  edit_state = JSON.parse(File.read(EDIT_STATE_FILE), symbolize_names: true)
  edit_state[:edit_count] || 0
rescue StandardError
  0
end

def summary_validated?
  return false unless File.exist?(SUMMARY_VALIDATED_FILE)

  validated = JSON.parse(File.read(SUMMARY_VALIDATED_FILE), symbolize_names: true)
  validated_at = Time.parse(validated[:validated_at])
  Time.now - validated_at < 3600
rescue StandardError
  false
end

def contains_table?(text)
  return false if text.nil? || text.empty?

  lines = text.split("\n")
  lines.any? { |line| line.match?(TABLE_HEADER_SEP) || (line.match?(TABLE_ROW) && line.count('|') >= 3) }
end

def extract_assistant_text(input)
  # Stop hook receives transcript_path, not transcript directly
  transcript_path = input['transcript_path']
  return '' unless transcript_path && File.exist?(transcript_path)

  # Read JSONL transcript
  lines = File.readlines(transcript_path)
  return '' if lines.empty?

  # Find last assistant message
  messages = lines.map { |l| JSON.parse(l) rescue nil }.compact
  last_assistant = messages.reverse.find { |m| m['role'] == 'assistant' }
  return '' unless last_assistant

  content = last_assistant['content']
  return content if content.is_a?(String)

  # Handle array content (Claude's content can be array of blocks)
  if content.is_a?(Array)
    content.select { |block| block['type'] == 'text' }
           .map { |block| block['text'] }
           .join("\n")
  else
    ''
  end
rescue StandardError
  ''
end

# Prevent infinite loops - check if stop hook already running
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

# Check for infinite loop prevention
exit 0 if input['stop_hook_active']

response_text = extract_assistant_text(input)

warnings = []

if contains_table?(response_text)
  warnings << 'TABLE_IN_OUTPUT: Used markdown table in response. Use plain text lists instead.'
end

edit_count = get_edit_count
if edit_count >= SUMMARY_REQUIRED_AFTER_EDITS && !summary_validated?
  warnings << "SUMMARY_PENDING: #{edit_count} edits without validated session summary."
elsif edit_count >= 15 && edit_count < SUMMARY_REQUIRED_AFTER_EDITS
  remaining = SUMMARY_REQUIRED_AFTER_EDITS - edit_count
  warnings << "SUMMARY_REMINDER: #{remaining} edits until session summary required."
end

if warnings.any?
  warn ''
  warnings.each { |w| warn "  ⚠️  #{w}" }
  warn ''
end

exit 0
