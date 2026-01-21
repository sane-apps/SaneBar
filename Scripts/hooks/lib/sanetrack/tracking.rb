# frozen_string_literal: true

require_relative '../../core/state_manager'
require 'fileutils'
require 'time'
require 'json'

module SaneTrack
  module Tracking
    # === TOOL CLASSIFICATION ===
    EDIT_TOOLS = %w[Edit Write NotebookEdit].freeze
    FAILURE_TOOLS = %w[Bash Edit Write].freeze  # Tools that can fail and trigger circuit breaker

    # === MCP VERIFICATION TOOLS ===
    MCP_VERIFICATION_PATTERNS = {
      apple_docs: /^mcp__apple-docs__/,
      context7: /^mcp__context7__/,
      github: /^mcp__github__(search_|get_|list_)/
    }.freeze

    # === INTELLIGENCE: Action Log for Pattern Learning ===
    MAX_ACTION_LOG = 20

    LOG_FILE = File.expand_path('../../../../.claude/sanetrack.log', __dir__)

    def self.track_edit(tool_name, tool_input, tool_response)
      return unless EDIT_TOOLS.include?(tool_name)

      file_path = tool_input['file_path'] || tool_input[:file_path]
      return unless file_path

      StateManager.update(:edits) do |e|
        e[:count] = (e[:count] || 0) + 1
        e[:unique_files] ||= []
        e[:unique_files] << file_path unless e[:unique_files].include?(file_path)
        e[:last_file] = file_path
        e
      end
    end

    def self.track_mcp_verification(tool_name, success)
      mcp_name = nil
      MCP_VERIFICATION_PATTERNS.each do |mcp, pattern|
        if tool_name.match?(pattern)
          mcp_name = mcp
          break
        end
      end

      return unless mcp_name

      StateManager.update(:mcp_health) do |health|
        health[:mcps] ||= {}
        health[:mcps][mcp_name] ||= { verified: false, last_success: nil, last_failure: nil, failure_count: 0 }

        if success
          health[:mcps][mcp_name][:verified] = true
          health[:mcps][mcp_name][:last_success] = Time.now.iso8601
          
          all_verified = MCP_VERIFICATION_PATTERNS.keys.all? do |mcp|
            health[:mcps][mcp] && health[:mcps][mcp][:verified]
          end

          if all_verified && !health[:verified_this_session]
            health[:verified_this_session] = true
            health[:last_verified] = Time.now.iso8601
            warn '✅ ALL MCPs VERIFIED - edits now allowed'
          end
        else
          health[:mcps][mcp_name][:last_failure] = Time.now.iso8601
          health[:mcps][mcp_name][:failure_count] = (health[:mcps][mcp_name][:failure_count] || 0) + 1
        end

        health
      end
    rescue StandardError => e
      warn "⚠️  MCP tracking error: #{e.message}"
    end

    def self.track_failure(tool_name, tool_response, error_pattern)
      return unless FAILURE_TOOLS.include?(tool_name)

      response_str = tool_response.to_s
      is_failure = response_str.match?(error_pattern)

      return unless is_failure

      StateManager.update(:circuit_breaker) do |cb|
        cb[:failures] = (cb[:failures] || 0) + 1
        cb[:last_error] = response_str[0..200]

        if cb[:failures] >= 3 && !cb[:tripped]
          cb[:tripped] = true
          cb[:tripped_at] = Time.now.iso8601
        end

        cb
      end
    end

    def self.reset_failure_count(tool_name)
      return unless FAILURE_TOOLS.include?(tool_name)

      cb = StateManager.get(:circuit_breaker)
      return if cb[:failures] == 0

      StateManager.update(:circuit_breaker) do |c|
        c[:failures] = 0
        c[:last_error] = nil unless c[:tripped]
        c
      end
    end

    def self.log_action_for_learning(tool_name, tool_input, success, error_sig = nil)
      StateManager.update(:action_log) do |log|
        log ||= []
        log << {
          tool: tool_name,
          timestamp: Time.now.iso8601,
          success: success,
          error_sig: error_sig,
          input_summary: summarize_input(tool_input)
        }
        log.last(MAX_ACTION_LOG)
      end
    rescue StandardError
      # Don't fail on logging errors
    end

    def self.summarize_input(input)
      return nil unless input.is_a?(Hash)
      input['file_path'] || input[:file_path] ||
        input['command']&.to_s&.slice(0, 50) || input[:command]&.to_s&.slice(0, 50) ||
        input['prompt']&.to_s&.slice(0, 50) || input[:prompt]&.to_s&.slice(0, 50)
    end

    def self.log_action(tool_name, result_type)
      FileUtils.mkdir_p(File.dirname(LOG_FILE))
      entry = {
        timestamp: Time.now.iso8601,
        tool: tool_name,
        result: result_type,
        pid: Process.pid
      }
      File.open(LOG_FILE, 'a') { |f| f.puts(entry.to_json) }
    rescue StandardError
      # Don't fail on logging errors
    end
  end
end
