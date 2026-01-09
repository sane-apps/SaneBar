#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SanePrompt - UserPromptSubmit Hook
# ==============================================================================
# Classifies prompts, injects context, detects patterns.
#
# Exit codes:
#   0 = allow (context injected via stdout if needed)
#   2 = block (rare - only for truly dangerous prompts)
#
# What this does:
#   1. Classifies: passthrough, question, task, big_task
#   2. Detects task types: bug_fix, new_feature, refactor, etc.
#   3. Shows applicable rules
#   4. Detects pattern triggers (words that predict rule violations)
#   5. Updates state for other hooks
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'core/state_manager'
require_relative 'saneprompt_intelligence'

include SanePromptIntelligence

LOG_FILE = File.expand_path('../../.claude/saneprompt.log', __dir__)

# === CONFIGURATION ===

# Pre-compiled regex unions for O(1) matching instead of O(n) array iteration
PASSTHROUGH_PATTERN = Regexp.union(
  /^(y|yes|n|no|ok|done|continue|approved|cancel|sure|thanks|thx)$/i,
  /^\/\w+/,  # slash commands
  /^[^a-zA-Z]*$/  # no letters (just symbols/numbers)
).freeze

# === SAFEMODE COMMANDS ===
BYPASS_FILE = File.expand_path('../../.claude/bypass_active.json', __dir__)
SANEMASTER_PATH = File.expand_path('../../Scripts/SaneMaster.rb', __dir__)

def handle_safemode_command(prompt)
  cmd = prompt.strip.downcase

  # === SANELOOP COMMANDS (user-only) ===
  if cmd.start_with?('sl+') || cmd.start_with?('saneloop on') || cmd.start_with?('saneloop start')
    # Start saneloop - extract task from command if provided
    task_match = prompt.match(/sl\+\s+(.+)/i) || prompt.match(/saneloop\s+(?:on|start)\s+(.+)/i)
    if task_match
      task = task_match[1].strip
      result = `#{SANEMASTER_PATH} saneloop start "#{task}" 2>&1`
      warn ''
      warn result
      warn ''
    else
      warn ''
      warn 'SANELOOP: Provide a task description'
      warn '  Usage: sl+ <task description>'
      warn '  Example: sl+ Fix the authentication bug'
      warn ''
    end
    true
  elsif cmd.start_with?('sl-') || cmd.start_with?('saneloop off') || cmd.start_with?('saneloop stop')
    # Stop/cancel saneloop
    result = `#{SANEMASTER_PATH} saneloop cancel 2>&1`
    warn ''
    warn result
    warn ''
    true
  elsif cmd.start_with?('sl?') || cmd == 'saneloop' || cmd.start_with?('saneloop status')
    # Show saneloop status
    result = `#{SANEMASTER_PATH} saneloop status 2>&1`
    warn ''
    warn result
    warn ''
    true
  elsif cmd.start_with?('s+') || cmd.start_with?('safemode on')
    # Enable safemode = delete bypass file
    if File.exist?(BYPASS_FILE)
      File.delete(BYPASS_FILE)
      warn ''
      warn 'SAFEMODE ON - enforcement active'
      warn ''
    else
      warn ''
      warn 'SAFEMODE already on'
      warn ''
    end
    true
  elsif cmd.start_with?('s-') || cmd.start_with?('safemode off')
    # Disable safemode = create bypass file
    FileUtils.mkdir_p(File.dirname(BYPASS_FILE))
    File.write(BYPASS_FILE, '{}')
    warn ''
    warn 'SAFEMODE OFF - enforcement bypassed'
    warn ''
    true
  elsif cmd.start_with?('s?') || cmd == 'safemode' || cmd.start_with?('safemode status')
    status = File.exist?(BYPASS_FILE) ? 'OFF (bypassed)' : 'ON (enforcing)'
    warn ''
    warn "SAFEMODE: #{status}"
    warn ''
    true
  elsif cmd.start_with?('reset breaker') || cmd.start_with?('reset circuit') || cmd.start_with?('rb-') || cmd.start_with?('rb+')
    # Reset circuit breaker state (rb- and rb+ both reset)
    debug_log("RESET BREAKER: cmd='#{cmd}'") rescue nil
    debug_log("BEFORE RESET: #{StateManager.get(:circuit_breaker).inspect}") rescue nil
    StateManager.reset(:circuit_breaker)
    log_reset('circuit_breaker', 'User reset circuit breaker')
    debug_log("AFTER RESET: #{StateManager.get(:circuit_breaker).inspect}") rescue nil
    warn ''
    warn 'CIRCUIT BREAKER RESET'
    warn '  Failures: 0'
    warn '  Tripped: false'
    warn '  Error signatures: cleared'
    warn '  (logged to reset_audit.log)'
    warn ''
    true
  elsif cmd.start_with?('rb?') || cmd == 'breaker status'
    # Show circuit breaker status
    cb = StateManager.get(:circuit_breaker)
    warn ''
    warn 'CIRCUIT BREAKER STATUS'
    warn "  Tripped: #{cb[:tripped] || false}"
    warn "  Failures: #{cb[:failures] || 0}"
    if cb[:error_signatures]&.any?
      warn '  Error signatures:'
      cb[:error_signatures].each { |sig, count| warn "    #{sig}: #{count}" }
    end
    warn ''
    true
  elsif cmd.start_with?('reset blocks') || cmd == 'unblock'
    # Reset refusal-to-read tracking (allows retrying after reading the message)
    StateManager.reset(:refusal_tracking)
    log_reset('refusal_tracking', 'User reset block counters')
    warn ''
    warn 'BLOCK COUNTERS RESET'
    warn '  All block type counters cleared.'
    warn '  You may now retry - but READ the block messages this time.'
    warn '  Next block of same type starts fresh at count=1.'
    warn ''
    true
  elsif cmd.start_with?('reset research') || cmd == 'rr-'
    # Reset research tracking (forces re-doing all 5 categories)
    StateManager.reset(:research)
    log_reset('research', 'User reset research requirements')
    warn ''
    warn 'RESEARCH RESET'
    warn '  All 5 research categories cleared.'
    warn '  Must complete: memory, docs, web, github, local'
    warn '  This is NOT a bypass - you must actually do the research.'
    warn ''
    true
  elsif cmd == 'reset?' || cmd == 'resets?'
    # Show all available reset commands
    warn ''
    warn 'AVAILABLE RESET COMMANDS'
    warn ''
    warn '  rb-  / reset breaker   → Clear circuit breaker (after 3+ failures)'
    warn '  reset blocks / unblock → Clear block counters (after repeated blocks)'
    warn '  rr- / reset research   → Clear research (forces redo all 5 categories)'
    warn ''
    warn 'Resets are LOGGED and do NOT disable hooks.'
    warn 'They allow retry - the hooks still enforce rules.'
    warn ''
    true
  else
    false
  end
