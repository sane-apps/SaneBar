#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Unified State Manager
# ==============================================================================
# Single source of truth for all hook state. Replaces 15+ scattered JSON files
# with one signed, locked state file.
#
# Features:
#   - Single .claude/state.json file
#   - File locking for concurrent access
#   - HMAC signing for tamper detection
#   - Atomic writes (tempfile + rename)
#   - Schema defaults for missing keys
#
# Usage:
#   require_relative 'core/state_manager'
#   StateManager.get(:circuit_breaker, :failures)  # => 0
#   StateManager.set(:circuit_breaker, :failures, 1)
#   StateManager.update(:edits) { |e| e[:count] += 1; e }
#   StateManager.reset(:research)
#
# Sections:
#   - circuit_breaker: Failure tracking, trip state
#   - requirements: What user requested, what's satisfied
#   - research: 5 category completion status
#   - edits: Edit count, unique files list
#   - saneloop: Active loop state, iteration, criteria
#   - enforcement: Enforcement breaker state
# ==============================================================================

require 'json'
require 'fileutils'
require 'tempfile'
require_relative '../state_signer'

module StateManager
  PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
  STATE_FILE = File.join(PROJECT_DIR, '.claude', 'state.json')
  LOCK_FILE = "#{STATE_FILE}.lock"

  # Schema with defaults for each section
  SCHEMA = {
    circuit_breaker: {
      failures: 0,
      tripped: false,
      tripped_at: nil,
      last_error: nil,
      error_signatures: {}
    },
    requirements: {
      requested: [],
      satisfied: [],
      is_task: false,
      is_big_task: false
    },
    research: {
      memory: nil,
      docs: nil,
      web: nil,
      github: nil,
      local: nil
    },
    edits: {
      count: 0,
      unique_files: [],
      last_file: nil
    },
    saneloop: {
      active: false,
      task: nil,
      iteration: 0,
      max_iterations: 20,
      acceptance_criteria: [],
      started_at: nil
    },
    enforcement: {
      blocks: [],
      halted: false,
      halted_at: nil,
      halted_reason: nil
    },
    # Edit attempt tracking (prevents "no big deal" syndrome)
    edit_attempts: {
      count: 0,
      last_attempt: nil,
      reset_at: nil
    },
    # === INTELLIGENCE: Pattern learning sections ===
    action_log: [],  # Last 20 actions for correlation
    learnings: [],   # Learned patterns from user corrections
    patterns: {
      weak_spots: {},     # { "rule_N" => count } - rules frequently violated
      triggers: {},       # { "word" => ["rule_N"] } - words that predict violations
      strengths: [],      # ["rule_N"] - rules with 100% compliance
      session_scores: []  # Last 10 SOP scores for variance detection
    },
    # === MCP VERIFICATION SYSTEM ===
    # Tracks MCP health and ensures all MCPs verified before edits
    mcp_health: {
      verified_this_session: false,
      last_verified: nil,
      mcps: {
        memory: { verified: false, last_success: nil, last_failure: nil, failure_count: 0 },
        apple_docs: { verified: false, last_success: nil, last_failure: nil, failure_count: 0 },
        context7: { verified: false, last_success: nil, last_failure: nil, failure_count: 0 },
        github: { verified: false, last_success: nil, last_failure: nil, failure_count: 0 }
      }
    },
    # === REFUSAL TO READ TRACKING ===
    # Detects when AI is blocked repeatedly for same reason but keeps trying
    # instead of reading the message and following instructions
    refusal_tracking: {}
  }.freeze

  class << self
    # Get a value from state
    # StateManager.get(:circuit_breaker, :failures) => 0
    # StateManager.get(:circuit_breaker) => { failures: 0, ... }
    def get(section, key = nil)
      state = load_state
      section_data = state[section] || SCHEMA[section].dup

      if key
        section_data[key]
      else
        section_data
      end
    end

    # Set a value in state
    # StateManager.set(:circuit_breaker, :failures, 1)
    def set(section, key, value)
      with_lock do
        state = load_state_unlocked
        state[section] ||= SCHEMA[section].dup
        state[section][key] = value
        save_state_unlocked(state)
      end
      value
    end

    # Update a section with a block
    # StateManager.update(:edits) { |e| e[:count] += 1; e }
    def update(section)
      with_lock do
        state = load_state_unlocked
        state[section] ||= SCHEMA[section].dup
        state[section] = yield(state[section])
        save_state_unlocked(state)
      end
    end

    # Reset a section to defaults
    # StateManager.reset(:research)
    def reset(section)
      with_lock do
        state = load_state_unlocked
        state[section] = SCHEMA[section].dup
        save_state_unlocked(state)
      end
    end

    # Reset all state (session start)
    def reset_all
      with_lock do
        state = {}
        SCHEMA.each { |k, v| state[k] = v.dup }
        save_state_unlocked(state)
      end
    end

    # Preserve some sections, reset others (session start pattern)
    def reset_except(*preserve)
      with_lock do
        old_state = load_state_unlocked
        state = {}
        SCHEMA.each do |k, v|
          state[k] = preserve.include?(k) ? (old_state[k] || v.dup) : v.dup
        end
        save_state_unlocked(state)
      end
    end

    # Check if state file exists
    def exists?
      File.exist?(STATE_FILE)
    end

    # Get full state (read-only copy)
    def to_h
      load_state.dup
    end

    # Debug: dump state
    def dump
      state = load_state
      JSON.pretty_generate(state)
    end

    private

    # Load state with file locking
    def load_state
      with_lock { load_state_unlocked }
    end

    # Load without lock (must be called within with_lock)
    def load_state_unlocked
      return initialize_state unless File.exist?(STATE_FILE)

      # Use stdlib symbolize_names: true via StateSigner
      data = StateSigner.read_verified(STATE_FILE, symbolize: true)
      return initialize_state unless data

      # Merge with schema defaults for any missing keys
      merge_with_defaults(data)
    rescue JSON::ParserError, StandardError
      initialize_state
    end

    # Save with atomic write (tempfile + rename)
    def save_state_unlocked(state)
      FileUtils.mkdir_p(File.dirname(STATE_FILE))

      # Write to temp file first
      temp = Tempfile.new('state', File.dirname(STATE_FILE))
      begin
        # Convert symbols to strings for JSON
        string_state = stringify_keys(state)
        StateSigner.write_signed(temp.path, string_state)
        temp.close

        # Atomic rename
        File.rename(temp.path, STATE_FILE)
      ensure
        temp.close rescue nil
        temp.unlink rescue nil
      end
    end

    # Initialize with schema defaults
    def initialize_state
      state = {}
      SCHEMA.each { |k, v| state[k] = v.dup }
      state
    end

    # File locking for concurrent access
    def with_lock
      FileUtils.mkdir_p(File.dirname(LOCK_FILE))
      File.open(LOCK_FILE, File::RDWR | File::CREAT, 0o644) do |f|
        f.flock(File::LOCK_EX)
        begin
          yield
        ensure
          f.flock(File::LOCK_UN)
        end
      end
    end

    # Merge loaded data with schema defaults (data already has symbol keys from JSON.parse)
    def merge_with_defaults(data)
      SCHEMA.each_with_object({}) do |(section, defaults), state|
        state[section] = data[section] || defaults.dup
      end
    end

    # Convert symbol keys to strings for JSON
    def stringify_keys(hash)
      result = {}
      hash.each do |k, v|
        key = k.to_s
        result[key] = v.is_a?(Hash) ? stringify_keys(v) : v
      end
      result
    end
  end
end

# CLI mode for testing/debugging
if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  options = {}
  OptionParser.new do |opts|
    opts.banner = 'Usage: state_manager.rb [options]'

    opts.on('-d', '--dump', 'Dump full state') { options[:dump] = true }
    opts.on('-g', '--get SECTION', 'Get section') { |s| options[:get] = s }
    opts.on('-r', '--reset SECTION', 'Reset section') { |s| options[:reset] = s }
    opts.on('--reset-all', 'Reset all state') { options[:reset_all] = true }
  end.parse!

  if options[:dump]
    puts StateManager.dump
  elsif options[:get]
    section = options[:get].to_sym
    data = StateManager.get(section)
    puts JSON.pretty_generate(data)
  elsif options[:reset]
    section = options[:reset].to_sym
    StateManager.reset(section)
    puts "Reset: #{section}"
  elsif options[:reset_all]
    StateManager.reset_all
    puts 'Reset all state'
  else
    puts StateManager.dump
  end
end
