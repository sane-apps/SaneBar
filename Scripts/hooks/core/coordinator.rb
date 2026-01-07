#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Enforcement Coordinator
# ==============================================================================
# Central orchestration for the hook enforcement system. Provides:
#   - Detection -> Decision -> Action pipeline
#   - Integration with StateManager for unified state
#   - Circuit breaker integration
#   - Audit logging
#   - Clean separation of concerns
#
# Flow:
#   1. CLASSIFY - Determine tool type (research, bootstrap, edit, etc.)
#   2. DETECT   - Run relevant detectors, collect results
#   3. DECIDE   - Aggregate results, check circuit breaker
#   4. ACT      - Block, warn, or allow
#
# Usage:
#   require_relative 'core/coordinator'
#
#   # In a hook entry point:
#   coordinator = Coordinator.new(input, hook_type: :pre_tool_use)
#   coordinator.run
#   # Handles exit codes automatically
# ==============================================================================

require 'json'
require_relative 'state_manager'
require_relative 'hook_registry'
require_relative '../rule_tracker'

class Coordinator
  BOOTSTRAP_PATTERNS = [
    /saneloop\s+start/i,
    /SaneMaster\.rb\s+saneloop/,
    /SaneMaster\.rb\s+verify/,
    /verify\.rb/
  ].freeze

  RESEARCH_TOOLS = %w[
    Read Glob Grep WebSearch WebFetch Task
    mcp__memory__read_graph mcp__memory__search_nodes
    mcp__apple-docs__ mcp__context7__ mcp__github__
  ].freeze

  attr_reader :input, :hook_type, :tool_name, :tool_input, :context

  def initialize(input, hook_type: :pre_tool_use)
    @input = input
    @hook_type = hook_type
    @tool_name = input['tool_name'] || ''
    @tool_input = input['tool_input'] || {}
    @context = build_context
  end

  # Main entry point - runs full pipeline
  def run
    # Phase 1: Classification
    classification = classify_tool

    # Phase 1.5: Security checks always run (even for bootstrap/research)
    security_decision = run_security_checks
    if security_decision&.blocked?
      execute_decision(security_decision)
    end

    # Skip enforcement for bootstrap commands
    if classification[:bootstrap]
      log_action(:allow, 'Bootstrap command')
      exit 0
    end

    # Skip enforcement for pure research (unless SaneLoop required)
    if classification[:research] && !saneloop_required?
      log_action(:allow, 'Research tool')
      exit 0
    end

    # Phase 2: Detection (full enforcement)
    decision = HookRegistry.run(hook_type, context)

    # Phase 3: Circuit breaker check
    if decision.blocked?
      breaker_status = check_circuit_breaker(decision.primary)
      if breaker_status == :halted
        emit_halted_warning(decision.primary)
        exit 0
      end
    end

    # Phase 4: Action
    execute_decision(decision)
  end

  private

  def build_context
    {
      tool_name: tool_name,
      tool_input: tool_input,
      input: input,
      state: StateManager.to_h,
      classification: nil # Set after classify_tool
    }
  end

  # Classify the tool for early-exit decisions
  def classify_tool
    result = {
      bootstrap: bootstrap_command?,
      research: research_tool?,
      edit: edit_tool?,
      type: determine_tool_type
    }
    @context[:classification] = result
    result
  end

  def bootstrap_command?
    return false unless tool_name == 'Bash'

    command = tool_input['command'] || ''
    BOOTSTRAP_PATTERNS.any? { |p| command.match?(p) }
  end

  def research_tool?
    return true if RESEARCH_TOOLS.any? { |t| tool_name.start_with?(t) }

    # Task tool: check if prompt is research (not editing)
    if tool_name == 'Task'
      prompt = tool_input['prompt'] || ''
      return !prompt.match?(/\b(edit|write|create|modify|update|fix)\b/i)
    end

    # Bash: check for readonly commands
    if tool_name == 'Bash'
      command = tool_input['command'] || ''
      readonly_patterns = [/^ls\b/, /^cat\b/, /^head\b/, /^tail\b/, /^git\s+(status|log|diff)\b/]
      return readonly_patterns.any? { |p| command.match?(p) }
    end

    false
  end

  def edit_tool?
    %w[Edit Write NotebookEdit].include?(tool_name)
  end

  def determine_tool_type
    return :bootstrap if bootstrap_command?
    return :research if research_tool?
    return :edit if edit_tool?

    :other
  end

  def saneloop_required?
    StateManager.get(:requirements, :requested)&.include?('saneloop')
  end

  # Run security-critical checks (path detector) - always runs
  def run_security_checks
    # Only run PathDetector for security (dangerous path blocking)
    security_hooks = HookRegistry.for(hook_type).select do |h|
      h.name == 'PathDetector'
    end

    return nil if security_hooks.empty?

    # Run security detectors
    results = []
    security_hooks.each do |detector_class|
      result = detector_class.new.check(context)
      results << result if result&.blocks?
      break if result&.blocks?  # Bail on first block
    end

    return nil if results.empty?

    # Return decision with the blocking result
    HookRegistry::Decision.new(
      action: :block,
      blockers: results,
      warnings: [],
      infos: [],
      primary: results.first
    )
  end

  # Circuit breaker: prevent infinite block loops
  def check_circuit_breaker(result)
    return :ok unless result

    StateManager.update(:enforcement) do |e|
      signature = "#{result.rule}:#{result.detector_name}"

      # Add this block to history (use string keys for JSON compatibility)
      e[:blocks] ||= []
      e[:blocks] << { 'signature' => signature, 'at' => Time.now.iso8601 }

      # Keep only last 10
      e[:blocks] = e[:blocks].last(10)

      # Check for 5x same signature (use string keys after JSON round-trip)
      recent = e[:blocks].last(5)
      if recent.length >= 5 && recent.all? { |b| b['signature'] == signature }
        e[:halted] = true
        e[:halted_at] = Time.now.iso8601
        e[:halted_reason] = "5x consecutive: #{signature}"
      end

      e
    end

    state = StateManager.get(:enforcement)
    state[:halted] ? :halted : :ok
  end

  def emit_halted_warning(result)
    warn ''
    warn '⚠️  ENFORCEMENT HALTED (circuit breaker tripped)'
    warn "   Same block fired 5x: #{result&.rule}"
    warn '   Switching to warn-only mode.'
    warn '   Reset with: StateManager.reset(:enforcement)'
    warn ''

    log_action(:halted, result&.message || 'Unknown')
  end

  def execute_decision(decision)
    if decision.blocked?
      emit_block(decision.primary)
      log_action(:block, decision.primary.message)
      exit 2
    end

    if decision.warnings.any?
      emit_warnings(decision.warnings)
      log_action(:warn, decision.warnings.map(&:message).join('; '))
    end

    # Clean pass
    log_action(:allow, 'All checks passed') if decision.clean?
    exit 0
  end

  def emit_block(result)
    warn ''
    warn "🔴 BLOCKED: #{result.rule || 'Enforcement'}"
    warn "   #{result.message}"
    if result.details[:fix]
      warn ''
      warn "   Fix: #{result.details[:fix]}"
    end
    warn ''
  end

  def emit_warnings(warnings)
    warn ''
    warnings.each do |w|
      warn "⚠️  #{w.rule || 'Warning'}: #{w.message}"
    end
    warn ''
  end

  def log_action(action, details)
    RuleTracker.log_enforcement(
      rule: 'coordinator',
      hook: hook_type.to_s,
      action: action.to_s,
      details: {
        tool: tool_name,
        message: details
      }
    )
  rescue StandardError
    # Don't fail on logging errors
  end

  # Class method for simple invocation from hook entry points
  class << self
    def run(hook_type: :pre_tool_use)
      input = parse_stdin
      return exit(0) unless input

      coordinator = new(input, hook_type: hook_type)
      coordinator.run
    end

    def parse_stdin
      JSON.parse($stdin.read)
    rescue JSON::ParserError, Errno::ENOENT, StandardError
      nil
    end
  end
end

# CLI mode for testing
if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  options = { hook_type: :pre_tool_use }
  OptionParser.new do |opts|
    opts.banner = 'Usage: coordinator.rb [options]'
    opts.on('-t', '--type TYPE', 'Hook type (pre_tool_use, post_tool_use)') do |t|
      options[:hook_type] = t.to_sym
    end
  end.parse!

  # Read from stdin or use test input
  if $stdin.tty?
    puts 'Coordinator loaded. Pipe JSON to stdin or use in hooks.'
    puts "Hook types: #{HookRegistry::TYPES.join(', ')}"
  else
    Coordinator.run(hook_type: options[:hook_type])
  end
end
