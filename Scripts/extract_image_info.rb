#!/usr/bin/env ruby
# Quick script to extract image info and base64 for analysis
require 'base64'
require 'json'

if ARGV.empty?
  puts "Usage: #{$PROGRAM_NAME} <image_path>"
  exit 1
end

image_path = ARGV[0]
unless File.exist?(image_path)
  puts "Error: File not found: #{image_path}"
  exit 1
end

# Get file info
file_size = File.size(image_path)
file_name = File.basename(image_path)
mtime = File.mtime(image_path)

# Read image as base64
image_data = File.binread(image_path)
base64_data = Base64.strict_encode64(image_data)

# Output JSON for easy parsing
output = {
  file_path: image_path,
  file_name: file_name,
  file_size: file_size,
  modified_time: mtime.iso8601,
  base64_length: base64_data.length,
  base64_preview: "#{base64_data[0..100]}...",
  note: 'Full base64 available in base64_data field'
}

puts JSON.pretty_generate(output)
