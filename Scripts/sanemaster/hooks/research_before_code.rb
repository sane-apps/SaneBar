#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Research Before Code Hook
# ==============================================================================
# Enforces focused research before implementing each feature/phase.
#
# Logic:
# 1. Detect Edit/Write to code files (*.swift, *.rb, etc.)
# 2. Extract current feature from TodoWrite state (in_progress items)
# 3. Check if .claude/research/<feature-slug>.md exists
# 4. BLOCK if no research file, with instructions to do research first
#
# Hook Type: PreToolUse (Edit, Write)
# Behavior: BLOCKS code edits until research is documented
# ==============================================================================

require 'json'
require 'fileutils'

RESEARCH_DIR = '.claude/research'
TODO_FILE = '.claude/todos.json'
BYPASS_FILE = '.claude/research_bypass.txt'

# Code file patterns that require research
CODE_PATTERNS = [
  /\.swift$/,
  /Core\/.*\.swift$/,
  /UI\/.*\.swift$/,
  /Services\/.*\.swift$/
].freeze

# Files that DON'T require research (tests, configs, etc.)
EXEMPT_PATTERNS = [
  /Tests?\//,
  /\.json$/,
  /\.md$/,
  /\.yml$/,
  /\.yaml$/,
  /project\.yml$/,
  /\.xcodeproj/,
  /Scripts\//
].freeze

# Read from stdin (Claude Code standard)
begin
  input = JSON.parse($stdin.read)
rescue JSON::ParserError, Errno::ENOENT
  exit 0 # Don't block on parse errors
end

tool_name = input['tool_name']
tool_input = input['tool_input'] || input

# Only check Edit and Write tools
exit 0 unless %w[Edit Write].include?(tool_name)

# Get the file path being edited
file_path = tool_input['file_path'] || tool_input['path'] || ''

# Check if it's a code file that needs research
is_code_file = CODE_PATTERNS.any? { |p| file_path.match?(p) }
is_exempt = EXEMPT_PATTERNS.any? { |p| file_path.match?(p) }

exit 0 unless is_code_file && !is_exempt

# Check for bypass
if File.exist?(BYPASS_FILE)
  bypass_content = File.read(BYPASS_FILE).strip.downcase
  if bypass_content == 'on' || bypass_content == 'true'
    exit 0 # Bypass enabled
  end
end

# Get current in-progress feature from todos
current_feature = nil
if File.exist?(TODO_FILE)
  begin
    todos = JSON.parse(File.read(TODO_FILE))
    in_progress = todos.find { |t| t['status'] == 'in_progress' }
    current_feature = in_progress['content'] if in_progress
  rescue StandardError
    # Can't parse todos, try to infer from file path
  end
end

# If no todo found, try to infer feature from file path
if current_feature.nil? || current_feature.empty?
  # Extract feature from path like "Core/Services/HoverService.swift" -> "hover-service"
  if file_path.match?(/Services\/(\w+)Service\.swift/)
    current_feature = file_path.match(/Services\/(\w+)Service\.swift/)[1]
  elsif file_path.match?(/(\w+)\.swift/)
    current_feature = file_path.match(/(\w+)\.swift/)[1]
  end
end

exit 0 if current_feature.nil? || current_feature.empty?

# Create feature slug for research file
feature_slug = current_feature
                 .gsub(/^P\d+:\s*/, '') # Remove "P0: " prefix
                 .gsub(/[^a-zA-Z0-9\s-]/, '') # Remove special chars
                 .strip
                 .downcase
                 .gsub(/\s+/, '-') # Spaces to dashes

# Check if research file exists
FileUtils.mkdir_p(RESEARCH_DIR) unless Dir.exist?(RESEARCH_DIR)
research_file = File.join(RESEARCH_DIR, "#{feature_slug}.md")

if File.exist?(research_file)
  # Research exists, check if it has minimum content
  content = File.read(research_file)
  lines = content.lines.reject { |l| l.strip.empty? || l.strip.start_with?('#') }

  if lines.length >= 5 # At least 5 non-header, non-empty lines
    exit 0 # Research is sufficient
  else
    warn ''
    warn '=' * 60
    warn '  RESEARCH FILE TOO SHORT'
    warn '=' * 60
    warn ''
    warn "  Feature: #{current_feature}"
    warn "  File: #{research_file}"
    warn "  Content: #{lines.length} lines (need at least 5)"
    warn ''
    warn '  Add more research before coding:'
    warn '    - How do competitors implement this?'
    warn '    - What APIs/frameworks to use?'
    warn '    - What are the gotchas?'
    warn ''
    warn '=' * 60
    warn ''
    exit 2 # BLOCK
  end
end

# No research file exists - BLOCK
warn ''
warn '=' * 60
warn '  BLOCKED: RESEARCH BEFORE CODE'
warn '=' * 60
warn ''
warn "  You're trying to edit: #{file_path}"
warn "  Current feature: #{current_feature}"
warn ''
warn '  But no research file exists at:'
warn "    #{research_file}"
warn ''
warn '  REQUIRED: Do focused research first!'
warn ''
warn '  1. Use Task agents to research how competitors implement this'
warn '  2. Check Apple docs / Context7 for APIs'
warn '  3. Document findings in the research file:'
warn ''
warn "     echo '# #{current_feature}' > #{research_file}"
warn ''
warn '  Research file should include:'
warn '    - Similar implementations (Ice, Hidden Bar, etc.)'
warn '    - APIs to use (CoreWLAN, Network, etc.)'
warn '    - Permission requirements'
warn '    - Implementation approach'
warn '    - Gotchas/edge cases'
warn ''
warn '  To bypass (emergency only):'
warn "    echo 'on' > #{BYPASS_FILE}"
warn ''
warn '=' * 60
warn ''

exit 2 # BLOCK
