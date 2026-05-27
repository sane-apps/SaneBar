# frozen_string_literal: true

class LiveZoneSmoke
  private

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

  def exercise_hidden_always_hidden_round_trip(candidate)
    move_and_verify('move icon to hidden', candidate, 'hidden')
    move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
    move_and_verify('move icon to hidden', candidate, 'hidden')
    puts '✅ Hidden/Always Hidden round-trip ok'
  rescue StandardError => e
    raise if @require_always_hidden

    if always_hidden_optional_failure?(e)
      puts "ℹ️ Skipping hidden/always-hidden round-trip check (likely free mode): #{e.message}"
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
    icon_unique_id = resolve_live_move_identifier(candidate)
    icon = escape_quotes(icon_unique_id)
    begin
      result = app_script("#{command} \"#{icon}\"").strip.downcase
      raise "#{command} returned '#{result}' for #{candidate[:unique_id]}" unless %w[true 1].include?(result)
    rescue StandardError => e
      raise unless timed_out_move_command?(command, e)

      puts "ℹ️ Salvaging timed-out move command via zone verification for #{icon_unique_id}"
    end

    wait_for_zone(icon_unique_id, candidate, expected_zone)
    assert_zone_stays_stable_after_move(icon_unique_id, candidate, expected_zone)
  end

  def assert_zone_stays_stable_after_move(icon_unique_id, candidate, expected_zone)
    return true unless @post_move_zone_stability_seconds.positive?

    sleep_with_watchdog(@post_move_zone_stability_seconds)
    zones = list_icon_zones

    if exact_move_identity_lost?(candidate, icon_unique_id, zones)
      live_ids = same_bundle_movable_candidates(zones, candidate).map { |item| item[:unique_id] }
      raise "Post-settle move verification lost exact identity: requested=#{icon_unique_id} bundle=#{candidate[:bundle]} live=#{live_ids.join(', ')}"
    end

    matched = matched_move_candidate(zones, icon_unique_id, candidate)
    if matched.nil?
      raise "Post-settle move verification could not find #{candidate[:bundle]} (#{candidate[:name]}) after move to #{expected_zone}"
    end

    unless matched[:zone] == expected_zone
      raise "Post-settle move verification drifted: #{candidate[:bundle]} (#{candidate[:name]}) expected #{expected_zone}, got #{matched[:zone]}"
    end

    puts "✅ Post-settle zone stability ok: #{icon_unique_id} stayed #{expected_zone}"
    true
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
        sleep_with_watchdog(POLL_SECONDS)
        next
      end

      if exact_move_identity_lost?(candidate, icon_unique_id, zones)
        live_ids = same_bundle_movable_candidates(zones, candidate).map { |item| item[:unique_id] }
        raise "Shared-bundle move verification lost exact identity: requested=#{icon_unique_id} bundle=#{candidate[:bundle]} live=#{live_ids.join(', ')}"
      end

      matched = matched_move_candidate(zones, icon_unique_id, candidate)
      return true if matched && matched[:zone] == expected_zone

      sleep_with_watchdog(POLL_SECONDS)
    end

    if last_error
      raise "Timeout waiting for #{candidate[:bundle]} (#{candidate[:name]}) to reach zone #{expected_zone} after transient poll failures: #{last_error.message}"
    end

    raise "Timeout waiting for #{candidate[:bundle]} (#{candidate[:name]}) to reach zone #{expected_zone}"
  end

  def same_bundle_movable_candidates(zones, candidate)
    zones.select { |item| item[:bundle] == candidate[:bundle] && item[:movable] }
  end

  def exact_move_identity_lost?(candidate, requested_unique_id, zones)
    return false unless same_bundle_movable_candidates(zones, candidate).length > 1

    zones.none? { |item| item[:unique_id] == requested_unique_id }
  end

  def matched_move_candidate(zones, requested_unique_id, candidate)
    exact = zones.find { |item| item[:unique_id] == requested_unique_id }
    return exact if exact

    same_bundle = same_bundle_movable_candidates(zones, candidate)
    return nil if same_bundle.length > 1

    zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] } ||
      same_bundle.first
  end

  def resolve_live_move_identifier(candidate)
    zones = list_icon_zones

    exact = zones.find { |item| item[:unique_id] == candidate[:unique_id] }
    return exact[:unique_id] if exact

    same_bundle = same_bundle_movable_candidates(zones, candidate)
    if same_bundle.length > 1
      live_ids = same_bundle.map { |item| item[:unique_id] }
      raise "Shared-bundle move candidate lost exact identity before action: requested=#{candidate[:unique_id]} bundle=#{candidate[:bundle]} live=#{live_ids.join(', ')}"
    end

    bundle_and_name = zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] }
    return bundle_and_name[:unique_id] if bundle_and_name
    return same_bundle.first[:unique_id] if same_bundle.length == 1

    candidate[:unique_id]
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
    verify_single_process
    script_lines = apple_script_lines(statement)
    attempts = 0
    timeout = app_script_timeout_for(statement)
    begin
      attempts += 1
      out, code = capture2e_with_timeout(
        '/usr/bin/osascript',
        *script_lines.flat_map { |line| ['-e', line] },
        timeout: timeout
      )
      raise "AppleScript failed (#{statement}): #{out.strip}" unless code.success?

      out
    rescue StandardError => e
      retryable = e.message.include?('timeout') || e.message.include?('failed')
      if attempts < APPLESCRIPT_RETRIES && retryable && !non_idempotent_app_script?(statement)
        sleep_with_watchdog(0.2)
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
    out, code = capture2e_with_timeout(
      '/usr/bin/osascript',
      *apple_script_lines(statement).flat_map { |line| ['-e', line] },
      timeout: timeout
    )
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
    return APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS if activation_app_script?(statement)
    return APPLESCRIPT_MOVE_TIMEOUT_SECONDS if move_app_script?(statement)
    return APPLESCRIPT_HEAVY_READ_TIMEOUT_SECONDS if heavy_read_app_script?(statement)

    APPLESCRIPT_TIMEOUT_SECONDS
  end

  def activation_app_script?(statement)
    statement.start_with?('activate browse icon ') ||
      statement.start_with?('right click browse icon ') ||
      statement.start_with?('activate icon ') ||
      statement.start_with?('right click icon ')
  end

  def heavy_read_app_script?(statement)
    statement == 'list icon zones' ||
      statement == 'list icons' ||
      statement == 'browse panel diagnostics' ||
      statement == 'activation diagnostics'
  end

  def move_app_script?(statement)
    statement.start_with?('move icon to ')
  end

  def capture2e_with_timeout(*cmd, timeout:)
    output = +''
    status = nil

    Open3.popen2e(*cmd) do |stdin, stdout, wait_thr|
      stdin.close
      reader = Thread.new { stdout.read.to_s }

      begin
        deadline = Time.now + timeout
        loop do
          check_resource_watchdog!
          if wait_thr.join(0.2)
            status = wait_thr.value
            output = reader.value
            break
          end

          raise "AppleScript timeout after #{timeout}s (#{cmd.join(' ')})" if Time.now >= deadline
        end
      rescue StandardError
        terminate_child_process(wait_thr)
        begin
          output = reader.value
        rescue StandardError
          output = ''
        end
        raise
      end
    end

    [output, status]
  end
end
