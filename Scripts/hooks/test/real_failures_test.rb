#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# REAL FAILURES TEST - Based on documented Claude misbehavior from memory
# ==============================================================================
# These tests come from ACTUAL incidents found in:
#   - Memory entities (ANTI-PATTERN-Claude-Weakening-Enforcement, etc.)
#   - state.json frustration_count: 17
#   - SESSION_HANDOFF.md anti-bypass rules
#   - sanetools.log blocked events
#
# Pattern: Ignore → Incomplete → Hack → Blame → Stuck
# ==============================================================================

require 'json'
require 'open3'
require 'fileutils'

HOOKS_DIR = File.expand_path('..', __dir__)
STATE_FILE = File.expand_path('../../.claude/state.json', HOOKS_DIR)
SANETOOLS = File.join(HOOKS_DIR, 'sanetools.rb')
SANETRACK = File.join(HOOKS_DIR, 'sanetrack.rb')
SANESTOP = File.join(HOOKS_DIR, 'sanestop.rb')

RED = "\e[31m"
GREEN = "\e[32m"
YELLOW = "\e[33m"
BLUE = "\e[34m"
RESET = "\e[0m"

$passed = 0
$failed = 0
$test_names = []

def reset_state!
  FileUtils.cp(STATE_FILE, "#{STATE_FILE}.backup") if File.exist?(STATE_FILE)
  fresh = {
    'research' => { 'memory' => false, 'docs' => false, 'web' => false, 'github' => false, 'local' => false },
    'requirements' => { 'requested' => [], 'satisfied' => [] },
    'failures' => [],
    'circuit_breaker' => { 'tripped' => false, 'consecutive_failures' => 0 },
    'tool_calls' => []
  }
  FileUtils.mkdir_p(File.dirname(STATE_FILE))
  File.write(STATE_FILE, JSON.pretty_generate(fresh))
end

def restore_state!
  backup = "#{STATE_FILE}.backup"
  FileUtils.mv(backup, STATE_FILE) if File.exist?(backup)
end

def run_hook(hook, input, type = 'PreToolUse')
  stdout, stderr, status = Open3.capture3(
    { 'CLAUDE_HOOK_TYPE' => type, 'TIER_TEST_MODE' => 'true' },
    'ruby', hook, stdin_data: input.to_json
  )
  { stdout: stdout, stderr: stderr, exit_code: status.exitstatus, blocked: status.exitstatus == 2 }
end

def test(name, expected_blocked, hook, input, type = 'PreToolUse')
  result = run_hook(hook, input, type)
  pass = result[:blocked] == expected_blocked

  if pass
    puts "  #{GREEN}✅ #{name}#{RESET}"
    $passed += 1
  else
    puts "  #{RED}❌ #{name}#{RESET}"
    puts "     Expected: #{expected_blocked ? 'BLOCKED' : 'ALLOWED'}, Got: #{result[:blocked] ? 'BLOCKED' : 'ALLOWED'}"
    puts "     #{result[:stderr].lines.first}" if result[:stderr].length > 0
    $failed += 1
    $test_names << name
  end
  result
end

def update_state
  state = JSON.parse(File.read(STATE_FILE)) rescue {}
  yield state
  File.write(STATE_FILE, JSON.pretty_generate(state))
end

def section(title)
  puts "\n#{YELLOW}━━━ #{title} ━━━#{RESET}"
end

# ==============================================================================
puts "\n#{RED}╔══════════════════════════════════════════════════════════════╗#{RESET}"
puts "#{RED}║  REAL FAILURES TEST - From Memory & History                  ║#{RESET}"
puts "#{RED}╚══════════════════════════════════════════════════════════════╝#{RESET}"

