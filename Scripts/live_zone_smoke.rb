#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
require 'time'
require 'tmpdir'

class LiveZoneSmoke
  APP_NAME = 'SaneBar'
  MAX_WAIT_SECONDS = 12
  POLL_SECONDS = 0.4
  LAYOUT_STABILIZE_TIMEOUT_SECONDS = 10
  LAYOUT_STABILIZE_POLL_SECONDS = 0.25
  ZONE_API_READY_TIMEOUT_SECONDS = 10
  ZONE_API_READY_POLL_SECONDS = 0.5
  APPLESCRIPT_TIMEOUT_SECONDS = 8
  APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS = 20
  APPLESCRIPT_RETRIES = 2
  BROWSE_PANEL_READY_TIMEOUT_SECONDS = 10
  BROWSE_PANEL_READY_POLL_SECONDS = 0.25
  BROWSE_ACTIVATION_COOLDOWN_SECONDS = 0.6
  SCREENSHOT_CAPTURE_TIMEOUT_SECONDS = 20
  APPLE_FALLBACK_BUNDLE_DENYLIST = %w[
    com.apple.controlcenter
    com.apple.systemuiserver
    com.apple.Spotlight
  ].freeze
  BROWSE_PANEL_COMMANDS = {
    'secondMenuBar' => 'show second menu bar',
    'findIcon' => 'open icon panel',
  }.freeze
  PREFERRED_BROWSE_ACTIVATION_IDS = %w[
    com.apple.menuextra.wifi
    com.apple.menuextra.spotlight
    com.apple.SSMenuAgent
    com.apple.controlcenter
  ].freeze
  STANDARD_APP_MENU_TITLES = %w[
    apple
    file
    edit
    view
    window
    help
  ].freeze

  def initialize
    @app_name = env_string('SANEBAR_SMOKE_APP_NAME') || APP_NAME
    @app_id = env_string('SANEBAR_SMOKE_APP_ID')
    @app_path = expand_env_path('SANEBAR_SMOKE_APP_PATH')
    @process_path = expand_env_path('SANEBAR_SMOKE_PROCESS_PATH')
    @require_always_hidden = ENV['SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN'] == '1'
    @require_all_candidates = ENV['SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES'] == '1'
    @capture_screenshots = ENV.fetch('SANEBAR_SMOKE_CAPTURE_SCREENSHOTS', '1') != '0'
    @screenshot_dir = expand_env_path('SANEBAR_SMOKE_SCREENSHOT_DIR') || File.join(Dir.tmpdir, 'sanebar-smoke')
    @required_candidate_ids = ENV.fetch('SANEBAR_SMOKE_REQUIRED_IDS', '')
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
    @supported_applescript_commands = detect_supported_applescript_commands
  end

  def run
    started_at = Time.now.utc
    puts "🔎 --- [ LIVE ZONE SMOKE ] ---"

    verify_single_process
    snapshot = wait_for_stable_layout_snapshot
    check_layout_invariants(snapshot)
    wait_for_zone_api_ready

    zones = list_icon_zones
    exercise_browse_modes(zones)
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
    out, status = sh('ps ax -o pid=,command=')
    raise "#{@app_name} process list could not be read." unless status.success?

    matches = out.lines.map(&:strip).reject(&:empty?).each_with_object([]) do |line, result|
      pid, command = line.split(/\s+/, 2)
      next unless pid && command
      next unless matching_app_process?(command)

      result << "#{pid} #{command}"
    end

    raise "#{@app_name} is not running at #{expected_process_path || @app_name}." if matches.empty?
    return if matches.length == 1

    details = matches.join(' | ')
    raise "Expected 1 #{@app_name} process, found #{matches.length}: #{details}"
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

    if truthy?(snapshot['alwaysHiddenGeometryReliable'])
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
    raw_candidates = zones.select do |item|
      item[:movable] &&
        !item[:bundle].start_with?('com.sanebar.app') &&
        %w[hidden visible alwaysHidden].include?(item[:zone])
    end
    excluded_app_menu_bundles = app_menu_bundle_ids(raw_candidates)
    candidates = raw_candidates.reject do |item|
      likely_standard_app_menu_candidate?(item) ||
        excluded_app_menu_bundles.include?(item[:bundle].to_s.downcase)
    end
    precise_bundles = candidates.reject { |item| coarse_bundle_fallback?(item) }.map { |item| item[:bundle] }.uniq
    candidates.reject! do |item|
      coarse_bundle_fallback?(item) && precise_bundles.include?(item[:bundle])
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

  def app_menu_bundle_ids(candidates)
    candidates.group_by { |item| item[:bundle].to_s.downcase }.each_with_object([]) do |(bundle, bundle_candidates), excluded|
      next if bundle.empty? || bundle.start_with?('com.apple.')

      titles = bundle_candidates.map { |candidate| candidate[:name].to_s.strip.downcase }
      excluded << bundle if (titles & STANDARD_APP_MENU_TITLES).length >= 3
    end
  end

  def likely_standard_app_menu_candidate?(item)
    title = item[:name].to_s.strip.downcase
    return false unless STANDARD_APP_MENU_TITLES.include?(title)

    identifier = item[:unique_id].to_s.downcase
    bundle = item[:bundle].to_s.downcase
    !bundle.start_with?('com.apple.') && (identifier.include?('.menuextra.') || identifier.include?('::axid:'))
  end

  def selected_candidates(zones)
    ordered = candidate_pool(zones)
    return ordered if @required_candidate_ids.empty?

    selected = @required_candidate_ids.map do |required_id|
      resolve_required_candidate(required_id, ordered)
    end

    missing_ids = @required_candidate_ids.zip(selected).map do |required_id, candidate|
      required_id if candidate.nil?
    end.compact
    raise "Required icon(s) missing from list icon zones: #{missing_ids.join(', ')}" unless missing_ids.empty?

    selected
  end

  def resolve_required_candidate(required_id, ordered)
    exact = ordered.find { |candidate| candidate[:unique_id] == required_id }
    return exact if exact

    bundle_id = required_id.split('::', 2).first
    return nil if bundle_id.nil? || bundle_id.empty?

    bundle_matches = ordered.select { |candidate| candidate[:bundle] == bundle_id }
    return bundle_matches.first if bundle_matches.length == 1

    nil
  end

  def exercise_browse_modes(zones)
    BROWSE_PANEL_COMMANDS.each do |expected_mode, command|
      unless supports_applescript_command?(command)
        puts "ℹ️ Skipping #{expected_mode}: running app does not expose '#{command}'"
        next
      end

      if full_browse_activation_supported?
        activation_candidates = browse_activation_candidates(zones)
        raise 'No browse activation candidate icon found.' if activation_candidates.empty?
        exercise_browse_mode(expected_mode: expected_mode, command: command, candidates: activation_candidates)
      else
        puts "ℹ️ Compatibility browse check for #{expected_mode}: activation diagnostics unavailable in running app"
        exercise_compatibility_browse_mode(expected_mode: expected_mode, command: command)
      end
    end
  end

  def full_browse_activation_supported?
    [
      'browse panel diagnostics',
      'activate browse icon',
      'right click browse icon',
    ].all? { |command| supports_applescript_command?(command) }
  end

  def browse_activation_candidates(zones)
    preferred = PREFERRED_BROWSE_ACTIVATION_IDS.map do |preferred_id|
      zones.find { |item| browse_candidate_matches?(item, preferred_id) }
    end.compact.uniq { |item| item[:unique_id] }

    fallback = candidate_pool(zones).sort_by do |item|
      [
        browse_zone_priority(item[:zone]),
        coarse_bundle_fallback?(item) ? 1 : 0,
      ]
    end
    (preferred + fallback).uniq { |item| item[:unique_id] }.take(3)
  end

  def browse_zone_priority(zone)
    case zone
    when 'visible' then 0
    when 'hidden' then 1
    else 2
    end
  end

  def coarse_bundle_fallback?(item)
    item[:unique_id].to_s == item[:bundle].to_s
  end

  def browse_candidate_matches?(item, preferred_id)
    values = [item[:unique_id], item[:bundle], item[:name]].compact.map(&:downcase)
    target = preferred_id.downcase
    values.any? { |value| value == target || value.include?(target) }
  end

  def exercise_browse_mode(expected_mode:, command:, candidates:)
    result = app_script(command).strip.downcase
    unless %w[true 1].include?(result)
      raise "#{command} returned '#{result}'"
    end

    wait_for_browse_panel(expected_mode)
    live_candidates = browse_activation_candidates(list_icon_zones)
    raise "No browse activation candidate icon found in #{expected_mode} after panel open." if live_candidates.empty?
    screenshot_path = capture_browse_screenshot(expected_mode) if @capture_screenshots
    puts "📸 #{expected_mode} screenshot: #{screenshot_path}" if screenshot_path

    exercise_browse_activation('activate browse icon', expected_mode, live_candidates)
    # SearchService debounces duplicate activation of the same icon for 450ms.
    # Leave enough headroom before immediately retrying that tile with right-click.
    sleep BROWSE_ACTIVATION_COOLDOWN_SECONDS
    exercise_browse_activation('right click browse icon', expected_mode, live_candidates)
    close_browse_panel
    puts "✅ Browse mode #{expected_mode} activation ok"
  ensure
    close_browse_panel_safely
  end

  def exercise_compatibility_browse_mode(expected_mode:, command:)
    result = app_script(command).strip.downcase
    unless %w[true 1].include?(result)
      raise "#{command} returned '#{result}'"
    end

    sleep 1.0
    screenshot_path = capture_browse_screenshot(expected_mode) if @capture_screenshots
    puts "📸 #{expected_mode} screenshot: #{screenshot_path}" if screenshot_path
    close_browse_panel
    puts "✅ Browse mode #{expected_mode} open/close ok"
  ensure
    close_browse_panel_safely
  end

  def exercise_browse_activation(command, expected_mode, candidates)
    failures = []

    candidates.each do |candidate|
      live_identifier = resolve_live_icon_identifier(candidate)
      baseline_diagnostics = current_browse_activation_diagnostics
      diagnostics = app_script(%(#{command} "#{escape_quotes(live_identifier)}"))
      return if browse_activation_succeeded?(diagnostics, expected_mode)

      failures << "#{candidate[:unique_id]} => #{browse_activation_failure_summary(diagnostics)}"
    rescue StandardError => e
      salvaged = salvage_timed_out_browse_activation(
        live_identifier: live_identifier,
        baseline_diagnostics: baseline_diagnostics,
        error: e
      )
      return if salvaged && browse_activation_succeeded?(salvaged, expected_mode)

      failures << "#{candidate[:unique_id]} => #{e.message}"
    end

    raise "#{command} failed in #{expected_mode}: #{failures.join(' | ')}"
  end

  def browse_activation_succeeded?(diagnostics, expected_mode)
    diagnostics.include?("origin: browsePanel") &&
      diagnostics.include?("finalOutcome: click succeeded") &&
      browse_activation_observably_verified?(diagnostics) &&
      diagnostics.include?("currentMode: #{expected_mode}") &&
      (
        diagnostics.include?('windowVisible: true') ||
        diagnostics.include?('windowVisible: false')
      )
  end

  def browse_activation_observably_verified?(diagnostics)
    diagnostics.lines.any? do |line|
      stripped = line.strip
      next false unless stripped.start_with?('firstAttempt:', 'retryAttempt:')

      stripped.include?('accepted=true') &&
        stripped.include?('verification=verified')
    end
  end

  def browse_activation_failure_summary(diagnostics)
    interesting = diagnostics.lines.map(&:strip).select do |line|
      line.start_with?('requestedApp:', 'firstAttempt:', 'retryAttempt:', 'finalOutcome:', 'currentMode:', 'windowVisible:', 'lastRelayoutReason:')
    end
    return interesting.join(' || ') unless interesting.empty?

    diagnostics.lines.last.to_s.strip
  end

  def wait_for_browse_panel(expected_mode)
    deadline = Time.now + BROWSE_PANEL_READY_TIMEOUT_SECONDS
    last_diagnostics = nil

    while Time.now < deadline
      last_diagnostics = browse_panel_diagnostics
      return if last_diagnostics.include?("currentMode: #{expected_mode}") &&
                last_diagnostics.include?('windowVisible: true')

      sleep BROWSE_PANEL_READY_POLL_SECONDS
    end

    raise "Browse panel did not become ready for #{expected_mode}: #{last_diagnostics}"
  end

  def close_browse_panel
    result = app_script('close browse panel').strip.downcase
    unless %w[true 1].include?(result)
      raise "close browse panel returned '#{result}'"
    end

    unless supports_applescript_command?('browse panel diagnostics')
      sleep 0.5
      return
    end

    wait_for_browse_panel_close
  end

  def close_browse_panel_safely
    close_browse_panel
  rescue StandardError
    nil
  end

  def wait_for_browse_panel_close
    deadline = Time.now + BROWSE_PANEL_READY_TIMEOUT_SECONDS
    last_diagnostics = nil

    while Time.now < deadline
      last_diagnostics = browse_panel_diagnostics
      return if last_diagnostics.include?('windowVisible: false')

      sleep BROWSE_PANEL_READY_POLL_SECONDS
    end

    raise "Browse panel did not close cleanly: #{last_diagnostics}"
  end

  def browse_panel_diagnostics
    app_script('browse panel diagnostics')
  end

  def detect_supported_applescript_commands
    sdef_path = @app_path && File.join(@app_path, 'Contents', 'Resources', 'SaneBar.sdef')
    return [] unless sdef_path && File.exist?(sdef_path)

    File.read(sdef_path).scan(/<command name="([^"]+)"/).flatten
  rescue StandardError
    []
  end

  def supports_applescript_command?(command_name)
    return true if @supported_applescript_commands.empty?

    @supported_applescript_commands.include?(command_name)
  end

  def capture_browse_screenshot(expected_mode)
    FileUtils.mkdir_p(@screenshot_dir)
    path = File.join(
      @screenshot_dir,
      "sanebar-#{expected_mode}-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.png"
    )
    command = "screencapture -x #{Shellwords.escape(path)}"
    script = <<~APPLESCRIPT
      do shell script #{command.inspect}
    APPLESCRIPT

    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: SCREENSHOT_CAPTURE_TIMEOUT_SECONDS)
    unless code.success?
      disable_screenshot_capture!("Screenshot capture failed: #{out.strip}", path)
      return nil
    end

    deadline = Time.now + SCREENSHOT_CAPTURE_TIMEOUT_SECONDS
    until File.exist?(path) && File.size?(path)
      if Time.now >= deadline
        disable_screenshot_capture!("Screenshot missing at #{path}", path)
        return nil
      end
      sleep 0.2
    end

    path
  rescue StandardError => e
    disable_screenshot_capture!(e.message, path)
    nil
  end

  def disable_screenshot_capture!(reason, path = nil)
    @capture_screenshots = false
    FileUtils.rm_f(path) if path
    puts "⚠️ Screenshot capture unavailable: #{reason}. Continuing without screenshots."
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
    begin
      result = app_script("#{command} \"#{icon}\"").strip.downcase
      unless %w[true 1].include?(result)
        raise "#{command} returned '#{result}' for #{candidate[:unique_id]}"
      end
    rescue StandardError => e
      raise unless timed_out_move_command?(command, e)

      puts "ℹ️ Salvaging timed-out move command via zone verification for #{icon_unique_id}"
    end

    wait_for_zone(icon_unique_id, candidate, expected_zone)
  end

  def wait_for_zone(icon_unique_id, candidate, expected_zone)
    deadline = Time.now + MAX_WAIT_SECONDS
    last_error = nil
    while Time.now < deadline
      begin
        zones = list_icon_zones
      rescue StandardError => e
        raise unless retryable_zone_poll_error?(e)

        last_error = e
        sleep POLL_SECONDS
        next
      end

      matched = zones.find { |item| item[:unique_id] == icon_unique_id } ||
        zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] } ||
        zones.find { |item| item[:bundle] == candidate[:bundle] && item[:movable] }
      return true if matched && matched[:zone] == expected_zone
      sleep POLL_SECONDS
    end

    if last_error
      raise "Timeout waiting for #{candidate[:bundle]} (#{candidate[:name]}) to reach zone #{expected_zone} after transient poll failures: #{last_error.message}"
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
    script = %(tell #{apple_script_target} to #{statement})
    attempts = 0
    timeout = app_script_timeout_for(statement)
    begin
      attempts += 1
      out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: timeout)
      raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?
      out
    rescue StandardError => e
      retryable = e.message.include?('timeout') || e.message.include?('failed')
      if attempts < APPLESCRIPT_RETRIES && retryable && !non_idempotent_app_script?(statement)
        sleep 0.2
        retry
      end
      raise
    end
  end

  def current_browse_activation_diagnostics
    [
      direct_app_script('activation diagnostics', timeout: 2.5),
      direct_app_script('browse panel diagnostics', timeout: 2.5)
    ].join("\n")
  rescue StandardError
    nil
  end

  def direct_app_script(statement, timeout:)
    script = %(tell #{apple_script_target} to #{statement})
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: timeout)
    raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?

    out
  end

  def salvage_timed_out_browse_activation(live_identifier:, baseline_diagnostics:, error:)
    return nil unless error.message.include?('AppleScript timeout')

    current = current_browse_activation_diagnostics
    return nil if current.nil? || current == baseline_diagnostics
    return nil unless current.include?('origin: browsePanel')
    return nil unless current.include?("requestedApp: id=#{live_identifier}")
    return nil unless current.include?('finalOutcome: click succeeded')
    return nil unless browse_activation_observably_verified?(current)

    puts "ℹ️ Salvaged timed-out browse activation via fresh diagnostics for #{live_identifier}"
    current
  end

  def non_idempotent_app_script?(statement)
    statement.start_with?('activate browse icon ') ||
      statement.start_with?('right click browse icon ')
  end

  def timed_out_move_command?(command, error)
    error.message.include?('AppleScript timeout') &&
      command.start_with?('move icon to ')
  end

  def app_script_timeout_for(statement)
    return APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS if heavy_read_app_script?(statement)

    APPLESCRIPT_TIMEOUT_SECONDS
  end

  def heavy_read_app_script?(statement)
    statement == 'list icon zones' || statement == 'list icons'
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

  def retryable_zone_poll_error?(error)
    return true if zone_api_retryable?(error)

    error.message.include?('AppleScript timeout')
  end

  def strict_candidate_mode?
    @require_all_candidates || !@required_candidate_ids.empty?
  end

  def escape_quotes(value)
    value.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  end

  def env_string(name)
    value = ENV[name].to_s.strip
    value.empty? ? nil : value
  end

  def expand_env_path(name)
    value = env_string(name)
    return nil unless value

    File.expand_path(value)
  end

  def expected_process_path
    return @process_path if @process_path
    return nil unless @app_path

    File.join(@app_path, 'Contents', 'MacOS', @app_name)
  end

  def matching_app_process?(command)
    binary = command.split(/\s+/, 2).first.to_s
    return false if binary.empty?

    expected = expected_process_path
    return File.expand_path(binary) == expected if expected

    binary.end_with?("/Contents/MacOS/#{@app_name}") || File.basename(binary) == @app_name
  end

  def apple_script_target
    return %(application id "#{escape_quotes(@app_id)}") if @app_id

    %(application "#{escape_quotes(@app_name)}")
  end
end

exit(LiveZoneSmoke.new.run ? 0 : 1)
