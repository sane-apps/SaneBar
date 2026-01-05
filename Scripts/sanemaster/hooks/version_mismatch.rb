#!/usr/bin/env ruby
# frozen_string_literal: true

# Version Mismatch Detection Hook
#
# Prevents BUG-008: Building to one path but launching from another.
#
# Plain English: If you build with a custom derivedDataPath (like ./build),
# then launch with your project tool (which uses DerivedData), you'll run the OLD
# version and think your changes work when they don't.
#
# This hook tracks the last build path and warns if launch uses a different one.

require 'json'
require 'fileutils'

STATE_FILE = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude', 'build_state.json')

def load_state
  return {} unless File.exist?(STATE_FILE)
  JSON.parse(File.read(STATE_FILE))
rescue StandardError
  {}
end

def save_state(state)
  FileUtils.mkdir_p(File.dirname(STATE_FILE))
  File.write(STATE_FILE, JSON.pretty_generate(state))
end

# Read tool input from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError
  exit 0
end

tool_name = input['tool_name']
tool_input = input['tool_input'] || {}

exit 0 unless tool_name == 'Bash'

command = tool_input['command'] || ''
state = load_state

# Detect build commands with custom derivedDataPath
if command.match?(/xcodebuild.*build/) && command.match?(/-derivedDataPath\s+(\S+)/)
  custom_path = command.match(/-derivedDataPath\s+(\S+)/)[1]
  state['last_build_path'] = custom_path
  state['last_build_time'] = Time.now.to_s
  state['used_custom_path'] = true
  save_state(state)
  exit 0
end

# Detect project tool launch (uses DerivedData by default)
if command.match?(/Scripts.*\s+(launch|test_mode|run)/)
  if state['used_custom_path'] && state['last_build_path']
    warn <<~WARNING

      ========================================
      VERSION MISMATCH WARNING
      ========================================

      Last build used custom path: #{state['last_build_path']}
      But your launch command uses: DerivedData

      These are DIFFERENT binaries!

      To fix:
        1. Use your project's verify command (uses DerivedData)
        2. Or: open "#{state['last_build_path']}/Build/Products/Debug/*.app"

      ========================================

    WARNING
    # Reset state after warning
    state['used_custom_path'] = false
    save_state(state)
  end
  exit 0
end

# Detect raw open command with custom build path
if command.match?(/open\s+.*\.app/) && state['used_custom_path']
  # Check if opening from the same path that was built
  if command.include?(state['last_build_path'].to_s)
    # Good - launching from same path
    state['used_custom_path'] = false
    save_state(state)
  end
  exit 0
end

exit 0
