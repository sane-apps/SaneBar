#!/usr/bin/env ruby
# frozen_string_literal: true

# Two-Fix Rule Reminder Hook
# Triggered on PreToolUse for Edit tool to remind about verification-first workflow

require 'json'
require 'fileutils'

# Read hook input from stdin (Claude Code standard)
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end

input['tool_name'] || 'unknown'
tool_input = input['tool_input'] || {}
session_id = input['session_id'] || 'unknown'

# Skip if editing a file in a different project
project_dir = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
current_project = File.basename(project_dir)
file_path = tool_input['file_path'] || ''
if file_path.include?('/Sane') && !file_path.include?("/#{current_project}")
  puts({ 'result' => 'continue' }.to_json)
  exit 0
end

# State file to track edit attempts
state_file = File.join(project_dir, '.claude', 'edit_state.json')
state_dir = File.dirname(state_file)
FileUtils.mkdir_p(state_dir)

# Load state
default_state = { 'edit_count' => 0, 'session' => nil, 'unique_files' => [] }
state = File.exist?(state_file) ? JSON.parse(File.read(state_file)) : default_state

# Reset counter if new session
state = { 'edit_count' => 0, 'session' => session_id, 'unique_files' => [] } if state['session'] != session_id

# Ensure unique_files exists (for backwards compatibility)
state['unique_files'] ||= []

# Increment edit count
state['edit_count'] += 1

# Track unique files edited
normalized_path = File.expand_path(file_path) if file_path && !file_path.empty?
if normalized_path && !state['unique_files'].include?(normalized_path)
  state['unique_files'] << normalized_path
end

# Save state
File.write(state_file, JSON.pretty_generate(state))

# Output reminder every 10 edits - MUST use warn for visibility
if (state['edit_count'] % 10).zero?
  warn ''
  warn '=' * 60
  warn "📋 CHECKPOINT: #{state['edit_count']} edits this session"
  warn '=' * 60
  warn ''
  warn '   Quick self-check:'
  warn '   • What task am I working on?'
  warn '   • Which SOP rules apply here?'
  warn '   • Have I verified my changes work?'
  warn ''
  warn '   Rule #3: Two strikes? Research before guessing again'
  warn '   Rule #6: Build → Kill → Launch → Logs → Confirm'
  warn ''
  warn '=' * 60
  warn ''
end

puts({ 'result' => 'continue' }.to_json)
