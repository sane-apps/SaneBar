#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Config - Centralized Configuration for All Hooks
# ==============================================================================
# Single source of truth for all paths, thresholds, and settings.
# All hooks should require this and use Config.* instead of defining paths locally.
#
# Usage:
#   require_relative 'core/config'
#   Config.state_file        # => /path/to/project/.claude/state.json
#   Config.bypass_active?    # => true/false
# ==============================================================================

require 'fileutils'

module Config
  class << self
    # === DIRECTORIES ===

    def project_dir
      @project_dir ||= ENV['CLAUDE_PROJECT_DIR'] || find_project_root || Dir.pwd
    end

    def claude_dir
      @claude_dir ||= File.join(project_dir, '.claude')
    end

    def hooks_dir
      @hooks_dir ||= File.expand_path('..', __dir__)
    end

    # === STATE FILE (unified) ===

    def state_file
      @state_file ||= File.join(claude_dir, 'state.json')
    end

    def state_lock_file
      @state_lock_file ||= "#{state_file}.lock"
    end

    # === BYPASS FILE ===

    def bypass_file
      @bypass_file ||= File.join(claude_dir, 'bypass_active.json')
    end

    def bypass_active?
      File.exist?(bypass_file)
    end

    # === LOG FILES ===

    def saneprompt_log
      @saneprompt_log ||= File.join(claude_dir, 'saneprompt.log')
    end

    def sanetools_log
      @sanetools_log ||= File.join(claude_dir, 'sanetools.log')
    end

    def sanetrack_log
      @sanetrack_log ||= File.join(claude_dir, 'sanetrack.log')
    end

    def sanestop_log
      @sanestop_log ||= File.join(claude_dir, 'sanestop.log')
    end

    def audit_log
      @audit_log ||= File.join(claude_dir, 'audit.jsonl')
    end

    def prompt_log
      @prompt_log ||= File.join(claude_dir, 'prompt_log.jsonl')
    end

    # === THRESHOLDS ===

    def circuit_breaker_threshold
      3
    end

    def file_size_warning
      500
    end

    def file_size_limit
      800
    end

    def max_action_log
      20
    end

    # === BLOCKED PATHS ===

    def blocked_paths
      @blocked_paths ||= %w[
        /etc/ /var/ /usr/ /bin/ /sbin/
        /System/ /Library/
        .ssh/ .gnupg/ .aws/ .kube/ .docker/
      ].freeze
    end

    # === HELPERS ===

    def ensure_claude_dir
      FileUtils.mkdir_p(claude_dir)
    end

    def find_project_root
      dir = Dir.pwd
      while dir != '/'
        return dir if File.exist?(File.join(dir, '.claude'))
        return dir if File.exist?(File.join(dir, '.git'))

        dir = File.dirname(dir)
      end
      nil
    end

    def reset!
      instance_variables.each { |var| instance_variable_set(var, nil) }
    end

    # === SELF-TEST ===

    def self_test
      warn 'Config Self-Test'
      warn '=' * 40

      passed = 0
      failed = 0

      tests = [
        ['project_dir exists', -> { !project_dir.nil? && !project_dir.empty? }],
        ['state_file ends with state.json', -> { state_file.end_with?('state.json') }],
        ['bypass_file ends with bypass_active.json', -> { bypass_file.end_with?('bypass_active.json') }],
        ['thresholds are positive', -> { circuit_breaker_threshold.positive? && file_size_limit.positive? }],
        ['blocked_paths is frozen array', -> { blocked_paths.is_a?(Array) && blocked_paths.frozen? }]
      ]

      tests.each do |name, test|
        if test.call
          passed += 1
          warn "  PASS: #{name}"
        else
          failed += 1
          warn "  FAIL: #{name}"
        end
      end

      warn ''
      warn "#{passed}/#{passed + failed} tests passed"
      warn ''
      warn(failed.zero? ? 'ALL TESTS PASSED' : "#{failed} TESTS FAILED")
      failed.zero? ? 0 : 1
    end
  end
end

# === MAIN ===

if __FILE__ == $PROGRAM_NAME
  if ARGV.include?('--self-test')
    exit Config.self_test
  elsif ARGV.include?('--show')
    warn "project_dir:  #{Config.project_dir}"
    warn "claude_dir:   #{Config.claude_dir}"
    warn "state_file:   #{Config.state_file}"
    warn "bypass_file:  #{Config.bypass_file}"
    warn "bypass_active: #{Config.bypass_active?}"
  else
    warn 'Usage: ruby config.rb [--self-test|--show]'
  end
end
