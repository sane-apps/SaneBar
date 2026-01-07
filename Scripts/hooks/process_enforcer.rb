#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Process Enforcer Hook
# ==============================================================================
# BLOCKS tool calls when Claude tries to bypass required processes.
# This is the "no shortcuts" enforcement layer.
#
# Enforces:
# 1. SaneLoop started when user requested it
# 2. Research done before using unfamiliar APIs
# 3. Plan shown for approval before implementation
# 4. Proper commit workflow (not just "git commit")
# 5. Bug logging to memory (not just mentioned)
# 6. Proper session summary format (not casual self-rating)
# 7. Verify cycle run before claiming "done"
#
# Hook Type: PreToolUse (Edit, Write, Bash)
# Exit 0 = Allow, Exit 1 = BLOCK
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'state_signer'
require_relative 'shortcut_detectors'
require_relative 'phase_manager'

include ShortcutDetectors

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
REQUIREMENTS_FILE = File.join(PROJECT_DIR, '.claude/prompt_requirements.json')
SANELOOP_STATE_FILE = File.join(PROJECT_DIR, '.claude/saneloop-state.json')
SATISFACTION_FILE = File.join(PROJECT_DIR, '.claude/process_satisfaction.json')
ENFORCEMENT_LOG = File.join(PROJECT_DIR, '.claude/enforcement_log.jsonl')
MEMORY_CHECK_FILE = File.join(PROJECT_DIR, '.claude/memory_checked.json')
RESEARCH_PROGRESS_FILE = File.join(PROJECT_DIR, '.claude/research_progress.json')
HYPOTHESIS_FILE = File.join(PROJECT_DIR, '.claude/research_hypotheses.json')
READ_HISTORY_FILE = File.join(PROJECT_DIR, '.claude/read_history.json')
EDIT_STATE_FILE = File.join(PROJECT_DIR, '.claude/edit_state.json')
SUMMARY_VALIDATED_FILE = File.join(PROJECT_DIR, '.claude/summary_validated.json')
ENFORCEMENT_BREAKER_FILE = File.join(PROJECT_DIR, '.claude/enforcement_breaker.json')


# Enforcement breaker: After N identical blocks, stop blocking and alert user
ENFORCEMENT_BREAKER_THRESHOLD = 5

# Session summary required after this many edits
SUMMARY_REQUIRED_AFTER_EDITS = 25

# Significant task threshold - require plan/SaneLoop after this many unique files
SIGNIFICANT_TASK_THRESHOLD = 3

# 5 mandatory research categories - ALL must be satisfied via TASK AGENTS
# ENFORCEMENT: Individual tool calls don't count. Must spawn Task agents.
# This prevents gaming by calling tools that fail or only searching our own repo.
# FIX: Use regex patterns with word boundaries (\b) to avoid false positives
RESEARCH_CATEGORIES = {
  memory: {
    name: 'Memory',
    patterns: [/\bmemory\b/i, /\bknowledge.?graph\b/i, /\bpast.?bugs\b/i, /\bmcp__memory\b/i],
    desc: 'Check past bugs/patterns via Task agent'
  },
  docs: {
    name: 'API Docs',
    patterns: [/\bdocumentation\b/i, /\bapi.?docs\b/i, /\bapple-docs\b/i, /\bcontext7\b/i, /\bsdk\b/i],
    desc: 'Verify APIs exist via Task agent'
  },
  web: {
    name: 'Web Search',
    patterns: [/\bweb.?search\b/i, /\bgoogle\b/i, /\bstackoverflow\b/i, /\bwebsearch\b/i],
    desc: 'Find patterns/solutions via Task agent'
  },
  local: {
    name: 'Local Codebase',
    patterns: [/\blocal.?code/i, /\bcodebase\b/i, /\bexisting.?code\b/i, /\bproject.?files\b/i],
    desc: 'Understand existing code via Task agent'
  },
  github: {
    name: 'External GitHub',
    patterns: [/\bgithub\b/i, /\bexternal.?repo/i, /\bopen.?source\b/i, /\bmcp__github\b/i],
    desc: 'Learn from community projects (NOT our repo) via Task agent',
    exclude_patterns: [/stephanjoseph/i, /saneprocess/i] # Our repo doesn't count!
  }
}.freeze

