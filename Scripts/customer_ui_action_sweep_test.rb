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
    startup_log = '/tmp/sanebar_runtime_startup_probe.log'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, wake_log, shared_log) do
    File.write(smoke_log, [
      'Settings window visual check ok',
      'Browse mode secondMenuBar open/close ok',
      'Browse mode findIcon open/close ok',
      'Live zone smoke passed'
    ].join("\n"))
    File.write(startup_log, 'Startup layout probe passed')
    File.write(wake_log, 'Wake layout probe passed')
    File.write(shared_log, [
      'Hidden/Visible move actions ok',
      'Always Hidden move actions ok',
      'Representative zone candidates ok',
      '✅ Candidate set passed: com.sanebar.sharedfixture::statusItem:0, com.sanebar.sharedfixture::statusItem:1',
      '✅ Live zone smoke passed'
    ].join("\n"))

    @sweep.send(:verify_recent_runtime_smoke)

    transcript = @sweep.instance_variable_get(:@transcript)
    assert_includes transcript, "shared_exact_id=#{shared_log} ok"
    end
  end

  def test_runtime_smoke_accepts_same_release_session_evidence_beyond_thirty_minutes
    smoke_log = '/tmp/sanebar_runtime_smoke.log'
    startup_log = '/tmp/sanebar_runtime_startup_probe.log'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, wake_log, shared_log) do
      now = Time.now
      @sweep.instance_variable_set(:@started_at, now)
      File.write(smoke_log, [
        'Settings window visual check ok',
        'Browse mode secondMenuBar open/close ok',
        'Browse mode findIcon open/close ok',
        'Live zone smoke passed'
      ].join("\n"))
      File.write(startup_log, 'Startup layout probe passed')
      File.write(wake_log, 'Wake layout probe passed')
      File.write(shared_log, [
        'Hidden/Visible move actions ok',
        'Always Hidden move actions ok',
        'Representative zone candidates ok',
        '✅ Candidate set passed: com.sanebar.sharedfixture::statusItem:0, com.sanebar.sharedfixture::statusItem:1',
        '✅ Live zone smoke passed'
      ].join("\n"))
      [smoke_log, startup_log, wake_log, shared_log].each do |path|
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
    startup_log = '/tmp/sanebar_runtime_startup_probe.log'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
    shared_log = '/tmp/sanebar_runtime_shared_bundle_smoke.log'
    preserve_files(smoke_log, startup_log, wake_log, shared_log) do
      now = Time.now
      @sweep.instance_variable_set(:@started_at, now)
      [smoke_log, startup_log, wake_log, shared_log].each do |path|
        File.write(path, 'Live zone smoke passed')
        File.utime(now - 3 * 60 * 60, now - 3 * 60 * 60, path)
      end

      error = assert_raises(RuntimeError) do
        @sweep.send(:verify_recent_runtime_smoke)
      end

      assert_includes error.message, "Missing runtime evidence #{smoke_log}"
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
    preserve_files(fullscreen_artifact) do
    File.write(
      fullscreen_artifact,
      JSON.pretty_generate(
        status: 'pass',
        evidence_types: %w[mini_runtime screenshot log],
        evidence_paths: ['/tmp/sanebar-top-strip.png'],
        completed_scenarios: [
          'native fullscreen enter and exit',
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
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_startup_probe.log: Startup layout probe passed', artifacts: ['/tmp/sanebar_runtime_startup_probe.log'] },
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

  def test_runtime_state_results_fail_without_named_fullscreen_scenarios
    fullscreen_artifact = '/tmp/sanebar_runtime_fullscreen_matrix.json'
    preserve_files(fullscreen_artifact) do
      FileUtils.rm_f(fullscreen_artifact)

    @sweep.instance_variable_set(:@action_results, {
      'startup-wake-appearance-recovery' => {
        evidence: [
          { type: 'mini_runtime', detail: '/tmp/sanebar_runtime_startup_probe.log: Startup layout probe passed', artifacts: ['/tmp/sanebar_runtime_startup_probe.log'] },
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
    wake_artifact = '/tmp/sanebar_runtime_wake_probe.json'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
    preserve_files(wake_artifact, wake_log) do
    File.write(wake_log, 'Wake layout probe passed')
    File.write(
      wake_artifact,
      JSON.pretty_generate(
        status: 'pass',
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
    wake_artifact = '/tmp/sanebar_runtime_wake_probe.json'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
    preserve_files(wake_artifact, wake_log) do
    File.write(wake_log, 'Wake layout probe passed')
    File.write(
      wake_artifact,
      JSON.pretty_generate(
        status: 'pass',
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
    wake_artifact = '/tmp/sanebar_runtime_wake_probe.json'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
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
    wake_artifact = '/tmp/sanebar_runtime_wake_probe.json'
    wake_log = '/tmp/sanebar_runtime_wake_probe.log'
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
    preserve_files(soak_artifact, soak_log) do
      File.write(
        soak_log,
        [
          'resource_soak_started_at=2026-06-13T12:00:00Z',
          'candidate={:app_path=>"/Applications/SaneBar.app", :app_version=>"2.1.62", :app_build=>"2162", :process_path=>"/Applications/SaneBar.app/Contents/MacOS/SaneBar"}',
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
          avg_cpu: 0.15,
          peak_cpu: 0.2,
          avg_rss_mb: 81.0,
          peak_rss_mb: 82.0,
          rss_growth_mb: 2.0,
          avg_physical_footprint_mb: 60.5,
          peak_physical_footprint_mb: 61.0,
          physical_footprint_growth_mb: 1.0,
          evidence_types: %w[mini_runtime log state_receipt],
          evidence_paths: [soak_log],
          completed_scenarios: [
            'at least 20m Mini soak sampled on the release candidate',
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
      old_time = Time.now - (2 * 60 * 60)
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

      assert_equal 'passed', soak[:status]
      assert_includes soak[:evidence_paths], soak_artifact
      assert_includes soak[:evidence_paths], soak_log
      assert_includes soak[:completed_scenarios], 'raw current-build resource soak artifact and log references exist'
      assert_includes soak[:completed_scenarios], 'per-sample CPU/RSS/physical footprint trend fields were captured'
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
            'at least 20m Mini soak sampled on the release candidate',
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
    assert_includes source, '/tmp/sanebar_runtime_hover_rehide.json'
    assert_includes source, 'settle_runtime_ui_for_rehide_probe'
    assert_includes source, 'park_pointer_away_from_menu_bar'
    assert_includes source, 'Pointer parking left the cursor in the menu-bar interaction region'
    assert_includes source, 'autoRehideBlockReason'
    assert_includes source, 'snapshot_summary(last)'
    assert_includes source, 'verify_recent_appearance_overlay_screenshots'
    assert_includes source, 'exercise_license_clipboard_paste_runtime_probe'
    assert_includes source, '/tmp/sanebar_runtime_license_paste.json'
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
