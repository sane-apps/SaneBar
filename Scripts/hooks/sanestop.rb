#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneStop - Stop Hook
# ==============================================================================
# Fires when Claude finishes responding. Validates session and saves learnings.
#
# Exit codes:
#   0 = allow Claude to stop
#   2 = block with reason (Claude must address it)
#
# What this does:
#   1. Checks if session summary is needed (significant edits made)
#   2. Validates summary format if present
#   3. Saves session learnings
#   4. Reports to user
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'core/state_manager'

LOG_FILE = File.expand_path('../../.claude/sanestop.log', __dir__)
MEMORY_STAGING_FILE = File.expand_path('../../.claude/memory_staging.json', __dir__)

# === CONFIGURATION ===

MIN_EDITS_FOR_SUMMARY = 3  # Require summary after 3+ edits
MIN_UNIQUE_FILES_FOR_SUMMARY = 2  # Or 2+ unique files edited

# === SOP SCORE CALCULATION ===

def count_session_violations
  enforcement = StateManager.get(:enforcement)
  blocks = enforcement[:blocks] || []
  return {} if blocks.empty?

  session_start = Time.now - 3600  # Last hour approximates session
  violations = Hash.new(0)

  blocks.each do |block|
    begin
      block_time = Time.parse(block[:timestamp] || block['timestamp'])
      next if block_time < session_start
    rescue ArgumentError
      # Invalid timestamp format - skip this block
      next
    end

    rule = block[:rule] || block['rule'] || 'unknown'
    violations[rule] += 1
  end

  violations
end

def calculate_sop_score(violations)
  unique_violations = violations.keys.count

  case unique_violations
  when 0 then 10
  when 1 then 9
  when 2 then 8
  when 3..4 then 7
  when 5..6 then 6
  else 5
  end
end

# === PATTERN UPDATES ===

def update_session_patterns(violations, sop_score)
  StateManager.update(:patterns) do |patterns|
    patterns ||= { weak_spots: {}, triggers: {}, strengths: [], session_scores: [] }

    # Update weak spots (rules violated this session)
    violations.each do |rule, count|
      rule_key = rule.to_s
      patterns[:weak_spots] ||= {}
      patterns[:weak_spots][rule_key] = (patterns[:weak_spots][rule_key] || 0) + count
    end

    # Track session score for trend analysis
    patterns[:session_scores] ||= []
    patterns[:session_scores] << sop_score
    patterns[:session_scores] = patterns[:session_scores].last(10)  # Keep last 10

    patterns
  end
rescue StandardError
  # Don't fail on state errors
end

# === MEMORY MCP STAGING ===
# Stage high-value learnings for Claude to save to Memory MCP
# Hook can't call MCP directly, so we stage for next session start

def stage_memory_learnings(violations, sop_score)
  return if violations.empty? && sop_score >= 9  # Nothing notable to save

  patterns = StateManager.get(:patterns)
  weak_spots = patterns&.dig(:weak_spots) || {}

  # Only stage if we have significant learnings
  significant_weak_spots = weak_spots.select { |_k, v| v.to_i >= 3 }
  return if significant_weak_spots.empty? && violations.empty?

  staging = {
    timestamp: Time.now.iso8601,
    project: File.basename(Dir.pwd),
    session_score: sop_score,
    violations_this_session: violations.transform_keys(&:to_s),
    cumulative_weak_spots: significant_weak_spots,
    needs_memory_update: true
  }

  # Generate suggested Memory entity
  if significant_weak_spots.any?
    top_weak = significant_weak_spots.max_by { |_k, v| v }
    staging[:suggested_entity] = {
      name: "SOP-WeakSpot-#{staging[:project]}",
      type: "LearningPattern",
      observations: [
        "Weak spot: Rule #{top_weak[0]} with #{top_weak[1]} cumulative violations",
        "Session score: #{sop_score}/10",
        "Recorded: #{Time.now.strftime('%Y-%m-%d')}"
      ]
    }
  end

  FileUtils.mkdir_p(File.dirname(MEMORY_STAGING_FILE))
  File.write(MEMORY_STAGING_FILE, JSON.pretty_generate(staging))
