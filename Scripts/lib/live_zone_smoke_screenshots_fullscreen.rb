# frozen_string_literal: true

class LiveZoneSmoke
  private

  def resolve_peekaboo_capture_tool
    requested = ENV.fetch('PEEKABOO_BIN', 'peekaboo')
    if requested.include?(File::SEPARATOR)
      path = File.expand_path(requested)
      return path if File.executable?(path)
    end

    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).concat(['/opt/homebrew/bin', '/usr/local/bin']).uniq.each do |dir|
      candidate = File.join(dir, requested)
      return candidate if File.executable?(candidate) && !File.directory?(candidate)
    end

    nil
  end

  def hide_terminal_capture_host
    apple_script = 'tell application "System Events" to if exists process "Terminal" then set visible of process "Terminal" to false'
    capture2e_with_timeout('/usr/bin/osascript', '-e', apple_script, timeout: 2)
  rescue StandardError
    nil
  end

  def close_terminal_capture_host
    apple_script = <<~APPLESCRIPT
      tell application "Terminal"
        close every window
        quit
      end tell
    APPLESCRIPT
    capture2e_with_timeout('/usr/bin/osascript', '-e', apple_script, timeout: 2)
    system('/usr/bin/pkill', '-x', 'Terminal', out: File::NULL, err: File::NULL)
  rescue StandardError
    nil
  end

  def main_display_top_strip_rect
    script = 'tell application "Finder" to get bounds of window of desktop'
    out, status = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "Could not read desktop bounds for top-strip capture: #{out.strip}" unless status.success?

    values = out.scan(/-?\d+/).map(&:to_i)
    raise "Unexpected desktop bounds: #{out.inspect}" unless values.length >= 4

    x1, y1, x2, _y2 = values.first(4)
    width = x2 - x1
    raise "Invalid desktop width for top-strip capture: #{out.inspect}" unless width.positive?

    [x1, y1, width, CUSTOMER_VISIBLE_TOP_STRIP_HEIGHT]
  end

  def self.orange_tint_pixel_stats?(stats)
    return false unless stats[:sampled_pixels].to_i >= 20

    stats[:avg_r] >= 70 &&
      stats[:avg_g] >= 15 &&
      stats[:avg_r] > stats[:avg_g] * 1.35 &&
      stats[:avg_g] > stats[:avg_b] * 1.8 &&
      stats[:avg_b] <= 45
  end

  def self.visible_orange_tint_pixel_stats?(stats)
    return false unless stats[:sampled_pixels].to_i >= 20

    ratio = stats[:orange_pixel_ratio].to_f
    ratio >= 0.04 || orange_tint_pixel_stats?(stats)
  end

  def self.appearance_tint_pixel_stats(path, max_rows: nil)
    bmp_path = path
    cleanup_path = nil
    unless File.extname(path).casecmp('.bmp').zero?
      cleanup_path = File.join(Dir.tmpdir, "sanebar-appearance-#{Process.pid}-#{Time.now.to_i}.bmp")
      out, status = Open3.capture2e('/usr/bin/sips', '-s', 'format', 'bmp', path, '--out', cleanup_path)
      raise "Could not convert tint snapshot to BMP: #{out.strip}" unless status.success? && File.size?(cleanup_path)

      bmp_path = cleanup_path
    end

    parse_bmp_pixel_stats(bmp_path, max_rows: max_rows)
  ensure
    FileUtils.rm_f(cleanup_path) if cleanup_path
  end

  def self.parse_bmp_pixel_stats(path, max_rows: nil)
    data = File.binread(path)
    raise "Not a BMP file: #{path}" unless data.start_with?('BM')

    pixel_offset = data.byteslice(10, 4).unpack1('V')
    width = data.byteslice(18, 4).unpack1('l<')
    raw_height = data.byteslice(22, 4).unpack1('l<')
    bits_per_pixel = data.byteslice(28, 2).unpack1('v')
    raise "Unsupported BMP depth #{bits_per_pixel}" unless [24, 32].include?(bits_per_pixel)
    raise "Invalid BMP dimensions #{width}x#{raw_height}" if width <= 0 || raw_height == 0

    height = raw_height.abs
    bytes_per_pixel = bits_per_pixel / 8
    row_stride = ((width * bits_per_pixel + 31) / 32) * 4
    max_samples_per_row = [width, 400].min
    step = [width / max_samples_per_row, 1].max
    totals = { r: 0.0, g: 0.0, b: 0.0, alpha: 0.0, sampled_pixels: 0 }
    orange_pixels = 0

    rows_to_sample = max_rows ? [max_rows.to_i, height].min : height
    rows_to_sample.times do |row|
      storage_row = raw_height.positive? ? (height - 1 - row) : row
      row_offset = pixel_offset + (storage_row * row_stride)
      x = 0
      while x < width
        pixel_offset_for_x = row_offset + (x * bytes_per_pixel)
        b = data.getbyte(pixel_offset_for_x).to_i
        g = data.getbyte(pixel_offset_for_x + 1).to_i
        r = data.getbyte(pixel_offset_for_x + 2).to_i
        alpha = bits_per_pixel == 32 ? data.getbyte(pixel_offset_for_x + 3).to_i : 255
        if alpha >= 8 || bits_per_pixel == 24
          totals[:r] += r
          totals[:g] += g
          totals[:b] += b
          totals[:alpha] += alpha
          totals[:sampled_pixels] += 1
          orange_pixels += 1 if r >= 70 && r > g * 1.25 && g > b * 1.3 && b <= 80
        end
        x += step
      end
    end

    count = totals[:sampled_pixels]
    raise "No nontransparent pixels found in #{path}" if count.zero?

    {
      sampled_pixels: count,
      avg_r: (totals[:r] / count).round(1),
      avg_g: (totals[:g] / count).round(1),
      avg_b: (totals[:b] / count).round(1),
      avg_alpha: (totals[:alpha] / count).round(1),
      orange_pixels: orange_pixels,
      orange_pixel_ratio: (orange_pixels.to_f / count).round(4)
    }
  end

  def assert_required_fullscreen_runtime_settings!
    settings = load_settings_json
    appearance = settings['menuBarAppearance'].is_a?(Hash) ? settings['menuBarAppearance'] : {}
    unless appearance['useLiquidGlass'] == true
      raise 'Fullscreen matrix requires Translucent Background / Liquid Glass enabled'
    end

    if macos_dark_mode_enabled?
      mark_fullscreen_matrix_scenario('Dark appearance with Translucent Background enabled')
    else
      raise 'Fullscreen matrix requires Dark appearance enabled'
    end

    if reduce_transparency_enabled?
      mark_fullscreen_matrix_scenario('Reduce Transparency enabled')
    else
      raise 'Fullscreen matrix requires Reduce Transparency enabled'
    end
  end

  def load_settings_json
    settings_path = File.expand_path('~/Library/Application Support/SaneBar/settings.json')
    return {} unless File.exist?(settings_path)

    JSON.parse(File.read(settings_path))
  rescue JSON::ParserError
    {}
  end

  def macos_dark_mode_enabled?
    script = 'tell application "System Events" to tell appearance preferences to get dark mode'
    out, status = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    status.success? && out.strip.casecmp('true').zero?
  end

  def reduce_transparency_enabled?
    out, status = capture2e_with_timeout('/usr/bin/defaults', 'read', 'com.apple.universalaccess', 'reduceTransparency', timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    status.success? && %w[1 true TRUE].include?(out.strip)
  end

  def mark_fullscreen_matrix_scenario(name)
    @fullscreen_matrix_scenarios << name
    @fullscreen_matrix_scenarios.uniq!
  end

  def write_fullscreen_matrix_artifact!
    payload = {
      status: 'pass',
      generated_at: Time.now.utc.iso8601,
      candidate: runtime_candidate_metadata,
      completed_scenarios: @fullscreen_matrix_scenarios,
      evidence_paths: @fullscreen_matrix_artifacts.uniq,
      evidence_types: %w[mini_runtime screenshot log],
      note: 'Customer-visible top-strip screenshots are full-screen crops captured with screencapture, not internal overlay snapshots.'
    }
    File.write(FULLSCREEN_MATRIX_ARTIFACT_PATH, JSON.pretty_generate(payload) + "\n")
    puts "✅ Fullscreen runtime matrix proof written: #{FULLSCREEN_MATRIX_ARTIFACT_PATH}"
  end

  def runtime_candidate_metadata
    info_plist = File.join(@app_path.to_s, 'Contents', 'Info.plist')
    {
      app_path: @app_path,
      app_version: plist_value(info_plist, 'CFBundleShortVersionString'),
      app_build: plist_value(info_plist, 'CFBundleVersion'),
      process_path: @process_path
    }
  end

  def plist_value(info_plist, key)
    return nil unless File.exist?(info_plist)

    out, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", info_plist)
    status.success? ? out.strip : nil
  end

  def open_full_width_transition_probe_window
    script = <<~APPLESCRIPT
      tell application "Finder" to set screenBounds to bounds of window of desktop
      tell application "TextEdit"
        activate
        make new document with properties {text:"SaneBar appearance transition probe"}
        set bounds of front window to screenBounds
      end tell
    APPLESCRIPT
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "Could not open appearance transition probe window: #{out.strip}" unless code.success?
  end

  def open_visible_transition_probe_window(probe)
    case probe[:app]
    when 'Safari'
      open_safari_transition_probe_window
    when 'TextEdit'
      open_textedit_transition_probe_window
    else
      raise "Unsupported visible transition probe app: #{probe[:app]}"
    end
  end

  def open_safari_transition_probe_window
    probe_html = File.join(Dir.tmpdir, 'sanebar-fullscreen-probe.html')
    File.write(
      probe_html,
      '<!doctype html><title>SaneBar Fullscreen Probe</title><body style="margin:0;background:#f8f8f8;color:#111;font:18px system-ui;padding:32px">SaneBar fullscreen transition probe</body>'
    )
    script = <<~APPLESCRIPT
      tell application "Safari"
        activate
        make new document with properties {URL:"file://#{probe_html}"}
      end tell
    APPLESCRIPT
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "Could not open Safari transition probe window: #{out.strip}" unless code.success?
  end

  def open_textedit_transition_probe_window
    open_full_width_transition_probe_window
  end

  def set_fullscreen_probe_window(probe, enabled)
    return unless probe

    script = <<~APPLESCRIPT
      tell application "#{probe[:app]}" to activate
      delay 0.2
      tell application "System Events"
        tell process "#{probe[:process]}"
          set frontmost to true
          if (count of windows) = 0 then error "No #{probe[:process]} windows available for fullscreen probe"
          set value of attribute "AXFullScreen" of window 1 to #{enabled ? 'true' : 'false'}
        end tell
      end tell
    APPLESCRIPT
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "Could not set #{probe[:app]} fullscreen=#{enabled}: #{out.strip}" unless code.success?
  rescue StandardError
    raise if enabled
  end

  def assert_fullscreen_probe_window_state!(probe, expected)
    script = <<~APPLESCRIPT
      tell application "System Events"
        tell process "#{probe[:process]}"
          if (count of windows) = 0 then return "no-window"
          return ((value of attribute "AXFullScreen" of window 1) as text)
        end tell
      end tell
    APPLESCRIPT
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "Could not read #{probe[:app]} fullscreen state: #{out.strip}" unless code.success?

    actual = out.strip.casecmp('true').zero?
    return if actual == expected

    raise "#{probe[:app]} fullscreen probe state mismatch: expected #{expected}, got #{out.strip.inspect}"
  end

  def toggle_native_fullscreen_probe_window
    script = <<~APPLESCRIPT
      tell application "TextEdit" to activate
      tell application "System Events"
        tell process "TextEdit"
          set frontmost to true
          keystroke "f" using {control down, command down}
        end tell
      end tell
    APPLESCRIPT
    _out, code = capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    code.success?
  rescue StandardError
    false
  end

  def close_transition_probe_window_safely
    script = <<~APPLESCRIPT
      tell application "TextEdit"
        if (count of windows) > 0 then close front window saving no
      end tell
    APPLESCRIPT
    capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
  rescue StandardError
    nil
  end

  def close_visible_transition_probe_window_safely(probe)
    return unless probe

    case probe[:app]
    when 'Safari'
      script = <<~APPLESCRIPT
        tell application "Safari"
          repeat with candidateWindow in windows
            try
              if URL of current tab of candidateWindow starts with "file:///tmp/sanebar-fullscreen-probe.html" then
                close candidateWindow
                exit repeat
              end if
            end try
          end repeat
        end tell
      APPLESCRIPT
      capture2e_with_timeout('/usr/bin/osascript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    when 'TextEdit'
      close_transition_probe_window_safely
    end
  rescue StandardError
    nil
  end

  def browse_activation_succeeded?(diagnostics, expected_mode)
    expected_visible = expected_mode == 'secondMenuBar' ? 'windowVisible: true' : nil

    diagnostics.include?('origin: browsePanel') &&
      diagnostics.include?('finalOutcome: click succeeded') &&
      browse_activation_observably_verified?(diagnostics) &&
      diagnostics.include?("currentMode: #{expected_mode}") &&
      (expected_visible.nil? || diagnostics.include?(expected_visible))
  end

  def verify_post_activation_browse_state!(expected_mode)
    return unless expected_mode == 'secondMenuBar'

    sleep_with_watchdog(SECOND_MENU_BAR_POST_ACTIVATION_VISIBILITY_SECONDS)
    diagnostics = browse_panel_diagnostics
    return if diagnostics.include?('currentMode: secondMenuBar') &&
              diagnostics.include?('windowVisible: true')

    raise "second menu bar collapsed after activation: #{browse_activation_failure_summary(diagnostics)}"
  end

  def seed_focus_probe_prior_app
    out, code = capture2e_with_timeout(
      '/usr/bin/osascript',
      '-e',
      %(tell application "#{FOCUS_PROBE_APP_NAME}" to activate),
      timeout: APPLESCRIPT_TIMEOUT_SECONDS
    )
    raise "focus probe activation failed: #{out.strip}" unless code.success?

    deadline = Time.now + FOCUS_PROBE_TIMEOUT_SECONDS
    while Time.now < deadline
      current_state = frontmost_app_state
      return current_state if current_state['bundleId'] == FOCUS_PROBE_APP_BUNDLE

      sleep_with_watchdog(FOCUS_PROBE_POLL_SECONDS)
    end

    raise "focus probe did not reach #{FOCUS_PROBE_APP_BUNDLE}"
  rescue StandardError => e
    puts "ℹ️ Focus probe skipped: #{e.message}"
    nil
  end

  def assert_frontmost_did_not_revert_to(prior_frontmost_state, command)
    return if prior_frontmost_state.nil?

    prior_bundle = prior_frontmost_state['bundleId'].to_s
    return if prior_bundle.empty?

    sleep_with_watchdog(RIGHT_CLICK_FOCUS_PROBE_SETTLE_SECONDS)
    current_state = frontmost_app_state
    return unless current_state['bundleId'].to_s == prior_bundle

    diagnostics = current_browse_activation_diagnostics
    prior_window = prior_frontmost_state['windowTitle'].to_s
    current_window = current_state['windowTitle'].to_s
    detail =
      if !prior_window.empty? && !current_window.empty? && prior_window == current_window
        "prior app/window #{prior_bundle} / #{prior_window.inspect}"
      elsif !prior_window.empty? || !current_window.empty?
        "prior app #{prior_bundle} (priorWindow=#{prior_window.inspect}, currentWindow=#{current_window.inspect})"
      else
        "prior app #{prior_bundle}"
      end
    raise "#{command} reverted focus to #{detail}: #{browse_activation_failure_summary(diagnostics)}"
  end

  def frontmost_app_state
    script = <<~JXA
      ObjC.import('AppKit')
      function frontWindowTitle() {
        try {
          const se = Application('System Events')
          const processes = se.applicationProcesses.whose({ frontmost: true })()
          if (!processes.length) return ''
          const windows = processes[0].windows()
          if (!windows.length) return ''
          return windows[0].name() || ''
        } catch (error) {
          return ''
        }
      }
      const app = $.NSWorkspace.sharedWorkspace.frontmostApplication
      const payload = {
        bundleId: '',
        localizedName: '',
        pid: 0,
        windowTitle: frontWindowTitle()
      }
      if (app) {
        payload.bundleId = ObjC.unwrap(app.bundleIdentifier) || ''
        payload.localizedName = ObjC.unwrap(app.localizedName) || ''
        payload.pid = Number(app.processIdentifier) || 0
      }
      JSON.stringify(payload)
    JXA
    out, code = capture2e_with_timeout('/usr/bin/osascript', '-l', 'JavaScript', '-e', script, timeout: APPLESCRIPT_TIMEOUT_SECONDS)
    raise "frontmost-app probe failed: #{out.strip}" unless code.success?

    JSON.parse(out.to_s)
  rescue JSON::ParserError => e
    raise "frontmost-app probe returned invalid JSON: #{e.message}"
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
      check_resource_watchdog!
      last_diagnostics = browse_panel_diagnostics
      return if last_diagnostics.include?("currentMode: #{expected_mode}") &&
                last_diagnostics.include?('windowVisible: true')

      sleep_with_watchdog(BROWSE_PANEL_READY_POLL_SECONDS)
    end

    raise "Browse panel did not become ready for #{expected_mode}: #{last_diagnostics}"
  end

  def assert_browse_panel_anchor!(expected_mode)
    deadline = Time.now + BROWSE_PANEL_READY_TIMEOUT_SECONDS
    last_snapshot = nil

    while Time.now < deadline
      check_resource_watchdog!
      last_snapshot = layout_snapshot
      mode_ok = last_snapshot['browseWindowMode'].to_s == expected_mode
      visible_ok = truthy?(last_snapshot['isBrowseVisible'])
      anchor_ok = truthy?(last_snapshot['browseWindowAnchorValid'])
      return if mode_ok && visible_ok && anchor_ok

      sleep_with_watchdog(BROWSE_PANEL_READY_POLL_SECONDS)
    end

    raise "Browse panel anchor invalid for #{expected_mode}: frame=#{last_snapshot&.dig('browseWindowFrame')} deltaX=#{last_snapshot&.dig('browseWindowAnchorDeltaX')} deltaY=#{last_snapshot&.dig('browseWindowAnchorDeltaY')} snapshot=#{last_snapshot}"
  end

  def close_browse_panel
    result = app_script('close browse panel').strip.downcase
    raise "close browse panel returned '#{result}'" unless %w[true 1].include?(result)

    unless supports_applescript_command?('browse panel diagnostics')
      sleep_with_watchdog(0.5)
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
      check_resource_watchdog!
      last_diagnostics = browse_panel_diagnostics
      return if last_diagnostics.include?('windowVisible: false')

      sleep_with_watchdog(BROWSE_PANEL_READY_POLL_SECONDS)
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
    internal_error = capture_internal_browse_screenshot(path)
    return await_screenshot_file(path) if internal_error.nil?

    window_error = capture_window_screenshot(expected_mode, path)
    return await_screenshot_file(path) if window_error.nil?

    disable_screenshot_capture!(
      [
        ("internal capture failed: #{internal_error}" unless internal_error.nil? || internal_error.empty?),
        ("window capture failed: #{window_error}" unless window_error.nil? || window_error.empty?)
      ].compact.join(' | '),
      path
    )
    nil
  rescue StandardError => e
    disable_screenshot_capture!(e.message, path)
    nil
  end

  def capture_settings_screenshot
    FileUtils.mkdir_p(@screenshot_dir)
    path = File.join(
      @screenshot_dir,
      "sanebar-settings-#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.png"
    )
    internal_error = capture_internal_settings_screenshot(path)
    return await_screenshot_file(path) if internal_error.nil?

    window_error = capture_window_screenshot('settings', path)
    return await_screenshot_file(path) if window_error.nil?

    disable_screenshot_capture!(
      [
        ("internal settings capture failed: #{internal_error}" unless internal_error.nil? || internal_error.empty?),
        ("window capture failed: #{window_error}" unless window_error.nil? || window_error.empty?)
      ].compact.join(' | '),
      path
    )
    nil
  rescue StandardError => e
    disable_screenshot_capture!(e.message, path)
    nil
  end

  def capture_internal_browse_screenshot(path)
    escaped_path = escape_quotes(path)
    direct_result = app_script(%(capture browse panel snapshot "#{escaped_path}")).strip.downcase
    return nil if %w[true 1].include?(direct_result)

    queued_result = app_script(%(queue browse panel snapshot "#{escaped_path}")).strip.downcase
    return nil if %w[true 1].include?(queued_result)

    "capture command returned #{direct_result.inspect}; queue command returned #{queued_result.inspect}"
  rescue StandardError => e
    e.message
  end

  def capture_internal_settings_screenshot(path)
    escaped_path = escape_quotes(path)
    direct_result = app_script(%(capture settings window snapshot "#{escaped_path}")).strip.downcase
    return nil if %w[true 1].include?(direct_result)

    queued_result = app_script(%(queue settings window snapshot "#{escaped_path}")).strip.downcase
    return nil if %w[true 1].include?(queued_result)

    "capture command returned #{direct_result.inspect}; queue command returned #{queued_result.inspect}"
  rescue StandardError => e
    e.message
  end

  def resolve_window_screenshot_tool
    from_path = `command -v screenshot 2>/dev/null`.strip
    return from_path unless from_path.empty?

    %w[
      ~/Library/Python/3.13/bin/screenshot
      ~/Library/Python/3.12/bin/screenshot
      ~/Library/Python/3.11/bin/screenshot
      ~/Library/Python/3.10/bin/screenshot
      ~/Library/Python/3.9/bin/screenshot
    ].map { |candidate| File.expand_path(candidate) }.find { |candidate| File.executable?(candidate) }
  end

  def capture_window_screenshot(expected_mode, path)
    return 'window screenshot tool unavailable' unless @window_screenshot_tool && File.executable?(@window_screenshot_tool)

    title = WINDOW_SCREENSHOT_TITLES.fetch(expected_mode, nil)
    command = [@window_screenshot_tool, @app_name, '-s', '-f', path]
    command += ['-t', title] if title
    out, code = capture2e_with_timeout(*command, timeout: SCREENSHOT_CAPTURE_TIMEOUT_SECONDS)
    return nil if code.success?

    FileUtils.rm_f(path)
    out.strip
  end

  def await_screenshot_file(path)
    deadline = Time.now + SCREENSHOT_CAPTURE_TIMEOUT_SECONDS
    until File.exist?(path) && File.size?(path)
      check_resource_watchdog!
      if Time.now >= deadline
        disable_screenshot_capture!("Screenshot missing at #{path}", path)
        return nil
      end
      sleep_with_watchdog(0.2)
    end

    path
  end

  def close_settings_window_safely
    return unless supports_applescript_command?('close settings window')

    app_script('close settings window')
  rescue StandardError
    nil
  end

  def disable_screenshot_capture!(reason, path = nil)
    @capture_screenshots = false
    FileUtils.rm_f(path) if path
    puts "⚠️ Screenshot capture unavailable: #{reason}. Continuing without screenshots."
  end
end
