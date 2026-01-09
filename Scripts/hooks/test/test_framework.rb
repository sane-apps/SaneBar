#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Test Framework - Lightweight Parameterized Testing
# ==============================================================================
# Infrastructure for 100+ tests per workflow without external dependencies.
#
# Usage:
#   require_relative 'test_framework'
#   include TestFramework
#
#   parameterized_test("Passthrough", CASES) do |input, expected|
#     assert_eq(classify(input), expected)
#   end
# ==============================================================================

module TestFramework
  PASS = '✅'
  FAIL = '❌'

  class TestResults
    attr_reader :passed, :failed, :failures, :categories

    def initialize
      @passed = 0
      @failed = 0
      @failures = []
      @categories = Hash.new { |h, k| h[k] = { passed: 0, failed: 0 } }
      @current_category = nil
    end

    def record_pass(name, category = nil)
      @passed += 1
      cat = category || @current_category
      @categories[cat][:passed] += 1 if cat
    end

    def record_fail(name, message, category = nil)
      @failed += 1
      cat = category || @current_category
      @failures << { name: name, message: message, category: cat }
      @categories[cat][:failed] += 1 if cat
    end

    def set_category(cat)
      @current_category = cat
    end

    def total
      @passed + @failed
    end

    def success?
      @failed == 0
    end

    def summary
      lines = ['', '=' * 60]
      lines << "RESULTS: #{@passed}/#{total} passed (#{@failed} failed)"
      lines << '=' * 60

      if @categories.any?
        lines << ''
        lines << 'By Category:'
        @categories.each do |cat, stats|
          lines << "  #{cat}: #{stats[:passed]}/#{stats[:passed] + stats[:failed]}"
        end
      end

      if @failures.any?
        lines << ''
        lines << "Failures (#{@failures.length}):"
        @failures.first(10).each do |f|
          lines << "  #{FAIL} #{f[:name]}"
          lines << "     #{f[:message]}"
        end
        lines << "  ... and #{@failures.length - 10} more" if @failures.length > 10
      end

      lines.join("\n")
    end
  end

  @results = TestResults.new

  class << self
    attr_accessor :results
  end

  def self.reset_results
    @results = TestResults.new
  end

  # === PARAMETERIZED TESTING ===

  def parameterized_test(name, cases, category: nil, verbose: false)
    TestFramework.results.set_category(category) if category
    warn "\n#{name} (#{cases.length} cases):"

    cases.each_with_index do |tc, idx|
      input = tc[:input]
      expected = tc[:expected] || tc[:expect]
      test_name = tc[:name] || "#{name}[#{idx}]"

      begin
        result = yield(input, expected, tc)
        if result == true || result.nil?
          TestFramework.results.record_pass(test_name, category)
          warn "  #{PASS} #{test_name}" if verbose
        else
          TestFramework.results.record_fail(test_name, "Got: #{result.inspect}", category)
          warn "  #{FAIL} #{test_name}: expected #{expected.inspect}, got #{result.inspect}"
        end
      rescue StandardError => e
        TestFramework.results.record_fail(test_name, e.message, category)
        warn "  #{FAIL} #{test_name}: #{e.message}"
      end
    end
  end

  def test(name, category: nil)
    TestFramework.results.set_category(category) if category
    begin
      result = yield
      if result
        TestFramework.results.record_pass(name, category)
        warn "  #{PASS} #{name}"
      else
        TestFramework.results.record_fail(name, 'Returned false', category)
        warn "  #{FAIL} #{name}"
      end
    rescue StandardError => e
      TestFramework.results.record_fail(name, e.message, category)
      warn "  #{FAIL} #{name}: #{e.message}"
    end
  end

  def test_category(name)
    TestFramework.results.set_category(name)
    warn "\n#{name}:"
    warn '-' * 40
    yield
  end

  # === ASSERTIONS ===

  def assert(condition, message = 'Assertion failed')
    raise message unless condition

    true
  end

  def assert_eq(actual, expected, message = nil)
    return true if actual == expected

    raise message || "Expected #{expected.inspect}, got #{actual.inspect}"
  end

  def assert_match(string, pattern, message = nil)
    return true if string.to_s.match?(pattern)

    raise message || "Expected to match #{pattern.inspect}"
  end

  def assert_includes(collection, item, message = nil)
    return true if collection.include?(item)

    raise message || "Expected to include #{item.inspect}"
  end

  # === TEST RUNNER ===

  def run_tests(name = 'Tests')
    TestFramework.reset_results
    warn '=' * 60
    warn name
    warn '=' * 60
    yield
    warn TestFramework.results.summary
    TestFramework.results.success? ? 0 : 1
  end
