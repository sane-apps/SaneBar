#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Rule Tracker
# ==============================================================================
# Shared module for tracking which SOP rules get enforced/violated.
# Used by hooks to log rule activity for analysis every 5 sessions.
#
# Usage in hooks:
#   require_relative 'rule_tracker'
#   RuleTracker.log_enforcement(rule: 0, hook: 'sop_mapper', action: 'warn')
#   RuleTracker.log_violation(rule: 3, hook: 'circuit_breaker', reason: '3 failures')
# ==============================================================================

require 'json'
require 'fileutils'

module RuleTracker
  TRACKING_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'rule_tracking.jsonl')

  # Map of rules to their names (for reports)
  RULES = {
    0 => 'NAME THE RULE BEFORE YOU CODE',
    1 => 'STAY IN YOUR LANE',
    2 => 'VERIFY BEFORE YOU TRY',
    3 => 'TWO STRIKES? INVESTIGATE',
    4 => 'GREEN MEANS GO',
    5 => 'THEIR HOUSE, THEIR RULES',
    6 => 'BUILD, KILL, LAUNCH, LOG',
    7 => 'NO TEST? NO REST',
    8 => 'BUG FOUND? WRITE IT DOWN',
    9 => 'NEW FILE? GEN THAT PILE',
    10 => 'FIVE HUNDRED\'S FINE, EIGHT\'S THE LINE',
    11 => 'TOOL BROKE? FIX THE YOKE',
    12 => 'TALK WHILE I WALK'
  }.freeze

  # Map hooks to their primary rule
  HOOK_RULES = {
    'sop_mapper' => 0,
    'skill_validator' => 0,
    'saneloop_enforcer' => 0,
    'edit_validator' => [1, 10],  # Multiple rules
    'circuit_breaker' => 3,
    'failure_tracker' => 3,
    'two_fix_reminder' => 3,
    'test_quality_checker' => 7,
    'deeper_look_trigger' => 8,
    'verify_reminder' => 6,
    'version_mismatch' => 6,
    'session_summary_validator' => :self_rating
  }.freeze

  # Severity levels for enforcement actions
  # Used to prioritize which issues to address first
  SEVERITY_LEVELS = {
    block: 3,      # Tool call was blocked - critical
    warn: 2,       # Warning issued - needs attention
    remind: 1,     # Reminder shown - informational
    checkpoint: 0, # Neutral checkpoint
    celebrate: -1  # Positive reinforcement
  }.freeze

  # Map action strings to severity
  def self.severity_for(action)
    SEVERITY_LEVELS[action.to_sym] || 1
  end

  def self.log_enforcement(rule:, hook:, action:, details: nil)
    write_entry(
      type: 'enforcement',
      rule: rule,
      hook: hook,
      action: action,  # 'warn', 'block', 'remind', 'checkpoint', 'celebrate'
      severity: severity_for(action),
      details: details
    )
  end

  def self.log_violation(rule:, hook:, reason:)
    write_entry(
      type: 'violation',
      rule: rule,
      hook: hook,
      reason: reason,
      severity: 3  # Violations are always critical
    )
  end

  def self.write_entry(data)
    FileUtils.mkdir_p(File.dirname(TRACKING_FILE))
    entry = data.merge(
      timestamp: Time.now.iso8601,
      session_id: ENV['CLAUDE_SESSION_ID'] || 'unknown'
    )
    File.open(TRACKING_FILE, 'a') { |f| f.puts(JSON.generate(entry)) }
  rescue StandardError
    # Don't let tracking failures break hooks
    nil
  end

  def self.report(sessions: 5)
    return { error: 'No tracking data' } unless File.exist?(TRACKING_FILE)

    entries = File.readlines(TRACKING_FILE).map { |l| JSON.parse(l, symbolize_names: true) }

    # Get unique session IDs and take last N
    session_ids = entries.map { |e| e[:session_id] }.uniq.last(sessions)
    recent = entries.select { |e| session_ids.include?(e[:session_id]) }

    # Count by rule
    by_rule = Hash.new { |h, k| h[k] = { enforcements: 0, violations: 0 } }
    recent.each do |e|
      rule = e[:rule]
      next unless rule

      if e[:type] == 'enforcement'
        by_rule[rule][:enforcements] += 1
      elsif e[:type] == 'violation'
        by_rule[rule][:violations] += 1
      end
    end

    # Count by severity
    by_severity = Hash.new(0)
    recent.each do |e|
      sev = e[:severity] || 1
      by_severity[sev] += 1
    end

    {
      sessions_analyzed: session_ids.count,
      total_entries: recent.count,
      by_rule: by_rule.sort_by { |r, _| r.to_s }.to_h,
      by_severity: {
        critical: by_severity[3],
        warning: by_severity[2],
        info: by_severity[1],
        neutral: by_severity[0],
        positive: by_severity[-1]
      },
      most_violated: by_rule.max_by { |_, v| v[:violations] }&.first,
      most_enforced: by_rule.max_by { |_, v| v[:enforcements] }&.first
    }
  end
end
