#!/usr/bin/env ruby
# frozen_string_literal: true

# Two-Fix Rule Reminder Hook
# Triggered on PreToolUse for Edit tool to remind about verification-first workflow

require 'json'
require 'fileutils'

# Read hook input from stdin
input = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end
input['tool_name'] || 'unknown'
session_id = input['session_id'] || 'unknown'

# State file to track edit attempts
state_file = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'edit_state.json')
state_dir = File.dirname(state_file)
FileUtils.mkdir_p(state_dir)

# Load state
state = File.exist?(state_file) ? JSON.parse(File.read(state_file)) : { 'edit_count' => 0, 'session' => nil }

# Reset counter if new session
state = { 'edit_count' => 0, 'session' => session_id } if state['session'] != session_id

# Increment edit count
state['edit_count'] += 1

# Save state
File.write(state_file, JSON.pretty_generate(state))

# Output reminder every 5 edits
output = if (state['edit_count'] % 5).zero?
           {
             'result' => 'continue',
             'message' => "Reminder: You've made #{state['edit_count']} edits this session. Remember: Verify before coding, Two-Fix Rule applies."
           }
         else
           { 'result' => 'continue' }
         end

puts output.to_json