end

# === TEST DATA ===

module TestData
  # 35 passthrough prompts
  PASSTHROUGH = [
    { input: 'y', expected: :passthrough },
    { input: 'n', expected: :passthrough },
    { input: 'Y', expected: :passthrough },
    { input: 'N', expected: :passthrough },
    { input: 'yes', expected: :passthrough },
    { input: 'no', expected: :passthrough },
    { input: 'Yes', expected: :passthrough },
    { input: 'No', expected: :passthrough },
    { input: 'YES', expected: :passthrough },
    { input: 'NO', expected: :passthrough },
    { input: 'ok', expected: :passthrough },
    { input: 'OK', expected: :passthrough },
    { input: 'Ok', expected: :passthrough },
    { input: 'done', expected: :passthrough },
    { input: 'Done', expected: :passthrough },
    { input: 'continue', expected: :passthrough },
    { input: 'Continue', expected: :passthrough },
    { input: 'approved', expected: :passthrough },
    { input: 'cancel', expected: :passthrough },
    { input: 'sure', expected: :passthrough },
    { input: 'thanks', expected: :passthrough },
    { input: 'thx', expected: :passthrough },
    { input: '/commit', expected: :passthrough },
    { input: '/help', expected: :passthrough },
    { input: '/clear', expected: :passthrough },
    { input: '/status', expected: :passthrough },
    { input: '/init', expected: :passthrough },
    { input: '123', expected: :passthrough },
    { input: '42', expected: :passthrough },
    { input: '!!!', expected: :passthrough },
    { input: '???', expected: :passthrough },
    { input: '...', expected: :passthrough },
    { input: 'hi', expected: :passthrough },
    { input: 'hey', expected: :passthrough },
    { input: 'k', expected: :passthrough },
  ].freeze

  # 25 question prompts
  QUESTIONS = [
    { input: 'what does this function do?', expected: :question },
    { input: 'What is the purpose of this file?', expected: :question },
    { input: 'where is the config file?', expected: :question },
    { input: 'Where are errors handled?', expected: :question },
    { input: 'when was this last updated?', expected: :question },
    { input: 'why is this implemented this way?', expected: :question },
    { input: 'Why does this crash?', expected: :question },
    { input: 'how does the authentication work?', expected: :question },
    { input: 'How do I run tests?', expected: :question },
    { input: 'which file handles routing?', expected: :question },
    { input: 'who wrote this code?', expected: :question },
    { input: 'can you explain the architecture?', expected: :question },
    { input: 'Can you explain how this works?', expected: :question },
    { input: 'tell me about the database schema', expected: :question },
    { input: 'Tell me about this pattern', expected: :question },
    { input: 'is this the right approach?', expected: :question },
    { input: 'Is this correct?', expected: :question },
    { input: 'should I use this pattern?', expected: :question },
    { input: 'are there any edge cases?', expected: :question },
    { input: 'does this handle errors?', expected: :question },
    { input: 'could this cause problems?', expected: :question },
    { input: 'would this work better?', expected: :question },
    { input: 'does this function return nil?', expected: :question },
    { input: 'is the test passing?', expected: :question },
    { input: 'do we have tests for this?', expected: :question },
  ].freeze

  # 35 task prompts
  TASKS = [
    { input: 'fix the bug in the login flow', expected: :task },
    { input: 'Fix the crash on startup', expected: :task },
    { input: 'fix this error', expected: :task },
    { input: 'Fix the failing tests', expected: :task },
    { input: 'add a new feature for user auth', expected: :task },
    { input: 'Add a logout button', expected: :task },
    { input: 'add error handling', expected: :task },
    { input: 'Add validation to the form', expected: :task },
    { input: 'create a new file for settings', expected: :task },
    { input: 'Create a test for this function', expected: :task },
    { input: 'create a model for users', expected: :task },
    { input: 'implement the search feature', expected: :task },
    { input: 'Implement dark mode', expected: :task },
    { input: 'implement caching', expected: :task },
    { input: 'build the API endpoint', expected: :task },
    { input: 'Build the settings page', expected: :task },
    { input: 'refactor the database layer', expected: :task },
    { input: 'Refactor this function', expected: :task },
    { input: 'refactor to use async/await', expected: :task },
    { input: 'update the config file', expected: :task },
    { input: 'Update the dependencies', expected: :task },
    { input: 'change the button color', expected: :task },
    { input: 'modify the response format', expected: :task },
    { input: 'delete the unused code', expected: :task },
    { input: 'Remove the deprecated function', expected: :task },
    { input: 'remove this file', expected: :task },
    { input: 'there is a bug in the parser', expected: :task },
    { input: 'I found an error in the tests', expected: :task },
    { input: 'this is broken, please investigate', expected: :task },
    { input: 'the app is crashing on launch', expected: :task },
    { input: 'write a function to validate emails', expected: :task },
    { input: 'make this work with the new API', expected: :task },
    { input: 'generate mocks for the tests', expected: :task },
    { input: 'set up the CI pipeline', expected: :task },
    { input: 'rewrite this function to be cleaner', expected: :task },
  ].freeze

  # 20 big task prompts
  BIG_TASKS = [
    { input: 'rewrite the entire authentication system', expected: :big_task },
    { input: 'refactor everything in the core module', expected: :big_task },
    { input: 'update all the components to use new API', expected: :big_task },
    { input: 'fix all the type errors', expected: :big_task },
    { input: 'review the entire codebase', expected: :big_task },
    { input: 'redesign the whole UI', expected: :big_task },
    { input: 'do a complete rewrite of the module', expected: :big_task },
    { input: 'implement the full feature set', expected: :big_task },
    { input: 'overhaul the database schema', expected: :big_task },
    { input: 'redesign the API layer', expected: :big_task },
    { input: 'rewrite this from scratch', expected: :big_task },
    { input: 'change the entire architecture', expected: :big_task },
    { input: 'rebuild the system from scratch', expected: :big_task },
    { input: 'implement a new framework', expected: :big_task },
    { input: 'migrate the entire infrastructure', expected: :big_task },
    { input: 'update multiple files to use the new pattern', expected: :big_task },
    { input: 'refactor multiple components', expected: :big_task },
    { input: 'fix issues across multiple modules', expected: :big_task },
    { input: 'overhaul the whole test suite', expected: :big_task },
    { input: 'redesign the complete data flow', expected: :big_task },
  ].freeze

  # 25 blocked paths
  BLOCKED_PATHS = [
    { input: '~/.ssh/id_rsa', expected: :blocked },
    { input: '~/.ssh/id_ed25519', expected: :blocked },
    { input: '~/.ssh/config', expected: :blocked },
    { input: '~/.ssh/known_hosts', expected: :blocked },
    { input: '/home/user/.ssh/id_rsa', expected: :blocked },
    { input: '/Users/user/.ssh/id_rsa', expected: :blocked },
    { input: '~/.aws/credentials', expected: :blocked },
    { input: '~/.aws/config', expected: :blocked },
    { input: '/home/user/.aws/credentials', expected: :blocked },
    { input: '/etc/passwd', expected: :blocked },
    { input: '/etc/shadow', expected: :blocked },
    { input: '/etc/hosts', expected: :blocked },
    { input: '/etc/sudoers', expected: :blocked },
    { input: '/var/log/auth.log', expected: :blocked },
    { input: '/var/run/secrets', expected: :blocked },
    { input: '/usr/bin/ruby', expected: :blocked },
    { input: '/System/Library', expected: :blocked },
    { input: '/project/.git/objects/abc123', expected: :blocked },
    { input: '/project/.git/objects/pack', expected: :blocked },
    { input: '/app/credentials.json', expected: :blocked },
    { input: '/app/.env', expected: :blocked },
    { input: '/home/user/.netrc', expected: :blocked },
    { input: '/app/.claude_hook_secret', expected: :blocked },
    { input: '/var/tmp/../etc/passwd', expected: :blocked },
    { input: '/tmp/../etc/shadow', expected: :blocked },
  ].freeze

  # 15 allowed paths
  ALLOWED_PATHS = [
    { input: '/Users/sj/SaneProcess/test.swift', expected: :allowed },
    { input: '/Users/sj/SaneProcess/src/main.rb', expected: :allowed },
    { input: '/tmp/test.txt', expected: :allowed },
    { input: '/project/README.md', expected: :allowed },
    { input: '/project/package.json', expected: :allowed },
    { input: '/project/Gemfile', expected: :allowed },
    { input: '/project/Makefile', expected: :allowed },
    { input: '/project/.gitignore', expected: :allowed },
    { input: '/project/.github/workflows/ci.yml', expected: :allowed },
    { input: '/project/config/database.yml', expected: :allowed },
    { input: '/project/.rubocop.yml', expected: :allowed },
    { input: '/project/.swiftlint.yml', expected: :allowed },
    { input: '/project/src/app.swift', expected: :allowed },
    { input: '/project/tests/test_app.rb', expected: :allowed },
    { input: '/project/lib/utils.rb', expected: :allowed },
  ].freeze

  # 25 error patterns
  ERROR_PATTERNS = [
    { input: 'bash: ruby: command not found', expected: 'COMMAND_NOT_FOUND' },
    { input: 'npm: command not found', expected: 'COMMAND_NOT_FOUND' },
    { input: "'foo' is not recognized as a command", expected: 'COMMAND_NOT_FOUND' },
    { input: 'zsh: command not found: xyz', expected: 'COMMAND_NOT_FOUND' },
    { input: 'sh: node: command not found', expected: 'COMMAND_NOT_FOUND' },
    { input: 'Permission denied (publickey)', expected: 'PERMISSION_DENIED' },
    { input: 'access denied for user', expected: 'PERMISSION_DENIED' },
    { input: 'Operation not permitted', expected: 'PERMISSION_DENIED' },
    { input: 'sudo: permission denied', expected: 'PERMISSION_DENIED' },
    { input: 'No such file or directory', expected: 'FILE_NOT_FOUND' },
    { input: 'File not found: config.yml', expected: 'FILE_NOT_FOUND' },
    { input: "path/to/file doesn't exist", expected: 'FILE_NOT_FOUND' },
    { input: 'Build failed with exit code 1', expected: 'BUILD_FAILED' },
    { input: 'Compilation error on line 42', expected: 'BUILD_FAILED' },
    { input: 'compile error: unexpected token', expected: 'BUILD_FAILED' },
    { input: 'syntax error, unexpected end', expected: 'SYNTAX_ERROR' },
    { input: 'Parse error on line 10', expected: 'SYNTAX_ERROR' },
    { input: 'unexpected token in JSON', expected: 'SYNTAX_ERROR' },
    { input: 'TypeError: undefined is not a function', expected: 'TYPE_ERROR' },
    { input: 'cannot convert String to Integer', expected: 'TYPE_ERROR' },
    { input: 'type mismatch: expected Int, got String', expected: 'TYPE_ERROR' },
    { input: 'Connection refused', expected: 'NETWORK_ERROR' },
    { input: 'Request timeout after 30s', expected: 'NETWORK_ERROR' },
    { input: 'Out of memory', expected: 'MEMORY_ERROR' },
    { input: 'memory allocation failed', expected: 'MEMORY_ERROR' },
  ].freeze

  def self.all_prompts
    PASSTHROUGH + QUESTIONS + TASKS + BIG_TASKS
  end

  def self.all_paths
    BLOCKED_PATHS + ALLOWED_PATHS
  end

  def self.counts
    {
      passthrough: PASSTHROUGH.length,
      questions: QUESTIONS.length,
      tasks: TASKS.length,
      big_tasks: BIG_TASKS.length,
      blocked_paths: BLOCKED_PATHS.length,
      allowed_paths: ALLOWED_PATHS.length,
      error_patterns: ERROR_PATTERNS.length,
      total_prompts: all_prompts.length,
      total_paths: all_paths.length
    }
  end
