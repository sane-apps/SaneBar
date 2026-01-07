#!/usr/bin/env ruby
# frozen_string_literal: true

# Verify Reminder Hook - Lightweight nudge after code edits
#
# PostToolUse hook for Edit on non-test Swift files.
# Just reminds to complete the verification cycle.
#
# Exit codes:
# - 0: Always (reminder only, never blocks)

require 'json'

# Read hook input from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_input = input['tool_input'] || {}
file_path = tool_input['file_path'] || ''

exit 0 if file_path.empty?

# Only remind for Swift source files (not tests, not configs)
exit 0 unless file_path.end_with?('.swift')
exit 0 if file_path.include?('/Tests/')
exit 0 if file_path.include?('Mock')

# Simple reminder
warn ''
warn '📋 VERIFY CYCLE: Edit complete → Now: verify → kill → launch → logs → confirm'
warn ''

exit 0
