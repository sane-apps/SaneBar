#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# RECOVERY TEST - Can Claude complete a task after failing?
# ==============================================================================
# Real Claude behavior:
#   1. Fails (blocked)
#   2. Complains / half-asses it
#   3. Tries to hack around hook
#   4. Claims hook is broken
#   5. Finally does it right
#   6. KEY: Does the hook LET CLAUDE FINISH? Or is Claude locked out?
# ==============================================================================

require 'json'
require 'open3'
require 'fileutils'

HOOKS_DIR = File.expand_path('..', __dir__)
STATE_FILE = File.expand_path('../../.claude/state.json', HOOKS_DIR)
SANETOOLS = File.join(HOOKS_DIR, 'sanetools.rb')
SANETRACK = File.join(HOOKS_DIR, 'sanetrack.rb')

RED = "\e[31m"
GREEN = "\e[32m"
YELLOW = "\e[33m"
BLUE = "\e[34m"
CYAN = "\e[36m"
RESET = "\e[0m"

def reset_state!
  FileUtils.cp(STATE_FILE, "#{STATE_FILE}.backup") if File.exist?(STATE_FILE)

  fresh_state = {
    'research' => {
      'memory' => false,
      'docs' => false,
      'web' => false,
      'github' => false,
      'local' => false
    },
    'requirements' => { 'requested' => [], 'satisfied' => [] },
    'failures' => [],
    'tool_calls' => []
  }

  FileUtils.mkdir_p(File.dirname(STATE_FILE))
  File.write(STATE_FILE, JSON.pretty_generate(fresh_state))
end

def restore_state!
  backup = "#{STATE_FILE}.backup"
  FileUtils.mv(backup, STATE_FILE) if File.exist?(backup)
end

def run_hook(hook_path, input, hook_type = 'PreToolUse')
  stdout, stderr, status = Open3.capture3(
    { 'CLAUDE_HOOK_TYPE' => hook_type, 'TIER_TEST_MODE' => 'true' },
    'ruby', hook_path,
    stdin_data: input.to_json
  )
  { stdout: stdout, stderr: stderr, exit_code: status.exitstatus, blocked: status.exitstatus == 2 }
end

def simulate_tool(tool_name, tool_input, result = 'success')
  # Pre-check
  pre = run_hook(SANETOOLS, { 'tool_name' => tool_name, 'tool_input' => tool_input })
  return pre if pre[:blocked]

  # Track result
  run_hook(SANETRACK, {
    'tool_name' => tool_name,
    'tool_input' => tool_input,
    'tool_result' => result
  }, 'PostToolUse')

  pre
end

def read_state
  JSON.parse(File.read(STATE_FILE)) rescue {}
end

def show_state
  state = read_state
  puts "   #{CYAN}Research state:#{RESET}"
  (state['research'] || {}).each do |cat, val|
    done = val.is_a?(Hash) || val == true
    puts "   #{done ? GREEN + '✓' : RED + '✗'} #{cat}#{RESET}"
  end
end

def phase(num, title, claude_says)
  puts "\n#{YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{RESET}"
  puts "#{YELLOW}PHASE #{num}: #{title}#{RESET}"
  puts "#{CYAN}Claude: \"#{claude_says}\"#{RESET}"
  puts "#{YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━#{RESET}"
end

# ==============================================================================
puts "\n#{RED}╔══════════════════════════════════════════════════════════════╗#{RESET}"
puts "#{RED}║  RECOVERY TEST - Can Claude finish after failing?            ║#{RESET}"
puts "#{RED}╚══════════════════════════════════════════════════════════════╝#{RESET}"

reset_state!

