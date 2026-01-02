# frozen_string_literal: true

require 'json'
require 'fileutils'

module SaneMasterModules
  # Circuit Breaker State Management
  # Tracks consecutive failures and trips breaker after threshold
  # Learned from 700+ iteration Ralph loop failure on 2026-01-02
  module CircuitBreakerState
    STATE_FILE = File.join(Dir.pwd, '.claude', 'circuit_breaker.json')
    DEFAULT_THRESHOLD = 3
    BLOCKED_TOOLS = %w[Edit Bash Write].freeze

    class << self
      def load_state
        return default_state unless File.exist?(STATE_FILE)

        JSON.parse(File.read(STATE_FILE), symbolize_names: true)
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
          last_failure: nil,
          failure_messages: [],
          threshold: DEFAULT_THRESHOLD
        }
      end

      def record_failure(message = nil)
        state = load_state
        state[:failures] += 1
        state[:last_failure] = Time.now.iso8601
        state[:failure_messages] ||= []
        state[:failure_messages] << message if message
        state[:failure_messages] = state[:failure_messages].last(5) # Keep last 5

        # Trip the breaker if threshold reached
        if state[:failures] >= state[:threshold] && !state[:tripped]
          state[:tripped] = true
          state[:tripped_at] = Time.now.iso8601
        end

        save_state(state)
        state
      end

      def record_success
        state = load_state
        # Success resets the failure counter (but not a tripped breaker)
        state[:failures] = 0 unless state[:tripped]
        state[:last_failure] = nil unless state[:tripped]
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
        if state[:tripped]
          {
            status: 'OPEN',
            message: "Circuit breaker TRIPPED at #{state[:tripped_at]}",
            failures: state[:failures],
            blocked_tools: BLOCKED_TOOLS
          }
        else
          {
            status: 'CLOSED',
            message: "#{state[:failures]}/#{state[:threshold]} failures before trip",
            failures: state[:failures],
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
