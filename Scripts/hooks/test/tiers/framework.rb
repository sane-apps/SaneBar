# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'

module TierTests
  HOOKS_DIR = File.expand_path('../..', __dir__)
  PROJECT_DIR = File.expand_path('../../../..', __dir__)

  class Runner
    PASS = '✅'
    FAIL = '❌'
    SKIP = '⏭️'

    attr_reader :passed, :failed, :skipped, :results

    def initialize(hook_name)
      @hook_name = hook_name
      @passed = 0
      @failed = 0
      @skipped = 0
      @results = { easy: [], hard: [], villain: [] }
    end

    def run_hook(stdin_data, env = {})
      hook_path = File.join(HOOKS_DIR, "#{@hook_name}.rb")
      env_with_defaults = {
        'CLAUDE_PROJECT_DIR' => PROJECT_DIR,
        'TIER_TEST_MODE' => 'true'
      }.merge(env)

      stdout, stderr, status = Open3.capture3(
        env_with_defaults,
        'ruby', hook_path,
        stdin_data: stdin_data.to_json
      )

      {
        stdout: stdout,
        stderr: stderr,
        exit_code: status.exitstatus,
        output: stdout + stderr
      }
    end

    def test(tier, name, expected_exit: nil, expected_output: nil, skip: false)
      if skip
        @skipped += 1
        @results[tier] << { name: name, status: :skipped, reason: 'Marked skip' }
        warn "  #{SKIP} #{name} (skipped)"
        return
      end

      result = yield

      passed = true
      failure_reason = nil

      if expected_exit && result[:exit_code] != expected_exit
        passed = false
        failure_reason = "Expected exit #{expected_exit}, got #{result[:exit_code]}"
      end

      if expected_output && !result[:output].include?(expected_output)
        passed = false
        failure_reason = "Expected output containing '#{expected_output}'"
      end

      if passed
        @passed += 1
        @results[tier] << { name: name, status: :passed }
        warn "  #{PASS} #{name}"
      else
        @failed += 1
        @results[tier] << { name: name, status: :failed, reason: failure_reason }
        warn "  #{FAIL} #{name}"
        warn "      #{failure_reason}" if failure_reason
      end
    end

    def summary
      easy = @results[:easy].count { |r| r[:status] == :passed }
      hard = @results[:hard].count { |r| r[:status] == :passed }
      villain = @results[:villain].count { |r| r[:status] == :passed }

      easy_total = @results[:easy].length
      hard_total = @results[:hard].length
      villain_total = @results[:villain].length

      {
        hook: @hook_name,
        passed: @passed,
        failed: @failed,
        skipped: @skipped,
        total: @passed + @failed + @skipped,
        by_tier: {
          easy: "#{easy}/#{easy_total}",
          hard: "#{hard}/#{hard_total}",
          villain: "#{villain}/#{villain_total}"
        }
      }
    end
  end
end
