# frozen_string_literal: true

require_relative 'framework'

module TierTests
  def self.test_sanetrack
    t = Runner.new('sanetrack')
    warn "\n=== SANETRACK TESTS ==="

    warn "\n  [EASY] Basic tracking"

    t.test(:easy, "tracks memory: mcp__memory__read_graph", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__memory__read_graph',
        'tool_input' => {},
        'tool_result' => { 'entities' => [] }
      })
    end

    t.test(:easy, "tracks memory: mcp__memory__search_nodes", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__memory__search_nodes',
        'tool_input' => { 'query' => 'bug' },
        'tool_result' => { 'entities' => [] }
      })
    end

    t.test(:easy, "tracks local: Read", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/test.txt' },
        'tool_result' => 'file content here'
      })
    end

    t.test(:easy, "tracks local: Grep", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Grep',
        'tool_input' => { 'pattern' => 'test' },
        'tool_result' => 'test.rb:50: match'
      })
    end

    t.test(:easy, "tracks local: Glob", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Glob',
        'tool_input' => { 'pattern' => '*.swift' },
        'tool_result' => ['file1.swift', 'file2.swift']
      })
    end

    t.test(:easy, "tracks web: WebSearch", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'WebSearch',
        'tool_input' => { 'query' => 'test' },
        'tool_result' => 'search results'
      })
    end

    t.test(:easy, "tracks web: WebFetch", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'WebFetch',
        'tool_input' => { 'url' => 'https://example.com' },
        'tool_result' => 'page content'
      })
    end

    t.test(:easy, "tracks docs: apple-docs MCP", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__apple-docs__search_apple_docs',
        'tool_input' => { 'query' => 'SwiftUI' },
        'tool_result' => 'documentation'
      })
    end

    t.test(:easy, "tracks docs: context7 MCP", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__context7__query-docs',
        'tool_input' => { 'libraryId' => '/test', 'query' => 'api' },
        'tool_result' => 'documentation'
      })
    end

    t.test(:easy, "tracks github: mcp__github__*", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__github__search_repositories',
        'tool_input' => { 'query' => 'test' },
        'tool_result' => 'repositories'
      })
    end

    t.test(:easy, "detects Bash failure (exit 1)", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'false' },
        'tool_result' => '',
        'is_error' => true
      })
    end

    t.test(:easy, "detects success (exit 0)", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'true' },
        'tool_result' => ''
      })
    end

    t.test(:easy, "detects Edit success", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => { 'file_path' => '/tmp/test.rb' },
        'tool_result' => 'File edited'
      })
    end

    t.test(:easy, "detects Read success", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/test.txt' },
        'tool_result' => 'contents'
      })
    end

    t.test(:easy, "tracks Task agent", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Task',
        'tool_input' => { 'prompt' => 'search codebase' },
        'tool_result' => 'found patterns'
      })
    end

    warn "\n  [HARD] Edge cases"

    [
      { input: 'bash: foo: command not found', sig: 'COMMAND_NOT_FOUND' },
      { input: 'error: unable to access', sig: 'ACCESS_DENIED' },
      { input: 'No such file or directory', sig: 'FILE_NOT_FOUND' },
      { input: 'TypeError: undefined', sig: 'TYPE_ERROR' },
      { input: 'SyntaxError: unexpected', sig: 'SYNTAX_ERROR' },
      { input: 'Permission denied', sig: 'PERMISSION_DENIED' },
      { input: 'Connection refused', sig: 'CONNECTION_ERROR' },
      { input: 'Timeout waiting for', sig: 'TIMEOUT' },
      { input: 'fatal: not a git repository', sig: 'GIT_ERROR' },
      { input: 'Build failed with exit code 1', sig: 'BUILD_FAILED' }
    ].each do |tc|
      t.test(:hard, "error signature: #{tc[:sig]}", expected_exit: 0) do
        t.run_hook({
          'tool_name' => 'Bash',
          'tool_input' => { 'command' => 'test' },
          'tool_result' => tc[:input],
          'is_error' => true
        })
      end
    end

    t.test(:hard, "NOT failure: Read file containing 'error'", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/test.txt' },
        'tool_result' => 'This file contains the word error but is not a failure'
      })
    end

    t.test(:hard, "NOT failure: Grep for 'fail'", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Grep',
        'tool_input' => { 'pattern' => 'fail' },
        'tool_result' => 'failure_handler.rb:50'
      })
    end

    t.test(:hard, "NOT failure: Read crash log", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/crash.log' },
        'tool_result' => 'Exception: NullPointerException at line 50'
      })
    end

    t.test(:hard, "NOT failure: Grep error patterns", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Grep',
        'tool_input' => { 'pattern' => 'command not found' },
        'tool_result' => 'docs/errors.md:50: handle command not found'
      })
    end

    t.test(:hard, "NOT failure: file has exit code in content", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/test.txt' },
        'tool_result' => 'exit code 1 means failure'
      })
    end

    t.test(:hard, "circuit breaker: 1 failure", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'test' },
        'tool_result' => 'command not found',
        'is_error' => true
      })
    end

    t.test(:hard, "circuit breaker: 2 failures", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'test2' },
        'tool_result' => 'command not found',
        'is_error' => true
      })
    end

    t.test(:hard, "circuit breaker: success resets", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'ls' },
        'tool_result' => 'file1 file2'
      })
    end

    t.test(:hard, "circuit breaker: mixed errors", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'test' },
        'tool_result' => 'Permission denied',
        'is_error' => true
      })
    end

    t.test(:hard, "tautology: self-comparison x == x", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => {
          'file_path' => '/tmp/MyTests.swift',
          'new_string' => '#expect(value == value)'
        }
      })
    end

    t.test(:hard, "tautology: count >= 0 always true", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => {
          'file_path' => '/tmp/MyTests.swift',
          'new_string' => '#expect(array.count >= 0)'
        }
      })
    end

    t.test(:hard, "tautology: empty assertion", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => {
          'file_path' => '/tmp/MyTests.swift',
          'new_string' => '#expect()'
        }
      })
    end

    t.test(:hard, "tautology: XCTAssertEqual self", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => {
          'file_path' => '/tmp/MyTests.swift',
          'new_string' => 'XCTAssertEqual(result, result)'
        }
      })
    end

    t.test(:hard, "NOT tautology: valid assertion", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => {
          'file_path' => '/tmp/MyTests.swift',
          'new_string' => '#expect(result.count == 3)'
        }
      })
    end

    t.test(:hard, "Task agent: no result tracking", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Task',
        'tool_input' => { 'prompt' => 'find files' },
        'tool_result' => nil
      })
    end

    warn "\n  [VILLAIN] Gaming attempts"

    t.test(:villain, "hidden error: success with error text", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'echo "Error: something failed" && exit 0' },
        'tool_result' => 'Error: something failed',
        'is_error' => false
      })
    end

    t.test(:villain, "hidden error: partial success", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'command 2>/dev/null; exit 0' },
        'tool_result' => '',
        'is_error' => false
      })
    end

    t.test(:villain, "hidden error: ignored exit code", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'false || true' },
        'tool_result' => '',
        'is_error' => false
      })
    end

    t.test(:villain, "empty research: Read empty file", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/empty.txt' },
        'tool_result' => ''
      })
    end

    t.test(:villain, "empty research: Grep no matches", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Grep',
        'tool_input' => { 'pattern' => 'nonexistent' },
        'tool_result' => ''
      })
    end

    t.test(:villain, "empty research: WebSearch no results", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'WebSearch',
        'tool_input' => { 'query' => 'asdfqwerzxcv1234' },
        'tool_result' => 'No results found'
      })
    end

    t.test(:villain, "empty research: memory empty graph", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__memory__read_graph',
        'tool_input' => {},
        'tool_result' => { 'entities' => [], 'relations' => [] }
      })
    end

    t.test(:villain, "empty research: Task no output", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Task',
        'tool_input' => { 'prompt' => 'search for nonexistent' },
        'tool_result' => 'No results found'
      })
    end

    t.test(:villain, "repeated same research", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/same.txt' },
        'tool_result' => 'same content'
      })
    end

    t.test(:villain, "research after edit started", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/late.txt' },
        'tool_result' => 'late research'
      })
    end

    t.test(:villain, "claim Task did research", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Task',
        'tool_input' => { 'prompt' => 'I already researched this' },
        'tool_result' => 'claim: research done'
      })
    end

    t.test(:villain, "fast research timing", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/fast.txt' },
        'tool_result' => 'fast'
      })
    end

    t.test(:villain, "success despite error in output", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'npm test' },
        'tool_result' => 'FAIL src/test.js',
        'is_error' => false
      })
    end

    t.test(:villain, "Edit claimed success but failed", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => { 'file_path' => '/tmp/test.rb' },
        'tool_result' => 'Edit conflict: file changed',
        'is_error' => true
      })
    end

    t.test(:villain, "multiple errors same signature", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'test3' },
        'tool_result' => 'command not found',
        'is_error' => true
      })
    end

    t.summary
  end
end
