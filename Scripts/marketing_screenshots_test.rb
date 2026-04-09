#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

require_relative 'marketing_screenshots'

class MarketingScreenshotsTest < Minitest::Test
  def with_env(overrides)
    original = {}
    overrides.each_key do |key|
      original[key] = ENV.key?(key) ? ENV[key] : :__missing__
    end

    overrides.each { |key, value| ENV[key] = value }
    ENV['SANEBAR_SCREENSHOT_RESET_CACHE'] = '1'
    yield
  ensure
    overrides.each_key do |key|
      if original[key] == :__missing__
        ENV.delete(key)
      else
        ENV[key] = original[key]
      end
    end
    ENV.delete('SANEBAR_SCREENSHOT_RESET_CACHE')
  end

  def test_run_cli_returns_failure_for_unknown_shot
    Dir.mktmpdir do |dir|
      status = with_env(
        'SANEBAR_SCREENSHOT_OUTPUT_DIR' => dir,
        'SANEBAR_SCREENSHOT_SKIP_SYNC' => '1',
        'SANEBAR_SCREENSHOT_TOOL' => '/usr/bin/true'
      ) do
        run_cli(['--shot', 'not-a-real-shot'])
      end

      assert_equal 1, status
    end
  end

  def test_run_cli_returns_failure_when_capture_command_fails
    Dir.mktmpdir do |dir|
      status = with_env(
        'SANEBAR_SCREENSHOT_OUTPUT_DIR' => dir,
        'SANEBAR_SCREENSHOT_SKIP_SYNC' => '1',
        'SANEBAR_SCREENSHOT_TOOL' => '/usr/bin/false'
      ) do
        run_cli(['--shot', 'settings-general'])
      end

      assert_equal 1, status
      refute File.exist?(File.join(dir, 'settings-general.png'))
    end
  end
end
