#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Realistic Flow Test - Simulates actual Claude behavior patterns
# ==============================================================================
# Tests the hooks against REAL failure modes:
#   1. Claude ignores prompt, jumps straight to editing
#   2. Claude does research wrong (partial/incomplete)
#   3. Claude leaves requirements blank
#   4. Claude finally does it right
# ==============================================================================

require 'json'
require 'open3'
require 'fileutils'

# Paths
HOOKS_DIR = File.expand_path('..', __dir__)
STATE_FILE = File.expand_path('../../.claude/state.json', HOOKS_DIR)
SANEPROMPT = File.join(HOOKS_DIR, 'saneprompt.rb')
SANETOOLS = File.join(HOOKS_DIR, 'sanetools.rb')
SANETRACK = File.join(HOOKS_DIR, 'sanetrack.rb')
SANESTOP = File.join(HOOKS_DIR, 'sanestop.rb')

# Colors
RED = "\e[31m"
GREEN = "\e[32m"
YELLOW = "\e[33m"
BLUE = "\e[34m"
RESET = "\e[0m"

def reset_state!
  # Backup existing state
  if File.exist?(STATE_FILE)
    FileUtils.cp(STATE_FILE, "#{STATE_FILE}.backup")
  end

  # Create fresh state
  fresh_state = {
    'research' => {
      'memory' => false,
      'docs' => false,
      'web' => false,
      'github' => false,
      'local' => false
    },
    'requirements' => {
      'requested' => [],
      'satisfied' => []
    },
    'failures' => [],
    'tool_calls' => []
  }

  FileUtils.mkdir_p(File.dirname(STATE_FILE))
  File.write(STATE_FILE, JSON.pretty_generate(fresh_state))
end

def restore_state!
  backup = "#{STATE_FILE}.backup"
  if File.exist?(backup)
    FileUtils.mv(backup, STATE_FILE)
  end
end

def run_hook(hook_path, input, hook_type = 'PreToolUse')
  env = {
    'CLAUDE_HOOK_TYPE' => hook_type,
    'TIER_TEST_MODE' => 'true'
  }

  stdout, stderr, status = Open3.capture3(
    env,
    'ruby', hook_path,
    stdin_data: input.to_json
  )

  {
    stdout: stdout,
    stderr: stderr,
    exit_code: status.exitstatus,
    blocked: status.exitstatus == 2
  }
end

def print_step(num, description)
  puts "\n#{BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{RESET}"
  puts "#{BLUE}STEP #{num}: #{description}#{RESET}"
  puts "#{BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{RESET}"
end

def print_result(result, expected_blocked)
  if result[:blocked]
    puts "#{RED}🚫 BLOCKED#{RESET}"
    puts "   #{result[:stderr].lines.first(3).join('   ')}" if result[:stderr].length > 0
  else
    puts "#{GREEN}✅ ALLOWED#{RESET}"
  end

  correct = result[:blocked] == expected_blocked
  if correct
    puts "#{GREEN}   ↳ Expected behavior!#{RESET}"
  else
    puts "#{RED}   ↳ WRONG! Expected #{expected_blocked ? 'BLOCKED' : 'ALLOWED'}#{RESET}"
  end

  correct
end

def read_state
  JSON.parse(File.read(STATE_FILE)) rescue {}
end

# ==============================================================================
# MAIN TEST FLOW
# ==============================================================================

puts "\n#{YELLOW}╔══════════════════════════════════════════════════════════════╗#{RESET}"
puts "#{YELLOW}║  REALISTIC FLOW TEST - Simulating Actual Claude Behavior     ║#{RESET}"
puts "#{YELLOW}╚══════════════════════════════════════════════════════════════╝#{RESET}"

reset_state!
results = []

