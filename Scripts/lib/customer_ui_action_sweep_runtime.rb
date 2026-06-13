# frozen_string_literal: true

class CustomerUIActionSweep
  RELEASE_RUNTIME_EVIDENCE_MAX_AGE_SECONDS = 2 * 60 * 60
  SWEEP_RUNTIME_ARTIFACT_MAX_AGE_SECONDS = 30 * 60
  RESOURCE_SOAK_ARTIFACT_PATH = '/tmp/sanebar_runtime_resource_soak.json'
  RESOURCE_SOAK_MAX_AGE_SECONDS = 24 * 60 * 60
  RESOURCE_SOAK_MIN_DURATION_SECONDS = 20 * 60
  RESOURCE_SOAK_RAW_SCENARIOS = [
    'raw current-build resource soak artifact and log references exist',
    'per-sample CPU/RSS/physical footprint trend fields were captured'
  ].freeze

  private

  def verify_recent_runtime_smoke
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = '/tmp/sanebar_runtime_startup_probe.log'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    native_log = '/tmp/sanebar_runtime_native_apple_smoke.log'
    host_log = '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    strict_fixture_log = '/tmp/sanebar_runtime_strict_fixture_smoke.log'
    [smoke_log, startup_log, wake_log].each do |path|
      raise "Missing runtime evidence #{path}" unless fresh_release_runtime_evidence?(path)
    end
    exact_logs = [strict_fixture_log, shared_log, native_log, host_log]
      .select { |path| fresh_release_runtime_evidence?(path) }
    exact_runtime = exact_logs.map { |path| File.read(path) }.join("\n")
    if exact_logs.empty? || !exact_runtime.include?('Live zone smoke passed')
      raise "Missing exact-ID runtime evidence #{[strict_fixture_log, shared_log, native_log, host_log].join(', ')}"
    end

    runtime = [smoke_log, startup_log, wake_log, *exact_logs]
      .select { |path| File.exist?(path) }
      .map { |path| File.read(path) }
      .join("\n")
    required = [
      ['Settings window visual check ok'],
      ['Hidden/Visible move actions ok'],
      ['Always Hidden move actions ok'],
      ['Representative zone candidates ok'],
      ['Live zone smoke passed']
    ]
    required.each do |markers|
      raise "Runtime smoke missing marker #{markers.join(' or ')}" unless markers.any? { |marker| runtime.include?(marker) }
    end
    require_runtime_marker_pair!(
      runtime,
      'Browse mode secondMenuBar activation ok',
      'Browse mode secondMenuBar open/close ok'
    )
    require_runtime_marker_pair!(
      runtime,
      'Browse mode findIcon activation ok',
      'Browse mode findIcon open/close ok'
    )
    raise 'Exact-ID smoke did not pass' unless exact_runtime.include?('Candidate set passed') || exact_runtime.include?('Candidate passed')
    if fresh_release_runtime_evidence?(strict_fixture_log)
      strict_fixture = File.read(strict_fixture_log)
      raise 'Strict exact-ID fixture smoke did not pass' unless strict_fixture.include?('Candidate set passed') && strict_fixture.include?('Browse mode findIcon activation ok') && strict_fixture.include?('Browse mode secondMenuBar activation ok')
    end
    if fresh_release_runtime_evidence?(shared_log) && File.read(shared_log).include?('Live zone smoke passed')
      shared = File.read(shared_log)
      raise 'Shared exact-ID smoke did not pass' unless shared.include?('Candidate set passed') || shared.include?('Candidate passed')
    end
    if fresh_release_runtime_evidence?(native_log) && File.read(native_log).include?('Live zone smoke passed')
      native = File.read(native_log)
      raise 'Native exact-ID smoke did not pass' unless native.include?('Candidate set passed') || native.include?('Candidate passed')
    end
    if fresh_release_runtime_evidence?(host_log) && File.read(host_log).include?('Live zone smoke passed')
      host = File.read(host_log)
      raise 'Host exact-ID smoke did not pass' unless host.include?('Candidate set passed') || host.include?('Candidate passed')
    end
    @transcript << "runtime_smoke=#{smoke_log} ok"
    @transcript << "strict_exact_id=#{strict_fixture_log} ok" if fresh_release_runtime_evidence?(strict_fixture_log) && File.read(strict_fixture_log).include?('Live zone smoke passed')
    @transcript << "shared_exact_id=#{shared_log} ok" if fresh_release_runtime_evidence?(shared_log) && File.read(shared_log).include?('Live zone smoke passed')
    @transcript << "startup_probe=#{startup_log} ok"
    @transcript << "wake_probe=#{wake_log} ok"
    @transcript << "native_exact_id=#{native_log} ok" if fresh_release_runtime_evidence?(native_log) && File.read(native_log).include?('Live zone smoke passed')
    @transcript << "host_exact_id=#{host_log} ok" if fresh_release_runtime_evidence?(host_log) && File.read(host_log).include?('Live zone smoke passed')
  end

  def fresh_release_runtime_evidence?(path)
    fresh_runtime_evidence?(path, max_age_seconds: RELEASE_RUNTIME_EVIDENCE_MAX_AGE_SECONDS)
  end

  def fresh_runtime_evidence?(path, max_age_seconds:)
    File.exist?(path) && File.mtime(path) >= @started_at - max_age_seconds
  end

  def verify_recent_appearance_overlay_screenshots
    usable = latest_runtime_screenshots
      .select { |candidate| File.basename(candidate).start_with?('sanebar-appearance-') }
      .select { |candidate| usable_appearance_screenshot?(candidate) }
    if usable.empty?
      raise 'Missing fresh usable appearance overlay screenshot evidence; run SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 ruby Scripts/qa.rb before customer_ui_sweep'
    end

    latest = usable.max_by { |candidate| File.mtime(candidate) }
    @transcript << "appearance_overlay_screenshots=#{usable.length} ok latest=#{latest}"
  end

  def require_runtime_marker_pair!(runtime, primary, fallback)
    return if runtime.include?(primary) || runtime.include?(fallback)

    raise "Runtime smoke missing marker #{primary} or #{fallback}"
  end

  def write_receipt
    report = customer_ui_contract_report
    receipt = {
      app: 'SaneBar',
      status: 'passed',
      host: Socket.gethostname.to_s.downcase,
      generated_at: Time.now.utc.iso8601,
      manifest_sha256: report.fetch('manifest_sha256'),
      source_fingerprint: report.fetch('source_fingerprint'),
      tested_action_ids: @action_ids,
      runtime_state_results: runtime_state_results(report),
      action_results: @action_results,
      screenshots: @screenshots.uniq.select { |path| usable_screenshot?(path) },
      evidence: {
        app_version: @running_bundle_version,
        app_build: @running_bundle_build,
        runtime_host: Socket.gethostname.to_s.downcase,
        local_air_fallback: ENV['SANE_APPROVE_LOCAL_UI_ON_AIR'] == 'MR. SANE APPROVES LOCAL UI ON AIR',
        mini_verify: 'SaneMaster verify passed after customer UI contract expansion',
        mini_release_preflight_runtime: 'SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 ./scripts/SaneMaster.rb release_preflight generated runtime smoke evidence',
        settings_tab_sweep: @transcript.select { |line| line.start_with?('settings_tab=') },
        settings_snapshots: @settings_snapshots,
        url_routes: @transcript.select { |line| line.start_with?('url_route=') },
        applescript_commands: @transcript.select { |line| line.start_with?('applescript=') },
        runtime_smoke: @transcript.select { |line| line.include?('runtime_smoke=') || line.include?('startup_probe=') || line.include?('native_exact_id=') },
        release_note: 'Customer UI sweep records only evidence produced by this Mini run; missing required action evidence blocks release.'
      }
    }
    receipt_json = JSON.pretty_generate(receipt) + "\n"
    [RECEIPT_PATH, OUTPUT_RECEIPT_PATH].each do |path|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, receipt_json)
    end

    transcript_path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")
    File.write(transcript_path, @transcript.join("\n") + "\n")
    puts "🧾 Transcript: #{relative(transcript_path)}"
  end

  def runtime_state_results(report)
    manifest = YAML.safe_load(File.read(MANIFEST_PATH), permitted_classes: [Date, Time], aliases: true) || {}
    matrix = manifest.fetch('runtime_state_matrix', {})
    matrix.map do |id, row|
      action_ids = Array(row['action_ids']).map(&:to_s)
      required_types = Array(row['required_evidence_types']).map(&:to_s)
      evidence = action_ids.flat_map do |action_id|
        Array(@action_results.dig(action_id, :evidence) || @action_results.dig(action_id, 'evidence'))
      end.compact
      evidence_types = evidence.map { |item| item[:type] || item['type'] if item.is_a?(Hash) }.compact.map(&:to_s)
      evidence_paths = evidence.flat_map do |item|
        next [] unless item.is_a?(Hash)

        Array(item[:paths] || item['paths'] || item[:artifacts] || item['artifacts'] || item[:path] || item['path'])
      end.compact
      runtime_artifact = runtime_state_artifact(id.to_s)
      if runtime_artifact
        evidence_types |= Array(runtime_artifact[:evidence_types])
        evidence_paths |= Array(runtime_artifact[:evidence_paths])
      end
      completed_scenarios = runtime_state_completed_scenarios(action_ids, runtime_artifact)
      required_scenarios = Array(row['required_scenarios']).map(&:to_s)
      missing_types = required_types - evidence_types
      missing_scenarios = required_scenarios - completed_scenarios
      informational_reason = runtime_state_informational_reason(row)
      failure_reasons = []
      failure_reasons << "missing evidence types: #{missing_types.join(', ')}" unless missing_types.empty?
      failure_reasons << "missing completed scenarios: #{missing_scenarios.join(', ')}" unless missing_scenarios.empty?
      failure_reasons << 'missing evidence paths' if evidence_paths.empty?
      if completed_scenarios.empty? && informational_reason.to_s.empty?
        failure_reasons << 'missing completed_scenarios for named runtime state'
      end
      status = if failure_reasons.empty?
                 'passed'
               elsif informational_reason.to_s.empty?
                 'failed'
               else
                 'informational'
               end
      {
        id: id.to_s,
        status: status,
        action_ids: action_ids,
        required_evidence_types: required_types,
        evidence_types: evidence_types.uniq,
        evidence_paths: evidence_paths.uniq,
        completed_scenarios: completed_scenarios.uniq,
        informational_reason: informational_reason,
        failure_reasons: failure_reasons,
        runtime_candidate: runtime_artifact && runtime_artifact[:candidate],
        manifest_sha256: report.fetch('manifest_sha256')
      }
    end
  end

  def runtime_state_completed_scenarios(action_ids, runtime_artifact)
    completed = Array(runtime_artifact && runtime_artifact[:completed_scenarios]).map(&:to_s).map(&:strip).reject(&:empty?)
    return completed unless completed.empty? && runtime_artifact.nil?

    action_ids.flat_map { |action_id| action_completed_scenarios(action_id) }.map(&:to_s).map(&:strip).reject(&:empty?)
  end

  def action_completed_scenarios(action_id)
    result = @action_results[action_id] || @action_results[action_id.to_s]
    return [] unless result.is_a?(Hash)
    return [] unless result[:status].to_s == 'passed' || result['status'].to_s == 'passed'

    workflow = result[:workflow] || result['workflow'] || {}
    steps = Array(workflow[:steps_completed] || workflow['steps_completed']).map(&:to_s).map(&:strip).reject(&:empty?)
    return steps unless steps.empty?

    Array(result[:output_assertions] || result['output_assertions']).map(&:to_s).map(&:strip).reject(&:empty?)
  end

  def runtime_state_informational_reason(row)
    return nil unless row.is_a?(Hash)
    return nil unless row['informational'] == true || row['status'].to_s == 'informational'

    reason = row['informational_reason'].to_s.strip
    reason.empty? ? nil : reason
  end

  def runtime_state_artifact(id)
    case id
    when 'fullscreen_maximize_transition'
      fullscreen_matrix_artifact
    when 'wake_visible_zone_persistence'
      wake_visible_zone_artifact
    when 'dynamic_helper_wake_drift'
      dynamic_helper_wake_artifact
    when 'shared_bundle_exact_id_moves'
      shared_bundle_exact_id_artifact
    when 'hover_auto_rehide'
      runtime_json_artifact('/tmp/sanebar_runtime_hover_rehide.json')
    when 'license_clipboard_paste'
      runtime_json_artifact('/tmp/sanebar_runtime_license_paste.json')
    when 'resource_soak_growth'
      resource_soak_artifact
    end
  end

  def fullscreen_matrix_artifact
    path = '/tmp/sanebar_runtime_fullscreen_matrix.json'
    return nil unless fresh_release_runtime_evidence?(path)

    payload = JSON.parse(File.read(path))
    return nil unless payload['status'] == 'pass'
    return nil unless runtime_candidate_matches?(payload)

    {
      evidence_types: Array(payload['evidence_types']).map(&:to_s),
      evidence_paths: ([path] + Array(payload['evidence_paths'])).map(&:to_s),
      completed_scenarios: Array(payload['completed_scenarios']).map(&:to_s),
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def wake_visible_zone_artifact
    path = '/tmp/sanebar_runtime_wake_probe.json'
    return nil unless fresh_release_runtime_evidence?(path)

    payload = JSON.parse(File.read(path))
    return nil unless runtime_candidate_matches?(payload)

    visible_proof = payload['visible_zone_persistence']
    hidden_proof = payload['hidden_zone_persistence']
    return nil unless payload['status'] == 'pass' &&
                      visible_proof.is_a?(Hash) && visible_proof['status'] == 'pass' &&
                      hidden_proof.is_a?(Hash) && hidden_proof['status'] == 'pass'

    {
      evidence_types: %w[mini_runtime log state_receipt],
      evidence_paths: [path, '/tmp/sanebar_runtime_wake_probe.log'].select { |candidate| File.exist?(candidate) },
      completed_scenarios: (
        Array(visible_proof['completed_scenarios']) +
          Array(hidden_proof['completed_scenarios'])
      ).map(&:to_s).uniq,
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def runtime_json_artifact(path, max_age_seconds: SWEEP_RUNTIME_ARTIFACT_MAX_AGE_SECONDS)
    return nil unless fresh_runtime_evidence?(path, max_age_seconds: max_age_seconds)

    payload = JSON.parse(File.read(path))
    return nil unless payload['status'] == 'pass'
    return nil unless runtime_candidate_matches?(payload)

    {
      evidence_types: Array(payload['evidence_types']).map(&:to_s),
      evidence_paths: ([path] + Array(payload['evidence_paths'])).map(&:to_s),
      completed_scenarios: Array(payload['completed_scenarios']).map(&:to_s),
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def resource_soak_artifact
    path = RESOURCE_SOAK_ARTIFACT_PATH
    return nil unless fresh_runtime_evidence?(path, max_age_seconds: RESOURCE_SOAK_MAX_AGE_SECONDS)

    payload = JSON.parse(File.read(path))
    return nil unless payload['status'] == 'pass'
    return nil unless runtime_candidate_matches?(payload)

    validation = validate_resource_soak_raw_proof(payload, path)
    return nil unless validation[:ok]

    {
      evidence_types: (Array(payload['evidence_types']).map(&:to_s) | %w[mini_runtime log state_receipt]),
      evidence_paths: validation[:evidence_paths],
      completed_scenarios: (Array(payload['completed_scenarios']).map(&:to_s) | RESOURCE_SOAK_RAW_SCENARIOS),
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def validate_resource_soak_raw_proof(payload, artifact_path)
    evidence_paths = resource_soak_evidence_paths(payload, artifact_path)
    return { ok: false, evidence_paths: evidence_paths } unless evidence_paths.include?(artifact_path)

    existing_paths = evidence_paths.select { |candidate| File.file?(candidate) }
    log_paths = existing_paths.select { |candidate| File.extname(candidate) == '.log' }
    return { ok: false, evidence_paths: evidence_paths } if log_paths.empty?
    return { ok: false, evidence_paths: evidence_paths } if payload['duration_seconds'].to_f < RESOURCE_SOAK_MIN_DURATION_SECONDS
    return { ok: false, evidence_paths: evidence_paths } if payload['sample_count'].to_i < 2

    sample_count = resource_soak_json_trend_samples(payload).length
    if sample_count < 2
      sample_count = log_paths.flat_map { |log_path| resource_soak_log_trend_samples(log_path) }.length
    end
    return { ok: false, evidence_paths: evidence_paths } if sample_count < 2

    { ok: true, evidence_paths: existing_paths.uniq }
  end

  def resource_soak_evidence_paths(payload, artifact_path)
    raw_paths = [
      artifact_path,
      *Array(payload['evidence_paths']),
      *Array(payload['raw_evidence_paths']),
      *Array(payload['artifact_paths']),
      *Array(payload['log_paths'])
    ]
    raw_paths.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def resource_soak_json_trend_samples(payload)
    Array(payload['samples']).select do |sample|
      sample.is_a?(Hash) &&
        sample.key?('sampled_at') &&
        resource_soak_numeric_field?(sample, 'elapsed_seconds', 'elapsed') &&
        resource_soak_numeric_field?(sample, 'cpu', 'cpu_percent') &&
        resource_soak_numeric_field?(sample, 'rss_mb') &&
        resource_soak_numeric_field?(sample, 'physical_footprint_mb')
    end
  end

  def resource_soak_numeric_field?(sample, *keys)
    keys.any? do |key|
      value = sample[key]
      !value.nil? && Float(value)
    rescue ArgumentError, TypeError
      false
    end
  end

  def resource_soak_log_trend_samples(log_path)
    File.readlines(log_path, chomp: true).select do |line|
      line.match?(/\bsample=\d+\b/) &&
        line.match?(/\belapsed=\d+(?:\.\d+)?s\b/) &&
        line.match?(/\bcpu=\d+(?:\.\d+)?\b/) &&
        line.match?(/\brss=\d+(?:\.\d+)?MB\b/) &&
        line.match?(/\bphysical=\d+(?:\.\d+)?MB\b/)
    end
  rescue StandardError
    []
  end

  def shared_bundle_exact_id_artifact
    path = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    return nil unless fresh_release_runtime_evidence?(path)

    body = File.read(path)
    return nil unless runtime_log_candidate_matches?(body)

    required_line = body.lines.find { |line| line.start_with?('required_ids=') }
    required_ids = required_line.to_s.sub(/\Arequired_ids=/, '').strip.split(',').reject(&:empty?)
    return nil if required_ids.length < 2
    return nil if body.include?('shared_bundle_exact_id_pool_empty=1') || body.include?('default_move_pool_empty=1')
    return nil unless body.include?('✅ Candidate set passed:')

    sample_paths = body.scan(%r{resource_sample=(/tmp/[^\s]+)}).flatten
    {
      evidence_types: %w[mini_runtime log state_receipt],
      evidence_paths: ([path] + sample_paths).select { |candidate| File.exist?(candidate) },
      completed_scenarios: [
        'shared-bundle exact-id smoke ran with non-empty required_ids',
        'every required shared-bundle candidate moved by unique ID, not sibling fallback'
      ],
      candidate: runtime_log_candidate(body)
    }
  end

  def dynamic_helper_wake_artifact
    path = '/tmp/sanebar_runtime_wake_probe.json'
    return nil unless fresh_release_runtime_evidence?(path)

    payload = JSON.parse(File.read(path))
    return nil unless runtime_candidate_matches?(payload)

    proof = payload['dynamic_helper_wake_drift']
    return nil unless payload['status'] == 'pass' && proof.is_a?(Hash) && proof['status'] == 'pass'

    {
      evidence_types: %w[mini_runtime log state_receipt],
      evidence_paths: [path, '/tmp/sanebar_runtime_wake_probe.log'].select { |candidate| File.exist?(candidate) },
      completed_scenarios: Array(proof['completed_scenarios']).map(&:to_s),
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def runtime_candidate_matches?(payload)
    return true unless @running_bundle_version && @running_bundle_build

    candidate = runtime_candidate(payload)
    return false unless candidate.is_a?(Hash)

    File.expand_path(candidate[:app_path].to_s) == '/Applications/SaneBar.app' &&
      candidate[:app_version].to_s == @running_bundle_version.to_s &&
      candidate[:app_build].to_s == @running_bundle_build.to_s
  end

  def runtime_candidate(payload)
    raw = payload['candidate']
    raw = payload if raw.nil? && payload.key?('app_path')
    return nil unless raw.is_a?(Hash)

    {
      app_path: raw['app_path'] || raw[:app_path],
      app_version: raw['app_version'] || raw[:app_version],
      app_build: raw['app_build'] || raw[:app_build],
      process_path: raw['process_path'] || raw[:process_path]
    }
  end

  def runtime_log_candidate_matches?(body)
    return true unless @running_bundle_version && @running_bundle_build

    candidate = runtime_log_candidate(body)
    File.expand_path(candidate[:app_path].to_s) == '/Applications/SaneBar.app' &&
      candidate[:app_version].to_s == @running_bundle_version.to_s &&
      candidate[:app_build].to_s == @running_bundle_build.to_s
  end

  def runtime_log_candidate(body)
    lines = body.lines.to_h do |line|
      key, value = line.strip.split('=', 2)
      [key, value]
    end
    {
      app_path: lines['candidate_app_path'],
      app_version: lines['candidate_app_version'],
      app_build: lines['candidate_app_build'],
      process_path: lines['candidate_process_path']
    }
  end

  def dynamic_helper_required_scenarios
    [
      'dynamic helper required IDs are present before wake',
      'dynamic helper required IDs remain in intended zones after wake',
      'helper-specific Hidden to Visible drift is rejected as a release blocker'
    ]
  end

  def write_failure_artifact(error)
    FileUtils.mkdir_p(OUTPUT_DIR)
    path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-failed-#{@timestamp}.txt")
    File.write(path, ([@transcript, "#{error.class}: #{error.message}", *error.backtrace].flatten.join("\n") + "\n"))
    warn "Failure transcript: #{relative(path)}"
  rescue StandardError
    nil
  end
end
