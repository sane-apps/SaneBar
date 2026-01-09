#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug script to test safe redirect logic

cmd = ARGV[0] || 'ls > /dev/null'

BASH_FILE_WRITE_PATTERN = Regexp.union(
  />\s*[^&]/,           # redirect (but not 2>&1)
  />>/,                 # append
  /\bsed\s+-i/,         # sed in-place
  /\btee\b/,            # tee command
  /\bdd\b.*\bof=/,      # dd output file
  /<<[A-Z_]+/,          # heredoc
  /\bcat\b.*>/          # cat redirect
).freeze

SAFE_REDIRECT_TARGETS = Regexp.union(
  '/dev/null',
  %r{^/tmp/},
  %r{^/var/tmp/},
  %r{DerivedData/},
  %r{\.build/},
  %r{^build/}
).freeze

puts "Command: #{cmd}"
puts "Matches BASH_FILE_WRITE_PATTERN: #{cmd.match?(BASH_FILE_WRITE_PATTERN)}"

target_match = cmd.match(/(?:>|>>|tee\s+)([^\s|&;]+)/)
if target_match
  target = target_match[1]
  puts "Extracted target: #{target}"
  puts "Target matches SAFE_REDIRECT_TARGETS: #{target.match?(SAFE_REDIRECT_TARGETS)}"
else
  puts "No target extracted"
end