# Early exit if bypass mode is active

# ═══════════════════════════════════════════════════════════════════════════════
# C1 FIX: BLOCKED READ PATHS - Sensitive files Claude must NEVER read
# ═══════════════════════════════════════════════════════════════════════════════

BLOCKED_READ_PATHS = [
  File.expand_path('~/.claude_hook_secret'),     # HMAC signing secret - would allow forgery
  File.expand_path('~/.claude/.hook_secret'),    # Alternate location
  File.expand_path('~/.ssh'),                    # SSH keys
  File.expand_path('~/.aws/credentials'),        # AWS credentials
  File.expand_path('~/.netrc'),                  # Network credentials
].freeze

def check_blocked_read_path(file_path)
  return false if file_path.nil? || file_path.empty?

  normalized = File.expand_path(file_path)
  BLOCKED_READ_PATHS.any? do |blocked|
    normalized == blocked || normalized.start_with?("#{blocked}/")
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# SATISFACTION CHECKS - How to verify each requirement is met
# ═══════════════════════════════════════════════════════════════════════════════

def saneloop_active?
  return false unless File.exist?(SANELOOP_STATE_FILE)

  state = JSON.parse(File.read(SANELOOP_STATE_FILE), symbolize_names: true)
  state[:active] == true
rescue StandardError
  false
end

def load_satisfaction
  # VULN-003 FIX: Use signed state files
  data = StateSigner.read_verified(SATISFACTION_FILE)
  return {} if data.nil?

  # Symbolize keys for compatibility
  data.transform_keys(&:to_sym).transform_values do |v|
    v.is_a?(Hash) ? v.transform_keys(&:to_sym) : v
  end
rescue StandardError
  {}
end

def save_satisfaction(sat)
  # VULN-003 FIX: Sign state files to prevent tampering
  string_sat = sat.transform_keys(&:to_s).transform_values do |v|
    v.is_a?(Hash) ? v.transform_keys(&:to_s) : v
  end
  StateSigner.write_signed(SATISFACTION_FILE, string_sat)
end

def mark_satisfied(requirement)
  sat = load_satisfaction
  sat[requirement.to_sym] = { satisfied_at: Time.now.iso8601 }
  save_satisfaction(sat)
end

def is_satisfied?(requirement)
  sat = load_satisfaction
  sat[requirement.to_sym] && sat[requirement.to_sym][:satisfied_at]
end

# Research progress tracking - 5 mandatory categories
def load_research_progress
  # VULN-003 FIX: Use signed state files
  data = StateSigner.read_verified(RESEARCH_PROGRESS_FILE)
  return {} if data.nil?

  # Symbolize keys for compatibility
  data.transform_keys(&:to_sym).transform_values do |v|
    v.is_a?(Hash) ? v.transform_keys(&:to_sym) : v
  end
rescue StandardError
  {}
end

def save_research_progress(progress)
  # VULN-003 FIX: Sign state files to prevent tampering
  string_progress = progress.transform_keys(&:to_s).transform_values do |v|
    v.is_a?(Hash) ? v.transform_keys(&:to_s) : v
  end
  StateSigner.write_signed(RESEARCH_PROGRESS_FILE, string_progress)
end

def mark_research_category(category, tool_name, prompt = nil)
  progress = load_research_progress
  progress[category] ||= { completed_at: nil, tool: nil, skipped: false, skip_reason: nil }

  # BUG FIX: Allow Task agents to upgrade existing entries to via_task=true
  # Previously, if a category was marked by direct tool call (via_task=false),
  # a later Task agent couldn't update it, causing permanent block.
  already_done_via_task = progress[category][:completed_at] && progress[category][:via_task]
  if already_done_via_task
    return # Already done via Task - no upgrade needed
  end

  # Either new entry OR upgrading non-Task entry to Task entry
  progress[category][:completed_at] = Time.now.iso8601
  progress[category][:tool] = tool_name
  progress[category][:prompt] = prompt&.slice(0, 200) if prompt # Store truncated prompt as proof
  progress[category][:via_task] = (tool_name == 'Task') # Track if done via Task agent
  save_research_progress(progress)
end