end

# Log all resets for audit trail
def log_reset(what, reason)
  log_file = File.join(CLAUDE_DIR, 'reset_audit.log')
  entry = {
    timestamp: Time.now.iso8601,
    reset_type: what,
    reason: reason,
    pid: Process.pid
  }
  File.open(log_file, 'a') { |f| f.puts(entry.to_json) }
rescue StandardError
  # Don't fail on logging errors
end

QUESTION_PATTERN = Regexp.union(
  /^(what|where|when|why|how|which|who|can you explain|tell me about)\b/i,
  /\?$/,  # ends with question mark
  /^(does|is|are|do|should|could|would)\s+(this|it|the|that)\b/i
).freeze

TASK_INDICATOR = Regexp.union(
  /\b(fix|add|create|implement|build|refactor|update|change|modify|delete|remove)\b/i,
  /\b(bug|error|issue|problem|broken|failing|crash)\b/i,
  /\b(feature|functionality|capability)\b/i,
  /\b(write|make|generate|set ?up|rewrite|overhaul|redesign)\b/i
).freeze

BIG_TASK_INDICATOR = Regexp.union(
  /\b(everything|all|entire|whole|complete|full)\b/i,
  /\b(rewrite|overhaul|redesign|architecture)\b/i,
  /\b(system|framework|infrastructure)\b/i,
  /\bmultiple (files|components|modules)\b/i
).freeze

