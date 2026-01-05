#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Quality Checker Hook - Enforces Rule #7 (NO TEST? NO REST)
#
# Detects tautology tests that always pass:
# - #expect(true) or XCTAssertTrue(true)
# - #expect(x == true || x == false) - always true logic
# - Empty test bodies
# - TODO/FIXME placeholders in assertions
#
# This is a PostToolUse hook for Edit/Write on test files.
# It WARNS but does not block (allows quick iteration).
#
# Exit codes:
# - 0: Always (warnings only)

require 'json'
require_relative 'rule_tracker'

# Tautology patterns to detect
TAUTOLOGY_PATTERNS = [
  # Literal true/false assertions
  /#expect\s*\(\s*true\s*\)/i,
  /#expect\s*\(\s*false\s*\)/i,
  /XCTAssertTrue\s*\(\s*true\s*\)/i,
  /XCTAssertFalse\s*\(\s*false\s*\)/i,
  /XCTAssert\s*\(\s*true\s*\)/i,

  # Always-true boolean logic (x == true || x == false)
  /#expect\s*\([^)]+==\s*true\s*\|\|\s*[^)]+==\s*false\s*\)/i,
  /#expect\s*\([^)]+==\s*false\s*\|\|\s*[^)]+==\s*true\s*\)/i,

  # Placeholder assertions
  /XCTAssert.*TODO/i,
  /XCTAssert.*FIXME/i,
  /#expect.*TODO/i,
  /#expect.*FIXME/i
].freeze

# Read hook input from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_input = input['tool_input'] || input
file_path = tool_input['file_path']

exit 0 if file_path.nil? || file_path.empty?

# Only check test files
exit 0 unless file_path.include?('/Tests/') || file_path.match?(/Tests?\.swift$/)

# For Edit tool, check new_string; for Write tool, check content
content = tool_input['new_string'] || tool_input['content'] || ''
exit 0 if content.empty?

# Collect issues
tautologies = []

# Check for tautology patterns
TAUTOLOGY_PATTERNS.each do |pattern|
  matches = content.scan(pattern)
  tautologies.concat(matches) unless matches.empty?
end

# Report issues
if tautologies.any?
  RuleTracker.log_enforcement(rule: 7, hook: 'test_quality_checker', action: 'warn', details: "#{tautologies.count} tautologies in #{file_path}")
  warn ''
  warn '=' * 60
  warn '⚠️  WARNING: Rule #7 - TAUTOLOGY TEST DETECTED'
  warn '=' * 60
  warn ''
  warn "   File: #{file_path}"
  warn ''
  warn '   These assertions always pass (useless tests):'
  tautologies.first(5).each do |match|
    warn "   • #{match.to_s.strip[0, 50]}..."
  end
  warn ''
  warn '   A good test should:'
  warn '   • Test actual computed values, not literals'
  warn '   • Verify behavior, not implementation'
  warn '   • Fail when the code is broken'
  warn ''
  warn '   Examples of GOOD assertions:'
  warn '   • #expect(result.count == 3)'
  warn '   • #expect(error.code == .invalidInput)'
  warn '   • #expect(viewModel.isLoading == false)'
  warn ''
  warn '=' * 60
  warn ''
end

# Always exit 0 (don't block, just warn)
exit 0
