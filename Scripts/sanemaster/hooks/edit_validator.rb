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
require_relative 'rule_tracker'

# Configuration
PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
SOFT_LIMIT = 500
HARD_LIMIT = 800

# Paths that should ALWAYS be blocked (dangerous/system paths)
BLOCKED_PATHS = [
  '/var',
  '/etc',
  '/usr',
  '/System',
  '/Library',
  '/private',
  File.expand_path('~/.claude'),
  File.expand_path('~/.config'),
  File.expand_path('~/.ssh'),
  File.expand_path('~/.aws')
].freeze

# User's home directory (cross-project work allowed with warning)
USER_HOME = File.expand_path('~')

# Read hook input from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_input = input['tool_input'] || input
file_path = tool_input['file_path']

exit 0 if file_path.nil? || file_path.empty?

# =============================================================================
# Rule #1: STAY IN YOUR LANE - Block dangerous paths, warn on cross-project
# =============================================================================

# Normalize paths for comparison
normalized_path = File.expand_path(file_path)
normalized_path = File.realpath(file_path) if File.exist?(file_path) && File.symlink?(file_path)
normalized_project = File.expand_path(PROJECT_DIR)

# Check 1: BLOCK dangerous/system paths (never allow)
if BLOCKED_PATHS.any? { |blocked| normalized_path.start_with?(blocked) }
  RuleTracker.log_violation(rule: 1, hook: 'edit_validator', reason: "Dangerous path: #{file_path}")
  warn ''
  warn '=' * 60
  warn '🔴 BLOCKED: Rule #1 - DANGEROUS PATH'
  warn '=' * 60
  warn ''
  warn "   File: #{file_path}"
  warn ''
  warn '   This path is blocked for safety reasons:'
  warn '   - System directories (/etc, /usr, /System, /Library)'
  warn '   - Temp directories (/var, /private)'
  warn '   - Sensitive config (~/.ssh, ~/.aws, ~/.claude)'
  warn ''
  warn '=' * 60
  exit 1
end

# Check 2: WARN on cross-project (user can still approve)
unless normalized_path.start_with?(normalized_project)
  warn ''
  if normalized_path.start_with?(USER_HOME)
    # It's in user home but different project - warn but allow
    RuleTracker.log_enforcement(rule: 1, hook: 'edit_validator', action: 'warn', details: "Cross-project: #{file_path}")
    warn '⚠️  WARNING: Rule #1 - Cross-project edit'
    warn "   Current project: #{PROJECT_DIR}"
    warn "   Target file: #{file_path}"
    warn ''
    warn '   If user requested this cross-project work, proceeding...'
    warn '   Otherwise, stay in your lane!'
    warn ''
  else
    # Outside user home entirely - block
    RuleTracker.log_violation(rule: 1, hook: 'edit_validator', reason: "Outside home: #{file_path}")
    warn '=' * 60
    warn '🔴 BLOCKED: Rule #1 - STAY IN YOUR LANE'
    warn '=' * 60
    warn ''
    warn "   File: #{file_path}"
    warn "   Project: #{PROJECT_DIR}"
    warn ''
    warn '   Path is outside your home directory.'
    warn '   Ask the user before editing system files.'
    warn ''
    warn '=' * 60
    exit 1
  end
end

# =============================================================================
# Rule #10: FILE SIZE - Warn at 500, block at 800
# =============================================================================

if File.exist?(file_path)
  line_count = File.readlines(file_path).count

  # Check if this edit will ADD lines
  old_string = tool_input['old_string'] || ''
  new_string = tool_input['new_string'] || ''
  lines_added = new_string.lines.count - old_string.lines.count
  projected_count = line_count + lines_added

  if projected_count > HARD_LIMIT
    RuleTracker.log_violation(rule: 10, hook: 'edit_validator', reason: "#{projected_count} lines > #{HARD_LIMIT} limit")
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
    warn '   - Run project generator after creating new files'
    warn ''
    warn '=' * 60
    exit 1
  elsif projected_count > SOFT_LIMIT
    RuleTracker.log_enforcement(rule: 10, hook: 'edit_validator', action: 'warn', details: "#{projected_count} lines > #{SOFT_LIMIT} soft limit")
    warn ''
    warn '⚠️  WARNING: Rule #10 - File approaching size limit'
    warn "   #{file_path}: #{line_count} → ~#{projected_count} lines"
    warn "   Soft limit: #{SOFT_LIMIT} | Hard limit: #{HARD_LIMIT}"
    warn '   Consider splitting soon.'
    warn ''
  end
end

# All checks passed
exit 0