# Trigger words that predict rule violations (learned from patterns)
PATTERN_TRIGGERS = {
  'quick' => { rules: ['#3'], warning: 'quick often leads to skipped research' },
  'just' => { rules: ['#3', '#2'], warning: '"just" suggests underestimating complexity' },
  'simple' => { rules: ['#2'], warning: '"simple" changes often need API verification' },
  'fast' => { rules: ['#3'], warning: 'rushing predicts #3 violations' },
  'easy' => { rules: ['#3', '#2'], warning: '"easy" often means skipped due diligence' },
  'minor' => { rules: ['#7'], warning: '"minor" changes still need tests' },
  'small' => { rules: ['#7'], warning: '"small" fixes still need tests' },
  'tiny' => { rules: ['#7'], warning: '"tiny" fixes still need tests' },
  'trivial' => { rules: ['#3', '#7'], warning: '"trivial" often means skipped verification' },
}.freeze

# === INTELLIGENCE: Frustration Detection (in saneprompt_intelligence.rb) ===

# === BUTT-KICKER: Catch ignored warnings ===
def check_ignored_warning(prompt)
  return nil unless File.exist?(LOG_FILE)

  # Get last non-passthrough entry
  last_entry = nil
  File.readlines(LOG_FILE).reverse_each do |line|
    entry = JSON.parse(line) rescue next
    next if entry['type'] == 'passthrough'
    last_entry = entry
    break
  end

  return nil unless last_entry
  return nil if last_entry['triggers'].nil? || last_entry['triggers'].empty?

  # Check if current prompt has same triggers
  current_triggers = detect_triggers(prompt).map { |t| t[:word] }
  repeated = last_entry['triggers'] & current_triggers

  return nil if repeated.empty?

  # BUTT-KICK
  "STOP. You were just warned about: #{repeated.join(', ')}. READ THE WARNING."
rescue StandardError
  nil
end

# === INTELLIGENCE: Requirement Triggers ===
# When user says these, store as REQUIREMENT that must be satisfied
REQUIREMENT_TRIGGERS = {
  saneloop: [/\bsaneloop\b/i, /\bsane ?loop\b/i, /start the loop/i],
  commit: [/\bcommit\b/i, /\bgit commit\b/i, /commit the changes/i],
  plan: [/\bplan\s*(first|before)\b/i, /\bmake a plan\b/i, /\bplan this\b/i],
  research: [/\bresearch\s*(first|this)\b/i, /\binvestigate\b/i, /\blook into\b/i]
}.freeze

