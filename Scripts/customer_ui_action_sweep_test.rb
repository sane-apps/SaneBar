#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'customer_ui_action_sweep'

class CustomerUIActionSweepTest < Minitest::Test
  def setup
    @sweep = CustomerUIActionSweep.new
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
    error = assert_raises(RuntimeError) do
      @sweep.send(:screenshot_for_action, 'appearance-customization-actions')
    end

    assert_includes error.message, 'no usable appearance overlay screenshot evidence'
  end

  def test_runtime_state_results_read_artifact_backed_evidence_paths
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
  end
end
