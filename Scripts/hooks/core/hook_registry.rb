#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Hook Registry
# ==============================================================================
# Central registry for all enforcement hooks. Provides:
#   - Auto-registration via inherited callback
#   - Type-based lookup (pre_tool_use, post_tool_use, etc.)
#   - Priority ordering (lower = runs first)
#   - Filtering by tool name
#
# Usage:
#   # Define a detector (auto-registers on class definition)
#   class MyDetector < HookRegistry::Detector
#     register_as :pre_tool_use, priority: 10
#     def check(context)
#       # return DetectorResult
#     end
#   end
#
#   # Get hooks for a type
#   HookRegistry.for(:pre_tool_use)  # => [MyDetector, ...]
#
#   # Run all hooks
#   HookRegistry.run(:pre_tool_use, context)
# ==============================================================================

module HookRegistry
  TYPES = %i[pre_tool_use post_tool_use session_start session_end stop user_prompt].freeze

  # Severity levels for detector results
  module Severity
    BLOCK = 2   # Exit 2 - prevents tool execution
    WARN = 1    # Exit 0 with warning shown
    INFO = 0    # Logged only, no output
  end

  # Result from a detector check
  class DetectorResult
    attr_reader :severity, :message, :rule, :detector_name, :details

    def initialize(severity:, message:, rule: nil, detector_name: nil, details: {})
      @severity = severity
      @message = message
      @rule = rule
      @detector_name = detector_name
      @details = details
    end

    def blocks?
      severity == Severity::BLOCK
    end

    def warns?
      severity == Severity::WARN
    end

    def info?
      severity == Severity::INFO
    end

    # Factory methods for clean creation
    class << self
      def block(message, rule: nil, detector: nil, details: {})
        new(severity: Severity::BLOCK, message: message, rule: rule,
            detector_name: detector, details: details)
      end

      def warn(message, rule: nil, detector: nil, details: {})
        new(severity: Severity::WARN, message: message, rule: rule,
            detector_name: detector, details: details)
      end

      def info(message, rule: nil, detector: nil, details: {})
        new(severity: Severity::INFO, message: message, rule: rule,
            detector_name: detector, details: details)
      end

      def allow
        new(severity: Severity::INFO, message: 'Allowed', rule: nil,
            detector_name: nil, details: {})
      end
    end
  end

  # Base class for all detectors - auto-registers on inheritance
  class Detector
    class << self
      attr_accessor :only_tools, :except_tools

      def inherited(subclass)
        super
        # Auto-register when a new detector class is defined
        Registry.global.enqueue(subclass)
      end

      # DSL for defining hook metadata
      def register_as(type, priority: 50, only: nil, except: nil)
        @registered = true
        @hook_type = type.to_sym
        @priority = priority
        @only_tools = Array(only).map(&:to_s) if only
        @except_tools = Array(except).map(&:to_s) if except
      end

      def registered?
        @registered == true
      end

      def hook_type
        @hook_type || :pre_tool_use
      end

      def priority
        @priority || 50
      end

      def matches?(context)
        tool = context[:tool_name]&.to_s
        return false if only_tools && !only_tools.include?(tool)
        return false if except_tools && except_tools.include?(tool)

        true
      end
    end

    # Subclasses must implement this
    def check(_context)
      raise NotImplementedError, "#{self.class}#check must be implemented"
    end

    # Convenience for creating results
    def block(message, rule: nil, details: {})
      DetectorResult.block(message, rule: rule, detector: self.class.name, details: details)
    end

    def warn_result(message, rule: nil, details: {})
      DetectorResult.warn(message, rule: rule, detector: self.class.name, details: details)
    end

    def info(message, rule: nil, details: {})
      DetectorResult.info(message, rule: rule, detector: self.class.name, details: details)
    end

    def allow
      DetectorResult.allow
    end
  end

  # Thread-safe registry with lazy enrollment
  class Registry
    class << self
      def global
        @global ||= new
      end

      def reset!
        @global = nil
      end

      # Convenience: HookRegistry.for(:pre_tool_use)
      def for(type)
        global.hooks_for(type)
      end

      # Convenience: HookRegistry.run(:pre_tool_use, context)
      def run(type, context)
        global.run(type, context)
      end
    end

    def initialize
      @hooks = Hash.new { |h, k| h[k] = [] }
      @enrollment_queue = []
      @processed = false
      @mutex = Mutex.new
    end

    # Queue a hook class for registration (called from inherited)
    def enqueue(hook_class)
      @mutex.synchronize do
        @enrollment_queue << hook_class
        @processed = false
      end
    end

    # Get hooks for a type, sorted by priority
    def hooks_for(type, context: nil)
      process_queue
      entries = @hooks[type.to_sym]
      return entries unless context

      entries.select { |klass| klass.matches?(context) }
    end

    # Run all hooks for a type, return aggregated decision
    def run(type, context, mode: :bail_early)
      detectors = hooks_for(type, context: context)
      results = []

      detectors.each do |detector_class|
        result = detector_class.new.check(context)
        results << result if result

        # Bail-early: stop on first blocker
        break if mode == :bail_early && result&.blocks?
      end

      aggregate(results)
    end

    # List all registered hooks (for debugging)
    def all
      process_queue
      @hooks.transform_values { |v| v.map(&:name) }
    end

    private

    def process_queue
      return if @processed && @enrollment_queue.empty?

      @mutex.synchronize do
        @enrollment_queue.each do |hook_class|
          # Skip abstract base classes that didn't call register_as
          next unless hook_class.registered?

          type = hook_class.hook_type
          @hooks[type] << hook_class
          @hooks[type].sort_by!(&:priority)
        end
        @enrollment_queue.clear
        @processed = true
      end
    end

    def aggregate(results)
      blockers = results.select(&:blocks?)
      warnings = results.select(&:warns?)
      infos = results.select(&:info?)

      Decision.new(
        action: blockers.any? ? :block : :allow,
        blockers: blockers,
        warnings: warnings,
        infos: infos,
        primary: blockers.first
      )
    end
  end

  # Aggregated decision from running detectors
  class Decision
    attr_reader :action, :blockers, :warnings, :infos, :primary

    def initialize(action:, blockers:, warnings:, infos:, primary:)
      @action = action
      @blockers = blockers
      @warnings = warnings
      @infos = infos
      @primary = primary
    end

    def blocked?
      action == :block
    end

    def clean?
      blockers.empty? && warnings.empty?
    end

    def exit_code
      blocked? ? 2 : 0
    end
  end

  # Module-level convenience methods
  class << self
    def for(type)
      Registry.for(type)
    end

    def run(type, context, mode: :bail_early)
      Registry.global.run(type, context, mode: mode)
    end

    def reset!
      Registry.reset!
    end

    def all
      Registry.global.all
    end
  end
end

# CLI mode for testing
if __FILE__ == $PROGRAM_NAME
  puts 'HookRegistry loaded'
  puts "Types: #{HookRegistry::TYPES.join(', ')}"
  puts "Registered: #{HookRegistry.all.inspect}"
end
