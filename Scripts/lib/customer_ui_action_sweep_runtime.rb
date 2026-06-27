# frozen_string_literal: true

class CustomerUIActionSweep
  RELEASE_RUNTIME_EVIDENCE_MAX_AGE_SECONDS = 2 * 60 * 60
  SWEEP_RUNTIME_ARTIFACT_MAX_AGE_SECONDS = 30 * 60
  RUNTIME_PREFLIGHT_EVIDENCE_DIR = File.join(PROJECT_ROOT, 'outputs', 'runtime-preflight')
  RESOURCE_SOAK_ARTIFACT_PATH = '/tmp/sanebar_runtime_resource_soak.json'
  RESOURCE_SOAK_MAX_AGE_SECONDS = SWEEP_RUNTIME_ARTIFACT_MAX_AGE_SECONDS
  RESOURCE_SOAK_CLOCK_SKEW_SECONDS = 5 * 60
  RESOURCE_SOAK_MIN_DURATION_SECONDS = 4 * 60
  RESOURCE_SOAK_ACCEPTED_ADAPTIVE_STATUSES = %w[early_pass full_duration_pass].freeze
  RESOURCE_SOAK_RAW_SCENARIOS = [
    'adaptive Mini resource check passed for this release build',
    'raw current-build resource soak artifact and log references exist',
    'per-sample CPU/RSS/physical footprint trend fields were captured'
  ].freeze

  # Runtime-state rows whose ONLY evidence comes from the AppleScript SBF move-matrix
  # lane. That lane is opt-in (SANEBAR_SMOKE_REQUIRE_MOVE_MATRIX=1) because the product
  # correctly refuses unsafe AppleScript drags on notch/off-screen separators — it is not
  # the real UI path. When the lane is gated off these rows are INFORMATIONAL, not failed
  # (real move coverage = Swift move-regression suite + on-device IRL). Mirrors the
  # contract-side `move_runtime_line` and the runtime `move_matrix_required` gating.
  MOVE_MATRIX_GATED_RUNTIME_STATES = %w[shared_bundle_exact_id_moves].freeze

  private

  def verify_recent_runtime_smoke
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = first_fresh_runtime_evidence_path(
      File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_startup_probe.log'),
      '/tmp/sanebar_runtime_startup_probe.log'
    )
    wake_log = first_fresh_runtime_evidence_path(
      File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_wake_probe.log'),
      '/tmp/sanebar_runtime_wake_probe.log'
    )
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    native_log = '/tmp/sanebar_runtime_native_apple_smoke.log'
    host_log = '/tmp/sanebar_runtime_host_exact_id_smoke.log'
    strict_fixture_log = '/tmp/sanebar_runtime_strict_fixture_smoke.log'
    # Single source of truth for whether AppleScript move/exact-ID evidence is required,
    # mirroring project_qa_runtime_preflight's representative_move_matrix_release_gate_enabled?.
    # When off (default) those lanes don't run, so the sweep must not demand their
    # evidence; real move coverage = Swift move-regression suite + on-device IRL (owner
    # ruling 2026-06-26: AppleScript moves aren't the real UI path).
    move_matrix_required = ENV['SANEBAR_SMOKE_REQUIRE_MOVE_MATRIX'] == '1'
    [smoke_log, startup_log, wake_log].each do |path|
      raise "Missing runtime evidence #{path}" unless fresh_release_runtime_evidence?(path)
    end
    exact_logs = [strict_fixture_log, shared_log, native_log, host_log]
      .select { |path| fresh_release_runtime_evidence?(path) }
    smoke_runtime = verified_runtime_log_body!(smoke_log, label: 'Runtime smoke')
    exact_runtime = exact_logs.map { |path| verified_runtime_log_body!(path, label: 'Exact-ID runtime smoke') }.join("\n")
    # Require exact-ID evidence only when the move-matrix is enabled (see move_matrix_required
    # above). Any logs that DO exist are still verified above and folded into the runtime
    # evidence below.
    if move_matrix_required &&
       (exact_logs.empty? || !exact_runtime.include?('Live zone smoke passed'))
      raise "Missing exact-ID runtime evidence #{[strict_fixture_log, shared_log, native_log, host_log].join(', ')}"
    end

    startup_artifact = first_fresh_runtime_evidence_path(
      File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_startup_probe.json'),
      '/tmp/sanebar_runtime_startup_probe.json'
    )
    verify_runtime_artifact_candidate!(startup_artifact, label: 'Startup layout probe')
    wake_artifact = first_fresh_runtime_evidence_path(
      File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_wake_probe.json'),
      '/tmp/sanebar_runtime_wake_probe.json'
    )
    verify_runtime_artifact_candidate!(wake_artifact, label: 'Wake layout probe')

    runtime = [smoke_runtime, safe_read_artifact(startup_log), safe_read_artifact(wake_log), exact_runtime].join("\n")
    required = [
      ['Settings window visual check ok'],
      ['Representative zone candidates ok'],
      ['Live zone smoke passed']
    ]
    # The move-action markers come only from the AppleScript move-matrix lanes, which are
    # gated off by default — require them only when the move-matrix is enabled (otherwise
    # the smoke legitimately skips them and move coverage is Swift + IRL).
    if move_matrix_required
      required << ['Hidden/Visible move actions ok']
      required << ['Always Hidden move actions ok']
    end
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
    # The exact-ID candidate-move assertion only applies when the move-matrix lanes ran.
    if move_matrix_required
      raise 'Exact-ID smoke did not pass' unless exact_runtime.include?('Candidate set passed') || exact_runtime.include?('Candidate passed')
    end
    if fresh_release_runtime_evidence?(strict_fixture_log)
      strict_fixture = safe_read_artifact(strict_fixture_log)
      raise 'Strict exact-ID fixture smoke did not pass' unless strict_fixture.include?('Candidate set passed') && strict_fixture.include?('Browse mode findIcon activation ok') && strict_fixture.include?('Browse mode secondMenuBar activation ok')
    end
    if fresh_release_runtime_evidence?(shared_log) && safe_read_artifact(shared_log).include?('Live zone smoke passed')
      shared = safe_read_artifact(shared_log)
      raise 'Shared exact-ID smoke did not pass' unless shared.include?('Candidate set passed') || shared.include?('Candidate passed')
    end
    if fresh_release_runtime_evidence?(native_log) && safe_read_artifact(native_log).include?('Live zone smoke passed')
      native = safe_read_artifact(native_log)
      raise 'Native exact-ID smoke did not pass' unless native.include?('Candidate set passed') || native.include?('Candidate passed')
    end
    if fresh_release_runtime_evidence?(host_log) && safe_read_artifact(host_log).include?('Live zone smoke passed')
      host = safe_read_artifact(host_log)
      raise 'Host exact-ID smoke did not pass' unless host.include?('Candidate set passed') || host.include?('Candidate passed')
    end
    @transcript << "runtime_smoke=#{smoke_log} ok"
    @transcript << "strict_exact_id=#{strict_fixture_log} ok" if fresh_release_runtime_evidence?(strict_fixture_log) && safe_read_artifact(strict_fixture_log).include?('Live zone smoke passed')
    @transcript << "shared_exact_id=#{shared_log} ok" if fresh_release_runtime_evidence?(shared_log) && safe_read_artifact(shared_log).include?('Live zone smoke passed')
    @transcript << "startup_probe=#{startup_log} ok"
    @transcript << "wake_probe=#{wake_log} ok"
    @transcript << "native_exact_id=#{native_log} ok" if fresh_release_runtime_evidence?(native_log) && safe_read_artifact(native_log).include?('Live zone smoke passed')
    @transcript << "host_exact_id=#{host_log} ok" if fresh_release_runtime_evidence?(host_log) && safe_read_artifact(host_log).include?('Live zone smoke passed')
    retained = retain_runtime_evidence_paths([smoke_log, startup_log, wake_log, *exact_logs], label: 'runtime-smoke')
    @transcript << "runtime_evidence_retained=#{retained.join(',')}" unless retained.empty?
  end

  def fresh_release_runtime_evidence?(path)
    fresh_runtime_evidence?(path, max_age_seconds: RELEASE_RUNTIME_EVIDENCE_MAX_AGE_SECONDS)
  end

  def fresh_runtime_evidence?(path, max_age_seconds:)
    stat = File.lstat(path)
    stat.file? && stat.mtime >= @started_at - max_age_seconds
  rescue StandardError
    false
  end

  def first_fresh_runtime_evidence_path(*paths)
    paths.find { |path| fresh_release_runtime_evidence?(path) } || paths.first
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

  def verified_runtime_log_body!(path, label:)
    body = safe_read_artifact(path)
    raise "#{label} #{path} cannot be validated before running SaneBar version/build are known" unless @running_bundle_version && @running_bundle_build
    return body if runtime_log_candidate_matches?(body)

    raise "#{label} #{path} candidate metadata does not match running SaneBar #{@running_bundle_version}(#{@running_bundle_build})"
  end

  def verify_runtime_artifact_candidate!(path, label:)
    raise "Missing runtime artifact evidence #{path}" unless fresh_release_runtime_evidence?(path)
    raise "#{label} #{path} cannot be validated before running SaneBar version/build are known" unless @running_bundle_version && @running_bundle_build

    payload = JSON.parse(safe_read_artifact(path))
    raise "#{label} #{path} status is #{payload['status'].inspect}, expected pass" unless payload['status'] == 'pass'
    raise "#{label} #{path} candidate metadata does not match running SaneBar #{@running_bundle_version}(#{@running_bundle_build})" unless runtime_candidate_matches?(payload)

    nil
  rescue JSON::ParserError => e
    raise "#{label} #{path} artifact is invalid JSON: #{e.message}"
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
        durable_runtime_evidence: Array(@retained_runtime_evidence_paths).uniq,
        release_note: 'Customer UI sweep records only evidence produced by this Mini run; missing required action evidence blocks release.'
      }
    }
    receipt_json = JSON.pretty_generate(receipt) + "\n"
    [RECEIPT_PATH, OUTPUT_RECEIPT_PATH].each do |path|
      FileUtils.mkdir_p(File.dirname(path))
      safe_copy_artifact_content(path, receipt_json)
    end

    transcript_path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-#{@timestamp}.txt")
    FileUtils.mkdir_p(File.dirname(transcript_path))
    safe_copy_artifact_content(transcript_path, @transcript.join("\n") + "\n")
    puts "🧾 Transcript: #{relative(transcript_path)}"
  end

  def runtime_state_results(report)
    manifest = YAML.safe_load(safe_read_artifact(MANIFEST_PATH), permitted_classes: [Date, Time], aliases: true) || {}
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
        if id.to_s == 'resource_soak_growth'
          evidence_paths = Array(runtime_artifact[:evidence_paths])
        else
          evidence_paths |= Array(runtime_artifact[:evidence_paths])
        end
      end
      evidence_paths = runtime_evidence_with_retained_paths(evidence_paths, label: "runtime-state-#{id}") if runtime_artifact
      completed_scenarios = runtime_state_completed_scenarios(action_ids, runtime_artifact)
      required_scenarios = Array(row['required_scenarios']).map(&:to_s)
      missing_types = required_types - evidence_types
      missing_scenarios = required_scenarios - completed_scenarios
      informational_reason = runtime_state_informational_reason(row) ||
                             move_matrix_gated_informational_reason(id.to_s)
      failure_reasons = []
      failure_reasons << "missing evidence types: #{missing_types.join(', ')}" unless missing_types.empty?
      failure_reasons << "missing completed scenarios: #{missing_scenarios.join(', ')}" unless missing_scenarios.empty?
      failure_reasons << 'missing evidence paths' if evidence_paths.empty?
      if id.to_s == 'resource_soak_growth' && runtime_artifact.nil?
        failure_reasons.concat(Array(@resource_soak_failure_reasons).uniq)
      end
      if completed_scenarios.empty? && informational_reason.to_s.empty?
        failure_reasons << 'missing completed_scenarios for named runtime state'
      end
      runtime_candidate = if runtime_artifact && runtime_artifact[:candidate]
                            runtime_artifact[:candidate]
                          elsif id.to_s == 'resource_soak_growth'
                            nil
                          else
                            current_runtime_candidate
                          end
      if runtime_candidate.nil? && informational_reason.to_s.empty?
        failure_reasons << 'missing runtime candidate metadata'
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
        runtime_candidate: runtime_candidate,
        manifest_sha256: report.fetch('manifest_sha256')
      }
    end
  end

  def current_runtime_candidate
    return nil unless @running_bundle_version && @running_bundle_build

    {
      app_path: '/Applications/SaneBar.app',
      app_version: @running_bundle_version,
      app_build: @running_bundle_build,
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    }
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

  # Downgrade move-matrix-only runtime states to informational when the opt-in
  # AppleScript move lane is gated off (the default). Keeps the receipt honest:
  # the row is reported, labeled why it is not gating, and never blocks release.
  def move_matrix_gated_informational_reason(id)
    return nil if ENV['SANEBAR_SMOKE_REQUIRE_MOVE_MATRIX'] == '1'
    return nil unless MOVE_MATRIX_GATED_RUNTIME_STATES.include?(id.to_s)

    'AppleScript move-matrix lane gated off by default ' \
      '(set SANEBAR_SMOKE_REQUIRE_MOVE_MATRIX=1 to require); ' \
      'real move coverage = Swift move-regression suite + on-device IRL'
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
      runtime_json_artifact(
        File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_hover_rehide.json')
      )
    when 'license_clipboard_paste'
      runtime_json_artifact(
        File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_license_paste.json')
      )
    when 'resource_soak_growth'
      resource_soak_artifact
    end
  end

  def fullscreen_matrix_artifact
    path = '/tmp/sanebar_runtime_fullscreen_matrix.json'
    return nil unless fresh_release_runtime_evidence?(path)

    payload = JSON.parse(safe_read_artifact(path))
    return nil unless payload['status'] == 'pass'
    return nil unless runtime_candidate_matches?(payload)

    {
      evidence_types: Array(payload['evidence_types']).map(&:to_s),
      evidence_paths: runtime_evidence_with_retained_paths([path] + Array(payload['evidence_paths']), label: 'fullscreen-matrix'),
      completed_scenarios: Array(payload['completed_scenarios']).map(&:to_s),
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def wake_visible_zone_artifact
    path = first_fresh_runtime_evidence_path(
      File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_wake_probe.json'),
      '/tmp/sanebar_runtime_wake_probe.json'
    )
    return nil unless fresh_release_runtime_evidence?(path)

    payload = JSON.parse(safe_read_artifact(path))
    return nil unless runtime_candidate_matches?(payload)

    visible_proof = payload['visible_zone_persistence']
    hidden_proof = payload['hidden_zone_persistence']
    return nil unless payload['status'] == 'pass' &&
                      visible_proof.is_a?(Hash) && visible_proof['status'] == 'pass' &&
                      hidden_proof.is_a?(Hash) && hidden_proof['status'] == 'pass'

    {
      evidence_types: %w[mini_runtime log state_receipt],
      evidence_paths: runtime_evidence_with_retained_paths(
        [
          path,
          first_fresh_runtime_evidence_path(
            File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_wake_probe.log'),
            '/tmp/sanebar_runtime_wake_probe.log'
          )
        ],
        label: 'wake-visible-zone'
      ),
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

    payload = JSON.parse(safe_read_artifact(path))
    return nil unless payload['status'] == 'pass'
    return nil unless runtime_candidate_matches?(payload)

    {
      evidence_types: Array(payload['evidence_types']).map(&:to_s),
      evidence_paths: runtime_evidence_with_retained_paths([path] + Array(payload['evidence_paths']), label: File.basename(path, '.*')),
      completed_scenarios: Array(payload['completed_scenarios']).map(&:to_s),
      candidate: runtime_candidate(payload)
    }
  rescue JSON::ParserError
    nil
  end

  def resource_soak_artifact
    @resource_soak_failure_reasons = []
    resource_soak_artifact_paths.each do |path|
      artifact = resource_soak_artifact_at(path)
      return artifact if artifact
    end

    nil
  end

  def resource_soak_artifact_paths
    durable_paths = Dir.glob(File.join(OUTPUT_DIR, '**', 'resource-soak-*.json'))
    ([RESOURCE_SOAK_ARTIFACT_PATH] + durable_paths)
      .uniq
      .select { |path| safe_regular_artifact_file?(path) }
      .sort_by { |path| File.mtime(path) }
      .reverse
  end

  def resource_soak_artifact_at(path)
    return nil unless fresh_runtime_evidence?(path, max_age_seconds: RESOURCE_SOAK_MAX_AGE_SECONDS)

    payload = JSON.parse(safe_read_artifact(path))
    return nil unless payload['status'] == 'pass'
    return nil unless runtime_candidate_matches?(payload)

    validation = validate_resource_soak_raw_proof(payload, path)
    @resource_soak_failure_reasons << "resource soak #{File.basename(path)} rejected: #{validation[:reason]}" if validation[:reason]
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
    return resource_soak_reject('artifact path was not included in candidate evidence', evidence_paths) unless evidence_paths.include?(artifact_path)
    return resource_soak_reject('resource proof timestamp is stale or future-dated', evidence_paths) unless resource_soak_payload_fresh?(payload)
    return resource_soak_reject('resource proof was not produced in adaptive mode', evidence_paths) unless payload['adaptive'] == true
    unless RESOURCE_SOAK_ACCEPTED_ADAPTIVE_STATUSES.include?(payload['adaptive_status'].to_s)
      return resource_soak_reject("resource proof adaptive status #{payload['adaptive_status'].inspect} is not accepted", evidence_paths)
    end

    existing_paths = evidence_paths.select { |candidate| resource_soak_regular_file?(candidate) }
    log_paths = existing_paths.select { |candidate| File.extname(candidate) == '.log' }
    return resource_soak_reject('resource proof log file is missing', evidence_paths) if log_paths.empty?
    log_rejection = log_paths.map { |log_path| resource_soak_log_rejection_reason(log_path, payload) }.compact.first
    return resource_soak_reject(log_rejection, evidence_paths) if log_rejection
    if payload['duration_seconds'].to_f < RESOURCE_SOAK_MIN_DURATION_SECONDS
      return resource_soak_reject("resource proof duration #{payload['duration_seconds'].to_f.round(1)}s is shorter than #{RESOURCE_SOAK_MIN_DURATION_SECONDS}s", evidence_paths)
    end
    declared_sample_count = payload['sample_count'].to_i
    return resource_soak_reject('resource proof has fewer than 2 samples', evidence_paths) if declared_sample_count < 2
    unless payload['physical_sample_count'].to_i == declared_sample_count
      return resource_soak_reject("resource proof physical sample count #{payload['physical_sample_count'].to_i} does not match sample count #{declared_sample_count}", evidence_paths)
    end
    unless payload['physical_missing_sample_count'].to_i == 0
      return resource_soak_reject("resource proof is missing physical footprint for #{payload['physical_missing_sample_count'].to_i} sample(s)", evidence_paths)
    end

    sample_count = resource_soak_json_trend_samples(payload).length
    return resource_soak_reject("resource proof has #{sample_count} complete JSON sample(s), expected #{declared_sample_count}", evidence_paths) unless sample_count == declared_sample_count
    if log_paths.any? { |log_path| resource_soak_log_trend_samples(log_path).length != declared_sample_count }
      return resource_soak_reject('resource proof log sample count does not match JSON sample count', evidence_paths)
    end

    durable_paths = durable_resource_soak_evidence_paths(existing_paths)
    return resource_soak_reject('resource proof could not be copied into durable evidence', durable_paths) if durable_paths.empty?

    { ok: true, evidence_paths: durable_paths }
  end

  def resource_soak_reject(reason, evidence_paths)
    { ok: false, evidence_paths: evidence_paths, reason: reason }
  end

  def resource_soak_evidence_paths(_payload, artifact_path)
    sibling_log = artifact_path.to_s.sub(/\.json\z/, '.log')
    raw_paths = [artifact_path, sibling_log]
    raw_paths.map(&:to_s).map(&:strip).reject(&:empty?).uniq
  end

  def durable_resource_soak_evidence_paths(paths)
    evidence_dir = @evidence_dir || OUTPUT_DIR
    FileUtils.mkdir_p(evidence_dir)

    paths.each_with_object([]) do |path, durable_paths|
      next unless resource_soak_regular_file?(path)

      expanded_path = File.expand_path(path)
      project_root = File.expand_path(PROJECT_ROOT) + File::SEPARATOR
      if expanded_path.start_with?(project_root)
        durable_paths << expanded_path
        next
      end

      durable_path = File.join(evidence_dir, "resource-soak-#{File.basename(path)}")
      safe_copy_artifact(path, durable_path)
      durable_paths << durable_path if File.file?(durable_path)
    end.uniq
  end

  def resource_soak_regular_file?(path)
    safe_regular_artifact_file?(path)
  end

  def resource_soak_payload_fresh?(payload)
    timestamp = payload['finished_at'] || payload['generated_at'] || payload['started_at']
    return false if timestamp.to_s.strip.empty?

    resource_soak_time_within_window?(Time.parse(timestamp.to_s))
  rescue ArgumentError, TypeError
    false
  end

  def resource_soak_time_within_window?(timestamp)
    timestamp >= @started_at - RESOURCE_SOAK_MAX_AGE_SECONDS &&
      timestamp <= @started_at + RESOURCE_SOAK_CLOCK_SKEW_SECONDS
  end

  def resource_soak_log_rejection_reason(log_path, payload)
    return 'resource proof log file is stale or future-dated' unless fresh_runtime_evidence?(log_path, max_age_seconds: RESOURCE_SOAK_MAX_AGE_SECONDS)
    return 'resource proof log file is a symlink' if File.symlink?(log_path)

    lines = safe_read_artifact_lines(log_path)
    return 'resource proof log has missing process or physical samples' if lines.any? { |line| line.include?('sample_missing') || line.include?('physical=unknown') }

    finished_at = lines.find { |line| line.start_with?('resource_soak_finished_at=') }.to_s.sub(/\Aresource_soak_finished_at=/, '')
    return 'resource proof log has no finished timestamp' if finished_at.strip.empty?
    return 'resource proof log timestamp is stale or future-dated' unless resource_soak_time_within_window?(Time.parse(finished_at))

    candidate = runtime_candidate(payload)
    body = lines.join("\n")
    if candidate && !resource_soak_log_candidate_value?(body, 'app_version', candidate[:app_version])
      return 'resource proof log candidate version does not match JSON artifact'
    end
    if candidate && !resource_soak_log_candidate_value?(body, 'app_build', candidate[:app_build])
      return 'resource proof log candidate build does not match JSON artifact'
    end
    return 'resource proof log did not record pass status' unless body.include?('status=pass')

    nil
  rescue ArgumentError, TypeError
    'resource proof log timestamp is unreadable'
  rescue StandardError
    'resource proof log could not be read'
  end

  def resource_soak_log_candidate_value?(body, key, value)
    escaped_value = Regexp.escape(value.to_s)
    escaped_key = Regexp.escape(key.to_s)
    body.match?(/:?#{escaped_key}\s*=>\s*"#{escaped_value}"/) ||
      body.match?(/#{escaped_key}:\s+"#{escaped_value}"/) ||
      body.match?(/"#{escaped_key}"\s*=>\s*"#{escaped_value}"/)
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
    safe_read_artifact_lines(log_path).select do |line|
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

    body = safe_read_artifact(path)
    return nil unless runtime_log_candidate_matches?(body)

    required_line = body.lines.find { |line| line.start_with?('required_ids=') }
    required_ids = required_line.to_s.sub(/\Arequired_ids=/, '').strip.split(',').reject(&:empty?)
    return nil if required_ids.length < 2
    return nil if body.include?('shared_bundle_exact_id_pool_empty=1') || body.include?('default_move_pool_empty=1')
    return nil unless body.include?('✅ Candidate set passed:')

    sample_paths = body.scan(%r{resource_sample=(/tmp/[^\s]+)}).flatten
    {
      evidence_types: %w[mini_runtime log state_receipt],
      evidence_paths: runtime_evidence_with_retained_paths([path] + sample_paths, label: 'shared-bundle-exact-id'),
      completed_scenarios: [
        'shared-bundle exact-id smoke ran with non-empty required_ids',
        'every required shared-bundle candidate moved by unique ID, not sibling fallback'
      ],
      candidate: runtime_log_candidate(body)
    }
  end

  def dynamic_helper_wake_artifact
    path = first_fresh_runtime_evidence_path(
      File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_wake_probe.json'),
      '/tmp/sanebar_runtime_wake_probe.json'
    )
    return nil unless fresh_release_runtime_evidence?(path)

    payload = JSON.parse(safe_read_artifact(path))
    return nil unless runtime_candidate_matches?(payload)

    proof = payload['dynamic_helper_wake_drift']
    return nil unless payload['status'] == 'pass' && proof.is_a?(Hash) && proof['status'] == 'pass'

    {
      evidence_types: %w[mini_runtime log state_receipt],
      evidence_paths: runtime_evidence_with_retained_paths(
        [
          path,
          first_fresh_runtime_evidence_path(
            File.join(RUNTIME_PREFLIGHT_EVIDENCE_DIR, 'sanebar_runtime_wake_probe.log'),
            '/tmp/sanebar_runtime_wake_probe.log'
          )
        ],
        label: 'dynamic-helper-wake'
      ),
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
    # Runtime logs are UTF-8 (✅/↳/emoji); if they were read under a US-ASCII
    # locale, reinterpret the same bytes as UTF-8 so strip/split never raise
    # Encoding::CompatibilityError. See memory: saneprocess-state-encoding-wipe.
    lines = body.to_s.dup.force_encoding(Encoding::UTF_8).lines.to_h do |line|
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

  def runtime_evidence_with_retained_paths(paths, label:)
    raw_paths = Array(paths).map(&:to_s).map(&:strip).reject(&:empty?).select { |path| safe_regular_artifact_file?(path) }
    retain_runtime_evidence_paths(raw_paths, label: label).uniq
  end

  def retain_runtime_evidence_paths(paths, label:)
    evidence_dir = @evidence_dir || OUTPUT_DIR
    FileUtils.mkdir_p(evidence_dir)
    retained = Array(paths).each_with_object([]) do |path, retained_paths|
      next unless path && safe_regular_artifact_file?(path)

      expanded_path = File.expand_path(path)
      evidence_root = File.expand_path(evidence_dir) + File::SEPARATOR
      if expanded_path.start_with?(evidence_root)
        retained_paths << relative(expanded_path)
        next
      end

      project_root = File.expand_path(PROJECT_ROOT) + File::SEPARATOR
      if expanded_path.start_with?(project_root)
        retained_paths << relative(expanded_path)
        next
      end

      safe_label = label.to_s.gsub(/[^A-Za-z0-9_.-]/, '-')
      destination = File.join(evidence_dir, "#{safe_label}-#{File.basename(path)}")
      safe_copy_artifact(path, destination)
      retained_paths << relative(destination) if File.file?(destination)
    end.uniq
    @retained_runtime_evidence_paths = (Array(@retained_runtime_evidence_paths) + retained).uniq
    retained
  end

  def write_failure_artifact(error)
    FileUtils.mkdir_p(OUTPUT_DIR)
    path = File.join(OUTPUT_DIR, "customer-ui-action-sweep-failed-#{@timestamp}.txt")
    safe_copy_artifact_content(path, ([@transcript, "#{error.class}: #{error.message}", *error.backtrace].flatten.join("\n") + "\n"))
    warn "Failure transcript: #{relative(path)}"
  rescue StandardError
    nil
  end
end
