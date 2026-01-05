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

# === CONFIGURATION ===

MIN_EDITS_FOR_SUMMARY = 3  # Require summary after 3+ edits
MIN_UNIQUE_FILES_FOR_SUMMARY = 2  # Or 2+ unique files edited

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

  # Calculate session stats
  stats = {
    timestamp: Time.now.iso8601,
    edits: edits[:count] || 0,
    unique_files: edits[:unique_files]&.length || 0,
    research_done: research.compact.keys.length,
    failures: cb[:failures] || 0,
    blocks: enf[:blocks]&.length || 0,
    halted: enf[:halted] || false
  }

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
  if stats[:edits] > 0
    warn '---'
    warn 'Session Stats'
    warn "  Edits: #{stats[:edits]} (#{stats[:unique_files]} unique files)"
    warn "  Research: #{stats[:research_done]}/5 categories"
    warn "  Failures: #{stats[:failures]}"
    warn "  Blocks: #{stats[:blocks]}"
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
