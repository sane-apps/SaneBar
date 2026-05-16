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
end
