#!/usr/bin/env ruby
# frozen_string_literal: true

# Deeper Look Trigger Hook
#
# Watches for patterns indicating discovered issues (hidden features, broken UI, etc.)
# Triggers a reminder to audit related code before moving on.
#
# PostToolUse hook for Grep, Read - analyzes tool output for issue patterns.
#
# Exit codes:
# - 0: Always (reminder only, never blocks)

require 'json'

# Patterns that indicate a discovered issue requiring deeper investigation
ISSUE_PATTERNS = [
  /hidden.*(?:feature|ui|button|control)/i,
  /no\s+(?:ui|button|control|way to)/i,
  /context\s*menu\s*only/i,
  /(?:doesn't|does not|isn't|is not)\s*work/i,
  /not\s+(?:wired|connected|exposed|triggered)/i,
  /broken/i,
  /missing\s+(?:ui|button|control)/i,
  /user.*(?:can't|cannot|no way)/i,
  /undiscoverable/i,
  /right-click\s+(?:only|required|to)/i
].freeze

# Related areas to check when issue is found
RELATED_CHECKS = {
  'UI' => ['grep -r "the_feature" UI/', 'Check if any view references this'],
  'Service' => ['grep -r "the_feature" Core/Services/', 'Check service implementation'],
  'Manager' => ['grep -r "the_feature" Core/*Manager*', 'Check manager wiring'],
  'Tests' => ['grep -r "the_feature" Tests/', 'Check if tests exist']
}.freeze

# Read hook input from stdin
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

tool_name = input['tool_name'] || 'unknown'
tool_output = input['tool_output'] || ''

# Only check relevant tools
exit 0 unless %w[Grep Read].include?(tool_name)

# Check if output contains issue patterns
found_issues = ISSUE_PATTERNS.select { |pattern| tool_output.match?(pattern) }

if found_issues.any?
  warn ''
  warn '=' * 60
  warn '🔍 DEEPER LOOK TRIGGER - Issue Pattern Detected'
  warn '=' * 60
  warn ''
  warn '   You discovered something broken/hidden!'
  warn ''
  warn '   STOP and ask yourself:'
  warn '   ┌─────────────────────────────────────────────────────────┐'
  warn '   │  "What ELSE might be broken that I haven\'t noticed?"   │'
  warn '   └─────────────────────────────────────────────────────────┘'
  warn ''
  warn '   Before fixing this ONE thing, check:'
  warn ''
  warn '   1. Similar patterns in related files:'
  warn '      grep -r "contextMenu" UI/           # Other hidden menus?'
  warn '      grep -r "func.*private" Core/       # Other unexposed features?'
  warn ''
  warn '   2. The full feature chain:'
  warn '      Code (Service) → Manager → UI → User'
  warn '      Is each link actually connected?'
  warn ''
  warn '   3. Other features in the same file:'
  warn '      If one feature is broken, siblings likely are too.'
  warn ''
  warn '   Patterns detected:'
  found_issues.first(3).each do |pattern|
    warn "   • #{pattern.source[0, 40]}..."
  end
  warn ''
  warn '=' * 60
  warn ''
end

exit 0
