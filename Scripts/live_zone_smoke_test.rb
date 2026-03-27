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

  def test_required_ids_enable_focused_smoke_mode
    smoke = build_smoke(required_ids: ['com.apple.menuextra.focusmode'])

    assert smoke.send(:focused_required_id_mode?)
  end

  def test_default_smoke_does_not_require_move_candidates
    smoke = build_smoke

    refute smoke.send(:move_candidates_required?)
  end

  def test_required_id_smoke_requires_move_candidates
    smoke = build_smoke(required_ids: ['com.apple.menuextra.focusmode'])

    assert smoke.send(:move_candidates_required?)
  end

  def test_browse_activation_candidates_prefer_curated_fixtures_and_skip_menumeters
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
      }
    ]

    candidates = smoke.send(:browse_activation_candidates, zones)
    candidate_ids = candidates.map { |candidate| candidate[:unique_id] }

    assert_equal 'com.apple.SSMenuAgent', candidate_ids.first
    assert_includes candidate_ids, 'com.apple.menuextra.display'
    assert_includes candidate_ids, 'com.example.precise::statusItem:2'
    refute_includes candidate_ids, 'com.yujitach.MenuMeters::statusItem:3'
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

  def test_transient_process_missing_is_tolerated_while_pid_is_still_alive
    smoke = build_smoke

    assert smoke.send(:tolerate_process_monitor_error?, RuntimeError.new('process_missing'))
    refute smoke.send(:resource_watchdog_failure)
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