# Detect which research category a Task prompt belongs to (if any)
# Uses regex patterns with word boundaries to avoid false positives
def research_category_for_task_prompt(prompt, description = nil)
  combined = [prompt, description].compact.join(' ')
  return nil if combined.empty?

  RESEARCH_CATEGORIES.each do |cat, config|
    patterns = config[:patterns] || []
    exclude_patterns = config[:exclude_patterns] || []

    # Check if any pattern matches
    has_match = patterns.any? { |pat| combined.match?(pat) }

    # Check if excluded (e.g., searching our own repo doesn't count for GitHub)
    is_excluded = exclude_patterns.any? { |pat| combined.match?(pat) }

    # Special case for GitHub: must NOT be searching our own repo
    if cat == :github && is_excluded
      warn "   ⚠️  GitHub research must be EXTERNAL (not our repo)"
      next
    end

    return cat if has_match
  end

  nil
end

# Check if research was done via Task agents (not individual tool calls)
def research_done_via_tasks?
  progress = load_research_progress
  return false if progress.empty?

  # All 5 categories must be completed via Task agents
  RESEARCH_CATEGORIES.keys.all? do |cat|
    cat_progress = progress[cat]
    cat_progress && cat_progress[:completed_at] && cat_progress[:via_task]
  end
end

# Legacy function for non-Task tools (kept for backward compatibility / logging only)
def research_category_for_tool(tool_name)
  # NOTE: Individual tool calls no longer count toward research satisfaction
  # This is kept only for logging/tracking purposes
  tool_to_category = {
    'mcp__memory__read_graph' => :memory,
    'WebSearch' => :web,
    'WebFetch' => :web,
    'Read' => :local,
    'Grep' => :local,
    'Glob' => :local
  }

  return tool_to_category[tool_name] if tool_to_category.key?(tool_name)

  # MCP tools
  return :docs if tool_name.start_with?('mcp__apple-docs__') || tool_name.start_with?('mcp__context7__')
  return :github if tool_name.start_with?('mcp__github__')

  nil
end

def research_status
  progress = load_research_progress
  done = []
  missing = []

  RESEARCH_CATEGORIES.each do |cat, config|
    if progress[cat] && (progress[cat][:completed_at] || progress[cat][:skipped])
      done << cat
    else
      missing << cat
    end
  end

  { done: done, missing: missing, all_done: missing.empty? }
end

def log_enforcement(action, details)
  FileUtils.mkdir_p(File.dirname(ENFORCEMENT_LOG))
  entry = {
    timestamp: Time.now.iso8601,
    action: action,
    details: details
  }
  File.open(ENFORCEMENT_LOG, 'a') { |f| f.puts entry.to_json }
end

def load_requirements
  return { requested: [], satisfied: [], modifiers: [] } unless File.exist?(REQUIREMENTS_FILE)

  JSON.parse(File.read(REQUIREMENTS_FILE), symbolize_names: true)
rescue StandardError
  { requested: [], satisfied: [], modifiers: [] }
end

# Check if session summary is required (based on edit count)
def session_summary_required?
  return false unless File.exist?(EDIT_STATE_FILE)

  edit_state = JSON.parse(File.read(EDIT_STATE_FILE), symbolize_names: true)
  edit_count = edit_state[:edit_count] || 0

  # Check if summary was validated after the edit count threshold
  if File.exist?(SUMMARY_VALIDATED_FILE)
    summary_data = JSON.parse(File.read(SUMMARY_VALIDATED_FILE), symbolize_names: true)
    validated_at = Time.parse(summary_data[:validated_at]) rescue nil
    edit_state_updated = Time.parse(edit_state[:updated] || edit_state['updated']) rescue nil

    # If summary was validated AFTER current edit state started, we're good
    return false if validated_at && edit_state_updated && validated_at > edit_state_updated
  end

  # Require summary after threshold
  edit_count >= SUMMARY_REQUIRED_AFTER_EDITS
rescue StandardError
  false
end

def edits_since_summary
  return 0 unless File.exist?(EDIT_STATE_FILE)

  edit_state = JSON.parse(File.read(EDIT_STATE_FILE), symbolize_names: true)
  edit_state[:edit_count] || 0
rescue StandardError
  0
end

def unique_files_edited
  return 0 unless File.exist?(EDIT_STATE_FILE)

  edit_state = JSON.parse(File.read(EDIT_STATE_FILE), symbolize_names: true)
  files = edit_state[:unique_files] || edit_state['unique_files'] || []
  files.length
