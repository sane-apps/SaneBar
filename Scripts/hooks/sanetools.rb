#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneTools - PreToolUse Hook
# ==============================================================================
# Enforces all requirements before tool execution.
#
# Exit codes:
#   0 = allow
#   2 = BLOCK (tool does NOT execute)
#
# What this enforces:
#   1. Blocked paths (/.ssh, /.aws, secrets, system dirs)
#   2. Research before editing (5 categories via Task agents)
#   3. Circuit breaker (3 failures = blocked)
#   4. Bash file write bypass detection
#   5. Subagent bypass detection
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'core/state_manager'

LOG_FILE = File.expand_path('../../.claude/sanetools.log', __dir__)

# === TOOL CLASSIFICATION ===

EDIT_TOOLS = %w[Edit Write NotebookEdit].freeze
RESEARCH_TOOLS = %w[Read Grep Glob WebSearch WebFetch Task].freeze
MEMORY_TOOLS = %w[mcp__memory__read_graph mcp__memory__search_nodes].freeze

# === BLOCKED PATHS ===

BLOCKED_PATHS = [
  %r{^/var/},
  %r{^/etc/},
  %r{^/usr/},
  %r{^/System/},
  %r{\.ssh/},
  %r{\.aws/},
  %r{\.claude_hook_secret},
  %r{/\.git/objects/},
  %r{\.netrc},
  %r{credentials\.json},
  %r{\.env$},
].freeze

# === BYPASS DETECTION ===

BASH_FILE_WRITE_PATTERNS = [
  />\s*[^&]/,           # redirect (but not 2>&1)
  />>/,                 # append
  /\bsed\s+-i/,         # sed in-place
  /\btee\b/,            # tee command
  /\bdd\b.*\bof=/,      # dd output file
  /<<[A-Z_]+/,          # heredoc
  /\bcat\b.*>/,         # cat redirect
].freeze

EDIT_KEYWORDS = %w[edit write create modify change update add remove delete fix patch].freeze

# === RESEARCH CATEGORIES ===

RESEARCH_CATEGORIES = {
  memory: {
    tools: %w[mcp__memory__read_graph mcp__memory__search_nodes],
    task_patterns: [/memory/i, /past bugs/i, /previous/i, /history/i]
  },
  docs: {
    tools: %w[mcp__apple-docs__* mcp__context7__*],
    task_patterns: [/docs/i, /documentation/i, /apple-docs/i, /context7/i, /api/i]
  },
  web: {
    tools: %w[WebSearch WebFetch],
    task_patterns: [/web/i, /search online/i, /google/i, /internet/i]
  },
  github: {
    tools: %w[mcp__github__*],
    task_patterns: [/github/i, /external.*example/i, /other.*repo/i]
  },
  local: {
    tools: %w[Read Grep Glob],
    task_patterns: [/codebase/i, /local/i, /existing/i, /current.*code/i, /file/i]
  }
}.freeze

# === CHECK FUNCTIONS ===

def check_blocked_path(tool_input)
  path = tool_input['file_path'] || tool_input['path'] || tool_input[:file_path] || tool_input[:path]
  return nil unless path

  path = File.expand_path(path) rescue path

  BLOCKED_PATHS.each do |pattern|
    if path.match?(pattern)
      return "BLOCKED PATH: #{path}\nRule #1: Stay in your lane"
    end
  end

  nil
end

def check_circuit_breaker
  cb = StateManager.get(:circuit_breaker)
  return nil unless cb[:tripped]

  "CIRCUIT BREAKER TRIPPED\n" \
  "#{cb[:failures]} consecutive failures detected.\n" \
  "Last error: #{cb[:last_error]}\n" \
  "User must say 'reset breaker' to continue."
end

def check_enforcement_halted
  enf = StateManager.get(:enforcement)
  return nil unless enf[:halted]

  # Allow through but warn - enforcement was halted due to loop detection
  warn "Enforcement halted: #{enf[:halted_reason]}"
  nil
