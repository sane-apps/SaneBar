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
