#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Unified Logger
# ==============================================================================
# Central logging for all enforcement actions. Writes to JSONL format
# with consistent schema across all log types.
#
# Log files:
#   - .claude/enforcement.jsonl - All enforcement decisions (block/warn/allow)
#   - .claude/audit.jsonl - Tool execution audit trail (existing)
#
# Usage:
#   Logger.log_block(rule:, message:, detector:, details:)
#   Logger.log_warning(rule:, message:, detector:, details:)
#   Logger.log_allow(tool:, context:)
#   Logger.log_tool(tool:, input:, outcome:)
# ==============================================================================

require 'json'
require 'fileutils'

module Logger
  PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
  ENFORCEMENT_LOG = File.join(PROJECT_DIR, '.claude', 'enforcement.jsonl')
  AUDIT_LOG = File.join(PROJECT_DIR, '.claude', 'audit.jsonl')
  MAX_SIZE = 1_000_000  # 1MB rotation threshold

  # Severity levels (consistent with RuleTracker)
  SEVERITY = {
    block: 3,
    warn: 2,
    allow: 1,
    info: 0
  }.freeze

  module_function

  # Log a blocking decision
  def log_block(rule:, message:, detector: nil, details: {})
    write_enforcement(
      type: 'block',
      severity: SEVERITY[:block],
      rule: rule,
      message: message,
      detector: detector,
      details: details
    )
  end

  # Log a warning
  def log_warning(rule:, message:, detector: nil, details: {})
    write_enforcement(
      type: 'warn',
      severity: SEVERITY[:warn],
      rule: rule,
      message: message,
      detector: detector,
      details: details
    )
  end

  # Log an allow decision
  def log_allow(tool:, context: {})
    write_enforcement(
      type: 'allow',
      severity: SEVERITY[:allow],
      rule: nil,
      message: "Allowed: #{tool}",
      detector: nil,
      details: context
    )
  end

  # Log tool execution (audit trail)
  def log_tool(tool:, input: {}, outcome: 'unknown', error: nil)
    entry = {
      timestamp: Time.now.utc.iso8601,
      session_id: ENV['CLAUDE_SESSION_ID'] || 'unknown',
      tool: tool,
      file: extract_file(input),
      outcome: outcome,
      error: error&.slice(0, 100)
    }

    write_jsonl(AUDIT_LOG, entry)
  end

  # Get recent enforcement entries
  def recent_blocks(count: 10)
    read_recent(ENFORCEMENT_LOG, count).select { |e| e['type'] == 'block' }
  end

  # Get enforcement summary
  def summary(since: nil)
    entries = read_all(ENFORCEMENT_LOG)
    entries = entries.select { |e| Time.parse(e['timestamp']) > since } if since

    {
      total: entries.length,
      blocks: entries.count { |e| e['type'] == 'block' },
      warnings: entries.count { |e| e['type'] == 'warn' },
      allows: entries.count { |e| e['type'] == 'allow' },
      by_rule: entries.group_by { |e| e['rule'] }.transform_values(&:length)
    }
  end

  private_class_method

  def self.write_enforcement(type:, severity:, rule:, message:, detector:, details:)
    entry = {
      timestamp: Time.now.utc.iso8601,
      session_id: ENV['CLAUDE_SESSION_ID'] || 'unknown',
      type: type,
      severity: severity,
      rule: rule,
      message: message,
      detector: detector,
      details: details
    }

    write_jsonl(ENFORCEMENT_LOG, entry)
  end

  def self.write_jsonl(file, entry)
    FileUtils.mkdir_p(File.dirname(file))
    rotate_if_needed(file)

    File.open(file, 'a') do |f|
      f.puts(JSON.generate(entry))
    end
  rescue StandardError
    # Never fail on logging errors
  end

  def self.rotate_if_needed(file)
    return unless File.exist?(file) && File.size(file) > MAX_SIZE

    # Keep last half of file
    content = File.read(file)
    lines = content.split("\n")
    keep = lines.last(lines.length / 2)
    File.write(file, keep.join("\n") + "\n")
  rescue StandardError
    # Ignore rotation errors
  end

  def self.read_recent(file, count)
    return [] unless File.exist?(file)

    lines = File.readlines(file).last(count)
    lines.map { |l| JSON.parse(l) rescue nil }.compact
  rescue StandardError
    []
  end

  def self.read_all(file)
    return [] unless File.exist?(file)

    File.readlines(file).map { |l| JSON.parse(l) rescue nil }.compact
  rescue StandardError
    []
  end

  def self.extract_file(input)
    input['file_path'] || input.dig('tool_input', 'file_path')
  end
end
