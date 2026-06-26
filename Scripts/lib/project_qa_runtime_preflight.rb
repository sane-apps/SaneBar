# frozen_string_literal: true

class ProjectQA
  RUNTIME_TARGET_LOCK_PATH = ENV['SANEBAR_RUNTIME_TARGET_LOCK_PATH'] ||
                             ENV['SANEMASTER_RUNTIME_PROBE_LOCK_PATH'] ||
                             '/tmp/sanebar_runtime_probe.lock'
  RUNTIME_PROBE_CONFLICT_PATTERNS = [
    'Scripts/startup_layout_probe.rb',
    'Scripts/live_zone_smoke.rb',
    'Scripts/wake_layout_probe.rb'
  ].freeze

  private

  def check_runtime_release_smoke
    print 'Running release runtime smoke... '

    unless runtime_smoke_mode?
      puts '⏭️  skipped (set SANEBAR_RELEASE_PREFLIGHT=1 or SANEBAR_RUN_RUNTIME_SMOKE=1)'
      return
    end

    unless runtime_smoke_host_allowed?
      message = 'Runtime smoke must run on the mini via ./scripts/SaneMaster.rb unless explicit Air fallback is approved for a Mini outage.'
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

    if (conflict_error = runtime_probe_conflict_error)
      @errors << conflict_error
      puts '❌ overlapping runtime probe active'
      return
    end

    restore_mode = nil
    appearance_settings_backup = nil
    runtime_lock = acquire_runtime_target_lock
    return unless runtime_lock

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
      FileUtils.rm_f("#{RUNTIME_WAKE_PROBE_LOG_PATH}.stdout")
      FileUtils.rm_f(RUNTIME_STARTUP_PROBE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_STARTUP_PROBE_ARTIFACT_PATH)
      FileUtils.rm_f("#{RUNTIME_STARTUP_PROBE_LOG_PATH}.stdout")
      FileUtils.rm_f('/tmp/sanebar_runtime_fullscreen_matrix.json')
      FileUtils.rm_f(RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH)
      FileUtils.rm_f(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH)
      screenshot_capture_available = runtime_screenshot_capture_available?(screenshot_dir)
      resume_phase = runtime_smoke_resume_phase
      release_smoke_screenshots_required =
        %w[move_matrix shared_bundle native_apple].include?(resume_phase) ? false : ENV.fetch('SANEBAR_RELEASE_SMOKE_SCREENSHOTS', '1') != '0'
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
      prelaunch_runtime_host_exact_id_fixture!

      # When the runtime smoke runs off-Mini (approved local-UI-on-Air notch
      # verification), the candidate must be built and installed on THIS host so
      # the smoke drives the real version. Otherwise SaneMaster routes test_mode
      # to the Mini and installs there, leaving the Air smoke to run a stale
      # /Applications build. Disable Mini routing so the build lands locally
      # where the smoke runs. On the Mini this flag is a no-op.
      test_mode_env = { 'SANEMASTER_ALLOW_UNSIGNED_FALLBACK' => '0' }
      test_mode_env['SANEMASTER_DISABLE_MINI_ROUTING'] = '1' unless running_on_mini_host?

      launch_out, launch_status = capture2e_with_progress(
        test_mode_env,
        SANEMASTER_CLI,
        'test_mode',
        '--release',
        '--no-logs',
        heartbeat_label: 'runtime smoke test_mode launch'
      )
      safe_write_runtime_file(RUNTIME_LAUNCH_LOG_PATH, launch_out)
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

      if capture_runtime_smoke_screenshots
        # SaneMaster test_mode owns runtime cleanup and may rewrite settings after
        # the original backup/seed above. Reapply the visual fixture after that
        # boundary, then relaunch so the app reads it at startup.
        prepare_runtime_smoke_appearance_settings!
        target = target.merge(relaunch: true)
      end

      unless ensure_runtime_smoke_target_running!(target)
        @errors << "Runtime smoke could not launch target #{target[:app_path]}. See #{RUNTIME_LAUNCH_LOG_PATH}"
        puts "❌ target launch failed (#{RUNTIME_LAUNCH_LOG_PATH})"
        return
      end

      puts
      puts '   ↳ runtime target launched; validating candidate pool'
      always_hidden_setup_error = ensure_runtime_smoke_always_hidden_ready!(target)
      if always_hidden_setup_error
        @errors << always_hidden_setup_error
        puts '❌ always-hidden runtime smoke setup failed'
        return
      end

      ensure_runtime_shared_bundle_fixture!(target)

      # This representative-zone pre-check tries to seed the shared (SBF) fixtures
      # into every zone so the AppleScript move-matrix has candidates. On real
      # menu bars a fixture can park where the product CORRECTLY refuses to drag
      # it (off-screen on a notchless Mini, notch-unsafe on a notched display),
      # so seeding can't complete — but that refusal is the safety feature
      # working, not a release blocker. Keep this pre-check ADVISORY: the live
      # smoke's own require_representative_zone_candidates! gate is the single
      # enforcer and is safety-aware (it tolerates product-correct refusals and
      # still fails loudly on a genuine move bug). (See the test audit: the
      # AppleScript move-matrix is not the UI drag/right-click path users use;
      # real move coverage is the Swift regression suite + on-device IRL.)
      puts '   ↳ checking representative runtime candidate pool'
      representative_zone_setup_error = runtime_smoke_representative_zone_readiness_error(target)
      if representative_zone_setup_error
        puts '   ↳ representative candidate pool incomplete; seeding fixtures'
        representative_zone_setup_error = ensure_runtime_smoke_representative_zones_ready!(target)
        if representative_zone_setup_error
          @warnings << "Representative runtime zone setup incomplete (#{representative_zone_setup_error}); deferring to the live smoke's safety-aware candidate gate."
          puts '⚠️ representative runtime zone setup incomplete; deferring to live smoke gate'
        end
      else
        puts '   ↳ representative candidate pool already ready'
      end
      sleep 1.5
      settle_readiness_error = runtime_smoke_representative_zone_readiness_error(target)
      if settle_readiness_error
        puts '   ↳ representative setup drifted after settle; reseeding once'
        representative_zone_settle_error = ensure_runtime_smoke_representative_zones_ready!(target)
        if representative_zone_settle_error
          @warnings << "Representative runtime zone setup drifted after settle (#{representative_zone_settle_error}); deferring to the live smoke's safety-aware candidate gate."
          puts '⚠️ representative runtime zone setup drifted; deferring to live smoke gate'
        end
      end

      puts
      puts "   ↳ smoke target: #{target[:app_path]}"
      puts "   ↳ #{target[:note]}" if target[:note]

      smoke_env = {
        'SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN' => '1',
        # FM-1 (#155/#156/#166): drive an outbound Always-Hidden move from a
        # GENUINELY hidden separator and assert the icon leaves Always Hidden.
        # DEFAULT-ON and release-blocking: the live_zone_smoke FM-1 gate runs on
        # every normal runtime smoke / customer_ui_sweep / release_preflight pass
        # without anyone setting an env flag. To DISABLE for a focused unrelated
        # run only, export SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH=1; the default
        # stays ON so a no-op hidden-outbound move keeps the release red.
        'SANEBAR_SMOKE_REQUIRE_HIDDEN_OUTBOUND_AH' => hidden_outbound_ah_gate_enabled? ? '1' : '0',
        'SANEBAR_SMOKE_REQUIRE_ALL_ZONES' => '1',
        'SANEBAR_SMOKE_REQUIRE_CANDIDATE' => '1',
        'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '0',
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
        'SANEBAR_SMOKE_REQUIRE_NO_KEYCHAIN' => '0',
        'SANEBAR_RUNTIME_TARGET_LOCK_BYPASS' => '1'
      }
      if capture_runtime_smoke_screenshots
        puts '   ↳ smoke screenshots enabled by SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1'
      elsif resume_phase == 'move_matrix'
        puts '   ↳ resuming runtime smoke at move matrix; skipping browse/settings/fullscreen visual phases already covered by the prior receipt'
      elsif resume_phase == 'shared_bundle'
        puts '   ↳ resuming runtime smoke at shared-bundle exact-ID lane; skipping default move matrix already covered by the prior receipt'
      elsif resume_phase == 'native_apple'
        puts '   ↳ resuming runtime smoke at native Apple exact-ID lane; skipping default and shared-bundle lanes already covered by prior receipts'
      elsif screenshot_capture_available
        puts '   ↳ smoke screenshots disabled for release gating (set SANEBAR_RELEASE_SMOKE_SCREENSHOTS=1 to opt in)'
      else
        puts '   ↳ screenshot capture unavailable on this host; continuing without smoke screenshots'
      end
      smoke_outputs = []
      default_move_coverage_deferred = false
      runtime_passes = %w[shared_bundle native_apple].include?(resume_phase) ? 0 : RUNTIME_SMOKE_PASSES
      runtime_passes.times do |index|
        pass_number = index + 1
        puts "   ↳ smoke pass #{pass_number}/#{RUNTIME_SMOKE_PASSES}"

        if pass_number > 1
          unless ensure_runtime_smoke_target_running!(target.merge(relaunch: true))
            safe_write_runtime_file(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
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
          pass_env.merge!(
            'SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY' => '1',
            'SANEBAR_SMOKE_SKIP_LAUNCH_IDLE_BUDGET' => '1',
            'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TRANSITIONS' => '0',
            'SANEBAR_SMOKE_REQUIRE_APPEARANCE_TINT_PIXELS' => '0',
            'SANEBAR_SMOKE_REQUIRE_VISIBLE_APPEARANCE_PIXELS' => '0'
          ) if resume_phase == 'move_matrix'
          smoke_out, smoke_status = capture2e_with_progress(
            pass_env,
            smoke_script,
            heartbeat_label: "runtime smoke pass #{pass_number}/#{RUNTIME_SMOKE_PASSES} (try #{attempt})",
            timeout: RUNTIME_SMOKE_PASS_TIMEOUT_SECONDS
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
              safe_write_runtime_file(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
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

          safe_write_runtime_file(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
          sample_suffix = File.exist?(resource_sample_path) ? " Resource sample: #{resource_sample_path}" : ''
          @errors << "Runtime smoke failed on pass #{pass_number}/#{RUNTIME_SMOKE_PASSES}. See #{RUNTIME_SMOKE_LOG_PATH}.#{sample_suffix}"
          puts "❌ failed on pass #{pass_number}/#{RUNTIME_SMOKE_PASSES} (#{RUNTIME_SMOKE_LOG_PATH})"
          return
        end
      end

      safe_write_runtime_file(RUNTIME_SMOKE_LOG_PATH, smoke_outputs.join("\n\n"))
      focused_runtime_smoke_ran = false
      unless resume_phase == 'native_apple'
        shared_bundle_ids = ensure_runtime_shared_bundle_fixture!(target)
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
          @errors << "Runtime smoke had no deterministic shared-bundle exact-id fixture candidates. Shared-bundle move regressions are release-blocking; the Mini must launch the shared-bundle fixture before release. See #{RUNTIME_SHARED_BUNDLE_SMOKE_LOG_PATH} and #{RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH}."
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
        return if resume_phase == 'shared_bundle'
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
      return if resume_phase == 'native_apple'

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

      startup_resource_soak_required = startup_probe_resource_soak_required?
      startup_resource_soak_seconds = startup_probe_resource_soak_seconds
      startup_probe_env = {
        'SANEBAR_SMOKE_APP_PATH' => target[:app_path],
        'SANEBAR_STARTUP_PROBE_LOG_PATH' => RUNTIME_STARTUP_PROBE_LOG_PATH,
        'SANEBAR_STARTUP_PROBE_ARTIFACT_PATH' => RUNTIME_STARTUP_PROBE_ARTIFACT_PATH,
        'SANEBAR_RUNTIME_TARGET_LOCK_BYPASS' => '1'
      }
      if startup_resource_soak_required
        startup_probe_env.merge!(
          'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_AFTER_155' => '1',
          'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_SECONDS' => startup_resource_soak_seconds.to_s,
          'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_MIN_SECONDS' => startup_resource_soak_seconds.to_s
        )
      end
      startup_probe_env.merge!(runtime_probe_no_keychain_env(target))
      startup_probe_started_at = Time.now
      startup_probe_out, startup_probe_status = capture2e_with_progress(
        startup_probe_env,
        startup_probe_script,
        heartbeat_label: 'runtime startup layout probe',
        timeout: startup_probe_timeout_seconds(startup_resource_soak_required, startup_resource_soak_seconds)
      )
      safe_write_runtime_file("#{RUNTIME_STARTUP_PROBE_LOG_PATH}.stdout", startup_probe_out)
      unless startup_probe_status.success?
        @errors << "Startup layout probe failed. See #{RUNTIME_STARTUP_PROBE_LOG_PATH} and #{RUNTIME_STARTUP_PROBE_ARTIFACT_PATH}."
        puts "❌ startup probe failed (#{RUNTIME_STARTUP_PROBE_LOG_PATH})"
        return
      end
      if (startup_artifact_error = startup_probe_artifact_contract_error(started_at: startup_probe_started_at))
        @errors << startup_artifact_error
        puts "❌ startup probe artifact incomplete (#{RUNTIME_STARTUP_PROBE_ARTIFACT_PATH})"
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
        'SANEBAR_WAKE_PROBE_REQUIRED_VISIBLE_IDS' => visible_dynamic_helper_ids.join(','),
        # FM-2: explicit far-from-Control-Center divider survives wake/validation
        # churn. DEFAULT-ON and release-blocking — the wake probe runs this case
        # unless a focused unrelated run opts out with
        # SANEBAR_WAKE_PROBE_EXPLICIT_DIVIDER_SURVIVAL=0. A failure aborts the
        # probe (status fail) which becomes a release-blocking @errors entry below.
        'SANEBAR_WAKE_PROBE_EXPLICIT_DIVIDER_SURVIVAL' =>
          ENV.fetch('SANEBAR_WAKE_PROBE_EXPLICIT_DIVIDER_SURVIVAL', '1'),
        'SANEBAR_RUNTIME_TARGET_LOCK_BYPASS' => '1'
      }
      wake_probe_env.merge!(runtime_probe_no_keychain_env(target))
      puts 'ℹ️ Wake layout probe intentionally sleeps/wakes the Mini display to test real wake recovery.'
      wake_probe_started_at = Time.now
      wake_probe_out, wake_probe_status = capture2e_with_progress(
        wake_probe_env,
        wake_probe_script,
        heartbeat_label: 'runtime wake layout probe',
        timeout: 240
      )
      safe_write_runtime_file("#{RUNTIME_WAKE_PROBE_LOG_PATH}.stdout", wake_probe_out)
      unless wake_probe_status.success?
        @errors << "Wake layout probe failed. See #{RUNTIME_WAKE_PROBE_LOG_PATH} and #{RUNTIME_WAKE_PROBE_ARTIFACT_PATH}."
        puts "❌ wake probe failed (#{RUNTIME_WAKE_PROBE_LOG_PATH})"
        return
      end
      if (wake_artifact_error = wake_probe_artifact_contract_error(started_at: wake_probe_started_at))
        @errors << wake_artifact_error
        puts "❌ wake probe artifact incomplete (#{RUNTIME_WAKE_PROBE_ARTIFACT_PATH})"
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
      cleanup_runtime_host_exact_id_fixture!
      cleanup_runtime_dynamic_helper_fixture!
      cleanup_runtime_visible_dynamic_helper_fixture!
      restore_runtime_smoke_appearance_settings!(appearance_settings_backup)
      restore_runtime_smoke_mode(restore_mode)
      release_runtime_target_lock(runtime_lock)
    end
  end

  def acquire_runtime_target_lock
    raise Errno::ELOOP if File.symlink?(RUNTIME_TARGET_LOCK_PATH)

    2.times do
      cleanup_runtime_target_lock_file
      lock_file = publish_runtime_target_lock_file('qa-runtime-smoke')
      return lock_file if lock_file
    end

    holder = runtime_target_lock_holder_detail
    detail = holder.empty? ? '' : " (#{holder})"
    @errors << "Runtime smoke target is already locked by another probe#{detail}."
    puts '❌ runtime target locked'
    nil
  rescue Errno::ELOOP
    @errors << "Runtime smoke target lock path is a symlink: #{RUNTIME_TARGET_LOCK_PATH}"
    puts '❌ runtime target lock path is unsafe'
    nil
  end

  def release_runtime_target_lock(lock_file)
    return unless lock_file

    begin
      lock_file.flock(File::LOCK_UN)
    rescue StandardError
      nil
    end
    begin
      lock_file.close unless lock_file.closed?
    rescue StandardError
      nil
    end
    cleanup_runtime_target_lock_file
  end

  def open_runtime_target_lock
    File.open(RUNTIME_TARGET_LOCK_PATH, runtime_target_lock_open_flags, 0o600)
  end

  def publish_runtime_target_lock_file(command)
    FileUtils.mkdir_p(File.dirname(RUNTIME_TARGET_LOCK_PATH))
    temp_path = runtime_target_lock_temp_path
    published = false
    lock_file = File.open(temp_path, runtime_target_lock_publish_flags, 0o600)
    lock_file.flock(File::LOCK_EX)
    lock_file.write("pid=#{Process.pid} started=#{Time.now.utc.iso8601} command=#{command}\n")
    lock_file.flush
    File.link(temp_path, RUNTIME_TARGET_LOCK_PATH)
    published = true
    lock_file
  rescue Errno::EEXIST
    nil
  ensure
    FileUtils.rm_f(temp_path) if temp_path && File.exist?(temp_path)
    unless published
      begin
        lock_file&.flock(File::LOCK_UN)
      rescue StandardError
        nil
      end
      begin
        lock_file&.close unless lock_file&.closed?
      rescue StandardError
        nil
      end
    end
  end

  def runtime_target_lock_temp_path
    dir = File.dirname(RUNTIME_TARGET_LOCK_PATH)
    base = File.basename(RUNTIME_TARGET_LOCK_PATH)
    File.join(dir, ".#{base}.#{Process.pid}.#{rand(1_000_000)}.tmp")
  end

  def runtime_target_lock_publish_flags
    flags = File::RDWR | File::CREAT | File::EXCL
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def runtime_target_lock_open_flags
    flags = File::RDWR | File::CREAT
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def cleanup_runtime_target_lock_file
    return unless File.exist?(RUNTIME_TARGET_LOCK_PATH)

    cleanup_lock = open_runtime_target_lock
    return unless cleanup_lock

    return unless cleanup_lock.flock(File::LOCK_EX | File::LOCK_NB)

    FileUtils.rm_f(RUNTIME_TARGET_LOCK_PATH)
  rescue Errno::ENOENT, Errno::ELOOP
    nil
  ensure
    if cleanup_lock
      begin
        cleanup_lock.flock(File::LOCK_UN)
      rescue StandardError
        nil
      end
      begin
        cleanup_lock.close unless cleanup_lock.closed?
      rescue StandardError
        nil
      end
    end
  end

  def runtime_target_lock_holder_detail
    return '' unless File.exist?(RUNTIME_TARGET_LOCK_PATH)

    File.open(RUNTIME_TARGET_LOCK_PATH, runtime_target_lock_read_flags) do |file|
      file.read.to_s.strip
    end
  rescue Errno::ENOENT
    ''
  end

  def runtime_target_lock_read_flags
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def safe_write_runtime_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    safe_runtime_directory_path!(File.dirname(path))
    File.open(path, safe_runtime_file_write_flags, 0o600) do |file|
      file.write(content)
    end
  end

  def safe_read_runtime_file(path)
    safe_runtime_directory_path!(File.dirname(path))
    File.open(path, safe_runtime_file_read_flags) do |file|
      file.read
    end
  end

  def safe_runtime_artifact_file?(path)
    safe_runtime_directory_path!(File.dirname(path))
    stat = File.lstat(path)
    stat.file?
  rescue StandardError
    false
  end

  def safe_runtime_file_write_flags
    flags = File::WRONLY | File::CREAT | File::TRUNC
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def safe_runtime_file_read_flags
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def runtime_probe_conflict_error
    output, status = Open3.capture2e('ps', 'ax', '-o', 'pid=,ppid=,command=')
    return nil unless status.success?

    conflicts = output.lines.map do |line|
      pid_raw, ppid_raw, command = line.strip.split(/\s+/, 3)
      next nil unless pid_raw && command

      pid = pid_raw.to_i
      ppid = ppid_raw.to_i
      next nil if pid == Process.pid || ppid == Process.pid
      next nil unless RUNTIME_PROBE_CONFLICT_PATTERNS.any? { |pattern| command.include?(pattern) }

      "#{pid} #{command}"
    end.compact

    return nil if conflicts.empty?

    "Overlapping SaneBar runtime probe process is active: #{conflicts.join(' | ')}"
  end

  def runtime_screenshot_capture_available?(screenshot_dir)
    return true if internal_runtime_snapshot_supported?

    !resolve_runtime_screenshot_tool.nil?
  end

  def runtime_fullscreen_matrix_artifact_passed?(path)
    return false unless safe_runtime_artifact_file?(path)

    payload = JSON.parse(safe_read_runtime_file(path))
    required = [
      'native fullscreen enter and exit',
      'hidden and visible icon zones persist across fullscreen Space transition',
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
      existed: safe_runtime_settings_exist?,
      content: safe_runtime_settings_exist? ? safe_runtime_settings_read : nil,
      dark_mode: runtime_smoke_dark_mode_enabled?,
      reduce_transparency: runtime_smoke_reduce_transparency_value
    }
    settings = backup[:content].to_s.empty? ? {} : JSON.parse(backup[:content])
    appearance = settings['menuBarAppearance'].is_a?(Hash) ? settings['menuBarAppearance'] : {}
    settings['hasCompletedOnboarding'] = true
    settings['hasSeenFreemiumIntro'] = true
    settings['hasCompletedHealthWizard'] = true
    # Neutralize standing layout intent for the smoke: hide-all-other
    # allow-lists and always-hidden pins left over from earlier QA/probe runs
    # make the app's startup reconciliation physically rearrange the very
    # items the smoke seeder just placed ("zone setup drifted after settle").
    # The original settings are restored from the backup after the smoke.
    settings['hideAllOtherMenuBarItems'] = false
    settings['hideAllOtherVisibleItemIds'] = []
    settings['alwaysHiddenPinnedItemIds'] = []
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
    safe_runtime_settings_write(JSON.pretty_generate(settings))
    set_runtime_smoke_dark_mode!(true)
    set_runtime_smoke_reduce_transparency!(true)
    backup
  rescue JSON::ParserError
    backup
  end

  def restore_runtime_smoke_appearance_settings!(backup)
    return if backup.nil?

    if backup[:existed]
      safe_runtime_settings_write(backup[:content])
    else
      safe_runtime_settings_remove
    end
    set_runtime_smoke_dark_mode!(backup[:dark_mode]) unless backup[:dark_mode].nil?
    restore_runtime_smoke_reduce_transparency!(backup[:reduce_transparency])
  rescue StandardError
    nil
  end

  def safe_runtime_settings_exist?
    safe_runtime_directory_path!(File.dirname(SETTINGS_PATH))
    stat = File.lstat(SETTINGS_PATH)
    raise "Unsafe symlink settings path: #{SETTINGS_PATH}" if stat.symlink?
    raise "Unsafe non-file settings path: #{SETTINGS_PATH}" unless stat.file?

    true
  rescue Errno::ENOENT
    false
  end

  def safe_runtime_settings_read
    safe_runtime_directory_path!(File.dirname(SETTINGS_PATH))
    File.open(SETTINGS_PATH, safe_runtime_settings_read_flags) do |file|
      file.read
    end
  end

  def safe_runtime_settings_write(content)
    FileUtils.mkdir_p(File.dirname(SETTINGS_PATH))
    safe_runtime_directory_path!(File.dirname(SETTINGS_PATH))
    File.open(SETTINGS_PATH, safe_runtime_settings_write_flags, 0o600) do |file|
      file.write(content)
    end
  end

  def safe_runtime_settings_remove
    return unless safe_runtime_settings_exist?

    FileUtils.rm_f(SETTINGS_PATH)
  end

  def safe_runtime_directory_path!(path)
    expanded = File.expand_path(path)
    current = expanded.start_with?(File::SEPARATOR) ? File::SEPARATOR : Dir.pwd
    expanded.split(File::SEPARATOR).reject(&:empty?).each do |component|
      current = current == File::SEPARATOR ? File.join(current, component) : File.join(current, component)
      next unless File.exist?(current)

      stat = File.lstat(current)
      if stat.symlink?
        real = File.realpath(current) rescue nil
        next if allowed_system_temp_directory_symlink?(current, real)

        raise "Unsafe symlink directory path: #{current}"
      end
      raise "Unsafe non-directory path: #{current}" unless stat.directory?
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

  def safe_runtime_settings_read_flags
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def safe_runtime_settings_write_flags
    flags = File::WRONLY | File::CREAT | File::TRUNC
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    flags
  end

  def runtime_smoke_dark_mode_enabled?
    script = 'tell application "System Events" to tell appearance preferences to get dark mode'
    out, status = capture2e_with_runtime_timeout(
      '/usr/bin/osascript',
      '-e',
      script,
      timeout: 8,
      label: 'AppleScript dark-mode read'
    )
    raise "Could not read dark mode setting: #{out.strip}" unless status.success?

    out.strip.casecmp('true').zero?
  end

  def set_runtime_smoke_dark_mode!(enabled)
    script = "tell application \"System Events\" to tell appearance preferences to set dark mode to #{enabled ? 'true' : 'false'}"
    out, status = capture2e_with_runtime_timeout(
      '/usr/bin/osascript',
      '-e',
      script,
      timeout: 8,
      label: 'AppleScript dark-mode write'
    )
    raise "Could not set dark mode=#{enabled}: #{out.strip}" unless status.success?
  end

  def runtime_smoke_reduce_transparency_value
    out, status = Open3.capture2e('/usr/bin/defaults', 'read', 'com.apple.universalaccess', 'reduceTransparency')
    return nil unless status.success?

    out.strip
  end

  # com.apple.universalaccess is TCC-protected (Full Disk Access). On the
  # approved Air fallback the GUI session host may lack FDA while sshd has it,
  # so protected writes fall back to loopback SSH. The gate still fails hard
  # when neither identity can write.
  def protected_universalaccess_write(*defaults_args)
    out, status = Open3.capture2e('/usr/bin/defaults', *defaults_args)
    return [out, status] if status.success?

    ssh_out, ssh_status = Open3.capture2e(
      '/usr/bin/ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3', 'localhost',
      '/usr/bin/defaults', *defaults_args
    )
    ssh_status.success? ? [ssh_out, ssh_status] : [out, status]
  end

  def set_runtime_smoke_reduce_transparency!(enabled)
    out, status = protected_universalaccess_write('write', 'com.apple.universalaccess', 'reduceTransparency', '-bool', enabled ? 'true' : 'false')
    raise "Could not set Reduce Transparency=#{enabled}: #{out.strip}" unless status.success?

    Open3.capture2e('/usr/bin/killall', 'cfprefsd')
  end

  def restore_runtime_smoke_reduce_transparency!(value)
    if value.nil?
      protected_universalaccess_write('delete', 'com.apple.universalaccess', 'reduceTransparency')
    else
      normalized = %w[1 true TRUE].include?(value.to_s) ? 'true' : 'false'
      protected_universalaccess_write('write', 'com.apple.universalaccess', 'reduceTransparency', '-bool', normalized)
    end
    Open3.capture2e('/usr/bin/killall', 'cfprefsd')
  end

  def startup_probe_artifact_contract_error(started_at: nil)
    unless safe_runtime_artifact_file?(RUNTIME_STARTUP_PROBE_ARTIFACT_PATH)
      return "Startup layout probe did not write artifact #{RUNTIME_STARTUP_PROBE_ARTIFACT_PATH}."
    end
    if stale_runtime_artifact?(RUNTIME_STARTUP_PROBE_ARTIFACT_PATH, started_at)
      return "Startup layout probe artifact is stale: #{RUNTIME_STARTUP_PROBE_ARTIFACT_PATH} predates this probe run."
    end

    artifact = JSON.parse(safe_read_runtime_file(RUNTIME_STARTUP_PROBE_ARTIFACT_PATH))
    unless artifact['status'] == 'pass'
      return "Startup layout probe artifact status is #{artifact['status'].inspect}, expected pass."
    end
    if (provenance_error = startup_probe_mini_runtime_provenance_error(artifact))
      return provenance_error
    end
    unless runtime_probe_candidate_matches_project?(artifact)
      return "Startup layout probe artifact candidate metadata does not match project #{project_yml_setting('MARKETING_VERSION')}(#{project_yml_setting('CURRENT_PROJECT_VERSION')})."
    end

    case_names = Array(artifact['cases']).map { |entry| entry['name'].to_s }

    # On an external-only / headless display (a Mac Mini has no built-in screen)
    # SaneBar intentionally does NOT capture a current-width position backup, so
    # the backup-dependent dirty-reboot recovery case (#157) is N/A and the probe
    # records it as skipped. Don't require that case or its backup-recovery
    # sub-scenarios in that environment — they cannot run when there is no backup
    # to poison and recover. The display-independent cases (#155, etc.) still run
    # and stay required. On real built-in-display customer machines nothing is
    # skipped, so this never reduces release coverage where the backup applies.
    external_only_skip = Array(artifact['cases']).any? do |entry|
      entry['status'].to_s == 'skipped' && entry['reason'].to_s.include?('external-only')
    end

    required_cases = [
      '#157 dirty reboot recovery keeps live anchors before hiding',
      '#155 dirty startup AH replay allows outbound moves'
    ]
    required_cases.reject! { |name| name.start_with?('#157') } if external_only_skip
    missing_cases = required_cases - case_names
    unless missing_cases.empty?
      return "Startup layout probe artifact missing release-blocking case(s): #{missing_cases.join(', ')}."
    end

    required_scenarios = [
      '#157 dirty startup recovers poisoned autosave defaults',
      '#157 dirty startup clears currentHost visibility overrides',
      '#157 dirty startup waits for valid status-item windows before auto-hide',
      '#157 dirty startup remains passive and does not move the cursor',
      '#155 dirty startup does not give up AH replay',
      '#155 dirty startup restores pinned icons into Always Hidden before outbound moves',
      '#155 pinned icon exits Always Hidden after dirty startup',
      '#155 Always Hidden outbound moves leave move state idle'
    ]
    required_scenarios.reject! { |name| name.start_with?('#157') } if external_only_skip
    if startup_probe_resource_soak_required?
      required_scenarios << '#155 dirty startup resource soak remains stable after outbound moves'
      required_scenarios << '#155 outbound move state remains durable after resource soak'
    end
    completed_scenarios = Array(artifact['completed_scenarios'])
    missing = required_scenarios - completed_scenarios
    return "Startup layout probe artifact missing completed scenario(s): #{missing.join(', ')}." unless missing.empty?

    startup_probe_resource_soak_required? ? startup_probe_resource_soak_contract_error(artifact) : nil
  rescue JSON::ParserError => e
    "Startup layout probe artifact is invalid JSON: #{e.message}."
  end

  def startup_probe_mini_runtime_provenance_error(artifact)
    provenance = artifact['runtime_provenance']
    return 'Startup layout probe artifact missing Mini runtime provenance.' unless provenance.is_a?(Hash)
    return 'Startup layout probe artifact Mini runtime provenance must mark mini_runtime=true.' unless provenance['mini_runtime'] == true
    return 'Startup layout probe artifact Mini runtime provenance missing host.' if provenance['host'].to_s.strip.empty?
    return "Startup layout probe artifact Mini runtime provenance host #{provenance['host'].inspect} is not the Mini." unless provenance['host'].to_s.downcase.include?('mini')
    return 'Startup layout probe artifact Mini runtime provenance missing generated_at.' if provenance['generated_at'].to_s.strip.empty?

    artifact_app_path = artifact['app_path'].to_s
    provenance_app_path = provenance['app_path'].to_s
    if !artifact_app_path.empty? && provenance_app_path != artifact_app_path
      return "Startup layout probe artifact Mini runtime provenance app_path #{provenance_app_path.inspect} does not match artifact app_path #{artifact_app_path.inspect}."
    end

    nil
  end

  def wake_probe_mini_runtime_provenance_error(artifact)
    provenance = artifact['runtime_provenance']
    return 'Wake layout probe artifact missing Mini runtime provenance.' unless provenance.is_a?(Hash)
    return 'Wake layout probe artifact Mini runtime provenance must mark mini_runtime=true.' unless provenance['mini_runtime'] == true
    return 'Wake layout probe artifact Mini runtime provenance missing host.' if provenance['host'].to_s.strip.empty?
    return "Wake layout probe artifact Mini runtime provenance host #{provenance['host'].inspect} is not the Mini." unless provenance['host'].to_s.downcase.include?('mini')
    return 'Wake layout probe artifact Mini runtime provenance missing generated_at.' if provenance['generated_at'].to_s.strip.empty?

    artifact_app_path = artifact['app_path'].to_s
    provenance_app_path = provenance['app_path'].to_s
    if !artifact_app_path.empty? && !provenance_app_path.empty? && provenance_app_path != artifact_app_path
      return "Wake layout probe artifact Mini runtime provenance app_path #{provenance_app_path.inspect} does not match artifact app_path #{artifact_app_path.inspect}."
    end

    nil
  end

  def runtime_probe_candidate_matches_project?(artifact)
    candidate = artifact['candidate']
    return false unless candidate.is_a?(Hash)

    File.expand_path(candidate['app_path'].to_s) == '/Applications/SaneBar.app' &&
      candidate['app_version'].to_s == project_yml_setting('MARKETING_VERSION') &&
      candidate['app_build'].to_s == project_yml_setting('CURRENT_PROJECT_VERSION')
  end

  def startup_probe_resource_soak_contract_error(artifact)
    case_entry = Array(artifact['cases']).find do |entry|
      entry.is_a?(Hash) && entry['name'].to_s == '#155 dirty startup AH replay allows outbound moves'
    end
    return 'Startup layout probe artifact missing #155 case details for resource proof.' unless case_entry

    post_soak = case_entry['post_soak']
    unless post_soak.is_a?(Hash) &&
           post_soak['hidden_zone'].to_s == 'hidden' &&
           post_soak['visible_zone'].to_s == 'visible' &&
           post_soak['idle'].is_a?(Hash) &&
           !runtime_truthy?(post_soak['idle']['isMoveInProgress'])
      return 'Startup layout probe #155 resource proof did not re-check icon zones and idle move state after soak.'
    end

    proof = case_entry['resource_soak']
    return 'Startup layout probe #155 case missing resource_soak proof payload.' unless proof.is_a?(Hash)

    artifact_path = proof['artifact_path'].to_s
    log_path = proof['log_path'].to_s
    return 'Startup layout probe #155 resource proof missing durable artifact_path.' if artifact_path.empty?
    return "Startup layout probe #155 resource proof still points at temp artifact #{artifact_path}." if artifact_path.start_with?('/tmp/')
    return "Startup layout probe #155 resource proof artifact is missing or unsafe: #{artifact_path}." unless safe_runtime_artifact_file?(artifact_path)
    return "Startup layout probe #155 resource proof log is missing or unsafe: #{log_path}." unless !log_path.empty? && safe_runtime_artifact_file?(log_path)

    raw = JSON.parse(safe_read_runtime_file(artifact_path))
    return "Startup layout probe #155 resource proof status is #{raw['status'].inspect}, expected pass." unless raw['status'] == 'pass'

    candidate = raw['candidate']
    return 'Startup layout probe #155 resource proof missing candidate metadata.' unless candidate.is_a?(Hash)

    expected_version = project_yml_setting('MARKETING_VERSION')
    expected_build = project_yml_setting('CURRENT_PROJECT_VERSION')
    if !expected_version.empty? && candidate['app_version'].to_s != expected_version
      return "Startup layout probe #155 resource proof candidate version #{candidate['app_version'].inspect} does not match project #{expected_version}."
    end
    if !expected_build.empty? && candidate['app_build'].to_s != expected_build
      return "Startup layout probe #155 resource proof candidate build #{candidate['app_build'].inspect} does not match project #{expected_build}."
    end

    nil
  rescue JSON::ParserError => e
    "Startup layout probe #155 resource proof artifact is invalid JSON: #{e.message}."
  end

  def project_yml_setting(key)
    source = safe_read_runtime_file(File.join(PROJECT_ROOT, 'project.yml'))
    match = source.match(/^\s*#{Regexp.escape(key)}:\s*"?([^"\n]+)"?\s*$/)
    match ? match[1].strip : ''
  rescue StandardError
    ''
  end

  def runtime_truthy?(value)
    value == true || value.to_s.downcase == 'true'
  end

  def startup_probe_resource_soak_required?
    override = ENV['SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_AFTER_155']
    return override == '1' unless override.nil? || override.empty?

    preflight_mode?
  end

  def startup_probe_resource_soak_seconds
    Integer(ENV.fetch('SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_SECONDS', '600'), 10).tap do |value|
      raise 'SANEBAR_STARTUP_PROBE_RESOURCE_SOAK_SECONDS must be positive' unless value.positive?
    end
  end

  def startup_probe_timeout_seconds(resource_soak_required, resource_soak_seconds)
    return 300 unless resource_soak_required

    [resource_soak_seconds + 300, 900].max
  end

  def wake_probe_artifact_contract_error(started_at: nil)
    unless safe_runtime_artifact_file?(RUNTIME_WAKE_PROBE_ARTIFACT_PATH)
      return "Wake layout probe did not write artifact #{RUNTIME_WAKE_PROBE_ARTIFACT_PATH}."
    end
    if stale_runtime_artifact?(RUNTIME_WAKE_PROBE_ARTIFACT_PATH, started_at)
      return "Wake layout probe artifact is stale: #{RUNTIME_WAKE_PROBE_ARTIFACT_PATH} predates this probe run."
    end

    artifact = JSON.parse(safe_read_runtime_file(RUNTIME_WAKE_PROBE_ARTIFACT_PATH))
    unless artifact['status'] == 'pass'
      return "Wake layout probe artifact status is #{artifact['status'].inspect}, expected pass."
    end
    if (provenance_error = wake_probe_mini_runtime_provenance_error(artifact))
      return provenance_error
    end
    unless runtime_probe_candidate_matches_project?(artifact)
      return "Wake layout probe artifact candidate metadata does not match project #{project_yml_setting('MARKETING_VERSION')}(#{project_yml_setting('CURRENT_PROJECT_VERSION')})."
    end

    required_sections = %w[
      visible_zone_persistence
      hidden_zone_persistence
      dynamic_helper_wake_drift
    ]
    missing_sections = required_sections.reject { |section| artifact[section].is_a?(Hash) }
    unless missing_sections.empty?
      return "Wake layout probe artifact missing proof section(s): #{missing_sections.join(', ')}."
    end

    failed_sections = required_sections.select do |section|
      artifact.fetch(section).fetch('status', nil) != 'pass'
    end
    unless failed_sections.empty?
      return "Wake layout probe artifact failed proof section(s): #{failed_sections.join(', ')}."
    end

    required_scenarios = [
      'baseline visible icon-zone snapshot before display sleep',
      'fresh authoritative icon-zone snapshot at 1s after wake',
      'fresh authoritative icon-zone snapshot at 5s after wake',
      'fresh authoritative icon-zone snapshot at 15s after wake',
      'visible required IDs remain visible and are not moved into Hidden or Always Hidden',
      'baseline hidden icon-zone snapshot before display sleep',
      'hidden required IDs remain hidden and are not moved into Visible or Always Hidden',
      'dynamic helper required IDs are present before wake',
      'dynamic helper required IDs remain in intended zones after wake',
      'helper-specific Hidden to Visible drift is rejected as a release blocker'
    ]
    completed_scenarios = required_sections.flat_map do |section|
      Array(artifact.dig(section, 'completed_scenarios')).map(&:to_s)
    end.uniq
    missing = required_scenarios - completed_scenarios
    return nil if missing.empty?

    "Wake layout probe artifact missing completed scenario(s): #{missing.join(', ')}."
  rescue JSON::ParserError => e
    "Wake layout probe artifact is invalid JSON: #{e.message}."
  end

  def stale_runtime_artifact?(path, started_at)
    return false unless started_at

    File.mtime(path) < (started_at - 1)
  rescue Errno::ENOENT
    true
  end

  def retryable_runtime_smoke_failure?(smoke_output)
    return true if smoke_output.include?('launch_idle_budget_exceeded')
    return true if smoke_output.include?('No icons returned from list icon zones.')
    return true if smoke_output.include?('runtime_target_lost during AppleScript') &&
                   smoke_output.include?('process_missing')
    return true if runtime_smoke_missing_apple_menu_extra_policy?(smoke_output)

    retryable_active_budget_overrun?(smoke_output)
  end

  def retryable_shared_bundle_runtime_smoke_failure?(smoke_output)
    return true if retryable_runtime_smoke_failure?(smoke_output)

    return true if smoke_output.include?('Required icon(s) missing from list icon zones:') &&
                   smoke_output.include?('com.sanebar.sharedfixture::')
    return true if smoke_output.include?('Candidate failures:') &&
                   smoke_output.include?('to reach zone alwaysHidden')
    return true if smoke_output.include?('Candidate failures:') &&
                   smoke_output.include?('Post-settle move verification drifted') &&
                   smoke_output.match?(/\d+\/\d+ candidates passed move action checks/)

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

  # FM-1 hidden-outbound Always-Hidden move gate. Default-ON and release-blocking:
  # the gate enforces on every normal runtime smoke unless a focused unrelated run
  # explicitly opts out via SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH=1. The legacy
  # explicit opt-in (SANEBAR_SMOKE_REQUIRE_HIDDEN_OUTBOUND_AH=1) is still honored
  # but no longer required; the default now provides the guard.
  def hidden_outbound_ah_gate_enabled?
    return false if ENV['SANEBAR_SMOKE_DISABLE_HIDDEN_OUTBOUND_AH'] == '1'

    true
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
