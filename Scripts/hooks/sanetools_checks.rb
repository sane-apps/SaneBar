#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# SaneTools Checks Module
# ==============================================================================
# Extracted from sanetools.rb per Rule #10 (file size limit)
# Contains all check_* functions for PreToolUse enforcement
# ==============================================================================

require_relative 'core/state_manager'

module SaneToolsChecks
  # Constants needed by checks
  BLOCKED_PATH_PATTERN = Regexp.union(
    %r{^~?/\.ssh},
    %r{^/etc(/|$)},    # Match /etc and /etc/anything
    %r{^/var(/|$)},    # Match /var and /var/anything
    %r{^/usr(/|$)},    # Match /usr and /usr/anything (system binaries)
    %r{^~?/\.aws},
    %r{^~?/\.gnupg},
    /\.env$/,
    /credentials\.json$/i,  # Block credentials.json but not credentials_template.json
    /secrets?\.ya?ml$/i,
    # C1 CRITICAL: Block hook secret key (Claude could forge signatures)
    /\.claude_hook_secret$/,
    # Block netrc (contains credentials)
    /\.netrc$/
  ).freeze

  STATE_FILE_PATTERN = %r{\.claude/[^/]+\.json$}.freeze

  FILE_SIZE_SOFT_LIMIT = 500
  FILE_SIZE_HARD_LIMIT = 800
  FILE_SIZE_HARD_LIMIT_MD = 1500

  SAFE_REDIRECT_TARGETS = Regexp.union(
    '/dev/null',
    %r{^/tmp/},
    %r{^/var/tmp/},
    %r{DerivedData/},
    %r{\.build/},
    %r{^build/}
  ).freeze

  SIGNIFICANT_FILE_PATTERNS = [
    %r{scripts/hooks/.*\.rb$},
    %r{scripts/sanemaster/.*\.rb$},
    %r{scripts/SaneMaster\.rb$},
    %r{docs/.*\.md$}
  ].freeze

  class << self
    def check_blocked_path(tool_input, tool_name = nil, edit_tools = [])
      path = tool_input['file_path'] || tool_input['path'] || tool_input[:file_path] || tool_input[:path]
      return nil unless path

      require 'uri'
      decoded_path = URI.decode_www_form_component(path) rescue path
      expanded_path = File.expand_path(path) rescue path
      expanded_decoded = File.expand_path(decoded_path) rescue decoded_path

      [path, decoded_path, expanded_path, expanded_decoded].each do |p|
        if p.match?(BLOCKED_PATH_PATTERN)
          return "BLOCKED PATH: #{path}\nRule #1: Stay in your lane"
        end

        # Path traversal detection: check for sensitive dirs anywhere in path
        # Catches: ./test/../.ssh/key, /foo/bar/.ssh/id_rsa
        if p.match?(%r{/\.ssh/}) || p.match?(%r{/\.aws/}) || p.match?(%r{/\.gnupg/})
          return "BLOCKED PATH (traversal detected): #{path}\nRule #1: Stay in your lane"
        end

        # State files: block edits only, allow reads
        if p.match?(STATE_FILE_PATTERN) && edit_tools.include?(tool_name)
          return "STATE FILE PROTECTED: #{path}\n" \
                 "Claude cannot edit .claude/*.json files directly.\n" \
                 "Use user commands (s+/s-/sl+/sl-) or SaneMaster.rb instead."
        end
      end

      nil
    end

    def check_file_size(tool_name, tool_input, edit_tools)
      return nil unless edit_tools.include?(tool_name)

      path = tool_input['file_path'] || tool_input[:file_path]
      return nil unless path

      is_markdown = path.end_with?('.md')
      hard_limit = is_markdown ? FILE_SIZE_HARD_LIMIT_MD : FILE_SIZE_HARD_LIMIT

      # Handle Write tool: check new content directly
      content = tool_input['content'] || tool_input[:content]
      if content
        projected_count = content.lines.count
        if projected_count > hard_limit
          return "FILE SIZE BLOCKED (Rule #10)\n" \
                 "#{path}: #{projected_count} lines > #{hard_limit} limit\n" \
                 "Split file first. Use extensions like Manager+Feature.swift"
        elsif projected_count > FILE_SIZE_SOFT_LIMIT && !is_markdown
          warn "FILE SIZE WARNING: #{path} at #{projected_count} lines (limit: #{hard_limit})"
        end
        return nil
      end

      # Handle Edit tool: calculate delta from old_string/new_string
      return nil unless File.exist?(path)
      line_count = File.readlines(path).count rescue 0

      old_string = tool_input['old_string'] || tool_input[:old_string] || ''
      new_string = tool_input['new_string'] || tool_input[:new_string] || ''
      lines_added = new_string.lines.count - old_string.lines.count
      projected_count = line_count + lines_added

      if projected_count > hard_limit
        return "FILE SIZE BLOCKED (Rule #10)\n" \
               "#{path}: #{projected_count} lines > #{hard_limit} limit\n" \
               "Split file first. Use extensions like Manager+Feature.swift"
      elsif projected_count > FILE_SIZE_SOFT_LIMIT && !is_markdown
        warn "FILE SIZE WARNING: #{path} at #{projected_count} lines (limit: #{hard_limit})"
      end

      nil
    end

    def check_table_ban(tool_name, tool_input, edit_tools)
      return nil unless edit_tools.include?(tool_name)

      content = tool_input['new_string'] || tool_input[:new_string] ||
                tool_input['content'] || tool_input[:content] || ''
      return nil if content.empty?

      table_patterns = [
        /\|[-:]+\|/,
        /^\s*\|.*\|.*\|/m
      ]

      if table_patterns.any? { |p| content.match?(p) }
        pipe_lines = content.lines.count { |l| l.count('|') >= 2 }
        if pipe_lines >= 2
          return "TABLE BLOCKED\n" \
                 "Markdown tables render poorly in terminal.\n" \
                 "Use plain lists or bullet points instead."
        end
      end

      nil
    end

    def check_bash_bypass(tool_name, tool_input, bash_file_write_pattern)
      return nil unless tool_name == 'Bash'

      command = tool_input['command'] || tool_input[:command] || ''

      unless command.match?(/SaneMaster\.rb/)
        state_bypass_patterns = [
          /ruby\s+-e.*\.claude\/.*\.json/i,
          /\brm\s+(-[rf]+\s+)?[^\|]*\.claude\/.*\.json/i,
          />\s*[^\s]*\.claude\/.*\.json/i,
          /\btee\s+[^\s]*\.claude\/.*\.json/i
        ]

        if state_bypass_patterns.any? { |p| command.match?(p) }
          return "STATE BYPASS BLOCKED\n" \
                 "Command appears to manipulate .claude state files: #{command[0..60]}...\n" \
                 "Claude cannot modify enforcement state via bash.\n" \
                 "Use user commands (s+/s-/sl+/sl-) or SaneMaster.rb instead."
        end
      end

      if command.match?(bash_file_write_pattern)
        target_match = command.match(/(?:>|>>|tee\s+)\s*([^\s|&;]+)/)
        target = target_match ? target_match[1] : nil

        return nil if target && target.match?(SAFE_REDIRECT_TARGETS)

        if command.match?(/^\s*\S+.*2>&1\s*$/) || command.match?(/2>\/dev\/null/)
          unless command.match?(/[^2]>\s*[^&]/) || command.match?(/>>/)
            return nil
          end
        end

        return "BASH FILE WRITE BLOCKED\n" \
               "Command appears to write files: #{command[0..80]}...\n" \
               "Use Edit or Write tool instead - bash writes bypass tracking.\n" \
               "Allowed: /tmp/, /dev/null, build dirs, stderr redirects (2>&1)"
      end

      nil
    end

    def check_readme_on_commit(tool_name, tool_input)
      return nil unless tool_name == 'Bash'

      command = tool_input['command'] || tool_input[:command] || ''
      return nil unless command.match?(/git\s+commit/)

      edits = StateManager.get(:edits)
      edited_files = edits[:unique_files] || []

      significant_edits = edited_files.any? do |f|
        SIGNIFICANT_FILE_PATTERNS.any? { |p| f.match?(p) }
      end

      return nil unless significant_edits

      readme_updated = edited_files.any? { |f| f.match?(/README\.md$/i) }
      return nil if readme_updated

      warn '---'
      warn 'README UPDATE REMINDER'
      warn ''
      warn 'You edited significant files but README.md was not updated:'
      significant = edited_files.select { |f| SIGNIFICANT_FILE_PATTERNS.any? { |p| f.match?(p) } }
      significant.first(5).each { |f| warn "  - #{File.basename(f)}" }
      warn ''
      warn 'Consider updating README.md to reflect these changes.'
      warn '---'

      nil
    end

    def check_subagent_bypass(tool_name, tool_input, edit_keywords, research_categories)
      return nil unless tool_name == 'Task'

      prompt = tool_input['prompt'] || tool_input[:prompt] || ''
      prompt_lower = prompt.downcase

      is_edit_task = edit_keywords.any? { |kw| prompt_lower.include?(kw) }
      return nil unless is_edit_task

      research = StateManager.get(:research)
      complete = research_categories.keys.all? { |cat| research[cat] }

      unless complete
        return "SUBAGENT BYPASS BLOCKED\n" \
               "Task appears to be for editing: #{prompt[0..50]}...\n" \
               "Complete research first (5 categories)."
      end

      nil
    end

    def check_research_before_edit(tool_name, edit_tools, research_categories)
      return nil unless edit_tools.include?(tool_name)

      research = StateManager.get(:research)
      complete = research_categories.keys.all? { |cat| research[cat] }

      return nil if complete

      missing = research_categories.keys.reject { |cat| research[cat] }
      "RESEARCH INCOMPLETE\n" \
      "Cannot edit until research is complete.\n" \
      "Missing: #{missing.join(', ')}\n" \
      "Use Task agents for each category."
    end

    def check_global_mutations(tool_name, global_mutation_pattern, research_categories)
      return nil unless tool_name.match?(global_mutation_pattern)

      research = StateManager.get(:research)
      complete = research_categories.keys.all? { |cat| research[cat] }

      return nil if complete

      missing = research_categories.keys.reject { |cat| research[cat] }
      "GLOBAL MUTATION BLOCKED\n" \
      "Tool '#{tool_name}' affects ALL projects (MCP memory is shared).\n" \
      "Complete research first. Missing: #{missing.join(', ')}\n" \
      "Use mcp__memory__read_graph to understand current state before mutating."
    end

    def check_external_mutations(tool_name, external_mutation_pattern, research_categories)
      return nil unless tool_name.match?(external_mutation_pattern)

      research = StateManager.get(:research)
      complete = research_categories.keys.all? { |cat| research[cat] }

      return nil if complete

      missing = research_categories.keys.reject { |cat| research[cat] }
      "EXTERNAL MUTATION BLOCKED\n" \
      "Tool '#{tool_name}' affects external systems (GitHub).\n" \
      "Complete research first. Missing: #{missing.join(', ')}\n" \
      "Use mcp__github__get_* or mcp__github__list_* to understand state first."
    end

    def check_circuit_breaker
      cb = StateManager.get(:circuit_breaker)
      return nil unless cb[:tripped]

      "CIRCUIT BREAKER TRIPPED\n" \
      "#{cb[:failures]} consecutive failures detected.\n" \
      "Last error: #{cb[:last_error]}\n" \
      "User must say 'reset breaker' to continue."
    end

    def check_enforcement_halted
      enf = StateManager.get(:enforcement)
      return nil unless enf[:halted]

      warn "Enforcement halted: #{enf[:halted_reason]}"
      nil
    end

    def check_research_only_mode(tool_name, edit_tools, global_mutation_pattern, external_mutation_pattern)
      reqs = StateManager.get(:requirements)
      return nil unless reqs[:is_research_only]

      if edit_tools.include?(tool_name) ||
         tool_name.match?(global_mutation_pattern) ||
         tool_name.match?(external_mutation_pattern)
        return "RESEARCH-ONLY MODE ACTIVE\n" \
               "User requested research/investigation only.\n" \
               "Tool '#{tool_name}' is blocked because it would make changes.\n" \
               "If you want to make changes, ask user to start a new session with an action request."
      end

      nil
    end

    def check_saneloop_required(tool_name, edit_tools)
      return nil unless edit_tools.include?(tool_name)

      reqs = StateManager.get(:requirements)
      return nil unless reqs[:is_big_task]

      saneloop = StateManager.get(:saneloop)
      return nil if saneloop[:active]

      "SANELOOP REQUIRED\n" \
      "Big task detected but SaneLoop not active.\n" \
      "This task matches big-task indicators (all/complete/rewrite/system/etc).\n" \
      "Start with: sl+ \"<task description>\"\n" \
      "Or ask user to start: ./Scripts/SaneMaster.rb saneloop start \"Task\""
    end

    def check_requirements(tool_name, bootstrap_tool_pattern, edit_tools, research_categories)
      return nil if tool_name.match?(bootstrap_tool_pattern)
      return nil unless edit_tools.include?(tool_name)

      reqs = StateManager.get(:requirements)
      requested = reqs[:requested] || []
      satisfied = reqs[:satisfied] || []

      return nil if requested.empty?

      unsatisfied = requested - satisfied

      return nil if unsatisfied.empty?

      if unsatisfied.include?('research')
        research = StateManager.get(:research)
        if research_categories.keys.all? { |cat| research[cat] }
          StateManager.update(:requirements) do |r|
            r[:satisfied] ||= []
            r[:satisfied] << 'research' unless r[:satisfied].include?('research')
            r
          end
          unsatisfied.delete('research')
        end
      end

      return nil if unsatisfied.empty?

      "REQUIREMENTS NOT MET\n" \
      "User requested: #{requested.join(', ')}\n" \
      "Unsatisfied: #{unsatisfied.join(', ')}\n" \
      "Complete these before editing."
    end

    # === INTELLIGENCE: Gaming Detection ===
    # Detect patterns suggesting attempts to game the enforcement system

    GAMING_THRESHOLDS = {
      rapid_research_seconds: 30,      # All research in < 30s is suspicious
      repeated_errors_count: 3,        # Same error 3x suggests brute force
      research_to_edit_seconds: 5,     # Gap too short = no real review
      error_rate_threshold: 0.7        # 70%+ failure rate is suspicious
    }.freeze

    def check_gaming_patterns(tool_name, edit_tools, research_categories)
      return nil unless edit_tools.include?(tool_name)

      warnings = []

      # Check 1: All research completed suspiciously fast
      if (w = check_rapid_research(research_categories))
        warnings << w
      end

      # Check 2: Same timestamp across all research (atomic completion)
      if (w = check_timestamp_gaming)
        warnings << w
      end

      # Check 3: High error rate then sudden success
      if (w = check_error_stuffing)
        warnings << w
      end

      return nil if warnings.empty?

      # Log gaming attempts to patterns for future sessions
      log_gaming_attempt(warnings)

      # Check if should block based on cumulative patterns
      patterns = StateManager.get(:patterns)
      gaming_count = patterns&.dig(:weak_spots, 'gaming') || 0

      # Block on:
      # 1. 3+ cumulative gaming warnings in session (pattern established), OR
      # 2. 2+ patterns detected simultaneously (severe gaming attempt)
      should_block = gaming_count >= 3 || warnings.length >= 2

      if should_block
        return "GAMING DETECTION BLOCKED\n" \
               "Research gaming patterns detected (#{gaming_count} attempts).\n" \
               "Patterns: #{warnings.join('; ')}\n" \
               "This suggests automated or scripted research completion.\n" \
               "Reset with: ./Scripts/SaneMaster.rb hooks reset"
      end

      # Under threshold - warn only (gives chance to correct behavior)
      warnings.each { |w| warn "⚠️  GAMING WARNING: #{w}" }
      nil
    end

    def check_rapid_research(research_categories)
      research = StateManager.get(:research)
      timestamps = []

      research_categories.keys.each do |cat|
        info = research[cat]
        next unless info.is_a?(Hash) && info[:completed_at]
        begin
          timestamps << Time.parse(info[:completed_at])
        rescue ArgumentError
          # Invalid timestamp format - skip this category
          next
        end
      end

      return nil if timestamps.length < 5

      span = timestamps.max - timestamps.min
      if span < GAMING_THRESHOLDS[:rapid_research_seconds]
        return "All 5 research categories in #{span.round}s (expected: >30s)"
      end

      nil
    end

    def check_timestamp_gaming
      research = StateManager.get(:research)
      timestamps = []

      research.each do |_cat, info|
        next unless info.is_a?(Hash) && info[:completed_at]
        timestamps << info[:completed_at]
      end

      completed = timestamps.compact.length
      unique = timestamps.compact.uniq.length

      # If 3+ categories have identical timestamp, suspicious
      if completed >= 3 && unique == 1
        return "#{completed} research categories at identical timestamp"
      end

      nil
    end

    def check_error_stuffing
      action_log = StateManager.get(:action_log) || []
      return nil if action_log.length < 10

      recent = action_log.last(10)
      errors = recent.count { |a| a[:error_sig] || a['error_sig'] }
      error_rate = errors.to_f / recent.length

      if error_rate >= GAMING_THRESHOLDS[:error_rate_threshold]
        last_action = recent.last
        tool = last_action[:tool] || last_action['tool']
        success = last_action[:success] || last_action['success']

        if tool == 'Task' && success
          return "#{(error_rate * 100).round}% error rate, then Task 'succeeded'"
        end
      end

      nil
    end

    def log_gaming_attempt(warnings)
      StateManager.update(:patterns) do |patterns|
        patterns[:weak_spots] ||= {}
        patterns[:weak_spots]['gaming'] = (patterns[:weak_spots]['gaming'] || 0) + 1
        patterns[:gaming_log] ||= []
        patterns[:gaming_log] << {
          timestamp: Time.now.iso8601,
          warnings: warnings
        }
        patterns[:gaming_log] = patterns[:gaming_log].last(10)
        patterns
      end
    rescue StandardError
      # Don't fail on logging errors
    end

    # === PREFLIGHT: MCP Verification System ===
    # Block edits until ALL MCPs have been verified this session
    # User insight: "how can you make sure all systems are go before work begins?"

    CLAUDE_DIR = File.join(ENV['CLAUDE_PROJECT_DIR'] || Dir.pwd, '.claude')
    MEMORY_STAGING_FILE = File.join(CLAUDE_DIR, 'memory_staging.json')

    # MCP verification tools (read-only operations to prove connectivity)
    MCP_VERIFICATION_INFO = {
      memory: { name: 'Memory', tool: 'mcp__memory__read_graph' },
      apple_docs: { name: 'Apple Docs', tool: 'mcp__apple-docs__search_apple_docs' },
      context7: { name: 'Context7', tool: 'mcp__context7__resolve-library-id' },
      github: { name: 'GitHub', tool: 'mcp__github__search_repositories' }
    }.freeze

    def check_pending_mcp_actions(tool_name, edit_tools)
      return nil unless edit_tools.include?(tool_name)

      # Get MCP health state
      health = StateManager.get(:mcp_health)

      # If all verified, allow edits
      return nil if health[:verified_this_session]

      # Check which MCPs are still unverified
      mcps = health[:mcps] || {}
      unverified = MCP_VERIFICATION_INFO.select do |key, _info|
        mcp_data = mcps[key]
        !mcp_data || !mcp_data[:verified]
      end

      # If all verified (but flag not set), allow and fix state
      if unverified.empty?
        StateManager.update(:mcp_health) { |h| h[:verified_this_session] = true; h }
        return nil
      end

      # Also check for memory staging (pending MCP action)
      pending_actions = []
      if File.exist?(MEMORY_STAGING_FILE)
        begin
          staging = JSON.parse(File.read(MEMORY_STAGING_FILE))
          if staging['needs_memory_update']
            entity_name = staging.dig('suggested_entity', 'name') || 'learnings'
            pending_actions << "Memory staging needs saving: #{entity_name}"
          end
        rescue StandardError
          pending_actions << 'Memory staging file needs review'
        end
      end

      # Build comprehensive error message
      unverified_list = unverified.map do |key, info|
        "  ⬜ #{info[:name]}: #{info[:tool]}"
      end.join("\n")

      msg = "MCP VERIFICATION INCOMPLETE\n" \
            "Cannot edit until all 4 MCPs are verified this session.\n" \
            "\n" \
            "Unverified MCPs (run each tool once to verify):\n" \
            "#{unverified_list}\n"

      if pending_actions.any?
        msg += "\n" \
               "Pending MCP actions:\n" \
               "#{pending_actions.map { |a| "  ⚠️  #{a}" }.join("\n")}\n"
      end

      msg += "\n" \
             "This ensures ALL systems are operational before you make changes.\n" \
             "Call each unverified MCP tool once to proceed."

      msg
    end

    # === EDIT ATTEMPT LIMIT ===
    # Prevents "no big deal" syndrome: 3 edit attempts without research = STOP
    # User insight: "genius with impulse control of a two year old"
    # This enforces the pause-and-think pattern

    MAX_EDIT_ATTEMPTS_BEFORE_RESEARCH = 3

    def check_edit_attempt_limit(tool_name, edit_tools)
      return nil unless edit_tools.include?(tool_name)

      attempts = StateManager.get(:edit_attempts) || {}
      count = attempts[:count] || 0

      # If under limit, increment and allow
      if count < MAX_EDIT_ATTEMPTS_BEFORE_RESEARCH
        StateManager.update(:edit_attempts) do |a|
          a ||= {}
          a[:count] = (a[:count] || 0) + 1
          a[:last_attempt] = Time.now.iso8601
          a
        end
        return nil
      end

      # At or over limit - reset research and block until FULL research is redone
      # If 3 edits didn't work, your understanding is wrong - research AGAIN
      StateManager.reset(:research)

      "EDIT ATTEMPT LIMIT REACHED\n" \
      "You've made #{count} edit attempts and they didn't work.\n" \
      "STOP. Your understanding is wrong. Research AGAIN from scratch.\n" \
      "\n" \
      "Research has been RESET. You MUST redo the FULL SaneLoop process:\n" \
      "  1. Memory - check past bugs and patterns (mcp__memory__read_graph)\n" \
      "  2. Docs - verify APIs exist (apple-docs, context7)\n" \
      "  3. Web - current best practices (WebSearch)\n" \
      "  4. GitHub - external examples (mcp__github__search_*)\n" \
      "  5. Local - understand existing code (Read, Grep, Glob)\n" \
      "\n" \
      "All 5 categories are now MISSING. Complete them all to continue.\n" \
      "\n" \
      "This is not punishment - it's the process that ALWAYS works.\n" \
      "Today's session proved it: full research found the 700+ iteration failure."
    end

    def reset_edit_attempts
      StateManager.update(:edit_attempts) do |a|
        a ||= {}
        a[:count] = 0
        a[:reset_at] = Time.now.iso8601
        a
      end
    rescue StandardError
      # Don't fail on reset errors
    end
  end
end