rescue StandardError
  0
end

def significant_task_detected?
  # Returns true if 3+ unique files edited without plan/saneloop already active
  unique_files_edited >= SIGNIFICANT_TASK_THRESHOLD
end

# ═══════════════════════════════════════════════════════════════════════════════
# SHORTCUT DETECTION - Moved to shortcut_detectors.rb module
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN ENFORCEMENT LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

# BYPASS CHECK: If user enabled bypass (b+), skip all enforcement

tool_name = input['tool_name'] || ''
tool_input = input['tool_input'] || {}

# ═══════════════════════════════════════════════════════════════════════════════
# C1 FIX: Block Read access to sensitive paths (secret key, SSH, credentials)
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Read'
  file_path = tool_input['file_path'] || ''
  if check_blocked_read_path(file_path)
    # Check for one-time skip BEFORE blocking

    warn ''
    warn '🔴 BLOCKED: Read access to sensitive file denied'
    warn "   File: #{file_path}"
    warn '   This file contains secrets that could compromise hook security.'
    warn ''
    exit 2
  end
end

# Get the content being written/edited
content = tool_input['new_string'] || tool_input['content'] || tool_input['command'] || ''
file_path = tool_input['file_path'] || ''

# Load requirements set by prompt_analyzer
reqs = load_requirements
requested = reqs[:requested] || []

blocks = []

# ═══════════════════════════════════════════════════════════════════════════════
# BOOTSTRAP FIX: Never block commands needed to SATISFY requirements
# ═══════════════════════════════════════════════════════════════════════════════

# These commands are ALWAYS allowed because they satisfy requirements:
is_bootstrap_command = false

if tool_name == 'Bash'
  bootstrap_patterns = [
    /saneloop\s+start/i,           # Starts a saneloop
    /SaneMaster\.rb\s+saneloop/i,  # SaneMaster saneloop commands
    /SaneMaster\.rb\s+verify/i,    # Verification commands
    /qa\.rb/i,                     # QA verification
  ]
  is_bootstrap_command = bootstrap_patterns.any? { |p| content.match?(p) }
end

# Research tools are NEVER blocked - you can ALWAYS investigate
is_research_tool = %w[Read Grep Glob WebFetch WebSearch].include?(tool_name) ||
                   tool_name.start_with?('mcp__')

# Task tool needs special handling - it's research UNLESS used for editing
# CRITICAL: Task agents are the PRIMARY way to satisfy research requirements
if tool_name == 'Task'
  task_prompt = tool_input['prompt'] || ''
  edit_keywords = %w[edit write create modify change update add append remove delete fix patch]
  is_edit_task = edit_keywords.any? { |kw| task_prompt.downcase.include?(kw) }
  is_research_tool = !is_edit_task  # Only research if NOT editing

  # Track research Task calls by category
  unless is_edit_task
    task_desc = tool_input['description'] || ''
    category = research_category_for_task_prompt(task_prompt, task_desc)
    if category
      mark_research_category(category, 'Task', task_prompt)
      warn "📊 Task research: #{RESEARCH_CATEGORIES[category][:name]} category tracked"
    end
  end
end

# Read-only Bash commands are also research
if tool_name == 'Bash'
  readonly_patterns = [
    /^\s*ls\b/,                    # List files
    /^\s*cat\s/,                   # Read files
    /^\s*head\b/,                  # Read file start
    /^\s*tail\b/,                  # Read file end
    /^\s*wc\b/,                    # Word count
    /^\s*find\b/,                  # Find files
    /^\s*grep\b/,                  # Search content
    /^\s*rg\b/,                    # Ripgrep
    /^\s*which\b/,                 # Find command
    /^\s*pwd\b/,                   # Current directory
    /^\s*git\s+(status|log|diff|show|branch)/i,  # Read-only git
    /^\s*ruby\s+-c\b/,             # Syntax check
  ]
  is_research_tool = true if readonly_patterns.any? { |p| content.match?(p) }
end

# Skip ALL enforcement for bootstrap commands - they're how you GET compliant
if is_bootstrap_command
  exit 0
end

