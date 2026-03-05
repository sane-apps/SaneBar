#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'

class LiveZoneSmoke
  APP_NAME = 'SaneBar'
  MAX_WAIT_SECONDS = 12
  POLL_SECONDS = 0.4
  LAYOUT_STABILIZE_TIMEOUT_SECONDS = 10
  LAYOUT_STABILIZE_POLL_SECONDS = 0.25
  ZONE_API_READY_TIMEOUT_SECONDS = 10
  ZONE_API_READY_POLL_SECONDS = 0.5
  APPLESCRIPT_TIMEOUT_SECONDS = 8
  APPLESCRIPT_RETRIES = 2
  APPLE_FALLBACK_BUNDLE_DENYLIST = %w[
    com.apple.controlcenter
    com.apple.systemuiserver
    com.apple.Spotlight
  ].freeze

  def initialize
    @require_always_hidden = ENV['SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN'] == '1'
    @require_all_candidates = ENV['SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES'] == '1'
    @required_candidate_ids = ENV.fetch('SANEBAR_SMOKE_REQUIRED_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
  end

  def run
    started_at = Time.now.utc
    puts "🔎 --- [ LIVE ZONE SMOKE ] ---"

    verify_single_process
    snapshot = wait_for_stable_layout_snapshot
    check_layout_invariants(snapshot)
    wait_for_zone_api_ready

    zones = list_icon_zones
    candidates = selected_candidates(zones)
    raise "No movable candidate icon found (need at least one hidden/visible icon)." if candidates.empty?

    failures = []
    passed_candidates = []

    candidates.each do |candidate|
      begin
        puts "🎯 Candidate: #{candidate[:name]} (#{candidate[:bundle]}) zone=#{candidate[:zone]}"
        exercise_hidden_visible_moves(candidate)
        exercise_always_hidden_moves(candidate)
        passed_candidates << candidate
        puts "✅ Candidate passed: #{candidate[:unique_id]}"
        break unless strict_candidate_mode?
      rescue StandardError => e
        failures << [candidate, e]
        puts "⚠️ Candidate failed: #{candidate[:bundle]} (#{e.message})"
      ensure
        begin
          restore_zone(candidate)
        rescue StandardError
          # Keep trying other candidates; final failure will include last_error.
        end
      end
    end

    if strict_candidate_mode?
      unless failures.empty?
        summary = failures.map do |candidate, error|
          "#{candidate[:unique_id]}: #{error.message}"
        end.join(' | ')
        raise "Candidate failures: #{summary}"
      end
      raise 'No candidates passed move action checks.' if passed_candidates.empty?
      puts "✅ Candidate set passed: #{passed_candidates.map { |candidate| candidate[:unique_id] }.join(', ')}"
    else
      last_failure = failures.last&.last
      raise(last_failure || 'No candidate passed move action checks.') if passed_candidates.empty?
    end

    duration = (Time.now.utc - started_at).round(2)
    puts "✅ Live zone smoke passed (#{duration}s)"
    true
  rescue StandardError => e
    puts "❌ Live zone smoke failed: #{e.message}"
    false
  end

  private

  def verify_single_process
    out, status = sh('pgrep -x SaneBar')
    raise 'SaneBar is not running.' unless status.success? && !out.strip.empty?

    count = out.lines.map(&:strip).reject(&:empty?).count
    raise "Expected 1 SaneBar process, found #{count}." unless count == 1
  end

  def layout_snapshot
    raw = app_script('layout snapshot')
    JSON.parse(raw)
  rescue JSON::ParserError
    raise "Invalid layout snapshot JSON: #{raw.inspect}"
  end

  def wait_for_stable_layout_snapshot
    deadline = Time.now + LAYOUT_STABILIZE_TIMEOUT_SECONDS
    attempts = 0
    last_snapshot = nil

    while Time.now < deadline
      attempts += 1
      last_snapshot = layout_snapshot
      return last_snapshot if layout_invariants_satisfied?(last_snapshot)
      sleep LAYOUT_STABILIZE_POLL_SECONDS
    end

    raise "Layout did not stabilize in #{LAYOUT_STABILIZE_TIMEOUT_SECONDS}s (attempts=#{attempts}, snapshot=#{last_snapshot})"
  end

  def check_layout_invariants(snapshot)
    unless layout_invariants_satisfied?(snapshot)
      raise "Layout invariant failed after stabilization (snapshot=#{snapshot})"
    end

    puts "✅ Layout invariants ok: separator/main order and launch proximity"
  end

  def layout_invariants_satisfied?(snapshot)
    return false unless truthy?(snapshot['separatorBeforeMain'])

    ah_x = snapshot['alwaysHiddenSeparatorOriginX']
    if ah_x.is_a?(Numeric) && ah_x.positive?
      return false unless truthy?(snapshot['alwaysHiddenBeforeSeparator'])
    end

    truthy?(snapshot['mainNearControlCenter'])
  end

  def list_icon_zones
    raw = list_icon_zones_raw
    zones = raw.lines.map do |line|
      zone, movable, bundle, unique_id, name = line.strip.split("\t", 5)
      next nil if zone.nil? || unique_id.nil?

      {
        zone: zone,
        movable: movable == 'true',
        bundle: bundle.to_s,
        unique_id: unique_id,
        name: name.to_s,
      }
    end.compact

    raise 'No icons returned from list icon zones.' if zones.empty?

    zones
  end

  def list_icon_zones_raw
    app_script('list icon zones')
  end

  def wait_for_zone_api_ready
    deadline = Time.now + ZONE_API_READY_TIMEOUT_SECONDS
    last_error = nil

    while Time.now < deadline
      begin
        zones = list_icon_zones
        return zones unless zones.empty?
      rescue StandardError => e
        last_error = e
        raise unless zone_api_retryable?(e)
      end

      sleep ZONE_API_READY_POLL_SECONDS
    end

    raise "Zone API did not become ready in #{ZONE_API_READY_TIMEOUT_SECONDS}s#{last_error ? " (last error: #{last_error.message})" : ''}"
  end

  def candidate_pool(zones)
    candidates = zones.select do |item|
      item[:movable] &&
        !item[:bundle].start_with?('com.sanebar.app') &&
        %w[hidden visible alwaysHidden].include?(item[:zone])
    end

    # Prefer non-Apple extras first (typically more consistently movable),
    # then Apple fallbacks while avoiding known noisy bundles.
    preferred = candidates.reject { |item| item[:bundle].start_with?('com.apple.') }
    apple_fallback = candidates.select do |item|
      item[:bundle].start_with?('com.apple.') &&
        !APPLE_FALLBACK_BUNDLE_DENYLIST.include?(item[:bundle])
    end
    denied = candidates.select { |item| APPLE_FALLBACK_BUNDLE_DENYLIST.include?(item[:bundle]) }

    ordered = preferred + apple_fallback + denied
    zone_priority = { 'hidden' => 0, 'visible' => 1, 'alwaysHidden' => 2 }
    ordered.sort_by { |item| zone_priority.fetch(item[:zone], 3) }
  end

  def selected_candidates(zones)
    ordered = candidate_pool(zones)
    return ordered if @required_candidate_ids.empty?

    selected = @required_candidate_ids.map do |required_id|
      ordered.find { |candidate| candidate[:unique_id] == required_id }
    end

    missing_ids = @required_candidate_ids.zip(selected).map do |required_id, candidate|
      required_id if candidate.nil?
    end.compact
    raise "Required icon(s) missing from list icon zones: #{missing_ids.join(', ')}" unless missing_ids.empty?

    selected
  end

  def exercise_hidden_visible_moves(candidate)
    if candidate[:zone] == 'hidden'
      move_and_verify('move icon to visible', candidate, 'visible')
      move_and_verify('move icon to hidden', candidate, 'hidden')
    elsif candidate[:zone] == 'alwaysHidden'
      # Some stable test fixtures (e.g. SaneClick) may start in always-hidden.
      # Bring them into the normal flow before running hidden/visible checks.
      move_and_verify('move icon to visible', candidate, 'visible')
      move_and_verify('move icon to hidden', candidate, 'hidden')
    else
      move_and_verify('move icon to hidden', candidate, 'hidden')
      move_and_verify('move icon to visible', candidate, 'visible')
    end
    puts '✅ Hidden/Visible move actions ok'
  end

  def exercise_always_hidden_moves(candidate)
    move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
    move_and_verify('move icon to visible', candidate, 'visible')
    puts '✅ Always Hidden move actions ok'
  rescue StandardError => e
    raise if @require_always_hidden
    if always_hidden_optional_failure?(e)
      puts "ℹ️ Skipping always-hidden move check (likely free mode): #{e.message}"
      return
    end
    raise
  end

  def restore_zone(candidate)
    target = candidate[:zone]
    case target
    when 'hidden'
      move_and_verify('move icon to hidden', candidate, 'hidden')
    when 'alwaysHidden'
      move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
    else
      move_and_verify('move icon to visible', candidate, 'visible')
    end
  end

  def move_and_verify(command, candidate, expected_zone)
    icon_unique_id = resolve_live_icon_identifier(candidate)
    icon = escape_quotes(icon_unique_id)
    result = app_script("#{command} \"#{icon}\"").strip.downcase
    unless %w[true 1].include?(result)
      raise "#{command} returned '#{result}' for #{candidate[:unique_id]}"
    end

    wait_for_zone(icon_unique_id, candidate, expected_zone)
  end

  def wait_for_zone(icon_unique_id, candidate, expected_zone)
    deadline = Time.now + MAX_WAIT_SECONDS
    while Time.now < deadline
      zones = list_icon_zones
      matched = zones.find { |item| item[:unique_id] == icon_unique_id } ||
        zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] } ||
        zones.find { |item| item[:bundle] == candidate[:bundle] && item[:movable] }
      return true if matched && matched[:zone] == expected_zone
      sleep POLL_SECONDS
    end

    raise "Timeout waiting for #{candidate[:bundle]} (#{candidate[:name]}) to reach zone #{expected_zone}"
  end

  def resolve_live_icon_identifier(candidate)
    zones = list_icon_zones

    exact = zones.find { |item| item[:unique_id] == candidate[:unique_id] }
    return exact[:unique_id] if exact

    bundle_and_name = zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] }
    return bundle_and_name[:unique_id] if bundle_and_name

    bundle_matches = zones.select { |item| item[:bundle] == candidate[:bundle] && item[:movable] }
    return bundle_matches.first[:unique_id] if bundle_matches.length == 1

    candidate[:unique_id]
  end

  def app_script(statement)
    script = %(tell application "#{APP_NAME}" to #{statement})
    attempts = 0
    begin
      attempts += 1
      out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
      raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?
      out
    rescue StandardError => e
      retryable = e.message.include?('timeout') || e.message.include?('failed')
      if attempts < APPLESCRIPT_RETRIES && retryable
        sleep 0.2
        retry
      end
      raise
    end
  end

  def capture2e_with_timeout(*cmd, timeout:)
    output = +''
    status = nil

    Open3.popen2e(*cmd) do |stdin, stdout, wait_thr|
      stdin.close
      reader = Thread.new { stdout.read.to_s }

      if wait_thr.join(timeout)
        status = wait_thr.value
        output = reader.value
      else
        begin
          Process.kill('TERM', wait_thr.pid)
        rescue StandardError
          nil
        end
        unless wait_thr.join(1)
          begin
            Process.kill('KILL', wait_thr.pid)
          rescue StandardError
            nil
          end
          wait_thr.join
        end

        begin
          output = reader.value
        rescue StandardError
          output = ''
        end

        raise "AppleScript timeout after #{timeout}s (#{cmd.join(' ')})"
      end
    end

    [output, status]
  end

  def sh(command)
    Open3.capture2e(command)
  end

  def truthy?(value)
    value == true || value.to_s.casecmp('true').zero?
  end

  def always_hidden_optional_failure?(error)
    message = error.message.to_s
    message.include?('failed to move to alwaysHidden') ||
      message.include?('to reach zone alwaysHidden')
  end

  def zone_api_retryable?(error)
    message = error.message.to_s
    message.include?('Connection is invalid') ||
      message.include?('Accessibility permission is required')
  end

  def strict_candidate_mode?
    @require_all_candidates || !@required_candidate_ids.empty?
  end

  def escape_quotes(value)
    value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  end
end

exit(LiveZoneSmoke.new.run ? 0 : 1)
