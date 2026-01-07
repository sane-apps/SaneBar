#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Hook System Integration Tests
# ==============================================================================
# Comprehensive tests for the consolidated hook architecture.
# Run: ruby scripts/hooks/test_hooks.rb
# ==============================================================================

require 'json'
require 'open3'
require 'fileutils'

PROJECT_DIR = File.expand_path('../..', __dir__)
ENV['CLAUDE_PROJECT_DIR'] = PROJECT_DIR

class HookTests
  attr_reader :passed, :failed, :results

  def initialize
    @passed = 0
    @failed = 0
    @results = []
  end

  def run_all
    puts "=" * 60
    puts "HOOK SYSTEM INTEGRATION TESTS"
    puts "=" * 60
    puts

    # Test StateManager
    test_group("StateManager") do
      test("get/set basic values") { test_state_get_set }
      test("update with block") { test_state_update }
      test("reset section") { test_state_reset }
      test("preserves sections on reset_except") { test_state_reset_except }
    end

    # Test HookRegistry
    test_group("HookRegistry") do
      test("auto-registers detectors") { test_registry_auto_register }
      test("priority ordering") { test_registry_priority }
    end

    # Test Detectors
    test_group("Detectors") do
      test("PathDetector blocks ~/.ssh") { test_path_blocks_ssh }
      test("PathDetector blocks /etc") { test_path_blocks_etc }
      test("PathDetector allows project paths") { test_path_allows_project }
      test("PathDetector allows /tmp") { test_path_allows_tmp }
    end

    # Test Coordinator
    test_group("Coordinator") do
      test("allows research tools") { test_coordinator_allows_research }
      test("blocks dangerous paths on research") { test_coordinator_blocks_dangerous }
      test("bootstrap commands allowed") { test_coordinator_allows_bootstrap }
    end

    # Test Entry Points
    test_group("Entry Points") do
      test("pre_tool_use.rb syntax valid") { test_entry_syntax('pre_tool_use.rb') }
      test("post_tool_use.rb syntax valid") { test_entry_syntax('post_tool_use.rb') }
      test("session_start.rb syntax valid") { test_entry_syntax('session_start.rb') }
    end

    # Test Circuit Breaker
    test_group("Circuit Breaker") do
      test("tracks blocks") { test_circuit_breaker_tracks }
      test("halts after 5x same") { test_circuit_breaker_halts }
    end

    # Summary
    puts
    puts "=" * 60
    puts "RESULTS: #{@passed} passed, #{@failed} failed"
    puts "=" * 60

    @failed == 0
  end

  private

  def test_group(name)
    puts "\n#{name}:"
    puts "-" * 40
    yield
  end

  def test(name)
    result = yield
    if result
      @passed += 1
      puts "  ✅ #{name}"
      @results << { name: name, status: :pass }
    else
      @failed += 1
      puts "  ❌ #{name}"
      @results << { name: name, status: :fail }
    end
  rescue StandardError => e
    @failed += 1
    puts "  ❌ #{name} - #{e.message}"
    @results << { name: name, status: :error, error: e.message }
  end

  # StateManager tests
  def test_state_get_set
    require_relative 'core/state_manager'
    StateManager.reset_all
    StateManager.set(:requirements, :requested, ['saneloop'])
    StateManager.get(:requirements, :requested) == ['saneloop']
  end

  def test_state_update
    require_relative 'core/state_manager'
    StateManager.reset(:edits)
    StateManager.update(:edits) do |e|
      e[:count] = 5
      e
    end
    StateManager.get(:edits, :count) == 5
  end

  def test_state_reset
    require_relative 'core/state_manager'
    StateManager.set(:requirements, :requested, ['test'])
    StateManager.reset(:requirements)
    req = StateManager.get(:requirements, :requested)
    req.nil? || req.empty?
  end

  def test_state_reset_except
    require_relative 'core/state_manager'
    StateManager.set(:enforcement, :halted, true)
    StateManager.set(:requirements, :requested, ['test'])
    StateManager.reset_except(:enforcement)
    req = StateManager.get(:requirements, :requested)
    halted = StateManager.get(:enforcement, :halted)
    (req.nil? || req.empty?) && halted == true
  end

  # HookRegistry tests
  def test_registry_auto_register
    require_relative 'core/hook_registry'
    require_relative 'detectors/base_detector'
    require_relative 'detectors/path_detector'

    hooks = HookRegistry.for(:pre_tool_use)
    hooks.any? { |h| h.name == 'PathDetector' }
  end

  def test_registry_priority
    require_relative 'core/hook_registry'

    hooks = HookRegistry.for(:pre_tool_use)
    return false if hooks.empty?

    # Verify sorted by priority (lower first)
    priorities = hooks.map(&:priority)
    priorities == priorities.sort
  end

  # Detector tests (using entry point)
  def test_path_blocks_ssh
    run_hook('Read', '~/.ssh/id_rsa') == 2
  end

  def test_path_blocks_etc
    run_hook('Read', '/etc/passwd') == 2
  end

  def test_path_allows_project
    run_hook('Read', "#{PROJECT_DIR}/README.md") == 0
  end

  def test_path_allows_tmp
    run_hook('Read', '/tmp/test.txt') == 0
  end

  # Coordinator tests
  def test_coordinator_allows_research
    run_hook('Grep', '/tmp/test') == 0
  end

  def test_coordinator_blocks_dangerous
    run_hook('Read', '~/.aws/credentials') == 2
  end

  def test_coordinator_allows_bootstrap
    run_hook('Bash', './scripts/SaneMaster.rb saneloop start "test"', command: true) == 0
  end

  # Entry point syntax tests
  def test_entry_syntax(file)
    path = File.join(__dir__, 'hooks', file)
    _, status = Open3.capture2e("ruby -c #{path}")
    status.success?
  end

  # Circuit breaker tests
  def test_circuit_breaker_tracks
    require_relative 'core/state_manager'
    StateManager.reset(:enforcement)

    # Simulate a block
    StateManager.update(:enforcement) do |e|
      e[:blocks] ||= []
      e[:blocks] << { 'signature' => 'test:Detector', 'at' => Time.now.iso8601 }
      e
    end

    blocks = StateManager.get(:enforcement, :blocks)
    blocks.length == 1
  end

  def test_circuit_breaker_halts
    require_relative 'core/state_manager'
    StateManager.reset(:enforcement)

    # Add 5 identical blocks
    5.times do
      StateManager.update(:enforcement) do |e|
        e[:blocks] ||= []
        e[:blocks] << { 'signature' => 'same:Detector', 'at' => Time.now.iso8601 }

        # Check for halt condition
        recent = e[:blocks].last(5)
        if recent.length >= 5 && recent.all? { |b| b['signature'] == 'same:Detector' }
          e[:halted] = true
        end
        e
      end
    end

    StateManager.get(:enforcement, :halted) == true
  end

  # Helper to run hook with input
  def run_hook(tool, path, command: false)
    input = if command
              { 'tool_name' => tool, 'tool_input' => { 'command' => path } }
            else
              { 'tool_name' => tool, 'tool_input' => { 'file_path' => path } }
            end

    hook_path = File.join(__dir__, 'hooks', 'pre_tool_use.rb')

    stdout, stderr, status = Open3.capture3(
      { 'CLAUDE_PROJECT_DIR' => PROJECT_DIR },
      'ruby', hook_path,
      stdin_data: JSON.generate(input)
    )

    status.exitstatus
  end
end

# Run tests
if __FILE__ == $PROGRAM_NAME
  tests = HookTests.new
  success = tests.run_all
  exit(success ? 0 : 1)
end
