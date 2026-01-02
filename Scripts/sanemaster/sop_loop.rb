# frozen_string_literal: true

# ==============================================================================
# SOP Loop Module - Two-Fix Rule Compliant Auto-Verification
# ==============================================================================

require 'json'
require 'fileutils'

module SaneMasterModules
  module SOPLoop
    STATE_FILE = '.claude/sop-verify-state.json'
    TASK_LIMITS = { info: 0, simple: 2, moderate: 4, complex: 10, research: 0 }.freeze

    # ===========================================================================
    # verify_gate - Run verify and track consecutive failures
    # ===========================================================================
    # Returns JSON with:
    #   - passed: bool
    #   - consecutive_failures: int
    #   - requires_escalation: bool (true after 2 consecutive failures)
    #   - escalation_actions: array of required actions if escalation needed
    # ===========================================================================
    def verify_gate(args)
      puts '🚦 --- [ SOP VERIFY GATE ] ---'

      # Load or initialize state
      state = load_verify_state

      # Run verification
      passed = run_verify_check

      if passed
        # Reset failure count on success
        state[:consecutive_failures] = 0
        state[:last_result] = 'passed'
        puts '✅ Verification passed'
      else
        # Increment failure count
        state[:consecutive_failures] += 1
        state[:last_result] = 'failed'
        puts "❌ Verification failed (attempt #{state[:consecutive_failures]})"
      end

      # Check Two-Fix Rule
      requires_escalation = state[:consecutive_failures] >= 2

      if requires_escalation
        puts ''
        puts '🛑 TWO-FIX RULE TRIGGERED'
        puts '   You have failed twice consecutively.'
        puts '   STOP GUESSING and investigate:'
        puts ''
        puts '   Required actions before next attempt:'
        puts '   1. Verify API exists: ./Scripts/SaneMaster.rb verify_api <API> [Framework]'
        puts '   2. Check SDK docs: Use apple-docs MCP'
        puts '   3. Check library docs: Use context7 MCP'
        puts '   4. Ask user for clarification if needed'
        puts ''
      end

      # Save state
      save_verify_state(state)

      # Build result
      result = {
        passed: passed,
        consecutive_failures: state[:consecutive_failures],
        requires_escalation: requires_escalation,
        escalation_actions: requires_escalation ? escalation_actions : []
      }

      # Output JSON for hook consumption
      if args.include?('--json')
        puts ''
        puts '--- JSON OUTPUT ---'
        puts JSON.pretty_generate(result)
      end

      result
    end

    # ===========================================================================
    # sop_loop - Start an SOP-compliant loop with auto-verification
    # ===========================================================================
    def start_sop_loop(args)
      puts '🔄 --- [ SOP LOOP ] ---'

      # Parse arguments
      task_type = :moderate
      prompt_parts = []

      args.each_with_index do |arg, _i|
        case arg
        when '--simple'
          task_type = :simple
        when '--complex'
          task_type = :complex
        when '--moderate'
          task_type = :moderate
        else
          prompt_parts << arg unless arg.start_with?('--')
        end
      end

      prompt = prompt_parts.join(' ')
      max_iterations = TASK_LIMITS[task_type]

      if prompt.empty?
        puts '❌ Error: No prompt provided'
        puts ''
        puts 'Usage: ./Scripts/SaneMaster.rb sop_loop [--simple|--moderate|--complex] <prompt>'
        puts ''
        puts 'Task types:'
        puts '  --simple   : 2 iterations (bug fixes, small changes)'
        puts '  --moderate : 4 iterations (features, refactoring)'
        puts '  --complex  : 10 iterations (large features, architecture)'
        return
      end

      if max_iterations.zero?
        puts '❌ Task type does not support looping'
        return
      end

      # Reset verify state
      reset_verify_state

      # Build SOP-enhanced prompt
      sop_prompt = build_sop_prompt(prompt, task_type)

      puts "Task type: #{task_type}"
      puts "Max iterations: #{max_iterations}"
      puts ''
      puts 'Starting SOP loop with Two-Fix Rule enforcement...'
      puts ''

      # Create Ralph loop state file
      create_ralph_state(sop_prompt, max_iterations)

      puts '✅ SOP loop activated'
      puts ''
      puts sop_prompt
    end

    # ===========================================================================
    # reset_escalation - Clear the escalation state after investigation
    # ===========================================================================
    def reset_escalation(_args)
      state = load_verify_state
      state[:consecutive_failures] = 0
      state[:escalation_cleared] = true
      save_verify_state(state)

      puts '✅ Escalation state cleared'
      puts '   You may now attempt another fix.'
      puts '   Remember: Verify APIs with SDK before coding!'
    end

    private

    def load_verify_state
      if File.exist?(STATE_FILE)
        JSON.parse(File.read(STATE_FILE), symbolize_names: true)
      else
        { consecutive_failures: 0, last_result: nil }
      end
    end

    def save_verify_state(state)
      FileUtils.mkdir_p(File.dirname(STATE_FILE))
      File.write(STATE_FILE, JSON.pretty_generate(state))
    end

    def reset_verify_state
      save_verify_state({ consecutive_failures: 0, last_result: nil })
    end

    def run_verify_check
      # Run verify and capture exit status
      system('./Scripts/SaneMaster.rb', 'verify', out: File::NULL, err: File::NULL)
    end

    def escalation_actions
      [
        'Verify API exists in SDK: ./Scripts/SaneMaster.rb verify_api <API>',
        'Check Apple docs: Use apple-docs MCP for usage examples',
        'Check library docs: Use context7 MCP for third-party APIs',
        'Read source code: Use Grep/Read to verify current implementation',
        'Ask user: If requirements are unclear, ask for clarification'
      ]
    end

    def build_sop_prompt(prompt, task_type)
      limit = TASK_LIMITS[task_type]

      <<~PROMPT
        #{prompt}

        ---
        ## SOP REQUIREMENTS (MANDATORY)

        You are in an SOP-compliant loop. Follow these rules:

        ### Two-Fix Rule (CRITICAL)
        - If `./Scripts/SaneMaster.rb verify` fails TWICE consecutively, you MUST:
          1. STOP attempting fixes
          2. Run `./Scripts/SaneMaster.rb verify_api <API>` to verify APIs exist
          3. Check documentation (apple-docs, context7 MCPs)
          4. Only then attempt another fix
        - Running `./Scripts/SaneMaster.rb reset_escalation` after investigation clears the block

        ### After EVERY Code Change
        1. `./Scripts/SaneMaster.rb verify` - Build and test
        2. `killall -9 SaneBar` - Kill zombie processes
        3. `./Scripts/SaneMaster.rb launch` - Fresh launch
        4. `./Scripts/SaneMaster.rb logs --follow` - Check logs

        ### Completion Criteria
        - [ ] verify passes with no errors
        - [ ] Regression test added (for bug fixes)
        - [ ] Self-rating 1-10 provided

        ### Iteration Limit: #{limit}
        Task type: #{task_type}

        <promise>SOP-COMPLETE</promise> only when ALL criteria verified.
      PROMPT
    end

    def create_ralph_state(prompt, max_iterations)
      ralph_state = <<~STATE
        ---
        active: true
        iteration: 1
        max_iterations: #{max_iterations}
        completion_promise: "SOP-COMPLETE"
        started_at: "#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
        sop_mode: true
        ---

        #{prompt}
      STATE

      FileUtils.mkdir_p('.claude')
      File.write('.claude/ralph-loop.local.md', ralph_state)
    end
  end
end
# rubocop:enable Metrics/ModuleLength