end

def check_bash_bypass(tool_name, tool_input)
  return nil unless tool_name == 'Bash'

  command = tool_input['command'] || tool_input[:command] || ''

  BASH_FILE_WRITE_PATTERNS.each do |pattern|
    if command.match?(pattern)
      # Check if research is complete
      research = StateManager.get(:research)
      complete = research_complete?(research)

      unless complete
        return "BASH FILE WRITE BLOCKED\n" \
               "Command appears to write files: #{command[0..50]}...\n" \
               "Complete research first (5 categories)."
      end
    end
  end

  nil
end

def check_subagent_bypass(tool_name, tool_input)
  return nil unless tool_name == 'Task'

  prompt = tool_input['prompt'] || tool_input[:prompt] || ''
  prompt_lower = prompt.downcase

  # Check if this Task is for editing
  is_edit_task = EDIT_KEYWORDS.any? { |kw| prompt_lower.include?(kw) }
  return nil unless is_edit_task

  # Check if research is complete
  research = StateManager.get(:research)
  complete = research_complete?(research)

  unless complete
    return "SUBAGENT BYPASS BLOCKED\n" \
           "Task appears to be for editing: #{prompt[0..50]}...\n" \
           "Complete research first (5 categories)."
  end

  nil
end

def check_research_before_edit(tool_name, tool_input)
  return nil unless EDIT_TOOLS.include?(tool_name)

  research = StateManager.get(:research)
  complete = research_complete?(research)

  return nil if complete

  missing = research_missing(research)
  "RESEARCH INCOMPLETE\n" \
  "Cannot edit until research is complete.\n" \
  "Missing: #{missing.join(', ')}\n" \
  "Use Task agents for each category."
end

def research_complete?(research)
  RESEARCH_CATEGORIES.keys.all? { |cat| research[cat] }
end

def research_missing(research)
  RESEARCH_CATEGORIES.keys.reject { |cat| research[cat] }
end

# === RESEARCH TRACKING ===

def track_research(tool_name, tool_input)
  # Check direct tool matches
  RESEARCH_CATEGORIES.each do |category, config|
    if config[:tools].any? { |t| tool_name.start_with?(t.sub('*', '')) }
      mark_research_done(category, tool_name, false)
    end
  end

  # Check Task agent prompts
  if tool_name == 'Task'
    prompt = tool_input['prompt'] || tool_input[:prompt] || ''

    RESEARCH_CATEGORIES.each do |category, config|
      if config[:task_patterns].any? { |p| prompt.match?(p) }
        mark_research_done(category, 'Task', true)
      end
    end
  end
end

def mark_research_done(category, tool, via_task)
  current = StateManager.get(:research, category)

  # Task agents can upgrade non-Task entries
  return if current && current[:via_task] && !via_task

  StateManager.update(:research) do |r|
    r[category] = {
      completed_at: Time.now.iso8601,
      tool: tool,
      via_task: via_task
    }
    r
  end
end

# === LOGGING ===

def log_action(tool_name, blocked, reason = nil)
  FileUtils.mkdir_p(File.dirname(LOG_FILE))
  entry = {
    timestamp: Time.now.iso8601,
    tool: tool_name,
    blocked: blocked,
    reason: reason&.lines&.first&.strip,
    pid: Process.pid
  }
  File.open(LOG_FILE, 'a') { |f| f.puts(entry.to_json) }
rescue StandardError
  # Don't fail on logging errors
end

# === MAIN ENFORCEMENT ===

