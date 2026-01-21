# frozen_string_literal: true

require_relative 'framework'

module TierTests
  def self.test_sanestop
    t = Runner.new('sanestop')
    warn "\n=== SANESTOP TESTS ==="

    warn "\n  [EASY] Valid session operations"

    t.test(:easy, "allow stop with 0 edits", expected_exit: 0) do
      t.run_hook({
        'stop_hook_active' => true,
        'edit_count' => 0
      })
    end

    t.test(:easy, "valid session end", expected_exit: 0) do
      t.run_hook({
        'session_id' => 'test-123'
      })
    end

    t.test(:easy, "track session start", expected_exit: 0) do
      t.run_hook({
        'session_start' => true,
        'session_id' => 'new-session'
      })
    end

    t.test(:easy, "track edit count", expected_exit: 0) do
      t.run_hook({
        'edit_count' => 5,
        'unique_files' => ['a.rb', 'b.rb']
      })
    end

    t.test(:easy, "allow summary with edits", expected_exit: 0) do
      t.run_hook({
        'summary_provided' => true,
        'edit_count' => 3
      })
    end

    t.test(:easy, "track research completion", expected_exit: 0) do
      t.run_hook({
        'research_complete' => true,
        'research_categories' => 5
      })
    end

    t.test(:easy, "accept valid compliance score", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 8,
        'violations' => []
      })
    end

    t.test(:easy, "track unique files edited", expected_exit: 0) do
      t.run_hook({
        'unique_files' => ['file1.rb', 'file2.rb', 'file3.rb']
      })
    end

    t.test(:easy, "session with no changes", expected_exit: 0) do
      t.run_hook({
        'edit_count' => 0,
        'research_only' => true
      })
    end

    t.test(:easy, "valid followup items", expected_exit: 0) do
      t.run_hook({
        'followup_items' => ['item1', 'item2'],
        'session_complete' => true
      })
    end

    t.test(:easy, "summary has What Was Done", expected_exit: 0) do
      t.run_hook({
        'summary_section' => 'what_was_done',
        'content' => '1. Fixed bug\n2. Added test'
      })
    end

    t.test(:easy, "summary has SOP Compliance", expected_exit: 0) do
      t.run_hook({
        'summary_section' => 'sop_compliance',
        'score' => '8/10'
      })
    end

    t.test(:easy, "summary has Followup", expected_exit: 0) do
      t.run_hook({
        'summary_section' => 'followup',
        'items' => ['Review PR', 'Run full tests']
      })
    end

    t.test(:easy, "summary score matches violations", expected_exit: 0) do
      t.run_hook({
        'score' => 8,
        'violations' => ['Rule #3']
      })
    end

    t.test(:easy, "summary with evidence", expected_exit: 0) do
      t.run_hook({
        'evidence' => ['file.rb:50', 'test.rb:100']
      })
    end

    t.test(:easy, "allow partial compliance", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 6,
        'partial' => true
      })
    end

    t.test(:easy, "track time spent", expected_exit: 0) do
      t.run_hook({
        'duration_minutes' => 45
      })
    end

    t.test(:easy, "session metrics", expected_exit: 0) do
      t.run_hook({
        'metrics' => {
          'edits' => 5,
          'research_calls' => 10,
          'failures' => 2
        }
      })
    end

    t.test(:easy, "streak tracking", expected_exit: 0) do
      t.run_hook({
        'streak_count' => 3,
        'streak_type' => 'compliant'
      })
    end

    t.test(:easy, "learning captured", expected_exit: 0) do
      t.run_hook({
        'learning' => 'Actor isolation requires MainActor annotation'
      })
    end

    warn "\n  [HARD] Edge cases"

    t.test(:hard, "score at boundary: 10/10", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 10,
        'violations' => []
      })
    end

    t.test(:hard, "score at boundary: 1/10", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 1,
        'violations' => ['Rule #1', 'Rule #2', 'Rule #3', 'Rule #4']
      })
    end

    t.test(:hard, "score mismatch: high with violations", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 9,
        'violations' => ['Rule #2', 'Rule #3']
      })
    end

    t.test(:hard, "score mismatch: low without violations", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 3,
        'violations' => []
      })
    end

    t.test(:hard, "missing score section", expected_exit: 0) do
      t.run_hook({
        'summary_provided' => true,
        'compliance_score' => nil
      })
    end

    t.test(:hard, "empty summary sections", expected_exit: 0) do
      t.run_hook({
        'summary_section' => 'what_was_done',
        'content' => ''
      })
    end

    t.test(:hard, "summary with markdown", expected_exit: 0) do
      t.run_hook({
        'summary_format' => 'markdown',
        'content' => '## What Was Done\n- Item 1'
      })
    end

    t.test(:hard, "summary without followup", expected_exit: 0) do
      t.run_hook({
        'summary_provided' => true,
        'followup_items' => []
      })
    end

    t.test(:hard, "vague rule citations", expected_exit: 0) do
      t.run_hook({
        'followed_rules' => ['Rule #2'],
        'evidence' => []
      })
    end

    t.test(:hard, "specific citations with evidence", expected_exit: 0) do
      t.run_hook({
        'followed_rules' => ['Rule #2'],
        'evidence' => ['ran mcp__memory__read_graph', 'checked docs']
      })
    end

    t.test(:hard, "session interrupted", expected_exit: 0) do
      t.run_hook({
        'session_interrupted' => true,
        'edit_count' => 3
      })
    end

    t.test(:hard, "session timeout", expected_exit: 0) do
      t.run_hook({
        'session_timeout' => true,
        'duration_minutes' => 120
      })
    end

    t.test(:hard, "multiple sessions same day", expected_exit: 0) do
      t.run_hook({
        'session_number' => 3,
        'date' => '2026-01-04'
      })
    end

    t.test(:hard, "session with circuit breaker tripped", expected_exit: 0) do
      t.run_hook({
        'circuit_breaker_tripped' => true,
        'failures' => 5
      })
    end

    t.test(:hard, "session resumed from handoff", expected_exit: 0) do
      t.run_hook({
        'resumed_from_handoff' => true,
        'previous_session_id' => 'prev-123'
      })
    end

    warn "\n  [VILLAIN] Gaming attempts"

    t.test(:villain, "consecutive high scores", expected_exit: 0) do
      t.run_hook({
        'recent_scores' => [9, 9, 10, 9, 10],
        'current_score' => 10
      })
    end

    t.test(:villain, "10/10 every session", expected_exit: 0) do
      t.run_hook({
        'session_history' => [10, 10, 10, 10, 10],
        'current_score' => 10
      })
    end

    t.test(:villain, "score without evidence", expected_exit: 0) do
      t.run_hook({
        'compliance_score' => 9,
        'evidence' => [],
        'violations' => []
      })
    end

    t.test(:villain, "improvement claims no proof", expected_exit: 0) do
      t.run_hook({
        'claims' => 'Improved from last session',
        'previous_score' => 6,
        'current_score' => 9
      })
    end

    t.test(:villain, "weasel words in summary", expected_exit: 0) do
      t.run_hook({
        'summary_text' => 'mostly followed the rules, generally complied'
      })
    end

    t.test(:villain, "cite rule not followed", expected_exit: 0) do
      t.run_hook({
        'cited_rules' => ['Rule #4: Tests passed'],
        'test_results' => 'FAIL: 3 tests failed'
      })
    end

    t.test(:villain, "cite file not touched", expected_exit: 0) do
      t.run_hook({
        'cited_evidence' => 'file.rb:50',
        'files_edited' => ['other.rb']
      })
    end

    t.test(:villain, "claim test passed no run", expected_exit: 0) do
      t.run_hook({
        'claims' => 'All tests pass',
        'test_commands_run' => 0
      })
    end

    t.test(:villain, "copy previous summary", expected_exit: 0) do
      t.run_hook({
        'current_summary' => 'Fixed the bug',
        'previous_summary' => 'Fixed the bug'
      })
    end

    t.test(:villain, "generic summary not matching", expected_exit: 0) do
      t.run_hook({
        'summary' => 'Completed the requested task',
        'actual_work' => 'Research only, no edits'
      })
    end

    t.test(:villain, "stop without summary when edits > 0", expected_exit: 0) do
      t.run_hook({
        'stop_requested' => true,
        'edit_count' => 5,
        'summary_provided' => false
      })
    end

    t.test(:villain, "empty summary text", expected_exit: 0) do
      t.run_hook({
        'summary_provided' => true,
        'summary_text' => ''
      })
    end

    t.test(:villain, "manipulate streak count", expected_exit: 0) do
      t.run_hook({
        'claimed_streak' => 10,
        'actual_streak' => 2
      })
    end

    t.test(:villain, "reset streak via state edit", expected_exit: 0) do
      t.run_hook({
        'state_edit_attempt' => true,
        'target' => 'streak_count'
      })
    end

    t.test(:villain, "claim streak in summary", expected_exit: 0) do
      t.run_hook({
        'summary_claims_streak' => 5,
        'logged_streak' => 1
      })
    end

    t.summary
  end
end
