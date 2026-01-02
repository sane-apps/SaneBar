# frozen_string_literal: true

module SaneMasterModules
  # Memory MCP integration for cross-session knowledge
  module Memory
    def show_memory_context_summary
      memory = load_memory
      return if memory.nil? || memory['entities'].empty?

      entities = memory['entities']
      by_type = entities.group_by { |e| e['entityType'] }

      bugs = (by_type['bug_pattern'] || []).count
      gotchas = (by_type['concurrency_gotcha'] || []).count
      violations = (by_type['file_violation'] || []).count

      puts "\n🧠 Memory Context:"
      puts "   #{bugs} bug patterns, #{gotchas} concurrency gotchas, #{violations} file violations"
      puts '   Run: ./Scripts/SaneMaster.rb memory_context for details'
    end

    def show_memory_context(_args)
      puts '🧠 --- [ MEMORY CONTEXT ] ---'
      puts ''

      memory = load_memory
      return puts '   ⚠️  No memory data found' if memory.nil? || memory['entities'].empty?

      entities = memory['entities']
      by_type = entities.group_by { |e| e['entityType'] }

      # Show bug patterns
      show_entity_group(by_type, 'bug_pattern', '🐛 Bug Patterns', 'Symptom:')

      # Show concurrency gotchas
      show_entity_group(by_type, 'concurrency_gotcha', '⚡ Concurrency Gotchas', 'Pattern:')

      # Show file violations
      violations = by_type['file_violation'] || []
      if violations.any?
        puts "📏 File Violations (#{violations.count}):"
        violations.each do |v|
          name = v['name'].sub('file_violation:', '')
          lines = v['observations'].find { |o| o.start_with?('Line count:') } || ''
          priority = v['observations'].find { |o| o.start_with?('Priority:') } || ''
          puts "   • #{name}: #{lines} #{priority}"
        end
        puts ''
      end

      # Show compliance rules
      show_entity_group(by_type, 'compliance_rule', '📋 Compliance Rules', 'Rule:')

      # Summary
      puts "📊 Total: #{entities.count} entities across #{by_type.keys.count} types"
    end

    def record_memory_entity(args)
      puts '📝 --- [ RECORD MEMORY ENTITY ] ---'
      puts ''
      puts 'Entity types: bug_pattern, concurrency_gotcha, architecture_pattern, file_violation, service, compliance_rule'
      puts ''
      puts 'Usage: ./Scripts/SaneMaster.rb memory_record <type> <name>'
      puts 'Example: ./Scripts/SaneMaster.rb memory_record bug_pattern timeline_freeze'
      puts ''

      if args.length < 2
        puts '❌ Please provide entity type and name'
        return
      end

      entity_type = args[0]
      entity_name = args[1]
      full_name = "#{entity_type}:#{entity_name}"

      puts "Creating entity: #{full_name}"
      puts 'Enter observations (one per line, empty line to finish):'
      puts ''

      observations = []
      loop do
        print '> '
        line = $stdin.gets&.chomp
        break if line.nil? || line.empty?

        observations << line
      end

      if observations.empty?
        puts '❌ No observations provided'
        return
      end

      memory = load_memory || { 'entities' => [], 'relations' => [] }

      new_entity = {
        'name' => full_name,
        'entityType' => entity_type,
        'observations' => observations
      }

      memory['entities'] << new_entity
      save_memory(memory)

      puts ''
      puts "✅ Created entity: #{full_name}"
      puts "   Observations: #{observations.count}"
    end

    def prune_memory_entities(args)
      puts '🧹 --- [ PRUNE MEMORY ENTITIES ] ---'
      puts ''

      dry_run = args.include?('--dry-run')

      memory = load_memory
      return puts '   ⚠️  No memory data found' if memory.nil?

      entities = memory['entities']
      original_count = entities.count

      stale = find_stale_entities(entities)

      if stale.empty?
        puts '✅ No stale entities found (>90 days old)'
        return
      end

      puts "Found #{stale.count} stale entities:"
      stale.each { |e| puts "   • #{e['name']}" }
      puts ''

      if dry_run
        puts '🔍 Dry run - no changes made'
        puts '   Run without --dry-run to delete these entities'
      else
        memory['entities'] = entities - stale
        save_memory(memory)
        puts "✅ Pruned #{stale.count} entities (#{original_count} → #{memory['entities'].count})"
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AUTO-RECORD FUNCTIONS
    # Called automatically from other workflows to record patterns
    # ═══════════════════════════════════════════════════════════════════════════

    # Record a bug fix pattern (call after successful bug fix)
    def auto_record_fix(name, observations)
      auto_record('bug_pattern', name, observations)
    end

    # Record an architecture decision (call after creating new files)
    def auto_record_architecture(name, observations)
      auto_record('architecture_pattern', name, observations)
    end

    # Record a concurrency pattern (call when fixing concurrency issues)
    def auto_record_concurrency(name, observations)
      auto_record('concurrency_gotcha', name, observations)
    end

    # Generic auto-record (silent, no prompts)
    def auto_record(entity_type, name, observations)
      return if name.nil? || observations.empty?

      memory = load_memory || { 'entities' => [], 'relations' => [] }
      full_name = "#{entity_type}:#{name}"

      # Check if entity already exists
      existing = memory['entities'].find { |e| e['name'] == full_name }
      if existing
        # Add new observations to existing entity
        existing['observations'] += observations
        existing['observations'] << "Last updated: #{Date.today}"
        existing['observations'].uniq!
      else
        # Create new entity
        new_entity = {
          'name' => full_name,
          'entityType' => entity_type,
          'observations' => observations + ["Recorded: #{Date.today}"]
        }
        memory['entities'] << new_entity
      end

      save_memory(memory)
      puts "   🧠 Auto-recorded: #{full_name}"
    rescue StandardError => e
      # Silent failure - don't interrupt workflow
      puts "   ⚠️  Memory auto-record failed: #{e.message}" if ENV['DEBUG']
    end

    # Suggest recording based on recent git changes
    def suggest_memory_record
      # Check for recent bug fixes in commit messages
      recent_commits = `git log --oneline -10 --format='%s' 2>/dev/null`.strip.split("\n")

      fix_commits = recent_commits.select { |c| c.downcase.include?('fix') }
      return if fix_commits.empty?

      puts ''
      puts '💡 Recent fix commits detected. Consider recording patterns:'
      fix_commits.first(3).each { |c| puts "   • #{c}" }
      puts '   Run: ./Scripts/SaneMaster.rb mr bug_pattern <name>'
    end

    private

    def show_entity_group(by_type, type_key, header, prefix)
      entities = by_type[type_key] || []
      return unless entities.any?

      puts "#{header} (#{entities.count}):"
      entities.each do |entity|
        name = entity['name'].sub("#{type_key}:", '')
        obs = entity['observations'].find { |o| o.start_with?(prefix) } || entity['observations'].first
        puts "   • #{name}: #{obs}"
      end
      puts ''
    end

    def find_stale_entities(entities)
      entities.select do |e|
        last_checked = e['observations'].find { |o| o.start_with?('Last checked:') }
        next false unless last_checked

        date_str = last_checked.sub('Last checked:', '').strip
        begin
          date = Date.parse(date_str)
          (Date.today - date).to_i > 90
        rescue StandardError
          false
        end
      end
    end
  end
end
