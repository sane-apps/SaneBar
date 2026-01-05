#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Prompt Analyzer Hook (UserPromptSubmit)
# ==============================================================================
# Analyzes user prompts to:
# 1. Detect trigger words that require specific actions
# 2. Track user patterns and corrections for learning
# 3. Detect frustration signals (indicates Claude missed something)
#
# Hook Type: UserPromptSubmit
# Runs: When user submits a prompt, before Claude processes it
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'rule_tracker'

REQUIREMENTS_FILE = '.claude/prompt_requirements.json'
PATTERNS_FILE = '.claude/user_patterns.json'
PROMPT_LOG_FILE = '.claude/prompt_log.jsonl'

# ═══════════════════════════════════════════════════════════════════════════════
# TRIGGER DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

TRIGGERS = {
  saneloop: {
    patterns: [/\bsaneloop\b/i, /\bsane.?loop\b/i, /\bdo a.*loop\b/i],
    action: 'Start SaneLoop with acceptance criteria',
    satisfaction: 'saneloop_started'
  },
  research: {
    patterns: [/\bresearch\b/i, /\binvestigate\b/i, /\blook into\b/i, /\bresearch first\b/i],
    action: 'Use research protocol (memory, docs, web) before coding',
    satisfaction: 'research_done'
  },
  plan: {
    patterns: [/\bmake a plan\b/i, /\bplan this\b/i, /\bplan first\b/i, /\bcreate a plan\b/i],
    action: 'Show plan in plain english for approval (not just reference a file)',
    satisfaction: 'plan_shown'
  },
  explain: {
    patterns: [/\bexplain\b/i, /\bwhat does.*mean\b/i, /\bwhy\b.*\?/i],
    action: 'Use plain english, define technical terms',
    satisfaction: 'explanation_given'
  },
  commit: {
    patterns: [/\bcommit\b/i, /\bpush\b/i, /\bgit commit\b/i],
    action: 'Pull first, status, diff, add, commit, update README',
    satisfaction: 'commit_done'
  },
  bug_note: {
    patterns: [/\bmake note.*bug\b/i, /\bnote this bug\b/i, /\blog.*bug\b/i, /\bcheck bug\b/i],
    action: 'Update bug logs + memory + check for patterns',
    satisfaction: 'bug_logged'
  },
  test_mode: {
    patterns: [/\btest mode\b/i],
    action: 'Kill → Build → Launch → Stream logs',
    satisfaction: 'test_cycle_done'
  },
  verify: {
    patterns: [/\bverify everything\b/i, /\bmake sure everything\b/i, /\bcheck everything\b/i],
    action: 'Full verification with checklist',
    satisfaction: 'verification_done'
  },
  show: {
    patterns: [/\bshow me\b/i, /\blet me see\b/i, /\bdisplay\b/i],
    action: 'Display content directly, do not just describe it',
    satisfaction: 'content_shown'
  },
  remember: {
    patterns: [/\bremember\b/i, /\bsave this\b/i, /\bstore this\b/i, /\bdon'?t forget\b/i],
    action: 'Store in memory MCP',
    satisfaction: 'memory_stored'
  },
  stop: {
    patterns: [/\bstop\b/i, /\bwait\b/i, /\bhold on\b/i, /\bhang on\b/i],
    action: 'Interrupt current action immediately',
    satisfaction: 'stopped',
    immediate: true
  },
  session_end: {
    patterns: [/\bwrap up\b/i, /\bend session\b/i, /\bwrap up session\b/i, /\bclose.*session\b/i, /\bfinish up\b/i],
    action: 'Run compliance report → proper summary (SOP Compliance + Performance) → session_end',
    satisfaction: 'session_ended'
  }
}.freeze

# ═══════════════════════════════════════════════════════════════════════════════
# MODIFIER PATTERNS (change how triggers are interpreted)
# ═══════════════════════════════════════════════════════════════════════════════

MODIFIERS = {
  first: {
    patterns: [/first\b/i, /\bbefore anything\b/i, /\bbefore you\b/i],
    meaning: 'Do this BEFORE any other action'
  },
  just: {
    patterns: [/\bjust\b/i, /\bonly\b/i, /\bminimal\b/i],
    meaning: 'Minimal scope - do not over-engineer'
  },
  quick: {
    patterns: [/\bquick\b/i, /\bquickly\b/i, /\bfast\b/i],
    meaning: 'Speed matters but do not skip verification'
  },
  everything: {
    patterns: [/\beverything\b/i, /\babsolutely\b/i, /\ball\b/i, /\bcomprehensive\b/i],
    meaning: 'Leave no stone unturned'
  },
  careful: {
    patterns: [/\bcareful\b/i, /\bcarefully\b/i, /\bthoroughly\b/i],
    meaning: 'Extra attention required'
  },
  again: {
    patterns: [/\bagain\b/i, /\btry again\b/i, /\bone more time\b/i],
    meaning: 'Previous attempt failed - use DIFFERENT approach (Rule #3)'
  }
}.freeze

# ═══════════════════════════════════════════════════════════════════════════════
# FRUSTRATION SIGNALS (Claude missed something)
# ═══════════════════════════════════════════════════════════════════════════════

FRUSTRATION_SIGNALS = {
  correction: {
    patterns: [/^no[,.]?\s/i, /\bthat'?s not\b/i, /\bi said\b/i, /\bi already\b/i, /\bi meant\b/i],
    meaning: 'Claude misunderstood - log for learning'
  },
  impatience: {
    patterns: [/\bidiot\b/i, /\buse your head\b/i, /\bthink\b/i, /\bstop rushing\b/i],
    meaning: 'Claude being careless - slow down'
  },
  skepticism: {
    patterns: [/\.\.\.$/, /\breally\?\b/i, /\bare you sure\b/i, /\bhmm\b/i],
    meaning: 'User doubts response - verify before continuing'
  },
  repetition: {
    patterns: [/\bi just said\b/i, /\blike i said\b/i, /\bas i mentioned\b/i],
    meaning: 'Claude ignored previous instruction - check history'
  }
}.freeze

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def load_requirements
  return { requested: [], satisfied: [], modifiers: [], timestamp: nil } unless File.exist?(REQUIREMENTS_FILE)

  JSON.parse(File.read(REQUIREMENTS_FILE), symbolize_names: true)
rescue StandardError
  { requested: [], satisfied: [], modifiers: [], timestamp: nil }
end

def save_requirements(reqs)
  FileUtils.mkdir_p(File.dirname(REQUIREMENTS_FILE))
  File.write(REQUIREMENTS_FILE, JSON.pretty_generate(reqs))
end

def load_patterns
  return { learned: [], corrections: 0, last_updated: nil } unless File.exist?(PATTERNS_FILE)

  JSON.parse(File.read(PATTERNS_FILE), symbolize_names: true)
rescue StandardError
  { learned: [], corrections: 0, last_updated: nil }
end

def save_patterns(patterns)
  FileUtils.mkdir_p(File.dirname(PATTERNS_FILE))
  File.write(PATTERNS_FILE, JSON.pretty_generate(patterns))
end

def log_prompt(prompt, detected_triggers, detected_modifiers, frustration)
  FileUtils.mkdir_p(File.dirname(PROMPT_LOG_FILE))
  entry = {
    timestamp: Time.now.iso8601,
    prompt: prompt[0..500], # Truncate long prompts
    triggers: detected_triggers,
    modifiers: detected_modifiers,
    frustration: frustration
  }
  File.open(PROMPT_LOG_FILE, 'a') { |f| f.puts entry.to_json }
end

def detect_patterns(text, pattern_hash)
  detected = []
  pattern_hash.each do |name, config|
    config[:patterns].each do |pattern|
      if text.match?(pattern)
        detected << { name: name, action: config[:action], meaning: config[:meaning] }.compact
        break
      end
    end
  end
  detected
end

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

prompt = input['prompt'] || ''
exit 0 if prompt.empty?

# Detect triggers, modifiers, and frustration
detected_triggers = detect_patterns(prompt, TRIGGERS)
detected_modifiers = detect_patterns(prompt, MODIFIERS)
detected_frustration = detect_patterns(prompt, FRUSTRATION_SIGNALS)

# Log the prompt for pattern learning
log_prompt(prompt, detected_triggers.map { |t| t[:name] }, detected_modifiers.map { |m| m[:name] }, detected_frustration.map { |f| f[:name] })

# Update requirements
reqs = load_requirements

# Clear old requirements if this is a new task (no triggers = fresh start)
# Keep requirements if user is continuing (has triggers that match existing)
if detected_triggers.any?
  trigger_names = detected_triggers.map { |t| t[:name].to_s }
  reqs[:requested] = trigger_names
  reqs[:satisfied] = [] # Reset satisfaction for new requests
  reqs[:modifiers] = detected_modifiers.map { |m| m[:name].to_s }
  reqs[:timestamp] = Time.now.iso8601
  save_requirements(reqs)
end

# Handle frustration signals - this is learning data
if detected_frustration.any?
  patterns = load_patterns
  patterns[:corrections] += 1
  patterns[:last_updated] = Time.now.iso8601

  # Log the correction for learning
  RuleTracker.log_violation(
    rule: :user_correction,
    hook: 'prompt_analyzer',
    reason: "User correction detected: #{detected_frustration.map { |f| f[:name] }.join(', ')}"
  )

  save_patterns(patterns)

  # Warn Claude about the frustration
  warn ''
  warn '⚠️  USER CORRECTION DETECTED'
  detected_frustration.each do |f|
    warn "   #{f[:name]}: #{f[:meaning]}"
  end
  warn '   → Slow down, check what you missed'
  warn ''
end

# Output detected triggers as context for Claude
if detected_triggers.any?
  warn ''
  warn '═══════════════════════════════════════════════════════════════'
  warn '  PROMPT ANALYSIS'
  warn '═══════════════════════════════════════════════════════════════'
  warn ''
  warn '  Detected triggers:'
  detected_triggers.each do |t|
    warn "    • #{t[:name]}: #{t[:action]}"
  end

  if detected_modifiers.any?
    warn ''
    warn '  Modifiers:'
    detected_modifiers.each do |m|
      warn "    • #{m[:name]}: #{m[:meaning]}"
    end
  end

  warn ''
  warn '  These requirements will be enforced by subsequent hooks.'
  warn ''
  warn '═══════════════════════════════════════════════════════════════'
  warn ''
end

exit 0