begin
  # ==========================================================================
  # SCENARIO: User says "audit our codebase for problems"
  # ==========================================================================

  puts "\n#{YELLOW}USER PROMPT: \"audit our codebase for problems\"#{RESET}"

  # First, saneprompt analyzes the user prompt
  prompt_input = {
    'user_prompt' => 'audit our codebase for problems',
    'hook_type' => 'UserPromptSubmit'
  }

  result = run_hook(SANEPROMPT, prompt_input, 'UserPromptSubmit')
  puts "\n#{BLUE}SANEPROMPT analyzed prompt:#{RESET}"
  puts "   #{result[:stderr]}" if result[:stderr].length > 0

  # ==========================================================================
  # STEP 1: Claude IGNORES the prompt and tries to Edit immediately
  # ==========================================================================

  print_step(1, "Claude ignores prompt, tries to Edit immediately")
  puts "#{YELLOW}   (Classic Claude: 'Let me just fix this real quick...')#{RESET}"

  edit_input = {
    'tool_name' => 'Edit',
    'tool_input' => {
      'file_path' => '/Users/sj/SaneProcess/scripts/hooks/sanetools.rb',
      'old_string' => 'def check',
      'new_string' => 'def check_fixed'
    }
  }

  result = run_hook(SANETOOLS, edit_input)
  results << print_result(result, true)  # Should be BLOCKED

  # ==========================================================================
  # STEP 2: Claude does PARTIAL research (only reads one file)
  # ==========================================================================

  print_step(2, "Claude does partial research (reads ONE file)")
  puts "#{YELLOW}   (Classic Claude: 'I looked at it, that's enough right?')#{RESET}"

  read_input = {
    'tool_name' => 'Read',
    'tool_input' => {
      'file_path' => '/Users/sj/SaneProcess/scripts/hooks/sanetools.rb'
    }
  }

  result = run_hook(SANETOOLS, read_input)
  results << print_result(result, false)  # Should be ALLOWED

  # Track the read
  track_input = {
    'tool_name' => 'Read',
    'tool_input' => read_input['tool_input'],
    'tool_result' => 'file contents...'
  }
  run_hook(SANETRACK, track_input, 'PostToolUse')

  # Now try to edit again
  puts "\n   #{YELLOW}Now Claude tries to Edit after minimal research...#{RESET}"
  result = run_hook(SANETOOLS, edit_input)
  results << print_result(result, true)  # Should STILL be BLOCKED

  # ==========================================================================
  # STEP 3: Claude leaves memory check BLANK (skips it entirely)
  # ==========================================================================

  print_step(3, "Claude skips memory check entirely")
  puts "#{YELLOW}   (Classic Claude: 'Memory? What memory? Let me just grep...')#{RESET}"

  # Claude does grep but never checks memory
  grep_input = {
    'tool_name' => 'Grep',
    'tool_input' => {
      'pattern' => 'def check',
      'path' => '/Users/sj/SaneProcess/scripts/hooks/'
    }
  }

  result = run_hook(SANETOOLS, grep_input)
  results << print_result(result, false)  # Grep allowed

  # Track it
  track_input = {
    'tool_name' => 'Grep',
    'tool_input' => grep_input['tool_input'],
    'tool_result' => 'matches...'
  }
  run_hook(SANETRACK, track_input, 'PostToolUse')

  # Check state - memory should still be false
  state = read_state
  puts "\n   #{BLUE}State check:#{RESET}"
  puts "   - memory researched: #{state.dig('research', 'memory') ? GREEN : RED}#{state.dig('research', 'memory')}#{RESET}"
  puts "   - local researched: #{state.dig('research', 'local') ? GREEN : RED}#{state.dig('research', 'local')}#{RESET}"

  # ==========================================================================
  # STEP 4: Claude tries BASH bypass to write file
  # ==========================================================================

  print_step(4, "Claude tries bash bypass")
  puts "#{YELLOW}   (Sneaky Claude: 'echo fix > file.rb' instead of Edit)#{RESET}"

  bash_input = {
    'tool_name' => 'Bash',
    'tool_input' => {
      'command' => 'echo "# fixed" >> /Users/sj/SaneProcess/scripts/hooks/sanetools.rb'
    }
  }

  result = run_hook(SANETOOLS, bash_input)
  results << print_result(result, true)  # Should be BLOCKED

  # ==========================================================================
  # STEP 5: Claude tries to access sensitive path
  # ==========================================================================

  print_step(5, "Claude tries to read ~/.ssh")
  puts "#{YELLOW}   (Curious Claude: 'Let me just check the ssh config...')#{RESET}"

  ssh_input = {
    'tool_name' => 'Read',
    'tool_input' => {
      'file_path' => File.expand_path('~/.ssh/config')
    }
  }

  result = run_hook(SANETOOLS, ssh_input)
  results << print_result(result, true)  # Should be BLOCKED

  # ==========================================================================
  # STEP 6: Claude FINALLY does it right - proper research
  # ==========================================================================

  print_step(6, "Claude finally does proper research")
  puts "#{YELLOW}   (Reformed Claude: 'Let me check memory, docs, and codebase...')#{RESET}"

  # Check memory
  memory_input = {
    'tool_name' => 'mcp__memory__read_graph',
    'tool_input' => {}
  }
  result = run_hook(SANETOOLS, memory_input)
  puts "\n   Memory check: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'ALLOWED'}#{RESET}"

  track_input = {
    'tool_name' => 'mcp__memory__read_graph',
    'tool_input' => {},
    'tool_result' => '{"entities": [], "relations": []}'
  }
  run_hook(SANETRACK, track_input, 'PostToolUse')

  # Use Task agent for exploration
  task_input = {
    'tool_name' => 'Task',
    'tool_input' => {
      'prompt' => 'Explore the hooks codebase and find potential issues',
      'subagent_type' => 'Explore'
    }
  }
  result = run_hook(SANETOOLS, task_input)
  puts "   Task agent: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'ALLOWED'}#{RESET}"

  track_input = {
    'tool_name' => 'Task',
    'tool_input' => task_input['tool_input'],
    'tool_result' => 'Found several issues in the codebase...'
  }
  run_hook(SANETRACK, track_input, 'PostToolUse')

  # Check docs
  docs_input = {
    'tool_name' => 'mcp__context7__query-docs',
    'tool_input' => {
      'libraryId' => '/ruby/ruby',
      'query' => 'file handling best practices'
    }
  }
  result = run_hook(SANETOOLS, docs_input)
  puts "   Docs check: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'ALLOWED'}#{RESET}"

  track_input = {
    'tool_name' => 'mcp__context7__query-docs',
    'tool_input' => docs_input['tool_input'],
    'tool_result' => 'Documentation about file handling...'
  }
  run_hook(SANETRACK, track_input, 'PostToolUse')

  # Check final state
  state = read_state
  puts "\n   #{BLUE}Final research state:#{RESET}"
  state['research']&.each do |category, done|
    status = done ? "#{GREEN}✓#{RESET}" : "#{RED}✗#{RESET}"
    puts "   #{status} #{category}: #{done}"
  end

  # ==========================================================================
  # STEP 7: Now try to Edit after proper research
  # ==========================================================================

  print_step(7, "Claude tries Edit after proper research")
  puts "#{YELLOW}   (Should this work now?)#{RESET}"

  result = run_hook(SANETOOLS, edit_input)
  # This might still be blocked depending on requirements - let's see
  puts "\n   Edit attempt: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'ALLOWED'}#{RESET}"
  if result[:blocked]
    puts "   #{result[:stderr].lines.first(5).join('   ')}" if result[:stderr].length > 0
  end

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  puts "\n#{YELLOW}╔══════════════════════════════════════════════════════════════╗#{RESET}"
  puts "#{YELLOW}║  TEST SUMMARY                                                 ║#{RESET}"
  puts "#{YELLOW}╚══════════════════════════════════════════════════════════════╝#{RESET}"

  passed = results.count(true)
  failed = results.count(false)

  puts "\n#{BLUE}Results:#{RESET}"
  puts "   #{GREEN}✅ Correct behaviors: #{passed}#{RESET}"
  puts "   #{RED}❌ Wrong behaviors: #{failed}#{RESET}"

  puts "\n#{BLUE}What the hooks caught:#{RESET}"
  puts "   • Edit before research: #{results[0] ? GREEN + 'BLOCKED ✓' : RED + 'MISSED ✗'}#{RESET}"
  puts "   • Edit after minimal research: #{results[2] ? GREEN + 'BLOCKED ✓' : RED + 'MISSED ✗'}#{RESET}"
  puts "   • Bash file write bypass: #{results[4] ? GREEN + 'BLOCKED ✓' : RED + 'MISSED ✗'}#{RESET}"
  puts "   • Sensitive path access: #{results[5] ? GREEN + 'BLOCKED ✓' : RED + 'MISSED ✗'}#{RESET}"

  if failed == 0
    puts "\n#{GREEN}★ ALL HOOKS BEHAVED CORRECTLY ★#{RESET}"
  else
    puts "\n#{RED}⚠ SOME HOOKS FAILED TO CATCH BAD BEHAVIOR#{RESET}"
  end

ensure
  restore_state!
end
