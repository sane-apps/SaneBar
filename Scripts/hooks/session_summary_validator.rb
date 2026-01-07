#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Session Summary Validator Hook (v2)
# ==============================================================================
# Makes SOP compliance rewarding and cheating IMPOSSIBLE.
#
# KEY CHANGE: SOP Compliance is AUTO-CALCULATED from violation data.
# Claude can't pick their own score - it comes from rule_tracking.jsonl.
#
# SCORING:
#   - SOP Compliance: AUTO-CALCULATED from session violations
#   - Performance: User provides (subjective quality assessment)
#
# AUTO-CALCULATION FORMULA:
#   0 unique rule violations = 10/10
#   1 unique rule violation  = 9/10
#   2 unique rule violations = 8/10
#   3-4 unique violations    = 7/10
#   5-6 unique violations    = 6/10
#   7+ unique violations     = 5/10 or lower
#
# ANTI-GAMING MEASURES:
#   - Score history tracked (last 10 sessions)
#   - Low variance detection (stdev < 0.8 over 5+ scores = suspicious)
#   - BLOCKS if claimed score doesn't match calculated score
#
# Hook Type: PostToolUse (Edit, Write)
# Triggers: When editing files that look like session summaries
# ==============================================================================

require 'json'
require 'fileutils'
require_relative 'rule_tracker'
require_relative 'state_signer'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
STREAK_FILE = File.join(PROJECT_DIR, '.claude/compliance_streak.json')
TRACKING_FILE = File.join(PROJECT_DIR, '.claude/rule_tracking.jsonl')

# SaneLoop lifecycle files - cleared when rating presented
SANELOOP_STATE_FILE = File.join(PROJECT_DIR, '.claude/saneloop-state.json')
SATISFACTION_FILE = File.join(PROJECT_DIR, '.claude/process_satisfaction.json')
RESEARCH_PROGRESS_FILE = File.join(PROJECT_DIR, '.claude/research_progress.json')
REQUIREMENTS_FILE = File.join(PROJECT_DIR, '.claude/prompt_requirements.json')
SANELOOP_ARCHIVE_DIR = File.join(PROJECT_DIR, '.claude/saneloop-archive')
SUMMARY_VALIDATED_FILE = File.join(PROJECT_DIR, '.claude/summary_validated.json')

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
  default = { current: 0, best: 0, last_score: nil, history: [] }
  return default unless File.exist?(STREAK_FILE)

  JSON.parse(File.read(STREAK_FILE), symbolize_names: true)
rescue StandardError
  default
end

def save_streak(streak)
  FileUtils.mkdir_p(File.dirname(STREAK_FILE))
  File.write(STREAK_FILE, JSON.pretty_generate(streak))
end

# ==============================================================================
# SaneLoop Lifecycle Cleanup
# ==============================================================================
# When a rating is presented, the SaneLoop is OVER:
# 1. Archive the SaneLoop state (preserve history)
# 2. Clear satisfaction (must re-earn for next task)
# 3. Clear research progress (must re-research for next task)
# 4. Clear requirements (fresh slate for next prompt)
# ==============================================================================

def cleanup_saneloop_on_rating
  cleaned = []

  # 1. Archive SaneLoop state (if exists)
  if File.exist?(SANELOOP_STATE_FILE)
    FileUtils.mkdir_p(SANELOOP_ARCHIVE_DIR)
    state = JSON.parse(File.read(SANELOOP_STATE_FILE), symbolize_names: true)
    task_slug = (state[:task] || 'unknown').gsub(/[^a-zA-Z0-9]+/, '_')[0..30]
    archive_name = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{task_slug}.json"
    archive_path = File.join(SANELOOP_ARCHIVE_DIR, archive_name)

    state[:archived_at] = Time.now.iso8601
    state[:completed] = true
    state[:completion_note] = 'Rating presented - SaneLoop lifecycle complete'
    File.write(archive_path, JSON.pretty_generate(state))
    File.delete(SANELOOP_STATE_FILE)
    cleaned << 'saneloop'
  end

  # 2. Clear satisfaction (must re-earn for next task)
  if File.exist?(SATISFACTION_FILE)
    File.delete(SATISFACTION_FILE)
    cleaned << 'satisfaction'
  end

  # 3. Clear research progress (must re-research for next task)
  if File.exist?(RESEARCH_PROGRESS_FILE)
    File.delete(RESEARCH_PROGRESS_FILE)
    cleaned << 'research'
  end

  # 4. Clear requirements (fresh slate)
  if File.exist?(REQUIREMENTS_FILE)
    File.delete(REQUIREMENTS_FILE)
    cleaned << 'requirements'
  end

  cleaned
end

