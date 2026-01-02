#!/usr/bin/env ruby
# frozen_string_literal: true

# Edit Validator Hook - Enforces Rule #1 (STAY IN YOUR LANE) and Rule #10 (FILE SIZE)
#
# Rule #1: Block edits outside project directory
# Rule #10: Warn at 500 lines, block at 800 lines
#
# Exit codes:
# - 0: Edit allowed
# - 1: Edit BLOCKED

require 'json'

# Configuration
PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
SOFT_LIMIT = 500
HARD_LIMIT = 800

# Get tool input from environment
tool_input_raw = ENV['CLAUDE_TOOL_INPUT']
exit 0 if tool_input_raw.nil? || tool_input_raw.empty?

begin
  tool_input = JSON.parse(tool_input_raw)
  file_path = tool_input['file_path']

  exit 0 if file_path.nil? || file_path.empty?

  # =============================================================================
  # Rule #1: STAY IN YOUR LANE - Block edits outside project
  # =============================================================================

  # Normalize paths for comparison
  normalized_path = File.expand_path(file_path)
  normalized_project = File.expand_path(PROJECT_DIR)

  unless normalized_path.start_with?(normalized_project)
    warn ''
    warn '=' * 60
    warn '🔴 BLOCKED: Rule #1 - STAY IN YOUR LANE'
    warn '=' * 60
    warn ''
    warn "   File: #{file_path}"
    warn "   Project: #{PROJECT_DIR}"
    warn ''
    warn '   All files must stay inside the project directory.'
    warn '   If you need to edit files elsewhere, ask the user first.'
    warn ''
    warn '=' * 60
    exit 1
  end

  # =============================================================================
  # Rule #10: FILE SIZE - Warn at 500, block at 800
  # =============================================================================

  if File.exist?(file_path)
    line_count = File.readlines(file_path).count

    # Check if this edit will ADD lines (rough estimate from new_string vs old_string)
    old_string = tool_input['old_string'] || ''
    new_string = tool_input['new_string'] || ''
    lines_added = new_string.lines.count - old_string.lines.count
    projected_count = line_count + lines_added

    if projected_count > HARD_LIMIT
      warn ''
      warn '=' * 60
      warn '🔴 BLOCKED: Rule #10 - FILE TOO LARGE'
      warn '=' * 60
      warn ''
      warn "   File: #{file_path}"
      warn "   Current: #{line_count} lines"
      warn "   After edit: ~#{projected_count} lines"
      warn "   Hard limit: #{HARD_LIMIT} lines"
      warn ''
      warn '   Split this file before continuing:'
      warn '   - Extract a protocol/extension to a new file'
      warn '   - Move related functionality to a helper'
      warn '   - Run xcodegen generate after creating new files'
      warn ''
      warn '=' * 60
      exit 1
    elsif projected_count > SOFT_LIMIT
      warn ''
      warn "⚠️  WARNING: Rule #10 - File approaching size limit"
      warn "   #{file_path}: #{line_count} → ~#{projected_count} lines"
      warn "   Soft limit: #{SOFT_LIMIT} | Hard limit: #{HARD_LIMIT}"
      warn "   Consider splitting soon."
      warn ''
    end
  end

  # All checks passed
  exit 0

rescue JSON::ParserError
  # Not valid JSON, skip validation
  exit 0
rescue StandardError => e
  # Don't block on unexpected errors, just warn
  warn "⚠️  Edit validator error: #{e.message}"
  exit 0
end
