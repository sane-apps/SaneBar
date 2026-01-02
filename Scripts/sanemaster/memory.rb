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
    # MEMORY HEALTH & COMPACTION
    # Prevent memory bloat that fills context
    # ═══════════════════════════════════════════════════════════════════════════

    ENTITY_WARN_THRESHOLD = 60
    OBSERVATION_WARN_THRESHOLD = 15  # Per entity
    TOKEN_WARN_THRESHOLD = 8000      # Estimated tokens

    def memory_health(_args = [])
      puts '🧠 --- [ MEMORY HEALTH ] ---'
      puts ''

      memory = load_memory
      return puts '   ⚠️  No memory data found' if memory.nil?

      entities = memory['entities'] || []
      relations = memory['relations'] || []

      # Calculate stats
      total_observations = entities.sum { |e| (e['observations'] || []).count }
      estimated_tokens = estimate_tokens(memory)
      verbose_entities = find_verbose_entities(entities)
      duplicate_candidates = find_duplicate_candidates(entities)

      # Entity count
      if entities.count > ENTITY_WARN_THRESHOLD
        puts "   ⚠️  Entity count: #{entities.count}/#{ENTITY_WARN_THRESHOLD} (HIGH - consolidate!)"
      else
        puts "   ✅ Entity count: #{entities.count}/#{ENTITY_WARN_THRESHOLD}"
      end

      # Token estimate
      if estimated_tokens > TOKEN_WARN_THRESHOLD
        puts "   ⚠️  Estimated tokens: ~#{estimated_tokens} (HIGH - will fill context!)"
      else
        puts "   ✅ Estimated tokens: ~#{estimated_tokens}"
      end

      # Verbose entities
      if verbose_entities.any?
        puts "   ⚠️  Verbose entities (>#{OBSERVATION_WARN_THRESHOLD} observations):"
        verbose_entities.first(5).each do |e|
          puts "      • #{e['name']}: #{e['observations'].count} observations"
        end
      end

      # Duplicate candidates
      if duplicate_candidates.any?
        puts '   ⚠️  Potential duplicates (similar names):'
        duplicate_candidates.first(3).each do |pair|
          puts "      • #{pair[0]} <-> #{pair[1]}"
        end
      end

      puts ''
      puts "📊 Summary: #{entities.count} entities, #{relations.count} relations, #{total_observations} observations"
      puts ''

      # Recommendations
      return unless entities.count > ENTITY_WARN_THRESHOLD || estimated_tokens > TOKEN_WARN_THRESHOLD

      puts '💡 Recommendations:'
      puts '   • Run: ./Scripts/SaneMaster.rb memory_compact --dry-run'
      puts '   • Run: ./Scripts/SaneMaster.rb memory_prune --dry-run'
      puts '   • Manually consolidate similar entities in Memory MCP'
    end

    def memory_compact(args)
      puts '📦 --- [ MEMORY COMPACT ] ---'
      puts ''

      dry_run = args.include?('--dry-run')
      aggressive = args.include?('--aggressive')

      memory = load_memory
      return puts '   ⚠️  No memory data found' if memory.nil?

      entities = memory['entities'] || []
      entities.count
      original_obs = entities.sum { |e| (e['observations'] || []).count }

      changes = []

      # 1. Trim verbose observations (keep most recent)
      entities.each do |entity|
        obs = entity['observations'] || []
        next unless obs.count > OBSERVATION_WARN_THRESHOLD

        # Keep first 3 (usually the core info) and last 5 (recent updates)
        trimmed = if aggressive
                    obs.first(3) + obs.last(3)
                  else
                    obs.first(5) + obs.last(5)
                  end
        trimmed.uniq!

        if trimmed.count < obs.count
          changes << "#{entity['name']}: #{obs.count} → #{trimmed.count} observations"
          entity['observations'] = trimmed unless dry_run
        end

        # 2. Remove duplicate observations within entities
        obs = entity['observations'] || []
        unique_obs = obs.uniq
        if unique_obs.count < obs.count
          changes << "#{entity['name']}: removed #{obs.count - unique_obs.count} duplicate observations"
          entity['observations'] = unique_obs unless dry_run
        end

        # 3. Remove date-only observations (noise)
        obs = entity['observations'] || []
        filtered = obs.grep_v(/^(Last (checked|updated)|Recorded):?\s*\d{4}-\d{2}-\d{2}$/)
        if filtered.count < obs.count
          changes << "#{entity['name']}: removed #{obs.count - filtered.count} date-only entries"
          entity['observations'] = filtered unless dry_run
        end
      end

      if changes.empty?
        puts '✅ Memory already compact - no changes needed'
        return
      end

      puts "Found #{changes.count} compaction opportunities:"
      changes.first(10).each { |c| puts "   • #{c}" }
      puts "   ... and #{changes.count - 10} more" if changes.count > 10
      puts ''

      if dry_run
        puts '🔍 Dry run - no changes made'
        puts '   Run without --dry-run to apply'
      else
        save_memory(memory)
        new_obs = entities.sum { |e| (e['observations'] || []).count }
        puts "✅ Compacted: #{original_obs} → #{new_obs} observations"
        puts "   (#{original_obs - new_obs} removed)"
      end
    end

    def check_memory_size_warning
      memory = load_memory
      return unless memory

      entities = memory['entities'] || []
      estimated_tokens = estimate_tokens(memory)

      if entities.count > ENTITY_WARN_THRESHOLD
        warn "⚠️  Memory has #{entities.count} entities (>#{ENTITY_WARN_THRESHOLD}) - may fill context"
        warn '   Run: ./Scripts/SaneMaster.rb memory_health'
      end

      return unless estimated_tokens > TOKEN_WARN_THRESHOLD

      warn "⚠️  Memory ~#{estimated_tokens} tokens (>#{TOKEN_WARN_THRESHOLD}) - context risk!"
      warn '   Run: ./Scripts/SaneMaster.rb memory_compact'
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MCP MEMORY CLEANUP
    # Analyze memory and generate MCP commands for cleanup
    # ═══════════════════════════════════════════════════════════════════════════

    def memory_cleanup(_args)
      puts '🧹 --- [ MCP MEMORY CLEANUP ANALYSIS ] ---'
      puts ''

      # Parse STDIN for memory graph JSON (piped from mcp__memory__read_graph)
      input = begin
        $stdin.read.strip
      rescue StandardError
        ''
      end

      if input.empty?
        puts 'Usage: Run mcp__memory__read_graph first, then ask Claude to analyze with:'
        puts '       "Analyze this memory for cleanup and run ./Scripts/SaneMaster.rb memory_cleanup"'
        puts ''
        puts 'Or provide JSON directly:'
        puts '       echo \'{"entities":[...]}\' | ./Scripts/SaneMaster.rb memory_cleanup'
        return
      end

      begin
        memory = JSON.parse(input)
      rescue JSON::ParserError => e
        puts "❌ Invalid JSON: #{e.message}"
        return
      end

      entities = memory['entities'] || []
      relations = memory['relations'] || []

      if entities.empty?
        puts '✅ No entities to analyze.'
        return
      end

      # Analyze
      puts "📊 Analyzing #{entities.count} entities, #{relations.count} relations..."
      puts ''

      recommendations = []

      # 1. Find verbose entities (>15 observations)
      verbose = find_verbose_entities(entities)
      if verbose.any?
        puts "⚠️  VERBOSE ENTITIES (#{verbose.count}) - >15 observations each:"
        verbose.each do |e|
          obs_count = e['observations'].count
          # Keep first 5 + last 3 observations
          keep = (e['observations'].first(5) + e['observations'].last(3)).uniq
          trim = e['observations'] - keep
          puts "   • #{e['name']}: #{obs_count} obs → keep #{keep.count}, trim #{trim.count}"
          next unless trim.any?

          recommendations << {
            type: 'trim_observations',
            entity: e['name'],
            delete_observations: trim
          }
        end
        puts ''
      end

      # 2. Find duplicate/similar entities
      duplicates = find_duplicate_candidates(entities)
      if duplicates.any?
        puts "⚠️  POTENTIAL DUPLICATES (#{duplicates.count} pairs):"
        duplicates.first(5).each do |pair|
          puts "   • #{pair[0]} <-> #{pair[1]}"
          recommendations << {
            type: 'potential_merge',
            entities: pair,
            note: 'Review for consolidation'
          }
        end
        puts ''
      end

      # 3. Find stale entities (>90 days since "Last checked")
      stale = find_stale_entities(entities)
      if stale.any?
        puts "⚠️  STALE ENTITIES (#{stale.count}) - >90 days old:"
        stale.each do |e|
          puts "   • #{e['name']}"
          recommendations << {
            type: 'delete_entity',
            entity: e['name']
          }
        end
        puts ''
      end

      # 4. Find date-only observations (noise)
      date_only_cleanup = []
      entities.each do |e|
        obs = e['observations'] || []
        dates = obs.grep(/^(Last (checked|updated)|Recorded):?\s*\d{4}-\d{2}-\d{2}$/)
        date_only_cleanup << { entity: e['name'], observations: dates } if dates.count > 2
      end
      if date_only_cleanup.any?
        puts "⚠️  DATE-ONLY OBSERVATIONS (#{date_only_cleanup.count} entities with >2 each):"
        date_only_cleanup.first(5).each do |c|
          puts "   • #{c[:entity]}: #{c[:observations].count} date-only entries"
          recommendations << {
            type: 'trim_observations',
            entity: c[:entity],
            delete_observations: c[:observations][0..-2] # Keep the most recent one
          }
        end
        puts ''
      end

      # Summary and MCP commands
      if recommendations.empty?
        puts '✅ Memory is clean! No recommendations.'
        return
      end

      puts '═══════════════════════════════════════════════════════════════════════════'
      puts '📋 RECOMMENDED MCP COMMANDS'
      puts '═══════════════════════════════════════════════════════════════════════════'
      puts ''

      # Group by type
      deletes = recommendations.select { |r| r[:type] == 'delete_entity' }
      trims = recommendations.select { |r| r[:type] == 'trim_observations' }

      if deletes.any?
        entity_names = deletes.map { |r| r[:entity] }
        puts 'Delete stale entities:'
        puts '```'
        puts 'mcp__memory__delete_entities'
        puts "entityNames: #{entity_names.to_json}"
        puts '```'
        puts ''
      end

      if trims.any?
        puts 'Trim verbose observations (run each separately):'
        trims.first(3).each do |t|
          puts '```'
          puts 'mcp__memory__delete_observations'
          puts "entityName: \"#{t[:entity]}\""
          puts "observations: #{t[:delete_observations].first(5).to_json}#{'...' if t[:delete_observations].count > 5}"
          puts '```'
          puts ''
        end
        puts "(#{trims.count - 3} more trim recommendations...)" if trims.count > 3
      end

      # Save recommendations to file for reference
      recommendations_file = File.join(Dir.pwd, '.claude', 'memory_cleanup_recommendations.json')
      File.write(recommendations_file, JSON.pretty_generate(recommendations))
      puts '💾 Full recommendations saved to: .claude/memory_cleanup_recommendations.json'
      puts ''
      puts "📉 Estimated savings: ~#{estimate_cleanup_savings(recommendations)} tokens"
    end

    def estimate_cleanup_savings(recommendations)
      total = 0
      recommendations.each do |r|
        case r[:type]
        when 'delete_entity'
          total += 200 # Average entity ~200 tokens
        when 'trim_observations'
          total += (r[:delete_observations]&.count || 0) * 15 # Average observation ~15 tokens
        end
      end
      total
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AUTOMATIC MEMORY MAINTENANCE
    # Called from session hooks - checks health and takes action if needed
    # ═══════════════════════════════════════════════════════════════════════════

    ARCHIVE_FILE = '.claude/memory_archive.jsonl'
    ARCHIVE_THRESHOLD_DAYS = 60

    def auto_memory_check(_args = [])
      # Read memory from STDIN (piped from mcp__memory__read_graph)
      input = begin
        $stdin.read.strip
      rescue StandardError
        ''
      end
      return if input.empty?

      begin
        memory = JSON.parse(input)
      rescue JSON::ParserError
        return
      end

      entities = memory['entities'] || []
      return if entities.empty?

      estimated_tokens = estimate_tokens(memory)
      issues = []

      # Check thresholds
      issues << :entity_count if entities.count > ENTITY_WARN_THRESHOLD
      issues << :token_count if estimated_tokens > TOKEN_WARN_THRESHOLD
      issues << :verbose if find_verbose_entities(entities).any?
      issues << :stale if find_stale_entities(entities).any?

      if issues.empty?
        puts '🧠 Memory health: ✅ OK'
        return
      end

      # Report issues
      puts '🧠 Memory health: ⚠️  Needs attention'
      puts "   Entities: #{entities.count}/#{ENTITY_WARN_THRESHOLD}"
      puts "   Tokens: ~#{estimated_tokens}/#{TOKEN_WARN_THRESHOLD}"

      # Auto-maintenance if any threshold exceeded
      puts ''
      if issues.include?(:entity_count) || issues.include?(:token_count)
        puts '🔧 Running auto-maintenance...'
        auto_maintain_memory(memory, entities)
      else
        puts '💡 Run: ./Scripts/SaneMaster.rb mcleanup (pipe memory graph)'
      end
    end

    def auto_maintain_memory(_memory, entities)
      archive_path = File.join(Dir.pwd, ARCHIVE_FILE)
      FileUtils.mkdir_p(File.dirname(archive_path))

      archived = []
      trimmed = []

      # 1. Archive entities with old "Last checked" dates
      old_entities = entities.select do |e|
        last_checked = (e['observations'] || []).find { |o| o.start_with?('Last checked:') }
        next false unless last_checked

        begin
          date = Date.parse(last_checked.sub('Last checked:', '').strip)
          (Date.today - date).to_i > ARCHIVE_THRESHOLD_DAYS
        rescue StandardError
          false
        end
      end

      if old_entities.any?
        # Append to archive
        File.open(archive_path, 'a') do |f|
          old_entities.each do |e|
            f.puts({
              archived_at: Time.now.utc.iso8601,
              entity: e
            }.to_json)
          end
        end
        archived = old_entities.map { |e| e['name'] }
        puts "   📦 Archived #{archived.count} old entities to #{ARCHIVE_FILE}"
      end

      # 2. Trim verbose entities (keep first 5 + last 3)
      verbose = find_verbose_entities(entities)
      verbose.each do |e|
        obs = e['observations'] || []
        keep = (obs.first(5) + obs.last(3)).uniq
        removed = obs.count - keep.count
        trimmed << { name: e['name'], removed: removed } if removed.positive?
      end

      if trimmed.any?
        total_removed = trimmed.sum { |t| t[:removed] }
        puts "   ✂️  Identified #{total_removed} observations to trim across #{trimmed.count} entities"
      end

      # Output recommended MCP commands
      return unless archived.any? || trimmed.any?

      puts ''
      puts '📋 Recommended MCP actions (run these commands):'

      if archived.any?
        puts ''
        puts 'Delete archived entities:'
        puts "mcp__memory__delete_entities entityNames: #{archived.to_json}"
      end

      return unless trimmed.any?

      puts ''
      puts 'Trim verbose entities (example for first one):'
      first = verbose.first
      obs = first['observations'] || []
      keep = (obs.first(5) + obs.last(3)).uniq
      delete = obs - keep
      puts "mcp__memory__delete_observations entityName: \"#{first['name']}\" observations: #{delete.first(5).to_json}"
    end

    def memory_archive_stats(_args = [])
      archive_path = File.join(Dir.pwd, ARCHIVE_FILE)

      unless File.exist?(archive_path)
        puts '📦 No memory archive found.'
        return
      end

      entries = File.readlines(archive_path).map do |line|
        JSON.parse(line)
      rescue StandardError
        nil
      end.compact
      puts "📦 Memory Archive: #{entries.count} entities"

      # Group by type
      by_type = entries.group_by { |e| e.dig('entity', 'entityType') }
      by_type.each do |type, items|
        puts "   #{type}: #{items.count}"
      end

      # Show archive file size
      size_kb = (File.size(archive_path) / 1024.0).round(1)
      puts ''
      puts "💾 Archive size: #{size_kb} KB"
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

    def estimate_tokens(memory)
      # Rough estimate: ~4 chars per token
      json_str = memory.to_json
      (json_str.length / 4.0).round
    end

    def find_verbose_entities(entities)
      entities.select { |e| (e['observations'] || []).count > OBSERVATION_WARN_THRESHOLD }
              .sort_by { |e| -(e['observations'] || []).count }
    end

    def find_duplicate_candidates(entities)
      names = entities.map { |e| e['name'] }
      duplicates = []

      names.each_with_index do |name1, i|
        names[(i + 1)..].each do |name2|
          # Check for similar names (same prefix or suffix)
          base1 = name1.split(':').last.downcase.gsub(/[_-]/, '')
          base2 = name2.split(':').last.downcase.gsub(/[_-]/, '')

          # Levenshtein-like similarity (simple version)
          if base1.include?(base2) || base2.include?(base1) ||
             (base1.length > 5 && base2.length > 5 && (base1[0, 5] == base2[0, 5]))
            duplicates << [name1, name2]
          end
        end
      end

      duplicates
    end
  end
end
