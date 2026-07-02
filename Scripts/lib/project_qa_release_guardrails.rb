# frozen_string_literal: true

class ProjectQA
  private

  def check_release_hygiene_guardrails
    print 'Checking release hygiene guardrails... '

    failures = []
    failures.concat(changelog_duplicate_heading_failures)
    failures.concat(privacy_manifest_failures)
    failures.concat(settings_docs_parity_failures)
    warnings = large_local_artifact_warnings

    if failures.empty?
      warnings.each { |warning| @warnings << warning }
      note = warnings.empty? ? '' : " (#{warnings.count} local artifact warning(s))"
      puts "✅ changelog + privacy manifest#{note}"
    else
      failures.each { |failure| @errors << failure }
      warnings.each { |warning| @warnings << warning }
      puts "❌ #{failures.count} release hygiene issue(s)"
    end
  end

  def changelog_duplicate_heading_failures
    changelog = File.join(PROJECT_ROOT, 'CHANGELOG.md')
    return [] unless File.exist?(changelog)

    headings = File.read(changelog).scan(/^## \[([^\]]+)\]/).flatten
    counts = Hash.new(0)
    headings.each { |version| counts[version] += 1 }
    duplicates = counts.select { |_version, count| count > 1 }
    return [] if duplicates.empty?

    ["Duplicate CHANGELOG version heading(s): #{duplicates.map { |version, count| "#{version} x#{count}" }.join(', ')}"]
  end

  def privacy_manifest_failures
    manifests = Dir.glob(File.join(PROJECT_ROOT, '**', 'PrivacyInfo.xcprivacy')).reject do |path|
      path.include?('/build/') || path.include?('/DerivedData/')
    end
    return ['PrivacyInfo.xcprivacy missing'] if manifests.empty?

    content = manifests.map { |path| File.read(path) }.join("\n")
    failures = []
    required_privacy_categories.each do |category, reason|
      unless content.include?(category)
        failures << "PrivacyInfo.xcprivacy missing required reason API category #{category}"
        next
      end
      next if reason.nil? || content.include?(reason)

      failures << "PrivacyInfo.xcprivacy category #{category} is missing reason #{reason}"
    end
    failures
  end

  def required_privacy_categories
    source = privacy_scanned_source
    PRIVACY_REQUIRED_REASON_PATTERNS.each_with_object({}) do |(category, config), required|
      next unless config.fetch(:patterns).any? { |pattern| source.match?(pattern) }

      required[category] = config[:reason]
    end
  end

  def privacy_scanned_source
    Dir.glob(File.join(PROJECT_ROOT, '{Core,UI,SaneBar}', '**', '*.swift')).map do |path|
      File.read(path)
    end.join("\n")
  end

  def settings_docs_parity_failures
    settings_view = File.join(PROJECT_ROOT, 'UI', 'SettingsView.swift')
    return [] unless File.exist?(settings_view) && File.exist?(README)

    settings_source = File.read(settings_view)
    tabs = settings_source.scan(/case\s+\w+\s*=\s*"([^"]+)"/).flatten.uniq
    return [] if tabs.empty?

    readme = File.read(README)
    missing = tabs.reject { |tab| readme.include?("| **#{tab}** |") }
    stale_general = tabs.include?('Control') && readme.include?('| **General** |')
    failures = []
    failures << "README settings table missing tab(s): #{missing.join(', ')}" unless missing.empty?
    failures << 'README settings table still documents stale General tab instead of Control' if stale_general
    failures
  end

  def large_local_artifact_warnings
    roots = %w[releases build outputs].map { |name| File.join(PROJECT_ROOT, name) }
    paths = roots.flat_map { |root| Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH) }
    large_paths = paths.select { |path| File.file?(path) && File.size(path) >= 50 * 1024 * 1024 }
    return [] if large_paths.empty?

    ["Large local generated artifact(s) present: #{large_paths.map { |path| relative_path(path) }.join(', ')}"]
  end

  def relative_path(path)
    File.expand_path(path).delete_prefix("#{PROJECT_ROOT}/")
  end

  def check_saneui_guardrails
    print 'Checking SaneUI guardrails... '

    unless File.exist?(File.expand_path('../../infra/SaneProcess/scripts/SaneMaster.rb', PROJECT_ROOT))
      @warnings << 'SaneUI guard skipped (maintainer-only check; SaneProcess infra not present)'
      puts '⚠️  skipped (standalone clone)'
      return
    end

    output, status = Open3.capture2e(SANEMASTER_CLI, 'saneui_guard', PROJECT_ROOT)
    lines = output.lines.map(&:strip).reject(&:empty?)
    if status.success?
      warning_lines = lines.select { |line| line.start_with?('- ') || line.start_with?('Warnings:') }
      unless warning_lines.empty?
        @warnings << "SaneUI guard warnings: #{warning_lines.join(' | ')}"
      end
      puts '✅ shared settings UI guard clean'
      return
    end

    @errors << "SaneUI guard failed: #{lines.join(' | ')}"
    puts '❌ shared settings UI drift'
  rescue StandardError => e
    @warnings << "SaneUI guard unavailable: #{e.class}: #{e.message}"
    puts '⚠️  unavailable'
  end

  def check_appcast_guardrails
    print 'Checking appcast guardrails... '

    unless File.exist?(APPCAST_XML)
      @warnings << "Appcast file not found at #{APPCAST_XML}"
      puts '⚠️  appcast.xml missing'
      return
    end

    content = File.read(APPCAST_XML)
    versions = content.scan(/sparkle:shortVersionString="(\d+\.\d+\.\d+)"/).flatten

    if versions.empty?
      @warnings << 'No sparkle:shortVersionString entries found in appcast.xml'
      puts '⚠️  no versions found'
      return
    end

    blocked_present = versions & BLOCKED_APPCAST_VERSIONS
    unless blocked_present.empty?
      @errors << "Blocked appcast version(s) present: #{blocked_present.join(', ')}"
      puts "❌ blocked versions present: #{blocked_present.join(', ')}"
      return
    end

    puts "✅ no blocked versions (#{BLOCKED_APPCAST_VERSIONS.join(', ')})"
  end

  def check_appcast_download_urls
    print 'Checking appcast download URLs... '

    unless File.exist?(APPCAST_XML)
      @warnings << "Appcast file not found at #{APPCAST_XML}"
      puts '⚠️  appcast.xml missing'
      return
    end

    content = File.read(APPCAST_XML)
    urls = content.scan(/<enclosure\s+url="([^"]+)"/).flatten.uniq

    if urls.empty?
      @warnings << "No appcast enclosure URLs found in #{APPCAST_XML}"
      puts '⚠️  no enclosure URLs found'
      return
    end

    failures = []
    warnings = []
    latest_url = urls.first
    urls.each_with_index do |url, index|
      response_code = url_status(
        url,
        attempts: index.zero? ? 3 : 1,
        connect_timeout: index.zero? ? '5' : '2',
        max_time: index.zero? ? '12' : '4'
      )
      next if response_code && response_code < 400

      message = "#{url} (#{response_code || 'error'})"
      if url == latest_url
        failures << message
      else
        warnings << message
      end
    end

    if failures.empty?
      puts "✅ #{urls.count} enclosure URLs reachable"
      warnings.each { |warning| @warnings << "Historical appcast enclosure could not be confirmed: #{warning}" }
    else
      failures.each { |failure| @errors << "Dead appcast enclosure URL: #{failure}" }
      puts "❌ #{failures.count} dead enclosure URL#{'s' unless failures.count == 1}"
    end
  end

  def check_migration_guardrails
    print 'Checking migration guardrails... '

    unless File.exist?(STATUS_BAR_POSITION_STORE_SWIFT) && STATUS_BAR_POSITION_TESTS.all? { |path| File.exist?(path) }
      @errors << 'Migration guardrail files missing (StatusBarPositionStore or split migration/recovery tests)'
      puts '❌ missing source/test file'
      return
    end

    source = File.read(STATUS_BAR_POSITION_STORE_SWIFT)
    tests = STATUS_BAR_POSITION_TESTS.map { |path| File.read(path) }.join("\n")
    failures = []

    stable_key_match = source.match(/stablePositionMigrationKey\s*=\s*"([^"]+)"/)
    unless stable_key_match
      failures << 'stablePositionMigrationKey constant not found in StatusBarPositionStore.swift'
      stable_key = nil
    else
      stable_key = stable_key_match[1]
    end

    unless source.match?(/if\s+shouldResetPositionsForKnownCorruption\(\)/)
      failures << 'migrateCorruptedPositionsIfNeeded must gate resets with shouldResetPositionsForKnownCorruption()'
    end

    unless source.match?(/static func shouldResetPositionsForKnownCorruption\(\)/)
      failures << 'shouldResetPositionsForKnownCorruption() predicate is missing from StatusBarPositionStore.swift'
    end

    if stable_key && !tests.include?(stable_key)
      failures << "Tests missing stable migration key '#{stable_key}' — migration key changes must be paired with regression tests"
    end

    legacy_keys = source.scan(/"SaneBar_PositionMigration_v\d+"/).map { |value| value.delete('"') }.uniq
    missing_legacy = legacy_keys.reject { |key| tests.include?(key) }
    failures << "Tests missing legacy migration keys: #{missing_legacy.join(', ')}" unless missing_legacy.empty?

    missing_titles = REQUIRED_MIGRATION_TEST_TITLES.reject { |title| tests.include?(title) }
    failures << "Missing required migration regression test titles: #{missing_titles.join(' | ')}" unless missing_titles.empty?

    missing_recovery_titles = REQUIRED_STATUS_RECOVERY_TEST_TITLES.reject { |title| tests.include?(title) }
    failures << "Missing required status-item recovery test titles: #{missing_recovery_titles.join(' | ')}" unless missing_recovery_titles.empty?

    if failures.empty?
      puts '✅ migration key changes are guarded by corruption + preservation tests'
    else
      failures.each { |failure| @errors << failure }
      puts "❌ #{failures.count} guardrail failure(s)"
    end
  end

  def check_test_mode_tooling_guardrails
    print 'Checking test-mode tooling guardrails... '

    script = File.expand_path('../../infra/SaneProcess/scripts/app_test_mode.sh', PROJECT_ROOT)
    unless File.exist?(script)
      @warnings << 'Test-mode tooling check skipped (maintainer-only check; SaneProcess infra not present)'
      puts '⚠️  skipped (standalone clone)'
      return
    end

    syntax_ok = system('bash', '-n', script, out: File::NULL, err: File::NULL)
    unless syntax_ok
      @errors << "Test-mode script has invalid shell syntax: #{script}"
      puts '❌ invalid shell syntax'
      return
    end

    list_out, list_status = Open3.capture2e(script, 'list')
    unless list_status.success?
      @errors << "Test-mode script failed to list apps: #{list_out.lines.last&.strip || 'unknown error'}"
      puts '❌ list command failed'
      return
    end

    listed_apps = list_out.lines.map(&:strip).reject(&:empty?)
    missing = EXPECTED_TEST_MODE_APPS - listed_apps
    extras = listed_apps - EXPECTED_TEST_MODE_APPS

    if missing.empty?
      extra_note = extras.empty? ? '' : " (+extra: #{extras.join(', ')})"
      puts "✅ list covers #{EXPECTED_TEST_MODE_APPS.count} apps#{extra_note}"
    else
      @errors << "Test-mode script missing app(s): #{missing.join(', ')}"
      puts "❌ missing: #{missing.join(', ')}"
    end
  end
end
