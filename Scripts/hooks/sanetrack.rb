#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneTrack - PostToolUse Hook
# ==============================================================================
# Tracks tool results after execution. Updates state based on outcomes.
# ==============================================================================

require 'json'
require_relative 'core/state_manager'
require_relative 'lib/sanetrack/tracking'
require_relative 'lib/sanetrack/intelligence'
require_relative 'lib/sanetrack/reminders'
require_relative 'lib/sanetrack/tautology'

# === MAIN PROCESSING ===

def process_result(tool_name, tool_input, tool_response)
  # Detect actual failures
  error_sig = SaneTrack::Intelligence.detect_actual_failure(tool_name, tool_response)
  is_error = !error_sig.nil?

  if is_error
    SaneTrack::Tracking.track_failure(tool_name, tool_response, SaneTrack::Intelligence::ERROR_PATTERN)
    SaneTrack::Tracking.track_mcp_verification(tool_name, false)
    
    response_str = tool_response.to_s[0..200]
    SaneTrack::Intelligence.track_error_signature(error_sig, tool_name, response_str)
    
    SaneTrack::Tracking.log_action_for_learning(tool_name, tool_input, false, error_sig)
    SaneTrack::Tracking.log_action(tool_name, 'failure')

    cb = StateManager.get(:circuit_breaker)
    SaneTrack::Reminders.emit_rewind_reminder(cb[:failures] || 0) if cb[:failures] && cb[:failures] >= 1
  else
    SaneTrack::Tracking.reset_failure_count(tool_name)
    SaneTrack::Tracking.track_edit(tool_name, tool_input, tool_response)
    SaneTrack::Tracking.track_mcp_verification(tool_name, true)

    tautology_warning = SaneTrack::Tautology.check_tautologies(tool_name, tool_input)
    warn tautology_warning if tautology_warning

    SaneTrack::Tracking.log_action_for_learning(tool_name, tool_input, true, nil)
    SaneTrack::Tracking.log_action(tool_name, 'success')

    if SaneTrack::Tracking::EDIT_TOOLS.include?(tool_name)
      edits = StateManager.get(:edits)
      SaneTrack::Reminders.emit_context_reminder(edits[:count] || 0)
    end

    SaneTrack::Reminders.emit_explore_reminder(tool_name, tool_input)

    # Git Push Reminder
    if tool_name == 'Bash'
      command = tool_input['command'] || tool_input[:command] || ''
      if command.match?(/git\s+commit/i) && !command.match?(/git\s+push/i)
        ahead_check = `git status 2>/dev/null | grep -o "ahead of.*by [0-9]* commit"`
        unless ahead_check.empty?
          warn ''
          warn '🚨 GIT PUSH REMINDER 🚨'
          warn "   You committed but haven't pushed!"
          warn "   Status: #{ahead_check.strip}"
          warn ''
          warn '   → Run: git push'
          warn '   → READ ALL DOCUMENTATION before claiming done'
          warn '   → Verify README is accurate and up to date'
          warn ''
        end
      end
    end
  end

  0
end

# === SELF-TEST ===

def self_test
  warn 'SaneTrack Self-Test (Refactored)'
  warn '=' * 40

  StateManager.reset(:edits)
  StateManager.reset(:circuit_breaker)
  StateManager.update(:enforcement) { |e| e[:halted] = false; e[:blocks] = []; e }

  passed = 0
  failed = 0

  # Test 1: Track edit
  process_result('Edit', { 'file_path' => '/test/file1.swift' }, { 'success' => true })
  edits = StateManager.get(:edits)
  if edits[:count] == 1 && edits[:unique_files].include?('/test/file1.swift')
    passed += 1
    warn '  PASS: Edit tracking'
  else
    failed += 1
    warn '  FAIL: Edit tracking'
  end

  # Test 3: Track failure
  process_result('Bash', {}, { 'error' => 'command not found' })
  cb = StateManager.get(:circuit_breaker)
  if cb[:failures] == 1
    passed += 1
    warn '  PASS: Failure tracking'
  else
    failed += 1
    warn '  FAIL: Failure tracking'
  end

  warn ''
  warn "#{passed}/#{passed + failed} tests passed"
  exit(failed == 0 ? 0 : 1)
end

def show_status
  edits = StateManager.get(:edits)
  cb = StateManager.get(:circuit_breaker)

  warn 'SaneTrack Status'
  warn '=' * 40
  warn ''
  warn 'Edits:'
  warn "  count: #{edits[:count]}"
  warn "  unique_files: #{edits[:unique_files]&.length || 0}"
  warn ''
  warn 'Circuit Breaker:'
  warn "  failures: #{cb[:failures]}"
  warn "  tripped: #{cb[:tripped]}"
  warn "  last_error: #{cb[:last_error]&.[](0..50)}" if cb[:last_error]

  exit 0
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('--self-test')
    self_test
  elsif ARGV.include?('--status')
    show_status
  else
    begin
      input = JSON.parse($stdin.read)
      tool_name = input['tool_name'] || 'unknown'
      tool_input = input['tool_input'] || {}
      tool_response = input['tool_response'] || {}
      exit process_result(tool_name, tool_input, tool_response)
    rescue JSON::ParserError, Errno::ENOENT
      exit 0
    end
  end
end