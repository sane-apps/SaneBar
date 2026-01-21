# frozen_string_literal: true

require_relative 'framework'

module TierTests
  def self.test_integration
    warn "\n=== INTEGRATION TESTS ==="
    passed = 0
    failed = 0

    warn "\n  [STATE FLOW] State persistence"

    state_file = File.join(PROJECT_DIR, '.claude/state.json')
    if File.exist?(state_file)
      begin
        JSON.parse(File.read(state_file))
        warn "  ✅ State file is valid JSON"
        passed += 1
      rescue JSON::ParserError
        warn "  ❌ State file is invalid JSON"
        failed += 1
      end
    else
      warn "  ⚠️  State file doesn't exist (may be first run)"
      passed += 1
    end

    warn "\n  [CHAIN] Saneprompt → Sanetools"

    require 'open3'

    prompt_stdout, prompt_stderr, prompt_status = Open3.capture3(
      { 'CLAUDE_PROJECT_DIR' => PROJECT_DIR, 'TIER_TEST_MODE' => 'true' },
      'ruby', File.join(HOOKS_DIR, 'saneprompt.rb'),
      stdin_data: { 'user_prompt' => 'fix the bug' }.to_json
    )

    if prompt_status.exitstatus == 0
      warn "  ✅ Saneprompt processed task prompt (exit 0)"
      passed += 1
    else
      warn "  ❌ Saneprompt failed (exit #{prompt_status.exitstatus})"
      failed += 1
    end

    tools_stdout, tools_stderr, tools_status = Open3.capture3(
      { 'CLAUDE_PROJECT_DIR' => PROJECT_DIR, 'TIER_TEST_MODE' => 'true' },
      'ruby', File.join(HOOKS_DIR, 'sanetools.rb'),
      stdin_data: { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => '/tmp/test.txt' } }.to_json
    )

    if tools_status.exitstatus == 0
      warn "  ✅ Sanetools allows Read after prompt (exit 0)"
      passed += 1
    else
      warn "  ❌ Sanetools blocked Read (exit #{tools_status.exitstatus})"
      failed += 1
    end

    track_stdout, track_stderr, track_status = Open3.capture3(
      { 'CLAUDE_PROJECT_DIR' => PROJECT_DIR, 'TIER_TEST_MODE' => 'true' },
      'ruby', File.join(HOOKS_DIR, 'sanetrack.rb'),
      stdin_data: {
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/test.txt' },
        'tool_result' => 'file contents'
      }.to_json
    )

    if track_status.exitstatus == 0
      warn "  ✅ Sanetrack processes Read result (exit 0)"
      passed += 1
    else
      warn "  ❌ Sanetrack failed (exit #{track_status.exitstatus})"
      failed += 1
    end

    warn "\n  [CHAIN] Session lifecycle"

    stop_stdout, stop_stderr, stop_status = Open3.capture3(
      { 'CLAUDE_PROJECT_DIR' => PROJECT_DIR, 'TIER_TEST_MODE' => 'true' },
      'ruby', File.join(HOOKS_DIR, 'sanestop.rb'),
      stdin_data: { 'stop_hook_active' => false }.to_json
    )

    if stop_status.exitstatus == 0
      warn "  ✅ Sanestop completes session (exit 0)"
      passed += 1
    else
      warn "  ❌ Sanestop failed (exit #{stop_status.exitstatus})"
      failed += 1
    end

    warn "\n  Integration: #{passed}/#{passed + failed} passed"

    {
      hook: 'INTEGRATION',
      passed: passed,
      failed: failed,
      skipped: 0,
      total: passed + failed,
      by_tier: { easy: passed, hard: 0, villain: 0 }
    }
  end
end
