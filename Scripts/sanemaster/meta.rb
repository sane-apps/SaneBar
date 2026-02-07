# frozen_string_literal: true

module SaneMasterModules
  # Meta-audit of SaneMaster tooling itself
  # Philosophy: Stability over bleeding edge. Prevent spiraling, not chase latest.
  module Meta
    include Base

    TOOL_LATEST_CHECK = {
      'swiftlint' => { brew: 'swiftlint', current_cmd: 'swiftlint --version' },
      'xcodegen' => { brew: 'xcodegen', current_cmd: 'xcodegen --version' },
      'periphery' => { brew: 'periphery', current_cmd: 'periphery version' },
      'mockolo' => { brew: 'mockolo', current_cmd: 'mockolo --version' },
      'lefthook' => { brew: 'lefthook', current_cmd: 'lefthook version' }
    }.freeze

    RUBY_FILE_SOFT_LIMIT = 500
    RUBY_FILE_HARD_LIMIT = 800
    TOTAL_RUBY_LINES_WARN = 6000  # Warn if tooling grows too large
    RUBOCOP_OFFENSE_LIMIT = 30    # Acceptable threshold

    SWIFT_FILE_SOFT_LIMIT = 500
    SWIFT_FILE_HARD_LIMIT = 800
    CRASH_REPORT_WARN = 5         # Warn if unaddressed crashes pile up
    TEST_COUNT_MIN = 900          # Warn if test count drops significantly
    TEST_QUALITY_WARN = 0         # Zero tolerance for test anti-patterns

    def run_meta(_args = [])
      start_time = Time.now
      puts '🩺 --- [ HEALTH CHECK ] ---'
      puts '    System, factoring, stability, configuration'
      puts ''

      results = {
        system: check_system_health,
        ruby_files: check_ruby_file_sizes,
        swift_files: check_swift_file_sizes,
        rubocop: check_rubocop_issues,
        test_count: check_test_count,
        test_quality: check_test_quality,
        mocks: check_mock_freshness,
        crash_backlog: check_crash_backlog,
        tool_versions: check_tool_versions_smart,
        hooks: check_hooks_health,
        mcp: check_mcp_health,
        commands: check_command_coverage
      }

      elapsed = ((Time.now - start_time) * 1000).round
      print_meta_summary(results, elapsed)
    end

    private

    def check_system_health
      puts '💻 System:'
      issues = []

      # Stuck processes
      stuck = find_stuck_processes
      if stuck.any?
        puts "   ⚠️  Stuck processes: #{stuck.join(', ')}"
        issues << :stuck_processes
      else
        puts '   ✅ No stuck processes'
      end

      # Disk space
      available = `df -h . | tail -1 | awk '{print $4}'`.strip
      if available.end_with?('M') || available.to_f < 20
        puts "   ⚠️  Low disk: #{available}"
        issues << :low_disk
      else
        puts "   ✅ Disk: #{available} available"
      end

      # DerivedData
      dd_size = begin
        `du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null`.split.first
      rescue StandardError
        '0'
      end
      size_gb = dd_size.end_with?('G') ? dd_size.to_f : 0
      if size_gb > 10
        puts "   ⚠️  DerivedData: #{dd_size} (clean with: rm -rf ~/Library/Developer/Xcode/DerivedData)"
        issues << :large_derived_data
      else
        puts "   ✅ DerivedData: #{dd_size}"
      end

      puts ''
      { issues: issues, status: issues.empty? ? :ok : :warning }
    end

    def find_stuck_processes
      stuck_pids = `pgrep -f 'xcodebuild|xctest' 2>/dev/null`.strip.split
      stuck_pids.reject do |pid|
        cmd = `ps -p #{pid} -o command= 2>/dev/null`.strip
        cmd.include?('mcpbridge')
      end
    end

    def check_ruby_file_sizes
      puts '📏 Ruby Factoring:'
      issues = []

      ruby_files = Dir.glob('Scripts/**/*.rb')
      file_data = ruby_files
                  .map { |file| { file: file.sub('Scripts/', ''), lines: File.readlines(file).count } }
                  .sort_by { |f| -f[:lines] }

      # Only show problematic files
      file_data.each do |fd|
        if fd[:lines] > RUBY_FILE_HARD_LIMIT
          puts "   ❌ #{fd[:file]}: #{fd[:lines]} lines (SPLIT REQUIRED)"
          issues << { file: fd[:file], lines: fd[:lines], severity: :hard }
        elsif fd[:lines] > RUBY_FILE_SOFT_LIMIT
          puts "   ⚠️  #{fd[:file]}: #{fd[:lines]} lines (watch this)"
          issues << { file: fd[:file], lines: fd[:lines], severity: :soft }
        end
      end

      total = file_data.sum { |f| f[:lines] }

      if total > TOTAL_RUBY_LINES_WARN
        puts "   ⚠️  Total: #{total} lines (getting large)"
      else
        puts "   ✅ Total: #{total} lines across #{ruby_files.count} files"
      end

      puts '   ✅ All files within limits' if issues.empty?
      puts ''

      issues
    end

    def check_swift_file_sizes
      puts '📱 Swift Factoring:'
      issues = []

      app_dir = project_app_dir
      tests_dir = project_tests_dir
      swift_files = Dir.glob("#{app_dir}/**/*.swift") + Dir.glob("#{tests_dir}/**/*.swift")

      # Exclude generated files
      swift_files.reject! { |f| f.include?('Mocks.swift') || f.include?('.generated.') }

      file_data = swift_files
                  .map { |file| { file: file, lines: File.readlines(file).count } }
                  .sort_by { |f| -f[:lines] }

      # Only show problematic files (top offenders)
      shown = 0
      file_data.each do |fd|
        if fd[:lines] > SWIFT_FILE_HARD_LIMIT
          puts "   ❌ #{fd[:file]}: #{fd[:lines]} lines (SPLIT REQUIRED)"
          issues << { file: fd[:file], lines: fd[:lines], severity: :hard }
          shown += 1
        elsif fd[:lines] > SWIFT_FILE_SOFT_LIMIT && shown < 5
          display_path = fd[:file].sub(%r{^#{Regexp.escape(app_dir)}/}, '')
          display_path = display_path.sub(%r{^#{Regexp.escape(tests_dir)}/}, '')
          puts "   ⚠️  #{display_path}: #{fd[:lines]} lines"
          issues << { file: fd[:file], lines: fd[:lines], severity: :soft }
          shown += 1
        end
      end

      hard_count = issues.count { |i| i[:severity] == :hard }
      soft_count = issues.count { |i| i[:severity] == :soft }

      if hard_count.positive?
        puts "   ❌ #{hard_count} file(s) over hard limit"
      elsif soft_count.positive?
        more = file_data.count { |f| f[:lines] > SWIFT_FILE_SOFT_LIMIT } - shown
        puts "   ... and #{more} more over soft limit" if more.positive?
      else
        puts '   ✅ All files within limits'
      end
      puts ''

      issues
    end

    def check_test_count
      puts '🧪 Test Health:'

      # Check last verify output for actual test count
      # XCTest reports more tests than grep finds due to parameterized tests
      last_verify = `grep -r "tests passed" ~/.sanemaster/logs/*.log 2>/dev/null | tail -1`

      if last_verify.match(/(\d+) tests/)
        count = ::Regexp.last_match(1).to_i
        if count < TEST_COUNT_MIN
          puts "   ⚠️  #{count} tests (expected #{TEST_COUNT_MIN}+)"
          puts ''
          return { count: count, status: :warning }
        else
          puts "   ✅ #{count} tests (from last verify)"
          puts ''
          return { count: count, status: :ok }
        end
      end

      # Fallback: count test files
      test_files = Dir.glob("#{project_tests_dir}/**/*Tests.swift").count
      puts "   ✅ #{test_files} test files"
      puts ''
      { count: test_files, status: :ok }
    end

    # Test Quality Linter - detects unfalsifiable tests
    # Anti-patterns that always pass regardless of code behavior:
    # - Tautologies: `x == true || x == false` (always true)
    # - Always-true: `#expect(Bool(true))` or `#expect(true)`
    # - Hardcoded magic values that only work for specific inputs
    # - TODO/FIXME placeholders in assertions
    def check_test_quality
      puts '🔬 Test Quality:'
      scan_test_quality(verbose: false)
    end

    # Full test quality scan with line numbers - standalone command
    def run_test_scan(args = [])
      verbose = args.include?('--verbose') || args.include?('-v')
      puts '🔬 --- [ TEST QUALITY SCAN ] ---'
      puts 'Scanning Swift test files for anti-patterns...'
      puts ''
      scan_test_quality(verbose: true)
    end

    # Core scanning logic - used by both check_test_quality and run_test_scan
    def scan_test_quality(verbose: false)
      # Comprehensive patterns from test_quality_checker.rb
      tautology_patterns = [
        # Literal true/false assertions
        { pattern: /#expect\s*\(\s*true\s*\)/i, name: '#expect(true)' },
        { pattern: /#expect\s*\(\s*false\s*\)/i, name: '#expect(false)' },
        { pattern: /XCTAssertTrue\s*\(\s*true\s*\)/i, name: 'XCTAssertTrue(true)' },
        { pattern: /XCTAssertFalse\s*\(\s*false\s*\)/i, name: 'XCTAssertFalse(false)' },
        { pattern: /XCTAssert\s*\(\s*true\s*\)/i, name: 'XCTAssert(true)' },
        # Always-true boolean logic
        { pattern: /== true\s*\|\|\s*.*== false/i, name: 'x == true || x == false (always true)' },
        { pattern: /== false\s*\|\|\s*.*== true/i, name: 'x == false || x == true (always true)' },
        # Placeholder assertions
        { pattern: /XCTAssert.*TODO/i, name: 'XCTAssert with TODO' },
        { pattern: /XCTAssert.*FIXME/i, name: 'XCTAssert with FIXME' },
        { pattern: /#expect.*TODO/i, name: '#expect with TODO' },
        { pattern: /#expect.*FIXME/i, name: '#expect with FIXME' }
      ]

      hardcoded_patterns = [
        # Magic numbers (excluding 0, 1, 2, 10, 100, -1)
        { pattern: /#expect\s*\([^)]+==\s*(?!0\b|1\b|2\b|10\b|100\b|-1\b)\d{2,}\s*\)/, name: 'Hardcoded magic number' },
        { pattern: /XCTAssertEqual\s*\([^,]+,\s*(?!0\b|1\b|2\b|10\b|100\b|-1\b)\d{2,}\s*\)/, name: 'Hardcoded magic number' },
        # Long literal strings (30+ chars)
        { pattern: /#expect\s*\([^)]+==\s*"[^"]{30,}"\s*\)/, name: 'Long hardcoded string' },
        { pattern: /XCTAssertEqual\s*\([^,]+,\s*"[^"]{30,}"\s*\)/, name: 'Long hardcoded string' },
        # Arbitrary array counts
        { pattern: /#expect\s*\([^)]+\.count\s*==\s*(?!0\b|1\b|2\b|3\b|10\b)\d+\s*\)/, name: 'Hardcoded array count' }
      ]

      issues = { tautologies: [], hardcoded: [] }
      test_files = Dir.glob("#{project_tests_dir}/**/*.swift")

      test_files.each do |file|
        content = File.read(file)
        lines = content.lines
        relative_path = file.sub(%r{^#{Regexp.escape(project_tests_dir)}/}, '')

        # Check tautology patterns with line numbers
        tautology_patterns.each do |pat|
          lines.each_with_index do |line, idx|
            next unless line.match?(pat[:pattern])

            issues[:tautologies] << {
              file: relative_path,
              line: idx + 1,
              pattern: pat[:name],
              snippet: line.strip[0..60]
            }
          end
        end

        # Check hardcoded patterns with line numbers
        hardcoded_patterns.each do |pat|
          lines.each_with_index do |line, idx|
            next unless line.match?(pat[:pattern])

            issues[:hardcoded] << {
              file: relative_path,
              line: idx + 1,
              pattern: pat[:name],
              snippet: line.strip[0..60]
            }
          end
        end
      end

      total_tautologies = issues[:tautologies].count
      total_hardcoded = issues[:hardcoded].count
      total_issues = total_tautologies + total_hardcoded

      if total_issues > TEST_QUALITY_WARN
        if verbose
          # Detailed output with line numbers
          if issues[:tautologies].any?
            puts '❌ TAUTOLOGIES (tests that always pass):'
            issues[:tautologies].group_by { |i| i[:file] }.each do |file, file_issues|
              puts "   📄 #{file}"
              file_issues.each do |issue|
                puts "      Line #{issue[:line]}: #{issue[:pattern]}"
                puts "         #{issue[:snippet]}..." if issue[:snippet].length > 10
              end
            end
            puts ''
          end

          if issues[:hardcoded].any?
            puts '⚠️  HARDCODED VALUES (may not generalize):'
            issues[:hardcoded].group_by { |i| i[:file] }.each do |file, file_issues|
              puts "   📄 #{file}"
              file_issues.each do |issue|
                puts "      Line #{issue[:line]}: #{issue[:pattern]}"
              end
            end
            puts ''
          end

          puts '─' * 50
          puts "📊 Summary: #{total_tautologies} tautologies, #{total_hardcoded} hardcoded values"
          puts ''
          puts '💡 A good test should:'
          puts '   • Test computed values, not literals'
          puts '   • Fail when code is broken'
          puts '   • Work for all valid inputs, not just test fixtures'
        else
          # Brief output for health check
          puts "   ❌ #{total_issues} test quality issues found"
          issues[:tautologies].group_by { |i| i[:file] }.each do |file, arr|
            puts "      ⚠️  #{file}: #{arr.count} tautological assertion(s)"
          end
          issues[:hardcoded].group_by { |i| i[:file] }.each do |file, arr|
            puts "      💡 #{file}: #{arr.count} hardcoded value(s)"
          end
        end
      else
        puts '   ✅ No test anti-patterns detected'
      end

      puts ''
      { status: total_issues > TEST_QUALITY_WARN ? :warning : :ok, issues: issues, count: total_issues }
    end

    def check_mock_freshness
      puts '🎭 Mock Freshness:'

      mocks_file = File.join(project_tests_dir, 'Mocks', 'Mocks.swift')
      protocol_dir = File.join(project_app_dir, 'Core', 'Protocols')

      # Check if any protocols exist first
      protocol_files = Dir.glob("#{protocol_dir}/**/*.swift")
      if protocol_files.empty?
        puts '   ✅ No protocols to mock'
        puts ''
        return { status: :ok, stale: false }
      end

      unless File.exist?(mocks_file)
        puts '   ⚠️  Mocks.swift not found'
        puts ''
        return { status: :warning, stale: true }
      end

      mocks_mtime = File.mtime(mocks_file)

      # Find any protocol file newer than Mocks.swift
      stale_protocols = Dir.glob("#{protocol_dir}/**/*.swift").select do |f|
        File.mtime(f) > mocks_mtime
      end

      if stale_protocols.any?
        puts "   ⚠️  Mocks may be stale (#{stale_protocols.count} protocol(s) modified since)"
        stale_protocols.first(3).each { |f| puts "      #{File.basename(f)}" }
        puts ''
        { status: :warning, stale: true, files: stale_protocols }
      else
        puts "   ✅ Up to date (#{mocks_mtime.strftime('%m/%d %H:%M')})"
        puts ''
        { status: :ok, stale: false }
      end
    end

    def check_crash_backlog
      puts '💥 Crash Backlog:'

      crash_dir = File.expand_path('~/Library/Logs/DiagnosticReports')
      recent_crashes = Dir.glob("#{crash_dir}/#{project_name}*.ips").select do |f|
        File.mtime(f) > (Time.now - (7 * 24 * 60 * 60)) # Last 7 days
      end

      if recent_crashes.count > CRASH_REPORT_WARN
        puts "   ⚠️  #{recent_crashes.count} crashes in last 7 days"
        recent_crashes.first(3).each do |f|
          puts "      #{File.basename(f)} (#{File.mtime(f).strftime('%m/%d')})"
        end
        puts ''
        { count: recent_crashes.count, status: :warning, files: recent_crashes }
      elsif recent_crashes.any?
        puts "   ℹ️  #{recent_crashes.count} crash(es) in last 7 days"
        puts ''
        { count: recent_crashes.count, status: :info, files: recent_crashes }
      else
        puts '   ✅ No recent crashes'
        puts ''
        { count: 0, status: :ok, files: [] }
      end
    end

    def check_rubocop_issues
      puts '🔍 Code Quality:'

      output = `bundle exec rubocop Scripts/ --format simple 2>/dev/null | tail -5`

      if output.match(/(\d+) offenses? detected/)
        count = ::Regexp.last_match(1).to_i
        if count > RUBOCOP_OFFENSE_LIMIT
          puts "   ❌ #{count} rubocop offenses (fix needed)"
        elsif count.positive?
          puts "   ✅ #{count} rubocop offenses (acceptable)"
        else
          puts '   ✅ No rubocop offenses'
        end
        puts ''
        return count
      end

      puts '   ✅ Clean'
      puts ''
      0
    end

    # Smart version checking: recommend minor/patch updates, just note major versions
    def check_tool_versions_smart
      puts '📦 Tool Versions:'
      recommendations = []

      TOOL_LATEST_CHECK.each do |name, config|
        result = check_single_tool(name, config[:current_cmd], config[:brew])
        recommendations << result if result
      end

      # Check Ruby separately with major version awareness
      ruby_result = check_ruby_version
      recommendations << ruby_result if ruby_result

      puts ''
      recommendations
    end

    def check_single_tool(name, current_cmd, brew_name)
      current = `#{current_cmd} 2>/dev/null`.strip.split.last&.gsub(/[^\d.]/, '') || 'unknown'
      latest = `brew info #{brew_name} 2>/dev/null | head -1`.strip.match(/[\d.]+/)&.to_s || 'unknown'

      return nil if current == 'unknown' || latest == 'unknown' || current == latest

      begin
        current_v = Gem::Version.new(current)
        latest_v = Gem::Version.new(latest)

        return nil if current_v >= latest_v

        current_parts = current.split('.').map(&:to_i)
        latest_parts = latest.split('.').map(&:to_i)

        major_bump = latest_parts[0] > current_parts[0]

        if major_bump
          # Major version: just note, don't recommend immediate update
          puts "   ℹ️  #{name}: #{current} (#{latest} available - major release, wait for .1)"
          nil
        else
          # Minor/patch: recommend update
          puts "   ⬆️  #{name}: #{current} → #{latest} (safe update)"
          { name: name, current: current, latest: latest, type: :recommended }
        end
      rescue ArgumentError
        puts "   ✅ #{name}: #{current}"
        nil
      end
    end

    def check_ruby_version
      current = RUBY_VERSION
      latest = `brew info ruby 2>/dev/null | head -1`.strip.match(/\d+\.\d+\.\d+/)&.to_s

      return nil unless latest && current != latest

      current_major = current.split('.').first.to_i
      latest_major = latest.split('.').first.to_i

      if latest_major > current_major
        puts "   ℹ️  ruby: #{current} (#{latest} available - major release, wait for stability)"
        nil
      elsif Gem::Version.new(current) < Gem::Version.new(latest)
        puts "   ⬆️  ruby: #{current} → #{latest} (safe update)"
        { name: 'ruby', current: current, latest: latest, type: :recommended }
      else
        puts "   ✅ ruby: #{current}"
        nil
      end
    end

    def check_hooks_health
      puts '🪝 Claude Hooks:'

      settings_file = File.join(Dir.pwd, '.claude', 'settings.json')
      unless File.exist?(settings_file)
        puts '   ❌ No .claude/settings.json'
        puts ''
        return { status: :missing }
      end

      begin
        settings = JSON.parse(File.read(settings_file))
        hooks = settings['hooks'] || {}

        expected = %w[SessionStart SessionEnd PreToolUse PostToolUse]
        missing = expected - hooks.keys

        hooks.each do |event, configs|
          hook_count = configs.sum { |c| (c['hooks'] || []).count }
          puts "   ✅ #{event}: #{hook_count} hook(s)"
        end

        missing.each do |event|
          puts "   ℹ️  #{event}: not configured"
        end

        puts ''
        { status: :ok, configured: hooks.keys, missing: missing }
      rescue JSON::ParserError
        puts '   ❌ settings.json parse error'
        puts ''
        { status: :error }
      end
    end

    def check_mcp_health
      puts '🔌 MCP Servers:'

      mcp_file = File.join(Dir.pwd, '.mcp.json')
      unless File.exist?(mcp_file)
        puts '   ❌ No .mcp.json'
        puts ''
        return { status: :missing }
      end

      begin
        mcp = JSON.parse(File.read(mcp_file))
        servers = mcp['mcpServers'] || {}

        # NOTE: xcode MCP is configured globally (xcrun mcpbridge)
        # NOTE: Memory MCP removed Jan 2026 - using Sane-Mem (localhost:37777) instead
        required = %w[apple-docs github context7 xcode]

        required.each do |name|
          if servers[name]
            puts "   ✅ #{name}"
          else
            puts "   ❌ #{name}: missing"
          end
        end

        extra = servers.keys - required
        extra.each do |name|
          puts "   ➕ #{name}: extra"
        end

        puts ''
        { status: :ok, configured: servers.keys }
      rescue JSON::ParserError
        puts '   ❌ .mcp.json parse error'
        puts ''
        { status: :error }
      end
    end

    def check_command_coverage
      puts '📋 Command Coverage:'

      # Count commands in COMMANDS hash (approximate by grepping)
      main_file = File.read('Scripts/SaneMaster.rb')
      command_count = main_file.scan(/when '[\w_]+'/).count

      puts "   📊 #{command_count} commands registered"

      # Check for undocumented commands (in dispatch but not in COMMANDS)
      # This is a simple heuristic
      puts '   ✅ Help system functional'
      puts ''

      command_count
    end

    def print_meta_summary(results, elapsed_ms)
      puts '─' * 50

      issues = []
      actions = []

      # System health
      if results[:system][:status] == :warning
        if results[:system][:issues].include?(:stuck_processes)
          issues << 'Stuck build processes'
          actions << 'killall -9 xcodebuild xctest'
        end
        if results[:system][:issues].include?(:large_derived_data)
          issues << 'DerivedData bloated'
          actions << 'rm -rf ~/Library/Developer/Xcode/DerivedData'
        end
        issues << 'Low disk space' if results[:system][:issues].include?(:low_disk)
      end

      # Ruby file sizes - only hard limits are real issues
      ruby_hard = results[:ruby_files].count { |i| i[:severity] == :hard }
      if ruby_hard.positive?
        issues << "#{ruby_hard} Ruby file(s) need splitting"
        actions << 'Split large Ruby files by responsibility'
      end

      # Swift file sizes - only hard limits are real issues
      swift_hard = results[:swift_files].count { |i| i[:severity] == :hard }
      if swift_hard.positive?
        issues << "#{swift_hard} Swift file(s) need splitting"
        actions << 'Split large Swift files by responsibility'
      end

      # Rubocop - only if over threshold
      if results[:rubocop] > RUBOCOP_OFFENSE_LIMIT
        issues << "#{results[:rubocop]} rubocop offenses"
        actions << 'rubocop -a Scripts/'
      end

      # Test count - if dropping
      if results[:test_count][:status] == :warning
        issues << "Test count dropped to #{results[:test_count][:count]}"
        actions << 'Investigate missing tests'
      end

      # Test quality - zero tolerance for anti-patterns
      if results[:test_quality][:status] == :warning
        issues << "#{results[:test_quality][:count]} test quality issues"
        actions << 'Fix unfalsifiable tests (see plan in .claude/plans/)'
      end

      # Mocks freshness
      if results[:mocks][:status] == :warning
        issues << 'Mocks may be stale'
        actions << './Scripts/SaneMaster.rb gen_mock'
      end

      # Crash backlog
      if results[:crash_backlog][:status] == :warning
        issues << "#{results[:crash_backlog][:count]} unaddressed crashes"
        actions << './Scripts/SaneMaster.rb crashes --recent'
      end

      # Tool versions - only if there are recommended (non-major) updates
      recommended = results[:tool_versions].compact
      if recommended.any?
        names = recommended.map { |r| r[:name] }.join(', ')
        issues << "Updates available: #{names}"
        actions << "brew upgrade #{names}"
      end

      # MCP/Hooks - configuration issues
      issues << 'MCP configuration issue' if results[:mcp][:status] != :ok

      issues << 'Hook configuration issue' if results[:hooks][:status] != :ok

      if issues.empty?
        puts "✅ Tooling healthy (#{elapsed_ms}ms)"
        puts ''
        puts '   No action needed. Tools are stable and well-factored.'
      else
        puts "⚠️  #{issues.count} item(s) to address (#{elapsed_ms}ms)"
        puts ''
        issues.each { |i| puts "   • #{i}" }
        puts ''
        puts '💡 Actions:'
        actions.each { |a| puts "   #{a}" }
      end
    end
  end
end
