#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneLoop Enforcer Hook
# ==============================================================================
# Ensures SaneLoop rules are followed:
# - BLOCKS if user requested saneloop but it hasn't been started
# - Warns when approaching max iterations
# - Warns when claiming completion without all criteria checked
# - Tracks iteration count automatically on tool use
#
# Hook Type: PreToolUse (Edit, Write, Bash)
# Behavior: BLOCKS if saneloop requested but not started
# ==============================================================================

require 'json'
require_relative 'rule_tracker'

SANELOOP_STATE_FILE = '.claude/saneloop-state.json'
REQUIREMENTS_FILE = '.claude/prompt_requirements.json'
BYPASS_FILE = '.claude/bypass_active.json'

# Skip enforcement if bypass is active
exit 0 if File.exist?(BYPASS_FILE)

# Read from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0 # Don't block on parse errors
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Did user request a saneloop that hasn't been started?
# ═══════════════════════════════════════════════════════════════════════════════

if File.exist?(REQUIREMENTS_FILE)
  begin
    reqs = JSON.parse(File.read(REQUIREMENTS_FILE), symbolize_names: true)
    if reqs[:requested]&.include?('saneloop') && !reqs[:satisfied]&.include?('saneloop')
      # Check if saneloop is actually active
      saneloop_active = false
      if File.exist?(SANELOOP_STATE_FILE)
        state = JSON.parse(File.read(SANELOOP_STATE_FILE), symbolize_names: true)
        saneloop_active = state[:active] == true
      end

      unless saneloop_active
        RuleTracker.log_violation(
          rule: :saneloop_required,
          hook: 'saneloop_enforcer',
          reason: 'User requested saneloop but it was not started'
        )

        warn ''
        warn '🛑 BLOCKED: SaneLoop required but not started'
        warn '   Run: ./Scripts/SaneMaster.rb saneloop start "Task" --promise "Done when..."'
        warn ''

        exit 2 # Exit code 2 = BLOCK in Claude Code
      end
    end
  rescue StandardError
    # Don't block on parse errors
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Is there an active saneloop to monitor?
# ═══════════════════════════════════════════════════════════════════════════════

unless File.exist?(SANELOOP_STATE_FILE)
  exit 0 # No loop active, allow
end

begin
  state = JSON.parse(File.read(SANELOOP_STATE_FILE), symbolize_names: true)
rescue JSON::ParserError, StandardError
  exit 0 # Can't read state, allow
end

# Only check if loop is active
unless state[:active]
  exit 0
end

tool_name = input['tool_name']
tool_input = input['tool_input'] || input

# Get current iteration info
iteration = state[:iteration] || 1
max_iterations = state[:max_iterations] || 15
task = state[:task] || 'Unknown task'
criteria = state[:acceptance_criteria] || []
unchecked_count = criteria.count { |c| !c[:checked] }
checked_count = criteria.count { |c| c[:checked] }
total_criteria = criteria.length

# Calculate warning thresholds
warning_threshold = (max_iterations * 0.7).to_i # Warn at 70%
critical_threshold = (max_iterations * 0.9).to_i # Critical at 90%

# Output status based on iteration count
if iteration >= max_iterations
  warn ''
  warn "🔴 SANELOOP MAX ITERATIONS | #{checked_count}/#{total_criteria} criteria | Task: #{task}"
  if unchecked_count.positive?
    criteria.reject { |c| c[:checked] }.each { |c| warn "  [ ] #{c[:text]}" }
  end
  warn '   Run: saneloop status or saneloop cancel'
  warn ''

  # Don't block, just warn strongly
  exit 0

elsif iteration >= critical_threshold
  warn ''
  warn "SANELOOP: #{iteration}/#{max_iterations} iterations (CRITICAL)"
  warn "  Task: #{task}"
  warn "  Progress: #{checked_count}/#{total_criteria} criteria checked"
  if unchecked_count.positive?
    warn "  Remaining: #{unchecked_count} criteria unchecked"
  end
  warn '  Consider reviewing approach before max iterations.'
  warn ''

elsif iteration >= warning_threshold
  # Gentler warning at 70%
  warn ''
  warn "SANELOOP: #{iteration}/#{max_iterations} iterations"
  warn "  Progress: #{checked_count}/#{total_criteria} criteria"
  warn ''
end

# Special check: detect "completion promise" patterns in output
# This is a PostToolUse concern, not PreToolUse - skip for now

exit 0
