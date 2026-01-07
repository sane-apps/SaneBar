#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SanePrompt Test Suite
# ==============================================================================
# Extracted from saneprompt.rb per Rule #10 (file size limit)
# Run: ruby saneprompt.rb --self-test
# ==============================================================================

require_relative 'core/state_manager'

module SanePromptTest
  def self.run(classify_proc, rules_proc, detect_triggers_proc, detect_frustration_proc,
               extract_requirements_proc, detect_research_only_proc, handle_safemode_proc)
    warn 'SanePrompt Self-Test'
    warn '=' * 40

    passed = 0
    failed = 0

    # === TEST COMMANDS FIRST (the ones that were never tested!) ===
    warn ''
    warn 'Testing commands:'

    # Test rb- resets circuit breaker
    StateManager.update(:circuit_breaker) { |cb| cb[:tripped] = true; cb[:failures] = 5; cb }
    original_stderr = $stderr.clone
    $stderr.reopen('/dev/null', 'w')
    result = handle_safemode_proc.call('rb-')
    $stderr.reopen(original_stderr)
    cb_after = StateManager.get(:circuit_breaker)
    if result == true && cb_after[:tripped] == false && cb_after[:failures] == 0
      passed += 1
      warn '  PASS: rb- resets circuit breaker'
    else
      failed += 1
      warn "  FAIL: rb- - result=#{result}, tripped=#{cb_after[:tripped]}"
    end

    # Test rb? returns true
    $stderr.reopen('/dev/null', 'w')
    result = handle_safemode_proc.call('rb?')
    $stderr.reopen(original_stderr)
    if result == true
      passed += 1
      warn '  PASS: rb? shows status'
    else
      failed += 1
      warn '  FAIL: rb? should return true'
    end

    # Test s- creates bypass file
    bypass_file = File.expand_path('../../.claude/bypass_active.json', __dir__)
    File.delete(bypass_file) if File.exist?(bypass_file)
    $stderr.reopen('/dev/null', 'w')
    handle_safemode_proc.call('s-')
    $stderr.reopen(original_stderr)
    if File.exist?(bypass_file)
      passed += 1
      warn '  PASS: s- creates bypass file'
    else
      failed += 1
      warn '  FAIL: s- should create bypass file'
    end

    # Test s+ deletes bypass file
    $stderr.reopen('/dev/null', 'w')
    handle_safemode_proc.call('s+')
    $stderr.reopen(original_stderr)
    if !File.exist?(bypass_file)
      passed += 1
      warn '  PASS: s+ deletes bypass file'
    else
      failed += 1
      warn '  FAIL: s+ should delete bypass file'
      File.delete(bypass_file) rescue nil
    end

    # === TEST JSON PARSING (the real production flow) ===
    warn ''
    warn 'Testing JSON parsing:'

    require 'open3'
    script_path = File.expand_path('saneprompt.rb', __dir__)

    # Test correct JSON structure
    json_input = '{"session_id":"test","prompt":"rb?"}'
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: json_input)
    if status.exitstatus == 0
      passed += 1
      warn '  PASS: JSON with prompt key parsed correctly'
    else
      failed += 1
      warn "  FAIL: JSON parsing failed - exit #{status.exitstatus}"
    end

    # Test missing prompt key defaults to empty
    json_input = '{"session_id":"test"}'
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: json_input)
    if status.exitstatus == 0
      passed += 1
      warn '  PASS: Missing prompt key handled gracefully'
    else
      failed += 1
      warn '  FAIL: Missing prompt key should not crash'
    end

    # Test invalid JSON doesn't crash
    json_input = 'not valid json {'
    _stdout, _stderr, status = Open3.capture3("ruby #{script_path}", stdin_data: json_input)
    if status.exitstatus == 0
      passed += 1
      warn '  PASS: Invalid JSON handled gracefully'
    else
      failed += 1
      warn "  FAIL: Invalid JSON should exit 0, not crash"
    end

    warn ''
    warn 'Testing prompt classification:'

    tests = [
      # === PASSTHROUGHS (35 tests) ===
      { input: 'y', expect: :passthrough },
      { input: 'yes', expect: :passthrough },
      { input: 'Y', expect: :passthrough },
      { input: 'Yes', expect: :passthrough },
      { input: 'YES', expect: :passthrough },
      { input: 'n', expect: :passthrough },
      { input: 'no', expect: :passthrough },
      { input: 'N', expect: :passthrough },
      { input: 'No', expect: :passthrough },
      { input: 'NO', expect: :passthrough },
      { input: 'ok', expect: :passthrough },
      { input: 'OK', expect: :passthrough },
      { input: 'Ok', expect: :passthrough },
      { input: 'k', expect: :passthrough },
      { input: 'sure', expect: :passthrough },
      { input: 'yep', expect: :passthrough },
      { input: 'nope', expect: :passthrough },
      { input: 'yeah', expect: :passthrough },
      { input: 'nah', expect: :passthrough },
      { input: '/commit', expect: :passthrough },
      { input: '/help', expect: :passthrough },
      { input: '/clear', expect: :passthrough },
      { input: '/status', expect: :passthrough },
      { input: 'rb-', expect: :passthrough },
      { input: 'rb?', expect: :passthrough },
      { input: 's+', expect: :passthrough },
      { input: 's-', expect: :passthrough },
      { input: '123', expect: :passthrough },
      { input: '1', expect: :passthrough },
      { input: '42', expect: :passthrough },
      { input: '', expect: :passthrough },
      { input: ' ', expect: :passthrough },
      { input: 'go', expect: :passthrough },
      { input: 'done', expect: :passthrough },
      { input: 'next', expect: :passthrough },

      # === QUESTIONS (35 tests) ===
      { input: 'what does this function do?', expect: :question },
      { input: 'how does the authentication work?', expect: :question },
      { input: 'can you explain the architecture?', expect: :question },
      { input: 'is this correct?', expect: :question },
      { input: 'why is this failing?', expect: :question },
      { input: 'where is the config file?', expect: :question },
      { input: 'when was this last updated?', expect: :question },
      { input: 'which module handles this?', expect: :question },
      { input: 'who wrote this code?', expect: :question },
      { input: 'does this support async?', expect: :question },
      { input: 'will this work on M1?', expect: :question },
      { input: 'should I use a struct or class?', expect: :question },
      { input: 'would this cause a memory leak?', expect: :question },
      { input: 'could you explain the flow?', expect: :question },
      { input: 'are there any edge cases?', expect: :question },
      { input: 'what is the purpose of this?', expect: :question },
      { input: 'how do I configure this?', expect: :question },
      { input: 'can this be simplified?', expect: :question },
      { input: 'is there a better approach?', expect: :question },
      { input: 'why does this use an actor?', expect: :question },
      { input: 'where should I put this file?', expect: :question },
      { input: 'what happens if this fails?', expect: :question },
      { input: 'how does error handling work here?', expect: :question },
      { input: 'can you trace the data flow?', expect: :question },
      { input: 'is this thread-safe?', expect: :question },
      { input: 'what are the dependencies?', expect: :question },
      { input: 'how is state managed?', expect: :question },
      { input: 'can you show me an example?', expect: :question },
      { input: 'is this the right pattern?', expect: :question },
      { input: 'what does this error mean?', expect: :question },
      { input: 'why use MainActor here?', expect: :question },
      { input: 'how do I test this?', expect: :question },
      { input: 'what is the expected behavior?', expect: :question },
      { input: 'can this be mocked?', expect: :question },
      { input: 'is there documentation for this?', expect: :question },

      # === TASKS (35 tests) ===
      { input: 'fix the bug in the login flow', expect: :task, rules: ['#3'] },
      { input: 'add a new feature for user auth', expect: :task, rules: ['#0'] },
      { input: 'refactor the database layer', expect: :task, rules: ['#4'] },
      { input: 'create a new file for settings', expect: :task, rules: ['#1'] },
      { input: 'update the config parser', expect: :task },
      { input: 'implement the save button', expect: :task },
      { input: 'write a test for this function', expect: :task },
      { input: 'add error handling here', expect: :task },
      { input: 'remove the deprecated method', expect: :task },
      { input: 'fix the variable name', expect: :task },
      { input: 'move the file to a separate folder', expect: :task },
      { input: 'create a new function for this', expect: :task },
      { input: 'add logging to this endpoint', expect: :task },
      { input: 'add validation for input parameters', expect: :task },
      { input: 'fix the nil case handling', expect: :task },
      { input: 'add a timeout to this request', expect: :task },
      { input: 'add caching for the response', expect: :task },
      { input: 'fix the slow database query', expect: :task },
      { input: 'add pagination support', expect: :task },
      { input: 'implement search functionality', expect: :task },
      { input: 'add a loading indicator', expect: :task },
      { input: 'fix the memory leak', expect: :task },
      { input: 'update the unit tests', expect: :task },
      { input: 'add support for dark mode', expect: :task },
      { input: 'implement the undo feature', expect: :task },
      { input: 'add keyboard shortcuts', expect: :task },
      { input: 'fix the layout issue', expect: :task },
      { input: 'update the dependencies', expect: :task },
      { input: 'add retry logic', expect: :task },
      { input: 'implement rate limiting', expect: :task },
      { input: 'add input validation', expect: :task },
      { input: 'fix the race condition', expect: :task },
      { input: 'add a progress bar', expect: :task },
      { input: 'implement the export feature', expect: :task },
      { input: 'add file upload support', expect: :task },

      # === BIG TASKS (20 tests) ===
      { input: 'rewrite the entire authentication system', expect: :big_task },
      { input: 'refactor everything in the core module', expect: :big_task },
      { input: 'update all the components to use new API', expect: :big_task },
      { input: 'update everything to migrate to Swift 6', expect: :big_task },
      { input: 'redesign the whole UI', expect: :big_task },
      { input: 'rebuild everything in the database layer', expect: :big_task },
      { input: 'refactor everything to restructure the project', expect: :big_task },
      { input: 'rewrite all the networking code', expect: :big_task },
      { input: 'overhaul the entire test suite', expect: :big_task },
      { input: 'refactor everything to use actors', expect: :big_task },
      { input: 'refactor the whole state management', expect: :big_task },
      { input: 'refactor all callbacks to async/await', expect: :big_task },
      { input: 'redesign the complete navigation system', expect: :big_task },
      { input: 'rewrite the entire persistence layer', expect: :big_task },
      { input: 'refactor all error handling everywhere', expect: :big_task },
      { input: 'refactor the full codebase to SwiftUI', expect: :big_task },
      { input: 'completely refactor all the services', expect: :big_task },
      { input: 'rebuild all the models everywhere', expect: :big_task },
      { input: 'replace the entire build system', expect: :big_task },
      { input: 'rewrite everything to be thread-safe', expect: :big_task },

      # === PATTERN TRIGGERS (10 tests) ===
      { input: 'quick fix for the login', expect: :task, trigger: 'quick' },
      { input: 'just add a button', expect: :task, trigger: 'just' },
      { input: 'simple change to the config', expect: :task, trigger: 'simple' },
      { input: 'add a small update to the styles', expect: :task, trigger: 'small' },
      { input: 'fix a small bug in the animation', expect: :task, trigger: 'small' },
      { input: 'minor fix for the tooltip', expect: :task, trigger: 'minor' },
      { input: 'easy change to the theme', expect: :task, trigger: 'easy' },
      { input: 'add a minor update to padding', expect: :task, trigger: 'minor' },
      { input: 'just a quick refactor', expect: :task, trigger: 'quick' },
      { input: 'simple one-liner fix', expect: :task, trigger: 'simple' },

      # === FRUSTRATION DETECTION (10 tests) ===
      { input: 'no, I said fix the login', expect: :task, frustration: :correction },
      { input: "that's not what I meant", expect: :question, frustration: :correction },
      { input: 'I just said fix it the other way again', expect: :task, frustration: :repetition },
      { input: 'I already said fix it differently', expect: :task },
      { input: 'no no no, fix it not like that', expect: :task, frustration: :correction },
      { input: 'fix the other file instead please', expect: :task },
      { input: 'that is wrong, fix it properly', expect: :task },
      { input: 'fix the same thing as before', expect: :task },
      { input: 'again I say fix the login', expect: :task },
      { input: 'fix this NOT what you did', expect: :task },

      # === RESEARCH-ONLY MODE (10 tests) ===
      { input: 'research why the login is failing', expect: :question, research_only: true },
      { input: 'investigate the crash in the camera module', expect: :question, research_only: true },
      { input: 'look into the memory leak issue', expect: :question, research_only: true },
      { input: 'explore the codebase to understand routing', expect: :question, research_only: true },
      { input: 'understand how the auth system works', expect: :question, research_only: true },
      { input: 'explain how the cache invalidation works', expect: :question, research_only: true },
      { input: "what's causing the slow performance", expect: :question, research_only: true },
      { input: 'find out why tests are flaky', expect: :question, research_only: true },
      { input: 'research the bug and fix it', expect: :task, research_only: false },
      { input: 'investigate and then implement the fix', expect: :task, research_only: false },

      # === REQUIREMENT EXTRACTION (10 tests) ===
      { input: 'start a saneloop and fix the bug', expect: :task, requirement: 'saneloop' },
      { input: 'commit the changes after you fix it', expect: :task, requirement: 'commit' },
      { input: 'make a plan first then implement it', expect: :task, requirement: 'plan' },
      { input: 'research this API then add the feature', expect: :task, requirement: 'research' },
      { input: 'enter saneloop to fix the issues', expect: :task, requirement: 'saneloop' },
      { input: 'create a commit when done fixing', expect: :task, requirement: 'commit' },
      { input: 'implement the fix after planning', expect: :task },
      { input: 'add the code after researching', expect: :task },
      { input: 'saneloop fix this complex bug', expect: :task, requirement: 'saneloop' },
      { input: 'fix everything then create commit', expect: :task }
    ]

    tests.each do |test|
      result_type = classify_proc.call(test[:input])
      type_ok = result_type == test[:expect]

      rules_ok = true
      if test[:rules]
        result_rules = rules_proc.call(test[:input])
        rules_ok = test[:rules].all? { |r| result_rules.any? { |rr| rr.include?(r) } }
      end

      trigger_ok = true
      if test[:trigger]
        triggers = detect_triggers_proc.call(test[:input])
        trigger_ok = triggers.any? { |t| t[:word] == test[:trigger] }
      end

      frustration_ok = true
      if test[:frustration]
        frustrations = detect_frustration_proc.call(test[:input])
        frustration_ok = frustrations.any? { |f| f[:type] == test[:frustration] }
      end

      requirement_ok = true
      if test[:requirement]
        requirements = extract_requirements_proc.call(test[:input])
        requirement_ok = requirements.include?(test[:requirement])
      end

      research_only_ok = true
      if test.key?(:research_only)
        is_research_only = detect_research_only_proc.call(test[:input])
        research_only_ok = is_research_only == test[:research_only]
      end

      if type_ok && rules_ok && trigger_ok && frustration_ok && requirement_ok && research_only_ok
        passed += 1
        warn "  PASS: '#{test[:input][0..40]}' -> #{result_type}"
      else
        failed += 1
        warn "  FAIL: '#{test[:input][0..40]}'"
        warn "        expected #{test[:expect]}, got #{result_type}" unless type_ok
        warn "        missing rule #{test[:rules]}" unless rules_ok
        warn "        missing trigger #{test[:trigger]}" unless trigger_ok
        warn "        missing frustration #{test[:frustration]}" unless frustration_ok
        warn "        missing requirement #{test[:requirement]}" unless requirement_ok
      end
    end

    warn ''
    warn "#{passed}/#{tests.length + 7} tests passed"  # +7 for command tests

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
end
