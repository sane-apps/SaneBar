#!/usr/bin/env ruby
# frozen_string_literal: true

# SaneBar Flow Tracer
# Analyzes code to map button clicks to their handlers
#
# Usage: ./scripts/trace_flow.rb [search_term]
# Example: ./scripts/trace_flow.rb "toggleHiddenItems"

require 'json'

CORE_PATH = File.expand_path('../Core', __dir__)
UI_PATH = File.expand_path('../UI', __dir__)

class FlowTracer
  def initialize
    @call_graph = {}
    @files_scanned = 0
  end

  def scan_all
    scan_directory(CORE_PATH)
    scan_directory(UI_PATH)
    puts "Scanned #{@files_scanned} Swift files"
  end

  def scan_directory(path)
    Dir.glob("#{path}/**/*.swift").each do |file|
      scan_file(file)
    end
  end

  def scan_file(path)
    @files_scanned += 1
    content = File.read(path)
    filename = File.basename(path)

    # Extract function definitions
    content.scan(/func\s+(\w+)\s*\([^)]*\)/).each do |match|
      func_name = match[0]
      @call_graph[func_name] ||= { defined_in: [], calls: [], called_by: [] }
      @call_graph[func_name][:defined_in] << filename
    end

    # Extract @objc function definitions (button handlers)
    content.scan(/@objc\s+(?:private\s+)?func\s+(\w+)/).each do |match|
      func_name = match[0]
      @call_graph[func_name] ||= { defined_in: [], calls: [], called_by: [], objc: true }
      @call_graph[func_name][:defined_in] << filename
      @call_graph[func_name][:objc] = true
    end

    # Extract function calls
    content.scan(/(\w+)\s*\(/).each do |match|
      caller = match[0]
      # Skip common keywords
      next if %w[if for while switch guard return case let var func class struct enum].include?(caller)
      @call_graph[caller] ||= { defined_in: [], calls: [], called_by: [] }
    end
  end

  def trace(func_name, depth = 0, visited = Set.new)
    return if visited.include?(func_name) || depth > 5
    visited.add(func_name)

    indent = "  " * depth
    info = @call_graph[func_name]

    if info
      objc_marker = info[:objc] ? " [BUTTON HANDLER]" : ""
      files = info[:defined_in].uniq.join(", ")
      puts "#{indent}→ #{func_name}#{objc_marker}"
      puts "#{indent}  (defined in: #{files})" unless files.empty?
    else
      puts "#{indent}→ #{func_name} [external/system]"
    end
  end

  def find_handlers
    puts "\n=== BUTTON HANDLERS (@objc functions) ===\n"
    @call_graph.select { |_, v| v[:objc] }.each do |name, info|
      puts "• #{name} (#{info[:defined_in].uniq.join(', ')})"
    end
  end

  def find_triggers
    puts "\n=== TRIGGER-RELATED FUNCTIONS ===\n"
    triggers = %w[
      showOnHover showOnScroll showOnAppLaunch showOnLowBattery
      showOnNetworkChange autoRehide toggleHiddenItems showHiddenItems
      hideHiddenItems scheduleRehide
    ]

    triggers.each do |trigger|
      if @call_graph[trigger]
        puts "✓ #{trigger} - defined in: #{@call_graph[trigger][:defined_in].uniq.join(', ')}"
      else
        puts "✗ #{trigger} - NOT FOUND as function"
      end
    end
  end

  def search(term)
    puts "\n=== SEARCHING FOR: #{term} ===\n"
    matches = @call_graph.keys.select { |k| k.downcase.include?(term.downcase) }
    matches.each do |match|
      info = @call_graph[match]
      objc = info[:objc] ? " [BUTTON]" : ""
      puts "• #{match}#{objc} - #{info[:defined_in].uniq.join(', ')}"
    end
    puts "Found #{matches.length} matches"
  end
end

# Main
tracer = FlowTracer.new
tracer.scan_all

if ARGV[0]
  tracer.search(ARGV[0])
else
  tracer.find_handlers
  tracer.find_triggers
end
