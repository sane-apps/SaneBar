#!/usr/bin/env ruby
# frozen_string_literal: true

# Deeper Look Trigger + SaneCop Hook
#
# Two functions in one hook:
# 1. DEEPER LOOK: Watches for patterns indicating discovered issues
# 2. SANE COP: Watches for weasel words indicating rule violations
#
# PostToolUse hook for Grep, Read, Bash - analyzes tool output.
#
# Exit codes:
# - 0: Always (reminder only, never blocks)

require 'json'

# === DEEPER LOOK: Issue patterns requiring investigation ===
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

# === SANE COP: Weasel word patterns indicating SOP violations ===
WEASEL_PATTERNS = {
  # Workarounds (Rule #5, #11)
  /\bmanually\b/i => {
    rule: '#5 / #11',
    msg: 'Use project tools, not manual steps. If tool is broken, fix it.',
    severity: :warning
  },
  /\bby hand\b/i => {
    rule: '#5',
    msg: 'Automate it - use project tools.',
    severity: :warning
  },

  # Giving up (Rule #3, #11)
  /tool (didn't|did not|doesn't|does not) work/i => {
    rule: '#11',
    msg: 'TOOL BROKE? FIX THE YOKE - fix the tool, don\'t work around it.',
    severity: :alert
  },
  /couldn't get.*to work/i => {
    rule: '#11',
    msg: 'If a tool fails, fix it. Don\'t work around.',
    severity: :warning
  },
  /tried.*didn't work/i => {
    rule: '#3',
    msg: 'TWO STRIKES? INVESTIGATE - research before third attempt.',
    severity: :warning
  },

  # Guessing (Rule #2)
  /should work/i => {
    rule: '#6',
    msg: 'VERIFY, don\'t hope. Run the full cycle.',
    severity: :warning
  },
  /probably fine/i => {
    rule: '#4 / #6',
    msg: 'GREEN MEANS GO - verify tests pass, don\'t assume.',
    severity: :warning
  },
  /I('ll| will) assume/i => {
    rule: '#2',
    msg: 'VERIFY BEFORE YOU TRY - check docs, don\'t assume.',
    severity: :alert
  },
  /I remember/i => {
    rule: '#2',
    msg: 'Check docs, don\'t trust memory. APIs change.',
    severity: :info
  },

  # Deferring (Rule #8)
  /fix (it |this )?later/i => {
    rule: '#8',
    msg: 'BUG FOUND? WRITE IT DOWN - use TodoWrite now.',
    severity: :warning
  },
  /\beventually\b/i => {
    rule: '#8',
    msg: 'Track it now or lose it forever.',
    severity: :info
  },
  /TODO:\s*fix/i => {
    rule: '#8',
    msg: 'Use TodoWrite, not code comments for tracking.',
    severity: :info
  },

  # Workaround commands (Rule #5)
  /\bcat\s+[^\|]+\.(swift|rb|ts|js|py)\b/i => {
    rule: '#5',
    msg: 'Use Read tool instead of cat for files.',
    severity: :info
  },
  /\bgrep\s+-r\b/i => {
    rule: '#5',
    msg: 'Use Grep tool instead of grep command.',
    severity: :info
  }
}.freeze

def output_issue_warning(found_issues)
  warn ''
  warn '=' * 65
  warn '🔍 DEEPER LOOK TRIGGER - Issue Pattern Detected'
  warn '=' * 65
  warn ''
  warn '   You discovered something broken/hidden!'
  warn ''
  warn '   ┌─────────────────────────────────────────────────────────────┐'
  warn '   │  "What ELSE might be broken that I haven\'t noticed?"       │'
  warn '   └─────────────────────────────────────────────────────────────┘'
  warn ''
  warn '   Before fixing this ONE thing, check similar patterns.'
  warn ''
  warn '   Patterns detected:'
  found_issues.first(3).each do |pattern|
    warn "   • #{pattern.source[0, 50]}..."
  end
  warn ''
  warn '=' * 65
  warn ''
end

def output_weasel_warning(found_weasels)
  warn ''
  warn '=' * 65
  warn '🚨 SANE COP - Weasel Words Detected'
  warn '=' * 65
  warn ''

  found_weasels.each do |pattern, info|
    icon = case info[:severity]
           when :alert then '🔴'
           when :warning then '🟡'
           else '🔵'
           end
    warn "   #{icon} Rule #{info[:rule]}: #{info[:msg]}"
  end

  warn ''
  warn '   ┌─────────────────────────────────────────────────────────────┐'
  warn '   │  These phrases often indicate SOP violations.              │'
  warn '   │  Stop and reconsider your approach.                        │'
  warn '   └─────────────────────────────────────────────────────────────┘'
  warn ''
  warn '=' * 65
  warn ''
end

# Read hook input from stdin
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

tool_name = input['tool_name'] || 'unknown'
tool_output = input['tool_output'] || ''
tool_input = input['tool_input'] || {}

# Check for Bash commands too (for workaround detection)
command = tool_input['command'] || ''

# Combine output and command for checking
text_to_check = "#{tool_output}\n#{command}"

# Only check relevant tools
exit 0 unless %w[Grep Read Bash].include?(tool_name)

# Skip if output is too short (probably not meaningful)
exit 0 if text_to_check.length < 20

# Check for issue patterns (Deeper Look)
found_issues = ISSUE_PATTERNS.select { |pattern| text_to_check.match?(pattern) }

# Check for weasel patterns (SaneCop)
found_weasels = WEASEL_PATTERNS.select { |pattern, _info| text_to_check.match?(pattern) }

# Output warnings
output_issue_warning(found_issues) if found_issues.any?
output_weasel_warning(found_weasels) if found_weasels.any?

exit 0
