#!/usr/bin/env ruby
# frozen_string_literal: true

# Session Start Hook - Bootstraps the .claude/ directory for a new session
#
# Actions:
# - Creates .claude/ directory if missing
# - Resets circuit breaker state (fresh session = fresh start)
# - Cleans up stale failure tracking
# - Outputs session context reminder
#
# This is a SessionStart hook that runs once when Claude Code starts.
#
# Exit codes:
# - 0: Always (bootstrap should never fail)

require 'json'
require 'fileutils'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
CLAUDE_DIR = File.join(PROJECT_DIR, '.claude')
BREAKER_FILE = File.join(CLAUDE_DIR, 'circuit_breaker.json')
FAILURE_FILE = File.join(CLAUDE_DIR, 'failure_state.json')

def ensure_claude_dir
  FileUtils.mkdir_p(CLAUDE_DIR)

  # Create .gitignore if missing
  gitignore = File.join(CLAUDE_DIR, '.gitignore')
  unless File.exist?(gitignore)
    File.write(gitignore, <<~GITIGNORE)
      # Claude Code state files (session-specific, don't commit)
      circuit_breaker.json
      failure_state.json
      audit.jsonl

      # Keep rules and settings
      !rules/
      !settings.json
    GITIGNORE
  end
end

def reset_session_state
  # Reset circuit breaker for new session
  if File.exist?(BREAKER_FILE)
    breaker = JSON.parse(File.read(BREAKER_FILE))

    # Only reset if it was tripped - preserve threshold settings
    if breaker['tripped']
      breaker['failures'] = 0
      breaker['tripped'] = false
      breaker['tripped_at'] = nil
      breaker['trip_reason'] = nil
      breaker['reset_at'] = Time.now.utc.iso8601
      breaker['reset_reason'] = 'new_session'
      File.write(BREAKER_FILE, JSON.pretty_generate(breaker))
    end
  end

  # Reset failure tracking
  if File.exist?(FAILURE_FILE)
    File.delete(FAILURE_FILE)
  end
end

def find_sop_file
  candidates = %w[DEVELOPMENT.md CONTRIBUTING.md SOP.md docs/SOP.md]
  candidates.find { |f| File.exist?(File.join(PROJECT_DIR, f)) }
end

def output_session_context
  project_name = File.basename(PROJECT_DIR)
  sop_file = find_sop_file

  warn ''
  warn "✅ #{project_name} session started"

  if sop_file
    warn "📋 SOP: #{sop_file}"
  else
    warn '⚠️  No SOP file found (DEVELOPMENT.md, CONTRIBUTING.md)'
  end

  # Check for pattern rules
  rules_dir = File.join(CLAUDE_DIR, 'rules')
  if Dir.exist?(rules_dir)
    rule_count = Dir.glob(File.join(rules_dir, '*.md')).count
    warn "📁 Pattern rules: #{rule_count} loaded" if rule_count.positive?
  end

  # Check for memory file and remind to load
  memory_file = File.join(CLAUDE_DIR, 'memory.json')
  if File.exist?(memory_file)
    warn '🧠 Memory available - run mcp__memory__read_graph at session start'
  end

  warn ''
end

# Main execution
begin
  ensure_claude_dir
  reset_session_state
  output_session_context
rescue StandardError => e
  warn "⚠️  Session start error: #{e.message}"
end

exit 0
