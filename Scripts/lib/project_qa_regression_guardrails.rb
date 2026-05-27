# frozen_string_literal: true

class ProjectQA
  private

  def check_recurring_regression_coverage_guardrails
    print 'Checking recurring-regression coverage guardrails... '

    failures = []
    RECURRING_REGRESSION_TEST_MARKERS.each do |relative_path, markers|
      path = File.join(PROJECT_ROOT, relative_path)
      unless File.exist?(path)
        failures << "Missing regression test file: #{relative_path}"
        next
      end

      content = regression_marker_content(relative_path)
      markers.each do |marker|
        failures << "Missing regression marker '#{marker}' in #{relative_path}" unless content.include?(marker)
      end
    end

    if failures.empty?
      puts "✅ #{RECURRING_REGRESSION_TEST_MARKERS.values.flatten.count} marker checks"
    else
      failures.each { |failure| @errors << failure }
      puts "❌ #{failures.count} missing marker(s)"
    end
  end

  def regression_marker_content(relative_path)
    paths = [File.join(PROJECT_ROOT, relative_path)]
    if relative_path.start_with?('Scripts/') && File.extname(relative_path) == '.rb'
      base = File.basename(relative_path, '.rb')
      paths.concat(Dir.glob(File.join(PROJECT_ROOT, 'Scripts', 'lib', "#{base}_*.rb")).sort)
    end
    paths.select { |path| File.exist?(path) }.map { |path| File.read(path) }.join("\n")
  end

  def check_release_cadence_guardrails
    print 'Checking release cadence guardrails... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1)'
      return
    end

    gh_available = system('command -v gh >/dev/null 2>&1')
    unless gh_available
      @warnings << 'Release cadence check skipped (gh not installed)'
      puts '⚠️  gh missing'
      return
    end

    releases_json, status = Open3.capture2e(
      'gh', 'release', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--limit', '2',
      '--json', 'tagName,publishedAt'
    )

    unless status.success?
      @warnings << 'Release cadence check skipped (failed to query GitHub releases)'
      puts '⚠️  gh query failed'
      return
    end

    releases = JSON.parse(releases_json) rescue []
    if releases.empty?
      @warnings << 'Release cadence check skipped (no releases returned from GitHub)'
      puts '⚠️  no release data'
      return
    end

    latest = releases.max_by { |release| Time.parse(release.fetch('publishedAt', Time.now.utc.iso8601)) }
    latest_time = Time.parse(latest.fetch('publishedAt'))
    hours_since_latest = ((Time.now.utc - latest_time) / 3600.0).round(1)

    if hours_since_latest < RELEASE_SOAK_HOURS
      details = "#{hours_since_latest}h since #{latest['tagName']} (<#{RELEASE_SOAK_HOURS}h)"
      approved, phrase = request_manual_override(
        gate: :release_cadence,
        summary: "Release cadence guard tripped (#{details})"
      )

      if approved
        @warnings << "Manual override approved for release cadence (#{details})"
        puts "⚠️  #{details} (manual approval)"
      else
        @errors << "Release cadence guard: #{details}. Manual approval phrase required: \"#{phrase}\"."
        puts "❌ #{details}"
      end
    else
      puts "✅ #{hours_since_latest}h since #{latest['tagName']}"
    end
  end

  def check_open_regression_guardrails
    print 'Checking open regression guardrails... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1)'
      return
    end

    gh_available = system('command -v gh >/dev/null 2>&1')
    unless gh_available
      @warnings << 'Open regression check skipped (gh not installed)'
      puts '⚠️  gh missing'
      return
    end

    issues_json, list_status = Open3.capture2e(
      'gh', 'issue', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--state', 'open',
      '--limit', '100',
      '--json', 'number,title,url,labels,createdAt,updatedAt,comments'
    )

    unless list_status.success?
      @warnings << 'Open regression check skipped (failed to query open issues)'
      puts '⚠️  gh query failed'
      return
    end

    issues = JSON.parse(issues_json) rescue []
    blocking = issues.select { |issue| open_issue_blocks_release?(issue) }
    classified_nonblocking = issues.select { |issue| release_nonblocking_disposition?(issue['labels']) }

    if blocking.empty?
      if classified_nonblocking.empty?
        puts '✅ no open release-blocking issues'
      else
        summary = classified_nonblocking.first(5).map { |issue| issue_release_disposition_summary(issue) }.join(', ')
        @warnings << "Open regression issue(s) classified non-blocking for release: #{summary}"
        puts "✅ no unclassified open release-blocking issues (classified: #{summary})"
      end
      return
    end

    summary = blocking.first(5).map { |issue| "##{issue['number']}" }.join(', ')
    approved, phrase = request_manual_override(
      gate: :open_regression_release,
      summary: "Open regression issue(s) detected (#{summary})"
    )

    if approved
      @warnings << "Manual override approved for open regression issue(s): #{summary}"
      puts "⚠️  open regression issues present (manual approval): #{summary}"
    else
      details = blocking.map { |issue| "##{issue['number']} #{issue['title']}" }.join(' | ')
      dispositions = (OPEN_RELEASE_NONBLOCKING_DISPOSITION_LABELS + OPEN_RELEASE_BLOCKING_DISPOSITION_LABELS).join(', ')
      @errors << "Open regression issue(s) block release: #{details}. Add a release disposition label if triaged (#{dispositions}) or use manual approval phrase: \"#{phrase}\"."
      puts "❌ blocking issue(s): #{summary}"
    end
  end

  def open_issue_blocks_release?(issue)
    return true if release_blocker_disposition?(issue['labels'])
    if patched_pending_has_newer_external_negative?(issue)
      return false if patched_pending_issue_addressed_by_pending_release?(issue)

      return true
    end
    return false if release_nonblocking_disposition?(issue['labels'])

    regression_like_title?(issue['title']) || release_blocking_issue_labels?(issue['labels'])
  end

  def patched_pending_issue_addressed_by_pending_release?(issue)
    labels = normalized_issue_label_names(issue['labels'])
    return false unless labels.include?('release:patched-pending')

    issue_number = issue['number'].to_s
    return false if issue_number.empty?

    evidence = open_regression_release_evidence_for_issue(issue_number)
    return false if evidence.empty?
    return false unless recent_open_regression_release_evidence?(evidence)
    return false unless OPEN_REGRESSION_ADDRESSING_PATTERNS.any? { |pattern| evidence.match?(pattern) }

    OPEN_REGRESSION_PROOF_PATTERNS.any? { |pattern| evidence.match?(pattern) }
  end

  def open_regression_release_evidence_for_issue(issue_number)
    issue_ref = /##{Regexp.escape(issue_number)}\b/
    open_regression_release_evidence_text
      .split(/\n(?=##\s|\z)/)
      .select { |section| section.match?(issue_ref) }
      .join("\n")
  end

  def open_regression_release_evidence_text
    chunks = []
    OPEN_REGRESSION_RELEASE_EVIDENCE_FILES.each do |path|
      chunks << File.read(path) if File.exist?(path)
    rescue StandardError
      next
    end
    chunks.join("\n")
  end

  def recent_open_regression_release_evidence?(text)
    cutoff = Date.today - OPEN_REGRESSION_RELEASE_EVIDENCE_TTL_DAYS
    text.scan(/\b20\d{2}-\d{2}-\d{2}\b/).any? do |date_string|
      Date.parse(date_string) >= cutoff
    rescue StandardError
      false
    end
  end

  def patched_pending_has_newer_external_negative?(issue)
    labels = normalized_issue_label_names(issue['labels'])
    return false unless labels.include?('release:patched-pending')

    comments = Array(issue['comments'])
    latest_trusted_patch = comments.map do |comment|
      association = comment['authorAssociation'].to_s.upcase
      body = comment['body'].to_s
      next unless trusted_issue_author_associations.include?(association)
      next unless body.match?(/fixed|patched|release|version|build/i)

      Time.parse(comment['createdAt'].to_s).utc
    rescue StandardError
      nil
    end.compact.max
    return false unless latest_trusted_patch

    comments.any? do |comment|
      association = comment['authorAssociation'].to_s.upcase
      next false if trusted_issue_author_associations.include?(association)
      next false unless reporter_negative_regression_text?(comment['body'])

      Time.parse(comment['createdAt'].to_s).utc > latest_trusted_patch
    rescue StandardError
      false
    end
  end

  def release_blocking_issue_labels?(labels)
    normalized_issue_label_names(labels).any? do |label|
      OPEN_RELEASE_BLOCKING_LABELS.include?(label) ||
        OPEN_RELEASE_BLOCKING_LABEL_PREFIXES.any? { |prefix| label.start_with?(prefix) }
    end
  end

  def release_blocker_disposition?(labels)
    (normalized_issue_label_names(labels) & OPEN_RELEASE_BLOCKING_DISPOSITION_LABELS).any?
  end

  def release_nonblocking_disposition?(labels)
    normalized = normalized_issue_label_names(labels)
    (normalized & OPEN_RELEASE_NONBLOCKING_DISPOSITION_LABELS).any? &&
      (normalized & OPEN_RELEASE_BLOCKING_DISPOSITION_LABELS).empty?
  end

  def release_nonblocking_disposition_label(labels)
    (normalized_issue_label_names(labels) & OPEN_RELEASE_NONBLOCKING_DISPOSITION_LABELS).first
  end

  def issue_release_disposition_summary(issue)
    label = release_nonblocking_disposition_label(issue['labels']) || 'release:unknown'
    "##{issue['number']}(#{label})"
  end

  def normalized_issue_label_names(labels)
    Array(labels).map do |label|
      name = label.is_a?(Hash) ? label['name'] : label
      normalized = name.to_s.strip.downcase
      normalized.empty? ? nil : normalized
    end.compact
  end

  def regression_like_title?(title)
    text = title.to_s.downcase
    patterns = [
      /reset/,
      /persist/,
      /disappear/,
      /appearance|tint|turns black|black bar|bar turns black/,
      /icons? gone/,
      /invisible|status items? invisible|menu ?bar icon|menubar icon/,
      /visible.*hidden|hidden.*visible/,
      /move.*visible|visible.*move/,
      /move.*hidden|hidden.*move/,
      /second menu bar/,
      /browse icons/,
      /focus jump|focus jumps|focus bug|focus/,
      /drag and drop/,
      /drag/,
      /build from source|can'?t build|cannot build|source build/,
      /check for updates|update direct to latest|app update|updater|update/,
      /cursor|mouse/,
      /cannot open/,
      /does not function|doesn't function|doesnt function/,
      /nothing seems to happen|nothing happens/,
      /won't show|wont show/,
      /not working/,
      /broke/,
      /fails?/
    ]
    patterns.any? { |pattern| text.match?(pattern) }
  end

  def reporter_confirmation?(comments)
    comments.any? do |comment|
      association = comment['authorAssociation'].to_s.upcase
      next false if trusted_issue_author_associations.include?(association)

      body = comment['body'].to_s
      reporter_confirmation_text?(body)
    end
  end

  def reporter_confirmation_text?(body)
    text = body.to_s.strip
    return false if text.empty?
    if text.match?(/not working|still broken|still not|does not work|doesn't work|doesnt work|fails?|issue persists|still seeing|same problem|still buggy/i)
      return false
    end

    text.match?(/fixed|works|it'?s working|working now|resolved|confirmed|looks good|thank you/i)
  end

  def reporter_negative_regression_text?(body)
    text = body.to_s.strip
    return false if text.empty?

    patterns = [
      /reopen(?:ing)?/i,
      /still (?:broken|failing|missing|not|reproduc|seeing)/i,
      /same (?:failure|bug|issue|problem|invisible-icon)/i,
      /reproduc(?:e|es|ed|ing|ible)/i,
      /fresh (?:trace|traces|diagnostics|log|logs)/i,
      /not resolved/i,
      /does(?:n'?t| not) (?:work|resolve)/i,
      /status-item windows are invalid/i,
      /scene-reconnection-loop|reconnection loop|reconnect loop/i,
      /turns? black|black bar|dark tint/i
    ]
    patterns.any? { |pattern| text.match?(pattern) }
  end

  def trusted_issue_author_associations
    %w[MEMBER OWNER COLLABORATOR]
  end

  def post_closure_negative_reporter_comments(comments, closed_at)
    closed_time = Time.parse(closed_at.to_s).utc
    Array(comments).select do |comment|
      association = comment['authorAssociation'].to_s.upcase
      next false if trusted_issue_author_associations.include?(association)

      created_at = comment['createdAt'].to_s
      next false if created_at.empty?

      Time.parse(created_at).utc > closed_time &&
        reporter_negative_regression_text?(comment['body'])
    rescue StandardError
      false
    end
  rescue StandardError
    []
  end

  def check_customer_facing_copy_guardrails
    puts 'Checking customer-facing copy guardrails...'
    files = [
      README,
      File.join(PROJECT_ROOT, 'docs', 'index.html'),
      File.join(PROJECT_ROOT, 'UI', 'Onboarding', 'WelcomeView.swift')
    ]
    blocked_phrases = [
      /works perfectly/i,
      /double-click any app/i,
      /any app to open/i,
      /drag apps between/i,
      /no data collected/i,
      /even if (it'?s|it is) invisible/i
    ]

    violations = files.flat_map do |path|
      next [] unless File.exist?(path)

      File.readlines(path).each_with_index.each_with_object([]) do |(line, index), matches|
        matches << "#{path.sub("#{PROJECT_ROOT}/", '')}:#{index + 1}" if blocked_phrases.any? { |pattern| line.match?(pattern) }
      end
    end

    if violations.empty?
      puts '✅ customer-facing copy avoids absolute/ambiguous release claims'
    else
      @errors << "Customer-facing copy contains absolute or tier-ambiguous claims: #{violations.join(', ')}"
      puts '❌ customer-facing copy guardrail failed'
    end
  end

  def closed_regression_confirmation_exemption_reason(comments)
    trusted_comments = comments.select do |comment|
      trusted_issue_author_associations.include?(comment['authorAssociation'].to_s.upcase)
    end
    closing_note = trusted_comments.reverse.map { |comment| comment['body'].to_s.strip }.find { |body| !body.empty? }.to_s
    return nil if closing_note.empty?

    return 'duplicate closure' if closing_note.match?(/duplicate of #\d+/i)
    return 'superseded closure' if closing_note.match?(/superseded by/i)

    settings_mismatch = closing_note.match?(/settings mismatch/i)
    missing_diagnostics = closing_note.match?(/never got the requested diagnostics|no fresh repro/i)
    return 'settings-mismatch closure' if settings_mismatch || missing_diagnostics

    nil
  end

  def check_regression_confirmation_guardrails
    print 'Checking regression close confirmation guardrails... '

    unless preflight_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1)'
      return
    end

    gh_available = system('command -v gh >/dev/null 2>&1')
    unless gh_available
      @warnings << 'Regression confirmation check skipped (gh not installed)'
      puts '⚠️  gh missing'
      return
    end

    cutoff_date = (Time.now.utc - (REGRESSION_CONFIRMATION_WINDOW_HOURS * 3600)).strftime('%Y-%m-%d')
    issues_json, list_status = Open3.capture2e(
      'gh', 'issue', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--state', 'closed',
      '--search', "closed:>=#{cutoff_date}",
      '--limit', '50',
      '--json', 'number,title,closedAt'
    )

    unless list_status.success?
      @warnings << 'Regression confirmation check skipped (failed to query closed issues)'
      puts '⚠️  gh query failed'
      return
    end

    issues = JSON.parse(issues_json) rescue []
    regression_issues = issues.select { |issue| regression_like_title?(issue['title']) }
    if regression_issues.empty?
      puts '✅ no recently closed regression-like issues'
      check_post_closure_regression_evidence_guardrails
      return
    end

    unconfirmed = []
    exempt = []
    regression_issues.each do |issue|
      details_json, details_status = Open3.capture2e(
        'gh', 'issue', 'view', issue['number'].to_s,
        '--repo', 'sane-apps/SaneBar',
        '--json', 'comments'
      )
      next unless details_status.success?

      comments = (JSON.parse(details_json)['comments'] rescue []) || []
      exemption_reason = closed_regression_confirmation_exemption_reason(comments)
      if exemption_reason
        exempt << "##{issue['number']} #{exemption_reason}"
        next
      end

      unconfirmed << issue['number'] unless reporter_confirmation?(comments)
    end

    if unconfirmed.empty?
      if exempt.empty?
        puts "✅ #{regression_issues.count} closed regression issue(s) have reporter confirmation"
      else
        puts "✅ #{regression_issues.count - exempt.count} closed regression issue(s) have reporter confirmation; #{exempt.count} exempt historical closure(s)"
      end
      check_post_closure_regression_evidence_guardrails
      return
    end

    details = "unconfirmed: #{unconfirmed.join(', ')}"
    approved, phrase = request_manual_override(
      gate: :unconfirmed_regression_close,
      summary: "Closed regression issue(s) without reporter confirmation (#{details})"
    )

    if approved
      @warnings << "Manual override approved for unconfirmed regression close(s): #{unconfirmed.join(', ')}"
      puts "⚠️  #{details} (manual approval)"
    else
      @errors << "Closed regression issue(s) without reporter confirmation: #{unconfirmed.join(', ')}. Manual approval phrase required: \"#{phrase}\"."
      puts "❌ #{details}"
    end

    check_post_closure_regression_evidence_guardrails
  end

  def check_post_closure_regression_evidence_guardrails
    cutoff_date = (Time.now.utc - (POST_CLOSE_REGRESSION_COMMENT_WINDOW_DAYS * 24 * 3600)).strftime('%Y-%m-%d')
    issues_json, list_status = Open3.capture2e(
      'gh', 'issue', 'list',
      '--repo', 'sane-apps/SaneBar',
      '--state', 'closed',
      '--search', "updated:>=#{cutoff_date}",
      '--limit', '100',
      '--json', 'number,title,closedAt,updatedAt,url,labels'
    )

    unless list_status.success?
      @warnings << 'Post-closure regression evidence check skipped (failed to query closed issues)'
      puts '⚠️  post-closure evidence query failed'
      return
    end

    issues = JSON.parse(issues_json) rescue []
    candidates = issues.select do |issue|
      next false unless regression_like_title?(issue['title'])
      closed_at = issue['closedAt'].to_s
      updated_at = issue['updatedAt'].to_s
      next false if closed_at.empty? || updated_at.empty?

      Time.parse(updated_at).utc > Time.parse(closed_at).utc
    rescue StandardError
      false
    end

    reopened_evidence = []
    classified_nonblocking = []
    candidates.each do |issue|
      details_json, details_status = Open3.capture2e(
        'gh', 'issue', 'view', issue['number'].to_s,
        '--repo', 'sane-apps/SaneBar',
        '--json', 'comments'
      )
      next unless details_status.success?

      comments = (JSON.parse(details_json)['comments'] rescue []) || []
      next if post_closure_negative_reporter_comments(comments, issue['closedAt']).empty?

      if release_nonblocking_disposition?(issue['labels'])
        classified_nonblocking << issue_release_disposition_summary(issue)
        next
      end

      reopened_evidence << issue['number']
    end

    if reopened_evidence.empty?
      if classified_nonblocking.empty?
        puts '✅ no closed regression issues with fresh negative reporter evidence'
      else
        @warnings << "Closed regression issue(s) with fresh negative evidence classified non-blocking for release: #{classified_nonblocking.join(', ')}"
        puts "✅ no unclassified closed regression issues with fresh negative reporter evidence (classified: #{classified_nonblocking.join(', ')})"
      end
      return
    end

    approved, phrase = request_manual_override(
      gate: :post_closure_regression_evidence,
      summary: "Closed regression issue(s) have fresh negative reporter evidence (#{reopened_evidence.join(', ')})"
    )

    if approved
      @warnings << "Manual override approved for post-closure regression evidence: #{reopened_evidence.join(', ')}"
      puts "⚠️  post-closure negative evidence: #{reopened_evidence.join(', ')} (manual approval)"
    else
      @errors << "Closed regression issue(s) have fresh negative reporter evidence: #{reopened_evidence.join(', ')}. Reopen/respond or use manual approval phrase: \"#{phrase}\"."
      puts "❌ post-closure negative evidence: #{reopened_evidence.join(', ')}"
    end
  end
end