begin
  # ==========================================================================
  phase(1, "FAIL - Claude tries to edit immediately",
        "I'll just make a quick fix...")
  # ==========================================================================

  result = simulate_tool('Edit', {
    'file_path' => '/Users/sj/SaneProcess/README.md',
    'old_string' => 'old',
    'new_string' => 'new'
  })

  puts "   Edit attempt: #{result[:blocked] ? RED + '🚫 BLOCKED' : GREEN + '✅ ALLOWED'}#{RESET}"
  puts "   #{result[:stderr].lines.first}" if result[:blocked]

  # ==========================================================================
  phase(2, "COMPLAIN - Claude half-asses research",
        "Fine, I'll read ONE file. Happy now?")
  # ==========================================================================

  result = simulate_tool('Read', { 'file_path' => '/Users/sj/SaneProcess/README.md' }, 'file contents')
  puts "   Read: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'allowed'}#{RESET}"

  result = simulate_tool('Edit', {
    'file_path' => '/Users/sj/SaneProcess/README.md',
    'old_string' => 'old',
    'new_string' => 'new'
  })
  puts "   Edit attempt: #{result[:blocked] ? RED + '🚫 BLOCKED' : GREEN + '✅ ALLOWED'}#{RESET}"
  show_state

  # ==========================================================================
  phase(3, "HACK - Claude tries bash bypass",
        "The Edit tool is broken. I'll use bash instead.")
  # ==========================================================================

  result = simulate_tool('Bash', { 'command' => 'echo "fix" >> README.md' })
  puts "   Bash write: #{result[:blocked] ? RED + '🚫 BLOCKED' : GREEN + '✅ ALLOWED'}#{RESET}"

  result = simulate_tool('Bash', { 'command' => 'sed -i "" "s/old/new/" README.md' })
  puts "   Sed in-place: #{result[:blocked] ? RED + '🚫 BLOCKED' : GREEN + '✅ ALLOWED'}#{RESET}"

  result = simulate_tool('Bash', { 'command' => 'cat > README.md << EOF\nnew content\nEOF' })
  puts "   Heredoc write: #{result[:blocked] ? RED + '🚫 BLOCKED' : GREEN + '✅ ALLOWED'}#{RESET}"

  # ==========================================================================
  phase(4, "BLAME - Claude claims hook is broken",
        "This hook is buggy. Let me try different variations...")
  # ==========================================================================

  # Try with different input formats
  result = simulate_tool('Edit', { 'path' => '/Users/sj/SaneProcess/README.md' })  # wrong key
  puts "   Edit (wrong key): #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'allowed'}#{RESET}"

  result = simulate_tool('Write', { 'file_path' => '/Users/sj/SaneProcess/README.md', 'content' => 'new' })
  puts "   Write tool: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'allowed'}#{RESET}"

  show_state

  # ==========================================================================
  phase(5, "COMPLY - Claude finally does proper research",
        "Okay fine. Let me actually check everything...")
  # ==========================================================================

  # Memory
  result = simulate_tool('mcp__memory__read_graph', {}, '{"entities":[]}')
  puts "   Memory: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'done'}#{RESET}"

  # Docs
  result = simulate_tool('mcp__context7__query-docs', { 'libraryId' => '/test', 'query' => 'test' }, 'docs')
  puts "   Docs: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'done'}#{RESET}"

  # Web
  result = simulate_tool('WebSearch', { 'query' => 'ruby best practices' }, 'results')
  puts "   Web: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'done'}#{RESET}"

  # GitHub
  result = simulate_tool('mcp__github__search_code', { 'q' => 'example' }, 'code')
  puts "   GitHub: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'done'}#{RESET}"

  # Local (already done from phase 2, but let's do more)
  result = simulate_tool('Grep', { 'pattern' => 'def', 'path' => '.' }, 'matches')
  puts "   Local: #{result[:blocked] ? RED + 'BLOCKED' : GREEN + 'done'}#{RESET}"

  show_state

  # ==========================================================================
  phase(6, "MOMENT OF TRUTH - Can Claude edit NOW?",
        "I've done all the research. Please let me edit...")
  # ==========================================================================

  result = simulate_tool('Edit', {
    'file_path' => '/Users/sj/SaneProcess/README.md',
    'old_string' => 'old',
    'new_string' => 'new'
  })

  if result[:blocked]
    puts "   #{RED}🚫 STILL BLOCKED!#{RESET}"
    puts "   #{RED}Error: #{result[:stderr]}#{RESET}"
    puts "\n   #{RED}★ CLAUDE IS LOCKED OUT - CANNOT RECOVER ★#{RESET}"

    # Debug: what's the actual state?
    puts "\n   #{YELLOW}Debug - Full state:#{RESET}"
    state = read_state
    puts JSON.pretty_generate(state)

    success = false
  else
    puts "   #{GREEN}✅ EDIT ALLOWED!#{RESET}"
    puts "\n   #{GREEN}★ CLAUDE RECOVERED AND COMPLETED THE TASK ★#{RESET}"
    success = true
  end

  # ==========================================================================
  puts "\n#{YELLOW}╔══════════════════════════════════════════════════════════════╗#{RESET}"
  puts "#{YELLOW}║  FINAL RESULT                                                 ║#{RESET}"
  puts "#{YELLOW}╚══════════════════════════════════════════════════════════════╝#{RESET}"

  if success
    puts "\n#{GREEN}✅ SUCCESS: Claude can recover from failures#{RESET}"
    puts "#{GREEN}   The hook workflow actually works end-to-end#{RESET}"
  else
    puts "\n#{RED}❌ FAILURE: Claude gets locked out#{RESET}"
    puts "#{RED}   The hook is too strict - no recovery path#{RESET}"
  end

ensure
  restore_state!
end