rescue StandardError
  # Don't fail on staging errors
end

# === CHECKS ===

def check_summary_needed
  edits = StateManager.get(:edits)
  edit_count = edits[:count] || 0
  unique_count = edits[:unique_files]&.length || 0

  # Summary needed if significant work was done
  return nil if edit_count < MIN_EDITS_FOR_SUMMARY && unique_count < MIN_UNIQUE_FILES_FOR_SUMMARY

  # Check if this stop hook already fired (prevent loop)
  # Just warn, don't block
  if edit_count >= MIN_EDITS_FOR_SUMMARY || unique_count >= MIN_UNIQUE_FILES_FOR_SUMMARY
    warn '---'
    warn 'Session Summary Reminder'
    warn ''
    warn "You made #{edit_count} edits to #{unique_count} files."
    warn 'Consider ending with a Session Summary per SOP.'
    warn '---'
  end

  nil  # Don't block, just remind
end

def save_session_learnings
  edits = StateManager.get(:edits)
  research = StateManager.get(:research)
  cb = StateManager.get(:circuit_breaker)
  enf = StateManager.get(:enforcement)

  # Calculate violations and SOP score
  violations = count_session_violations
  sop_score = calculate_sop_score(violations)

  # Calculate session stats
  stats = {
    timestamp: Time.now.iso8601,
    edits: edits[:count] || 0,
    unique_files: edits[:unique_files]&.length || 0,
    research_done: research.compact.keys.length,
    failures: cb[:failures] || 0,
    blocks: enf[:blocks]&.length || 0,
    halted: enf[:halted] || false,
    violations: violations,
    sop_score: sop_score
  }

  # Update patterns for future sessions
  update_session_patterns(violations, sop_score)

  # Stage high-value learnings for Memory MCP
  stage_memory_learnings(violations, sop_score)

  log_session(stats)
  stats
end

def log_session(stats)
  FileUtils.mkdir_p(File.dirname(LOG_FILE))
  File.open(LOG_FILE, 'a') { |f| f.puts(stats.to_json) }
rescue StandardError
  # Don't fail on logging errors
end

# === MAIN PROCESSING ===

def process_stop(stop_hook_active)
  # Don't loop if already in a stop hook
  return 0 if stop_hook_active

  # Check if summary needed (non-blocking reminder)
  check_summary_needed

  # Save learnings
  stats = save_session_learnings

  # Report to user
  if stats[:edits] > 0 || stats[:violations].any?
    warn '---'
    warn 'Session Stats'
    warn "  Edits: #{stats[:edits]} (#{stats[:unique_files]} unique files)"
    warn "  Research: #{stats[:research_done]}/5 categories"
    warn "  Failures: #{stats[:failures]}"
    warn "  Blocks: #{stats[:blocks]}"

    # Show SOP score and violations
    warn ''
    warn "  Auto SOP Score: #{stats[:sop_score]}/10"
    if stats[:violations].any?
      warn '  Violations this session:'
      stats[:violations].each do |rule, count|
        warn "    #{rule}: #{count}x"
      end
    else
      warn '  No rule violations detected'
    end

    # Show patterns learned
    patterns = StateManager.get(:patterns)
    if patterns && patterns[:weak_spots]&.any?
      weak = patterns[:weak_spots].sort_by { |_k, v| -v.to_i }.first(3)
      if weak.any?
        warn ''
        warn '  Cumulative weak spots (across sessions):'
        weak.each { |rule, count| warn "    #{rule}: #{count} total violations" }
      end
    end

    # Show score trend
    scores = patterns&.dig(:session_scores) || []
    if scores.length >= 3
      recent_avg = scores.last(3).sum.to_f / 3
      warn ''
      warn "  Score trend: #{recent_avg.round(1)} avg (last 3 sessions)"
    end

    warn '---'
  end

  0  # Allow stop