# CRITICAL: Skip enforcement for research UNLESS SaneLoop is required but not active
# BIG TASK FIX: If prompt requires SaneLoop, block even research Task agents until started
if is_research_tool
  # Check if SaneLoop is required but not active
  is_big = reqs[:is_big_task] || PhaseManager.active?
  is_simple = reqs[:is_task] && !is_big
  needs_saneloop = requested.include?('saneloop') || is_big || is_simple
  
  if needs_saneloop
    unless saneloop_active?
      # Block TASK agents (not individual research tools - those are fine)
      if tool_name == 'Task'
        warn ''
        if PhaseManager.active?
          phase = PhaseManager.current_phase
          warn "🛑 BLOCKED: Phase #{phase[:name]} needs SaneLoop"
          warn "   #{PhaseManager.status}"
          warn "   Fix: ./Scripts/SaneMaster.rb saneloop start \"Phase: #{phase[:name]}\""
        elsif is_big
          warn '🛑 BLOCKED: Big task needs phased SaneLoops'
          warn '   This is a multi-phase task. Start Phase 1 first.'
          warn '   Fix: ./Scripts/SaneMaster.rb saneloop start "Phase 1: Research"'
        else
          warn '🛑 BLOCKED: Task needs SaneLoop'
          warn '   Even simple tasks need a SaneLoop for structure.'
          warn '   Fix: ./Scripts/SaneMaster.rb saneloop start "your task"'
        end
        warn ''
        exit 2

      end
    end
  end
  # Track memory check - mandatory before project work
  if tool_name == 'mcp__memory__read_graph'
    FileUtils.mkdir_p(File.dirname(MEMORY_CHECK_FILE))
    File.write(MEMORY_CHECK_FILE, { checked_at: Time.now.iso8601 }.to_json)
  end

  # NOTE: Individual tool calls are logged but do NOT satisfy research requirements
  # Only Task agents satisfy research (prevents gaming with failed calls or own-repo searches)
  # The Task tool handler (above) tracks research Task calls with mark_research_category()

  # Show progress for informational purposes only
  if tool_name == 'Task'
    status = research_status
    if research_done_via_tasks?
      mark_satisfied(:research)
      warn '✅ All 5 Task agents complete - research satisfied'
    elsif status[:done].any?
      done_via_task = status[:done].count { |cat| load_research_progress.dig(cat, :via_task) }
      remaining = status[:missing].map { |c| RESEARCH_CATEGORIES[c][:name] }.join(', ')
      warn "📊 Research: #{done_via_task}/5 Task agents | Missing: #{remaining}"
    end
  end

  exit 0
end

# MEMORY CHECK: Warn if Edit/Write without checking memory first
if %w[Edit Write].include?(tool_name) && !File.exist?(MEMORY_CHECK_FILE)
  warn ''
  warn '⚠️  MEMORY NOT CHECKED - Run mcp__memory__read_graph first'
  warn '   Past bugs often repeat. Check memory before project work.'
  warn ''
  # Warn only, don't block (yet)
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 1: SaneLoop Required
# ═══════════════════════════════════════════════════════════════════════════════