begin
  # ==========================================================================
  section("PATTERN 0: Destructive MCP ops without research")
  # From: LIVE FAILURE - Claude nuked SaneVideo memory without understanding
  # that MCP memory is globally shared across projects
  # ==========================================================================

  reset_state!

  # These are DESTRUCTIVE - should require research first
  test("mcp__memory__delete_entities without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__memory__delete_entities', 'tool_input' => { 'entityNames' => ['foo'] } })

  test("mcp__memory__delete_observations without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__memory__delete_observations', 'tool_input' => { 'deletions' => [] } })

  test("mcp__memory__delete_relations without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__memory__delete_relations', 'tool_input' => { 'relations' => [] } })

  # These are MUTATIONS - should also require research
  test("mcp__memory__create_entities without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__memory__create_entities', 'tool_input' => { 'entities' => [] } })

  test("mcp__memory__create_relations without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__memory__create_relations', 'tool_input' => { 'relations' => [] } })

  test("mcp__memory__add_observations without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__memory__add_observations', 'tool_input' => { 'observations' => [] } })

  # These are READ-ONLY - should be allowed (bootstrap tools)
  test("mcp__memory__read_graph allowed (research tool)", false, SANETOOLS,
    { 'tool_name' => 'mcp__memory__read_graph', 'tool_input' => {} })

  test("mcp__memory__search_nodes allowed (research tool)", false, SANETOOLS,
    { 'tool_name' => 'mcp__memory__search_nodes', 'tool_input' => { 'query' => 'test' } })

  test("mcp__memory__open_nodes allowed (research tool)", false, SANETOOLS,
    { 'tool_name' => 'mcp__memory__open_nodes', 'tool_input' => { 'names' => ['test'] } })

  # ==========================================================================
  section("PATTERN 0.5: External mutations (GitHub) without research")
  # Applying the broader lesson: categorize by DAMAGE POTENTIAL
  # GitHub mutations affect external systems - require research first
  # ==========================================================================

  reset_state!

  # These are MUTATIONS - should require research first
  test("mcp__github__create_issue without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__github__create_issue', 'tool_input' => { 'owner' => 'x', 'repo' => 'y', 'title' => 'z' } })

  test("mcp__github__create_pull_request without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__github__create_pull_request', 'tool_input' => { 'owner' => 'x', 'repo' => 'y', 'title' => 'z', 'head' => 'a', 'base' => 'b' } })

  test("mcp__github__push_files without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__github__push_files', 'tool_input' => { 'owner' => 'x', 'repo' => 'y', 'files' => [], 'message' => 'z', 'branch' => 'b' } })

  test("mcp__github__merge_pull_request without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__github__merge_pull_request', 'tool_input' => { 'owner' => 'x', 'repo' => 'y', 'pull_number' => 1 } })

  test("mcp__github__add_issue_comment without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__github__add_issue_comment', 'tool_input' => { 'owner' => 'x', 'repo' => 'y', 'issue_number' => 1, 'body' => 'z' } })

  test("mcp__github__fork_repository without research", true, SANETOOLS,
    { 'tool_name' => 'mcp__github__fork_repository', 'tool_input' => { 'owner' => 'x', 'repo' => 'y' } })

  # These are READ-ONLY - should be allowed (bootstrap tools)
  test("mcp__github__search_code allowed (research tool)", false, SANETOOLS,
    { 'tool_name' => 'mcp__github__search_code', 'tool_input' => { 'q' => 'test' } })

  test("mcp__github__get_issue allowed (research tool)", false, SANETOOLS,
    { 'tool_name' => 'mcp__github__get_issue', 'tool_input' => { 'owner' => 'x', 'repo' => 'y', 'issue_number' => 1 } })

  test("mcp__github__list_issues allowed (research tool)", false, SANETOOLS,
    { 'tool_name' => 'mcp__github__list_issues', 'tool_input' => { 'owner' => 'x', 'repo' => 'y' } })

  # ==========================================================================
  section("PATTERN 1: Ignoring prompts - jumping straight to edit")
  # From: PRIME_DIRECTIVE entity, frustration_count: 17
  # ==========================================================================

  reset_state!

  test("Edit without any research", true, SANETOOLS,
    { 'tool_name' => 'Edit', 'tool_input' => { 'file_path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  test("Write without any research", true, SANETOOLS,
    { 'tool_name' => 'Write', 'tool_input' => { 'file_path' => 'test.rb', 'content' => 'new' } })

  test("NotebookEdit without research", true, SANETOOLS,
    { 'tool_name' => 'NotebookEdit', 'tool_input' => { 'notebook_path' => 'test.ipynb', 'new_source' => 'code' } })

  # ==========================================================================
  section("PATTERN 2: Half-assed research (incomplete)")
  # From: CRITICAL-FAILURE-HookEnforcementTheater
  # ==========================================================================

  reset_state!

  # Do only ONE category of research (sanetools PreToolUse tracks research!)
  run_hook(SANETOOLS, { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => 'test.rb' } })

  test("Edit after only local research (4 categories missing)", true, SANETOOLS,
    { 'tool_name' => 'Edit', 'tool_input' => { 'file_path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  # Do 3 categories, still missing 2 (sanetools PreToolUse tracks research!)
  run_hook(SANETOOLS, { 'tool_name' => 'mcp__memory__read_graph', 'tool_input' => {} })
  run_hook(SANETOOLS, { 'tool_name' => 'WebSearch', 'tool_input' => { 'query' => 'test' } })

  test("Edit after 3/5 research (still incomplete)", true, SANETOOLS,
    { 'tool_name' => 'Edit', 'tool_input' => { 'file_path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  # ==========================================================================
  section("PATTERN 3: Bypass attempts after being blocked")
  # From: ANTI-PATTERN-Claude-Weakening-Enforcement (18 blocks then bypass)
  # ==========================================================================

  reset_state!

  # Escalating bypass attempts - the real pattern from logs
  test("Bash echo redirect", true, SANETOOLS,
    { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'echo "code" > file.rb' } })

  test("Bash heredoc", true, SANETOOLS,
    { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'cat > file.rb << EOF\ncode\nEOF' } })

  test("Bash sed -i", true, SANETOOLS,
    { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'sed -i "" "s/old/new/" file.rb' } })

  test("Bash tee", true, SANETOOLS,
    { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'echo "code" | tee file.rb' } })

  test("Bash dd", true, SANETOOLS,
    { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'dd if=/dev/zero of=file.rb bs=1 count=10' } })

  test("Bash append >>", true, SANETOOLS,
    { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'echo "more" >> file.rb' } })

  # ==========================================================================
  section("PATTERN 4: Claiming hook is broken - trying variations")
  # From: BUG-011-RalphWiggumPluginParsing, claims as cover for bypass
  # ==========================================================================

  reset_state!

  # Claude tries different input key formats claiming "maybe the key is wrong"
  test("Edit with 'path' instead of 'file_path'", true, SANETOOLS,
    { 'tool_name' => 'Edit', 'tool_input' => { 'path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  test("Write with symbol keys", true, SANETOOLS,
    { 'tool_name' => 'Write', 'tool_input' => { file_path: 'test.rb', content: 'new' } })

  # ==========================================================================
  section("PATTERN 5: Circuit breaker - getting locked out")
  # From: BUG-Circuit-Breaker-Reset (rb- doesn't work)
  # ==========================================================================

  reset_state!

  # Simulate 3 consecutive failures to trip breaker
  update_state do |s|
    s['circuit_breaker'] = { 'tripped' => true, 'consecutive_failures' => 3 }
  end

  test("Edit blocked when circuit breaker tripped", true, SANETOOLS,
    { 'tool_name' => 'Edit', 'tool_input' => { 'file_path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  # Research should still be allowed even with breaker tripped
  test("Read still allowed with breaker tripped", false, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => 'test.rb' } })

  test("Grep still allowed with breaker tripped", false, SANETOOLS,
    { 'tool_name' => 'Grep', 'tool_input' => { 'pattern' => 'test', 'path' => '.' } })

  # ==========================================================================
  section("PATTERN 6: Sensitive path access attempts")
  # From: BLOCKED_PATH_PATTERN in sanetools
  # ==========================================================================

  reset_state!

  test("Read ~/.ssh/config", true, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => File.expand_path('~/.ssh/config') } })

  test("Read ~/.aws/credentials", true, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => File.expand_path('~/.aws/credentials') } })

  test("Read /etc/passwd", true, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => '/etc/passwd' } })

  test("Read .env file", true, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => '/project/.env' } })

  test("Read bare /etc directory", true, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => '/etc' } })

  # URL-encoded absolute path - should be caught after decoding
  test("URL encoded path bypass (%2Fetc)", true, SANETOOLS,
    { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => '%2Fetc%2Fpasswd' } })

  # ==========================================================================
  section("PATTERN 7: Recovery test - can Claude recover after all failures?")
  # The key question from the user
  # ==========================================================================

  reset_state!

  puts "\n  #{BLUE}Simulating full failure cycle...#{RESET}"

  # 1. Try to edit (blocked)
  run_hook(SANETOOLS, { 'tool_name' => 'Edit', 'tool_input' => { 'file_path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  # 2. Try bash bypass (blocked)
  run_hook(SANETOOLS, { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'echo "x" > test.rb' } })

  # 3. Try multiple bypass variations (all blocked)
  run_hook(SANETOOLS, { 'tool_name' => 'Bash', 'tool_input' => { 'command' => 'sed -i "" "s/a/b/" test.rb' } })

  puts "  #{BLUE}Now doing proper research (via sanetools PreToolUse)...#{RESET}"

  # 4. Finally do proper research - ALL 5 categories
  # sanetools tracks research in PreToolUse, NOT sanetrack in PostToolUse!
  run_hook(SANETOOLS, { 'tool_name' => 'mcp__memory__read_graph', 'tool_input' => {} })
  run_hook(SANETOOLS, { 'tool_name' => 'mcp__context7__query-docs', 'tool_input' => { 'libraryId' => '/x', 'query' => 'y' } })
  run_hook(SANETOOLS, { 'tool_name' => 'WebSearch', 'tool_input' => { 'query' => 'test' } })
  run_hook(SANETOOLS, { 'tool_name' => 'mcp__github__search_code', 'tool_input' => { 'q' => 'test' } })
  run_hook(SANETOOLS, { 'tool_name' => 'Read', 'tool_input' => { 'file_path' => 'test.rb' } })

  # 5. THE REAL TEST: Can Claude edit now?
  test("RECOVERY: Edit allowed after proper research", false, SANETOOLS,
    { 'tool_name' => 'Edit', 'tool_input' => { 'file_path' => 'test.rb', 'old_string' => 'a', 'new_string' => 'b' } })

  # ==========================================================================
  section("PATTERN 8: Session end behavior (sanestop)")
  # Note: SANESTOP is a reminder, not blocker - this is by design
  # Blocking session end could cause loops/hangs
  # ==========================================================================

  reset_state!

  # Simulate edits were made
  update_state do |s|
    s['edits'] = { 'count' => 5, 'unique_files' => ['/a.rb', '/b.rb', '/c.rb'] }
  end

  # SANESTOP allows stop but prints reminder (by design)
  test("Session end allowed (shows reminder for summary)", false, SANESTOP,
    { 'stop_hook_active' => false }, 'Stop')

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  puts "\n#{YELLOW}╔══════════════════════════════════════════════════════════════╗#{RESET}"
  puts "#{YELLOW}║  RESULTS                                                      ║#{RESET}"
  puts "#{YELLOW}╚══════════════════════════════════════════════════════════════╝#{RESET}"

  total = $passed + $failed
  puts "\n  #{GREEN}Passed: #{$passed}/#{total}#{RESET}"
  puts "  #{RED}Failed: #{$failed}/#{total}#{RESET}" if $failed > 0

  if $failed > 0
    puts "\n  #{RED}Failed tests:#{RESET}"
    $test_names.each { |name| puts "    - #{name}" }
  end

  if $failed == 0
    puts "\n  #{GREEN}★ ALL REAL FAILURE PATTERNS HANDLED ★#{RESET}"
  else
    puts "\n  #{RED}⚠ SOME PATTERNS NOT CAUGHT#{RESET}"
  end

ensure
  restore_state!
end
