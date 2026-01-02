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

  # Empty or trivial comparisons
  /#expect\s*\(\s*\w+\s*==\s*\w+\s*\)/, # expect(x == x)

  # Placeholder assertions
  /XCTAssert.*TODO/i,
  /XCTAssert.*FIXME/i,
  /#expect.*TODO/i,
  /#expect.*FIXME/i,

  # Force unwrap in test (not a tautology but bad practice)
  /#expect\s*\([^)]*!\s*[^=]/
].freeze

# Weak assertion patterns (warn but less severe)
WEAK_PATTERNS = [
  # Testing for not-nil only (should test actual value)
  /#expect\s*\([^)]+\s*!=\s*nil\s*\)/i,
  /XCTAssertNotNil\s*\(/i,

  # Very short test bodies (might be incomplete)
  /func\s+test\w+\s*\(\s*\)\s*(throws\s*)?\{\s*\}/
].freeze

# Get tool input from environment
tool_input_raw = ENV.fetch('CLAUDE_TOOL_INPUT', nil)
exit 0 if tool_input_raw.nil? || tool_input_raw.empty?

begin
  tool_input = JSON.parse(tool_input_raw)
  file_path = tool_input['file_path']

  exit 0 if file_path.nil? || file_path.empty?

  # Only check test files - must be in Tests/ directory (avoid false positives like NotATest.swift)
  exit 0 unless file_path.include?('/Tests/')

  # For Edit tool, check new_string; for Write tool, check content
  content = tool_input['new_string'] || tool_input['content'] || ''
  exit 0 if content.empty?

  # Collect issues
  tautologies = []
  weak_assertions = []

  # Skip tautology check if there's an explicit REASON or INTENTIONAL comment
  # (developer knows what they're doing)
  skip_tautology = content.match?(%r{//\s*(REASON|INTENTIONAL|PLACEHOLDER):}i)

  # Check for tautology patterns
  unless skip_tautology
    TAUTOLOGY_PATTERNS.each do |pattern|
      matches = content.scan(pattern)
      tautologies.concat(matches) unless matches.empty?
    end
  end

  # Check for weak patterns
  WEAK_PATTERNS.each do |pattern|
    matches = content.scan(pattern)
    weak_assertions.concat(matches) unless matches.empty?
  end

  # Report issues
  if tautologies.any?
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

  if weak_assertions.any? && tautologies.empty?
    warn ''
    warn '⚠️  Note: Weak assertions detected in test'
    warn "   File: #{file_path}"
    warn '   Consider testing actual values, not just nil checks.'
    warn ''
  end

  # Always exit 0 (don't block, just warn)
  exit 0
rescue JSON::ParserError
  # Not valid JSON, skip validation
  exit 0
rescue StandardError => e
  # Don't block on unexpected errors, just warn
  warn "⚠️  Test quality checker error: #{e.message}"
  exit 0
end
