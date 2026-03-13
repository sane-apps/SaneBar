#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'qa'

class ProjectQATest < Minitest::Test
  def setup
    @qa = ProjectQA.new
  end

  def test_reporter_confirmation_accepts_plain_working_reply
    assert @qa.send(:reporter_confirmation_text?, "It's working. The updates are a bit slow in the UI but that's ok.")
  end

  def test_reporter_confirmation_rejects_negative_reply
    refute @qa.send(:reporter_confirmation_text?, "It's not working. The same problem is still happening.")
  end

  def test_stale_open_regression_after_release_when_quiet_for_five_days
    release = { 'tagName' => 'v2.1.26', 'publishedAt' => '2026-03-01T12:00:00Z' }
    issue = {
      'number' => 94,
      'createdAt' => '2026-02-28T17:44:05Z',
      'updatedAt' => '2026-03-01T11:59:59Z'
    }

    assert @qa.send(:stale_open_regression_after_release?, issue, release, now: Time.parse('2026-03-06T12:00:01Z'))
  end

  def test_stale_open_regression_waits_until_five_day_mark
    release = { 'tagName' => 'v2.1.26', 'publishedAt' => '2026-03-01T12:00:00Z' }
    issue = {
      'number' => 94,
      'createdAt' => '2026-02-28T17:44:05Z',
      'updatedAt' => '2026-03-01T11:59:59Z'
    }

    refute @qa.send(:stale_open_regression_after_release?, issue, release, now: Time.parse('2026-03-05T23:59:59Z'))
  end

  def test_stale_open_regression_rejects_issue_updated_after_release
    release = { 'tagName' => 'v2.1.26', 'publishedAt' => '2026-03-01T12:00:00Z' }
    issue = {
      'number' => 94,
      'createdAt' => '2026-02-28T17:44:05Z',
      'updatedAt' => '2026-03-02T09:00:00Z'
    }

    refute @qa.send(:stale_open_regression_after_release?, issue, release, now: Time.parse('2026-03-07T12:00:00Z'))
  end

  def test_runtime_smoke_retryable_failure_matches_launch_idle_budget_spike
    assert @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: launch_idle_budget_exceeded peakCpu=15.9% > 15.0%')
  end

  def test_runtime_smoke_retryable_failure_rejects_real_smoke_failures
    refute @qa.send(:retryable_runtime_smoke_failure?, '❌ Live zone smoke failed: Required icon(s) missing from list icon zones')
  end
end
