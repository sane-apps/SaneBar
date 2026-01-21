#!/usr/bin/env ruby
# frozen_string_literal: true

# Migrate MCP memory.json files to Sane-Mem SQLite database
# This consolidates all project memories into the unified Sane-Mem system
# Uses sqlite3 CLI instead of Ruby gem for portability

require 'json'
require 'securerandom'
require 'time'
require 'shellwords'

DB_PATH = File.expand_path('~/.claude-mem/claude-mem.db')
SANE_APPS_ROOT = File.expand_path('~/SaneApps')

# All memory sources to migrate
MEMORY_SOURCES = {
  'SaneBar' => "#{SANE_APPS_ROOT}/apps/SaneBar/.claude/memory.json",
  'SaneVideo' => "#{SANE_APPS_ROOT}/apps/SaneVideo/.claude/memory.json",
  'SaneClip' => "#{SANE_APPS_ROOT}/apps/SaneClip/.claude/memory.json",
  'SaneHosts' => "#{SANE_APPS_ROOT}/apps/SaneHosts/.claude/memory.json",
  'SaneSync' => "#{SANE_APPS_ROOT}/apps/SaneSync/.claude/memory.json",
  'SaneScript' => "#{SANE_APPS_ROOT}/apps/SaneScript/.claude/memory.json",
  'SaneAI' => "#{SANE_APPS_ROOT}/apps/SaneAI/.claude/memory.json",
  'SaneProcess' => "#{SANE_APPS_ROOT}/infra/SaneProcess/.claude/memory.json",
  'Global' => File.expand_path('~/.claude/global-memory.json')
}.freeze

# Map MCP entity types to Sane-Mem observation types
TYPE_MAPPING = {
  'Project' => 'feature',
  'bug_pattern' => 'bugfix',
  'Pattern' => 'discovery',
  'GlobalPattern' => 'discovery',
  'Insight' => 'discovery',
  'ComplianceGuide' => 'discovery',
  'Tool' => 'feature',
  'GlobalTool' => 'feature',
  'GlobalDecision' => 'decision',
  'ActionItem' => 'change',
  'Feature' => 'feature',
  'DesignReview' => 'discovery',
  'architecture_pattern' => 'discovery',
  'concurrency_gotcha' => 'bugfix',
  'system_failure' => 'bugfix',
  'CorePrinciple' => 'discovery'
}.freeze

def type_for(entity_type)
  TYPE_MAPPING[entity_type] || 'discovery'
end

def sql_escape(str)
  return '' if str.nil?

  str.gsub("'", "''")
end

def run_sql(sql)
  # Use sqlite3 CLI
  cmd = "sqlite3 #{DB_PATH.shellescape} #{sql.shellescape}"
  result = `#{cmd} 2>&1`
  unless $?.success?
    warn "SQL Error: #{result}"
    return false
  end
  true
end

def get_existing_titles(project)
  cmd = "sqlite3 #{DB_PATH.shellescape} \"SELECT title FROM observations WHERE project = '#{sql_escape(project)}'\""
  result = `#{cmd} 2>&1`
  return [] unless $?.success?

  result.strip.split("\n").to_set
end

def migrate!
  migrated = 0
  skipped = 0
  duplicates = 0

  MEMORY_SOURCES.each do |project, path|
    unless File.exist?(path)
      warn "⚠️  #{project}: #{path} not found, skipping"
      skipped += 1
      next
    end

    begin
      data = JSON.parse(File.read(path))
      entities = data['entities'] || []

      if entities.empty?
        warn "⚠️  #{project}: No entities found, skipping"
        skipped += 1
        next
      end

      # Create a migration session for this project
      session_id = SecureRandom.uuid
      content_id = "migration-#{project.downcase}-#{Time.now.to_i}"
      now = Time.now

      session_sql = <<~SQL
        INSERT INTO sdk_sessions (content_session_id, memory_session_id, project, user_prompt, started_at, started_at_epoch, completed_at, completed_at_epoch, status)
        VALUES ('#{sql_escape(content_id)}', '#{sql_escape(session_id)}', '#{sql_escape(project)}', 'Memory migration from MCP JSON', '#{now.iso8601}', #{now.to_i}, '#{now.iso8601}', #{now.to_i}, 'completed')
      SQL

      unless run_sql(session_sql)
        warn "❌ #{project}: Failed to create session"
        skipped += 1
        next
      end

      # Track which entities we've already seen (by title) to avoid duplicates
      existing_titles = get_existing_titles(project)

      entity_count = 0
      entities.each do |entity|
        name = entity['name']
        entity_type = entity['entityType']
        observations = entity['observations'] || []

        next if observations.empty?

        # Skip if we already have this in the database
        if existing_titles.include?(name)
          warn "   ↳ Skipping duplicate: #{name}"
          duplicates += 1
          next
        end

        # Build the observation record
        title = name
        subtitle = "Migrated from #{project} MCP memory"
        narrative = observations.join("\n\n")
        obs_type = type_for(entity_type)

        obs_sql = <<~SQL
          INSERT INTO observations
          (memory_session_id, project, text, type, title, subtitle, narrative, facts, created_at, created_at_epoch)
          VALUES ('#{sql_escape(session_id)}', '#{sql_escape(project)}', '#{sql_escape(narrative)}', '#{obs_type}', '#{sql_escape(title)}', '#{sql_escape(subtitle)}', '#{sql_escape(narrative)}', '', '#{now.iso8601}', #{now.to_i})
        SQL

        if run_sql(obs_sql)
          entity_count += 1
          migrated += 1
        end
      end

      puts "✅ #{project}: Migrated #{entity_count} entities"

    rescue JSON::ParserError => e
      warn "❌ #{project}: JSON parse error: #{e.message}"
      skipped += 1
    rescue StandardError => e
      warn "❌ #{project}: Error: #{e.message}"
      skipped += 1
    end
  end

  puts "\n📊 Migration Summary"
  puts "   Migrated:   #{migrated} observations"
  puts "   Duplicates: #{duplicates} skipped"
  puts "   Errors:     #{skipped} sources"
end

# Verify the database exists
unless File.exist?(DB_PATH)
  abort "❌ Sane-Mem database not found at #{DB_PATH}"
end

puts "🔄 Starting memory migration to Sane-Mem..."
puts "   Database: #{DB_PATH}"
puts ""

migrate!
