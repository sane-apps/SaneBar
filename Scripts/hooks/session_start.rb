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
require 'time'
require_relative 'state_signer'

PROJECT_DIR = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
CLAUDE_DIR = File.join(PROJECT_DIR, '.claude')
BREAKER_FILE = File.join(CLAUDE_DIR, 'circuit_breaker.json')
FAILURE_FILE = File.join(CLAUDE_DIR, 'failure_state.json')

# Satisfaction/enforcement state files to clear on fresh session
SATISFACTION_FILE = File.join(CLAUDE_DIR, 'process_satisfaction.json')
RESEARCH_PROGRESS_FILE = File.join(CLAUDE_DIR, 'research_progress.json')
REQUIREMENTS_FILE = File.join(CLAUDE_DIR, 'prompt_requirements.json')
SANELOOP_STATE_FILE = File.join(CLAUDE_DIR, 'saneloop-state.json')
SANELOOP_ARCHIVE_DIR = File.join(CLAUDE_DIR, 'saneloop-archive')
EDIT_STATE_FILE = File.join(CLAUDE_DIR, 'edit_state.json')
SUMMARY_VALIDATED_FILE = File.join(CLAUDE_DIR, 'summary_validated.json')

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
  # VULN-007 FIX: Do NOT auto-reset tripped breaker
  # A tripped breaker indicates repeated failures that need human review
  # Claude should not be able to bypass by starting a new session

  # VULN-003 FIX: Use signed state files
  breaker = StateSigner.read_verified(BREAKER_FILE)

  if breaker && breaker['tripped']
    # Mark that reset is pending user approval
    breaker['pending_user_reset'] = true
    breaker['session_started_while_tripped'] = Time.now.utc.iso8601
    StateSigner.write_signed(BREAKER_FILE, breaker)

    # Warn user - breaker stays tripped
    warn ''
    warn '🔴 CIRCUIT BREAKER STILL TRIPPED'
    warn "   Tripped at: #{breaker['tripped_at']}"
    warn "   Reason: #{breaker['trip_reason']}"
    warn ''
    warn '   Say "reset breaker" or "approve breaker reset" to clear.'
    warn '   This prevents Claude from bypassing failures by restarting.'
    warn ''
    return # Don't reset failure tracking either
  end

  # Only reset failure tracking if breaker is NOT tripped
  if File.exist?(FAILURE_FILE)
    File.delete(FAILURE_FILE)
  end
end

def find_sop_file
  candidates = %w[DEVELOPMENT.md CONTRIBUTING.md SOP.md docs/SOP.md]
  candidates.find { |f| File.exist?(File.join(PROJECT_DIR, f)) }
end

# Clear stale satisfaction from previous sessions
# New session = fresh slate, must re-earn compliance
def clear_stale_satisfaction
  # Silently clear stale files - this is routine cleanup, not an error
  [SATISFACTION_FILE, RESEARCH_PROGRESS_FILE, REQUIREMENTS_FILE,
   EDIT_STATE_FILE, SUMMARY_VALIDATED_FILE].each do |file|
    File.delete(file) if File.exist?(file)
  end
end

# Detect and handle SaneLoop from previous session
# User requirement: saneloops do NOT persist across sessions - always archive
def handle_stale_saneloop
  return unless File.exist?(SANELOOP_STATE_FILE)

  state = JSON.parse(File.read(SANELOOP_STATE_FILE), symbolize_names: true)
  return unless state[:active]

  started_at = Time.parse(state[:started_at]) rescue nil
  hours_old = started_at ? ((Time.now - started_at) / 3600.0).round(1) : 0

  # Archive ANY saneloop from previous session - no persistence allowed
  FileUtils.mkdir_p(SANELOOP_ARCHIVE_DIR)
  task_slug = (state[:task] || 'unknown').gsub(/[^a-zA-Z0-9]+/, '_')[0..30]
  archive_name = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_SESSION_END_#{task_slug}.json"
  archive_path = File.join(SANELOOP_ARCHIVE_DIR, archive_name)

  state[:archived_at] = Time.now.iso8601
  state[:completed] = false
  state[:completion_note] = "SESSION ENDED: Archived on new session start (was #{hours_old}h old)"
  File.write(archive_path, JSON.pretty_generate(state))
  File.delete(SANELOOP_STATE_FILE)

  warn ''
  warn '⚠️  PREVIOUS SESSION SANELOOP ARCHIVED'
  warn "   Task: #{state[:task]}"
  warn "   Age: #{hours_old} hours"
  warn "   Status: Never completed (session ended)"
  warn ''
  warn '   SaneLoops do not persist across sessions.'
  warn '   Start fresh: ./Scripts/SaneMaster.rb saneloop start "Task" --promise "Done"'
  warn ''
