#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'

# Test a single hook call with debug output
hook_path = File.expand_path('../sanetools.rb', __dir__)

test_input = {
  'tool_name' => 'Bash',
  'tool_input' => { 'command' => 'ls > /dev/null' }
}

puts "Input JSON: #{test_input.to_json}"
puts "Running hook: #{hook_path}"
puts "---"

stdout, stderr, status = Open3.capture3(
  { 'TIER_TEST_MODE' => 'true' },
  'ruby', hook_path,
  stdin_data: test_input.to_json
)

puts "STDOUT: #{stdout}"
puts "STDERR: #{stderr}"
puts "EXIT CODE: #{status.exitstatus}"
puts "---"
puts status.exitstatus == 0 ? "PASS: Hook allowed the command" : "FAIL: Hook blocked the command"
