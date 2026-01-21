#!/usr/bin/env ruby
# frozen_string_literal: true

# Remove the redundant "memory" MCP server from all .mcp.json files
# The memory is now consolidated in Sane-Mem SQLite database

require 'json'

MCP_FILES = [
  '/Users/sj/SaneApps/apps/SaneBar/.mcp.json',
  '/Users/sj/SaneApps/apps/SaneVideo/.mcp.json',
  '/Users/sj/SaneApps/apps/SaneClip/.mcp.json',
  '/Users/sj/SaneApps/apps/SaneHosts/.mcp.json',
  '/Users/sj/SaneApps/apps/SaneSync/.mcp.json',
  '/Users/sj/SaneApps/apps/SaneScript/.mcp.json',
  '/Users/sj/SaneApps/apps/SaneAI/.mcp.json',
  '/Users/sj/SaneApps/infra/SaneProcess/.mcp.json'
].freeze

updated = 0
skipped = 0

MCP_FILES.each do |path|
  unless File.exist?(path)
    warn "⚠️  #{path} not found"
    skipped += 1
    next
  end

  begin
    data = JSON.parse(File.read(path))
    servers = data['mcpServers']

    unless servers&.key?('memory')
      puts "⏭️  #{File.basename(File.dirname(path))}: No memory entry found"
      skipped += 1
      next
    end

    # Remove the memory entry
    servers.delete('memory')

    # Write back with nice formatting
    File.write(path, JSON.pretty_generate(data) + "\n")

    puts "✅ #{File.basename(File.dirname(path))}: Removed memory MCP"
    updated += 1

  rescue JSON::ParserError => e
    warn "❌ #{path}: JSON parse error: #{e.message}"
    skipped += 1
  rescue StandardError => e
    warn "❌ #{path}: Error: #{e.message}"
    skipped += 1
  end
end

puts "\n📊 Summary"
puts "   Updated: #{updated} files"
puts "   Skipped: #{skipped} files"
