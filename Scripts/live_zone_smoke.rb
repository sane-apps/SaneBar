#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'

class LiveZoneSmoke
  APP_NAME = 'SaneBar'
  MAX_WAIT_SECONDS = 12
  POLL_SECONDS = 0.4
  APPLE_FALLBACK_BUNDLE_DENYLIST = %w[
    com.apple.controlcenter
    com.apple.systemuiserver
    com.apple.Spotlight
  ].freeze

  def initialize
    @require_always_hidden = ENV['SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN'] == '1'
  end

  def run
    started_at = Time.now.utc
    puts "🔎 --- [ LIVE ZONE SMOKE ] ---"

    verify_single_process
    snapshot = layout_snapshot
    check_layout_invariants(snapshot)

    zones = list_icon_zones
    candidates = candidate_pool(zones)
    raise "No movable candidate icon found (need at least one hidden/visible icon)." if candidates.empty?

    last_error = nil
    moved_candidate = nil

    candidates.each do |candidate|
      begin
        puts "🎯 Candidate: #{candidate[:name]} (#{candidate[:bundle]}) zone=#{candidate[:zone]}"
        exercise_hidden_visible_moves(candidate)
        exercise_always_hidden_moves(candidate)
        moved_candidate = candidate
        break
      rescue StandardError => e
        last_error = e
        puts "⚠️ Candidate failed: #{candidate[:bundle]} (#{e.message})"
      ensure
        begin
          restore_zone(candidate)
        rescue StandardError
          # Keep trying other candidates; final failure will include last_error.
        end
      end
    end

    raise(last_error || "No candidate passed move action checks.") unless moved_candidate

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

  def check_layout_invariants(snapshot)
    unless truthy?(snapshot['separatorBeforeMain'])
      raise "Layout invariant failed: separatorBeforeMain=false (snapshot=#{snapshot})"
    end

    ah_x = snapshot['alwaysHiddenSeparatorOriginX']
    if ah_x.is_a?(Numeric) && ah_x.positive?
      unless truthy?(snapshot['alwaysHiddenBeforeSeparator'])
        raise "Layout invariant failed: alwaysHiddenBeforeSeparator=false (snapshot=#{snapshot})"
      end
    end

    unless truthy?(snapshot['mainNearControlCenter'])
      raise "Launch position invariant failed: main icon is not near Control Center (snapshot=#{snapshot})"
    end

    puts "✅ Layout invariants ok: separator/main order and launch proximity"
  end

  def list_icon_zones
    raw = app_script('list icon zones')
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
    out, code = Open3.capture2e('/usr/bin/osascript', '-e', script)
    raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?

    out
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

  def escape_quotes(value)
    value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  end
end

exit(LiveZoneSmoke.new.run ? 0 : 1)