end

# === SELF TEST ===

if __FILE__ == $PROGRAM_NAME
  include TestFramework

  exit_code = run_tests('Test Framework Self-Test') do
    test_category('Framework') do
      test('TestResults tracks pass') do
        r = TestFramework::TestResults.new
        r.record_pass('t1')
        r.passed == 1
      end

      test('TestResults tracks fail') do
        r = TestFramework::TestResults.new
        r.record_fail('t1', 'err')
        r.failed == 1 && r.failures.length == 1
      end

      test('success? true when no failures') do
        r = TestFramework::TestResults.new
        r.record_pass('t1')
        r.success?
      end
    end

    test_category('TestData Counts') do
      c = TestData.counts
      test("passthrough >= 30: #{c[:passthrough]}") { c[:passthrough] >= 30 }
      test("questions >= 20: #{c[:questions]}") { c[:questions] >= 20 }
      test("tasks >= 30: #{c[:tasks]}") { c[:tasks] >= 30 }
      test("big_tasks >= 15: #{c[:big_tasks]}") { c[:big_tasks] >= 15 }
      test("blocked_paths >= 20: #{c[:blocked_paths]}") { c[:blocked_paths] >= 20 }
      test("error_patterns >= 20: #{c[:error_patterns]}") { c[:error_patterns] >= 20 }
      test("total_prompts >= 100: #{c[:total_prompts]}") { c[:total_prompts] >= 100 }
    end
  end

  warn "\nTest data: #{TestData.counts[:total_prompts]} prompts, #{TestData.counts[:total_paths]} paths"
  exit exit_code
end