# Research-only mode: user wants research WITHOUT any edits
# When detected, ALL mutations blocked for the session (even after research complete)
RESEARCH_ONLY_PATTERN = Regexp.union(
  /\bresearch\b(?!.*\b(then|and|after)\b.*\b(fix|add|implement|update|change)\b)/i,  # "research X" without action verbs
  /\binvestigate\b(?!.*\b(then|and)\b.*\bfix\b)/i,     # "investigate" without "then fix"
  /\blook into\b(?!.*\b(then|and)\b.*\bfix\b)/i,       # "look into" without "then fix"
  /\bexplore\b.*\b(codebase|code|project)\b/i,         # "explore the codebase"
  /\bunderstand\b.*\b(how|why|what)\b/i,               # "understand how X works"
  /\bexplain\b.*\b(how|why|what)\b/i,                  # "explain how X works"
  /\bwhat('?s| is)\b.*\b(causing|happening|wrong)\b/i, # "what's causing X"
  /\bfind out\b.*\bwhy\b/i                             # "find out why"
).freeze

# Action verbs that override research-only (user wants changes)
ACTION_VERBS_PATTERN = /\b(fix|add|create|implement|update|change|modify|edit|write|remove|delete|refactor)\b/i.freeze

# === RESEARCH-ONLY MODE DETECTION ===
# User wants investigation WITHOUT any edits
# When detected: ALL mutations blocked for entire session

def detect_research_only_mode(prompt)
  # Must match research pattern
  return false unless prompt.match?(RESEARCH_ONLY_PATTERN)

  # If action verbs present, user wants changes (not research-only)
  return false if prompt.match?(ACTION_VERBS_PATTERN)

  true
end

# Fresh start = reset requirements; Additive = add to existing
FRESH_START_TRIGGERS = %w[saneloop commit test_mode].freeze
ADDITIVE_TRIGGERS = %w[research plan explain verify].freeze

RULES_BY_TASK = {
  bug_fix: ['#3 Two Strikes', '#7 No Test No Rest', '#8 Bug Found Write Down'],
  new_feature: ['#0 Name Rule First', '#2 Verify API', '#9 Gen Pile'],
  refactor: ['#4 Green Means Go', '#10 File Size'],
  file_create: ['#1 Stay in Lane', '#9 Gen Pile'],
  general: ['#0 Name Rule First', '#5 Their House Their Rules'],
}.freeze

# === CLASSIFICATION ===

def classify_prompt(prompt)
  return :passthrough if prompt.match?(PASSTHROUGH_PATTERN)
  return :passthrough if prompt.length < 10

  # Questions don't need full enforcement
  return :question if prompt.match?(QUESTION_PATTERN)

  # Check for task indicators
  return :question unless prompt.match?(TASK_INDICATOR)

  # Check for big task indicators
  prompt.match?(BIG_TASK_INDICATOR) ? :big_task : :task
end

def detect_task_types(prompt)
  types = []
  types << :bug_fix if prompt.match?(/\b(fix|bug|error|broken|failing|crash)\b/i)
  types << :new_feature if prompt.match?(/\b(add|create|implement|new|feature)\b/i)
  types << :refactor if prompt.match?(/\b(refactor|reorganize|restructure|clean ?up)\b/i)
  types << :file_create if prompt.match?(/\b(create|new) (file|class|struct|view|model)\b/i)
  types << :general if types.empty?
  types
end

def rules_for_prompt(prompt)
  types = detect_task_types(prompt)
  types.flat_map { |t| RULES_BY_TASK[t] }.uniq
end

def detect_triggers(prompt)
  triggers = []
  prompt_lower = prompt.downcase

  PATTERN_TRIGGERS.each do |word, info|
    if prompt_lower.include?(word)
      triggers << { word: word, rules: info[:rules], warning: info[:warning] }
    end
  end

  triggers
end


# === INTELLIGENCE: Requirement Extraction ===

def extract_requirements(prompt)
  detected = []

  REQUIREMENT_TRIGGERS.each do |req_type, patterns|
    if patterns.any? { |p| prompt.match?(p) }
      detected << req_type.to_s
    end
  end

  detected
end

def update_requirements(detected_reqs)
  return if detected_reqs.empty?

  StateManager.update(:requirements) do |reqs|
    # Check if any detected requirement is a fresh start trigger
    is_fresh = detected_reqs.any? { |r| FRESH_START_TRIGGERS.include?(r) }

    if is_fresh
      # Reset and set new requirements
      reqs[:requested] = detected_reqs
      reqs[:satisfied] = []
    else
      # Additive: merge with existing
      reqs[:requested] = ((reqs[:requested] || []) + detected_reqs).uniq
    end

    reqs
  end
rescue StandardError
  # Don't fail on state errors
end

# === INTELLIGENCE: Pattern Learning (in saneprompt_intelligence.rb) ===

# === INTELLIGENCE: Pattern Display (in saneprompt_intelligence.rb) ===

# === STATE & LOGGING ===

def log_prompt(prompt_type, rules, triggers)
  FileUtils.mkdir_p(File.dirname(LOG_FILE))
  entry = {
    timestamp: Time.now.iso8601,
    type: prompt_type,
    rules: rules,
    triggers: triggers.map { |t| t[:word] },
    pid: Process.pid
  }
  File.open(LOG_FILE, 'a') { |f| f.puts(entry.to_json) }
rescue StandardError
  # Don't fail on logging errors
end

def update_state(prompt_type, is_big_task, is_research_only = false)
  StateManager.update(:requirements) do |req|
    req[:is_task] = [:task, :big_task].include?(prompt_type)
    req[:is_big_task] = prompt_type == :big_task
    req[:is_research_only] = is_research_only
    req
  end
rescue StandardError
  # Don't fail on state errors
end

# === OUTPUT ===

def output_context(prompt_type, rules, triggers, prompt, frustrations = [], detected_reqs = [], learning_warning = nil, patterns = nil, memory_staging = nil)
  lines = []

  # Only show context for tasks
  return if [:passthrough, :question].include?(prompt_type)

  lines << '---'
  lines << "Task type: #{prompt_type}"

  # AUTO-SANELOOP: Inject structured workflow for ALL tasks
  # This is the core of the unified workflow system
  # Learned from 700+ iteration failure: guardrails prevent spirals
  # User insight: "ANY code change is a big task" - no more "no big deal" syndrome
  lines << ''
  lines << 'WORKFLOW STRUCTURE (auto-injected):'
  lines << '  1. Research ALL 5 categories before editing (memory, docs, web, github, local)'
  lines << '  2. Define acceptance criteria: what does "done" look like?'
  lines << '  3. Edits blocked until research complete (sanetools enforces)'
  lines << '  4. Self-rate SOP compliance when done'
  lines << ''
  lines << 'GUARDRAILS ACTIVE (all code tasks):'
  lines << '  - Max 3 edit attempts before mandatory research pause (ENFORCED)'
  lines << '  - If stuck after 2 tries: STOP and investigate, do not guess'
  lines << '  - Circuit breaker trips at 3 consecutive failures'
  if prompt_type == :big_task
    lines << ''
    lines << 'BIG TASK - Additional guardrails:'
    lines << '  - SaneLoop iterations tracked'
    lines << '  - Max 20 iterations before human check-in'
  end

  # INTELLIGENCE: Memory MCP update needed from previous session
  memory_context = format_memory_staging_context(memory_staging)
  if memory_context
    lines << ''
    lines << memory_context
  end

  # INTELLIGENCE: Show learned patterns from previous sessions
  pattern_context = format_patterns_for_claude(patterns)
  if pattern_context
    lines << ''
    lines << pattern_context
  end

  # INTELLIGENCE: Learning pattern warning
  if learning_warning
    lines << ''
    lines << "LEARNING WARNING: #{learning_warning}"
  end

  # INTELLIGENCE: Frustration detected
  if frustrations.any?
    lines << ''
    lines << 'FRUSTRATION DETECTED:'
    frustrations.each do |f|
      lines << "  Type: #{f[:type]} - User may be correcting you. Read carefully."
    end
  end

  # INTELLIGENCE: Requirements extracted
  if detected_reqs.any?
    lines << ''
    lines << 'REQUIREMENTS DETECTED:'
    detected_reqs.each do |r|
      lines << "  #{r} - Must be satisfied before editing"
    end
  end

  if triggers.any?
    lines << ''
    lines << 'PATTERN ALERT:'
    triggers.each do |t|
      lines << "  #{t[:word]}: #{t[:warning]}"
    end
  end

  if rules.any?
    lines << ''
    lines << 'Applicable rules:'
    rules.each { |r| lines << "  #{r}" }
  end

  lines << '---'

  # Output to stdout - this becomes context for Claude
  puts lines.join("\n")
end

def output_warning(prompt_type, rules, triggers, frustrations = [], detected_reqs = [], patterns = nil)
  # Only show warnings for tasks (stderr shown to user)
  return if [:passthrough, :question].include?(prompt_type)

  warn '---'
  warn "SanePrompt: #{prompt_type.to_s.gsub('_', ' ').upcase}"

  # INTELLIGENCE: Show pattern summary to user
  pattern_summary = format_patterns_for_user(patterns)
  if pattern_summary
    warn ''
    warn pattern_summary
  end

  # INTELLIGENCE: Show frustration warning to user
  if frustrations.any?
    warn ''
    warn 'Frustration detected - Claude will read carefully'
  end

  # INTELLIGENCE: Show detected requirements
  if detected_reqs.any?
    warn ''
    warn "Requirements: #{detected_reqs.join(', ')}"
  end

  if triggers.any?
    warn ''
    warn 'Pattern triggers detected:'
    triggers.each { |t| warn "  #{t[:word]} -> #{t[:warning]}" }
  end

  if rules.any?
    warn ''
    warn 'Rules to follow:'
    rules.first(3).each { |r| warn "  #{r}" }
  end

  warn '---'
end

# === MAIN PROCESSING ===

def process_prompt(prompt)
  # Handle safemode commands first
  if handle_safemode_command(prompt)
    return 0
  end

  prompt_type = classify_prompt(prompt)

  if prompt_type == :passthrough
    log_prompt(:passthrough, [], [])
    return 0
  end

  rules = rules_for_prompt(prompt)
  triggers = detect_triggers(prompt)

  # === INTELLIGENCE ===

  # 0. BUTT-KICKER: Check if ignoring previous warning
  butt_kick = check_ignored_warning(prompt)
  if butt_kick
    warn ''
    warn '=' * 50
    warn butt_kick
    warn '=' * 50
    warn ''
  end

  # 1. Detect frustration signals
  frustrations = detect_frustration(prompt)

  # 2. Extract and store requirements
  detected_reqs = extract_requirements(prompt)
  update_requirements(detected_reqs)

  # 3. Learn from frustration
  learn_from_frustration(prompt, frustrations)

  # 4. Check past learnings for patterns
  learning_warning = check_past_learnings

  # 5. Detect research-only mode
  is_research_only = detect_research_only_mode(prompt)

  # 6. Get learned patterns from previous sessions
  learned_patterns = get_learned_patterns

  # 7. Check for memory staging from previous session
  memory_staging = check_memory_staging
  # Mark as processed so it doesn't repeat on every prompt
  mark_memory_staging_processed if memory_staging

  # === END INTELLIGENCE ===

  log_prompt(prompt_type, rules, triggers)
  update_state(prompt_type, prompt_type == :big_task, is_research_only)

  # Output research-only warning
  if is_research_only
    warn ''
    warn '=' * 50
    warn 'RESEARCH-ONLY MODE ACTIVE'
    warn 'User wants investigation, NOT changes.'
    warn 'ALL edits blocked for this session.'
    warn '=' * 50
    warn ''
  end

  # Output memory staging reminder to user
  if memory_staging
    warn ''
    warn '=' * 50
    warn 'MEMORY MCP UPDATE PENDING'
    warn 'Previous session staged learnings - Claude will save to Memory MCP'
    warn '=' * 50
    warn ''
  end

  # Output context to Claude (stdout)
  output_context(prompt_type, rules, triggers, prompt, frustrations, detected_reqs, learning_warning, learned_patterns, memory_staging)

  # Output warning to user (stderr)
  output_warning(prompt_type, rules, triggers, frustrations, detected_reqs, learned_patterns)

  0  # Always allow prompts
end

# === SELF-TEST ===
# Tests extracted to saneprompt_test.rb per Rule #10

def self_test
  require_relative 'saneprompt_test'
  exit SanePromptTest.run(
    method(:classify_prompt),
    method(:rules_for_prompt),
    method(:detect_triggers),
    method(:detect_frustration),
    method(:extract_requirements),
    method(:detect_research_only_mode),
    method(:handle_safemode_command)
  )
end

def check_heartbeat
  begin
    last_line = File.readlines(LOG_FILE).last
    entry = JSON.parse(last_line)
    last = Time.parse(entry['timestamp'])
    age = Time.now - last
    warn "Last prompt: #{entry['type']} at #{entry['timestamp']} (#{age.round}s ago)"
    exit(age < 300 ? 0 : 1)
  rescue StandardError => e
    warn "No heartbeat: #{e.message}"
    exit 1
  end
end

# === DEBUG LOGGING ===
DEBUG_FILE = File.expand_path('../../.claude/saneprompt_debug.log', __dir__)

def debug_log(msg)
  FileUtils.mkdir_p(File.dirname(DEBUG_FILE))
  File.open(DEBUG_FILE, 'a') { |f| f.puts("[#{Time.now.iso8601}] #{msg}") }
rescue StandardError
  # ignore
end

# === MAIN ===

if ARGV.include?('--self-test')
  self_test
elsif ARGV.include?('--check-heartbeat')
  check_heartbeat
else
  begin
    raw = $stdin.read
    debug_log("RAW INPUT: #{raw[0..200]}")
    input = JSON.parse(raw)
    debug_log("PARSED KEYS: #{input.keys.inspect}")
    prompt = input['prompt'] || input['user_prompt'] || ''
    debug_log("EXTRACTED PROMPT: '#{prompt}'")
    exit process_prompt(prompt)
  rescue JSON::ParserError, Errno::ENOENT => e
    debug_log("PARSE ERROR: #{e.message}")
    exit 0  # Don't block on parse errors
  end
end
