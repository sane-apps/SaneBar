#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative 'customer_ui_action_sweep'

class CustomerUIActionSweepTest < Minitest::Test
  def setup
    @sweep = CustomerUIActionSweep.new
  end

  def preserve_files(*paths)
    saved = paths.to_h do |path|
      if File.exist?(path)
        [path, { data: File.binread(path), atime: File.atime(path), mtime: File.mtime(path) }]
      else
        [path, nil]
      end
    end

    yield
  ensure
    saved&.each do |path, snapshot|
      if snapshot
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, snapshot[:data])
        File.utime(snapshot[:atime], snapshot[:mtime], path)
      else
        FileUtils.rm_f(path)
      end
    end
  end

  def startup_probe_log_path
    path = File.join(CustomerUIActionSweep.const_get(:PROJECT_ROOT), 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.log')
    FileUtils.mkdir_p(File.dirname(path))
    path
  end

  def startup_probe_artifact_path
    path = File.join(CustomerUIActionSweep.const_get(:PROJECT_ROOT), 'outputs', 'runtime-preflight', 'sanebar_runtime_startup_probe.json')
    FileUtils.mkdir_p(File.dirname(path))
    path
  end

  def write_startup_probe_artifact(path = startup_probe_artifact_path, mtime: Time.now)
    candidate = project_runtime_candidate_fixture
    File.write(
      path,
      JSON.pretty_generate(
        status: 'pass',
        app_path: '/Applications/SaneBar.app',
        candidate: candidate,
        runtime_provenance: {
          mini_runtime: true,
          host: 'mini',
          generated_at: mtime.utc.iso8601,
          app_path: '/Applications/SaneBar.app'
        },
        cases: [{ name: 'current-width backup restore' }]
      )
    )
    File.utime(mtime, mtime, path)
  end

  def wake_probe_log_path
    path = File.join(CustomerUIActionSweep.const_get(:PROJECT_ROOT), 'outputs', 'runtime-preflight', 'sanebar_runtime_wake_probe.log')
    FileUtils.mkdir_p(File.dirname(path))
    path
  end

  def wake_probe_artifact_path
    path = File.join(CustomerUIActionSweep.const_get(:PROJECT_ROOT), 'outputs', 'runtime-preflight', 'sanebar_runtime_wake_probe.json')
    FileUtils.mkdir_p(File.dirname(path))
    path
  end

  def write_wake_probe_artifact(path = wake_probe_artifact_path, mtime: Time.now)
    File.write(
      path,
      JSON.pretty_generate(
        status: 'pass',
        app_path: '/Applications/SaneBar.app',
        candidate: project_runtime_candidate_fixture,
        runtime_provenance: {
          mini_runtime: true,
          host: 'mini',
          generated_at: mtime.utc.iso8601,
          app_path: '/Applications/SaneBar.app'
        },
        cases: [{ name: 'wake visible/hidden persistence' }]
      )
    )
    File.utime(mtime, mtime, path)
  end

  def project_runtime_candidate_fixture
    {
      app_path: '/Applications/SaneBar.app',
      app_version: @sweep.send(:project_version, 'MARKETING_VERSION'),
      app_build: @sweep.send(:project_version, 'CURRENT_PROJECT_VERSION'),
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    }
  end

  def runtime_log_lines(*lines, candidate: project_runtime_candidate_fixture)
    [
      "candidate_app_path=#{candidate[:app_path]}",
      "candidate_app_version=#{candidate[:app_version]}",
      "candidate_app_build=#{candidate[:app_build]}",
      "candidate_process_path=#{candidate[:process_path]}",
      *lines
    ].join("\n")
  end

  def seed_running_bundle_from_project!
    @sweep.instance_variable_set(:@running_bundle_version, @sweep.send(:project_version, 'MARKETING_VERSION'))
    @sweep.instance_variable_set(:@running_bundle_build, @sweep.send(:project_version, 'CURRENT_PROJECT_VERSION'))
  end

  def runtime_candidate_fixture(version: '2.1.62', build: '2162')
    {
      app_path: '/Applications/SaneBar.app',
      app_version: version,
      app_build: build,
      process_path: '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    }
  end

  def with_manifest(content)
    old_path = CustomerUIActionSweep.const_get(:MANIFEST_PATH)
    Dir.mktmpdir('sanebar-customer-ui-manifest-') do |dir|
      manifest_path = File.join(dir, 'CustomerUIActions.yml')
      File.write(manifest_path, content)
      CustomerUIActionSweep.send(:remove_const, :MANIFEST_PATH)
      CustomerUIActionSweep.const_set(:MANIFEST_PATH, manifest_path)
      yield
    end
  ensure
    if defined?(old_path) && old_path
      CustomerUIActionSweep.send(:remove_const, :MANIFEST_PATH) if CustomerUIActionSweep.const_defined?(:MANIFEST_PATH, false)
      CustomerUIActionSweep.const_set(:MANIFEST_PATH, old_path)
    end
  end

  def test_full_runtime_completion_requires_real_mini_evidence
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['fixture']
    }

    error = assert_raises(RuntimeError) do
      @sweep.send(:assert_required_evidence!, 'control-settings-actions', action, [
        { type: 'fixture', detail: 'source_guard=settings_control ok checks=7' }
      ])
    end

    assert_includes error.message, 'full_runtime_completion requires strict Mini runtime evidence'
  end

  def test_mini_evidence_rejects_source_guard_placeholder_text
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['mini_click']
    }

    error = assert_raises(RuntimeError) do
      @sweep.send(:assert_required_evidence!, 'pro-basic-gating-actions', action, [
        { type: 'mini_click', detail: 'Pro/Basic gates verified through Mini settings sweep and source guards without performing purchase.' }
      ])
    end

    assert_includes error.message, 'evidence is a placeholder'
  end

  def test_mini_evidence_requires_runtime_provenance_prefix
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['mini_click']
    }

    error = assert_raises(RuntimeError) do
      @sweep.send(:assert_required_evidence!, 'browse-icons-search-navigation', action, [
        { type: 'mini_click', detail: 'Browse Icons opened and looked fine.' }
      ])
    end

    assert_includes error.message, 'lacks Mini runtime provenance'
  end

  def test_runtime_smoke_marker_counts_as_real_mini_click_evidence
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['mini_click']
    }

    @sweep.send(:assert_required_evidence!, 'icon-zone-move-reorder-always-hidden', action, [
      { type: 'mini_click', detail: '/tmp/sanebar_runtime_strict_fixture_smoke.log: ✅ Hidden/Always Hidden round-trip ok' }
    ])
  end

  def test_native_exact_id_runtime_marker_counts_as_real_mini_click_evidence
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['mini_click']
    }

    @sweep.send(:assert_required_evidence!, 'icon-zone-move-reorder-always-hidden', action, [
      { type: 'mini_click', detail: '/tmp/sanebar_runtime_native_apple_smoke.log: ✅ Hidden/Always Hidden round-trip ok' }
    ])
  end

  def test_durable_startup_probe_marker_counts_as_real_mini_runtime_evidence
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['mini_runtime']
    }
    startup_artifact = File.join(
      CustomerUIActionSweep.const_get(:RUNTIME_PREFLIGHT_DIR),
      'sanebar_runtime_startup_probe.json'
    )

    @sweep.send(:assert_required_evidence!, 'startup-wake-appearance-recovery', action, [
      { type: 'mini_runtime', detail: "#{startup_artifact}: Startup layout probe passed" }
    ])
  end

  def test_mini_runtime_rejects_arbitrary_project_output_runtime_detail
    action = {
      'required_proof_level' => 'full_runtime_completion',
      'required_evidence_types' => ['mini_runtime']
    }
    non_runtime_preflight_artifact = File.join(
      CustomerUIActionSweep.const_get(:OUTPUT_DIR),
      'sanebar_runtime_startup_probe.json'
    )

    error = assert_raises(RuntimeError) do
      @sweep.send(:assert_required_evidence!, 'startup-wake-appearance-recovery', action, [
        { type: 'mini_runtime', detail: "#{non_runtime_preflight_artifact}: Startup layout probe passed" }
      ])
    end

    assert_includes error.message, 'lacks Mini runtime provenance'
  end

  def test_startup_probe_runtime_provenance_payload_is_required
    path = File.join(
      CustomerUIActionSweep.const_get(:RUNTIME_PREFLIGHT_DIR),
      'sanebar_runtime_startup_probe.json'
    )
    valid_payload = {
      'app_path' => '/Applications/SaneBar.app',
      'candidate' => {
        'app_path' => '/Applications/SaneBar.app',
        'app_version' => @sweep.send(:project_version, 'MARKETING_VERSION'),
        'app_build' => @sweep.send(:project_version, 'CURRENT_PROJECT_VERSION')
      },
      'runtime_provenance' => {
        'mini_runtime' => true,
        'host' => 'mini',
        'generated_at' => Time.now.utc.iso8601,
        'app_path' => '/Applications/SaneBar.app'
      }
    }

    assert_nil @sweep.send(:startup_probe_runtime_provenance_error, valid_payload, path)
    assert_includes(
      @sweep.send(:startup_probe_runtime_provenance_error, valid_payload.merge('runtime_provenance' => {}), path),
      'does not mark mini_runtime=true'
    )
  end

  def test_appearance_actions_cannot_fall_back_to_settings_screenshot
    @sweep.define_singleton_method(:latest_runtime_screenshots) { [] }

    error = assert_raises(RuntimeError) do
      @sweep.send(:screenshot_for_action, 'appearance-customization-actions')
    end

    assert_includes error.message, 'no usable appearance overlay screenshot evidence'
  end

  def test_health_tab_warning_labels_are_release_blockers
    warnings = @sweep.send(
      :health_tab_warnings,
      'Health :: StatusAccessibilityOKMenu Bar GeometryNeeds CheckSaneBar ItemsDetachedLayout ModeLive'
    )

    assert_includes warnings, 'Needs Check'
    assert_includes warnings, 'Detached'
  end

  def test_health_tab_warning_triggers_repair_route_before_passing
    calls = 0
    repair_warnings = nil
    @sweep.define_singleton_method(:press_settings_tab) do |_index|
      calls += 1
      if calls == 1
        'Health :: StatusAccessibilityOKMenu Bar GeometryNeeds CheckSaneBar ItemsHidden by macOS'
      else
        'Health :: StatusAccessibilityOKMenu Bar GeometryGoodSaneBar ItemsReady'
      end
    end
    @sweep.define_singleton_method(:trigger_health_repair_route) do |warnings|
      repair_warnings = warnings
    end

    text = @sweep.send(:wait_for_clean_health_tab, 5, timeout: 2.0)

    assert_includes text, 'Ready'
    assert_equal ['Needs Check', 'Hidden by macOS'], repair_warnings
  end

  def test_health_tab_failure_records_runtime_snapshot
    @sweep.define_singleton_method(:press_settings_tab) do |_index|
      'Health :: StatusAccessibilityOKMenu Bar GeometryNeeds RepairSaneBar ItemsDetached'
    end
    @sweep.define_singleton_method(:trigger_health_repair_route) { |_warnings| nil }
    @sweep.define_singleton_method(:app_script) do |statement|
      statement == 'layout snapshot' ? '{"startupItemsValid":false}' : ''
    end

    error = assert_raises(RuntimeError) do
      @sweep.send(:wait_for_clean_health_tab, 5, timeout: 0.1)
    end

    assert_includes error.message, 'Needs Repair'
    transcript = @sweep.instance_variable_get(:@transcript).join("\n")
    assert_includes transcript, 'health_runtime_snapshot={"startupItemsValid":false}'
  end

  def test_snapshot_capture_stages_through_app_allowed_cache_path
    destination = "/tmp/sanebar-customer-ui-sweep-test-#{$$}.png"
    captured_statement = nil
    @sweep.define_singleton_method(:app_script) do |statement|
      captured_statement = statement
      staged_path = statement.match(/"([^"]+)"/)[1]
      FileUtils.mkdir_p(File.dirname(staged_path))
      File.write(staged_path, 'png-bytes')
      ''
    end

    @sweep.send(:capture_snapshot, 'settings window', destination)

    assert_equal 'png-bytes', File.read(destination)
    assert_includes captured_statement, 'capture settings window snapshot'
    assert_includes captured_statement, '/Library/Caches/com.sanebar.app/customer-ui-sweep/'
    refute_includes captured_statement, destination
  ensure
    FileUtils.rm_f(destination) if destination
  end

  def test_customer_ui_sweep_checks_runtime_smoke_before_expensive_ui_work
    source = File.read(File.join(CustomerUIActionSweep.const_get(:PROJECT_ROOT), 'scripts/customer_ui_action_sweep.rb'))
    run_start = source.index('  def run')
    run_end = source.index("\n  rescue StandardError => e", run_start)
    run_source = source[run_start...run_end]

    assert_operator run_source.index('verify_release_app_running!'), :<, run_source.index('verify_recent_runtime_smoke')
    assert_operator run_source.index('verify_recent_runtime_smoke'), :<, run_source.index('exercise_settings_tabs')
    assert_operator run_source.index('verify_recent_runtime_smoke'), :<, run_source.index('capture_runtime_visual_snapshots')
  end

  def test_runtime_smoke_accepts_move_only_exact_id_lanes_with_default_visual_proof
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = startup_probe_log_path
    startup_artifact = startup_probe_artifact_path
    wake_log = wake_probe_log_path
    wake_artifact = wake_probe_artifact_path
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, startup_artifact, wake_log, wake_artifact, shared_log) do
      Dir.mktmpdir do |evidence_dir|
        seed_running_bundle_from_project!
        @sweep.instance_variable_set(:@evidence_dir, evidence_dir)
        File.write(smoke_log, runtime_log_lines(
          'Settings window visual check ok',
          'Browse mode secondMenuBar open/close ok',
          'Browse mode findIcon open/close ok',
          'Live zone smoke passed'
        ))
        File.write(startup_log, 'Startup layout probe passed')
        write_startup_probe_artifact(startup_artifact)
        File.write(wake_log, 'Wake layout probe passed')
        write_wake_probe_artifact(wake_artifact)
        File.write(shared_log, runtime_log_lines(
          'Hidden/Visible move actions ok',
          'Always Hidden move actions ok',
          'Representative zone candidates ok',
          '✅ Candidate set passed: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A, com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B',
          '✅ Live zone smoke passed'
        ))

        @sweep.send(:verify_recent_runtime_smoke)

        transcript = @sweep.instance_variable_get(:@transcript)
        retained = @sweep.instance_variable_get(:@retained_runtime_evidence_paths)
        assert_includes transcript, "shared_exact_id=#{shared_log} ok"
        assert transcript.any? { |line| line.start_with?('runtime_evidence_retained=') }
        assert retained.any? { |path| File.basename(path) == 'runtime-smoke-sanebar_runtime_smoke.log' && File.file?(path) }
        assert retained.any? { |path| File.basename(path) == 'runtime-smoke-sanebar_runtime_shared_bundle_smoke.log' && File.file?(path) }
      end
    end
  end

  def test_runtime_smoke_accepts_same_release_session_evidence_beyond_thirty_minutes
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = startup_probe_log_path
    startup_artifact = startup_probe_artifact_path
    wake_log = wake_probe_log_path
    wake_artifact = wake_probe_artifact_path
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, startup_artifact, wake_log, wake_artifact, shared_log) do
      now = Time.now
      seed_running_bundle_from_project!
      @sweep.instance_variable_set(:@started_at, now)
      File.write(smoke_log, runtime_log_lines(
        'Settings window visual check ok',
        'Browse mode secondMenuBar open/close ok',
        'Browse mode findIcon open/close ok',
        'Live zone smoke passed'
      ))
      File.write(startup_log, 'Startup layout probe passed')
      write_startup_probe_artifact(startup_artifact, mtime: now - 45 * 60)
      File.write(wake_log, 'Wake layout probe passed')
      write_wake_probe_artifact(wake_artifact, mtime: now - 45 * 60)
      File.write(shared_log, runtime_log_lines(
        'Hidden/Visible move actions ok',
        'Always Hidden move actions ok',
        'Representative zone candidates ok',
        '✅ Candidate set passed: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A, com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-B',
        '✅ Live zone smoke passed'
      ))
      [smoke_log, startup_log, wake_log, wake_artifact, shared_log].each do |path|
        File.utime(now - 45 * 60, now - 45 * 60, path)
      end

      @sweep.send(:verify_recent_runtime_smoke)

      transcript = @sweep.instance_variable_get(:@transcript)
      assert_includes transcript, "runtime_smoke=#{smoke_log} ok"
      assert_includes transcript, "shared_exact_id=#{shared_log} ok"
      assert @sweep.send(:runtime_evidence_lines).any? { |line| line.include?('Candidate set passed') }
      assert_includes @sweep.send(:runtime_log_artifacts), shared_log
    end
  end

  def test_runtime_smoke_rejects_release_evidence_older_than_bounded_session_window
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = startup_probe_log_path
    startup_artifact = startup_probe_artifact_path
    wake_log = wake_probe_log_path
    wake_artifact = wake_probe_artifact_path
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, startup_artifact, wake_log, wake_artifact, shared_log) do
      now = Time.now
      seed_running_bundle_from_project!
      @sweep.instance_variable_set(:@started_at, now)
      write_startup_probe_artifact(startup_artifact, mtime: now - 3 * 60 * 60)
      write_wake_probe_artifact(wake_artifact, mtime: now - 3 * 60 * 60)
      [smoke_log, shared_log].each do |path|
        File.write(path, runtime_log_lines('Live zone smoke passed'))
        File.utime(now - 3 * 60 * 60, now - 3 * 60 * 60, path)
      end
      [startup_log, wake_log].each do |path|
        File.write(path, 'Live zone smoke passed')
        File.utime(now - 3 * 60 * 60, now - 3 * 60 * 60, path)
      end

      error = assert_raises(RuntimeError) do
        @sweep.send(:verify_recent_runtime_smoke)
      end

      assert_includes error.message, "Missing runtime evidence #{smoke_log}"
    end
  end

  def test_runtime_smoke_rejects_fresh_log_from_wrong_candidate
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = startup_probe_log_path
    startup_artifact = startup_probe_artifact_path
    wake_log = wake_probe_log_path
    wake_artifact = wake_probe_artifact_path
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, startup_artifact, wake_log, wake_artifact, shared_log) do
      seed_running_bundle_from_project!
      stale_candidate = project_runtime_candidate_fixture.merge(app_version: '0.0.1', app_build: '1')
      File.write(smoke_log, runtime_log_lines(
        'Settings window visual check ok',
        'Browse mode secondMenuBar open/close ok',
        'Browse mode findIcon open/close ok',
        'Live zone smoke passed',
        candidate: stale_candidate
      ))
      File.write(startup_log, 'Startup layout probe passed')
      write_startup_probe_artifact(startup_artifact)
      File.write(wake_log, 'Wake layout probe passed')
      write_wake_probe_artifact(wake_artifact)
      File.write(shared_log, runtime_log_lines(
        'Hidden/Visible move actions ok',
        'Always Hidden move actions ok',
        'Representative zone candidates ok',
        '✅ Candidate set passed: com.sanebar.sharedfixture::axid:com.sanebar.sharedfixture.SBF-A',
        '✅ Live zone smoke passed'
      ))

      error = assert_raises(RuntimeError) do
        @sweep.send(:verify_recent_runtime_smoke)
      end

      assert_includes error.message, 'candidate metadata does not match running SaneBar'
    end
  end

  def test_latest_runtime_screenshots_uses_release_session_window
    old_home = ENV['HOME']
    Dir.mktmpdir('sanebar-customer-ui-home-') do |home|
      ENV['HOME'] = home
      screenshot_dir = File.join(home, 'Desktop', 'Screenshots', 'SaneBar')
      FileUtils.mkdir_p(screenshot_dir)
      now = Time.now
      fresh = File.join(screenshot_dir, 'sanebar-appearance-top-strip-baseline-fresh.png')
      stale = File.join(screenshot_dir, 'sanebar-appearance-top-strip-baseline-stale.png')
      png = "\x89PNG\r\n\x1A\n".b + "\x00\x00\x00\rIHDR".b + [120, 30].pack('NN')
      File.binwrite(fresh, png)
      File.binwrite(stale, png)
      File.utime(now - 45 * 60, now - 45 * 60, fresh)
      File.utime(now - 3 * 60 * 60, now - 3 * 60 * 60, stale)
      @sweep.instance_variable_set(:@started_at, now)

      screenshots = @sweep.send(:latest_runtime_screenshots)

      assert_includes screenshots, fresh
      refute_includes screenshots, stale
    end
  ensure
    ENV['HOME'] = old_home
  end

  def test_runtime_state_results_read_artifact_backed_evidence_paths
    fullscreen_artifact = '/tmp/sanebar_runtime_fullscreen_matrix.json'
    startup_log = startup_probe_log_path
    preserve_files(fullscreen_artifact) do
    File.write(
      fullscreen_artifact,
      JSON.pretty_generate(
        status: 'pass',
        evidence_types: %w[mini_runtime screenshot log],
        evidence_paths: ['/tmp/sanebar-top-strip.png'],
        candidate: runtime_candidate_fixture,
        completed_scenarios: [
          'native fullscreen enter and exit',
          'hidden and visible icon zones persist across fullscreen Space transition',
          'maximized desktop window below the menu bar',
          'Dark appearance with Translucent Background enabled',
          'Reduce Transparency enabled',
          'customer-visible menu-bar top-strip shade comparison, not only internal overlay snapshots'
        ]
      )
    )
    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: "#{startup_log}: Startup layout probe passed", artifacts: [startup_log] },
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: ['/tmp/sanebar_runtime_wake_probe.log'] },
          { type: 'screenshot', detail: 'appearance screenshot', artifacts: ['outputs/customer-ui/appearance.png'] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime.log: Appearance tint pixels ok', artifacts: ['outputs/customer-ui/state.json'] },
          { type: 'log', detail: 'runtime log', artifacts: ['/tmp/sanebar_runtime.log'] }
        ]
      },
      'appearance-customization-actions' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime.log: Appearance tint pixels ok', artifacts: ['/tmp/sanebar_runtime.log'] },
          { type: 'screenshot', detail: 'appearance screenshot', artifacts: ['outputs/customer-ui/appearance.png'] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime.log: Appearance tint pixels ok', artifacts: ['outputs/customer-ui/state.json'] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    transition = rows.find { |row| row[:id] == 'fullscreen_maximize_transition' }

    assert_equal 'passed', transition[:status]
    assert_includes transition[:evidence_paths], '/tmp/sanebar_runtime.log'
    assert_includes transition[:evidence_paths], fullscreen_artifact
    assert_includes transition[:completed_scenarios], 'Reduce Transparency enabled'
    end
  end

  def test_runtime_state_results_read_durable_hover_and_license_probe_artifacts
    runtime_dir = CustomerUIActionSweep.const_get(:RUNTIME_PREFLIGHT_DIR)
    hover_json = File.join(runtime_dir, 'sanebar_runtime_hover_rehide.json')
    hover_log = File.join(runtime_dir, 'sanebar_runtime_hover_rehide.log')
    license_json = File.join(runtime_dir, 'sanebar_runtime_license_paste.json')
    license_log = File.join(runtime_dir, 'sanebar_runtime_license_paste.log')
    legacy_hover_json = '/tmp/sanebar_runtime_hover_rehide.json'
    legacy_license_json = '/tmp/sanebar_runtime_license_paste.json'

    preserve_files(hover_json, hover_log, license_json, license_log, legacy_hover_json, legacy_license_json) do
      FileUtils.mkdir_p(runtime_dir)
      FileUtils.rm_f(legacy_hover_json)
      FileUtils.rm_f(legacy_license_json)
      File.write(hover_log, "hover pass\n")
      File.write(license_log, "license pass\n")
      File.write(
        hover_json,
        JSON.pretty_generate(
          status: 'pass',
          evidence_types: %w[mini_click mini_runtime log state_receipt],
          evidence_paths: [hover_log],
          completed_scenarios: [
            'hover reveal opens hidden items',
            'leaving the reveal zone auto-rehides after the configured delay',
            'repeated hover cycles do not leave stale visible items'
          ],
          candidate: project_runtime_candidate_fixture
        )
      )
      File.write(
        license_json,
        JSON.pretty_generate(
          status: 'pass',
          evidence_types: %w[mini_click screenshot log state_receipt],
          evidence_paths: [license_log],
          completed_scenarios: [
            'license sheet accepts clipboard paste into the key field',
            'Activate uses the pasted value instead of an empty or stale field',
            'invalid test key shows a visible validation result without dismissing the sheet'
          ],
          candidate: project_runtime_candidate_fixture
        )
      )

      seed_running_bundle_from_project!
      with_manifest(<<~YAML) do
        runtime_state_matrix:
          hover_auto_rehide:
            action_ids: [control-settings-actions]
            required_evidence_types: [mini_click, mini_runtime, log, state_receipt]
            required_scenarios:
              - hover reveal opens hidden items
              - leaving the reveal zone auto-rehides after the configured delay
              - repeated hover cycles do not leave stale visible items
          license_clipboard_paste:
            action_ids: [license-about-support-actions]
            required_evidence_types: [mini_click, screenshot, log, state_receipt]
            required_scenarios:
              - license sheet accepts clipboard paste into the key field
              - Activate uses the pasted value instead of an empty or stale field
              - invalid test key shows a visible validation result without dismissing the sheet
      YAML
        rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
        hover = rows.find { |row| row[:id] == 'hover_auto_rehide' }
        license = rows.find { |row| row[:id] == 'license_clipboard_paste' }

        assert_equal 'passed', hover[:status]
        assert_includes hover[:evidence_paths], hover_json
        assert_includes hover[:evidence_paths], hover_log
        assert_equal 'passed', license[:status]
        assert_includes license[:evidence_paths], license_json
        assert_includes license[:evidence_paths], license_log
      end
    end
  end

  def test_runtime_state_results_reject_legacy_tmp_hover_and_license_probe_artifacts
    runtime_dir = CustomerUIActionSweep.const_get(:RUNTIME_PREFLIGHT_DIR)
    hover_json = File.join(runtime_dir, 'sanebar_runtime_hover_rehide.json')
    license_json = File.join(runtime_dir, 'sanebar_runtime_license_paste.json')
    legacy_hover_json = '/tmp/sanebar_runtime_hover_rehide.json'
    legacy_license_json = '/tmp/sanebar_runtime_license_paste.json'

    preserve_files(hover_json, license_json, legacy_hover_json, legacy_license_json) do
      FileUtils.rm_f(hover_json)
      FileUtils.rm_f(license_json)
      File.write(
        legacy_hover_json,
        JSON.pretty_generate(
          status: 'pass',
          evidence_types: %w[mini_click mini_runtime log state_receipt],
          evidence_paths: [legacy_hover_json],
          completed_scenarios: ['hover reveal opens hidden items'],
          candidate: project_runtime_candidate_fixture
        )
      )
      File.write(
        legacy_license_json,
        JSON.pretty_generate(
          status: 'pass',
          evidence_types: %w[mini_click screenshot log state_receipt],
          evidence_paths: [legacy_license_json],
          completed_scenarios: ['license sheet accepts clipboard paste into the key field'],
          candidate: project_runtime_candidate_fixture
        )
      )

      seed_running_bundle_from_project!
      with_manifest(<<~YAML) do
        runtime_state_matrix:
          hover_auto_rehide:
            action_ids: [control-settings-actions]
            required_evidence_types: [mini_click, mini_runtime, log, state_receipt]
            required_scenarios:
              - hover reveal opens hidden items
          license_clipboard_paste:
            action_ids: [license-about-support-actions]
            required_evidence_types: [mini_click, screenshot, log, state_receipt]
            required_scenarios:
              - license sheet accepts clipboard paste into the key field
      YAML
        rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
        hover = rows.find { |row| row[:id] == 'hover_auto_rehide' }
        license = rows.find { |row| row[:id] == 'license_clipboard_paste' }

        assert_equal 'failed', hover[:status]
        assert_equal 'failed', license[:status]
        assert_includes hover[:failure_reasons], 'missing evidence paths'
        assert_includes license[:failure_reasons], 'missing evidence paths'
      end
    end
  end

  def test_runtime_state_results_fail_without_named_fullscreen_scenarios
    fullscreen_artifact = '/tmp/sanebar_runtime_fullscreen_matrix.json'
    startup_log = startup_probe_log_path
    preserve_files(fullscreen_artifact) do
      FileUtils.rm_f(fullscreen_artifact)

    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: "#{startup_log}: Startup layout probe passed", artifacts: [startup_log] },
          { type: 'screenshot', detail: 'appearance screenshot', artifacts: ['outputs/customer-ui/appearance.png'] },
          { type: 'log', detail: 'runtime log', artifacts: ['/tmp/sanebar_runtime.log'] }
        ]
      },
      'appearance-customization-actions' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime.log: Appearance tint pixels ok', artifacts: ['/tmp/sanebar_runtime.log'] },
          { type: 'screenshot', detail: 'appearance screenshot', artifacts: ['outputs/customer-ui/appearance.png'] },
          { type: 'log', detail: 'runtime log', artifacts: ['/tmp/sanebar_runtime.log'] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    transition = rows.find { |row| row[:id] == 'fullscreen_maximize_transition' }

    assert_equal 'failed', transition[:status]
    assert_empty transition[:completed_scenarios]
    end
  end

  def test_runtime_state_results_rejects_stale_runtime_artifact_candidate
    fullscreen_artifact = '/tmp/sanebar_runtime_fullscreen_matrix.json'
    preserve_files(fullscreen_artifact) do
      File.write(
        fullscreen_artifact,
        JSON.pretty_generate(
          status: 'pass',
          candidate: {
            app_path: '/Applications/SaneBar.app',
            app_version: '2.1.61',
            app_build: '2161'
          },
          evidence_types: %w[mini_runtime screenshot log],
          evidence_paths: ['/tmp/sanebar-top-strip.png'],
          completed_scenarios: [
            'native fullscreen enter and exit',
            'hidden and visible icon zones persist across fullscreen Space transition',
            'maximized desktop window below the menu bar',
            'Dark appearance with Translucent Background enabled',
            'Reduce Transparency enabled',
            'customer-visible menu-bar top-strip shade comparison, not only internal overlay snapshots'
          ]
        )
      )
      @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
      @sweep.instance_variable_set(:@running_bundle_build, '2162')
      @sweep.instance_variable_set(:@action_results, {
        'startup-wake-appearance-recovery' => {
          evidence: [
            { type: 'mini_runtime', detail: '/tmp/sanebar_runtime.log: Startup layout probe passed', artifacts: ['/tmp/sanebar_runtime.log'] },
            { type: 'screenshot', detail: 'appearance screenshot', artifacts: ['outputs/customer-ui/appearance.png'] },
            { type: 'log', detail: 'runtime log', artifacts: ['/tmp/sanebar_runtime.log'] }
          ]
        },
        'appearance-customization-actions' => {
          evidence: [
            { type: 'mini_runtime', detail: '/tmp/sanebar_runtime.log: Appearance tint pixels ok', artifacts: ['/tmp/sanebar_runtime.log'] },
            { type: 'screenshot', detail: 'appearance screenshot', artifacts: ['outputs/customer-ui/appearance.png'] },
            { type: 'log', detail: 'runtime log', artifacts: ['/tmp/sanebar_runtime.log'] }
          ]
        }
      })

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      transition = rows.find { |row| row[:id] == 'fullscreen_maximize_transition' }

      assert_equal 'failed', transition[:status]
      assert_empty transition[:completed_scenarios]
    end
  end

  def test_runtime_state_results_include_wake_visible_zone_artifact
    wake_artifact = wake_probe_artifact_path
    wake_log = wake_probe_log_path
    preserve_files(wake_artifact, wake_log) do
    File.write(wake_log, 'Wake layout probe passed')
    File.write(
      wake_artifact,
      JSON.pretty_generate(
        status: 'pass',
        candidate: runtime_candidate_fixture,
        visible_zone_persistence: {
          status: 'pass',
          completed_scenarios: [
            'baseline visible icon-zone snapshot before display sleep',
            'fresh authoritative icon-zone snapshot at 1s after wake',
            'fresh authoritative icon-zone snapshot at 5s after wake',
            'fresh authoritative icon-zone snapshot at 15s after wake',
            'visible required IDs remain visible and are not moved into Hidden or Always Hidden'
          ]
        },
        hidden_zone_persistence: {
          status: 'pass',
          completed_scenarios: [
            'baseline hidden icon-zone snapshot before display sleep',
            'fresh authoritative icon-zone snapshot at 1s after wake',
            'fresh authoritative icon-zone snapshot at 5s after wake',
            'fresh authoritative icon-zone snapshot at 15s after wake',
            'hidden required IDs remain hidden and are not moved into Visible or Always Hidden'
          ]
        }
      )
    )
    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
          { type: 'screenshot', detail: 'wake screenshot', artifacts: ['outputs/customer-ui/wake.png'] },
          { type: 'log', detail: 'wake log', artifacts: [wake_log] }
        ]
      },
      'browse-icons-icon-context-actions' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
          { type: 'screenshot', detail: 'browse screenshot', artifacts: ['outputs/customer-ui/browse.png'] },
          { type: 'log', detail: 'wake log', artifacts: [wake_log] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    wake = rows.find { |row| row[:id] == 'wake_visible_zone_persistence' }

    assert_equal 'passed', wake[:status]
    assert_includes wake[:completed_scenarios], 'fresh authoritative icon-zone snapshot at 15s after wake'
    end
  end

  def test_runtime_state_results_include_dynamic_helper_wake_artifact
    wake_artifact = wake_probe_artifact_path
    wake_log = wake_probe_log_path
    preserve_files(wake_artifact, wake_log) do
    File.write(wake_log, 'Wake layout probe passed')
    File.write(
      wake_artifact,
      JSON.pretty_generate(
        status: 'pass',
        candidate: runtime_candidate_fixture,
        dynamic_helper_wake_drift: {
          status: 'pass',
          required_ids: ['com.sindresorhus.Lungo-setapp'],
          completed_scenarios: [
            'dynamic helper required IDs are present before wake',
            'dynamic helper required IDs remain in intended zones after wake',
            'helper-specific Hidden to Visible drift is rejected as a release blocker'
          ]
        }
      )
    )
    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
          { type: 'screenshot', detail: 'wake screenshot', artifacts: ['outputs/customer-ui/wake.png'] },
          { type: 'log', detail: 'wake log', artifacts: [wake_log] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime_wake_probe.log: helper wake proof', artifacts: [wake_artifact] }
        ]
      },
      'browse-icons-icon-context-actions' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
          { type: 'screenshot', detail: 'browse screenshot', artifacts: ['outputs/customer-ui/browse.png'] },
          { type: 'log', detail: 'wake log', artifacts: [wake_log] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime_wake_probe.log: helper wake proof', artifacts: [wake_artifact] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    helper = rows.find { |row| row[:id] == 'dynamic_helper_wake_drift' }

    assert_equal 'passed', helper[:status]
    assert_includes helper[:completed_scenarios], 'helper-specific Hidden to Visible drift is rejected as a release blocker'
    end
  end

  def test_runtime_state_results_do_not_claim_dynamic_helper_screenshot_from_json_only
    wake_artifact = wake_probe_artifact_path
    wake_log = wake_probe_log_path
    preserve_files(wake_artifact, wake_log) do
      File.write(wake_log, 'Wake layout probe passed')
      File.write(
        wake_artifact,
        JSON.pretty_generate(
          status: 'pass',
          dynamic_helper_wake_drift: {
            status: 'pass',
            completed_scenarios: [
              'dynamic helper required IDs are present before wake',
              'dynamic helper required IDs remain in intended zones after wake',
              'helper-specific Hidden to Visible drift is rejected as a release blocker'
            ]
          }
        )
      )
      @sweep.instance_variable_set(:@action_results, {
        'startup-wake-appearance-recovery' => {
          evidence: [
            { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
            { type: 'log', detail: 'wake log', artifacts: [wake_log] },
            { type: 'state_receipt', detail: '/tmp/sanebar_runtime_wake_probe.log: helper wake proof', artifacts: [wake_artifact] }
          ]
        },
        'browse-icons-icon-context-actions' => {
          evidence: [
            { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
            { type: 'log', detail: 'wake log', artifacts: [wake_log] },
            { type: 'state_receipt', detail: '/tmp/sanebar_runtime_wake_probe.log: helper wake proof', artifacts: [wake_artifact] }
          ]
        }
      })

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      helper = rows.find { |row| row[:id] == 'dynamic_helper_wake_drift' }

      assert_equal 'failed', helper[:status]
      refute_includes helper[:evidence_types], 'screenshot'
    end
  end

  def test_runtime_state_results_rejects_inferred_dynamic_helper_from_generic_hidden_wake_proof
    wake_artifact = wake_probe_artifact_path
    wake_log = wake_probe_log_path
    preserve_files(wake_artifact, wake_log) do
    File.write(wake_log, 'Wake layout probe passed')
    File.write(
      wake_artifact,
      JSON.pretty_generate(
        status: 'pass',
        hidden_zone_persistence: {
          status: 'pass',
          completed_scenarios: [
            'baseline hidden icon-zone snapshot before display sleep',
            'fresh authoritative icon-zone snapshot at 1s after wake',
            'fresh authoritative icon-zone snapshot at 5s after wake',
            'fresh authoritative icon-zone snapshot at 15s after wake',
            'hidden required IDs remain hidden and are not moved into Visible or Always Hidden'
          ],
          proofs: [
            {
              required_hidden_ids: ['com.sindresorhus.Lungo-setapp::statusItem:0'],
              completed_scenarios: ['hidden required IDs remain hidden and are not moved into Visible or Always Hidden']
            }
          ]
        }
      )
    )
    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
          { type: 'screenshot', detail: 'wake screenshot', artifacts: ['outputs/customer-ui/wake.png'] },
          { type: 'log', detail: 'wake log', artifacts: [wake_log] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime_wake_probe.log: helper wake proof', artifacts: [wake_artifact] }
        ]
      },
      'browse-icons-icon-context-actions' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_wake_probe.log: Wake layout probe passed', artifacts: [wake_log] },
          { type: 'screenshot', detail: 'browse screenshot', artifacts: ['outputs/customer-ui/browse.png'] },
          { type: 'log', detail: 'wake log', artifacts: [wake_log] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime_wake_probe.log: helper wake proof', artifacts: [wake_artifact] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    helper = rows.find { |row| row[:id] == 'dynamic_helper_wake_drift' }

    assert_equal 'failed', helper[:status]
    refute_includes helper[:completed_scenarios], 'helper-specific Hidden to Visible drift is rejected as a release blocker'
    end
  end

  def test_runtime_state_results_include_shared_bundle_exact_id_artifact
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(shared_log) do
    File.write(
      shared_log,
      [
        'required_ids=com.apple.controlcenter.wifi,com.apple.controlcenter.battery',
        'resource_sample=/tmp/sanebar_runtime_shared_bundle_resource_sample-try1.txt',
        '✅ Candidate set passed: com.apple.controlcenter.wifi, com.apple.controlcenter.battery'
      ].join("\n")
    )
    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_shared_bundle_smoke.log: shared bundle passed', artifacts: [shared_log] },
          { type: 'log', detail: 'shared bundle log', artifacts: [shared_log] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime_shared_bundle_smoke.log: exact IDs', artifacts: [shared_log] }
        ]
      },
      'browse-icons-icon-context-actions' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_shared_bundle_smoke.log: shared bundle passed', artifacts: [shared_log] },
          { type: 'log', detail: 'shared bundle log', artifacts: [shared_log] },
          { type: 'state_receipt', detail: '/tmp/sanebar_runtime_shared_bundle_smoke.log: exact IDs', artifacts: [shared_log] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    shared = rows.find { |row| row[:id] == 'shared_bundle_exact_id_moves' }

    assert_equal 'passed', shared[:status]
    assert_includes shared[:completed_scenarios], 'shared-bundle exact-id smoke ran with non-empty required_ids'
    end
  end

  def test_runtime_state_results_fail_named_state_without_completed_scenarios
    @sweep.instance_variable_set(:@action_results, {
      'onboarding-basic-pro-permission-actions' => {
        status: 'passed',
        evidence: [
          { type: 'mini_click', detail: 'settings_tab=license ok', artifacts: ['outputs/customer-ui/license-click.json'] },
          { type: 'screenshot', detail: 'license screenshot', artifacts: ['outputs/customer-ui/license.png'] }
        ]
      },
      'pro-basic-gating-actions' => {
        status: 'passed',
        evidence: [
          { type: 'mini_click', detail: 'settings_tab=control ok', artifacts: ['outputs/customer-ui/pro-click.json'] },
          { type: 'log', detail: 'pro log', artifacts: ['outputs/customer-ui/pro.log'] }
        ]
      },
      'license-about-support-actions' => {
        status: 'passed',
        evidence: [
          { type: 'mini_click', detail: 'settings_tab=about ok', artifacts: ['outputs/customer-ui/about-click.json'] },
          { type: 'log', detail: 'license log', artifacts: ['outputs/customer-ui/license.log'] }
        ]
      }
    })

    rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
    basic_pro = rows.find { |row| row[:id] == 'basic_pro_mode' }

    assert_equal 'failed', basic_pro[:status]
    assert_empty basic_pro[:completed_scenarios]
    assert_includes basic_pro[:failure_reasons], 'missing completed_scenarios for named runtime state'
  end

  def test_runtime_state_results_allows_explicit_informational_state_without_scenarios
    with_manifest(<<~YAML) do
      ---
      runtime_state_matrix:
        external_tracker_note:
          informational: true
          informational_reason: Recorded by the external tracker, not a release-blocking runtime state.
          action_ids: []
          required_evidence_types: []
    YAML
      @sweep.instance_variable_set(:@action_results, {})

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      info = rows.find { |row| row[:id] == 'external_tracker_note' }

      assert_equal 'informational', info[:status]
      assert_equal 'Recorded by the external tracker, not a release-blocking runtime state.', info[:informational_reason]
      assert_empty info[:completed_scenarios]
    end
  end

  def test_runtime_state_results_accept_resource_soak_same_day_candidate
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    Dir.mktmpdir do |evidence_dir|
      @sweep.instance_variable_set(:@evidence_dir, evidence_dir)
      preserve_files(soak_artifact, soak_log) do
        now = Time.now.utc
        unrelated_path = File.join(evidence_dir, 'unrelated-proof.txt')
        File.write(unrelated_path, 'this must not be copied into resource-soak evidence')
        File.write(
          soak_log,
          [
            "resource_soak_started_at=#{(now - 1260).iso8601}",
            'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"2.1.62", :app_build=>"2162", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
            'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
            'sample=2 elapsed=1260.0s cpu=0.1 rss=82.0MB physical=61.0MB',
            "resource_soak_finished_at=#{now.iso8601}",
            'status=pass'
          ].join("\n")
        )
        File.write(
          soak_artifact,
          JSON.pretty_generate(
            status: 'pass',
            started_at: (now - 1260).iso8601,
            finished_at: now.iso8601,
            duration_seconds: 1260.0,
            adaptive: true,
            adaptive_status: 'full_duration_pass',
            sample_count: 2,
            physical_sample_count: 2,
            physical_missing_sample_count: 0,
            avg_cpu: 0.15,
            peak_cpu: 0.2,
            avg_rss_mb: 81.0,
            peak_rss_mb: 82.0,
            rss_growth_mb: 2.0,
            avg_physical_footprint_mb: 60.5,
            peak_physical_footprint_mb: 61.0,
            physical_footprint_growth_mb: 1.0,
            evidence_types: %w[mini_runtime log state_receipt],
            evidence_paths: [soak_log, unrelated_path],
            completed_scenarios: [
              'adaptive Mini resource check passed for this release build',
              'average CPU remains within idle budget',
              'RSS and physical footprint do not grow beyond the short-soak release budget'
            ],
            samples: [
              {
                sampled_at: '2026-06-13T12:00:00Z',
                elapsed_seconds: 0.0,
                cpu: 0.2,
                rss_mb: 80.0,
                physical_footprint_mb: 60.0
              },
              {
                sampled_at: '2026-06-13T12:21:00Z',
                elapsed_seconds: 1260.0,
                cpu: 0.1,
                rss_mb: 82.0,
                physical_footprint_mb: 61.0
              }
            ],
            candidate: {
              app_path: '/Applications/SaneBar.app',
              app_version: '2.1.62',
              app_build: '2162'
            }
          )
        )
        old_time = Time.now - (5 * 60)
        File.utime(old_time, old_time, soak_artifact)
        File.utime(old_time, old_time, soak_log)
        @sweep.instance_variable_set(:@started_at, Time.now)
        @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
        @sweep.instance_variable_set(:@running_bundle_build, '2162')
        @sweep.instance_variable_set(:@action_results, {
          'startup-wake-appearance-recovery' => {
            evidence: [
              { type: 'mini_runtime', detail: 'runtime', artifacts: ['/tmp/sanebar_runtime_resource_soak.log'] },
              { type: 'log', detail: 'log', artifacts: ['/tmp/sanebar_runtime_resource_soak.log'] },
              { type: 'state_receipt', detail: 'receipt', artifacts: [soak_artifact] }
            ]
          }
        })

        rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
        soak = rows.find { |row| row[:id] == 'resource_soak_growth' }
        durable_artifact = File.join(evidence_dir, 'resource-soak-sanebar_runtime_resource_soak.json')
        durable_log = File.join(evidence_dir, 'resource-soak-sanebar_runtime_resource_soak.log')

        assert_equal 'passed', soak[:status]
        assert_includes soak[:evidence_paths], durable_artifact
        assert_includes soak[:evidence_paths], durable_log
        refute_includes soak[:evidence_paths], soak_artifact
        refute_includes soak[:evidence_paths], soak_log
        refute_includes soak[:evidence_paths], unrelated_path
        assert File.file?(durable_artifact)
        assert File.file?(durable_log)
        assert_includes soak[:completed_scenarios], 'adaptive Mini resource check passed for this release build'
        assert_includes soak[:completed_scenarios], 'raw current-build resource soak artifact and log references exist'
        assert_includes soak[:completed_scenarios], 'per-sample CPU/RSS/physical footprint trend fields were captured'
      end
    end
  end

  def test_resource_soak_log_validation_accepts_keyword_hash_candidate_format
    Dir.mktmpdir do |dir|
      now = Time.now.utc
      soak_log = File.join(dir, 'sanebar_runtime_resource_soak.log')
      File.write(
        soak_log,
        [
          "resource_soak_started_at=#{(now - 244).iso8601}",
          'candidate={pid: 46901, app_path: "/Applications/SaneBar.app", app_version: "2.1.72", app_build: "2172", process_path: "/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
          'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
          'sample=2 elapsed=244.0s cpu=0.1 rss=82.0MB physical=61.0MB',
          "resource_soak_finished_at=#{now.iso8601}",
          'status=pass'
        ].join("\n")
      )
      @sweep.instance_variable_set(:@started_at, Time.now)
      payload = {
        'candidate' => {
          'app_path' => '/Applications/SaneBar.app',
          'app_version' => '2.1.72',
          'app_build' => '2172'
        }
      }

      assert_nil @sweep.send(:resource_soak_log_rejection_reason, soak_log, payload)
    end
  end

  def test_runtime_state_results_accepts_fresh_durable_resource_soak_when_tmp_is_gone
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    output_dir = CustomerUIActionSweep.const_get(:OUTPUT_DIR)
    FileUtils.mkdir_p(output_dir)

    preserve_files(soak_artifact, soak_log) do
      FileUtils.rm_f([soak_artifact, soak_log])
      Dir.mktmpdir('resource-soak-durable-', output_dir) do |evidence_dir|
        now = Time.now.utc
        durable_artifact = File.join(evidence_dir, 'resource-soak-sanebar_runtime_resource_soak.json')
        durable_log = File.join(evidence_dir, 'resource-soak-sanebar_runtime_resource_soak.log')
        File.write(
          durable_log,
          [
            "resource_soak_started_at=#{(now - 660).iso8601}",
            'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"9.9.9", :app_build=>"9999", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
            'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
            'sample=2 elapsed=660.0s cpu=0.1 rss=82.0MB physical=61.0MB',
            "resource_soak_finished_at=#{now.iso8601}",
            'status=pass'
          ].join("\n")
        )
        File.write(
          durable_artifact,
          JSON.pretty_generate(
            status: 'pass',
            started_at: (now - 660).iso8601,
            finished_at: now.iso8601,
            duration_seconds: 660.0,
            adaptive: true,
            adaptive_status: 'full_duration_pass',
            sample_count: 2,
            physical_sample_count: 2,
            physical_missing_sample_count: 0,
            evidence_types: %w[mini_runtime log state_receipt],
            evidence_paths: [soak_log],
            completed_scenarios: [
              'average CPU remains within idle budget',
              'RSS and physical footprint do not grow beyond the short-soak release budget'
            ],
            samples: [
              {
                sampled_at: '2026-06-13T12:00:00Z',
                elapsed_seconds: 0.0,
                cpu: 0.2,
                rss_mb: 80.0,
                physical_footprint_mb: 60.0
              },
              {
                sampled_at: '2026-06-13T12:11:00Z',
                elapsed_seconds: 660.0,
                cpu: 0.1,
                rss_mb: 82.0,
                physical_footprint_mb: 61.0
              }
            ],
            candidate: {
              app_path: '/Applications/SaneBar.app',
              app_version: '9.9.9',
              app_build: '9999'
            }
          )
        )
        @sweep.instance_variable_set(:@started_at, Time.now)
        @sweep.instance_variable_set(:@running_bundle_version, '9.9.9')
        @sweep.instance_variable_set(:@running_bundle_build, '9999')
        @sweep.instance_variable_set(:@action_results, {
          'startup-wake-appearance-recovery' => {
            status: 'passed',
            evidence: []
          }
        })

        rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
        soak = rows.find { |row| row[:id] == 'resource_soak_growth' }

        assert_equal 'passed', soak[:status]
        assert_includes soak[:evidence_paths], durable_artifact
        assert_includes soak[:evidence_paths], durable_log
        assert_includes soak[:completed_scenarios], 'adaptive Mini resource check passed for this release build'
      end
    end
  end

  def test_write_receipt_persists_durable_resource_soak_paths
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    receipt_paths = [
      CustomerUIActionSweep.const_get(:RECEIPT_PATH),
      CustomerUIActionSweep.const_get(:OUTPUT_RECEIPT_PATH)
    ]

    Dir.mktmpdir do |evidence_dir|
      @sweep.instance_variable_set(:@evidence_dir, evidence_dir)
      preserve_files(soak_artifact, soak_log, *receipt_paths) do
        now = Time.now.utc
        File.write(
          soak_log,
          [
            "resource_soak_started_at=#{(now - 1260).iso8601}",
            'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"2.1.62", :app_build=>"2162", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
            'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
            'sample=2 elapsed=1260.0s cpu=0.1 rss=82.0MB physical=61.0MB',
            "resource_soak_finished_at=#{now.iso8601}",
            'status=pass'
          ].join("\n")
        )
        File.write(
          soak_artifact,
          JSON.pretty_generate(
            status: 'pass',
            started_at: (now - 1260).iso8601,
            finished_at: now.iso8601,
            duration_seconds: 1260.0,
            adaptive: true,
            adaptive_status: 'full_duration_pass',
            sample_count: 2,
            physical_sample_count: 2,
            physical_missing_sample_count: 0,
            evidence_types: %w[mini_runtime log state_receipt],
            evidence_paths: [soak_log],
            completed_scenarios: [
              'adaptive Mini resource check passed for this release build'
            ],
            samples: [
              {
                sampled_at: '2026-06-13T12:00:00Z',
                elapsed_seconds: 0.0,
                cpu: 0.2,
                rss_mb: 80.0,
                physical_footprint_mb: 60.0
              },
              {
                sampled_at: '2026-06-13T12:21:00Z',
                elapsed_seconds: 1260.0,
                cpu: 0.1,
                rss_mb: 82.0,
                physical_footprint_mb: 61.0
              }
            ],
            candidate: {
              app_path: '/Applications/SaneBar.app',
              app_version: '2.1.62',
              app_build: '2162'
            }
          )
        )
        old_time = Time.now - (5 * 60)
        File.utime(old_time, old_time, soak_artifact)
        File.utime(old_time, old_time, soak_log)
        @sweep.instance_variable_set(:@started_at, Time.now)
        @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
        @sweep.instance_variable_set(:@running_bundle_build, '2162')
        @sweep.instance_variable_set(:@action_ids, ['startup-wake-appearance-recovery'])
        @sweep.instance_variable_set(:@action_results, {
          'startup-wake-appearance-recovery' => {
            evidence: [
              { type: 'mini_runtime', detail: 'runtime', artifacts: [soak_log] },
              { type: 'log', detail: 'log', artifacts: [soak_log] },
              { type: 'state_receipt', detail: 'receipt', artifacts: [soak_artifact] }
            ]
          }
        })
        @sweep.define_singleton_method(:customer_ui_contract_report) do
          { 'manifest_sha256' => 'abc', 'source_fingerprint' => 'def' }
        end

        with_manifest(<<~YAML) do
          version: 1
          app: SaneBar
          runtime_state_matrix:
            resource_soak_growth:
              why: Release candidates must prove resource growth from durable Mini soak artifacts.
              action_ids: [startup-wake-appearance-recovery]
              required_evidence_types: [mini_runtime, log, state_receipt]
          actions:
            - id: startup-wake-appearance-recovery
              title: Startup wake recovery works
              required_evidence_types: [mini_runtime, log, state_receipt]
        YAML
          @sweep.send(:write_receipt)
        end

        receipt = JSON.parse(File.read(CustomerUIActionSweep.const_get(:OUTPUT_RECEIPT_PATH)))
        soak = receipt.fetch('runtime_state_results').find { |row| row['id'] == 'resource_soak_growth' }
        durable_artifact = File.join(evidence_dir, 'resource-soak-sanebar_runtime_resource_soak.json')
        durable_log = File.join(evidence_dir, 'resource-soak-sanebar_runtime_resource_soak.log')

        assert_equal 'passed', soak['status']
        assert_includes soak['evidence_paths'], durable_artifact
        assert_includes soak['evidence_paths'], durable_log
        refute_includes soak['evidence_paths'], soak_artifact
        refute_includes soak['evidence_paths'], soak_log
        assert_includes soak['completed_scenarios'], 'adaptive Mini resource check passed for this release build'
      ensure
        @sweep.singleton_class.remove_method(:customer_ui_contract_report) rescue nil
      end
    end
  end

  def test_runtime_state_results_rejects_resource_soak_from_wrong_candidate_version
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    preserve_files(soak_artifact, soak_log) do
      File.write(
        soak_log,
        [
          'resource_soak_started_at=2026-06-13T12:00:00Z',
          'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"2.1.61", :app_build=>"2161", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
          'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
          'sample=2 elapsed=1260.0s cpu=0.1 rss=82.0MB physical=61.0MB',
          'resource_soak_finished_at=2026-06-13T12:21:00Z',
          'status=pass'
        ].join("\n")
      )
      File.write(
        soak_artifact,
        JSON.pretty_generate(
          status: 'pass',
          duration_seconds: 1260.0,
          sample_count: 2,
          evidence_types: %w[mini_runtime log state_receipt],
          evidence_paths: [soak_log],
          completed_scenarios: [
            'adaptive Mini resource check passed for this release build',
            'average CPU remains within idle budget',
            'RSS and physical footprint do not grow beyond the short-soak release budget'
          ],
          samples: [
            {
              sampled_at: '2026-06-13T12:00:00Z',
              elapsed_seconds: 0.0,
              cpu: 0.2,
              rss_mb: 80.0,
              physical_footprint_mb: 60.0
            },
            {
              sampled_at: '2026-06-13T12:21:00Z',
              elapsed_seconds: 1260.0,
              cpu: 0.1,
              rss_mb: 82.0,
              physical_footprint_mb: 61.0
            }
          ],
          candidate: {
            app_path: '/Applications/SaneBar.app',
            app_version: '2.1.61',
            app_build: '2161'
          }
        )
      )
      old_time = Time.now - (2 * 60 * 60)
      File.utime(old_time, old_time, soak_artifact)
      File.utime(old_time, old_time, soak_log)
      @sweep.instance_variable_set(:@started_at, Time.now)
      @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
      @sweep.instance_variable_set(:@running_bundle_build, '2162')
      @sweep.instance_variable_set(:@action_results, {
        'startup-wake-appearance-recovery' => {
          status: 'passed',
          evidence: [
            { type: 'mini_runtime', detail: 'runtime', artifacts: [soak_log] },
            { type: 'log', detail: 'log', artifacts: [soak_log] },
            { type: 'state_receipt', detail: 'receipt', artifacts: [soak_artifact] }
          ]
        }
      })

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      soak = rows.find { |row| row[:id] == 'resource_soak_growth' }

      assert_equal 'failed', soak[:status]
      assert_nil soak[:runtime_candidate]
      refute_includes soak[:completed_scenarios], 'raw current-build resource soak artifact and log references exist'
    end
  end

  def test_runtime_state_results_rejects_summary_only_resource_soak
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    preserve_files(soak_artifact, soak_log) do
      File.write(soak_log, "resource_soak_started_at=2026-06-13T12:00:00Z\nResource soak summary only\nstatus=pass\n")
      File.write(
        soak_artifact,
        JSON.pretty_generate(
          status: 'pass',
          duration_seconds: 1260.0,
          sample_count: 2,
          avg_cpu: 0.15,
          peak_rss_mb: 82.0,
          evidence_types: %w[mini_runtime log state_receipt],
          evidence_paths: [soak_log],
          completed_scenarios: [
            'adaptive Mini resource check passed for this release build',
            'average CPU remains within idle budget',
            'RSS and physical footprint do not grow beyond the short-soak release budget'
          ],
          candidate: {
            app_path: '/Applications/SaneBar.app',
            app_version: '2.1.62',
            app_build: '2162'
          }
        )
      )
      @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
      @sweep.instance_variable_set(:@running_bundle_build, '2162')
      @sweep.instance_variable_set(:@action_results, {
        'startup-wake-appearance-recovery' => {
          status: 'passed',
          evidence: [
            { type: 'mini_runtime', detail: 'runtime', artifacts: [soak_log] },
            { type: 'log', detail: 'log', artifacts: [soak_log] },
            { type: 'state_receipt', detail: 'receipt', artifacts: [soak_artifact] }
          ]
        }
      })

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      soak = rows.find { |row| row[:id] == 'resource_soak_growth' }

      assert_equal 'failed', soak[:status]
      refute_includes soak[:completed_scenarios], 'raw current-build resource soak artifact and log references exist'
      assert_includes soak[:failure_reasons].join("\n"), 'missing completed_scenarios'
    end
  end

  def test_runtime_state_results_rejects_resource_soak_with_missing_samples
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    preserve_files(soak_artifact, soak_log) do
      File.write(
        soak_log,
        [
          'resource_soak_started_at=2026-06-13T12:00:00Z',
          'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"2.1.62", :app_build=>"2162", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
          'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
          'sample=2 elapsed=260.0s cpu=0.1 rss=82.0MB physical=61.0MB',
          'sample_missing elapsed=270.0s pid=12345',
          'sample_missing elapsed=1200.0s pid=12345',
          'resource_soak_finished_at=2026-06-13T12:20:00Z',
          'status=pass'
        ].join("\n")
      )
      File.write(
        soak_artifact,
        JSON.pretty_generate(
          status: 'pass',
          duration_seconds: 1260.0,
          sample_count: 2,
          evidence_types: %w[mini_runtime log state_receipt],
          evidence_paths: [soak_log],
          completed_scenarios: [
            'adaptive Mini resource check passed for this release build',
            'average CPU remains within idle budget',
            'RSS and physical footprint do not grow beyond the short-soak release budget'
          ],
          samples: [
            {
              sampled_at: '2026-06-13T12:00:00Z',
              elapsed_seconds: 0.0,
              cpu: 0.2,
              rss_mb: 80.0,
              physical_footprint_mb: 60.0
            },
            {
              sampled_at: '2026-06-13T12:04:20Z',
              elapsed_seconds: 260.0,
              cpu: 0.1,
              rss_mb: 82.0,
              physical_footprint_mb: 61.0
            }
          ],
          candidate: {
            app_path: '/Applications/SaneBar.app',
            app_version: '2.1.62',
            app_build: '2162'
          }
        )
      )
      old_time = Time.now - (2 * 60 * 60)
      File.utime(old_time, old_time, soak_artifact)
      File.utime(old_time, old_time, soak_log)
      @sweep.instance_variable_set(:@started_at, Time.now)
      @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
      @sweep.instance_variable_set(:@running_bundle_build, '2162')
      @sweep.instance_variable_set(:@action_results, {
        'startup-wake-appearance-recovery' => {
          status: 'passed',
          evidence: [
            { type: 'mini_runtime', detail: 'runtime', artifacts: [soak_log] },
            { type: 'log', detail: 'log', artifacts: [soak_log] },
            { type: 'state_receipt', detail: 'receipt', artifacts: [soak_artifact] }
          ]
        }
      })

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      soak = rows.find { |row| row[:id] == 'resource_soak_growth' }

      assert_equal 'failed', soak[:status]
      refute_includes soak[:completed_scenarios], 'raw current-build resource soak artifact and log references exist'
    end
  end

  def test_runtime_state_results_rejects_resource_soak_with_sparse_physical_samples
    soak_artifact = '/tmp/sanebar_runtime_resource_soak.json'
    soak_log = '/tmp/sanebar_runtime_resource_soak.log'
    preserve_files(soak_artifact, soak_log) do
      now = Time.now.utc
      File.write(
        soak_log,
        [
          'resource_soak_started_at=2026-06-13T12:00:00Z',
          'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"2.1.62", :app_build=>"2162", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
          'sample=1 elapsed=0.0s cpu=0.2 rss=80.0MB physical=60.0MB',
          'sample=2 elapsed=260.0s cpu=0.1 rss=82.0MB physical=unknown',
          'resource_soak_finished_at=2026-06-13T12:04:20Z',
          'status=pass'
        ].join("\n")
      )
      File.write(
        soak_artifact,
        JSON.pretty_generate(
          status: 'pass',
          started_at: (now - 260).iso8601,
          finished_at: now.iso8601,
          duration_seconds: 260.0,
          adaptive: true,
          adaptive_status: 'early_pass',
          sample_count: 2,
          physical_sample_count: 1,
          physical_missing_sample_count: 1,
          evidence_types: %w[mini_runtime log state_receipt],
          evidence_paths: [soak_log],
          completed_scenarios: [
            'adaptive Mini resource check passed for this release build',
            'average CPU remains within idle budget',
            'RSS and physical footprint do not grow beyond the short-soak release budget'
          ],
          samples: [
            {
              sampled_at: '2026-06-13T12:00:00Z',
              elapsed_seconds: 0.0,
              cpu: 0.2,
              rss_mb: 80.0,
              physical_footprint_mb: 60.0
            },
            {
              sampled_at: '2026-06-13T12:04:20Z',
              elapsed_seconds: 260.0,
              cpu: 0.1,
              rss_mb: 82.0
            }
          ],
          candidate: {
            app_path: '/Applications/SaneBar.app',
            app_version: '2.1.62',
            app_build: '2162'
          }
        )
      )
      File.utime(Time.now, Time.now, soak_artifact)
      File.utime(Time.now, Time.now, soak_log)
      @sweep.instance_variable_set(:@started_at, Time.now)
      @sweep.instance_variable_set(:@running_bundle_version, '2.1.62')
      @sweep.instance_variable_set(:@running_bundle_build, '2162')
      @sweep.instance_variable_set(:@action_results, {
        'startup-wake-appearance-recovery' => {
          status: 'passed',
          evidence: [
            { type: 'mini_runtime', detail: 'runtime', artifacts: [soak_log] },
            { type: 'log', detail: 'log', artifacts: [soak_log] },
            { type: 'state_receipt', detail: 'receipt', artifacts: [soak_artifact] }
          ]
        }
      })

      rows = @sweep.send(:runtime_state_results, { 'manifest_sha256' => 'abc' })
      soak = rows.find { |row| row[:id] == 'resource_soak_growth' }

      assert_equal 'failed', soak[:status]
      refute_includes soak[:completed_scenarios], 'raw current-build resource soak artifact and log references exist'
    end
  end

  def test_settings_tab_selector_ignores_front_system_dialog
    source = File.read(File.join(__dir__, 'customer_ui_action_sweep.rb'))
    runtime_source = File.read(File.join(__dir__, 'lib', 'customer_ui_action_sweep_runtime.rb'))

    assert_includes source, 'subrole is "AXStandardWindow"'
    assert_includes source, 'set settingsWindow to first window whose subrole is "AXStandardWindow"'
    assert_includes source, 'splitter group 1 of group 1 of settingsWindow'
    assert_includes source, 'set browseWindow to missing value'
    assert_includes source, 'name of candidateWindow is "Icon Panel"'
    assert_includes source, 'buttons of group 1 of browseWindow'
    assert_includes source, 'description is "+ Custom"'
    assert_includes source, 'Icon Panel standard window not found'
    assert_includes source, 'set groupDialog to missing value'
    assert_includes source, 'candidateText contains "New Custom Group"'
    assert_includes source, 'repeat 24 times'
    assert_includes source, 'text field 1 of groupDialog'
    assert_includes source, 'exercise_hover_auto_rehide_runtime_probe'
    assert_includes source, "runtime_probe_artifact_path('hover_rehide', 'json')"
    refute_includes source, '/tmp/sanebar_runtime_hover_rehide.json'
    assert_includes source, 'settle_runtime_ui_for_rehide_probe'
    assert_includes source, 'park_pointer_away_from_menu_bar'
    assert_includes source, 'move_pointer_to_menu_bar_for_hover_probe'
    assert_includes source, 'ensure_hover_reveal_enabled_for_probe'
    assert_includes source, 'Pointer parking left the cursor in the menu-bar interaction region'
    assert_includes source, 'autoRehideBlockReason'
    assert_includes source, 'snapshot_summary(last)'
    assert_includes source, 'verify_recent_appearance_overlay_screenshots'
    assert_includes source, 'exercise_license_clipboard_paste_runtime_probe'
    assert_includes source, "runtime_probe_artifact_path('license_paste', 'json')"
    refute_includes source, '/tmp/sanebar_runtime_license_paste.json'
    assert_includes source, 'drive_license_clipboard_paste_ui'
    assert_includes source, 'saneui-license-paste'
    assert_includes source, 'saneui-license-key-field'
    assert_includes source, 'saneui-license-activate'
    assert_includes source, 'safe_write_runtime_probe_file'
    assert_includes source, 'SANE_APPROVE_LOCAL_UI_ON_AIR'
    assert_includes runtime_source, 'host: Socket.gethostname.to_s.downcase'
    assert_includes runtime_source, 'local_air_fallback:'
  end

  def test_customer_ui_sweep_fails_early_without_fresh_appearance_overlay_screenshots
    @sweep.define_singleton_method(:latest_runtime_screenshots) { [] }

    error = assert_raises(RuntimeError) do
      @sweep.send(:verify_recent_appearance_overlay_screenshots)
    end

    assert_includes error.message, 'Missing fresh usable appearance overlay screenshot evidence'
    assert_includes error.message, 'SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 ruby Scripts/qa.rb'
  end
end
