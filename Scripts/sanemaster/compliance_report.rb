# frozen_string_literal: true

# Compliance Report Module
# Generates end-of-session compliance summary from audit log

require 'json'

module SaneMasterModules
  module ComplianceReport
    AUDIT_LOG = File.join(Dir.pwd, '.claude', 'audit_log.jsonl')
    BREAKER_STATE = File.join(Dir.pwd, '.claude', 'circuit_breaker.json')

    RULE_NAMES = {
      '#1:STAY_IN_LANE' => 'Stay in Your Lane',
      '#3:TWO_STRIKES' => 'Investigate After Two',
      '#5:SANEMASTER' => 'Use SaneMaster',
      '#6:FULL_CYCLE' => 'Full Verification Cycle',
      '#7:TEST_QUALITY' => 'No Tautology Tests',
      '#10:FILE_SIZE' => 'File Size Limits',
      '#RALPH:EXIT_CONDITION' => 'Ralph Loop Safety'
    }.freeze

    def self.generate(session_id: nil)
      entries = load_audit_log(session_id)
      breaker = load_breaker_state

      if entries.empty?
        puts "\n📊 No audit log entries found for this session.\n"
        return
      end

      # Count by rule
      rule_stats = Hash.new { |h, k| h[k] = { pass: 0, warn: 0, blocked: 0 } }

      entries.each do |entry|
        result = entry['result'] || 'pass'
        (entry['rules_checked'] || []).each do |rule|
          rule_stats[rule][result.to_sym] += 1
        end
      end

      # Generate report
      puts ''
      puts '📊 Session Compliance Report'
      puts '═' * 50

      total_checks = 0
      total_pass = 0
      total_warn = 0
      total_blocked = 0

      RULE_NAMES.each do |rule_key, rule_name|
        stats = rule_stats[rule_key]
        next if stats[:pass].zero? && stats[:warn].zero? && stats[:blocked].zero?

        total = stats[:pass] + stats[:warn] + stats[:blocked]
        total_checks += total
        total_pass += stats[:pass]
        total_warn += stats[:warn]
        total_blocked += stats[:blocked]

        status = if stats[:blocked].positive?
                   '🔴'
                 elsif stats[:warn].positive?
                   '⚠️ '
                 else
                   '✅'
                 end

        pct = total.positive? ? ((stats[:pass].to_f / total) * 100).round : 100
        detail = []
        detail << "#{stats[:blocked]} blocked" if stats[:blocked].positive?
        detail << "#{stats[:warn]} warnings" if stats[:warn].positive?
        detail_str = detail.empty? ? '' : " (#{detail.join(', ')})"

        puts "#{status} #{rule_name.ljust(25)} #{pct}%#{detail_str}"
      end

      puts '─' * 50

      # Overall score
      if total_checks.positive?
        overall_pct = ((total_pass.to_f / total_checks) * 100).round
        puts "Overall: #{overall_pct}% compliant (#{total_checks} checks)"
      end

      # Circuit breaker status
      breaker_status = if breaker[:tripped]
                         "🔴 TRIPPED (#{breaker[:failures]} failures)"
                       elsif breaker[:failures].positive?
                         "⚠️  #{breaker[:failures]}/#{breaker[:threshold]} failures"
                       else
                         '✅ CLOSED (0 failures)'
                       end
      puts "Circuit breaker: #{breaker_status}"

      # Tool usage summary
      tool_counts = entries.group_by { |e| e['tool'] }.transform_values(&:count)
      puts ''
      puts 'Tool usage:'
      tool_counts.sort_by { |_, v| -v }.first(5).each do |tool, count|
        puts "  #{tool}: #{count}"
      end

      puts '═' * 50
      puts ''
    end

    def self.load_audit_log(session_id = nil)
      return [] unless File.exist?(AUDIT_LOG)

      entries = File.readlines(AUDIT_LOG).map do |line|
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end.compact

      # Filter by session if specified
      if session_id
        entries.select! { |e| e['session'] == session_id }
      else
        # Get entries from last 24 hours
        cutoff = Time.now - (24 * 60 * 60)
        entries.select! do |e|
          Time.parse(e['timestamp']) > cutoff
        rescue StandardError
          false
        end
      end

      entries
    end

    def self.load_breaker_state
      return default_breaker unless File.exist?(BREAKER_STATE)

      state = JSON.parse(File.read(BREAKER_STATE), symbolize_names: true)
      state[:threshold] ||= 5
      state
    rescue StandardError
      default_breaker
    end

    def self.default_breaker
      { failures: 0, tripped: false, threshold: 5 }
    end
  end
end