def process_tool(tool_name, tool_input)
  # Always check blocked paths first
  if (reason = check_blocked_path(tool_input))
    log_action(tool_name, true, reason)
    output_block(reason)
    return 2
  end

  # Check circuit breaker
  if (reason = check_circuit_breaker)
    log_action(tool_name, true, reason)
    output_block(reason)
    return 2
  end

  # Check if enforcement is halted (warn but allow)
  check_enforcement_halted

  # Track research progress BEFORE checking requirements
  track_research(tool_name, tool_input)

  # Check bash bypass
  if (reason = check_bash_bypass(tool_name, tool_input))
    log_action(tool_name, true, reason)
    output_block(reason)
    return 2
  end

  # Check subagent bypass
  if (reason = check_subagent_bypass(tool_name, tool_input))
    log_action(tool_name, true, reason)
    output_block(reason)
    return 2
  end

  # Check research before edit
  if (reason = check_research_before_edit(tool_name, tool_input))
    log_action(tool_name, true, reason)
    output_block(reason)
    return 2
  end

  # All checks passed
  log_action(tool_name, false)
  0
end

def output_block(reason)
  warn '---'
  warn 'SANETOOLS BLOCKED'
  warn ''
  warn reason
  warn '---'
end

# === SELF-TEST ===

def self_test
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

  tests = [
    # Blocked paths
    { tool: 'Read', input: { 'file_path' => '~/.ssh/id_rsa' }, expect_block: true, name: 'Block ~/.ssh/' },
    { tool: 'Edit', input: { 'file_path' => '/etc/passwd' }, expect_block: true, name: 'Block /etc/' },
    { tool: 'Write', input: { 'file_path' => '/var/log/test' }, expect_block: true, name: 'Block /var/' },

    # Edit without research (should block)
    { tool: 'Edit', input: { 'file_path' => '/Users/sj/SaneProcess/test.swift' }, expect_block: true, name: 'Block edit without research' },

    # Research tools (should allow and track)
    { tool: 'Read', input: { 'file_path' => '/Users/sj/SaneProcess/test.swift' }, expect_block: false, name: 'Allow Read (tracks local)' },
    { tool: 'Grep', input: { 'pattern' => 'test' }, expect_block: false, name: 'Allow Grep' },
    { tool: 'WebSearch', input: { 'query' => 'swift patterns' }, expect_block: false, name: 'Allow WebSearch (tracks web)' },
    { tool: 'mcp__memory__read_graph', input: {}, expect_block: false, name: 'Allow memory read (tracks memory)' },

    # Task agents (should allow and track)
    { tool: 'Task', input: { 'prompt' => 'Search documentation for this API' }, expect_block: false, name: 'Allow Task (tracks docs)' },
    { tool: 'Task', input: { 'prompt' => 'Search GitHub for external examples' }, expect_block: false, name: 'Allow Task (tracks github)' },
  ]

  passed = 0
  failed = 0

  tests.each do |test|
    # Suppress output
    original_stderr = $stderr.clone
    $stderr.reopen('/dev/null', 'w')

    exit_code = process_tool(test[:tool], test[:input])

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
  tracked_count = RESEARCH_CATEGORIES.keys.count { |cat| research[cat] }

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
    exit_code = process_tool('Edit', { 'file_path' => '/Users/sj/SaneProcess/test.swift' })
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

def show_status
  research = StateManager.get(:research)
  cb = StateManager.get(:circuit_breaker)
  enf = StateManager.get(:enforcement)

  warn 'SaneTools Status'
  warn '=' * 40

  warn ''
  warn 'Research:'
  RESEARCH_CATEGORIES.keys.each do |cat|
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

  exit 0
end

def reset_state
  StateManager.reset(:research)
  StateManager.reset(:circuit_breaker)
  StateManager.update(:enforcement) do |e|
    e[:halted] = false
    e[:blocks] = []
    e
  end
  warn 'State reset'
  exit 0
end

# === MAIN ===

if ARGV.include?('--self-test')
  self_test
elsif ARGV.include?('--status')
  show_status
elsif ARGV.include?('--reset')
  reset_state
else
  begin
    input = JSON.parse($stdin.read)
    tool_name = input['tool_name'] || 'unknown'
    tool_input = input['tool_input'] || {}
    exit process_tool(tool_name, tool_input)
  rescue JSON::ParserError, Errno::ENOENT
    exit 0  # Don't block on parse errors
  end
end
