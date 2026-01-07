# frozen_string_literal: true

# ==============================================================================
# Shortcut Detectors
# ==============================================================================
# Helper module for detecting Claude trying to bypass processes.
# Extracted from process_enforcer.rb to keep file under 800 lines.
# ==============================================================================

module ShortcutDetectors
  # Table detection regex patterns (built at runtime to avoid hook false positives)
  TABLE_HEADER_SEP = Regexp.new('\|[-:]+\|')
  TABLE_ROW = Regexp.new('\|.*\|.*\|')

  module_function

  def detect_casual_self_rating(content)
    casual_patterns = [
      /Self-Rating:\s*\d+\/10/i,
      /Rating:\s*\d+\/10/i,
      /\*\*Self-rating:\s*\d+\/10\*\*/i,
      /My rating:\s*\d+\/10/i
    ]

    proper_format = content.include?('SOP Compliance:') && content.include?('Performance:')
    casual_patterns.any? { |p| content.match?(p) } && !proper_format
  end

  def detect_lazy_commit(command)
    return false unless command.match?(/git commit/i)

    has_status = command.include?('status')
    has_diff = command.include?('diff')
    command.match?(/git commit\s+-m/i) && !has_status && !has_diff
  end

  def detect_bash_file_write(command)
    file_write_patterns = [
      />(?!&)/,
      />>/,
      /\bsed\s+(-[a-zA-Z]*i|-i)/,
      /\btee\b/,
      /\bcat\s*>(?!&)/,
      /<<\s*['"]?EOF/i,
      /\bdd\b.*\bof=/,
      /\bcp\b.*[^|]$/,
      /\bmv\b.*[^|]$/,
      /\btouch\b/,
      /\binstall\b.*-[a-zA-Z]*[mM]/
    ]

    safe_patterns = [
      /\/dev\/null/,
      /\bgit\b/,
      /\|.*>/
    ]

    return false if safe_patterns.any? { |p| command.match?(p) }

    file_write_patterns.any? { |p| command.match?(p) }
  end

  def detect_bash_table_bypass(command)
    return false unless command.match?(/\bsed\b|\becho\b|>>|>/)

    TABLE_HEADER_SEP.match?(command) || TABLE_ROW.match?(command)
  end

  def detect_bash_size_bypass(command)
    return nil unless command.match?(/\bsed\s+(-[a-zA-Z]*i|-i)/)

    file_match = command.match(/sed\s+(?:-[a-zA-Z]*i|-i)\s+(?:''|"")?\s*'[^']*'\s+(.+)$/)
    file_match ||= command.match(/sed\s+(?:-[a-zA-Z]*i|-i)\s+(?:''|"")?\s*"[^"]*"\s+(.+)$/)
    return nil unless file_match

    file_path = file_match[1].strip.gsub(/['"]/, '')
    return nil unless File.exist?(file_path)

    line_count = File.readlines(file_path).count
    is_markdown = file_path.end_with?('.md')
    limit = is_markdown ? 1500 : 800

    return { file: file_path, lines: line_count, limit: limit } if line_count > limit

    nil
  end

  def detect_skipped_verification(content, _tool_name)
    done_patterns = [
      /\bdone\b/i,
      /\bcomplete\b/i,
      /\bfinished\b/i,
      /\ball set\b/i,
      /\bthat'?s it\b/i
    ]

    return false unless done_patterns.any? { |p| content.match?(p) }
    return false unless File.exist?('.claude/audit.jsonl')

    recent_calls = File.readlines('.claude/audit.jsonl').last(10)
    recent_calls.any? { |line| line.include?('verify') || line.include?('qa.rb') }
  rescue StandardError
    false
  end
end
