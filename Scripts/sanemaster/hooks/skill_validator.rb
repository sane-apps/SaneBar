#!/usr/bin/env ruby
# frozen_string_literal: true

# Skill Validator Hook - validates skill invocations before they run
# Specifically enforces sane-loop exit conditions
#
# PreToolUse hook for Skill - validates before execution
#
# Exit codes:
# - 0: Allow
# - 1: Block (missing exit conditions)

require 'json'

# Read hook input from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
  tool_input = input['tool_input'] || {}
  skill_name = (tool_input['skill'] || '').downcase
  args = tool_input['args'] || ''

  # Only validate sane-loop
  exit 0 unless skill_name.include?('sane-loop')

  # Check for required flags
  has_max_iter = args.include?('--max-iterations')
  has_promise = args.include?('--completion-promise')

  # Check if max-iterations is 0 (unlimited)
  unlimited = args.match(/--max-iterations\s+0(?:\s|$)/)

  if !has_max_iter && !has_promise
    warn ''
    warn '❌ BLOCKED: SaneLoop loop requires an exit condition!'
    warn ''
    warn '   You must provide at least ONE of:'
    warn '     --max-iterations N    (where N > 0)'
    warn "     --completion-promise 'TEXT'"
    warn ''
    warn '   Example:'
    warn '     /sane-loop "Fix bug" --max-iterations 15 --completion-promise "BUG-FIXED"'
    warn ''
    warn '   This prevents infinite loops (learned from 700+ iteration failure).'
    exit 1
  end

  if unlimited && !has_promise
    warn ''
    warn '❌ BLOCKED: --max-iterations 0 (unlimited) requires --completion-promise!'
    warn ''
    warn '   Either:'
    warn '     1. Set --max-iterations to a positive number (10-20 recommended)'
    warn "     2. Add --completion-promise 'TEXT' as exit condition"
    warn ''
    exit 1
  end

  # Warn about high iteration counts
  if (match = args.match(/--max-iterations\s+(\d+)/))
    count = match[1].to_i
    warn "⚠️  WARNING: --max-iterations #{count} is high. 10-20 is recommended." if count > 30
  end

  puts '✅ SaneLoop loop validated: exit conditions present'
rescue JSON::ParserError
  # Not valid JSON, skip validation
  exit 0
end
