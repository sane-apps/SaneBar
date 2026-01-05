#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Session Summary Validator Hook
# ==============================================================================
# Makes SOP compliance rewarding and cheating mortifying.
#
# FORMAT REQUIREMENTS:
#   - SOP Compliance: X/10 (binary - rules followed or not)
#   - Performance: X/10 (quality assessment)
#   - Self-Rating: X/10 (combined)
#
# SOP COMPLIANCE (10/10 if no rules broken):
#   ✅ #X: specific action (proof required)
#   ❌ None (valid if no rules were actually broken)
#
# PERFORMANCE (must have at least one ⚠️):
#   Objective criteria for ⚠️ gaps:
#   - No unit tests for new code
#   - Simulated vs actual verification
#   - Missing error handling for edge cases
#   - Large changes that could have been split
#   - Hardcoded values that should be configurable
#   - No documentation for public APIs
#
# Hook Type: PostToolUse (Edit, Write)
# Triggers: When editing files that look like session summaries
# ==============================================================================

require 'json'
require 'fileutils'
require_relative 'rule_tracker'

STREAK_FILE = '.claude/compliance_streak.json'

# Weasel words that indicate lazy/vague compliance claims
WEASEL_PATTERNS = [
  { pattern: /✅ #\d+: Used tools?$/i, shame: "TOO VAGUE: 'Used tools' - which tool? what command?" },
  { pattern: /✅ #\d+: Followed (the )?process$/i, shame: "MEANINGLESS: 'Followed process' - be specific" },
  { pattern: /✅ #\d+: Did (it )?(right|correctly|properly)$/i, shame: "EMPTY: What exactly did you do right?" },
  { pattern: /\betc\b/i, shame: "WEASEL WORD: 'etc' - list everything or nothing" },
  { pattern: /\bvarious\b/i, shame: "WEASEL WORD: 'various' - be specific" },
  { pattern: /\bsome\b things/i, shame: "WEASEL WORD: 'some things' - name them" },
]

# Patterns that indicate genuine compliance
EXCELLENCE_PATTERNS = [
  { pattern: /✅ #\d+:.*\b(qa\.rb|SaneMaster|verify)\b/i, praise: 'Used project tools by name' },
  { pattern: /✅ #\d+:.*\bline \d+\b/i, praise: 'Cited specific line numbers' },
  { pattern: /✅ #\d+:.*\b[A-Z][a-z]+\.(rb|swift|ts|py)\b/, praise: 'Referenced specific files' },
  { pattern: /Followup:.*\b(add|create|implement|hook|test|sync)\b/im, praise: 'Actionable followup items' },
]

def load_streak
  return { current: 0, best: 0, last_score: nil } unless File.exist?(STREAK_FILE)

  JSON.parse(File.read(STREAK_FILE), symbolize_names: true)
rescue StandardError
  { current: 0, best: 0, last_score: nil }
end

def save_streak(streak)
  FileUtils.mkdir_p(File.dirname(STREAK_FILE))
  File.write(STREAK_FILE, JSON.pretty_generate(streak))
end

# Read from stdin
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_input = input['tool_input'] || input
tool_output = input['tool_output'] || ''
content = tool_input['new_string'] || tool_input['content'] || tool_output

# Only check content that looks like a session summary
exit 0 unless content.include?('SOP Compliance:') || content.include?('Session Summary')

# Normalize escaped newlines from JSON
content = content.gsub('\\n', "\n")

# Extract the score
score_match = content.match(/SOP Compliance:\s*(\d+)\/10/i)
exit 0 unless score_match

score = score_match[1].to_i
streak = load_streak

# === SHAME CHECKS ===

shames = []

# Check for weasel words
WEASEL_PATTERNS.each do |check|
  shames << check[:shame] if content.match?(check[:pattern])
end

# Check: Must have Performance section with at least one ⚠️ gap (nobody's perfect)
# ❌ None is valid for SOP Compliance if no rules were broken
# But Performance must show self-critique
unless content.match?(/Performance:.*⚠️/m)
  shames << "NO PERFORMANCE GAPS: Nobody's perfect. List at least one ⚠️ in Performance section."
end

# Check: Performance gaps must be objective, not vague
if content.match?(/⚠️.*could have been better/i) ||
   content.match?(/⚠️.*should have/i) ||
   content.match?(/⚠️.*minor issues?/i)
  shames << "VAGUE PERFORMANCE GAP: Be specific. What exactly was missing? (tests, docs, error handling)"
end

# Check: Score inflation - claiming 9-10 with vague content
if score >= 9 && shames.any?
  shames << "SCORE INFLATION: Claiming #{score}/10 but content has weasel words or missing sections"
end

# Check: Suspicious streak of same scores
if streak[:last_score] == score && streak[:current] >= 3
  shames << "SUSPICIOUS PATTERN: #{streak[:current] + 1} sessions in a row at exactly #{score}/10. Really?"
end

# === OUTPUT ===

if shames.any?
  RuleTracker.log_violation(rule: :self_rating, hook: 'session_summary_validator', reason: shames.first)
  warn ''
  warn '=' * 60
  warn '  🚨 SESSION SUMMARY VALIDATION FAILED'
  warn '=' * 60
  warn ''
  shames.each { |s| warn "  ❌ #{s}" }
  warn ''
  warn '  Your compliance streak has been RESET to 0.'
  warn '  Fix the issues above and try again.'
  warn ''
  warn '=' * 60
  warn ''

  # Reset streak on shame
  streak[:current] = 0
  streak[:last_score] = score
  save_streak(streak)

  # Don't block, but make it painful
  exit 0
end

# === REWARD CHECKS ===

praises = []
EXCELLENCE_PATTERNS.each do |check|
  praises << check[:praise] if content.match?(check[:pattern])
end

# Update streak
if score >= 8
  streak[:current] += 1
  streak[:best] = [streak[:best], streak[:current]].max
else
  streak[:current] = 0
end
streak[:last_score] = score
save_streak(streak)

# Celebration for high scores
if score >= 9
  RuleTracker.log_enforcement(rule: :self_rating, hook: 'session_summary_validator', action: 'celebrate', details: "#{score}/10 - streak: #{streak[:current]}")
  warn ''
  warn '=' * 60
  warn '  🏆 EXCELLENT SOP COMPLIANCE!'
  warn '=' * 60
  warn ''
  warn "  Score: #{score}/10"
  warn "  Streak: #{streak[:current]} sessions | Best: #{streak[:best]}"
  warn ''
  if praises.any?
    warn '  What made this great:'
    praises.each { |p| warn "    ✨ #{p}" }
  end
  warn ''
  if streak[:current] >= 5
    warn '  🔥 FIVE SESSION STREAK! You are building real discipline.'
  elsif streak[:current] >= 3
    warn '  💪 Three in a row! The process is becoming habit.'
  end
  warn ''
  warn '=' * 60
  warn ''
elsif score >= 7
  warn ''
  warn "✅ Good session (#{score}/10) | Streak: #{streak[:current]}"
  warn ''
end

exit 0
