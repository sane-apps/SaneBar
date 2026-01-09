#!/usr/bin/env ruby
# frozen_string_literal: true

# Test the target extraction regex
cmd = 'ls > /dev/null'
regex = /(?:>|>>|tee\s+)([^\s|&;]+)/

puts "Command: #{cmd.inspect}"
puts "Regex: #{regex.inspect}"

match = cmd.match(regex)
puts "Match: #{match.inspect}"

if match
  puts "Target: #{match[1].inspect}"
else
  puts "NO MATCH!"

  # Debug: try to understand why
  puts "---"
  puts "Testing simpler patterns:"
  puts "> in command: #{cmd.include?('>')}"
  puts "Match />/ : #{cmd.match(/>/).inspect}"
  puts "Match />[^&]/ : #{cmd.match(/>[^&]/).inspect}"
  puts "Match />\\s*/ : #{cmd.match(/>\s*/).inspect}"
  puts "Match /(?:>)([^\s]+)/ : #{cmd.match(/(?:>)([^\s]+)/).inspect}"
end
