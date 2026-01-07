# frozen_string_literal: true

require 'English'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'optparse'
require 'set'
require 'time'

module SaneMasterModules
  # Shared constants and utilities used across all modules
  module Base
    # --- Paths ---
    SOP_SNAPSHOT_DIR = File.expand_path('~/.sanemaster/snapshots')
    SOP_LOG_DIR = File.expand_path('~/.sanemaster/logs')
    HOMEBREW_RUBY = '/opt/homebrew/opt/ruby/bin/ruby'
    HOMEBREW_BUNDLE = '/opt/homebrew/opt/ruby/bin/bundle'
    VERSION_CACHE_FILE = File.expand_path('~/.sanemaster/versions_cache.json')
    VERSION_CACHE_MAX_AGE = 7 * 24 * 60 * 60 # 7 days in seconds
    TEMPLATE_DIR = File.expand_path('~/.sanemaster/templates')
    MEMORY_FILE = File.join(Dir.pwd, '.claude', 'memory.json')

    # --- Tool Versions ---
    TOOL_VERSIONS = {
      'swiftlint' => { cmd: 'swiftlint --version', min: '0.62.0' },
      'xcodegen' => { cmd: 'xcodegen --version', extract: /Version: ([\d.]+)/, min: '2.44.0' },
      'periphery' => { cmd: 'periphery version', min: '3.2.0' },
      'mockolo' => { cmd: 'mockolo --version', min: '2.4.0' },
      'lefthook' => { cmd: 'lefthook --version', extract: /lefthook version ([\d.]+)/, min: '2.0.0' }
    }.freeze

    TOOL_SOURCES = {
      'swiftlint' => { type: :homebrew, formula: 'swiftlint' },
      'xcodegen' => { type: :homebrew, formula: 'xcodegen' },
      'periphery' => { type: :homebrew, formula: 'periphery' },
      'mockolo' => { type: :github, repo: 'uber/mockolo' },
      'lefthook' => { type: :homebrew, formula: 'lefthook' },
      'fastlane' => { type: :rubygems, gem: 'fastlane' },
      'ruby' => { type: :homebrew, formula: 'ruby' }
    }.freeze

    # --- SOP Directory Helpers ---

    def ensure_sop_dirs
      FileUtils.mkdir_p(SOP_SNAPSHOT_DIR)
      FileUtils.mkdir_p(SOP_LOG_DIR)
    end

    def sop_log(message)
      return unless @sop_log

      File.open(@sop_log, 'a') { |f| f.puts "[#{Time.now.iso8601}] #{message}" }
    end

    # --- Memory Helpers ---

    # Load memory from STDIN (piped from mcp__memory__read_graph) or local cache
    def load_memory(from_stdin: false)
      if from_stdin
        input = begin
          $stdin.read.strip
        rescue StandardError
          ''
        end
        return nil if input.empty?

        begin
          memory = JSON.parse(input)
          # Cache locally for future use
          save_memory(memory)
          memory
        rescue JSON::ParserError
          nil
        end
      elsif File.exist?(MEMORY_FILE)
        JSON.parse(File.read(MEMORY_FILE))
      else
        warn ''
        warn '⚠️  No local memory cache found at .claude/memory.json'
        warn ''
        warn 'To use memory commands, pipe from MCP:'
        warn '  1. Ask Claude to run: mcp__memory__read_graph'
        warn '  2. Copy the JSON output'
        warn '  3. Run: echo \'<json>\' | ./Scripts/SaneMaster.rb <command>'
        warn ''
        warn 'Or use: ./Scripts/SaneMaster.rb msync to create a cache.'
        warn ''
        nil
      end
    rescue JSON::ParserError
      nil
    end

    def save_memory(memory)
      FileUtils.mkdir_p(File.dirname(MEMORY_FILE))
      File.write(MEMORY_FILE, JSON.pretty_generate(memory))
    end

    # Sync memory from STDIN (requires piping from mcp__memory__read_graph)
    def memory_sync(_args)
      puts '🔄 --- [ MEMORY SYNC ] ---'
      puts ''
      puts 'Paste the output from mcp__memory__read_graph below,'
      puts 'then press Ctrl+D (or Ctrl+Z on Windows) when done:'
      puts ''

      memory = load_memory(from_stdin: true)
      if memory
        count = (memory['entities'] || []).count
        puts ''
        puts "✅ Synced #{count} entities to .claude/memory.json"
      else
        puts ''
        puts '❌ No valid JSON received'
      end
    end
  end
end
