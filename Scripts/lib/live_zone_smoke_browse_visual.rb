# frozen_string_literal: true

class LiveZoneSmoke
  private

  def exercise_browse_modes(zones)
    forced_activation_candidates = nil
    if focused_required_id_mode? && @pin_required_browse_always_hidden
      forced_activation_candidates = selected_candidates(zones)
      forced_activation_candidates.each do |candidate|
        move_and_verify('move icon to always hidden', candidate, 'alwaysHidden')
      end
      puts "✅ Focused browse fixtures pinned Always Hidden: #{forced_activation_candidates.map { |item| item[:unique_id] }.join(', ')}"
    end

    BROWSE_PANEL_COMMANDS.each do |expected_mode, command|
      unless supports_applescript_command?(command)
        puts "ℹ️ Skipping #{expected_mode}: running app does not expose '#{command}'"
        next
      end

      if full_browse_activation_supported? && (!focused_required_id_mode? || @pin_required_browse_always_hidden)
        exercise_browse_mode(
          expected_mode: expected_mode,
          command: command,
          zones: zones,
          forced_activation_candidates: forced_activation_candidates
        )
      else
        reason = focused_required_id_mode? ? 'focused required-id smoke' : 'activation diagnostics unavailable in running app'
        puts "ℹ️ Compatibility browse check for #{expected_mode}: #{reason}"
        exercise_compatibility_browse_mode(expected_mode: expected_mode, command: command)
      end
    end

    exercise_settings_window_visual_check
    exercise_appearance_transition_visual_check
  ensure
    if forced_activation_candidates
      forced_activation_candidates.each do |candidate|
        restore_zone(candidate)
      rescue StandardError => e
        puts "⚠️ Failed to restore focused browse fixture #{candidate[:unique_id]}: #{e.message}"
      end
    end
  end

  def full_browse_activation_supported?
    [
      'browse panel diagnostics',
      'activate browse icon',
      'right click browse icon'
    ].all? { |command| supports_applescript_command?(command) }
  end

  def browse_activation_candidates(zones, expected_mode:, activation_command:)
    ordered_pool = browse_activation_pool(zones).sort_by do |item|
      [
        browse_zone_priority(item[:zone]),
        coarse_bundle_fallback?(item) ? 1 : 0
      ]
    end
    ordered_pool = compact_precise_non_apple_bundle_candidates(ordered_pool)
    precise_non_apple = ordered_pool.reject do |item|
      coarse_bundle_fallback?(item) ||
        item[:bundle].start_with?('com.apple.') ||
        browse_activation_denied?(item, expected_mode: expected_mode)
    end
    exact_apple = ordered_pool.select do |item|
      !coarse_bundle_fallback?(item) &&
        item[:bundle].start_with?('com.apple.') &&
        !browse_activation_denied?(item, expected_mode: expected_mode)
    end
    coarse_non_apple = ordered_pool.select do |item|
      coarse_bundle_fallback?(item) &&
        !item[:bundle].start_with?('com.apple.') &&
        !browse_activation_denied?(item, expected_mode: expected_mode)
    end

    preferred = PREFERRED_BROWSE_ACTIVATION_IDS.map do |preferred_id|
      ordered_pool.find { |item| browse_candidate_matches?(item, preferred_id) }
    end.compact.reject { |item| browse_activation_denied?(item, expected_mode: expected_mode) }
      .uniq { |item| item[:unique_id] }

    fallback = ordered_pool.reject { |item| browse_activation_denied?(item, expected_mode: expected_mode) }

    # Generic browse smoke needs to prefer third-party identities first.
    # Precise rows are best, but even coarse third-party bundle fallbacks have
    # been more stable on this Mini than Apple/system fixtures for the browse
    # click paths we exercise. Curated Apple fixtures stay as fallback
    # coverage, but they should not consume the main smoke budget when usable
    # non-Apple rows are available.
    candidate_order =
      if expected_mode == 'secondMenuBar'
        precise_non_apple + coarse_non_apple + exact_apple + preferred + fallback
      else
        precise_non_apple + coarse_non_apple + preferred + fallback
      end

    candidate_order.uniq { |item| item[:unique_id] }.take(3)
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

  def browse_activation_denied?(item, expected_mode: nil)
    return true if BROWSE_ACTIVATION_UNRELIABLE_IDS.any? { |value| browse_candidate_matches?(item, value) }

    # Exact MenuMeters rows are stable browse fixtures on the Mini in both
    # browse modes, even though the coarse bundle fallback is still too noisy
    # to lead the generic activation pool.
    if item[:bundle].casecmp('com.yujitach.MenuMeters').zero? &&
       !coarse_bundle_fallback?(item)
      return false
    end

    return false if PREFERRED_BROWSE_ACTIVATION_IDS.any? { |preferred_id| browse_candidate_matches?(item, preferred_id) }

    bundle = item[:bundle].to_s.strip.downcase
    BROWSE_ACTIVATION_BUNDLE_DENYLIST.any? { |value| value.downcase == bundle }
  end

  def exercise_browse_mode(expected_mode:, command:, zones:, forced_activation_candidates: nil)
    focus_probe_prior_state = seed_focus_probe_prior_app
    result = app_script(command).strip.downcase
    raise "#{command} returned '#{result}'" unless %w[true 1].include?(result)

    wait_for_browse_panel(expected_mode)
    assert_browse_panel_anchor!(expected_mode)
    screenshot_path = capture_browse_screenshot(expected_mode) if @capture_screenshots
    puts "📸 #{expected_mode} screenshot: #{screenshot_path}" if screenshot_path

    # Keep candidate pools from the pre-open snapshot. Once the browse session
    # is active, classification intentionally collapses always-hidden geometry
    # back into the generic hidden lane, which can reintroduce off-panel IDs
    # into the runtime smoke budget.
    left_click_candidates = forced_activation_candidates || browse_activation_candidates(
      zones,
      expected_mode: expected_mode,
      activation_command: 'activate browse icon'
    )
    right_click_candidates = forced_activation_candidates || browse_activation_candidates(
      zones,
      expected_mode: expected_mode,
      activation_command: 'right click browse icon'
    )
    if left_click_candidates.empty? && right_click_candidates.empty?
      if browse_activation_candidates_required?
        raise 'No browse activation candidate icon found.'
      end

      puts 'ℹ️ No browse activation candidate icon found on this setup; skipping browse click checks for this default smoke run.'
      close_browse_panel
      puts "✅ Browse mode #{expected_mode} open/close ok"
      return
    end

    exercise_browse_activation('activate browse icon', expected_mode, left_click_candidates)
    # SearchService debounces duplicate activation of the same icon for 450ms.
    # Leave enough headroom before immediately retrying that tile with right-click.
    sleep_with_watchdog(BROWSE_ACTIVATION_COOLDOWN_SECONDS)
    exercise_browse_activation(
      'right click browse icon',
      expected_mode,
      right_click_candidates,
      prior_frontmost_state: focus_probe_prior_state
    )
    close_browse_panel
    puts "✅ Browse mode #{expected_mode} activation ok"
  ensure
    close_browse_panel_safely
  end

  def exercise_compatibility_browse_mode(expected_mode:, command:)
    result = app_script(command).strip.downcase
    raise "#{command} returned '#{result}'" unless %w[true 1].include?(result)

    wait_for_browse_panel(expected_mode)
    assert_browse_panel_anchor!(expected_mode)
    screenshot_path = capture_browse_screenshot(expected_mode) if @capture_screenshots
    puts "📸 #{expected_mode} screenshot: #{screenshot_path}" if screenshot_path
    close_browse_panel
    puts "✅ Browse mode #{expected_mode} open/close ok"
  ensure
    close_browse_panel_safely
  end

  def exercise_browse_activation(command, expected_mode, candidates, prior_frontmost_state: nil)
    failures = []

    candidates.each do |candidate|
      live_identifier = resolve_live_icon_identifier(candidate)
      baseline_diagnostics = current_browse_activation_diagnostics
      diagnostics = app_script(%(#{command} "#{escape_quotes(live_identifier)}"))
      if browse_activation_succeeded?(diagnostics, expected_mode)
        verify_post_activation_browse_state!(expected_mode)
        assert_frontmost_did_not_revert_to(prior_frontmost_state, command) unless prior_frontmost_state.nil?
        return
      end

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

  def exercise_settings_window_visual_check
    return unless supports_applescript_command?('open settings window')

    result = app_script('open settings window').strip.downcase
    raise "open settings window returned '#{result}'" unless %w[true 1].include?(result)

    screenshot_path = capture_settings_screenshot if @capture_screenshots
    puts "📸 settings screenshot: #{screenshot_path}" if screenshot_path
    puts '✅ Settings window visual check ok'
  ensure
    close_settings_window_safely
  end

  def exercise_appearance_transition_visual_check
    return unless @capture_screenshots

    unless supports_applescript_command?('capture appearance overlay snapshot')
      raise 'Appearance transition smoke requires capture appearance overlay snapshot' if @require_appearance_transitions

      puts 'ℹ️ Skipping appearance transition visual check: capture command unavailable'
      return
    end

    baseline = capture_appearance_overlay_screenshot('baseline')
    unless baseline
      raise 'Appearance transition smoke requires a visible custom appearance overlay' if @require_appearance_transitions

      puts 'ℹ️ Skipping appearance transition visual check: custom appearance overlay is not visible'
      return
    end
    assert_appearance_tint_snapshot!(baseline, 'baseline')
    assert_customer_visible_top_strip_tint!('baseline', expected_visible: true)

    open_full_width_transition_probe_window
    sleep_with_watchdog(0.5)
    maximized = capture_appearance_overlay_screenshot('maximized-host')
    raise 'Appearance overlay was not visible over a maximized/full-width host window' unless maximized
    assert_appearance_tint_snapshot!(maximized, 'maximized-host')
    assert_customer_visible_top_strip_tint!('maximized-host', expected_visible: true)
    mark_fullscreen_matrix_scenario('maximized desktop window below the menu bar')

    exercise_app_activation_tint_stability_check
    exercise_visible_fullscreen_transition_pixel_check
    assert_required_fullscreen_runtime_settings!
    write_fullscreen_matrix_artifact!

    puts "✅ Appearance transition visual check ok: #{[baseline, maximized].compact.join(', ')}"
  ensure
    close_visible_transition_probe_window_safely(FULLSCREEN_TRANSITION_PROBE_APPS.first)
  end

  def exercise_app_activation_tint_stability_check
    return unless @require_visible_appearance_pixels

    FULLSCREEN_TRANSITION_PROBE_APPS.each do |probe|
      begin
        open_visible_transition_probe_window(probe)
        sleep_with_watchdog(0.2)
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-activation-immediate", expected_visible: true)
        sleep_with_watchdog(0.7)
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-activation-settled", expected_visible: true)
        mark_fullscreen_matrix_scenario('app activation keeps dark custom tint visible')
      rescue StandardError => e
        handle_transition_probe_failure(probe, 'activation tint stability', e)
      ensure
        close_visible_transition_probe_window_safely(probe)
      end
    end

    puts '✅ App activation tint stability ok'
  end

  def exercise_visible_fullscreen_transition_pixel_check
    return unless @require_visible_appearance_pixels

    FULLSCREEN_TRANSITION_PROBE_APPS.each do |probe|
      begin
        open_visible_transition_probe_window(probe)
        sleep_with_watchdog(0.4)

        set_fullscreen_probe_window(probe, true)
        sleep_with_watchdog(FULLSCREEN_APPEARANCE_SETTLE_SECONDS)
        assert_fullscreen_probe_window_state!(probe, true)
        assert_appearance_overlay_hidden_after_fullscreen_settle!("#{probe[:label]} fullscreen enter")
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-fullscreen-enter", expected_visible: false)

        sleep_with_watchdog(0.8)

        set_fullscreen_probe_window(probe, false)
        sleep_with_watchdog(FULLSCREEN_APPEARANCE_SETTLE_SECONDS)
        assert_fullscreen_probe_window_state!(probe, false)
        assert_appearance_overlay_restored_after_fullscreen_settle!("#{probe[:label]}-fullscreen-exit")
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-fullscreen-exit", expected_visible: true)
        mark_fullscreen_matrix_scenario('native fullscreen enter and exit')
      rescue StandardError => e
        handle_transition_probe_failure(probe, 'fullscreen transition', e)
      ensure
        set_fullscreen_probe_window(probe, false) if probe
        close_visible_transition_probe_window_safely(probe)
      end
    end

    puts '✅ Visible fullscreen transition contract ok'
  end

  def handle_transition_probe_failure(probe, context, error)
    raise error if probe.fetch(:required, true)

    puts "⚠️ Optional #{probe[:app]} #{context} probe skipped: #{error.message}"
  end

  def assert_customer_visible_top_strip_tint!(label, expected_visible:)
    return unless @require_visible_appearance_pixels

    path = capture_customer_visible_top_strip(label)
    stats = self.class.appearance_tint_pixel_stats(path, max_rows: CUSTOMER_VISIBLE_TOP_STRIP_HEIGHT)
    visible = self.class.visible_orange_tint_pixel_stats?(stats)
    if expected_visible && !visible
      raise "Customer-visible top-strip tint missing for #{label}: #{stats.inspect}"
    elsif !expected_visible && visible
      raise "Customer-visible top-strip tint still visible for #{label}: #{stats.inspect}"
    end

    message = expected_visible ? 'tint pixels ok' : 'overlay absent'
    puts "✅ Customer-visible top-strip #{message} (#{label}): #{stats.inspect}"
    mark_fullscreen_matrix_scenario('customer-visible menu-bar top-strip shade comparison, not only internal overlay snapshots')
  end

  def assert_appearance_overlay_hidden_after_fullscreen_settle!(label)
    path = capture_appearance_overlay_screenshot(label.gsub(/\s+/, '-'))
    return if path.nil?

    stats = self.class.appearance_tint_pixel_stats(path)
    raise "Appearance overlay remained visible after #{label}: #{File.basename(path)} #{stats.inspect}"
  end

  def assert_appearance_overlay_restored_after_fullscreen_settle!(label)
    path = capture_appearance_overlay_screenshot(label)
    raise "Appearance overlay did not restore after #{label}" unless path

    assert_appearance_tint_snapshot!(path, label)
  end

  def assert_appearance_tint_snapshot!(path, label)
    return unless @require_appearance_tint_pixels

    stats = self.class.appearance_tint_pixel_stats(path)
    unless self.class.orange_tint_pixel_stats?(stats)
      raise "Appearance overlay #{label} did not contain the expected orange tint pixels: #{stats.inspect}"
    end

    puts "✅ Appearance tint pixels ok (#{label}): #{stats.inspect}"
  end

  def capture_appearance_overlay_screenshot(label)
    FileUtils.mkdir_p(@screenshot_dir)
    path = File.join(
      @screenshot_dir,
      "sanebar-appearance-#{label}-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.png"
    )
    result = app_script(%(capture appearance overlay snapshot "#{escape_quotes(path)}")).strip.downcase
    return await_screenshot_file(path) if %w[true 1].include?(result)

    FileUtils.rm_f(path)
    nil
  rescue StandardError
    FileUtils.rm_f(path) if path
    nil
  end

  def capture_customer_visible_top_strip(label)
    FileUtils.mkdir_p(@screenshot_dir)
    path = File.join(
      @screenshot_dir,
      "sanebar-appearance-top-strip-#{label}-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.png"
    )
    if (screen_path = capture_customer_visible_screen_via_peekaboo(label, output_path: path))
      @fullscreen_matrix_artifacts << screen_path
      return screen_path
    end

    rect = main_display_top_strip_rect
    out, status = capture2e_with_timeout(
      '/usr/sbin/screencapture',
      '-x',
      "-R#{rect.join(',')}",
      path,
      timeout: SCREENSHOT_CAPTURE_TIMEOUT_SECONDS
    )
    raise "Could not capture customer-visible top strip #{label}: #{out.strip}" unless status.success?

    screenshot = await_screenshot_file(path)
    raise "Customer-visible top strip screenshot missing for #{label}" unless screenshot

    @fullscreen_matrix_artifacts << screenshot
    screenshot
  end

  def capture_customer_visible_screen_via_peekaboo(label, output_path: nil)
    peekaboo = resolve_peekaboo_capture_tool
    return nil unless peekaboo

    FileUtils.mkdir_p(TOP_STRIP_CAPTURE_WORKDIR)
    stamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
    safe_label = label.gsub(/[^A-Za-z0-9._-]+/, '-')
    screen_path = output_path || File.join(TOP_STRIP_CAPTURE_WORKDIR, "screen-#{safe_label}-#{stamp}.png")
    status_path = File.join(TOP_STRIP_CAPTURE_WORKDIR, "screen-#{safe_label}-#{stamp}.status")
    stdout_path = File.join(TOP_STRIP_CAPTURE_WORKDIR, "screen-#{safe_label}-#{stamp}.stdout")
    stderr_path = File.join(TOP_STRIP_CAPTURE_WORKDIR, "screen-#{safe_label}-#{stamp}.stderr")
    script_path = File.join(TOP_STRIP_CAPTURE_WORKDIR, "screen-#{safe_label}-#{stamp}.zsh")
    File.write(
      script_path,
      [
        '#!/bin/zsh',
        'set +e',
        '/usr/bin/osascript -e \'tell application "System Events" to if exists process "Terminal" then set visible of process "Terminal" to false\' >/dev/null 2>&1',
        'sleep 0.4',
        "#{Shellwords.escape(peekaboo)} image --mode screen --path #{Shellwords.escape(screen_path)} > #{Shellwords.escape(stdout_path)} 2> #{Shellwords.escape(stderr_path)}",
        "echo $? > #{Shellwords.escape(status_path)}"
      ].join("\n")
    )
    File.chmod(0o700, script_path)

    apple_script = <<~APPLESCRIPT
      on run argv
        tell application "Terminal"
          do script item 1 of argv
        end tell
      end run
    APPLESCRIPT
    _out, launch_status = capture2e_with_timeout(
      '/usr/bin/osascript',
      '-e',
      apple_script,
      "/bin/zsh #{Shellwords.escape(script_path)}; exit",
      timeout: APPLESCRIPT_TIMEOUT_SECONDS
    )
    return nil unless launch_status.success?

    hide_terminal_capture_host
    deadline = Time.now + SCREENSHOT_CAPTURE_TIMEOUT_SECONDS
    sleep 0.2 until File.exist?(status_path) || Time.now >= deadline
    close_terminal_capture_host
    return nil unless File.exist?(status_path)

    exit_status = File.read(status_path).to_i
    return nil unless exit_status.zero? && File.size?(screen_path)

    screen_path
  ensure
    close_terminal_capture_host
  end
end
