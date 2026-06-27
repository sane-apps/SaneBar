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

    close_settings_window_for_visual_probe!('appearance transition setup')

    baseline = capture_appearance_overlay_screenshot('baseline')
    unless baseline
      raise 'Appearance transition smoke requires a visible custom appearance overlay' if @require_appearance_transitions

      puts 'ℹ️ Skipping appearance transition visual check: custom appearance overlay is not visible'
      return
    end
    assert_appearance_tint_snapshot!(baseline, 'baseline')
    assert_customer_visible_top_strip_tint!('baseline', expected_visible: true)

    # Owner ruling (2026-06-26): SaneBar's OWN UI appearance (the menu-bar overlay
    # tint verified by the baseline above + the settings/browse screenshots) stays.
    # What's removed is the set of probes that LAUNCH Safari and TextEdit and drive
    # their windows fullscreen/maximized to check SaneBar's overlay over THEM. That
    # external-app automation is brittle (it hung on Safari today), tests a
    # long-solved/stable behavior, and is not SaneBar's UI. The fullscreen matrix
    # (open_full_width/visible transition probes + the fullscreen_maximize_transition
    # runtime state) is dropped accordingly. Re-add real coverage only if a
    # regression in overlay-over-fullscreen ever actually recurs.
    puts "✅ Appearance baseline tint ok (SaneBar menu-bar overlay): #{baseline}"
  end

  def exercise_app_activation_tint_stability_check
    return unless @require_visible_appearance_pixels

    FULLSCREEN_TRANSITION_PROBE_APPS.each do |probe|
      begin
        open_visible_transition_probe_window(probe)
        sleep_with_watchdog(0.2)
        assert_frontmost_probe_surface!(probe, "#{probe[:label]} activation", fullscreen_expected: false)
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-activation-immediate", expected_visible: true)
        sleep_with_watchdog(0.7)
        assert_frontmost_probe_surface!(probe, "#{probe[:label]} activation settled", fullscreen_expected: false)
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
        zone_baseline = capture_fullscreen_space_transition_zone_baseline!

        set_fullscreen_probe_window(probe, true)
        sleep_with_watchdog(FULLSCREEN_APPEARANCE_SETTLE_SECONDS)
        assert_fullscreen_probe_window_state!(probe, true)
        assert_frontmost_probe_surface!(probe, "#{probe[:label]} fullscreen enter", fullscreen_expected: true)
        assert_appearance_overlay_hidden_after_fullscreen_settle!("#{probe[:label]} fullscreen enter")
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-fullscreen-enter", expected_visible: false, restore_bundle_id: probe[:bundle])
        assert_fullscreen_space_transition_zone_persistence!(zone_baseline, "#{probe[:label]} fullscreen enter")

        sleep_with_watchdog(0.8)

        set_fullscreen_probe_window(probe, false)
        ensure_visible_transition_probe_window_available!(probe)
        sleep_with_watchdog(FULLSCREEN_APPEARANCE_SETTLE_SECONDS)
        assert_fullscreen_probe_window_state!(probe, false)
        assert_frontmost_probe_surface!(probe, "#{probe[:label]} fullscreen exit", fullscreen_expected: false)
        assert_appearance_overlay_restored_after_fullscreen_settle!("#{probe[:label]}-fullscreen-exit")
        assert_customer_visible_top_strip_tint!("#{probe[:label]}-fullscreen-exit", expected_visible: true, restore_bundle_id: probe[:bundle])
        assert_fullscreen_space_transition_zone_persistence!(zone_baseline, "#{probe[:label]} fullscreen exit")
        mark_fullscreen_matrix_scenario('native fullscreen enter and exit')
        mark_fullscreen_matrix_scenario('hidden and visible icon zones persist across fullscreen Space transition')
      rescue StandardError => e
        handle_transition_probe_failure(probe, 'fullscreen transition', e)
      ensure
        set_fullscreen_probe_window(probe, false) if probe
        close_visible_transition_probe_window_safely(probe)
      end
    end

    puts '✅ Visible fullscreen transition contract ok'
  end

  def capture_fullscreen_space_transition_zone_baseline!
    zones = wait_for_zone_api_ready
    candidates = candidate_pool(zones)
    visible_ids = fullscreen_space_transition_zone_ids(candidates, expected_zone: 'visible')
    if visible_ids.empty?
      visible_ids = fullscreen_space_transition_zone_ids(zones, expected_zone: 'visible')
    end
    baseline = {
      visible_ids: visible_ids,
      hidden_ids: fullscreen_space_transition_zone_ids(candidates, expected_zone: 'hidden')
    }

    raise 'Fullscreen transition proof could not find baseline visible IDs' if baseline[:visible_ids].empty?
    raise 'Fullscreen transition proof could not find baseline hidden IDs' if baseline[:hidden_ids].empty?

    baseline
  end

  def fullscreen_space_transition_zone_ids(zones, expected_zone:, limit: 3)
    zones.select do |item|
      item[:zone] == expected_zone &&
        item[:bundle].to_s != 'com.sanebar.app' &&
        !item[:unique_id].to_s.start_with?('com.sanebar.app::')
    end.reject { |item| likely_standard_app_menu_candidate?(item) }
      .map { |item| item[:unique_id].to_s.empty? ? item[:bundle].to_s : item[:unique_id].to_s }
      .reject(&:empty?)
      .uniq
      .first(limit)
  end

  def assert_fullscreen_space_transition_zone_persistence!(baseline, label)
    visible_ids = Array(baseline[:visible_ids]).map(&:to_s)
    hidden_ids = Array(baseline[:hidden_ids]).map(&:to_s)
    deadline = Time.now + LAYOUT_STABILIZE_TIMEOUT_SECONDS
    last_problem = nil

    while Time.now < deadline
      begin
        zones = list_icon_zones
      rescue StandardError => e
        last_problem = { zone_api_error: e.message }
        raise unless retryable_zone_poll_error?(e)

        sleep_with_watchdog(LAYOUT_STABILIZE_POLL_SECONDS)
        next
      end
      zone_lookup = zones.each_with_object({}) do |item, lookup|
        unique_id = item[:unique_id].to_s
        bundle = item[:bundle].to_s
        lookup[unique_id] = item unless unique_id.empty?
        lookup[bundle] = item unless bundle.empty?
      end

      moved_visible = visible_ids.reject { |identifier| zone_lookup[identifier]&.fetch(:zone, nil) == 'visible' }
      moved_hidden = hidden_ids.reject { |identifier| zone_lookup[identifier]&.fetch(:zone, nil) == 'hidden' }
      if moved_visible.empty? && moved_hidden.empty?
        puts "✅ Fullscreen Space transition zone persistence ok (#{label})"
        return
      end

      last_problem = {
        moved_visible: moved_visible,
        moved_hidden: moved_hidden
      }
      sleep_with_watchdog(LAYOUT_STABILIZE_POLL_SECONDS)
    end

    raise "Fullscreen Space transition changed icon zones after #{label}: #{last_problem.inspect}"
  end

  def handle_transition_probe_failure(probe, context, error)
    raise error if probe.fetch(:required, true)

    puts "⚠️ Optional #{probe[:app]} #{context} probe skipped: #{error.message}"
  end

  def assert_customer_visible_top_strip_tint!(label, expected_visible:, restore_bundle_id: nil)
    return unless @require_visible_appearance_pixels

    path = capture_customer_visible_top_strip(label, restore_bundle_id: restore_bundle_id)
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

  def capture_customer_visible_top_strip(label, restore_bundle_id: nil)
    FileUtils.mkdir_p(@screenshot_dir)
    path = File.join(
      @screenshot_dir,
      "sanebar-appearance-top-strip-#{label}-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.png"
    )
    if (crop_path = capture_customer_visible_top_strip_via_mini_gui(label, output_path: path, restore_bundle_id: restore_bundle_id))
      @fullscreen_matrix_artifacts << crop_path
      return crop_path
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

  def capture_customer_visible_top_strip_via_mini_gui(label, output_path:, restore_bundle_id: nil)
    runner = resolve_mini_gui_runner_tool
    return nil unless runner

    FileUtils.mkdir_p(top_strip_capture_workdir)
    prune_top_strip_capture_workdir!
    stamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
    safe_label = label.gsub(/[^A-Za-z0-9._-]+/, '-')
    x, y, width, height = main_display_top_strip_rect
    screencapture_rect = [x, y, width, height].join(',')

    last_failure = nil
    2.times do |attempt|
      attempt_stamp = attempt.zero? ? stamp : "#{stamp}-retry#{attempt + 1}"
      stdout_path = File.join(top_strip_capture_workdir, "screen-crop-#{safe_label}-#{attempt_stamp}.stdout")
      runner_log_path = File.join(top_strip_capture_workdir, "screen-crop-#{safe_label}-#{attempt_stamp}.log")
      runner_status_path = File.join(top_strip_capture_workdir, "screen-crop-#{safe_label}-#{attempt_stamp}.status")
      command = [
        'set -euo pipefail',
        "rm -f #{Shellwords.escape(output_path)}",
        [
          '/usr/sbin/screencapture',
          '-x',
          "-R#{screencapture_rect}",
          Shellwords.escape(output_path)
        ].join(' '),
        "test -s #{Shellwords.escape(output_path)}",
        "echo #{Shellwords.escape(output_path)}"
      ].join(' && ')

      out = nil
      status = nil
      begin
        runner_args = [
          runner,
          '--log-file',
          runner_log_path,
          '--status-file',
          runner_status_path,
          '--title',
          'SaneBar Top Strip Capture',
          '--close-window',
          '--poll-seconds',
          '1'
        ]
        if restore_bundle_id.to_s.empty?
          runner_args << '--restore-frontmost'
        else
          runner_args += ['--restore-bundle-id', restore_bundle_id.to_s]
        end
        runner_args += ['--', command]
        out, status = capture2e_with_timeout(
          *runner_args,
          timeout: SCREENSHOT_CAPTURE_TIMEOUT_SECONDS + 20
        )
      rescue StandardError => e
        last_failure = "#{e.message}; #{top_strip_capture_debug_details(runner_log_path, runner_status_path)}"
        sleep_with_watchdog(0.5) if attempt.zero?
        next
      end
      safe_top_strip_file_write(stdout_path, out)
      return await_screenshot_file(output_path) if status.success?

      last_failure = top_strip_capture_debug_details(runner_log_path, runner_status_path, wrapper_stdout: out)
      sleep_with_watchdog(0.5) if attempt.zero?
    end

    raise "Official Mini GUI top-strip capture failed for #{label}: #{last_failure}"
  end

  def top_strip_capture_workdir
    TOP_STRIP_CAPTURE_WORKDIR
  end

  def prune_top_strip_capture_workdir!
    dir = top_strip_capture_workdir
    return unless Dir.exist?(dir)

    entries = Dir.glob(File.join(dir, '*')).select { |path| safe_top_strip_regular_file?(path) }
    now = Time.now
    stale = entries.select do |path|
      now - File.lstat(path).mtime > TOP_STRIP_CAPTURE_ARTIFACT_RETENTION_SECONDS
    rescue StandardError
      false
    end
    FileUtils.rm_f(stale)

    remaining = (entries - stale).select { |path| safe_top_strip_regular_file?(path) }
    overflow = remaining.sort_by { |path| File.lstat(path).mtime }.reverse.drop(TOP_STRIP_CAPTURE_MAX_ARTIFACTS)
    FileUtils.rm_f(overflow)
  end

  def top_strip_capture_debug_details(log_path, status_path, wrapper_stdout: nil)
    details = ["log=#{log_path}", "status_file=#{status_path}"]
    if (status_content = safe_top_strip_file_read(status_path))
      status = status_content.strip
      details << "status=#{status.empty? ? '<empty>' : status}"
    else
      details << 'status=<missing-or-unsafe>'
    end
    lines = safe_top_strip_file_lines(log_path, limit: 12)
    if lines.any?
      details << "log_tail=#{lines.join(' | ')}" unless lines.empty?
    else
      details << 'log=<missing-or-unsafe>'
    end
    if wrapper_stdout && !wrapper_stdout.to_s.strip.empty?
      stdout_tail = wrapper_stdout.to_s.lines.last(8).map(&:strip).join(' | ')
      details << "wrapper_stdout=#{stdout_tail}"
    end
    details.join('; ')
  rescue StandardError => e
    "log=#{log_path}; status_file=#{status_path}; debug_unavailable=#{e.message}"
  end

  def safe_top_strip_file_read(path)
    return nil unless safe_top_strip_regular_file?(path)

    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(path, flags, &:read)
  rescue StandardError
    nil
  end

  def safe_top_strip_file_write(path, content)
    safe_top_strip_directory_path!(File.dirname(path))
    flags = File::WRONLY | File::CREAT | File::TRUNC
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(path, flags, 0o600) { |file| file.write(content.to_s) }
    true
  rescue StandardError
    false
  end

  def safe_top_strip_file_lines(path, limit:)
    content = safe_top_strip_file_read(path)
    return [] unless content

    content.lines(chomp: true).last(limit)
  end

  def safe_top_strip_regular_file?(path)
    return false if path.nil? || path.to_s.empty?

    safe_top_strip_directory_path!(File.dirname(path))
    stat = File.lstat(path)
    stat.file? && !stat.symlink?
  rescue StandardError
    false
  end

  def safe_top_strip_directory_path!(path)
    expanded = File.expand_path(path)
    current = expanded.start_with?(File::SEPARATOR) ? File::SEPARATOR : Dir.pwd
    expanded.split(File::SEPARATOR).reject(&:empty?).each do |part|
      current = current == File::SEPARATOR ? File.join(current, part) : File.join(current, part)
      next unless File.exist?(current)

      stat = File.lstat(current)
      if stat.symlink?
        real = File.realpath(current) rescue nil
        next if allowed_system_temp_directory_symlink?(current, real)

        raise "Unsafe top-strip capture directory symlink: #{current}"
      end
      raise "Top-strip capture parent is not a directory: #{current}" unless stat.directory?
    end
    true
  end

  def allowed_system_temp_directory_symlink?(path, real)
    expanded = File.expand_path(path)
    canonical = File.expand_path(real.to_s)
    return true if expanded == '/tmp' && canonical == '/private/tmp'
    return true if expanded == '/var' && canonical == '/private/var'

    expanded == File.expand_path(Dir.tmpdir) && canonical == File.realpath(Dir.tmpdir)
  rescue StandardError
    false
  end
end
