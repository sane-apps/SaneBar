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

LOG_FILE = File.expand_path('../../.claude/saneprompt.log', __dir__)

# === CONFIGURATION ===

PASSTHROUGH_PATTERNS = [
  /^(y|yes|n|no|ok|done|continue|approved|cancel|sure|thanks|thx)$/i,
  /^\/\w+/,  # slash commands
  /^[^a-zA-Z]*$/,  # no letters (just symbols/numbers)
].freeze

QUESTION_PATTERNS = [
  /^(what|where|when|why|how|which|who|can you explain|tell me about)\b/i,
  /\?$/,  # ends with question mark
  /^(does|is|are|do|should|could|would)\s+(this|it|the|that)\b/i,
].freeze

TASK_INDICATORS = [
  /\b(fix|add|create|implement|build|refactor|update|change|modify|delete|remove)\b/i,
  /\b(bug|error|issue|problem|broken|failing|crash)\b/i,
  /\b(feature|functionality|capability)\b/i,
  /\b(write|make|generate|set ?up|rewrite|overhaul|redesign)\b/i,
].freeze

BIG_TASK_INDICATORS = [
  /\b(everything|all|entire|whole|complete|full)\b/i,
  /\b(rewrite|overhaul|redesign|architecture)\b/i,
  /\b(system|framework|infrastructure)\b/i,
  /\bmultiple (files|components|modules)\b/i,
].freeze

# Trigger words that predict rule violations (learned from patterns)
PATTERN_TRIGGERS = {
  'quick' => { rules: ['#3'], warning: 'quick often leads to skipped research' },
  'just' => { rules: ['#3', '#2'], warning: '"just" suggests underestimating complexity' },
  'simple' => { rules: ['#2'], warning: '"simple" changes often need API verification' },
  'fast' => { rules: ['#3'], warning: 'rushing predicts #3 violations' },
  'easy' => { rules: ['#3', '#2'], warning: '"easy" often means skipped due diligence' },
  'minor' => { rules: ['#7'], warning: '"minor" changes still need tests' },
  'small' => { rules: ['#7'], warning: '"small" fixes still need tests' },
}.freeze

RULES_BY_TASK = {
  bug_fix: ['#3 Two Strikes', '#7 No Test No Rest', '#8 Bug Found Write Down'],
  new_feature: ['#0 Name Rule First', '#2 Verify API', '#9 Gen Pile'],
  refactor: ['#4 Green Means Go', '#10 File Size'],
  file_create: ['#1 Stay in Lane', '#9 Gen Pile'],
  general: ['#0 Name Rule First', '#5 Their House Their Rules'],
}.freeze

# === CLASSIFICATION ===

def classify_prompt(prompt)
  return :passthrough if PASSTHROUGH_PATTERNS.any? { |p| prompt.match?(p) }
  return :passthrough if prompt.length < 10

  # Questions don't need full enforcement
  return :question if QUESTION_PATTERNS.any? { |p| prompt.match?(p) }

  # Check for task indicators
  has_task = TASK_INDICATORS.any? { |p| prompt.match?(p) }
  return :question unless has_task

  # Check for big task indicators
  is_big = BIG_TASK_INDICATORS.any? { |p| prompt.match?(p) }
  is_big ? :big_task : :task
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

def update_state(prompt_type, is_big_task)
  StateManager.update(:requirements) do |req|
    req[:is_task] = [:task, :big_task].include?(prompt_type)
    req[:is_big_task] = prompt_type == :big_task
    req
  end
rescue StandardError
  # Don't fail on state errors
end

# === OUTPUT ===

def output_context(prompt_type, rules, triggers, prompt)
  lines = []

  # Only show context for tasks
  return if [:passthrough, :question].include?(prompt_type)

  lines << '---'
  lines << "Task type: #{prompt_type}"

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

def output_warning(prompt_type, rules, triggers)
  # Only show warnings for tasks (stderr shown to user)
  return if [:passthrough, :question].include?(prompt_type)

  warn '---'
  warn "SanePrompt: #{prompt_type.to_s.gsub('_', ' ').upcase}"

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
  prompt_type = classify_prompt(prompt)

  if prompt_type == :passthrough
    log_prompt(:passthrough, [], [])
    return 0
  end

  rules = rules_for_prompt(prompt)
  triggers = detect_triggers(prompt)

  log_prompt(prompt_type, rules, triggers)
  update_state(prompt_type, prompt_type == :big_task)

  # Output context to Claude (stdout)
  output_context(prompt_type, rules, triggers, prompt)

  # Output warning to user (stderr)
  output_warning(prompt_type, rules, triggers)

  0  # Always allow prompts
end

# === SELF-TEST ===

def self_test
  tests = [
    # Passthroughs
    { input: 'y', expect: :passthrough },
    { input: 'yes', expect: :passthrough },
    { input: '/commit', expect: :passthrough },
    { input: '123', expect: :passthrough },
    { input: 'ok', expect: :passthrough },

    # Questions
    { input: 'what does this function do?', expect: :question },
    { input: 'how does the authentication work?', expect: :question },
    { input: 'can you explain the architecture?', expect: :question },
    { input: 'is this correct?', expect: :question },

    # Tasks
    { input: 'fix the bug in the login flow', expect: :task, rules: ['#3'] },
    { input: 'add a new feature for user auth', expect: :task, rules: ['#0'] },
    { input: 'refactor the database layer', expect: :task, rules: ['#4'] },
    { input: 'create a new file for settings', expect: :task, rules: ['#1'] },

    # Big tasks
    { input: 'rewrite the entire authentication system', expect: :big_task },
    { input: 'refactor everything in the core module', expect: :big_task },
    { input: 'update all the components to use new API', expect: :big_task },

    # Pattern triggers
    { input: 'quick fix for the login', expect: :task, trigger: 'quick' },
    { input: 'just add a button', expect: :task, trigger: 'just' },
    { input: 'simple change to the config', expect: :task, trigger: 'simple' },
  ]

  passed = 0
  failed = 0

  tests.each do |test|
    result_type = classify_prompt(test[:input])
    type_ok = result_type == test[:expect]

    rules_ok = true
    if test[:rules]
      result_rules = rules_for_prompt(test[:input])
      rules_ok = test[:rules].all? { |r| result_rules.any? { |rr| rr.include?(r) } }
    end

    trigger_ok = true
    if test[:trigger]
      triggers = detect_triggers(test[:input])
      trigger_ok = triggers.any? { |t| t[:word] == test[:trigger] }
    end

    if type_ok && rules_ok && trigger_ok
      passed += 1
      warn "  PASS: '#{test[:input][0..40]}' -> #{result_type}"
    else
      failed += 1
      warn "  FAIL: '#{test[:input][0..40]}'"
      warn "        expected #{test[:expect]}, got #{result_type}" unless type_ok
      warn "        missing rule #{test[:rules]}" unless rules_ok
      warn "        missing trigger #{test[:trigger]}" unless trigger_ok
    end
  end

  warn ''
  warn "#{passed}/#{tests.length} tests passed"

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

# === MAIN ===

if ARGV.include?('--self-test')
  self_test
elsif ARGV.include?('--check-heartbeat')
  check_heartbeat
else
  begin
    input = JSON.parse($stdin.read)
    prompt = input['prompt'] || input['user_prompt'] || ''
    exit process_prompt(prompt)
  rescue JSON::ParserError, Errno::ENOENT
    exit 0  # Don't block on parse errors
  end
end
