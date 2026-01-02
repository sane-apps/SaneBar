# frozen_string_literal: true

require 'json'
require 'fileutils'

module SaneMasterModules
  # Circuit Breaker State Management
  # Tracks consecutive failures and trips breaker after threshold
  # Learned from 700+ iteration Ralph loop failure on 2026-01-02
  #
  # Two conditions to trip:
  # 1. 5+ total consecutive failures, OR
  # 2. 3+ identical errors (same error signature = stuck in loop)
  module CircuitBreakerState
    STATE_FILE = File.join(Dir.pwd, '.claude', 'circuit_breaker.json')
    DEFAULT_THRESHOLD = 5           # Total failures before trip
    SAME_ERROR_THRESHOLD = 3        # Same error repeats before trip
    BLOCKED_TOOLS = %w[Edit Bash Write].freeze

    class << self
      def load_state
        return default_state unless File.exist?(STATE_FILE)

        state = JSON.parse(File.read(STATE_FILE), symbolize_names: true)
        # Ensure error_signatures uses string keys (JSON symbolizes them on load)
        state[:error_signatures] = state[:error_signatures].transform_keys(&:to_s) if state[:error_signatures].is_a?(Hash)
        state
      rescue JSON::ParserError
        default_state
      end

      def save_state(state)
        FileUtils.mkdir_p(File.dirname(STATE_FILE))
        File.write(STATE_FILE, JSON.pretty_generate(state))
      end

      def default_state
        {
          failures: 0,
          tripped: false,
          tripped_at: nil,
          trip_reason: nil,
          last_failure: nil,
          failure_messages: [],
          error_signatures: {}, # Track unique error patterns
          threshold: DEFAULT_THRESHOLD,
          same_error_threshold: SAME_ERROR_THRESHOLD
        }
      end

      # Extract a signature from an error message (normalize for comparison)
      def error_signature(message)
        return nil if message.nil? || message.empty?

        # Normalize: lowercase, remove line numbers, file paths, timestamps
        message.downcase
               .gsub(/:\d+:\d+:/, ':N:N:') # Line:col numbers
               .gsub(%r{/[\w/.-]+\.swift}, 'FILE.swift') # File paths
               .gsub(/\d{4}-\d{2}-\d{2}/, 'DATE') # Dates
               .gsub(/\d+/, 'N')                      # All numbers
               .strip[0, 100]                         # First 100 chars
      end

      def record_failure(message = nil)
        state = load_state
        state[:failures] += 1
        state[:last_failure] = Time.now.iso8601
        state[:failure_messages] ||= []
        state[:failure_messages] << message if message
        state[:failure_messages] = state[:failure_messages].last(10) # Keep last 10

        # Track error signatures for same-error detection
        state[:error_signatures] ||= {}
        if message
          sig = error_signature(message)
          if sig
            state[:error_signatures][sig] ||= 0
            state[:error_signatures][sig] += 1
          end
        end

        # Trip conditions:
        # 1. Total failures >= threshold (5)
        # 2. Same error repeated >= same_error_threshold (3)
        unless state[:tripped]
          same_error_count = state[:error_signatures].values.max || 0

          if state[:failures] >= state[:threshold]
            state[:tripped] = true
            state[:tripped_at] = Time.now.iso8601
            state[:trip_reason] = "#{state[:failures]} consecutive failures"
          elsif same_error_count >= state[:same_error_threshold]
            state[:tripped] = true
            state[:tripped_at] = Time.now.iso8601
            state[:trip_reason] = "Same error repeated #{same_error_count}x (stuck in loop)"
          end
        end

        save_state(state)
        state
      end

      def record_success
        state = load_state
        # Success resets the failure counter and signatures (but not a tripped breaker)
        unless state[:tripped]
          state[:failures] = 0
          state[:last_failure] = nil
          state[:error_signatures] = {}
        end
        save_state(state)
        state
      end

      def tripped?
        load_state[:tripped]
      end

      def reset!
        save_state(default_state)
        puts '✅ Circuit breaker reset. Tool calls unblocked.'
      end

      def status
        state = load_state
        same_error_max = (state[:error_signatures] || {}).values.max || 0

        if state[:tripped]
          {
            status: 'OPEN',
            message: "Circuit breaker TRIPPED at #{state[:tripped_at]}",
            trip_reason: state[:trip_reason],
            failures: state[:failures],
            blocked_tools: BLOCKED_TOOLS
          }
        else
          {
            status: 'CLOSED',
            message: "#{state[:failures]}/#{state[:threshold]} failures, #{same_error_max}/#{state[:same_error_threshold]} same-error",
            failures: state[:failures],
            same_error_count: same_error_max,
            blocked_tools: []
          }
        end
      end

      def should_block?(tool_name)
        return false unless tripped?

        BLOCKED_TOOLS.include?(tool_name)
      end
    end
  end
end
