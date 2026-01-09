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
# Structure (per Rule #10 - file size limit):
#   sanetools.rb        - Main entry, constants, processing (~350 lines)
#   sanetools_checks.rb - All check_* functions (~280 lines)
#   sanetools_test.rb   - Self-test suite (~230 lines)
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'core/state_manager'
require_relative 'sanetools_checks'

# === SAFEMODE BYPASS ===
BYPASS_FILE = File.expand_path('../../.claude/bypass_active.json', __dir__)
BYPASS_ACTIVE = File.exist?(BYPASS_FILE)

LOG_FILE = File.expand_path('../../.claude/sanetools.log', __dir__)

# === TOOL CLASSIFICATION ===

EDIT_TOOLS = %w[Edit Write NotebookEdit].freeze
RESEARCH_TOOLS = %w[Read Grep Glob WebSearch WebFetch Task].freeze
MEMORY_TOOLS = %w[mcp__memory__read_graph mcp__memory__search_nodes].freeze

# === INTELLIGENCE: Bootstrap Whitelist ===
# These tools ALWAYS allowed to prevent circular blocking
# CRITICAL: Categorize by DAMAGE POTENTIAL, not by name!
BOOTSTRAP_TOOL_PATTERN = Regexp.union(
  /^mcp__memory__read_graph$/,
  /^mcp__memory__search_nodes$/,
  /^mcp__memory__open_nodes$/,
  /^Read$/,
  /^Grep$/,
  /^Glob$/,
  /^WebSearch$/,
  /^WebFetch$/,
  /^mcp__apple-docs__/,
  /^mcp__context7__/,
  /^mcp__github__search_/,
  /^mcp__github__get_/,
  /^mcp__github__list_/,
  /^Task$/
).freeze

# === MUTATION PATTERNS (require research) ===

GLOBAL_MUTATION_PATTERN = Regexp.union(
  /^mcp__memory__delete_/,
  /^mcp__memory__create_/,
  /^mcp__memory__add_/
).freeze

EXTERNAL_MUTATION_PATTERN = Regexp.union(
  /^mcp__github__create_/,
  /^mcp__github__push_/,
  /^mcp__github__update_/,
  /^mcp__github__merge_/,
  /^mcp__github__fork_/,
  /^mcp__github__add_/
).freeze

# === INTELLIGENCE: Requirement Satisfaction ===
REQUIREMENT_SATISFACTION = {
  'saneloop' => {
    satisfied_by: [/saneloop/i, /start.*loop/i],
    requires_tool: 'Task'
  },
  'commit' => {
    satisfied_by: [/git commit/i],
    requires_tool: 'Bash'
  },
  'plan' => {
    satisfied_by: [/plan/i, /approach/i, /strategy/i],
    output_pattern: true
  },
  'research' => {
    satisfied_by: [:all_research_complete]
  }
}.freeze

# === BYPASS DETECTION ===

BASH_FILE_WRITE_PATTERN = Regexp.union(
  # Output redirection
  />\s*[^&]/,
  />>/,
  # In-place editing
  /\bsed\s+-i/,
  # Pipe to file
  /\btee\b/,
  # Direct disk write
  /\bdd\b.*\bof=/,
  # Heredoc
  /<<[A-Z_]+/,
  # Cat redirect
  /\bcat\b.*>/,
  # File copy (M8 addition)
  /\bcp\s+/,
  # Download to file (M8 addition)
  /\bcurl\b.*-[oO]/,
  /\bwget\b.*-O/,
  # Patch application (M8 addition)
  /\bgit\s+apply\b/,
  # Bulk file operations (M8 addition)
  /\bxargs\b.*\b(touch|rm|mv|cp)\b/,
  # Move/overwrite (M8 addition)
  /\bmv\s+/
).freeze

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

# === HELPER FUNCTIONS ===

def is_bootstrap_tool?(tool_name)
  tool_name.match?(BOOTSTRAP_TOOL_PATTERN)
end

def research_complete?(research)
  RESEARCH_CATEGORIES.keys.all? { |cat| research[cat] }
end

