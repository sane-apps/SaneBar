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
BYPASS_FILE = File.join(PROJECT_DIR, '.claude/bypass_active.json')
READ_HISTORY_FILE = File.join(PROJECT_DIR, '.claude/read_history.json')

# Skip enforcement if bypass is active
exit 0 if File.exist?(BYPASS_FILE)

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
# READ-BEFORE-EDIT: Warn if editing a file that wasn't read first
# =============================================================================

def file_was_read?(path)
  return true unless File.exist?(READ_HISTORY_FILE)

  history = begin
    JSON.parse(File.read(READ_HISTORY_FILE))
  rescue StandardError
    { 'files' => [] }
  end

  normalized = File.expand_path(path)
  history['files'].include?(normalized)
end

# Only check for existing files (new files don't need to be read first)
if File.exist?(file_path) && !file_was_read?(file_path)
  # Skip warning for certain file types that are OK to edit without reading
  skip_read_check = file_path.match?(/\.(json|lock|sum)$/) ||
                    file_path.include?('.claude/') ||
                    file_path.include?('node_modules/')

  unless skip_read_check
    RuleTracker.log_enforcement(rule: 2, hook: 'edit_validator', action: 'warn', details: "Edit without Read: #{file_path}")
    warn ''
    warn '⚠️  WARNING: Rule #2 - Editing file not yet read this session'
    warn "   File: #{file_path}"
    warn '   VERIFY BEFORE YOU TRY: Read files before proposing edits.'
    warn '   Use Read tool first to understand existing code.'
    warn ''
  end
end

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
  warn "🔴 BLOCKED: Rule #1 - Dangerous path: #{file_path}"
  warn ''
  exit 2 # Exit code 2 = BLOCK in Claude Code
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
    warn ''
    warn "🔴 BLOCKED: Rule #1 - Outside home: #{file_path}"
    warn ''
    exit 2 # Exit code 2 = BLOCK in Claude Code
  end
end

# =============================================================================
# Rule #10: FILE SIZE - Warn at 500, block at 800 (or 1500 for .md docs)
# =============================================================================

if File.exist?(file_path)
  line_count = File.readlines(file_path).count

  # Check if this edit will ADD lines
  old_string = tool_input['old_string'] || ''
  new_string = tool_input['new_string'] || ''
  lines_added = new_string.lines.count - old_string.lines.count
  projected_count = line_count + lines_added

  # .md files get higher limits - documentation is naturally longer
  is_markdown = file_path.end_with?('.md')
  effective_soft = is_markdown ? 1000 : SOFT_LIMIT
  effective_hard = is_markdown ? 1500 : HARD_LIMIT

  if projected_count > effective_hard
    RuleTracker.log_violation(rule: 10, hook: 'edit_validator', reason: "#{projected_count} lines > #{effective_hard} limit")
    warn ''
    warn "🔴 BLOCKED: Rule #10 - #{projected_count} lines > #{effective_hard} limit. Split file first."
    warn ''
    exit 2 # Exit code 2 = BLOCK in Claude Code
  elsif projected_count > effective_soft
    RuleTracker.log_enforcement(rule: 10, hook: 'edit_validator', action: 'warn', details: "#{projected_count} lines > #{effective_soft} soft limit")
    warn ''
    warn '⚠️  WARNING: Rule #10 - File approaching size limit'
    warn "   #{file_path}: #{line_count} → ~#{projected_count} lines"
    warn "   Soft limit: #{effective_soft} | Hard limit: #{effective_hard}"
    warn '   Consider splitting soon.'
    warn ''
  end
end

# =============================================================================
# TABLE BAN - No markdown tables (they render terribly in terminal)
# =============================================================================

content = tool_input['new_string'] || tool_input['content'] || ''

# Detect markdown table patterns
table_patterns = [
  /\|[-:]+\|/,           # |---|---| header separator
  /^\s*\|.*\|.*\|/m,     # | col | col | rows
]

if table_patterns.any? { |p| content.match?(p) }
  # Count pipes to confirm it's really a table (not just a single |)
  pipe_lines = content.lines.count { |l| l.count('|') >= 2 }

  if pipe_lines >= 2
    RuleTracker.log_violation(rule: :no_tables, hook: 'edit_validator', reason: 'Markdown table detected')
    warn ''
    warn '🔴 BLOCKED: No tables. Use plain lists instead.'
    warn ''
    exit 2
  end
end

# All checks passed
exit 0