rescue StandardError => e
  warn "⚠️  Error checking SaneLoop state: #{e.message}"
end

def output_session_context
  # Only warn if there's an actual problem (no SOP)
  sop_file = find_sop_file
  unless sop_file
    warn '⚠️  No SOP file found (DEVELOPMENT.md, CONTRIBUTING.md)'
  end

  # Check memory health - only warns if bloat detected
  check_memory_health
end

# Check for pending MCP actions that need resolution
MEMORY_STAGING_FILE = File.join(CLAUDE_DIR, 'memory_staging.json')

def check_pending_mcp_actions
  pending = []

  # Check memory staging
  if File.exist?(MEMORY_STAGING_FILE)
    begin
      staging = JSON.parse(File.read(MEMORY_STAGING_FILE))
      if staging['needs_memory_update']
        pending << {
          type: 'memory_staging',
          message: "Memory staging needs saving: #{staging['suggested_entity']&.dig('name') || 'learnings'}",
          action: 'Call mcp__memory__create_entities then delete memory_staging.json'
        }
      end
    rescue StandardError
      # Ignore parse errors
    end
  end

  if pending.any?
    warn ''
    warn '🚨 PENDING MCP ACTIONS - MUST RESOLVE BEFORE WORK'
    warn ''
    pending.each do |p|
      warn "   ⚠️  #{p[:message]}"
      warn "      Action: #{p[:action]}"
    end
    warn ''
    warn '   EDITS WILL BE BLOCKED until these are resolved.'
    warn ''
  end

  pending
end

# Memory health check on cached data
# Thresholds match memory.rb: 60 entities, 8000 tokens
ENTITY_WARN = 40  # Lower threshold for early warning
TOKEN_WARN = 6000

def check_memory_health
  memory_file = File.join(CLAUDE_DIR, 'memory.json')

  # Silent if no memory file - not an error condition
  return unless File.exist?(memory_file)

  begin
    memory = JSON.parse(File.read(memory_file))
    entities = memory['entities'] || []
    entity_count = entities.count

    # Estimate tokens (~4 chars per token)
    est_tokens = (File.size(memory_file) / 4.0).round

    # Check for verbose entities (>15 observations each)
    verbose = entities.count { |e| (e['observations'] || []).count > 15 }

    # Only warn if bloat detected - routine status goes to JSON context
    if entity_count > ENTITY_WARN || est_tokens > TOKEN_WARN || verbose > 3
      warn '⚠️  MEMORY BLOAT DETECTED'
      warn "   Entities: #{entity_count}/#{ENTITY_WARN} | Tokens: ~#{est_tokens}/#{TOKEN_WARN}"
      warn "   Verbose entities (>15 obs): #{verbose}" if verbose > 0
      warn '   Run: ./Scripts/SaneMaster.rb mh        # Full health report'
      warn '   Run: ./Scripts/SaneMaster.rb mcompact  # Trim verbose entities'
    end
  rescue StandardError
    # Silent on parse errors - not critical
  end
end

# === MCP VERIFICATION SYSTEM ===
# Reset verification for new session and prompt Claude to verify MCPs

MCP_VERIFICATION_TOOLS = {
  memory: 'mcp__memory__read_graph',
  apple_docs: 'mcp__apple-docs__search_apple_docs',
  context7: 'mcp__context7__resolve-library-id',
  github: 'mcp__github__search_repositories'
}.freeze

def reset_mcp_verification
  require_relative 'core/state_manager'

  # Reset verification flag for new session (MCPs must re-verify)
  StateManager.update(:mcp_health) do |health|
    health[:verified_this_session] = false
    # Keep historical data but reset per-session verification
    health[:mcps].each do |_mcp, data|
      data[:verified] = false if data.is_a?(Hash)
    end
    health
  end