if requested.include?('saneloop') && !saneloop_active?
  blocks << {
    rule: 'SANELOOP_REQUIRED',
    message: 'User requested SaneLoop but none is active.',
    fix: 'Run: ./Scripts/SaneMaster.rb saneloop start "task" --criteria "..." --promise "..."'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 1.2: SIGNIFICANT TASK DETECTION (3+ unique files = needs plan/SaneLoop)
# ═══════════════════════════════════════════════════════════════════════════════

# Auto-detect significant multi-file work that should have been planned
if %w[Edit Write].include?(tool_name)
  if significant_task_detected? && !saneloop_active? && !is_satisfied?(:plan)
    file_count = unique_files_edited
    blocks << {
      rule: 'SIGNIFICANT_TASK_DETECTED',
      message: "#{file_count} unique files edited without plan or SaneLoop. This is significant work.",
      fix: 'Either: 1) Show a plan for user approval, OR 2) Start SaneLoop with: ./Scripts/SaneMaster.rb saneloop start "task"'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 1.5: VULN-003 FIX - Subagent Bypass Detection
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Task'
  # Check if spawning an editing subagent to bypass enforcement
  task_prompt = tool_input['prompt'] || ''
  edit_keywords = %w[edit write create modify change update add append remove delete fix patch]

  is_edit_task = edit_keywords.any? { |kw| task_prompt.downcase.include?(kw) }

  # Only block if there are unsatisfied requirements
  has_blocking_requirements = (
    (requested.include?('saneloop') && !saneloop_active?) ||
    (requested.include?('plan') && !is_satisfied?(:plan))
  )

  if is_edit_task && has_blocking_requirements
    blocks << {
      rule: 'SUBAGENT_BYPASS',
      message: 'Nice try! Spawning a subagent to do your editing is still cheating.',
      fix: 'Complete the required process (saneloop, plan approval) before ANY code changes.'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 2: Research Required Before Implementation (5 MANDATORY TASK AGENTS)
# ENFORCEMENT: Must spawn 5 Task agents for research - individual tool calls don't count
# This prevents gaming by calling tools that fail or only searching our own repo
# ═══════════════════════════════════════════════════════════════════════════════

# Research is mandatory for Edit/Write unless already satisfied
research_required = %w[Edit Write].include?(tool_name) && !is_satisfied?(:research)

if research_required
  # Check if research was done via Task agents (the only valid way now)
  if research_done_via_tasks?
    mark_satisfied(:research)
    warn '✅ Research: All 5 Task agents complete - research satisfied'
  else
    status = research_status
    done_via_task = status[:done].count { |cat| load_research_progress.dig(cat, :via_task) }
    missing_names = status[:missing].map { |c| RESEARCH_CATEGORIES[c][:name] }
    not_via_task = status[:done].reject { |cat| load_research_progress.dig(cat, :via_task) }

    # Build the fix message
    fix_parts = []
    fix_parts << "Spawn 5 Task agents in parallel for research" if done_via_task < 5
    fix_parts << "Missing: #{missing_names.join(', ')}" if missing_names.any?
    if not_via_task.any?
      fix_parts << "NOT via Task: #{not_via_task.map { |c| RESEARCH_CATEGORIES[c][:name] }.join(', ')}"
    end

    blocks << {
      rule: 'RESEARCH_FIRST_VIA_TASKS',
      message: "#{done_via_task}/5 research Task agents complete. Must use Task agents, not individual tools.",
      fix: fix_parts.join('. ') + ". Example: Task(subagent_type='general-purpose', prompt='Search memory for...')"
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 3: Plan Approval Required
# ═══════════════════════════════════════════════════════════════════════════════

if requested.include?('plan') && !is_satisfied?(:plan)
  # Block Edit/Write until plan is shown and approved
  if %w[Edit Write].include?(tool_name)
    blocks << {
      rule: 'PLAN_APPROVAL_REQUIRED',
      message: 'User requested a plan before implementation.',
      fix: 'Show the plan in plain english for user approval first. Do NOT just reference a file.'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 4: Casual Self-Rating Detection
# ═══════════════════════════════════════════════════════════════════════════════

if %w[Edit Write].include?(tool_name) && detect_casual_self_rating(content)
  blocks << {
    rule: 'PROPER_RATING_FORMAT',
    message: 'Detected casual self-rating without proper format.',
    fix: 'Use: SOP Compliance: X/10 (auto from compliance report) + Performance: X/10 (with gaps)'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 5: Lazy Commit Detection
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Bash' && detect_lazy_commit(content)
  blocks << {
    rule: 'FULL_COMMIT_WORKFLOW',
    message: 'Detected simple "git commit" without full workflow.',
    fix: 'Full workflow: git pull → status → diff → add → commit (with README update if needed)'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 5.5: VULN-002 FIX - Bash File Write Bypass Detection
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Bash' && detect_bash_file_write(content)
  # Only block if there are unsatisfied requirements that would block Edit/Write
  has_blocking_requirements = (
    (requested.include?('saneloop') && !saneloop_active?) ||
    (requested.include?('plan') && !is_satisfied?(:plan)) ||
    (requested.include?('research') && !is_satisfied?(:research))
  )

  if has_blocking_requirements
    blocks << {
      rule: 'BASH_FILE_WRITE_BYPASS',
      message: 'Detected Bash command that writes to files. Nice try!',
      fix: 'You cannot bypass Edit/Write restrictions with echo/sed/cat. Complete the required process first.'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 5.6: VULN-004 FIX - Bash Table Bypass Detection
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Bash' && detect_bash_table_bypass(content)
  blocks << {
    rule: 'BASH_TABLE_BYPASS',
    message: 'Detected markdown table in sed/echo command. Tables are banned.',
    fix: 'Tables render terribly in terminal. Use plain lists instead. No bypassing with sed!'
  }
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 5.7: VULN-005 FIX - Bash File Size Bypass Detection
# ═══════════════════════════════════════════════════════════════════════════════

if tool_name == 'Bash'
  size_violation = detect_bash_size_bypass(content)
  if size_violation
    blocks << {
      rule: 'BASH_SIZE_BYPASS',
      message: "sed target #{size_violation[:file]} is #{size_violation[:lines]} lines (limit: #{size_violation[:limit]}). Nice try!",
      fix: 'Cannot bypass file size limits with sed. Split the file first.'
    }
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 6: Bug Note Must Update Memory
# ═══════════════════════════════════════════════════════════════════════════════

if requested.include?('bug_note') && !is_satisfied?(:bug_note)
  # If not using memory MCP, block
  unless tool_name.start_with?('mcp__memory')
    # Allow research tools, but block implementation until memory is updated
    if %w[Edit Write Bash].include?(tool_name)
      blocks << {
        rule: 'BUG_TO_MEMORY',
        message: 'Bug note requested but memory not updated.',
        fix: 'Use mcp__memory__create_entities or mcp__memory__add_observations to log the bug pattern.'
      }
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 7: Verify Before Done
# ═══════════════════════════════════════════════════════════════════════════════

if requested.include?('verify') && !is_satisfied?(:verify)
  # Check if claiming done without verification
  if %w[Edit Write].include?(tool_name) && content.match?(/\b(done|complete|finished)\b/i)
    # Check recent audit log for verify/qa.rb
    verified_recently = false
    if File.exist?('.claude/audit.jsonl')
      recent = File.readlines('.claude/audit.jsonl').last(20).join
      verified_recently = recent.include?('verify') || recent.include?('qa.rb')
    end

    unless verified_recently
      blocks << {
        rule: 'VERIFY_BEFORE_DONE',
        message: 'Claiming "done" but verification not run.',
        fix: 'Run: ./Scripts/SaneMaster.rb verify (or ruby scripts/qa.rb) before claiming done.'
      }
    end
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK 8: Session Summary Required After 25+ Edits
# ═══════════════════════════════════════════════════════════════════════════════

if session_summary_required? && %w[Edit Write].include?(tool_name)
  edit_count = edits_since_summary
  blocks << {
    rule: 'SESSION_SUMMARY_REQUIRED',
    message: "#{edit_count} edits without session summary. Time to wrap up and document.",
    fix: 'Write session summary to .claude/SESSION_HANDOFF.md with format: ## Session Summary, SOP Compliance: X/10, Performance: X/10'
  }
end


# ═══════════════════════════════════════════════════════════════════════════════
# ENFORCEMENT CIRCUIT BREAKER
# ═══════════════════════════════════════════════════════════════════════════════
# If the same block fires 5x consecutively, the hook itself is likely broken.
# Stop blocking, switch to warn-only, alert user to fix hooks or enable bypass.

def load_enforcement_breaker
  return { blocks: [], halted: false } unless File.exist?(ENFORCEMENT_BREAKER_FILE)
  JSON.parse(File.read(ENFORCEMENT_BREAKER_FILE), symbolize_names: true)
rescue StandardError
  { blocks: [], halted: false }
end

def save_enforcement_breaker(state)
  FileUtils.mkdir_p(File.dirname(ENFORCEMENT_BREAKER_FILE))
  File.write(ENFORCEMENT_BREAKER_FILE, JSON.pretty_generate(state))
end

def enforcement_halted?
  state = load_enforcement_breaker
  state[:halted] == true
end

def check_enforcement_breaker(block_signature)
  state = load_enforcement_breaker
  
  # Already halted? Stay halted until user resets
  return :halted if state[:halted]
  
  # Add this block to history
  state[:blocks] ||= []
  state[:blocks] << { signature: block_signature, at: Time.now.iso8601 }
  
  # Keep only last 10 for analysis
  state[:blocks] = state[:blocks].last(10)
  
  # Check if last N blocks have same signature
  recent = state[:blocks].last(ENFORCEMENT_BREAKER_THRESHOLD)
  if recent.length >= ENFORCEMENT_BREAKER_THRESHOLD
    signatures = recent.map { |b| b[:signature] }
    if signatures.uniq.length == 1
      # Same block 5x in a row - HALT enforcement
      state[:halted] = true
      state[:halted_at] = Time.now.iso8601
      state[:halted_reason] = block_signature
      save_enforcement_breaker(state)
      return :tripped
    end
  end
  
  save_enforcement_breaker(state)
  :ok
end

def reset_enforcement_breaker
  state = { blocks: [], halted: false, reset_at: Time.now.iso8601 }
  save_enforcement_breaker(state)
end

def clear_enforcement_breaker_on_success
  # Called when a tool succeeds - reset consecutive block counter
  state = load_enforcement_breaker
  return if state[:halted] # Don't auto-reset if halted - user must explicitly reset
  state[:blocks] = [] # Clear block history on success
  save_enforcement_breaker(state)
end


# ═══════════════════════════════════════════════════════════════════════════════
# ENFORCEMENT OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

if blocks.any?
  # Check for one-time skip BEFORE blocking

  # Generate block signature for breaker tracking
  block_signature = blocks.map { |b| b[:rule] }.sort.join('|')
  breaker_status = check_enforcement_breaker(block_signature)
  
  case breaker_status
  when :halted
    # Enforcement already halted from previous session
    warn ''
    warn '⚠️  ENFORCEMENT HALTED (from previous loop)'
    warn '   Hooks blocked 5x consecutively - likely a hook bug, not Claude.'
    warn '   Options:'
    warn '   1. "bypass on" - disable all enforcement'
    warn '   2. Fix hooks in ~/SaneProcess/scripts/hooks/'
    warn '   3. "reset enforcement breaker" - try enforcement again'
    warn ''
    warn "   Would have blocked: #{block_signature}"
    warn ''
    exit 0 # WARN only, don't block
    
  when :tripped
    # Just tripped! Alert user dramatically
    warn ''
    warn '🚨 ENFORCEMENT CIRCUIT BREAKER TRIPPED!'
    warn ''
    warn '   The same block fired 5x consecutively.'
    warn '   This usually means the HOOK is broken, not Claude.'
    warn ''
    warn "   Repeated block: #{block_signature}"
    warn ''
    warn '   ENFORCEMENT IS NOW HALTED until you:'
    warn '   1. "bypass on" - disable all enforcement'
    warn '   2. Fix hooks in ~/SaneProcess/scripts/hooks/'
    warn '   3. "reset enforcement breaker" - try enforcement again'
    warn ''
    warn '   Allowing this tool call to proceed...'
    warn ''
    exit 0 # Allow this call, enforcement halted
    
  else
    # Normal blocking
    log_enforcement('BLOCKED', blocks.map { |b| b[:rule] })

    warn ''
    warn '🛑 BLOCKED'
    blocks.each do |b|
      warn "  ❌ #{b[:rule]}: #{b[:message]}"
      warn "     Fix: #{b[:fix]}"
    end
    warn ''

    exit 2 # Exit code 2 = BLOCK in Claude Code
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# AUTO-SATISFACTION DETECTION & POSITIVE FEEDBACK
# ═══════════════════════════════════════════════════════════════════════════════

satisfied_now = []

# NOTE: Research auto-satisfaction now tracked in early-exit block (lines 326-351)
# using 5 mandatory categories system. Old "3 operations" logic removed.

# If using memory MCP for bug, mark satisfied
if requested.include?('bug_note') && tool_name.start_with?('mcp__memory')
  mark_satisfied(:bug_note)
  satisfied_now << 'bug_note'
end

# ═══════════════════════════════════════════════════════════════════════════════
# POSITIVE FEEDBACK - Make compliance feel GOOD
# ═══════════════════════════════════════════════════════════════════════════════

if satisfied_now.any?
  warn "✅ #{satisfied_now.join(', ')} satisfied"
end

# Show progress toward full compliance
sat = load_satisfaction
satisfied_count = sat.keys.count
required_count = requested.count

if satisfied_count > 0 && required_count > 0 && satisfied_count >= required_count
  warn '✅ All requirements satisfied'
end

exit 0
