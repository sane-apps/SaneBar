#!/usr/bin/env ruby
# frozen_string_literal: true

# Failure Tracking Hook
# Tracks consecutive failures and enforces Two-Fix Rule escalation

require 'json'
require 'fileutils'

# Read hook input from stdin
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end
tool_name = input['tool_name'] || 'unknown'
tool_input = input['tool_input'] || {}
tool_output = input['tool_output'] || ''
session_id = input['session_id'] || 'unknown'

# Skip if command is for a different project
project_dir = ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd
current_project = File.basename(project_dir)
command = tool_input['command'] || ''
if command.include?('/Sane') && !command.include?("/#{current_project}")
  puts({ 'result' => 'continue' }.to_json)
  exit 0
end

# State file for failure tracking
state_file = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'failure_state.json')
state_dir = File.dirname(state_file)
FileUtils.mkdir_p(state_dir)

# Load state
state = begin
  File.exist?(state_file) ? JSON.parse(File.read(state_file)) : default_state
rescue StandardError
  default_state
end

def default_state
  { 'consecutive_failures' => 0, 'last_failure_tool' => nil, 'session' => nil, 'escalated' => false }
end

# Reset if new session
state = default_state if state['session'] != session_id
state['session'] = session_id

# Detect failure patterns
failure_patterns = [
  /error:/i,
  /failed/i,
  /FAIL/,
  /cannot find/i,
  /no such file/i,
  /undefined/i,
  /not found/i,
  /compile error/i,
  /build failed/i
]

is_failure = failure_patterns.any? { |pattern| tool_output.match?(pattern) }

if is_failure
  state['consecutive_failures'] += 1
  state['last_failure_tool'] = tool_name

  # Enforce Two-Fix Rule
  if state['consecutive_failures'] >= 2 && !state['escalated']
    state['escalated'] = true
    File.write(state_file, JSON.pretty_generate(state))

    msg = "TWO-FIX RULE: #{state['consecutive_failures']} failures. " \
          'STOP GUESSING. Look up docs/SDK/source before next fix.'
    output = { 'result' => 'continue', 'message' => msg }
    puts output.to_json
    exit 0
  end
else
  # Success - reset counter
  state['consecutive_failures'] = 0
  state['escalated'] = false
end

# Save state
File.write(state_file, JSON.pretty_generate(state))

puts({ 'result' => 'continue' }.to_json)
