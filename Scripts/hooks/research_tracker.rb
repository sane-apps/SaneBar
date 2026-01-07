#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Research Tracker Hook
# ==============================================================================
# Tracks research tool usage AND captures what was found.
# Runs on: WebSearch, WebFetch, mcp__memory__*, mcp__apple-docs__*,
#          mcp__context7__*, mcp__github__*, Read, Grep, Glob
#
# PostToolUse hook - captures tool OUTPUT to verify it was actually used.
#
# Creates .claude/research_findings.jsonl with:
# - What tool was called
# - What was the query/input
# - What was found (summary of output)
# - Timestamp
#
# This provides PROOF that research was done, not just that tools were called.
# ==============================================================================

require 'json'
require 'fileutils'
require_relative 'state_signer'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
FINDINGS_FILE = File.join(PROJECT_DIR, '.claude/research_findings.jsonl')
RESEARCH_PROGRESS_FILE = File.join(PROJECT_DIR, '.claude/research_progress.json')
READ_HISTORY_FILE = File.join(PROJECT_DIR, '.claude/read_history.json')
BYPASS_FILE = File.join(PROJECT_DIR, '.claude/bypass_active.json')

# Skip if bypass active
exit 0 if File.exist?(BYPASS_FILE)

# Category mapping
RESEARCH_CATEGORIES = {
  memory: {
    name: 'Memory',
    matchers: ->(t) { t == 'mcp__memory__read_graph' }
  },
  docs: {
    name: 'API Docs',
    matchers: ->(t) { t.start_with?('mcp__apple-docs__') || t.start_with?('mcp__context7__') }
  },
  web: {
    name: 'Web Search',
    matchers: ->(t) { %w[WebSearch WebFetch].include?(t) }
  },
  local: {
    name: 'Local Codebase',
    matchers: ->(t) { %w[Read Grep Glob].include?(t) }
  },
  github: {
    name: 'GitHub',
    matchers: ->(t) { t.start_with?('mcp__github__') }
  }
}.freeze

def category_for_tool(tool_name)
  RESEARCH_CATEGORIES.each do |cat, config|
    return cat if config[:matchers].call(tool_name)
  end
  nil
end

def summarize_output(output, max_length = 500)
  return '(empty)' if output.nil? || output.empty?

  text = output.to_s
  if text.length > max_length
    text[0...max_length] + "... (#{text.length} chars total)"
  else
    text
  end
end

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
  # Convert symbol keys to strings for JSON
  string_progress = progress.transform_keys(&:to_s).transform_values do |v|
    v.is_a?(Hash) ? v.transform_keys(&:to_s) : v
  end
  StateSigner.write_signed(RESEARCH_PROGRESS_FILE, string_progress)
end

def log_finding(entry)
  FileUtils.mkdir_p(File.dirname(FINDINGS_FILE))
  File.open(FINDINGS_FILE, 'a') { |f| f.puts entry.to_json }
end

# Track files that have been Read (for read-before-edit enforcement)
def track_read_file(file_path)
  return if file_path.nil? || file_path.empty?

  FileUtils.mkdir_p(File.dirname(READ_HISTORY_FILE))
  history = begin
    JSON.parse(File.read(READ_HISTORY_FILE))
  rescue StandardError
    { 'files' => [], 'session_start' => Time.now.iso8601 }
  end

  normalized = File.expand_path(file_path)
  unless history['files'].include?(normalized)
    history['files'] << normalized
    history['last_read'] = Time.now.iso8601
    File.write(READ_HISTORY_FILE, JSON.pretty_generate(history))
  end
end

# Read hook input from stdin
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0
end

tool_name = input['tool_name'] || ''
tool_input = input['tool_input'] || {}
tool_output = input['tool_response'] || input['tool_output'] || ''

# Check if this is a research tool
category = category_for_tool(tool_name)
exit 0 unless category

# Extract meaningful query/input info
query_info = case tool_name
             when 'mcp__memory__read_graph'
               'Full graph read'
             when 'WebSearch'
               tool_input['query']
             when 'WebFetch'
               tool_input['url']
             when 'Read'
               tool_input['file_path']
             when 'Grep'
               "#{tool_input['pattern']} in #{tool_input['path'] || 'project'}"
             when 'Glob'
               tool_input['pattern']
             else
               tool_input.to_s[0..200]
             end

# Count items in output to verify something was actually returned
# VULN-006 FIX: Track both stats AND whether output is meaningful
output_stats = case tool_name
               when 'mcp__memory__read_graph'
                 parsed = JSON.parse(tool_output) rescue {}
                 entities = parsed['entities'] || []
                 "#{entities.length} entities found"
               when 'Grep'
                 lines = tool_output.to_s.lines.count
                 "#{lines} matches"
               when 'Read'
                 lines = tool_output.to_s.lines.count
                 "#{lines} lines read"
               else
                 chars = tool_output.to_s.length
                 "#{chars} chars returned"
               end

# VULN-006 FIX: Validate meaningful output before counting as complete
# Empty or trivial results don't count as "research done"
is_meaningful = case tool_name
                when 'mcp__memory__read_graph'
                  parsed = JSON.parse(tool_output) rescue {}
                  (parsed['entities'] || []).length > 0
                when 'mcp__memory__search_nodes'
                  parsed = JSON.parse(tool_output) rescue {}
                  (parsed['entities'] || []).length > 0
                when 'Grep', 'Glob'
                  tool_output.to_s.lines.count > 0
                when 'Read'
                  tool_output.to_s.length > 100  # At least 100 chars
                when 'WebSearch', 'WebFetch'
                  tool_output.to_s.length > 200  # At least 200 chars
                else
                  tool_output.to_s.length > 50   # Minimum threshold
                end

# Log the finding with proof
finding = {
  timestamp: Time.now.iso8601,
  category: category,
  tool: tool_name,
  query: query_info,
  output_stats: output_stats,
  output_preview: summarize_output(tool_output, 300)
}
log_finding(finding)

# Track Read tool usage for read-before-edit enforcement
if tool_name == 'Read' && is_meaningful
  track_read_file(tool_input['file_path'])
end

# Update research progress (VULN-006 FIX: only if output is meaningful)
progress = load_research_progress
progress[category] ||= {}
unless progress[category][:completed_at]
  if is_meaningful
    progress[category][:completed_at] = Time.now.iso8601
    progress[category][:tool] = tool_name
    progress[category][:query] = query_info
    progress[category][:proof] = output_stats
    save_research_progress(progress)

    # Count completed categories
    done_count = progress.count { |_, v| v[:completed_at] || v[:skipped] }
    remaining = 5 - done_count

    if remaining.zero?
      warn '✅ All 5 research categories complete with documented findings'
    else
      warn "📊 Research: #{done_count}/5 | #{RESEARCH_CATEGORIES[category][:name]} logged: #{output_stats}"
    end
  else
    # Tool called but output was empty/trivial - doesn't count
    warn "⚠️  #{RESEARCH_CATEGORIES[category][:name]}: Empty result - doesn't count. Try a different query."
  end
end

exit 0