def research_missing(research)
  RESEARCH_CATEGORIES.keys.reject { |cat| research[cat] }
end

# === RESEARCH TRACKING ===

def track_research(tool_name, tool_input)
  research_done = false

  RESEARCH_CATEGORIES.each do |category, config|
    if config[:tools].any? { |t| tool_name.start_with?(t.sub('*', '')) }
      mark_research_done(category, tool_name, false)
      research_done = true
    end
  end

  if tool_name == 'Task'
    prompt = tool_input['prompt'] || tool_input[:prompt] || ''
    RESEARCH_CATEGORIES.each do |category, config|
      if config[:task_patterns].any? { |p| prompt.match?(p) }
        mark_research_done(category, 'Task', true)
        research_done = true
      end
    end
  end

  # Reset edit attempt counter ONLY when:
  # 1. We just did research (research_done is true), AND
  # 2. ALL 5 categories are now complete
  # Not just one tool - the FULL investigation (all 5 categories)
  # This is the SaneLoop process - it ALWAYS pays off
  if research_done
    research = StateManager.get(:research)
    all_complete = RESEARCH_CATEGORIES.keys.all? { |cat| research[cat] }
    if all_complete
      SaneToolsChecks.reset_edit_attempts
      SaneToolsChecks.reward_correct_behavior(:research_done)
    end
  end
end

def mark_research_done(category, tool, via_task)
  current = StateManager.get(:research, category)
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

def mark_requirement_satisfied(requirement)
  StateManager.update(:requirements) do |reqs|
    reqs[:satisfied] ||= []
    reqs[:satisfied] << requirement unless reqs[:satisfied].include?(requirement)
    reqs
  end
end

def track_requirement_satisfaction(tool_name, tool_input)
  reqs = StateManager.get(:requirements)
  requested = reqs[:requested] || []
  return if requested.empty?

  requested.each do |req|
    config = REQUIREMENT_SATISFACTION[req]
    next unless config
    next if config[:requires_tool] && tool_name != config[:requires_tool]

    input_text = [
      tool_input['command'],
      tool_input['prompt'],
      tool_input[:command],
      tool_input[:prompt]
    ].compact.join(' ')

    if config[:satisfied_by].is_a?(Array) && config[:satisfied_by].first != :all_research_complete
      if config[:satisfied_by].any? { |p| input_text.match?(p) }
        mark_requirement_satisfied(req)
      end
    end
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

  # Track violations in StateManager for SOP scoring
  track_violation(tool_name, reason) if blocked && reason
rescue StandardError
  # Don't fail on logging errors
end

def track_violation(tool_name, reason)
  rule = detect_rule_from_reason(reason)
  StateManager.update(:enforcement) do |e|
    e[:blocks] ||= []
    e[:blocks] << {
      tool: tool_name,
      rule: rule,
      reason: reason.lines.first&.strip,
      timestamp: Time.now.iso8601
    }
    e[:blocks] = e[:blocks].last(50)
    e
  end
rescue StandardError
  # Don't fail on tracking errors
end

def detect_rule_from_reason(reason)
  case reason
  when /Rule #1|BLOCKED PATH|STAY IN YOUR LANE/i then 'Rule #1'
  when /Rule #2|RESEARCH.*INCOMPLETE|VERIFY/i then 'Rule #2'
  when /Rule #3|CIRCUIT BREAKER/i then 'Rule #3'
  when /Rule #10|FILE SIZE|lines.*limit/i then 'Rule #10'
  when /TABLE BLOCKED/i then 'no_tables'
  when /BASH.*WRITE|STATE.*BYPASS/i then 'bypass_attempt'
  when /SUBAGENT.*BLOCKED/i then 'subagent_bypass'
  when /MUTATION.*BLOCKED/i then 'mutation_blocked'
  when /REQUIREMENTS NOT MET/i then 'requirements'
  when /SANELOOP REQUIRED/i then 'saneloop_required'
  else 'unknown'
  end
end

