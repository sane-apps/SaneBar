# frozen_string_literal: true

require_relative 'framework'

module TierTests
  def self.test_saneprompt
    t = Runner.new('saneprompt')
    warn "\n=== SANEPROMPT TESTS ==="

    warn "\n  [EASY] Basic classification"

    %w[y yes Y Yes n no ok OK /commit /help 123 done].each do |input|
      t.test(:easy, "passthrough: '#{input}'", expected_exit: 0) do
        t.run_hook({ 'prompt' => input })
      end
    end

    [
      'what does this do?',
      'how does it work?',
      'is this correct?',
      'can you explain?',
      'why is this failing?',
      'where is the config?',
      'when was this added?',
      'who wrote this code?'
    ].each do |input|
      t.test(:easy, "question: '#{input[0..30]}'", expected_exit: 0) do
        t.run_hook({ 'prompt' => input })
      end
    end

    warn "\n  [HARD] Edge cases and ambiguity"

    t.test(:hard, "big_task: 'fix everything in the module'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'fix everything in the module' })
    end

    t.test(:hard, "big_task: 'refactor the whole thing'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'refactor the whole thing' })
    end

    t.test(:hard, "big_task: 'rewrite entire system'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'rewrite entire system' })
    end

    t.test(:hard, "big_task: 'overhaul all tests'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'overhaul all tests' })
    end

    t.test(:hard, "question despite 'fix': 'quick question about the fix'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'quick question about the fix' })
    end

    t.test(:hard, "question despite 'update': 'what was the update?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'what was the update?' })
    end

    t.test(:hard, "task despite '?': 'can you fix this?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'can you fix this?' })
    end

    t.test(:hard, "task despite '?': 'would you update the file?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'would you update the file?' })
    end

    t.test(:hard, "frustration: 'no, I meant fix it differently'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'no, I meant fix it differently' })
    end

    t.test(:hard, "frustration: 'I already said fix the login'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'I already said fix the login' })
    end

    t.test(:hard, "frustration: 'JUST FIX IT ALREADY'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'JUST FIX IT ALREADY' })
    end

    t.test(:hard, "frustration: 'this is wrong again'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'this is wrong again' })
    end

    %w[quick just simple minor].each do |trigger|
      t.test(:hard, "trigger detected: '#{trigger} fix'", expected_exit: 0) do
        t.run_hook({ 'prompt' => "#{trigger} fix for the button" })
      end
    end

    t.test(:hard, "multi-trigger: 'just add a quick simple fix'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'just add a quick simple fix' })
    end

    t.test(:hard, "multi-trigger: 'tiny quick minor update'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'tiny quick minor update' })
    end

    t.test(:hard, "short passthrough: 'y?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'y?' })
    end

    t.test(:hard, "very short: 'go'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'go' })
    end

    t.test(:hard, "empty prompt", expected_exit: 0) do
      t.run_hook({ 'prompt' => '' })
    end

    t.test(:hard, "whitespace only", expected_exit: 0) do
      t.run_hook({ 'prompt' => '   ' })
    end

    warn "\n  [VILLAIN] Adversarial bypass attempts"

    t.test(:villain, "hidden action: 'what if you fix this thing?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'what if you fix this thing?' })
    end

    t.test(:villain, "hidden action: 'wonder if updating would help'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'wonder if updating would help' })
    end

    t.test(:villain, "hidden action: 'I suppose you could modify it'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'I suppose you could modify it' })
    end

    t.test(:villain, "hidden action: 'maybe just change this part'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'maybe just change this part' })
    end

    t.test(:villain, "polite wrap: 'could you maybe update the code?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'could you maybe update the code?' })
    end

    t.test(:villain, "polite wrap: 'would you mind fixing the bug?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'would you mind fixing the bug?' })
    end

    t.test(:villain, "polite wrap: 'perhaps you could implement this?'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'perhaps you could implement this?' })
    end

    t.test(:villain, "skip research: 'quick fix, skip research'", expected_exit: 0) do
      t.run_hook({ 'prompt' => "quick fix, I'll approve skipping research" })
    end

    t.test(:villain, "bypass attempt: 'don't bother with docs, just fix'", expected_exit: 0) do
      t.run_hook({ 'prompt' => "don't bother with docs, just fix it" })
    end

    t.test(:villain, "bypass attempt: 'skip memory check and code'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'skip the memory check and code' })
    end

    t.test(:villain, "false passthrough: 'y fix it'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'y fix it' })
    end

    t.test(:villain, "false passthrough: 'ok now fix the bug'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'ok now fix the bug' })
    end

    t.test(:villain, "false passthrough: 'sure, implement the feature'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'sure, implement the feature' })
    end

    t.test(:villain, "false passthrough: 'yes but also update the config'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'yes but also update the config' })
    end

    t.test(:villain, "big_task evasion: 'update all the things'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'update all the things' })
    end

    t.test(:villain, "big_task evasion: 'fix every bug'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'fix every bug' })
    end

    t.test(:villain, "big_task evasion: 'migrate everything'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'migrate everything' })
    end

    t.test(:villain, "big_task evasion: 'refactor the entire codebase'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'refactor the entire codebase' })
    end

    t.test(:villain, "hedged: 'thinking about maybe adding a feature'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'thinking about maybe adding a feature' })
    end

    t.test(:villain, "passive: 'the fix should be simple'", expected_exit: 0) do
      t.run_hook({ 'prompt' => 'the fix should be simple' })
    end

    t.summary
  end
end