end

# === SELF-TEST ===

def self_test
  warn 'SaneStop Self-Test'
  warn '=' * 40

  # Reset state
  StateManager.reset(:edits)
  StateManager.reset(:research)
  StateManager.reset(:circuit_breaker)

  passed = 0
  failed = 0

  # Test 1: No edits = no reminder
  original_stderr = $stderr.clone
  $stderr.reopen('/dev/null', 'w')
  exit_code = process_stop(false)
  $stderr.reopen(original_stderr)

  if exit_code == 0
    passed += 1
    warn '  PASS: No edits -> allow stop'
  else
    failed += 1
    warn '  FAIL: Should allow stop with no edits'
  end

  # Test 2: With edits = reminder shown but still allow
  StateManager.update(:edits) do |e|
    e[:count] = 5
    e[:unique_files] = ['/a.swift', '/b.swift', '/c.swift']
    e
  end

  original_stderr = $stderr.clone
  $stderr.reopen('/dev/null', 'w')
  exit_code = process_stop(false)
  $stderr.reopen(original_stderr)

  if exit_code == 0
    passed += 1
    warn '  PASS: With edits -> allow stop (reminder shown)'
  else
    failed += 1
    warn '  FAIL: Should allow stop even with edits'
  end

  # Test 3: stop_hook_active = skip processing
  exit_code = process_stop(true)
  if exit_code == 0
    passed += 1
    warn '  PASS: stop_hook_active -> skip processing'
  else
    failed += 1
    warn '  FAIL: Should skip when stop_hook_active'
  end

  # Test 4: Session logging works
  if File.exist?(LOG_FILE)
    last_line = File.readlines(LOG_FILE).last
    entry = JSON.parse(last_line)
    if entry['edits'] == 5
      passed += 1
      warn '  PASS: Session logging'
    else
      failed += 1
      warn '  FAIL: Session logging incorrect'
    end
  else
    failed += 1
    warn '  FAIL: Log file not created'
  end

  # === JSON INTEGRATION TESTS ===
  warn ''
  warn 'Testing JSON parsing (integration):'

  require 'open3'

  # Test valid JSON
  json_input = '{"stop_hook_active":false}'
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: json_input)
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Valid JSON parsed correctly (exit 0)'
  else
    failed += 1
    warn "  FAIL: Valid JSON should return exit 0, got #{status.exitstatus}"
  end

  # Test JSON with stop_hook_active = true (should skip and return 0)
  json_input = '{"stop_hook_active":true}'
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: json_input)
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: stop_hook_active=true skips processing (exit 0)'
  else
    failed += 1
    warn "  FAIL: stop_hook_active=true should exit 0, got #{status.exitstatus}"
  end

  # Test invalid JSON doesn't crash
  json_input = 'definitely not json'
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: json_input)
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Invalid JSON returns exit 0 (fail safe)'
  else
    failed += 1
    warn "  FAIL: Invalid JSON should return exit 0, got #{status.exitstatus}"
  end

  # Test empty input doesn't crash
  stdout, stderr, status = Open3.capture3("ruby #{__FILE__}", stdin_data: '')
  if status.exitstatus == 0
    passed += 1
    warn '  PASS: Empty input returns exit 0 (fail safe)'
  else
    failed += 1
    warn "  FAIL: Empty input should return exit 0, got #{status.exitstatus}"
  end

  warn ''
  warn "#{passed}/#{passed + failed} tests passed"

  if failed == 0
    warn ''
    warn 'ALL TESTS PASSED'
    exit 0
  else
    warn ''
    warn "#{failed} TESTS FAILED"
    exit 1
  end
end

# === MAIN ===

if ARGV.include?('--self-test')
  self_test
else
  begin
    input = JSON.parse($stdin.read)
    stop_hook_active = input['stop_hook_active'] || false
    exit process_stop(stop_hook_active)
  rescue JSON::ParserError, Errno::ENOENT
    exit 0  # Don't fail on parse errors
  end
end