def output_block(reason, tool_name = nil)
  warn '---'
  warn 'SANETOOLS BLOCKED'
  warn ''
  warn reason

  # Check for refusal to read (repeated same block)
  if tool_name && (escalation = SaneToolsChecks.check_refusal_to_read(tool_name, reason))
    warn ''
    warn escalation
  end

  warn '---'
end

# === MAIN ENFORCEMENT ===

def process_tool(tool_name, tool_input)
  # === BYPASS MODE: Still track, but do not block ===
  if BYPASS_ACTIVE
    track_research(tool_name, tool_input)
    track_requirement_satisfaction(tool_name, tool_input)
    log_action(tool_name, false)
    return 0
  end

  is_bootstrap = is_bootstrap_tool?(tool_name)

  # Always check blocked paths first (pass tool_name to allow reads of state files)
  if (reason = SaneToolsChecks.check_blocked_path(tool_input, tool_name, EDIT_TOOLS))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Bootstrap tools skip most checks
  if is_bootstrap
    track_research(tool_name, tool_input)
    track_requirement_satisfaction(tool_name, tool_input)
    log_action(tool_name, false)
    return 0
  end

  # Check circuit breaker
  if (reason = SaneToolsChecks.check_circuit_breaker)
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # PREFLIGHT: Check pending MCP actions (memory staging, etc.)
  if (reason = SaneToolsChecks.check_pending_mcp_actions(tool_name, EDIT_TOOLS))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check research-only mode
  if (reason = SaneToolsChecks.check_research_only_mode(tool_name, EDIT_TOOLS, GLOBAL_MUTATION_PATTERN, EXTERNAL_MUTATION_PATTERN))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check if enforcement is halted
  SaneToolsChecks.check_enforcement_halted

  # Track research progress BEFORE checking requirements
  track_research(tool_name, tool_input)
  track_requirement_satisfaction(tool_name, tool_input)

  # Check bash bypass
  if (reason = SaneToolsChecks.check_bash_bypass(tool_name, tool_input, BASH_FILE_WRITE_PATTERN))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check subagent bypass
  if (reason = SaneToolsChecks.check_subagent_bypass(tool_name, tool_input, EDIT_KEYWORDS, RESEARCH_CATEGORIES))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check research before edit
  if (reason = SaneToolsChecks.check_research_before_edit(tool_name, EDIT_TOOLS, RESEARCH_CATEGORIES))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check SaneLoop required for big tasks
  if (reason = SaneToolsChecks.check_saneloop_required(tool_name, EDIT_TOOLS))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check file size (Rule #10)
  if (reason = SaneToolsChecks.check_file_size(tool_name, tool_input, EDIT_TOOLS))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check table ban
  if (reason = SaneToolsChecks.check_table_ban(tool_name, tool_input, EDIT_TOOLS))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check global mutations
  if (reason = SaneToolsChecks.check_global_mutations(tool_name, GLOBAL_MUTATION_PATTERN, RESEARCH_CATEGORIES))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check external mutations
  if (reason = SaneToolsChecks.check_external_mutations(tool_name, EXTERNAL_MUTATION_PATTERN, RESEARCH_CATEGORIES))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check requirements
  if (reason = SaneToolsChecks.check_requirements(tool_name, BOOTSTRAP_TOOL_PATTERN, EDIT_TOOLS, RESEARCH_CATEGORIES))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check edit attempt limit (prevents "no big deal" syndrome)
  # 3 edit attempts without research = forced pause
  if (reason = SaneToolsChecks.check_edit_attempt_limit(tool_name, EDIT_TOOLS))
    log_action(tool_name, true, reason)
    output_block(reason, tool_name)
    return 2
  end

  # Check for gaming patterns (non-blocking, logs for future detection)
  SaneToolsChecks.check_gaming_patterns(tool_name, EDIT_TOOLS, RESEARCH_CATEGORIES)

  # Check README on commit (non-blocking reminder)
  SaneToolsChecks.check_readme_on_commit(tool_name, tool_input)

  # All checks passed
  log_action(tool_name, false)
  0
end

# === CLI UTILITIES ===

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
  require_relative 'sanetools_test'
  exit SaneToolsTest.run(method(:process_tool), RESEARCH_CATEGORIES)
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
