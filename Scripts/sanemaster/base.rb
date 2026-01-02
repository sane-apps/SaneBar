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

    def load_memory
      return nil unless File.exist?(MEMORY_FILE)

      JSON.parse(File.read(MEMORY_FILE))
    rescue JSON::ParserError
      nil
    end

    def save_memory(memory)
      FileUtils.mkdir_p(File.dirname(MEMORY_FILE))
      File.write(MEMORY_FILE, JSON.pretty_generate(memory))
    end
  end
end
