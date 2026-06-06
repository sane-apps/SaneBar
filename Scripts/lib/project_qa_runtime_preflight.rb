# frozen_string_literal: true

class ProjectQA
  private

  def check_runtime_release_smoke
    print 'Running release runtime smoke... '

    unless runtime_smoke_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1 or SANEBAR_RUN_RUNTIME_SMOKE=1)'
      return
    end

    unless running_on_mini_host?
      message = 'Runtime smoke must run on the mini via ./scripts/SaneMaster.rb so the local workspace syncs before release verification.'
      if preflight_mode?
        @errors << message
        puts '❌ not on mini'
      else
        @warnings << message
        puts '⚠️  not on mini'
      end
      return
    end

    smoke_script = File.join(SCRIPTS_DIR, 'live_zone_smoke.rb')
    unless File.exist?(smoke_script)
      @errors << "Runtime smoke script missing: #{smoke_script}"
      puts '❌ missing live_zone_smoke.rb'
      return
    end
    startup_probe_script = File.join(SCRIPTS_DIR, 'startup_layout_probe.rb')
    unless File.exist?(startup_probe_script)
      @errors << "Startup layout probe missing: #{startup_probe_script}"
      puts '❌ missing startup_layout_probe.rb'
      return
    end
    wake_probe_script = File.join(SCRIPTS_DIR, 'wake_layout_probe.rb')
    unless File.exist?(wake_probe_script)
      @errors << "Wake layout probe missing: #{wake_probe_script}"
      puts '❌ missing wake_layout_probe.rb'
      return
    end

    restore_mode = nil
    appearance_settings_backup = nil

    begin
      restore_mode, mode_error = ensure_runtime_smoke_pro_mode!
      if mode_error
        @errors << mode_error
        puts '❌ could not seed Pro smoke mode'
        return
      end

      screenshot_dir = File.expand_path("~/Desktop/Screenshots/#{PROJECT_NAME}")
      FileUtils.mkdir_p(screenshot_dir)
      Dir.glob(File.join(screenshot_dir, 'sanebar-*.png')).each { |path| FileUtils.rm_f(path) }
      FileUtils.rm_f(RUNTIME_SMOKE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_LAUNCH_LOG_PATH)
      FileUtils.rm_f(RUNTIME_WAKE_PROBE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_WAKE_PROBE_ARTIFACT_PATH)
      FileUtils.rm_f('/tmp/sanebar_runtime_fullscreen_matrix.json')
      FileUtils.rm_f(RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH)
      screenshot_capture_available = runtime_screenshot_capture_available?(screenshot_dir)
      release_smoke_screenshots_required = ENV.fetch('SANEBAR_RELEASE_SMOKE_SCREENSHOTS', '1') != '0'
      capture_runtime_smoke_screenshots = release_smoke_screenshots_required && screenshot_capture_available
      appearance_settings_backup = prepare_runtime_smoke_appearance_settings! if capture_runtime_smoke_screenshots
      if release_smoke_screenshots_required && !capture_runtime_smoke_screenshots
        @errors << 'Runtime smoke screenshot/tint evidence is required but unavailable on this host.'
        puts '❌ runtime smoke screenshot/tint evidence unavailable'
        return
      end
      prelaunch_runtime_shared_bundle_fixture!
      prelaunch_runtime_dynamic_helper_fixture!
      prelaunch_runtime_visible_dynamic_helper_fixture!

      launch_out, launch_status = Open3.capture2e(
        { 'SANEMASTER_ALLOW_UNSIGNED_FALLBACK' => '0' },
        SANEMASTER_CLI,
        'test_mode',
        '--release',
        '--no-logs'
      )
      File.write(RUNTIME_LAUNCH_LOG_PATH, launch_out)
      unless launch_status.success?
        @errors << "Runtime smoke launch failed. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ launch failed (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      target = runtime_smoke_target(launch_output: launch_out)
      unless target
        @errors << "Runtime smoke could not determine launch target. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ unknown launch target (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      target_error = validate_runtime_smoke_target(target)
      if target_error
        @errors << "#{target_error} See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ invalid runtime smoke target (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      unless ensure_runtime_smoke_target_running!(target)
        @errors << "Runtime smoke could not launch target #{target[:app_path]}. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ target launch failed (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      always_hidden_setup_error = ensure_runtime_smoke_always_hidden_ready!(target)
      if always_hidden_setup_error
        @errors << always_hidden_setup_error
        puts '❌ always-hidden runtime smoke setup failed'
        return
      end

      puts
      puts "   ↳ smoke target: #{target[:app_path]}"
      puts "   ↳ #{target[:note]}" if target[:note]

      smoke_env = {
        'SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN' => '0',
        'SANEBAR_SMOKE_REQUIRE_CANDIDATE' => '1',
        'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '1',
        'SANEBAR_SMOKE_WATCH_RESOURCES' => '1',
        'SANEBAR_SMOKE_MAX_CPU_PERCENT' => RUNTIME_SMOKE_MAX_CPU_PERCENT.to_s,
        'SANEBAR_SMOKE_MAX_CPU_BREACH_SAMPLES' => RUNTIME_SMOKE_MAX_CPU_BREACH_SAMPLES.to_s,
        'SANEBAR_SMOKE_EMERGENCY_CPU_PERCENT' => RUNTIME_SMOKE_EMERGENCY_CPU_PERCENT.to_s,
        'SANEBAR_SMOKE_MAX_RSS_MB' => RUNTIME_SMOKE_MAX_RSS_MB.to_s,
        'SANEBAR_SMOKE_MAX_RSS_BREACH_SAMPLES' => RUNTIME_SMOKE_MAX_RSS_BREACH_SAMPLES.to_s,
        'SANEBAR_SMOKE_EMERGENCY_RSS_MB' => RUNTIME_SMOKE_EMERGENCY_RSS_MB.to_s,
        'SANEBAR_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX' => RUNTIME_SMOKE_LAUNCH_IDLE_CPU_AVG_MAX.to_s,
        'SANEBAR_SMOKE_LAUNCH_IDLE_CPU_PEAK_MAX' => RUNTIME_SMOKE_LAUNCH_IDLE_CPU_PEAK_MAX.to_s,
        'SANEBAR_SMOKE_LAUNCH_IDLE_RSS_MB_MAX' => RUNTIME_SMOKE_LAUNCH_IDLE_RSS_MB_MAX.to_s,
        'SANEBAR_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS' => RUNTIME_SMOKE_POST_SMOKE_IDLE_SETTLE_SECONDS.to_s,
        'SANEBAR_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS' => RUNTIME_SMOKE_POST_SMOKE_IDLE_SAMPLE_SECONDS.to_s,
        'SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_AVG_MAX' => RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_AVG_MAX.to_s,
        'SANEBAR_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX' => RUNTIME_SMOKE_POST_SMOKE_IDLE_CPU_PEAK_MAX.to_s,
        'SANEBAR_SMOKE_POST_SMOKE_IDLE_RSS_MB_MAX' => RUNTIME_SMOKE_POST_SMOKE_IDLE_RSS_MB_MAX.to_s,
        'SANEBAR_SMOKE_ACTIVE_AVG_CPU_MAX' => RUNTIME_SMOKE_ACTIVE_AVG_CPU_MAX.to_s,
        'SANEBAR_SMOKE_ACTIVE_AVG_RSS_MB_MAX' => RUNTIME_SMOKE_ACTIVE_AVG_RSS_MB_MAX.to_s,
        'SANEBAR_SMOKE_CAPTURE_SCREENSHOTS' => capture_runtime_smoke_screenshots ? '1' : '0',
        'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TRANSITIONS' => capture_runtime_smoke_screenshots ? '1' : '0',
        'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TINT_PIXELS' => capture_runtime_smoke_screenshots ? '1' : '0',
        'SANEBAR_SMOKE_REQUIRE_VISIBLE_APPEARANCE_PIXELS' => capture_runtime_smoke_screenshots ? '1' : '0',
        'SANEBAR_SMOKE_SCREENSHOT_DIR' => screenshot_dir,
        'SANEBAR_SMOKE_APP_PATH' => target[:app_path],
        'SANEBAR_SMOKE_PROCESS_PATH' => target[:process_path],
        'SANEBAR_SMOKE_REQUIRE_NO_KEYCHAIN' => '0'
      }
      if capture_runtime_smoke_screenshots
        puts '   ↳ smoke screenshots enabled by SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1'
      elsif screenshot_capture_available
        puts '   ↳ smoke screenshots disabled for release gating (set SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 to opt in)'
      else
        puts '   ↳ screenshot capture unavailable on this host; continuing without smoke screenshots'
      end
      smoke_outputs = []
      default_move_coverage_deferred = false
      RUNTIME_SMOKE_PASSES.times do |index|
        pass_number = index + 1
        puts "   ↳ smoke pass #{pass_number}/#{RUNTIME_SMOKE_PASSES}"

        if pass_number > 1
          unless ensure_runtime_smoke_target_running!(target.merge(relaunch: true))
            File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
            @errors << "Runtime smoke could not relaunch target #{target[:app_path]} before pass #{pass_number}/#{RUNTIME_SMOKE_PASSES}. See #{RUNTIME_SMOKE_LOG_PATH}."
            puts "❌ relaunch failed before pass #{pass_number}/#{RUNTIME_SMOKE_PASSES} (#{RUNTIME_SMOKE_LOG_PATH})"
            return
          end
        end

        attempt = 0
        loop do
          attempt += 1
          resource_sample_path = "/tmp/sanebar_runtime_resource_sample-pass#{pass_number}-try#{attempt}.txt"
          FileUtils.rm_f(resource_sample_path)
          pass_env = smoke_env.merge('SANEBAR_SMOKE_RESOURCE_SAMPLE_PATH' => resource_sample_path)
          smoke_out, smoke_status = capture2e_with_progress(
            pass_env,
            smoke_script,
            heartbeat_label: "runtime smoke pass #{pass_number}/#{RUNTIME_SMOKE_PASSES} (try #{attempt})"
          )
          smoke_outputs << [
            "pass #{pass_number}/#{RUNTIME_SMOKE_PASSES} try #{attempt}",
            *runtime_smoke_candidate_lines(target),
            "resource_sample=#{resource_sample_path}",
            smoke_out
          ].join("\n")
          break if smoke_status.success?

          if attempt <= RUNTIME_SMOKE_RETRIES_PER_PASS && retryable_runtime_smoke_failure?(smoke_out)
            puts "   ↳ relaunching after transient runtime smoke failure (retry #{attempt}/#{RUNTIME_SMOKE_RETRIES_PER_PASS})"
            unless ensure_runtime_smoke_target_running!(target.merge(relaunch: true))
              File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
              @errors << "Runtime smoke retry could not relaunch target #{target[:app_path]}. See #{RUNTIME_SMOKE_LOG_PATH}."
              puts "❌ retry relaunch failed (#{RUNTIME_SMOKE_LOG_PATH})"
              return
            end
            next
          end

          if runtime_smoke_no_candidate_fixture_policy?(smoke_out)
            default_move_coverage_deferred = true
            puts '   ↳ default runtime fixture pool empty on this host; keeping browse/layout result and deferring coverage to shared-bundle exact-id smoke'
            break
          end

          File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
          sample_suffix = File.exist?(resource_sample_path) ? " Resource sample: #{resource_sample_path}" : ''
          @errors << "Runtime smoke failed on pass #{pass_number}/#{RUNTIME_SMOKE_PASSES}. See #{RUNTIME_SMOKE_LOG_PATH}.#{sample_suffix}"
          puts "❌ failed on pass #{pass_number}/#{RUNTIME_SMOKE_PASSES} (#{RUNTIME_SMOKE_LOG_PATH})"
          return
        end
      end

      File.write(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
      focused_runtime_smoke_ran = false
      shared_bundle_ids = runtime_smoke_available_shared_bundle_candidate_ids(
        target,
        required_ids: RUNTIME_SHARED_BUNDLE_IDS
      )
      if shared_bundle_ids.empty?
        shared_bundle_ids = ensure_runtime_shared_bundle_fixture!(target)
      end
      if shared_bundle_ids.empty?
        File.write(
          RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH,
          [
            'required_ids=',
            'resource_sample=',
            "default_move_pool_empty=#{default_move_coverage_deferred ? 1 : 0}",
            'shared_bundle_exact_id_pool_empty=1'
          ].join("\n")
        )
        @errors << "Runtime smoke had no shared-bundle exact-id candidates. Shared-bundle move regressions are release-blocking; the Mini needs either two movable Control Center/Clock/Focus/Wi-Fi/Battery/Display items or the deterministic shared-bundle fixture must launch. See #{RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH} and #{RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH}."
        puts "❌ shared-bundle exact-id smoke unavailable (#{RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH})"
        return
      else
        focused_runtime_smoke_ran = true
        return unless run_focused_runtime_smoke_exact_ids(
          target: target,
          smoke_env: smoke_env,
          smoke_script: smoke_script,
          exact_ids: shared_bundle_ids,
          log_path: RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH,
          lane_name: 'shared-bundle',
          retryable_failure_method: :retryable_shared_bundle_runtime_smoke_failure?
        )
      end

      native_apple_ids = runtime_smoke_available_required_candidate_ids(
        target,
        required_ids: RUNTIME_NATIVE_APPLE_IDS
      )
      if native_apple_ids.empty?
        puts '   ↳ native-apple exact-id smoke skipped (Siri/Spotlight not present on this host)'
      else
        focused_runtime_smoke_ran = true
        return unless run_focused_runtime_smoke_exact_ids(
          target: target,
          smoke_env: smoke_env,
          smoke_script: smoke_script,
          exact_ids: native_apple_ids,
          log_path: RUNTIME_NATIVE_APPLE_SMOKE_LOG_PATH,
          lane_name: 'native-apple exact-id',
          retryable_failure_method: :retryable_runtime_smoke_failure?
        )
      end

      host_fixture_ids = ensure_runtime_host_exact_id_fixture!(target)
      host_exact_id_ids = runtime_smoke_available_required_candidate_ids(
        target,
        required_ids: RUNTIME_HOST_EXACT_ID_SENTINEL_IDS
      )
      if host_exact_id_ids.empty?
        @errors << "Runtime smoke had no host exact-id sentinel candidates. Host-specific menu item movement is release-blocking; install or launch a deterministic sentinel before release. See #{RUNTIME_HOST_EXACT_ID_SMOKE_LOG_PATH} and #{RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH}."
        puts "❌ host exact-id smoke unavailable (#{RUNTIME_HOST_EXACT_ID_SMOKE_LOG_PATH})"
        return
      elsif host_fixture_ids.empty? && (host_exact_id_ids & RUNTIME_HOST_EXACT_ID_FIXTURE_IDS).empty?
        @warnings << "Host exact-id smoke used installed host item(s) only; deterministic sentinel unavailable. See #{RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH}."
      else
        focused_runtime_smoke_ran = true
        return unless run_focused_runtime_smoke_exact_ids(
          target: target,
          smoke_env: smoke_env,
          smoke_script: smoke_script,
          exact_ids: host_exact_id_ids,
          log_path: RUNTIME_HOST_EXACT_ID_SMOKE_LOG_PATH,
          lane_name: 'host exact-id',
          retryable_failure_method: :retryable_runtime_smoke_failure?
        )
      end

      if default_move_coverage_deferred && !focused_runtime_smoke_ran
        @errors << "Runtime smoke had no default fixture candidates and no focused exact-id fallback candidates. See #{RUNTIME_SMOKE_LOG_PATH}."
        puts "❌ no focused exact-id fallback candidates after default fixture miss (#{RUNTIME_SMOKE_LOG_PATH})"
        return
      end

      startup_probe_env = {
        'SANEBAR_SMOKE_APP_PATH' => target[:app_path],
        'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH,
        'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH
      }
      startup_probe_env.merge!(runtime_probe_no_keychain_env(target))
      startup_probe_out, startup_probe_status = capture2e_with_progress(
        startup_probe_env,
        startup_probe_script,
        heartbeat_label: 'runtime startup layout probe'
      )
      File.write("#{RUNTIME_STARTUP_PROBE_LOG_PATH}.stdout", startup_probe_out)
      unless startup_probe_status.success?
        @errors << "Startup layout probe failed. See #{RUNTIME_STARTUP_PROBE_LOG_PATH} and #{RUNTIME_STARTUP_PROBE_ARTIFACT_PATH}."
        puts "❌ startup probe failed (#{RUNTIME_STARTUP_PROBE_LOG_PATH})"
        return
      end

      dynamic_helper_ids = ensure_runtime_dynamic_helper_wake_fixture!(target)
      if dynamic_helper_ids.empty?
        @errors << "Wake layout probe had no deterministic dynamic-helper fixture. Lungo-style Hidden-to-Visible wake drift is release-blocking. See #{RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH}."
        puts "❌ dynamic-helper wake fixture unavailable (#{RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH})"
        return
      end
      visible_dynamic_helper_ids = ensure_runtime_visible_dynamic_helper_wake_fixture!(target)
      if visible_dynamic_helper_ids.empty?
        @errors << "Wake layout probe had no deterministic visible dynamic-helper fixture. SwiftBar-style Visible-to-Hidden wake drift is release-blocking. See #{RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH}."
        puts "❌ visible dynamic-helper wake fixture unavailable (#{RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH})"
        return
      end

      wake_probe_env = {
        'SANEBAR_SMOKE_APP_PATH' => target[:app_path],
        'SANEBAR_WAKE_PROBE_LOG_PATH' => RUNTIME_WAKE_PROBE_LOG_PATH,
        'SANEBAR_WAKE_PROBE_ARTIFACT_PATH' => RUNTIME_WAKE_PROBE_ARTIFACT_PATH,
        'SANEBAR_WAKE_PROBE_DYNAMIC_HELPER_IDS' => dynamic_helper_ids.join(','),
        'SANEBAR_WAKE_PROBE_REQUIRED_VISIBLE_IDS' => visible_dynamic_helper_ids.join(',')
      }
      wake_probe_env.merge!(runtime_probe_no_keychain_env(target))
      puts 'ℹ️ Wake layout probe intentionally sleeps/wakes the Mini display to test real wake recovery.'
      wake_probe_out, wake_probe_status = capture2e_with_progress(
        wake_probe_env,
        wake_probe_script,
        heartbeat_label: 'runtime wake layout probe'
      )
      File.write("#{RUNTIME_WAKE_PROBE_LOG_PATH}.stdout", wake_probe_out)
      unless wake_probe_status.success?
        @errors << "Wake layout probe failed. See #{RUNTIME_WAKE_PROBE_LOG_PATH} and #{RUNTIME_WAKE_PROBE_ARTIFACT_PATH}."
        puts "❌ wake probe failed (#{RUNTIME_WAKE_PROBE_LOG_PATH})"
        return
      end

      if capture_runtime_smoke_screenshots
        expected_screenshots = runtime_smoke_expected_modes(target).to_h do |mode|
          [mode, Dir.glob(File.join(screenshot_dir, "sanebar-#{mode}-*.png")).max_by { |path| File.mtime(path) }]
        end
        missing = expected_screenshots.select { |_mode, path| path.nil? }.keys
        appearance_screenshots = Dir.glob(File.join(screenshot_dir, 'sanebar-appearance-*.png'))
        missing << 'appearance-transition' if appearance_screenshots.empty?
        fullscreen_restore_screenshots = Dir.glob(File.join(screenshot_dir, 'sanebar-appearance-*-fullscreen-exit-*.png'))
        missing << 'fullscreen-overlay-restore' if fullscreen_restore_screenshots.empty?
        fullscreen_matrix_artifact = '/tmp/sanebar_runtime_fullscreen_matrix.json'
        unless runtime_fullscreen_matrix_artifact_passed?(fullscreen_matrix_artifact)
          missing << 'fullscreen-customer-visible-matrix'
        end
        unless missing.empty?
          @errors << "Runtime smoke missing screenshot artifact(s): #{missing.join(', ')}"
          puts "❌ missing screenshot(s): #{missing.join(', ')}"
          return
        end

        artifact_summary = expected_screenshots.map { |mode, path| "#{mode}=#{File.basename(path)}" }.join(', ')
        puts "✅ staged release browse smoke x#{RUNTIME_SMOKE_PASSES} + startup+wake layout probes (#{artifact_summary})"
      else
        puts "✅ staged release browse smoke x#{RUNTIME_SMOKE_PASSES} + startup+wake layout probes"
      end
    ensure
      cleanup_runtime_shared_bundle_fixture!
      cleanup_runtime_dynamic_helper_fixture!
      cleanup_runtime_visible_dynamic_helper_fixture!
      restore_runtime_smoke_appearance_settings!(appearance_settings_backup)
      restore_runtime_smoke_mode(restore_mode)
    end
  end

  def runtime_screenshot_capture_available?(screenshot_dir)
    return true if internal_runtime_snapshot_supported?

    !resolve_runtime_screenshot_tool.nil?
  end

  def runtime_fullscreen_matrix_artifact_passed?(path)
    return false unless File.exist?(path)

    payload = JSON.parse(File.read(path))
    required = [
      'native fullscreen enter and exit',
      'maximized desktop window below the menu bar',
      'app activation keeps dark custom tint visible',
      'Dark appearance with Translucent Background enabled',
      'Reduce Transparency enabled',
      'customer-visible menu-bar top-strip shade comparison, not only internal overlay snapshots'
    ]
    payload['status'] == 'pass' &&
      (required - Array(payload['completed_scenarios']).map(&:to_s)).empty? &&
      Array(payload['evidence_paths']).any?
  rescue JSON::ParserError
    false
  end

  def prepare_runtime_smoke_appearance_settings!
    backup = {
      existed: File.exist?(SETTINGS_PATH),
      content: File.exist?(SETTINGS_PATH) ? File.read(SETTINGS_PATH) : nil,
      dark_mode: runtime_smoke_dark_mode_enabled?,
      reduce_transparency: runtime_smoke_reduce_transparency_value
    }
    settings = backup[:content].to_s.empty? ? {} : JSON.parse(backup[:content])
    appearance = settings['menuBarAppearance'].is_a?(Hash) ? settings['menuBarAppearance'] : {}
    settings['hasCompletedOnboarding'] = true
    settings['menuBarAppearance'] = appearance.merge(
      'isEnabled' => true,
      'useLiquidGlass' => true,
      'tintColor' => '#FF5500',
      'tintOpacity' => 0.35,
      'tintColorDark' => '#FF5500',
      'tintOpacityDark' => 0.35,
      'hasShadow' => false,
      'hasBorder' => false,
      'hasRoundedCorners' => false
    )
    FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
    File.write(SETTINGS_PATH, JSON.pretty_generate(settings))
    set_runtime_smoke_dark_mode!(true)
    set_runtime_smoke_reduce_transparency!(true)
    backup
  rescue JSON::ParserError
    backup
  end

  def restore_runtime_smoke_appearance_settings!(backup)
    return if backup.nil?

    if backup[:existed]
      File.write(SETTINGS_PATH, backup[:content])
    else
      FileUtils.rm_f(SETTINGS_PATH)
    end
    set_runtime_smoke_dark_mode!(backup[:dark_mode]) unless backup[:dark_mode].nil?
    restore_runtime_smoke_reduce_transparency!(backup[:reduce_transparency])
  rescue StandardError
    nil
  end

  def runtime_smoke_dark_mode_enabled?
    script = 'tell application "System Events" to tell appearance preferences to get dark mode'
    out, status = Open3.capture2e('/usr/bin/osascript', '-e', script)
    raise "Could not read dark mode setting: #{out.strip}" unless status.success?

    out.strip.casecmp('true').zero?
  end

  def set_runtime_smoke_dark_mode!(enabled)
    script = "tell application \"System Events\" to tell appearance preferences to set dark mode to #{enabled ? 'true' : 'false'}"
    out, status = Open3.capture2e('/usr/bin/osascript', '-e', script)
    raise "Could not set dark mode=#{enabled}: #{out.strip}" unless status.success?
  end

  def runtime_smoke_reduce_transparency_value
    out, status = Open3.capture2e('/usr/bin/defaults', 'read', 'com.apple.universalaccess', 'reduceTransparency')
    return nil unless status.success?

    out.strip
  end

  def set_runtime_smoke_reduce_transparency!(enabled)
    out, status = Open3.capture2e('/usr/bin/defaults', 'write', 'com.apple.universalaccess', 'reduceTransparency', '-bool', enabled ? 'true' : 'false')
    raise "Could not set Reduce Transparency=#{enabled}: #{out.strip}" unless status.success?

    Open3.capture2e('/usr/bin/killall', 'cfprefsd')
  end

  def restore_runtime_smoke_reduce_transparency!(value)
    if value.nil?
      Open3.capture2e('/usr/bin/defaults', 'delete', 'com.apple.universalaccess', 'reduceTransparency')
    else
      normalized = %w[1 true TRUE].include?(value.to_s) ? 'true' : 'false'
      Open3.capture2e('/usr/bin/defaults', 'write', 'com.apple.universalaccess', 'reduceTransparency', '-bool', normalized)
    end
    Open3.capture2e('/usr/bin/killall', 'cfprefsd')
  end

  def retryable_runtime_smoke_failure?(smoke_output)
    return true if smoke_output.include?('launch_idle_budget_exceeded')
    return true if smoke_output.include?('No icons returned from list icon zones.')
    return true if runtime_smoke_missing_apple_menu_extra_policy?(smoke_output)

    retryable_active_budget_overrun?(smoke_output)
  end

  def retryable_shared_bundle_runtime_smoke_failure?(smoke_output)
    return true if retryable_runtime_smoke_failure?(smoke_output)

    return true if smoke_output.include?('Candidate failures:') &&
                   smoke_output.include?('to reach zone alwaysHidden')

    smoke_output.include?('Candidate failed: com.apple.controlcenter') &&
      smoke_output.include?('Hidden/Visible move actions ok') &&
      smoke_output.include?("Icon 'com.apple.menuextra.") &&
      smoke_output.include?('not found')
  end

  def retryable_active_budget_overrun?(smoke_output)
    resource_match = smoke_output.match(/Resource watchdog:\s+samples=\d+\s+avgCpu=(\d+(?:\.\d+)?)%\s+peakCpu=\d+(?:\.\d+)?%\s+avgRss=\d+(?:\.\d+)?MB\s+peakRss=\d+(?:\.\d+)?MB/)
    failure_match = smoke_output.match(/active_budget_exceeded\s+avgCpu=(\d+(?:\.\d+)?)%\s+>\s+(\d+(?:\.\d+)?)%/)
    return false unless failure_match

    limit = failure_match[2].to_f
    observed = if resource_match
      resource_match[1].to_f
    else
      failure_match[1].to_f
    end

    observed >= limit && (observed - limit) <= 0.6
  end

  def runtime_smoke_no_candidate_fixture_policy?(smoke_output)
    smoke_output.include?('No movable candidate icon found (need at least one hidden/visible icon).') ||
      smoke_output.include?('No browse activation candidate icon found.') ||
      runtime_smoke_missing_apple_menu_extra_policy?(smoke_output)
  end

  def runtime_smoke_missing_apple_menu_extra_policy?(smoke_output)
    smoke_output.include?("Icon 'com.apple.menuextra.") &&
      smoke_output.include?('not found') &&
      smoke_output.include?('activate browse icon failed')
  end

  def retryable_stability_suite_failure?(output)
    return false unless output.include?('** TEST FAILED **')
    return false unless output.include?('Testing started')
    return false if output.match?(/\berror:\b/i)
    return false if output.include?('XCTAssert')
    return false if output.include?('Assertion')
    return false if output.include?('Test Suite')
    return false if output.include?('failed -[')
    return false if output.include?('❌')

    true
  end
end
