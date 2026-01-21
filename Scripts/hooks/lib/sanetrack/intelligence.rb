# frozen_string_literal: true

require_relative '../../core/state_manager'
require 'time'

module SaneTrack
  module Intelligence
    ERROR_PATTERN = Regexp.union(
      /error/i,
      /failed/i,
      /exception/i,
      /cannot/i,
      /unable/i,
      /denied/i,
      /not found/i,
      /no such/i
    ).freeze

    ERROR_SIGNATURES = {
      'COMMAND_NOT_FOUND' => [/command not found/i, /not recognized as.*command/i],
      'PERMISSION_DENIED' => [/permission denied/i, /access denied/i, /not permitted/i],
      'FILE_NOT_FOUND' => [/no such file/i, /file not found/i, /doesn't exist/i],
      'BUILD_FAILED' => [/build failed/i, /compilation error/i, /compile error/i],
      'SYNTAX_ERROR' => [/syntax error/i, /parse error/i, /unexpected token/i],
      'TYPE_ERROR' => [/type.*error/i, /cannot convert/i, /type mismatch/i],
      'NETWORK_ERROR' => [/connection refused/i, /timeout/i, /network error/i],
      'MEMORY_ERROR' => [/out of memory/i, /memory error/i, /allocation failed/i],
    }.freeze

    def self.normalize_error(response_str)
      return nil unless response_str.is_a?(String)

      ERROR_SIGNATURES.each do |signature, patterns|
        if patterns.any? { |p| response_str.match?(p) }
          return signature
        end
      end

      return 'GENERIC_ERROR' if response_str.match?(ERROR_PATTERN)
      nil
    end

    def self.track_error_signature(signature, tool_name, response_str)
      return unless signature

      sig_key = signature.to_sym

      StateManager.update(:circuit_breaker) do |cb|
        cb[:error_signatures] ||= {}
        cb[:error_signatures][sig_key] = (cb[:error_signatures][sig_key] || 0) + 1

        if cb[:error_signatures][sig_key] >= 3 && !cb[:tripped]
          cb[:tripped] = true
          cb[:tripped_at] = Time.now.iso8601
          cb[:last_error] = "#{signature} x#{cb[:error_signatures][sig_key]}: #{response_str[0..100]}"
        end

        cb
      end
    end

    def self.detect_actual_failure(tool_name, tool_response)
      return nil unless tool_response.is_a?(Hash)

      if tool_response['error'] || tool_response[:error]
        error_text = (tool_response['error'] || tool_response[:error]).to_s
        return normalize_error(error_text) || 'GENERIC_ERROR'
      end

      stderr = tool_response['stderr'] || tool_response[:stderr]
      if stderr.is_a?(String) && !stderr.empty?
        sig = normalize_error(stderr)
        return sig if sig
      end

      if tool_name == 'Bash'
        exit_code = tool_response['exit_code'] || tool_response[:exit_code]
        return 'COMMAND_FAILED' if exit_code && exit_code != 0

        stdout = tool_response['stdout'] || tool_response[:stdout] || ''
        if stdout.match?(/no such file|not found/i)
          return nil unless stdout.match?(/^(bash|sh|ruby|python|node):\s/i)
        end
      end

      return nil if tool_name == 'Read'
      return nil if %w[Edit Write].include?(tool_name)
      return nil if tool_name.start_with?('mcp__')
      return nil if tool_name == 'Task'

      nil
    end
  end
end
