# frozen_string_literal: true

require_relative 'tracking'

module SaneTrack
  module Tautology
    TEST_FILE_PATTERN = %r{(Tests?/|Specs?/|_test\.|_spec\.|Tests?\.swift|Spec\.swift)}i.freeze

    TAUTOLOGY_PATTERNS = [
      /#expect\s*\(\s*true\s*\)/i,
      /#expect\s*\(\s*false\s*\)/i,
      /XCTAssertTrue\s*\(\s*true\s*\)/i,
      /XCTAssertFalse\s*\(\s*false\s*\)/i,
      /XCTAssert\s*\(\s*true\s*\)/i,
      /#expect\s*\([^)]+==\s*true\s*\|\|\s*[^)]+==\s*false\s*\)/i,
      /XCTAssert.*TODO/i,
      /#expect.*TODO/i,
      /#expect\s*\(\s*(\w+)\s*==\s*\1\s*\)/,
      /XCTAssertEqual\s*\(\s*(\w+)\s*,\s*\1\s*\)/,
      /#expect\s*\([^)]+\s*!=\s*nil\s*\)\s*$/,
      /XCTAssertNotNil\s*\(\s*\w+\s*\)\s*$/,
      /#expect\s*\([^)]+\.count\s*>=\s*0\s*\)/i,
      /XCTAssertGreaterThanOrEqual\s*\([^,]+\.count\s*,\s*0\s*\)/i,
      /#expect\s*\(\s*\)/,
      /XCTAssert\s*\(\s*\)/
    ].freeze

    def self.check_tautologies(tool_name, tool_input)
      return nil unless Tracking::EDIT_TOOLS.include?(tool_name)

      file_path = tool_input['file_path'] || tool_input[:file_path] || ''
      return nil unless file_path.match?(TEST_FILE_PATTERN)

      new_string = tool_input['new_string'] || tool_input[:new_string] || ''
      return nil if new_string.empty?

      matches = TAUTOLOGY_PATTERNS.select { |pattern| new_string.match?(pattern) }
      return nil if matches.empty?

      "RULE #7 WARNING: Test contains tautology (always passes)\n" \
      "   File: #{File.basename(file_path)}\n" \
      "   Found: #{matches.length} suspicious pattern(s)\n" \
      "   Fix: Replace with meaningful assertions that test actual behavior"
    end
  end
end