# Calculate standard deviation for variance check
def calculate_stdev(scores)
  return 0.0 if scores.length < 2

  mean = scores.sum.to_f / scores.length
  variance = scores.map { |x| (x - mean)**2 }.sum / scores.length
  Math.sqrt(variance)
end

# Count unique rule violations from tracking log
def count_session_violations
  return 0 unless File.exist?(TRACKING_FILE)

  # Get entries from last hour (approximate session)
  session_start = Time.now - 3600
  violations = []

  File.readlines(TRACKING_FILE).each do |line|
    entry = JSON.parse(line, symbolize_names: true)
    next unless entry[:type] == 'violation'

    # Parse timestamp
    begin
      entry_time = Time.parse(entry[:timestamp])
      next if entry_time < session_start
    rescue StandardError
      next
    end

    violations << entry[:rule]
  end

  # Return count of UNIQUE rules violated
  violations.uniq.count
rescue StandardError
  0
end

# Calculate expected SOP Compliance score from violations
def calculate_sop_score
  violations = count_session_violations

  case violations
  when 0 then 10
  when 1 then 9
  when 2 then 8
  when 3..4 then 7
  when 5..6 then 6
  else 5
  end
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

# Extract the claimed score
score_match = content.match(/SOP Compliance:\s*(\d+)\/10/i)
exit 0 unless score_match

claimed_score = score_match[1].to_i
calculated_score = calculate_sop_score
streak = load_streak
history = streak[:history] || []

# === SHAME CHECKS ===

shames = []

# CHECK 1: Claimed score must match calculated score (THE BIG ONE)
if claimed_score != calculated_score
  shames << "SCORE MISMATCH: You claimed #{claimed_score}/10 but violations show #{calculated_score}/10. " \
             "SOP Compliance is calculated from data, not chosen. Use #{calculated_score}/10."
end

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

# Check: Low variance in history (the "always 8" detector)
if history.length >= 5
  stdev = calculate_stdev(history)
  if stdev < 0.8
    shames << "LOW VARIANCE: Last #{history.length} scores have stdev=#{stdev.round(2)}. " \
              "Healthy self-assessment should vary more. Are you gaming the system?"
  end
end

# Check: Suspicious streak of same scores (keep for backwards compat)
if streak[:last_score] == claimed_score && streak[:current] >= 3
  shames << "SUSPICIOUS PATTERN: #{streak[:current] + 1} sessions in a row at exactly #{claimed_score}/10. Really?"
end

# === OUTPUT ===

if shames.any?
  RuleTracker.log_violation(rule: :self_rating, hook: 'session_summary_validator', reason: shames.first)
  warn ''
  warn '🚨 SUMMARY VALIDATION FAILED - streak reset to 0'
  shames.each { |s| warn "  ❌ #{s}" }
  warn ''

  # Reset streak on shame
  streak[:current] = 0
  streak[:last_score] = claimed_score
  save_streak(streak)

  # Don't block, but make it painful
  exit 0
end

# === REWARD CHECKS ===

praises = []
EXCELLENCE_PATTERNS.each do |check|
  praises << check[:praise] if content.match?(check[:pattern])
end

# Update streak and history (use calculated score, not claimed)
if calculated_score >= 8
  streak[:current] += 1
  streak[:best] = [streak[:best], streak[:current]].max
else
  streak[:current] = 0
end
streak[:last_score] = calculated_score

# Update history (keep last 10 scores)
history << calculated_score
streak[:history] = history.last(10)

save_streak(streak)

# ==============================================================================
# SANELOOP LIFECYCLE END - Rating presented = SaneLoop complete
# ==============================================================================
cleaned = cleanup_saneloop_on_rating
if cleaned.any?
  warn ''
  warn '🔄 SANELOOP COMPLETE - Satisfaction revoked'
  warn "   Cleared: #{cleaned.join(', ')}"
  warn '   Next task requires fresh research & compliance'
  warn ''
end

# Mark session summary as validated (resets edit count requirement)
summary_data = {
  validated_at: Time.now.iso8601,
  score: calculated_score,
  edit_count_at_validation: 0  # Will be used to track edits since last summary
}
File.write(SUMMARY_VALIDATED_FILE, JSON.pretty_generate(summary_data))

# Celebration for high scores
if calculated_score >= 9
  RuleTracker.log_enforcement(rule: :self_rating, hook: 'session_summary_validator', action: 'celebrate', details: "#{calculated_score}/10 - streak: #{streak[:current]}")
  warn ''
  warn '=' * 60
  warn '  🏆 EXCELLENT SOP COMPLIANCE!'
  warn '=' * 60
  warn ''
  warn "  Score: #{calculated_score}/10"
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
elsif calculated_score >= 7
  warn ''
  warn "✅ Good session (#{calculated_score}/10) | Streak: #{streak[:current]}"
  warn ''
end

exit 0
