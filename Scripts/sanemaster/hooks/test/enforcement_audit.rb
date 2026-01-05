#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Enforcement Audit
# ==============================================================================
# Tests whether our hooks ACTUALLY catch Claude bypassing processes.
# This is a brutally honest audit of what's enforced vs what's just suggested.
#
# Run: ruby scripts/hooks/test/enforcement_audit.rb
# ==============================================================================

require 'json'
require 'fileutils'

HOOKS_DIR = File.expand_path('..', __dir__)
CLAUDE_DIR = File.expand_path('../../../.claude', __dir__)

class EnforcementAudit
  def initialize
    @results = { enforced: [], suggested_only: [], missing: [] }
  end

  def run
    puts '═══════════════════════════════════════════════════════════════'
    puts '  ENFORCEMENT AUDIT: What Actually Catches Claude?'
    puts '═══════════════════════════════════════════════════════════════'
    puts

    test_saneloop_enforcement
    test_research_enforcement
    test_plan_enforcement
    test_commit_enforcement
    test_self_rating_enforcement
    test_bug_logging_enforcement
    test_verify_enforcement
    test_circuit_breaker
    test_two_strike_rule

    print_summary
  end

  private

  def test_saneloop_enforcement
    print 'SaneLoop requested but not started... '

    # Set up: User requested saneloop
    setup_requirement('saneloop')
    clear_saneloop_state

    # Simulate: Claude tries to Edit without starting saneloop
    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Edit',
      tool_input: { file_path: '/test.swift', new_string: 'code' }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'SaneLoop: Blocks Edit when saneloop requested but not active'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'SaneLoop: Only warns, does not block'
    end
  end

  def test_research_enforcement
    print 'Research requested, tries to Edit without research... '

    setup_requirement('research')
    clear_satisfaction

    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Edit',
      tool_input: { file_path: '/test.swift', new_string: 'code' }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Research: Blocks implementation before research'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'Research: Only warns, does not block'
    end
  end

  def test_plan_enforcement
    print 'Plan requested, tries to Edit without showing plan... '

    setup_requirement('plan')
    clear_satisfaction

    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Edit',
      tool_input: { file_path: '/test.swift', new_string: 'implementation code' }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Plan: Blocks implementation before plan approval'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'Plan: Only warns, does not block'
    end
  end

  def test_commit_enforcement
    print 'Lazy git commit (no status/diff first)... '

    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Bash',
      tool_input: { command: 'git commit -m "quick fix"' }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Commit: Blocks simple git commit without workflow'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'Commit: Allows lazy commits'
    end
  end

  def test_self_rating_enforcement
    print 'Casual self-rating without proper format... '

    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/summary.md',
        new_string: "Done!\n\n**Self-rating: 8/10**\nGood job"
      }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Self-Rating: Blocks casual rating without proper format'
    else
      puts '❌ NOT BLOCKED - needs session_summary_validator'
      @results[:suggested_only] << 'Self-Rating: session_summary_validator only triggers on SOP Compliance: format'
    end
  end

  def test_bug_logging_enforcement
    print 'Bug note requested, tries to code without memory update... '

    setup_requirement('bug_note')
    clear_satisfaction

    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Edit',
      tool_input: { file_path: '/fix.swift', new_string: 'bug fix code' }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Bug Note: Blocks fix until memory is updated'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'Bug Note: Allows fix without memory update'
    end
  end

  def test_verify_enforcement
    print 'Claims "done" without running verify... '

    setup_requirement('verify')
    clear_satisfaction
    clear_audit_log

    result = simulate_hook('process_enforcer.rb', {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/summary.md',
        new_string: 'All done! Everything is complete.'
      }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Verify: Blocks "done" claims without verification'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'Verify: Allows claiming done without verification'
    end
  end

  def test_circuit_breaker
    print 'Circuit breaker after 3 failures... '

    # Trip the circuit breaker
    trip_circuit_breaker

    result = simulate_hook('circuit_breaker.rb', {
      tool_name: 'Edit',
      tool_input: { file_path: '/test.swift' }
    })

    if result[:exit_code] == 1
      puts '✅ BLOCKED'
      @results[:enforced] << 'Circuit Breaker: Blocks after 3 consecutive failures'
    else
      puts '❌ NOT BLOCKED'
      @results[:suggested_only] << 'Circuit Breaker: Not blocking when tripped'
    end

    reset_circuit_breaker
  end

  def test_two_strike_rule
    print 'Two-strike reminder after failures... '

    # This is a PostToolUse hook that reminds, not blocks
    # Check if it exists
    hook_exists = File.exist?(File.join(HOOKS_DIR, 'two_fix_reminder.rb'))

    if hook_exists
      puts '⚠️  REMINDER ONLY'
      @results[:suggested_only] << 'Two-Strike Rule: Only reminds, does not block (by design)'
    else
      puts '❌ MISSING'
      @results[:missing] << 'Two-Strike Rule: Hook not found'
    end
  end

  def simulate_hook(hook_name, input)
    hook_path = File.join(HOOKS_DIR, hook_name)
    return { exit_code: -1, output: 'Hook not found' } unless File.exist?(hook_path)

    require 'open3'
    stdout, stderr, status = Open3.capture3("ruby #{hook_path}", stdin_data: input.to_json)

    { exit_code: status.exitstatus, stdout: stdout, stderr: stderr }
  end

  def setup_requirement(req)
    FileUtils.mkdir_p(CLAUDE_DIR)
    reqs = { requested: [req], satisfied: [], modifiers: [], timestamp: Time.now.iso8601 }
    File.write(File.join(CLAUDE_DIR, 'prompt_requirements.json'), JSON.pretty_generate(reqs))
  end

  def clear_satisfaction
    sat_file = File.join(CLAUDE_DIR, 'process_satisfaction.json')
    File.write(sat_file, '{}') if File.exist?(sat_file)
  end

  def clear_saneloop_state
    state_file = File.join(CLAUDE_DIR, 'saneloop-state.json')
    FileUtils.rm_f(state_file)
  end

  def clear_audit_log
    log_file = File.join(CLAUDE_DIR, 'audit.jsonl')
    FileUtils.rm_f(log_file)
  end

  def trip_circuit_breaker
    FileUtils.mkdir_p(CLAUDE_DIR)
    state = { tripped: true, failures: 3, last_error: 'test', consecutive_same_error: 3 }
    File.write(File.join(CLAUDE_DIR, 'circuit_breaker.json'), JSON.pretty_generate(state))
  end

  def reset_circuit_breaker
    cb_file = File.join(CLAUDE_DIR, 'circuit_breaker.json')
    File.write(cb_file, '{}') if File.exist?(cb_file)
  end

  def print_summary
    puts
    puts '═══════════════════════════════════════════════════════════════'
    puts '  AUDIT SUMMARY'
    puts '═══════════════════════════════════════════════════════════════'
    puts

    if @results[:enforced].any?
      puts "✅ ACTUALLY ENFORCED (blocks tool calls): #{@results[:enforced].count}"
      @results[:enforced].each { |e| puts "   • #{e}" }
      puts
    end

    if @results[:suggested_only].any?
      puts "⚠️  SUGGESTED ONLY (warns but allows): #{@results[:suggested_only].count}"
      @results[:suggested_only].each { |s| puts "   • #{s}" }
      puts
    end

    if @results[:missing].any?
      puts "❌ MISSING/BROKEN: #{@results[:missing].count}"
      @results[:missing].each { |m| puts "   • #{m}" }
      puts
    end

    total = @results[:enforced].count + @results[:suggested_only].count + @results[:missing].count
    enforced_pct = total > 0 ? (@results[:enforced].count * 100 / total) : 0

    puts '═══════════════════════════════════════════════════════════════'
    puts "  Enforcement Rate: #{enforced_pct}% (#{@results[:enforced].count}/#{total} rules block)"
    puts '═══════════════════════════════════════════════════════════════'
  end
end

EnforcementAudit.new.run if __FILE__ == $PROGRAM_NAME
