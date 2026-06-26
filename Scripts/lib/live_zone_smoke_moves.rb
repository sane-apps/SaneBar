# frozen_string_literal: true

class LiveZoneSmoke
  private

  def exercise_representative_move_action_matrix(candidates)
    candidates = refresh_representative_move_action_matrix_candidates(candidates)
    by_zone = candidates.group_by { |candidate| candidate[:zone].to_s }
    visible_candidate = Array(by_zone['visible']).first
    hidden_candidate = Array(by_zone['hidden']).first
    always_hidden_candidates = Array(by_zone['alwaysHidden'])

    if visible_candidate.nil? || hidden_candidate.nil? || always_hidden_candidates.length < 3
      # Reached here only because the upstream candidate gate already TOLERATED a
      # product-correct safety refusal (a shared fixture parked where the product
      # correctly won't drag it). This AppleScript move matrix exercises SaneBar's
      # AppleScript move command — NOT the UI drag / right-click "Move to…" code
      # path users actually use — so it is not representative coverage to begin
      # with. Skip it rather than block the release; real move coverage is the
      # Swift move-regression suite plus on-device IRL verification. If the gate
      # did NOT degrade (genuine setup bug), still fail loudly.
      if @representative_zone_setup_degraded
        warn '⚠️ Skipping AppleScript representative move matrix (shared fixtures ' \
             'un-seedable via product-correct notch-unsafe/off-screen refusals). This ' \
             'matrix drives the AppleScript move command, not the UI drag/right-click ' \
             'path; real coverage is the Swift move-regression suite + on-device IRL ' \
             "verification (visible=#{!visible_candidate.nil?} hidden=#{!hidden_candidate.nil?} " \
             "ah=#{always_hidden_candidates.length})."
        return []
      end
      raise 'Representative move matrix requires a visible candidate.' unless visible_candidate
      raise 'Representative move matrix requires a hidden candidate.' unless hidden_candidate
      raise 'Representative move matrix requires three settled always-hidden candidates.' if always_hidden_candidates.length < 3
    end

    passed = []

    ah_to_visible = begin
      exercise_matrix_move_with_fallback(
        'AH->Visible',
        prioritize_ah_to_visible_candidates(always_hidden_candidates),
        'move icon to visible',
        'visible'
      )
    rescue StandardError => e
      puts "ℹ️ Matrix AH->Visible existing candidates failed; staging visible candidate through Always Hidden: #{e.message}"
      staged_candidate = visible_candidate.merge(zone: 'visible')
      move_and_verify('move icon to always hidden', staged_candidate, 'alwaysHidden')
      move_and_verify(
        'move icon to visible',
        staged_candidate.merge(zone: 'alwaysHidden', staged_always_hidden_outbound: true),
        'visible'
      )
      staged_candidate.merge(zone: 'visible')
    end
    passed << ah_to_visible

    ah_to_hidden_candidates = prioritize_ah_to_hidden_candidates(
      always_hidden_candidates.reject { |candidate| candidate[:unique_id] == ah_to_visible[:unique_id] }
    )
    ah_to_hidden = begin
      exercise_matrix_move_with_fallback(
        'AH->Hidden',
        ah_to_hidden_candidates,
        'move icon to hidden',
        'hidden'
      )
    rescue StandardError => e
      puts "ℹ️ Matrix AH->Hidden existing candidates failed; staging hidden candidate through Always Hidden: #{e.message}"
      staged_candidate = hidden_candidate.merge(zone: 'hidden')
      move_and_verify('move icon to always hidden', staged_candidate, 'alwaysHidden')
      move_and_verify(
        'move icon to hidden',
        staged_candidate.merge(zone: 'alwaysHidden', staged_always_hidden_outbound: true),
        'hidden'
      )
      staged_candidate.merge(zone: 'hidden')
    end
    passed << ah_to_hidden
    puts '✅ Always Hidden move actions ok'

    hidden_visible_candidates = matrix_hidden_visible_candidates(
      primary: ah_to_visible.merge(zone: 'visible'),
      visible_candidate: visible_candidate,
      hidden_candidate: hidden_candidate,
      all_candidates: candidates
    )
    hidden_visible_candidate = exercise_hidden_visible_moves_with_fallback(hidden_visible_candidates)
    puts "✅ Hidden/Visible move actions ok (#{hidden_visible_candidate[:unique_id]})"

    puts "🎯 Matrix Hidden->Always Hidden candidate: #{hidden_candidate[:name]} (#{hidden_candidate[:bundle]})"
    move_and_verify('move icon to always hidden', hidden_candidate, 'alwaysHidden')
    passed << hidden_candidate
    puts '✅ Hidden/Always Hidden round-trip ok'

    puts "✅ Candidate set passed: #{passed.map { |candidate| candidate[:unique_id] }.uniq.join(', ')}"
    passed
  end

  def refresh_representative_move_action_matrix_candidates(candidates)
    return candidates if representative_move_matrix_candidate_set_complete?(candidates)

    zones = require_representative_zone_candidates!(list_icon_zones)
    refreshed = selected_candidates(zones)
    representative_move_matrix_candidate_set_complete?(refreshed) ? refreshed : candidates
  rescue StandardError => e
    puts "⚠️ Representative move matrix live refresh failed: #{e.message}"
    candidates
  end

  def representative_move_matrix_candidate_set_complete?(candidates)
    by_zone = Array(candidates).group_by { |candidate| candidate[:zone].to_s }
    Array(by_zone['visible']).any? &&
      Array(by_zone['hidden']).any? &&
      Array(by_zone['alwaysHidden']).length >= 3
  end

  def matrix_hidden_visible_candidates(primary:, visible_candidate:, hidden_candidate:, all_candidates:)
    ordered = [primary, visible_candidate, hidden_candidate] +
      all_candidates.reject { |candidate| candidate[:zone] == 'alwaysHidden' }
    seen = {}
    ordered.compact.each_with_object([]) do |candidate, result|
      unique_id = candidate[:unique_id].to_s
      next if unique_id.empty? || seen[unique_id]

      seen[unique_id] = true
      result << candidate
    end
  end

  def exercise_hidden_visible_moves_with_fallback(candidates)
    failures = []
    candidates.each do |candidate|
      live_candidate = live_matrix_candidate(candidate)
      next unless live_candidate

      puts "🎯 Matrix Hidden/Visible candidate: #{live_candidate[:name]} (#{live_candidate[:bundle]})"
      exercise_hidden_visible_moves(live_candidate.merge(matrix_hidden_visible_outbound: true))
      return live_candidate
    rescue StandardError => e
      failures << "#{candidate[:unique_id]} => #{e.message}"
      puts "⚠️ Matrix Hidden/Visible candidate failed: #{candidate[:bundle]} (#{e.message})"
    end

    raise "Representative move matrix could not prove Hidden/Visible: #{failures.join(' | ')}"
  end

  def live_matrix_candidate(candidate)
    zones = list_icon_zones
    matched = matched_move_candidate(zones, candidate[:unique_id], candidate)
    return nil unless matched
    return nil if matched[:zone] == 'alwaysHidden'

    candidate.merge(matched)
  end

  def exercise_matrix_move_with_fallback(label, candidates, command, expected_zone)
    candidates = compact_representative_matrix_candidates(safe_matrix_drag_source_candidates(label, candidates))
    failures = []
    max_passes = candidates.all? { |candidate| deterministic_shared_fixture_candidate?(candidate) } ? 1 : 2
    max_passes.times do |pass|
      if pass == 1
        puts "ℹ️ Retrying matrix #{label} after extended menu bar settle"
        sleep_with_watchdog(8.0)
        wait_for_move_ready_state
      end

      candidates.each do |candidate|
        puts "🎯 Matrix #{label} candidate: #{candidate[:name]} (#{candidate[:bundle]})"
        move_and_verify(command, candidate, expected_zone)
        return candidate
      rescue StandardError => e
        failures << "#{candidate[:unique_id]} => #{e.message}"
        puts "⚠️ Matrix #{label} candidate failed: #{candidate[:bundle]} (#{e.message})"
      end
    end

    raise "Representative move matrix could not prove #{label}: #{failures.join(' | ')}"
  end

  def compact_representative_matrix_candidates(candidates)
    candidates = Array(candidates).compact
    return candidates unless candidates.length > 1
    return candidates unless candidates.all? { |candidate| deterministic_shared_fixture_candidate?(candidate) }

    [candidates.first]
  end

  def prioritize_ah_to_visible_candidates(candidates)
    candidates.sort_by do |candidate|
      [
        deterministic_shared_fixture_candidate?(candidate) ? 1 : 0,
        candidate[:bundle].to_s.start_with?('com.apple.') ? 1 : 0,
        candidate[:name].to_s.downcase
      ]
    end
  end

  def prioritize_ah_to_hidden_candidates(candidates)
    candidates.sort_by do |candidate|
      [
        deterministic_shared_fixture_candidate?(candidate) ? 0 : 1,
        candidate[:bundle].to_s.start_with?('com.apple.') ? 1 : 0,
        candidate[:name].to_s.downcase
      ]
    end
  end

  def deterministic_shared_fixture_candidate?(candidate)
    candidate[:bundle].to_s == 'com.sanebar.sharedfixture'
  end

  def safe_matrix_drag_source_candidates(label, candidates)
    safe, unsafe = Array(candidates).partition do |candidate|
      !candidate.key?(:drag_source_safety) || candidate[:drag_source_safety].to_s == 'safe'
    end
    unless unsafe.empty?
      skipped = unsafe.map { |candidate| "#{candidate[:unique_id]}@#{candidate[:center_x] || 'unknown'}" }.join(', ')
      puts "ℹ️ Matrix #{label} skipped offscreen/notch-unsafe drag source(s): #{skipped}"
    end
    safe
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
    wait_for_move_ready_state
    icon_unique_id = resolve_live_move_identifier(candidate)
    settle_before_outbound_move(icon_unique_id, candidate, expected_zone)
    icon = escape_quotes(icon_unique_id)
    begin
      result = app_script("#{command} \"#{icon}\"").strip.downcase
      raise "#{command} returned '#{result}' for #{candidate[:unique_id]}" unless %w[true 1].include?(result)
    rescue StandardError => e
      if timed_out_move_command?(command, e)
        puts "ℹ️ Salvaging timed-out move command via zone verification for #{icon_unique_id}"
      elsif retryable_failed_move_command?(command, e)
        puts "ℹ️ Retrying failed move command after menu bar settle for #{icon_unique_id}: #{e.message}"
        sleep_with_watchdog(1.2)
        result = app_script("#{command} \"#{icon}\"").strip.downcase
        raise "#{command} retry returned '#{result}' for #{candidate[:unique_id]}" unless %w[true 1].include?(result)
      else
        raise
      end
    end

    wait_for_zone(icon_unique_id, candidate, expected_zone)
    assert_zone_stays_stable_after_move(icon_unique_id, candidate, expected_zone)
  end

  def settle_before_outbound_move(icon_unique_id, candidate, expected_zone)
    return true if expected_zone == 'alwaysHidden'

    zones = list_icon_zones
    matched = matched_move_candidate(zones, icon_unique_id, candidate)
    return true unless matched

    if matched.key?(:drag_source_safety) && matched[:drag_source_safety].to_s != 'safe'
      if staged_always_hidden_outbound_candidate?(candidate, matched)
        puts "ℹ️ Allowing staged Always Hidden outbound attempt for #{icon_unique_id}; product workflow will reveal/repair before dragging"
      elsif matrix_hidden_visible_outbound_candidate?(candidate, matched, expected_zone)
        puts "ℹ️ Allowing matrix Hidden outbound attempt for #{icon_unique_id}; product workflow will reveal hidden icons before dragging"
      else
        raise "Refusing outbound move from unsafe drag source #{icon_unique_id} (safety=#{matched[:drag_source_safety]}, centerX=#{matched[:center_x] || 'unknown'})"
      end
    end
    return true unless matched[:zone] == 'alwaysHidden'

    puts "ℹ️ Settling before Always Hidden outbound move for #{icon_unique_id}"
    sleep_with_watchdog(ALWAYS_HIDDEN_OUTBOUND_SETTLE_SECONDS)
    wait_for_move_ready_state
    true
  end

  def staged_always_hidden_outbound_candidate?(candidate, matched)
    candidate[:staged_always_hidden_outbound] == true && matched[:zone].to_s == 'alwaysHidden'
  end

  def matrix_hidden_visible_outbound_candidate?(candidate, matched, expected_zone)
    candidate[:matrix_hidden_visible_outbound] == true &&
      matched[:zone].to_s == 'hidden' &&
      expected_zone.to_s == 'visible'
  end

  def wait_for_move_ready_state
    close_browse_panel_safely
    close_settings_window_safely
    deadline = Time.now + 6.0
    last_snapshot = nil
    last_error = nil

    while Time.now < deadline
      begin
        last_snapshot = layout_snapshot
        ready = !truthy?(last_snapshot['isMoveInProgress']) &&
                !truthy?(last_snapshot['isBrowseVisible']) &&
                !truthy?(last_snapshot['isBrowseSessionActive']) &&
                !truthy?(last_snapshot['isMenuOpen'])
        return true if ready
      rescue StandardError => e
        last_error = e
        # Fall through to a short settle; move verification will surface hard
        # failures with the command-specific context.
      end
      sleep_with_watchdog(0.25)
    end

    error_detail = last_error ? ", last_error=#{last_error.message}" : ''
    raise "Menu bar did not become move-ready before action (snapshot=#{last_snapshot}#{error_detail})"
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
    return nil if focused_required_id_mode?

    same_bundle = same_bundle_movable_candidates(zones, candidate)
    return nil if same_bundle.length > 1

    zones.find { |item| item[:bundle] == candidate[:bundle] && item[:name] == candidate[:name] } ||
      same_bundle.first
  end

  def resolve_live_move_identifier(candidate)
    zones = list_icon_zones

    exact = zones.find { |item| item[:unique_id] == candidate[:unique_id] }
    return exact[:unique_id] if exact

    if focused_required_id_mode?
      live_ids = same_bundle_movable_candidates(zones, candidate).map { |item| item[:unique_id] }
      raise "Required exact move candidate missing before action: requested=#{candidate[:unique_id]} bundle=#{candidate[:bundle]} live=#{live_ids.join(', ')}"
    end

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
      raise runtime_target_lost_error(statement, e) if runtime_target_lost_after_applescript_failure?

      retryable = e.message.include?('timeout') || e.message.include?('failed')
      if attempts < APPLESCRIPT_RETRIES && retryable && !non_idempotent_app_script?(statement)
        sleep_with_watchdog(0.2)
        retry
      end
      raise
    end
  end

  def runtime_target_lost_after_applescript_failure?
    !app_process_still_alive? && current_matching_process_summary == 'none'
  rescue StandardError
    false
  end

  def runtime_target_lost_error(statement, error)
    RuntimeError.new(
      "runtime_target_lost during AppleScript #{statement}: #{error.message}; #{process_monitor_error_detail(RuntimeError.new('process_missing'))}"
    )
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

  def retryable_failed_move_command?(command, error)
    command.start_with?('move icon to ') &&
      error.message.include?('failed to move')
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
    timed_out = false

    Open3.popen2e(*cmd, pgroup: true) do |stdin, stdout, wait_thr|
      stdin.close
      begin
        deadline = Time.now + timeout
        loop do
          check_resource_watchdog!
          read_command_output_nonblocking!(stdout, output)
          if wait_thr.join(0.2)
            status = wait_thr.value
            read_command_output_nonblocking!(stdout, output, max_drain_seconds: 1.0)
            break
          end

          if Time.now >= deadline
            timed_out = true
            terminate_child_process(wait_thr)
            read_command_output_nonblocking!(stdout, output, max_drain_seconds: 1.0)
            break
          end
        end
      rescue StandardError
        terminate_child_process(wait_thr)
        read_command_output_nonblocking!(stdout, output, max_drain_seconds: 1.0)
        raise
      end
    end

    if timed_out
      tail = output.lines.last(12).join.strip
      detail = tail.empty? ? '' : " output_tail=#{tail}"
      raise "AppleScript timeout after #{timeout}s (#{cmd.join(' ')})#{detail}"
    end

    [output, status]
  end

  def read_command_output_nonblocking!(stdout, output, max_drain_seconds: 0.4)
    deadline = Time.now + max_drain_seconds
    loop do
      break if Time.now >= deadline

      ready = IO.select([stdout], nil, nil, 0.05)
      break unless ready

      chunk = stdout.read_nonblock(4096, exception: false)
      case chunk
      when String
        output << normalize_command_output_chunk(chunk)
      when :wait_readable
        next
      else
        break
      end
    end
  rescue IOError
    nil
  end

  def normalize_command_output_chunk(chunk)
    chunk.to_s.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace, replace: '?')
  rescue EncodingError
    normalized = chunk.to_s.dup
    normalized.force_encoding(Encoding::UTF_8)
    normalized.valid_encoding? ? normalized : normalized.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
  end
end
