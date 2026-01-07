#!/usr/bin/env ruby
# frozen_string_literal: true

# Path Rules Hook - Shows context-specific rules when editing files
#
# Reads file path from Edit/Write tool input, matches against pattern rules,
# and outputs reminders for the applicable rules.
#
# Rules live in .claude/rules/*.md with patterns in the header.

require 'json'

# Use project dir from env, fall back to pwd
PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
RULES_DIR = File.join(PROJECT_DIR, '.claude', 'rules')

# Pattern matching for file paths
PATTERN_RULES = {
  # Tests
  %w[**/Tests/**/*.swift **/Specs/**/*.swift **/*Tests.swift **/*Spec.swift] => 'tests.md',
  # Views
  %w[**/Views/**/*.swift **/UI/**/*.swift **/*View.swift] => 'views.md',
  # Services
  %w[**/Services/**/*.swift **/*Service.swift **/*Manager.swift] => 'services.md',
  # Models
  %w[**/Models/**/*.swift **/*Model.swift **/Core/**/*.swift **/Domain/**/*.swift] => 'models.md',
  # Scripts
  %w[**/Scripts/**/*.rb **/scripts/**/*.rb **/*_hook.rb **/*_validator.rb] => 'scripts.md',
  # Hooks
  %w[**/hooks/**/*.rb] => 'hooks.md'
}.freeze

def match_patterns(file_path, patterns)
  patterns.any? do |pattern|
    File.fnmatch(pattern, file_path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
  end
end

def find_matching_rules(file_path)
  matched = []
  PATTERN_RULES.each do |patterns, rule_file|
    if match_patterns(file_path, patterns)
      rule_path = File.join(RULES_DIR, rule_file)
      matched << rule_path if File.exist?(rule_path)
    end
  end
  matched
end

def extract_summary(rule_path)
  content = File.read(rule_path)
  lines = content.lines

  # Get title (first # line)
  title = lines.find { |l| l.start_with?('# ') }&.strip&.sub(/^# /, '') || 'Rules'

  # Get requirements section
  in_requirements = false
  requirements = []

  lines.each do |line|
    if line.match?(/^## Requirements/)
      in_requirements = true
      next
    end

    break if in_requirements && line.match?(/^## /)

    if in_requirements && line.match?(/^\d+\.\s/)
      # Extract just the bold part
      if (match = line.match(/\*\*(.+?)\*\*/))
        requirements << match[1]
      end
    end
  end

  { title: title, requirements: requirements }
end

def main
  # Read tool input from stdin
  input = JSON.parse($stdin.read) rescue {}
  tool_name = input['tool_name'] || ''

  # Only check for Edit and Write tools
  return unless %w[Edit Write].include?(tool_name)

  file_path = input.dig('tool_input', 'file_path') || ''
  return if file_path.empty?

  # Only check Swift and Ruby files
  return unless file_path.end_with?('.swift') || file_path.end_with?('.rb')

  # Find matching rules
  matched_rules = find_matching_rules(file_path)
  return if matched_rules.empty?

  # Output summary
  matched_rules.each do |rule_path|
    summary = extract_summary(rule_path)
    next if summary[:requirements].empty?

    warn "\n📋 #{summary[:title]}"
    summary[:requirements].each { |r| warn "   • #{r}" }
  end
  warn ''
end

main if __FILE__ == $PROGRAM_NAME