rescue StandardError => e
  warn "⚠️  Could not reset MCP verification: #{e.message}"
end

def show_mcp_verification_status
  require_relative 'core/state_manager'

  health = StateManager.get(:mcp_health)
  mcps = health[:mcps] || {}

  # Check for any previous failures
  failures = mcps.select { |_, data| data.is_a?(Hash) && data[:failure_count].to_i > 0 }

  # Only warn if there were previous MCP failures - otherwise silent
  # The enforcement still happens via PreToolUse hook, we just don't spam stderr
  if failures.any?
    warn '⚠️  MCPs with previous failures (verify before editing):'
    failures.each do |mcp, data|
      warn "   #{mcp}: #{data[:failure_count]} failures"
    end
  end
end

# Debug logging for troubleshooting startup issues
DEBUG_LOG = File.join(CLAUDE_DIR, 'session_start_debug.log')

def log_debug(msg)
  File.open(DEBUG_LOG, 'a') { |f| f.puts "[#{Time.now.iso8601}] #{msg}" }
rescue StandardError
  # Ignore logging errors
end

# Build context for Claude (injected via stdout JSON)
def build_session_context
  require_relative 'core/state_manager'

  context_parts = []
  project_name = File.basename(PROJECT_DIR)
  sop_file = find_sop_file

  context_parts << "# [SaneProcess] Session Started"
  context_parts << "Project: #{project_name}"
  context_parts << "SOP: #{sop_file}" if sop_file

  # Pattern rules count
  rules_dir = File.join(CLAUDE_DIR, 'rules')
  if Dir.exist?(rules_dir)
    rule_count = Dir.glob(File.join(rules_dir, '*.md')).count
    context_parts << "Pattern rules: #{rule_count} loaded" if rule_count.positive?
  end

  # Memory status
  memory_file = File.join(CLAUDE_DIR, 'memory.json')
  if File.exist?(memory_file)
    begin
      memory = JSON.parse(File.read(memory_file))
      entities = memory['entities'] || []
      est_tokens = (File.size(memory_file) / 4.0).round
      context_parts << "Memory: #{entities.count} entities (~#{est_tokens} tokens)"
    rescue StandardError
      # Ignore
    end
  end

  # MCP verification reminder (enforcement happens in PreToolUse)
  health = StateManager.get(:mcp_health) rescue {}
  unless health.dig(:verified_this_session)
    context_parts << ""
    context_parts << "MCP verification: Required before editing"
    context_parts << "Verify by calling: memory read_graph, apple-docs search, context7 resolve, github search"
  end

  context_parts.join("\n")
end

# Main execution
begin
  log_debug "Starting session_start hook"
  ensure_claude_dir
  log_debug "ensure_claude_dir done"
  reset_session_state
  log_debug "reset_session_state done"
  clear_stale_satisfaction
  log_debug "clear_stale_satisfaction done"
  handle_stale_saneloop
  log_debug "handle_stale_saneloop done"
  reset_mcp_verification      # Reset MCP verification for new session
  log_debug "reset_mcp_verification done"
  output_session_context      # User-facing messages to stderr
  log_debug "output_session_context done"
  check_pending_mcp_actions   # Alert user to pending actions
  log_debug "check_pending_mcp_actions done"
  show_mcp_verification_status # Show MCP status and prompt
  log_debug "show_mcp_verification_status done"

  # Output JSON to stdout for Claude Code to inject into context
  # Must use hookSpecificOutput format for SessionStart hooks
  result = {
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: build_session_context
    }
  }
  puts JSON.generate(result)
  log_debug "JSON output written - SUCCESS"
rescue StandardError => e
  log_debug "ERROR: #{e.class}: #{e.message}"
  log_debug e.backtrace&.first(5)&.join("\n") || "No backtrace"
  warn "⚠️  Session start error: #{e.message}"
  # Still output valid JSON even on error so Claude Code doesn't show "error"
  puts JSON.generate({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: "Session start encountered an error: #{e.message}"
    }
  })
end

exit 0
