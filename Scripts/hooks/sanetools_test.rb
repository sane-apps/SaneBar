#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneTools Test Suite
# ==============================================================================
# Extracted from sanetools.rb per Rule #10 (file size limit)
# Run: ruby sanetools.rb --self-test
# ==============================================================================

require_relative 'core/state_manager'

module SaneToolsTest
  def self.run(process_tool_proc, research_categories)
    warn 'SaneTools Self-Test'
    warn '=' * 40

    # Reset state for clean test
    StateManager.reset(:research)
    StateManager.reset(:circuit_breaker)
    StateManager.update(:enforcement) do |e|
      e[:halted] = false
      e[:blocks] = []
      e
    end

    passed = 0
    failed = 0

    # === CIRCUIT BREAKER TEST ===
    warn ''
    warn 'Testing circuit breaker:'

    # Trip the circuit breaker
    StateManager.update(:circuit_breaker) do |cb|
      cb[:tripped] = true
      cb[:failures] = 5
      cb[:last_error] = 'Test error'
      cb
    end

    original_stderr = $stderr.clone
    $stderr.reopen('/dev/null', 'w')
    exit_code = process_tool_proc.call('Edit', { 'file_path' => '/tmp/test_project/test.swift' })
    $stderr.reopen(original_stderr)

    if exit_code == 2
      passed += 1
      warn '  PASS: Circuit breaker blocks edits when tripped'
    else
      failed += 1
      warn '  FAIL: Circuit breaker should block when tripped'
    end

    # Reset circuit breaker for remaining tests
    StateManager.reset(:circuit_breaker)

    # === BASH FILE WRITE BYPASS TEST ===
    warn ''
    warn 'Testing bash file write bypass:'

    # Ensure research is incomplete
    StateManager.reset(:research)

    original_stderr = $stderr.clone
    $stderr.reopen('/dev/null', 'w')
    # Use source file path (not /tmp/ which is in safe list)
    exit_code = process_tool_proc.call('Bash', { 'command' => 'echo "test" > /tmp/test_project/src/file.swift' })
    $stderr.reopen(original_stderr)

    if exit_code == 2
      passed += 1
      warn '  PASS: Bash file writes blocked to source files'
    else
      failed += 1
      warn '  FAIL: Bash file writes should be blocked to source files'
    end

    # === STANDARD TESTS ===
    warn ''
    warn 'Testing tool blocking:'

    tests = [
      # Blocked paths
      { tool: 'Read', input: { 'file_path' => '~/.ssh/id_rsa' }, expect_block: true, name: 'Block ~/.ssh/' },
      { tool: 'Edit', input: { 'file_path' => '/etc/passwd' }, expect_block: true, name: 'Block /etc/' },
      { tool: 'Write', input: { 'file_path' => '/var/log/test' }, expect_block: true, name: 'Block /var/' },

      # Edit without research (should block)
      { tool: 'Edit', input: { 'file_path' => '/tmp/test_project/test.swift' }, expect_block: true, name: 'Block edit without research' },

      # Research tools (should allow and track)
      { tool: 'Read', input: { 'file_path' => '/tmp/test_project/test.swift' }, expect_block: false, name: 'Allow Read (tracks local)' },
      { tool: 'Grep', input: { 'pattern' => 'test' }, expect_block: false, name: 'Allow Grep' },
      { tool: 'WebSearch', input: { 'query' => 'swift patterns' }, expect_block: false, name: 'Allow WebSearch (tracks web)' },
      { tool: 'mcp__memory__read_graph', input: {}, expect_block: false, name: 'Allow memory read (tracks memory)' },

      # Task agents (should allow and track)
      { tool: 'Task', input: { 'prompt' => 'Search documentation for this API' }, expect_block: false, name: 'Allow Task (tracks docs)' },
      { tool: 'Task', input: { 'prompt' => 'Search GitHub for external examples' }, expect_block: false, name: 'Allow Task (tracks github)' }
    ]

    tests.each do |test|
      # Suppress output
      original_stderr = $stderr.clone
      $stderr.reopen('/dev/null', 'w')

      exit_code = process_tool_proc.call(test[:tool], test[:input])

      $stderr.reopen(original_stderr)

      blocked = exit_code == 2
      expected = test[:expect_block]

      if blocked == expected
        passed += 1
        warn "  PASS: #{test[:name]}"
      else
        failed += 1
        warn "  FAIL: #{test[:name]} - expected #{expected ? 'BLOCK' : 'ALLOW'}, got #{blocked ? 'BLOCK' : 'ALLOW'}"
      end
    end

    # Check research tracking
    research = StateManager.get(:research)
    tracked_count = research_categories.keys.count { |cat| research[cat] }

    warn ''
    warn "Research tracked: #{tracked_count}/5 categories"
    research.each do |cat, info|
      status = info ? "done (#{info[:tool]})" : 'pending'
      warn "  #{cat}: #{status}"
    end

    # Now edit should work (all research done)
    if tracked_count == 5
      original_stderr = $stderr.clone
      $stderr.reopen('/dev/null', 'w')
      exit_code = process_tool_proc.call('Edit', { 'file_path' => '/tmp/test_project/test.swift' })
      $stderr.reopen(original_stderr)

      if exit_code == 0
        passed += 1
        warn '  PASS: Edit allowed after research'
      else
        failed += 1
        warn '  FAIL: Edit still blocked after research'
      end
    else
      warn '  SKIP: Not all research categories tracked'
    end

    # === JSON INTEGRATION TESTS ===
    warn ''
    warn 'Testing JSON parsing (integration):'

    require 'open3'
    script_path = File.expand_path('sanetools.rb', __dir__)

    # Test valid JSON with tool_name and tool_input
    json_input = '{"tool_name":"Read","tool_input":{"file_path":"/tmp/test_project/test.swift"}}'
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: json_input)
    if status.exitstatus == 0
      passed += 1
      warn '  PASS: Valid JSON parsed correctly (Read tool allowed)'
    else
      failed += 1
      warn "  FAIL: Valid JSON parsing - exit #{status.exitstatus}"
    end

    # Test blocked path via JSON
    json_input = '{"tool_name":"Read","tool_input":{"file_path":"~/.ssh/id_rsa"}}'
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: json_input)
    if status.exitstatus == 2
      passed += 1
      warn '  PASS: Blocked path correctly blocked via JSON'
    else
      failed += 1
      warn "  FAIL: Blocked path should return exit 2, got #{status.exitstatus}"
    end

    # Test invalid JSON doesn't crash
    json_input = 'not valid json at all'
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: json_input)
    if status.exitstatus == 0
      passed += 1
      warn '  PASS: Invalid JSON returns exit 0 (fail safe)'
    else
      failed += 1
      warn "  FAIL: Invalid JSON should return exit 0, got #{status.exitstatus}"
    end

    # Test empty input doesn't crash
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: '')
    if status.exitstatus == 0
      passed += 1
      warn '  PASS: Empty input returns exit 0 (fail safe)'
    else
      failed += 1
      warn "  FAIL: Empty input should return exit 0, got #{status.exitstatus}"
    end

    # === CLEANUP ===
    StateManager.reset(:circuit_breaker)
    StateManager.update(:enforcement) do |e|
      e[:halted] = false
      e[:blocks] = []
      e
    end

    warn ''
    warn "#{passed}/#{passed + failed} tests passed"

    if failed == 0
      warn ''
      warn 'ALL TESTS PASSED'
      0
    else
      warn ''
      warn "#{failed} TESTS FAILED"
      1
    end
  end

  def self.show_status(research_categories)
    research = StateManager.get(:research)
    cb = StateManager.get(:circuit_breaker)
    enf = StateManager.get(:enforcement)

    warn 'SaneTools Status'
    warn '=' * 40

    warn ''
    warn 'Research:'
    research_categories.keys.each do |cat|
      info = research[cat]
      status = info ? "done (#{info[:tool]}, via_task=#{info[:via_task]})" : 'pending'
      warn "  #{cat}: #{status}"
    end

    warn ''
    warn 'Circuit Breaker:'
    warn "  failures: #{cb[:failures]}"
    warn "  tripped: #{cb[:tripped]}"

    warn ''
    warn 'Enforcement:'
    warn "  halted: #{enf[:halted]}"
    warn "  blocks: #{enf[:blocks]&.length || 0}"

    0
  end

  def self.reset_state
    StateManager.reset(:research)
    StateManager.reset(:circuit_breaker)
    StateManager.update(:enforcement) do |e|
      e[:halted] = false
      e[:blocks] = []
      e
    end
    warn 'State reset'
    0
  end
end
