#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'live_zone_smoke'

class LiveZoneSmokeTest < Minitest::Test
  def build_smoke(required_ids: [])
    smoke = LiveZoneSmoke.allocate
    smoke.instance_variable_set(:@require_always_hidden, false)
    smoke.instance_variable_set(:@require_all_candidates, false)
    smoke.instance_variable_set(:@required_candidate_ids, required_ids)
    smoke.instance_variable_set(:@app_pid, Process.pid)
    smoke.instance_variable_set(:@active_avg_cpu_max, LiveZoneSmoke::DEFAULT_ACTIVE_AVG_CPU_MAX)
    smoke.instance_variable_set(:@active_avg_rss_mb_max, LiveZoneSmoke::DEFAULT_ACTIVE_AVG_RSS_MB_MAX)
    smoke.instance_variable_set(:@post_move_zone_stability_seconds, LiveZoneSmoke::DEFAULT_POST_MOVE_ZONE_STABILITY_SECONDS)
    smoke.send(:reset_resource_watchdog_state)
    smoke
  end

  def test_normal_candidate_pool_keeps_move_denylist
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.menuextra.focusmode',
        unique_id: 'com.apple.menuextra.focusmode::axid:7',
        name: 'Focus'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_normal_candidate_pool_excludes_menumeters_even_with_bundle_whitespace
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: ' com.yujitach.MenuMeters ',
        unique_id: 'com.yujitach.MenuMeters::statusItem:3',
        name: 'MenuMeters'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_normal_candidate_pool_excludes_unreliable_setapp_helpers
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sindresorhus.Lungo-setapp',
        unique_id: 'com.sindresorhus.Lungo-setapp::statusItem:0',
        name: 'Lungo'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.setapp.DesktopClient.SetappLauncher',
        unique_id: 'com.setapp.DesktopClient.SetappLauncher::axid:Setapp-MenuBar-Item',
        name: 'SetappLauncher'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.ameba.SwiftBar',
        unique_id: 'com.ameba.SwiftBar::statusItem:0',
        name: 'SwiftBar'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_normal_candidate_pool_excludes_codex_controller_status_item
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.openai.codex',
        unique_id: 'com.openai.codex::statusItem:0',
        name: 'Codex'
      }
    ]

    candidates = smoke.send(:candidate_pool, zones)

    assert_empty candidates
  end

  def test_required_candidate_bypasses_move_denylist
    required_id = 'com.apple.menuextra.focusmode::axid:7'
    smoke = build_smoke(required_ids: [required_id])
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.menuextra.focusmode',
        unique_id: required_id,
        name: 'Focus'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal [required_id], candidates.map { |candidate| candidate[:unique_id] }
  end

  def test_required_bundle_id_resolves_single_denylisted_candidate
    smoke = build_smoke(required_ids: ['com.apple.menuextra.siri'])
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.menuextra.siri',
        unique_id: 'com.apple.menuextra.siri::axid:3',
        name: 'Siri'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal ['com.apple.menuextra.siri::axid:3'], candidates.map { |candidate| candidate[:unique_id] }
  end

  def test_required_shared_fixture_remains_available_for_exact_id_move_smoke
    required_id = 'com.sanebar.sharedfixture::statusItem:0'
    smoke = build_smoke(required_ids: [required_id])
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: required_id,
        name: 'SaneBarSharedFixture'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal [required_id], candidates.map { |candidate| candidate[:unique_id] }
  end

  def test_prepare_zones_reseeds_always_hidden_after_visual_checks
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible.one', unique_id: 'visible-one', name: 'Visible One' },
      { zone: 'visible', movable: true, bundle: 'com.example.visible.two', unique_id: 'visible-two', name: 'Visible Two' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.one', unique_id: 'hidden-one', name: 'Hidden One' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden.two', unique_id: 'hidden-two', name: 'Hidden Two' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah.one', unique_id: 'ah-one', name: 'AH One' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah.two', unique_id: 'ah-two', name: 'AH Two' }
    ]
    calls = []

    smoke.define_singleton_method(:close_browse_panel_safely) {}
    smoke.define_singleton_method(:close_settings_window_safely) {}
    smoke.define_singleton_method(:prepare_layout_baseline) {}
    smoke.define_singleton_method(:wait_for_stable_layout_snapshot) {}
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) { zones }
    smoke.define_singleton_method(:move_and_verify) do |command, donor, expected_zone|
      calls << [command, donor[:unique_id], expected_zone]
      zones.find { |item| item[:unique_id] == donor[:unique_id] }[:zone] = expected_zone
    end

    prepared = smoke.send(:prepare_zones_for_move_checks)
    prepared_counts = smoke.send(:candidate_pool, prepared).group_by { |item| item[:zone] }.transform_values(&:length)

    assert_equal 3, prepared_counts['alwaysHidden']
    assert_equal 1, calls.length
    assert_equal 'move icon to always hidden', calls.first[0]
    assert_equal 'alwaysHidden', calls.first[2]
  end

  def test_required_ids_enable_focused_smoke_mode
    smoke = build_smoke(required_ids: ['com.apple.menuextra.focusmode'])

    assert smoke.send(:focused_required_id_mode?)
  end

  def test_matching_process_requires_no_keychain_when_requested
    smoke = build_smoke
    smoke.instance_variable_set(:@process_path, '/Applications/SaneBar.app/Contents/MacOS/SaneBar')
    smoke.instance_variable_set(:@require_no_keychain_process, true)

    assert smoke.send(
      :matching_app_process?,
      '/Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain'
    )
    refute smoke.send(
      :matching_app_process?,
      '/Applications/SaneBar.app/Contents/MacOS/SaneBar'
    )
  end

  def test_default_smoke_does_not_require_move_candidates
    smoke = build_smoke

    refute smoke.send(:move_candidates_required?)
  end

  def test_required_id_smoke_requires_move_candidates
    smoke = build_smoke(required_ids: ['com.apple.menuextra.focusmode'])

    assert smoke.send(:move_candidates_required?)
  end

  def test_all_zone_smoke_rejects_empty_always_hidden_candidate_lane
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.visible',
        unique_id: 'com.example.visible::statusItem:0',
        name: 'Visible'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.hidden',
        unique_id: 'com.example.hidden::statusItem:0',
        name: 'Hidden'
      }
    ]

    error = assert_raises(RuntimeError) do
      smoke.send(:require_representative_zone_candidates!, zones)
    end

    assert_includes error.message, 'three representative movable always-hidden candidates'
  end

  def test_all_zone_smoke_selects_three_always_hidden_candidates_for_action_matrix
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.visible',
        unique_id: 'com.example.visible::statusItem:0',
        name: 'Visible'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.hidden',
        unique_id: 'com.example.hidden::statusItem:0',
        name: 'Hidden'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.example.always',
        unique_id: 'com.example.always::statusItem:0',
        name: 'Always'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.example.always2',
        unique_id: 'com.example.always2::statusItem:0',
        name: 'Always 2'
      },
      {
        zone: 'alwaysHidden',
        movable: true,
        bundle: 'com.example.always3',
        unique_id: 'com.example.always3::statusItem:0',
        name: 'Always 3'
      }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal %w[visible hidden alwaysHidden alwaysHidden alwaysHidden], candidates.map { |candidate| candidate[:zone] }
    assert smoke.send(:strict_candidate_mode?)
    assert smoke.send(:representative_action_matrix_mode?)
  end

  def test_all_zone_smoke_prefers_shared_fixture_for_visible_and_hidden_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    zones = [
      { zone: 'visible', movable: true, bundle: 'com.pxkan.pipit2', unique_id: 'pipit-id', name: 'Pipit' },
      { zone: 'visible', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'fixture-visible-id', name: 'SaneBarSharedFixture' },
      { zone: 'hidden', movable: true, bundle: 'com.apple.weather.menu', unique_id: 'weather-id', name: 'WeatherMenu' },
      { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'fixture-hidden-id', name: 'SaneBarSharedFixture' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]

    candidates = smoke.send(:selected_candidates, zones)

    assert_equal 'fixture-visible-id', candidates[0][:unique_id]
    assert_equal 'fixture-hidden-id', candidates[1][:unique_id]
  end

  def test_representative_action_matrix_tests_all_direct_zone_moves
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id ah2-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['move icon to visible', 'ah1-id', 'visible'],
      ['move icon to hidden', 'ah2-id', 'hidden'],
      ['hidden-visible-sequence', 'ah1-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_reserves_shared_fixture_for_always_hidden_to_hidden
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'fixture-ah-id', name: 'SaneBarSharedFixture' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.apple.weather.menu', unique_id: 'weather-id', name: 'WeatherMenu' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id fixture-ah-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['move icon to visible', 'ah1-id', 'visible'],
      ['move icon to hidden', 'fixture-ah-id', 'hidden'],
      ['hidden-visible-sequence', 'ah1-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_stages_visible_candidate_when_ah_to_visible_candidates_fail
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:exercise_matrix_move_with_fallback) do |label, candidates_for_label, command, expected_zone|
      raise 'all AH->Visible candidates failed' if label == 'AH->Visible'

      calls << [label, candidates_for_label.first[:unique_id], command, expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidates_for_label.first[:unique_id] }
      live[:zone] = expected_zone if live
      candidates_for_label.first
    end
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[visible-id ah1-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['move icon to always hidden', 'visible-id', 'alwaysHidden'],
      ['move icon to visible', 'visible-id', 'visible'],
      ['AH->Hidden', 'ah1-id', 'move icon to hidden', 'hidden'],
      ['hidden-visible-sequence', 'visible-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_stages_hidden_candidate_when_ah_to_hidden_candidates_fail
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.sanebar.sharedfixture', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:exercise_matrix_move_with_fallback) do |label, candidates_for_label, command, expected_zone|
      raise 'all AH->Hidden candidates failed' if label == 'AH->Hidden'

      calls << [label, candidates_for_label.first[:unique_id], command, expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidates_for_label.first[:unique_id] }
      live[:zone] = expected_zone if live
      candidates_for_label.first
    end
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id hidden-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_equal [
      ['AH->Visible', 'ah1-id', 'move icon to visible', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden'],
      ['move icon to hidden', 'hidden-id', 'hidden'],
      ['hidden-visible-sequence', 'ah1-id', 'visible'],
      ['move icon to always hidden', 'hidden-id', 'alwaysHidden']
    ], calls
  end

  def test_representative_action_matrix_falls_back_when_hidden_visible_candidate_fails
    smoke = build_smoke
    calls = []
    candidates = [
      { zone: 'visible', movable: true, bundle: 'com.example.visible', unique_id: 'visible-id', name: 'Visible' },
      { zone: 'hidden', movable: true, bundle: 'com.example.hidden', unique_id: 'hidden-id', name: 'Hidden' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah1', unique_id: 'ah1-id', name: 'AH 1' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah2', unique_id: 'ah2-id', name: 'AH 2' },
      { zone: 'alwaysHidden', movable: true, bundle: 'com.example.ah3', unique_id: 'ah3-id', name: 'AH 3' }
    ]
    smoke.define_singleton_method(:list_icon_zones) { candidates }
    smoke.define_singleton_method(:move_and_verify) do |command, candidate, expected_zone|
      calls << [command, candidate[:unique_id], expected_zone]
      live = candidates.find { |item| item[:unique_id] == candidate[:unique_id] }
      live[:zone] = expected_zone if live
    end
    smoke.define_singleton_method(:exercise_hidden_visible_moves) do |candidate|
      calls << ['hidden-visible-sequence', candidate[:unique_id], 'visible']
      raise 'candidate-specific visible drag failed' if candidate[:unique_id] == 'ah1-id'
    end

    passed = smoke.send(:exercise_representative_move_action_matrix, candidates)

    assert_equal %w[ah1-id ah2-id hidden-id], passed.map { |candidate| candidate[:unique_id] }
    assert_includes calls, ['hidden-visible-sequence', 'ah1-id', 'visible']
    assert_includes calls, ['hidden-visible-sequence', 'visible-id', 'visible']
  end

  def test_strict_candidate_mode_can_require_minimum_passing_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@min_passing_candidates, 1)

    assert_equal 1, smoke.send(:strict_candidate_minimum, 3)
  end

  def test_strict_candidate_mode_defaults_to_every_candidate
    smoke = build_smoke

    assert_equal 3, smoke.send(:strict_candidate_minimum, 3)
  end

  def test_representative_action_matrix_strict_minimum_uses_matrix_result
    smoke = build_smoke
    smoke.instance_variable_set(:@require_all_zones, true)
    smoke.instance_variable_set(:@required_candidate_ids, [])
    smoke.instance_variable_set(:@require_all_candidates, false)

    assert smoke.send(:representative_action_matrix_mode?)
    assert_equal 1, smoke.send(:strict_candidate_minimum, 5)
  end

  def test_default_smoke_does_not_require_browse_activation_candidates
    smoke = build_smoke

    refute smoke.send(:browse_activation_candidates_required?)
  end

  def test_required_candidate_smoke_does_not_require_browse_activation_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@require_candidate, true)

    refute smoke.send(:browse_activation_candidates_required?)
  end

  def test_required_browse_activation_candidate_smoke_requires_browse_activation_candidates
    smoke = build_smoke
    smoke.instance_variable_set(:@require_browse_activation_candidate, true)

    assert smoke.send(:browse_activation_candidates_required?)
  end

  def test_browse_activation_candidates_prefer_precise_non_apple_before_apple_fixtures
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.precise',
        unique_id: 'com.example.precise::statusItem:2',
        name: 'Widget'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.yujitach.MenuMeters',
        unique_id: 'com.yujitach.MenuMeters::statusItem:3',
        name: 'MenuMeters'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.SSMenuAgent',
        unique_id: 'com.apple.SSMenuAgent',
        name: 'SSMenuAgent'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.Spotlight',
        unique_id: 'com.apple.menuextra.spotlight',
        name: 'Spotlight'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'com.example.precise::statusItem:2', candidate_ids.first
    assert_includes candidate_ids, 'com.yujitach.MenuMeters::statusItem:3'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
    refute_includes candidate_ids, 'com.apple.SSMenuAgent'
    refute_includes candidate_ids, 'com.apple.menuextra.spotlight'
  end

  def test_browse_activation_candidates_exclude_unreliable_setapp_helpers
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sindresorhus.Lungo-setapp',
        unique_id: 'com.sindresorhus.Lungo-setapp::statusItem:0',
        name: 'Lungo'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.setapp.DesktopClient.SetappLauncher',
        unique_id: 'com.setapp.DesktopClient.SetappLauncher::axid:Setapp-MenuBar-Item',
        name: 'SetappLauncher'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    refute_includes candidate_ids, 'com.sindresorhus.Lungo-setapp::statusItem:0'
    refute_includes candidate_ids, 'com.setapp.DesktopClient.SetappLauncher::axid:Setapp-MenuBar-Item'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_exclude_codex_controller_status_item
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.openai.codex',
        unique_id: 'com.openai.codex::statusItem:0',
        name: 'Codex'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    refute_includes candidate_ids, 'com.openai.codex::statusItem:0'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_exclude_unreliable_audio_video_extra
    smoke = build_smoke
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.audiovideo',
        name: 'Audio and Video Controls'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'findIcon',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    refute_includes candidate_ids, 'com.apple.menuextra.audiovideo'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_allow_shared_fixture
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.sanebar.sharedfixture',
        unique_id: 'com.sanebar.sharedfixture::statusItem:0',
        name: 'SaneBarSharedFixture'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'activate browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_includes candidate_ids, 'com.sanebar.sharedfixture::statusItem:0'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_find_icon_right_click_candidates_prefer_precise_non_apple_before_apple_fixtures
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.precise',
        unique_id: 'com.example.precise::statusItem:2',
        name: 'Widget'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.SSMenuAgent',
        unique_id: 'com.apple.SSMenuAgent',
        name: 'SSMenuAgent'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'findIcon',
      activation_command: 'right click browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'com.example.precise::statusItem:2', candidate_ids.first
    refute_includes candidate_ids, 'com.apple.SSMenuAgent'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_browse_activation_candidates_prefer_coarse_non_apple_before_apple_fixtures
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'org.p0deje.Maccy',
        unique_id: 'org.p0deje.Maccy',
        name: 'Maccy'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.apple.SSMenuAgent',
        unique_id: 'com.apple.SSMenuAgent',
        name: 'SSMenuAgent'
      },
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.apple.controlcenter',
        unique_id: 'com.apple.menuextra.display',
        name: 'Display'
      }
    ]

    candidates = smoke.send(
      :browse_activation_candidates,
      zones,
      expected_mode: 'secondMenuBar',
      activation_command: 'right click browse icon'
    )
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'org.p0deje.Maccy', candidate_ids.first
    refute_includes candidate_ids, 'com.apple.SSMenuAgent'
    assert_includes candidate_ids, 'com.apple.menuextra.display'
  end

  def test_focus_revert_guard_accepts_observable_successful_browse_click
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:frontmost_app_state) do
      { 'bundleId' => 'com.apple.finder', 'windowTitle' => 'Desktop' }
    end
    smoke.define_singleton_method(:current_browse_activation_diagnostics) do
      "finalOutcome: click succeeded\nwindowVisible: true\ncurrentMode: secondMenuBar"
    end

    assert_nil smoke.send(
      :assert_frontmost_did_not_revert_to,
      { 'bundleId' => 'com.apple.finder', 'windowTitle' => 'Desktop' },
      'right click browse icon'
    )
  end

  def test_browse_activation_pool_drops_coarse_duplicate_when_precise_rows_exist
    smoke = build_smoke
    zones = [
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.widget',
        unique_id: 'com.example.widget',
        name: 'Widget'
      },
      {
        zone: 'hidden',
        movable: true,
        bundle: 'com.example.widget',
        unique_id: 'com.example.widget::statusItem:1',
        name: 'Widget'
      }
    ]

    candidates = smoke.send(:browse_activation_pool, zones)
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal ['com.example.widget::statusItem:1'], candidate_ids
  end

  def test_prepare_layout_baseline_hides_expanded_runtime
    smoke = build_smoke
    called = []

    smoke.define_singleton_method(:close_browse_panel_safely) { called << :close_browse }
    smoke.define_singleton_method(:close_settings_window_safely) { called << :close_settings }
    smoke.define_singleton_method(:layout_snapshot) { { 'hidingState' => 'expanded' } }
    smoke.define_singleton_method(:supports_applescript_command?) { |command| command == 'hide' }
    smoke.define_singleton_method(:app_script) { |statement| called << statement }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| called << [:sleep, seconds] }

    smoke.send(:prepare_layout_baseline)

    assert_includes called, :close_browse
    assert_includes called, :close_settings
    assert_includes called, 'hide'
  end

  def test_diagnostics_reads_use_heavy_applescript_timeout
    smoke = build_smoke

    assert_equal LiveZoneSmoke::APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'browse panel diagnostics')
    assert_equal LiveZoneSmoke::APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'activation diagnostics')
  end

  def test_activation_commands_use_extended_applescript_timeout
    smoke = build_smoke

    assert_equal LiveZoneSmoke::APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'activate browse icon "com.example.app::statusItem:1"')
    assert_equal LiveZoneSmoke::APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS,
                 smoke.send(:app_script_timeout_for, 'right click browse icon "com.example.app::statusItem:1"')
  end

  def test_transient_process_missing_is_tolerated_while_pid_is_still_alive
    smoke = build_smoke

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
    refute smoke.send(:resource_watchdog_failure)
  end

  def test_zone_api_ready_retries_empty_zone_snapshots
    smoke = build_smoke
    attempts = 0
    zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.ready',
        unique_id: 'com.example.ready::statusItem:0',
        name: 'Ready'
      }
    ]

    smoke.define_singleton_method(:check_resource_watchdog!) {}
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) do
      attempts += 1
      raise 'No icons returned from list icon zones.' if attempts == 1

      zones
    end

    assert_equal zones, smoke.send(:wait_for_zone_api_ready)
    assert_equal 2, attempts
  end

  def test_post_move_zone_stability_rejects_delayed_zone_drift
    smoke = build_smoke
    candidate = {
      zone: 'visible',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end

    error = assert_raises(RuntimeError) do
      smoke.send(
        :assert_zone_stays_stable_after_move,
        'com.example.widget::statusItem:0',
        candidate,
        'visible'
      )
    end
    assert_match(/Post-settle move verification drifted/, error.message)
  end

  def test_post_move_zone_stability_accepts_same_zone_after_settle
    smoke = build_smoke
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'hidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end

    assert smoke.send(
      :assert_zone_stays_stable_after_move,
      'com.example.widget::statusItem:0',
      candidate,
      'hidden'
    )
  end

  def test_move_and_verify_retries_failed_move_after_settle
    smoke = build_smoke
    candidate = {
      zone: 'alwaysHidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    calls = []
    sleeps = []
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end
    smoke.define_singleton_method(:app_script) do |statement|
      calls << statement
      raise 'AppleScript failed: Icon failed to move to hidden.' if calls.length == 1

      "true\n"
    end
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| sleeps << seconds }
    smoke.define_singleton_method(:wait_for_move_ready_state) { true }
    smoke.define_singleton_method(:wait_for_zone) { |_icon_unique_id, _candidate, _expected_zone| true }
    smoke.define_singleton_method(:assert_zone_stays_stable_after_move) { |_icon_unique_id, _candidate, _expected_zone| true }

    smoke.send(:move_and_verify, 'move icon to hidden', candidate, 'hidden')

    assert_equal 2, calls.length
    assert_includes sleeps, 1.2
  end

  def test_move_readiness_waits_for_browse_and_menu_teardown
    smoke = build_smoke
    snapshots = [
      {
        'isMoveInProgress' => false,
        'isBrowseVisible' => true,
        'isBrowseSessionActive' => true,
        'isMenuOpen' => false
      },
      {
        'isMoveInProgress' => false,
        'isBrowseVisible' => false,
        'isBrowseSessionActive' => false,
        'isMenuOpen' => false
      }
    ]
    closed = []
    sleeps = []
    smoke.define_singleton_method(:close_browse_panel_safely) { closed << :browse }
    smoke.define_singleton_method(:close_settings_window_safely) { closed << :settings }
    smoke.define_singleton_method(:layout_snapshot) { snapshots.shift }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| sleeps << seconds }

    assert smoke.send(:wait_for_move_ready_state)
    assert_equal [:browse, :settings], closed
    assert_equal [0.25], sleeps
  end

  def test_always_hidden_outbound_move_gets_extra_settle
    smoke = build_smoke
    candidate = {
      zone: 'alwaysHidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    sleeps = []
    ready_calls = 0
    smoke.define_singleton_method(:list_icon_zones) do
      [
        {
          zone: 'alwaysHidden',
          movable: true,
          bundle: 'com.example.widget',
          unique_id: 'com.example.widget::statusItem:0',
          name: 'Widget'
        }
      ]
    end
    smoke.define_singleton_method(:wait_for_move_ready_state) { ready_calls += 1 }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| sleeps << seconds }

    assert smoke.send(:settle_before_always_hidden_outbound_move, candidate[:unique_id], candidate, 'hidden')
    assert_includes sleeps, LiveZoneSmoke::ALWAYS_HIDDEN_OUTBOUND_SETTLE_SECONDS
    assert_equal 1, ready_calls
  end

  def test_always_hidden_inbound_move_skips_extra_settle
    smoke = build_smoke
    candidate = {
      zone: 'hidden',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    smoke.define_singleton_method(:list_icon_zones) { raise 'should not inspect zones for inbound AH move' }
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| raise 'should not sleep for inbound AH move' }

    assert smoke.send(:settle_before_always_hidden_outbound_move, candidate[:unique_id], candidate, 'alwaysHidden')
  end

  def test_prepare_zones_for_move_checks_refreshes_live_zone_state
    smoke = build_smoke
    calls = []
    refreshed_zones = [
      {
        zone: 'visible',
        movable: true,
        bundle: 'com.example.visible',
        unique_id: 'com.example.visible::statusItem:0',
        name: 'Visible'
      }
    ]
    smoke.define_singleton_method(:close_browse_panel_safely) { calls << :close_browse }
    smoke.define_singleton_method(:close_settings_window_safely) { calls << :close_settings }
    smoke.define_singleton_method(:prepare_layout_baseline) { calls << :prepare_layout }
    smoke.define_singleton_method(:wait_for_stable_layout_snapshot) { calls << :wait_layout }
    smoke.define_singleton_method(:sleep_with_watchdog) { |seconds| calls << [:sleep, seconds] }
    smoke.define_singleton_method(:list_icon_zones) { calls << :list_zones; refreshed_zones }
    smoke.define_singleton_method(:require_representative_zone_candidates!) { |zones| calls << [:require_zones, zones] }

    assert_same refreshed_zones, smoke.send(:prepare_zones_for_move_checks)
    assert_equal [
      :close_browse,
      :close_settings,
      :prepare_layout,
      :wait_layout,
      [:sleep, 1.5],
      :list_zones,
      [:require_zones, refreshed_zones]
    ], calls
  end

  def test_hidden_always_hidden_round_trip_uses_exact_customer_sequence
    smoke = build_smoke
    candidate = {
      zone: 'visible',
      movable: true,
      bundle: 'com.example.widget',
      unique_id: 'com.example.widget::statusItem:0',
      name: 'Widget'
    }
    calls = []
    smoke.define_singleton_method(:move_and_verify) do |command, move_candidate, expected_zone|
      calls << [command, move_candidate.fetch(:unique_id), expected_zone]
    end

    smoke.send(:exercise_hidden_always_hidden_round_trip, candidate)

    assert_equal [
      ['move icon to hidden', 'com.example.widget::statusItem:0', 'hidden'],
      ['move icon to always hidden', 'com.example.widget::statusItem:0', 'alwaysHidden'],
      ['move icon to hidden', 'com.example.widget::statusItem:0', 'hidden']
    ], calls
  end

  def test_launch_idle_budget_accepts_small_peak_only_cpu_spike
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:capture_resource_window) do |sample_seconds:, interval_seconds:|
      {
        avg_cpu: 3.9,
        peak_cpu: 16.9,
        avg_rss_mb: 57.6,
        peak_rss_mb: 57.6
      }
    end

    smoke.send(
      :assert_idle_budget!,
      label: 'launch',
      settle_seconds: 0,
      sample_seconds: 3.0,
      cpu_avg_max: 5.0,
      cpu_peak_max: 15.0,
      rss_mb_max: 128.0
    )
  end

  def test_launch_idle_budget_still_rejects_sustained_cpu_overrun
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:capture_resource_window) do |sample_seconds:, interval_seconds:|
      {
        avg_cpu: 5.5,
        peak_cpu: 16.9,
        avg_rss_mb: 57.6,
        peak_rss_mb: 57.6
      }
    end

    assert_raises(RuntimeError) do
      smoke.send(
        :assert_idle_budget!,
        label: 'launch',
        settle_seconds: 0,
        sample_seconds: 3.0,
        cpu_avg_max: 5.0,
        cpu_peak_max: 15.0,
        rss_mb_max: 128.0
      )
    end
  end

  def test_post_smoke_idle_budget_accepts_rss_cache_when_physical_footprint_is_within_budget
    smoke = build_smoke
    smoke.define_singleton_method(:sleep_with_watchdog) { |_seconds| }
    smoke.define_singleton_method(:capture_resource_window) do |sample_seconds:, interval_seconds:|
      {
        avg_cpu: 0.3,
        peak_cpu: 0.5,
        avg_rss_mb: 196.7,
        peak_rss_mb: 196.7
      }
    end
    smoke.define_singleton_method(:current_physical_footprint_mb) { 129.0 }

    smoke.send(
      :assert_idle_budget!,
      label: 'post-smoke',
      settle_seconds: 0,
      sample_seconds: 4.0,
      cpu_avg_max: 5.0,
      cpu_peak_max: 20.0,
      rss_mb_max: 160.0
    )
  end

  def test_active_average_budget_skips_too_few_samples
    smoke = build_smoke
    state = smoke.instance_variable_get(:@resource_watchdog_state)
    state[:sample_count] = LiveZoneSmoke::DEFAULT_ACTIVE_AVG_MIN_SAMPLES - 1
    state[:total_cpu] = 999.0
    state[:total_rss_mb] = 999.0

    smoke.send(:assert_active_average_budget!)
  end

  def test_active_average_budget_rejects_sustained_cpu_after_minimum_samples
    smoke = build_smoke
    state = smoke.instance_variable_get(:@resource_watchdog_state)
    state[:sample_count] = LiveZoneSmoke::DEFAULT_ACTIVE_AVG_MIN_SAMPLES
    state[:total_cpu] = (LiveZoneSmoke::DEFAULT_ACTIVE_AVG_CPU_MAX + 1.0) * state[:sample_count]
    state[:total_rss_mb] = 50.0 * state[:sample_count]

    assert_raises(RuntimeError) do
      smoke.send(:assert_active_average_budget!)
    end
  end

  def test_repeated_process_missing_stops_after_tolerance
    smoke = build_smoke

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
    refute smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
  end

  def test_process_missing_is_tolerated_when_same_pid_is_still_visible_in_full_process_table
    smoke = build_smoke
    smoke.define_singleton_method(:app_process_still_alive?) { false }
    smoke.define_singleton_method(:current_app_process_visible?) { true }

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
  end

  def test_process_missing_is_not_tolerated_when_pid_is_gone_everywhere
    smoke = build_smoke
    smoke.define_singleton_method(:app_process_still_alive?) { false }
    smoke.define_singleton_method(:current_app_process_visible?) { false }

    refute smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
  end
end
