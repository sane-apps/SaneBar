# frozen_string_literal: true

module SaneMasterModules
  # Crash analysis, xcresult diagnosis, log analysis
  module Diagnostics
    def diagnose(path, dump: false)
      puts '🔬 --- [ SANEMASTER DIAGNOSE ] ---'

      @diagnostics_dir = File.join(Dir.tmpdir, 'SaneBar_Diagnostics')
      FileUtils.mkdir_p(@diagnostics_dir)

      xcresult = path || find_latest_xcresult
      unless xcresult && File.exist?(xcresult)
        puts '❌ No .xcresult bundle found.'
        puts '   Run tests first: ./Scripts/SaneMaster.rb verify'
        return
      end

      puts "📦 Analyzing result: #{xcresult}"
      export_path = export_xcresult(xcresult)
      return unless export_path

      puts "  ✅ Exported to: #{export_path}"
      analyze_app_logs(export_path)
      analyze_test_logs(export_path) if dump
      puts "\n✅ Diagnosis complete."
    end

    def analyze_crashes(args)
      puts '💥 --- [ CRASH REPORT ANALYSIS ] ---'
      puts 'Analyzing SaneBar crash reports for patterns...'
      puts ''

      crash_dir = File.expand_path('~/Library/Logs/DiagnosticReports')
      crash_files = Dir.glob(File.join(crash_dir, 'SaneBar-*.ips')).sort_by { |f| File.mtime(f) }.reverse

      if crash_files.empty?
        puts '✅ No crash reports found. The app appears stable!'
        return
      end

      show_details = args.include?('--details') || args.include?('-d')
      recent_only = args.include?('--recent') || args.include?('-r')

      crash_files = filter_recent_crashes(crash_files) if recent_only
      puts "📊 Found #{crash_files.count} crash report(s)"
      puts ''

      crash_data = parse_crash_files(crash_files.first(50))
      print_crash_analysis(crash_data, show_details)
    end

    private

    def export_xcresult(xcresult)
      export_path = File.join(@diagnostics_dir, "diagnostics_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
      FileUtils.mkdir_p(export_path)

      # Try new API first, fall back to legacy
      export_cmd = "xcrun xcresulttool export diagnostics --path '#{xcresult}' --output-path '#{export_path}' 2>&1"
      export_result = `#{export_cmd}`

      if export_result.include?('error') || export_result.include?('Error')
        export_cmd = "xcrun xcresulttool export --legacy --type directory --path '#{xcresult}' --output-path '#{export_path}' 2>&1"
        export_result = `#{export_cmd}`
      end

      if export_result.include?('error') || export_result.include?('Error')
        puts "  Cannot read xcresult: #{export_result.lines.first}"
        puts '❌ Failed to export diagnostics.'
        return nil
      end

      export_path
    end

    def analyze_app_logs(_export_path)
      app_log = find_app_log
      if app_log
        puts "\n  📱 App Log: #{app_log}"
        puts '  --- App Runtime Insights ---'

        File.foreach(app_log) do |line|
          case line
          when /error|Error|ERROR|crash|Crash|CRASH|exception|Exception/
            puts "  ❌ #{line.strip}"
          when /warning|Warning|WARNING/
            puts "  ⚠️  #{line.strip}"
          when /✅|🎬|📊|🔍/
            puts "  ℹ️  #{line.strip}"
          end
        end
      else
        puts '  ⚠️  No App Log found.'
      end
    end

    def analyze_test_logs(_export_path)
      test_log = find_test_log
      if test_log
        puts "\n  📄 Test Log: #{test_log}"
        puts '  --- Test Runner Insights ---'
        process_test_log(test_log)
      else
        puts '  ⚠️  No Test Runner Log found.'
      end
    end

    def process_test_log(test_log)
      printing_hierarchy = false
      hierarchy_lines_count = 0

      File.foreach(test_log) do |line|
        if line.match?(/dumping.*hierarchy|dumping.*descendants|dumping.*sheet/i)
          puts "  📄 ... Hierarchy Dump Start [matches '#{line.strip}'] ..."
          printing_hierarchy = true
          hierarchy_lines_count = 0
          next
        end

        if printing_hierarchy
          if line.include?("Test Case '-[") || hierarchy_lines_count > 1000
            printing_hierarchy = false
            puts '  📄 ... Hierarchy Dump End ...'
          else
            puts "    #{line}"
            hierarchy_lines_count += 1
            next
          end
        end

        puts "  🔍 #{line.strip}" if line.match?(/debug:/i)
        puts "  ❌ #{line.strip}" if line.include?('failure') || line.include?('Assertion failed')
        puts "  ⏳ #{line.strip}" if line.include?('Waiting') && line.include?('for')
      end
    end

    def find_app_log
      logs = Dir.glob(File.join(@diagnostics_dir, '**', 'StandardOutputAndStandardError*.txt'))
      logs.find { |f| f.include?('com.sanevideo.SaneBar') || f.include?('SaneBar') } || logs.first
    end

    def find_test_log
      logs = Dir.glob(File.join(@diagnostics_dir, '**', 'StandardOutputAndStandardError*.txt'))
      logs.find { |f| f.include?('xctest') || f.include?('Test') }
    end

    def find_latest_xcresult
      system_dd_logs = Dir.glob(File.expand_path('~/Library/Developer/Xcode/DerivedData/SaneBar-*/Logs/Test/*.xcresult'))
      dd_logs = Dir.glob('.derivedData/Logs/Test/*.xcresult')
      fl_logs = Dir.glob('fastlane/test_output/*.xcresult')
      tmp_logs = Dir.glob('/tmp/*.xcresult')

      (system_dd_logs + dd_logs + fl_logs + tmp_logs).max_by { |f| File.mtime(f) }
    end

    def filter_recent_crashes(crash_files)
      cutoff = Time.now - (24 * 60 * 60)
      puts '📅 Showing crashes from last 24 hours only'
      crash_files.select { |f| File.mtime(f) > cutoff }
    end

    def parse_crash_files(crash_files)
      crash_data = []
      crash_files.each do |file|
        data = parse_single_crash(file)
        crash_data << data if data
      rescue StandardError
        # Skip unparseable files
      end
      crash_data
    end

    def parse_single_crash(file)
      content = File.read(file)
      json_start = content.index("\n{")
      return nil unless json_start

      json_data = JSON.parse(content[json_start..])
      exception = json_data['exception'] || {}
      threads = json_data['threads'] || []
      faulting_thread = threads.find { |t| t['triggered'] }

      return nil unless faulting_thread

      frames = faulting_thread['frames'] || []
      signature = frames.first(4).map { |f| (f['symbol'] || '?')[0..35] }.join(' -> ')
      app_frame = find_app_frame(frames)

      {
        file: File.basename(file),
        time: File.mtime(file),
        type: exception['type'] || 'Unknown',
        signal: exception['signal'] || 'Unknown',
        subtype: exception['subtype'],
        signature: signature,
        queue: faulting_thread['queue'] || 'unknown',
        app_frame: app_frame,
        thread_index: json_data['faultingThread'] || 0
      }
    end

    def find_app_frame(frames)
      app_frame = frames.first(15).find do |f|
        src = f['sourceFile'] || ''
        sym = f['symbol'] || ''
        src.include?('SaneBar') || sym.include?('SaneBar')
      end

      return nil unless app_frame

      "#{app_frame['symbol']} (#{File.basename(app_frame['sourceFile'] || 'unknown')}:#{app_frame['sourceLine']})"
    end

    def print_crash_analysis(crash_data, show_details)
      print_crash_distribution(crash_data)
      print_thread_distribution(crash_data)
      print_top_signatures(crash_data)
      print_app_frames(crash_data)
      print_known_patterns(crash_data)
      print_crash_details(crash_data) if show_details
      print_crash_summary(crash_data)
    end

    def print_crash_distribution(crash_data)
      puts '📈 CRASH TYPE DISTRIBUTION'
      puts '─' * 50
      type_counts = crash_data.group_by { |c| c[:type] }.transform_values(&:count)
      type_counts.sort_by { |_, count| -count }.each do |type, count|
        pct = (count.to_f / crash_data.count * 100).round(1)
        puts "  #{type}: #{count} (#{pct}%)"
      end
      puts ''
    end

    def print_thread_distribution(crash_data)
      puts '🧵 FAULTING THREAD DISTRIBUTION'
      puts '─' * 50
      thread_counts = crash_data.group_by { |c| c[:thread_index] }.transform_values(&:count)
      thread_counts.sort_by { |_, count| -count }.each do |thread, count|
        pct = (count.to_f / crash_data.count * 100).round(1)
        label = thread.zero? ? 'Main Thread' : "Thread #{thread}"
        puts "  #{label}: #{count} (#{pct}%)"
      end
      puts ''
    end

    def print_top_signatures(crash_data)
      puts '🔍 TOP CRASH SIGNATURES (Pattern Detection)'
      puts '─' * 50
      sig_counts = crash_data.group_by { |c| c[:signature] }.transform_values(&:count)
      sig_counts.sort_by { |_, count| -count }.first(8).each do |sig, count|
        puts "  [#{count}x] #{sig}"
      end
      puts ''
    end

    def print_app_frames(crash_data)
      app_frames = crash_data.map { |c| c[:app_frame] }.compact
      return unless app_frames.any?

      puts '📱 SANEVIDEO CODE FRAMES'
      puts '─' * 50
      frame_counts = app_frames.group_by(&:itself).transform_values(&:count)
      frame_counts.sort_by { |_, count| -count }.first(10).each do |frame, count|
        puts "  [#{count}x] #{frame}"
      end
      puts ''
    end

    def print_known_patterns(crash_data)
      puts '⚠️  KNOWN ISSUE PATTERNS'
      puts '─' * 50

      patterns = {
        'Actor Isolation (MainActor.assumeIsolated)' => crash_data.count { |c| c[:signature].include?('dispatch_assert_queue') },
        'Object Deallocated (Timer/Publisher)' => crash_data.count do |c|
          c[:signature].include?('isMainExecutor') && c[:subtype]&.include?('0x000000000000001')
        end,
        'Test Cleanup (XCTMemoryChecker)' => crash_data.count { |c| c[:signature].include?('XCTMemoryChecker') },
        'Memory Corruption (objc_release)' => crash_data.count { |c| c[:signature].start_with?('objc_release') && !c[:signature].include?('XCTMemoryChecker') }
      }

      patterns.each do |pattern, count|
        next if count.zero?

        pct = (count.to_f / crash_data.count * 100).round(1)
        puts "  #{pattern}: #{count} (#{pct}%)"
      end
      puts ''
    end

    def print_crash_details(crash_data)
      puts '📋 RECENT CRASHES (Details)'
      puts '─' * 50
      crash_data.first(10).each do |crash|
        puts "  📄 #{crash[:file]}"
        puts "     Time: #{crash[:time].strftime('%Y-%m-%d %H:%M:%S')}"
        puts "     Type: #{crash[:type]} (#{crash[:signal]})"
        puts "     Queue: #{crash[:queue]}"
        puts "     Signature: #{crash[:signature]}"
        puts "     App Frame: #{crash[:app_frame]}" if crash[:app_frame]
        puts ''
      end
    end

    def print_crash_summary(crash_data)
      puts '📊 SUMMARY'
      puts '─' * 50
      puts "  Total crashes analyzed: #{crash_data.count}"
      puts "  Oldest: #{crash_data.last[:time].strftime('%Y-%m-%d %H:%M')}" if crash_data.any?
      puts "  Newest: #{crash_data.first[:time].strftime('%Y-%m-%d %H:%M')}" if crash_data.any?

      main_thread_crashes = crash_data.count { |c| c[:thread_index].zero? }
      puts "  ⚠️  #{main_thread_crashes}/#{crash_data.count} crashes on Main Thread - check UI/state code" if main_thread_crashes > crash_data.count * 0.5

      test_crashes = crash_data.count { |c| c[:signature].include?('XCT') }
      return unless test_crashes.positive?

      puts "  ℹ️  #{test_crashes} crash(es) in test cleanup - review async test handling"
    end
  end
end
# rubocop:enable Metrics/ModuleLength
