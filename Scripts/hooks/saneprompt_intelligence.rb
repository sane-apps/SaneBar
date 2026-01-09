#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SanePrompt Intelligence Module
# ==============================================================================
# Pattern learning, memory staging, frustration detection - extracted from
# saneprompt.rb per Rule #10 (file size limits).
#
# Usage:
#   require_relative 'saneprompt_intelligence'
#   include SanePromptIntelligence
# ==============================================================================

require 'json'
require 'fileutils'
require 'time'
require_relative 'core/state_manager'

module SanePromptIntelligence
  MEMORY_STAGING_FILE = File.expand_path('../../.claude/memory_staging.json', __dir__)

  # === FRUSTRATION DETECTION ===

  FRUSTRATION_PATTERNS = {
    correction: [/^no[,.]?\s/i, /that'?s not/i, /I said/i, /I meant/i, /I already/i],
    impatience: [/use your head/i, /\bthink\b/i, /stop rushing/i, /\bidiot\b/i],
    repetition: [/I just said/i, /like I said/i, /as I mentioned/i, /again/i]
  }.freeze

  def detect_frustration(prompt)
    frustrations = []

    FRUSTRATION_PATTERNS.each do |type, patterns|
      patterns.each do |pattern|
        if prompt.match?(pattern)
          frustrations << { type: type, pattern: pattern.source }
          break  # One match per type is enough
        end
      end
    end

    frustrations
  end

  def learn_from_frustration(prompt, frustrations)
    return if frustrations.empty?

    StateManager.update(:requirements) do |reqs|
      reqs[:frustration_count] = (reqs[:frustration_count] || 0) + 1
      reqs
    end

    # Get recent actions for correlation
    action_log = StateManager.get(:action_log) || []
    recent_actions = action_log.last(3)

    learning = {
      type: frustrations.first[:type],
      pattern: frustrations.first[:pattern],
      recent_actions: recent_actions.map { |a| a[:tool] rescue a['tool'] },
      prompt_fragment: prompt.slice(0, 100),
      timestamp: Time.now.iso8601
    }

    # Store locally for session use
    StateManager.update(:learnings) do |learnings|
      learnings ||= []
      learnings << learning
      learnings.last(50)  # Keep last 50 learnings
    end

    # Log for analysis
    log_learning(learning)
  rescue StandardError
    # Don't fail on learning errors
  end

  def log_learning(learning)
    learnings_file = File.expand_path('../../.claude/learnings.jsonl', __dir__)
    FileUtils.mkdir_p(File.dirname(learnings_file))
    File.open(learnings_file, 'a') { |f| f.puts(learning.to_json) }
  rescue StandardError
    # Don't fail on logging errors
  end

  def check_past_learnings
    learnings = StateManager.get(:learnings) || []
    return nil if learnings.empty?

    # Check if we have recent repeated corrections
    recent = learnings.last(5)
    correction_count = recent.count { |l| l[:type] == :correction || l['type'] == 'correction' }

    if correction_count >= 3
      return "PATTERN: #{correction_count} corrections in recent prompts. Read user message carefully."
    end

    nil
  end

  # === PATTERN DISPLAY ===

  def get_learned_patterns
    patterns = StateManager.get(:patterns)
    return nil unless patterns

    result = { weak_spots: [], triggers: [], strengths: [], score_trend: nil }

    # Weak spots: rules frequently violated
    weak_spots = patterns[:weak_spots] || patterns['weak_spots'] || {}
    weak_spots.each do |rule, count|
      result[:weak_spots] << { rule: rule, count: count } if count.to_i >= 2
    end
    result[:weak_spots].sort_by! { |w| -w[:count] }

    # Learned triggers: words that predict violations
    triggers = patterns[:triggers] || patterns['triggers'] || {}
    triggers.each do |word, rules|
      next if rules.nil? || rules.empty?
      result[:triggers] << { word: word, rules: rules }
    end

    # Strengths: rules with 100% compliance
    result[:strengths] = patterns[:strengths] || patterns['strengths'] || []

    # Session scores: detect trend
    scores = patterns[:session_scores] || patterns['session_scores'] || []
    if scores.length >= 3
      recent_avg = scores.last(3).sum.to_f / 3
      earlier_avg = scores.first(3).sum.to_f / 3
      if recent_avg < earlier_avg - 1
        result[:score_trend] = :declining
      elsif recent_avg > earlier_avg + 1
        result[:score_trend] = :improving
      end
    end

    # Return nil if nothing to show
    return nil if result[:weak_spots].empty? && result[:triggers].empty? &&
                  result[:strengths].empty? && result[:score_trend].nil?

    result
  end

  def format_patterns_for_claude(patterns)
    return nil unless patterns

    lines = []
    lines << 'LEARNED PATTERNS FROM PREVIOUS SESSIONS:'

    if patterns[:weak_spots].any?
      lines << ''
      lines << 'WEAK SPOTS (rules frequently violated):'
      patterns[:weak_spots].first(3).each do |ws|
        lines << "  Rule #{ws[:rule]}: #{ws[:count]} violations - EXTRA ATTENTION NEEDED"
      end
    end

    if patterns[:triggers].any?
      lines << ''
      lines << 'TRIGGER WORDS (predict violations):'
      patterns[:triggers].first(5).each do |t|
        lines << "  \"#{t[:word]}\" -> often leads to #{t[:rules].join(', ')} violations"
      end
    end

    if patterns[:strengths].any?
      lines << ''
      lines << "STRENGTHS: #{patterns[:strengths].join(', ')} - consistent compliance"
    end

    if patterns[:score_trend] == :declining
      lines << ''
      lines << 'TREND: SOP scores declining - slow down, follow process'
    elsif patterns[:score_trend] == :improving
      lines << ''
      lines << 'TREND: SOP scores improving - keep it up'
    end

    lines.join("\n")
  end

  def format_patterns_for_user(patterns)
    return nil unless patterns

    lines = []

    if patterns[:weak_spots].any?
      weak_rules = patterns[:weak_spots].map { |ws| ws[:rule] }.first(3).join(', ')
      lines << "Weak spots: #{weak_rules}"
    end

    if patterns[:score_trend] == :declining
      lines << 'Trend: declining'
    end

    return nil if lines.empty?
    lines.join(' | ')
  end

  # === MEMORY MCP INTEGRATION ===
  # Check for staged learnings from previous session's sanestop.rb

  def check_memory_staging
    return nil unless File.exist?(MEMORY_STAGING_FILE)

    staging = JSON.parse(File.read(MEMORY_STAGING_FILE)) rescue nil
    return nil unless staging && staging['needs_memory_update']

    staging
  end

  def format_memory_staging_context(staging)
    return nil unless staging

    entity = staging['suggested_entity']
    return nil unless entity

    lines = []
    lines << 'MEMORY MCP UPDATE NEEDED:'
    lines << ''
    lines << 'Previous session staged high-value learnings. Save to Memory MCP:'
    lines << ''
    lines << "Entity: #{entity['name']}"
    lines << "Type: #{entity['type']}"
    lines << 'Observations:'
    entity['observations'].each { |obs| lines << "  - #{obs}" }
    lines << ''
    lines << 'ACTION REQUIRED: Call mcp__memory__create_entities or mcp__memory__add_observations'
    lines << "Then delete: #{MEMORY_STAGING_FILE}"

    lines.join("\n")
  end

  def mark_memory_staging_processed
    return unless File.exist?(MEMORY_STAGING_FILE)

    # Mark as processed (don't delete - Claude will delete after saving)
    staging = JSON.parse(File.read(MEMORY_STAGING_FILE)) rescue nil
    return unless staging

    staging['needs_memory_update'] = false
    staging['processed_at'] = Time.now.iso8601
    File.write(MEMORY_STAGING_FILE, JSON.pretty_generate(staging))
  rescue StandardError
    # Don't fail on staging errors
  end
end
