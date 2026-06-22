# frozen_string_literal: true

class ProjectQA
  private

  def write_runtime_fixture_bundle_icon!(app_contents, symbol_name:, background_hex:, fixture_log:)
    resources_dir = File.join(app_contents, 'Resources')
    FileUtils.mkdir_p(resources_dir)

    iconset_dir = File.join(
      Dir.tmpdir,
      "sanebar-fixture-#{symbol_name.gsub(/[^a-zA-Z0-9]+/, '_')}-#{Process.pid}.iconset"
    )
    FileUtils.rm_rf(iconset_dir)
    FileUtils.mkdir_p(iconset_dir)

    generator_source = File.join(Dir.tmpdir, "sanebar-fixture-icon-generator-#{Process.pid}.swift")
    File.write(generator_source, runtime_fixture_icon_generator_source)

    output, status = Open3.capture2e('/usr/bin/swift', generator_source, symbol_name, background_hex, iconset_dir)
    fixture_log << "icon_generator_status=#{status.exitstatus}"
    fixture_log << output.strip unless output.strip.empty?
    return false unless status.success?

    output, status = Open3.capture2e(
      '/usr/bin/iconutil',
      '-c',
      'icns',
      iconset_dir,
      '-o',
      File.join(resources_dir, 'AppIcon.icns')
    )
    fixture_log << "iconutil_status=#{status.exitstatus}"
    fixture_log << output.strip unless output.strip.empty?
    status.success?
  rescue StandardError => e
    fixture_log << "icon_error=#{e.class}: #{e.message}"
    false
  ensure
    FileUtils.rm_rf(iconset_dir) if defined?(iconset_dir) && iconset_dir
  end

  def runtime_fixture_icon_generator_source
    <<~SWIFT
      import AppKit

      let symbolName = CommandLine.arguments[1]
      let backgroundHex = CommandLine.arguments[2]
      let iconsetPath = CommandLine.arguments[3]

      func color(from hex: String) -> NSColor {
          let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
          var value: UInt64 = 0
          Scanner(string: trimmed).scanHexInt64(&value)
          let red = CGFloat((value >> 16) & 0xff) / 255.0
          let green = CGFloat((value >> 8) & 0xff) / 255.0
          let blue = CGFloat(value & 0xff) / 255.0
          return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
      }

      func writeIcon(named fileName: String, size: CGFloat) throws {
          let image = NSImage(size: NSSize(width: size, height: size))
          image.lockFocus()
          NSColor.clear.setFill()
          NSRect(x: 0, y: 0, width: size, height: size).fill()
          color(from: backgroundHex).setFill()
          NSBezierPath(
              roundedRect: NSRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88),
              xRadius: size * 0.2,
              yRadius: size * 0.2
          ).fill()

          if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
              let config = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .semibold)
              let configured = symbol.withSymbolConfiguration(config) ?? symbol
              configured.isTemplate = true
              NSColor.white.set()
              configured.draw(
                  in: NSRect(x: size * 0.22, y: size * 0.22, width: size * 0.56, height: size * 0.56),
                  from: .zero,
                  operation: .sourceOver,
                  fraction: 1.0
              )
          }

          image.unlockFocus()
          guard
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
          else {
              throw NSError(domain: "SaneBarFixtureIcon", code: 1)
          }
          try png.write(to: URL(fileURLWithPath: iconsetPath).appendingPathComponent(fileName))
      }

      let specs: [(String, CGFloat)] = [
          ("icon_16x16.png", 16),
          ("icon_16x16@2x.png", 32),
          ("icon_32x32.png", 32),
          ("icon_32x32@2x.png", 64),
          ("icon_128x128.png", 128),
          ("icon_128x128@2x.png", 256),
          ("icon_256x256.png", 256),
          ("icon_256x256@2x.png", 512),
          ("icon_512x512.png", 512),
          ("icon_512x512@2x.png", 1024)
      ]

      for spec in specs {
          try writeIcon(named: spec.0, size: spec.1)
      }
    SWIFT
  end

  def run_focused_runtime_smoke_exact_ids(target:, smoke_env:, smoke_script:, exact_ids:, log_path:, lane_name:, retryable_failure_method:)
    focused_outputs = []
    unless ensure_runtime_smoke_target_running!(target.merge(relaunch: true))
      @errors << "Focused #{lane_name} smoke could not relaunch target #{target[:app_path]}. See #{RUNTIME_LAUNCH_LOG_PATH}"
      puts "❌ #{lane_name} relaunch failed (#{RUNTIME_LAUNCH_LOG_PATH})"
      return false
    end

    if (pro_error = focused_runtime_smoke_pro_error(target, lane_name))
      focused_outputs << pro_error
      File.write(log_path, focused_outputs.join("\n\n"))
      @errors << "#{pro_error} See #{log_path}."
      puts "❌ #{lane_name} Pro precheck failed (#{log_path})"
      return false
    end

    puts "   ↳ #{lane_name} smoke after relaunch: #{exact_ids.join(', ')}"
    focused_env = smoke_env.merge(
      'SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN' => '1',
      'SANEBAR_SMOKE_REQUIRED_IDS' => exact_ids.join(','),
      'SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES' => '1',
      'SANEBAR_SMOKE_SKIP_MOVE_CHECKS' => '0',
      'SANEBAR_SMOKE_REQUIRE_NO_KEYCHAIN' => target[:no_keychain] ? '1' : '0'
    )
    focused_env['SANEBAR_SMOKE_EXACT_ID_MOVE_ONLY'] = '1'
    focused_env['SANEBAR_SMOKE_SKIP_LAUNCH_IDLE_BUDGET'] = '1'
    focused_env['SANEBAR_SMOKE_ALLOW_NOTCH_UNSAFE_REQUIRED_SKIPS'] = '1'
    if lane_name == 'host exact-id'
      focused_env['SANEBAR_SMOKE_PIN_REQUIRED_BROWSE_ALWAYS_HIDDEN'] = '1'
    end
    focused_attempt = 0

    loop do
      focused_attempt += 1
      focused_sample_path = log_path.sub(/\.log\z/, "_resource_sample-try#{focused_attempt}.txt")
      FileUtils.rm_f(focused_sample_path)
      focused_out, focused_status = capture2e_with_progress(
        focused_env.merge('SANEBAR_SMOKE_RESOURCE_SAMPLE_PATH' => focused_sample_path),
        smoke_script,
        heartbeat_label: "runtime smoke #{lane_name} (try #{focused_attempt})",
        timeout: focused_runtime_smoke_timeout_seconds(exact_ids)
      )
      focused_outputs << [
        "required_ids=#{exact_ids.join(',')}",
        "try=#{focused_attempt}",
        *runtime_smoke_candidate_lines(target),
        "resource_sample=#{focused_sample_path}",
        focused_out
      ].join("\n")

      if !focused_status.success? &&
         focused_attempt <= RUNTIME_SMOKE_RETRIES_PER_PASS &&
         send(retryable_failure_method, focused_out)
        puts "   ↳ relaunching after transient #{lane_name} runtime smoke failure (retry #{focused_attempt}/#{RUNTIME_SMOKE_RETRIES_PER_PASS})"
        unless ensure_runtime_smoke_target_running!(target.merge(relaunch: true))
          File.write(log_path, focused_outputs.join("\n\n"))
          @errors << "Focused #{lane_name} smoke retry could not relaunch target #{target[:app_path]}. See #{log_path}."
          puts "❌ #{lane_name} retry relaunch failed (#{log_path})"
          return false
        end
        unless prepare_focused_runtime_smoke_retry!(
          target: target,
          exact_ids: exact_ids,
          lane_name: lane_name,
          focused_outputs: focused_outputs
        )
          File.write(log_path, focused_outputs.join("\n\n"))
          @errors << "Focused #{lane_name} smoke retry could not reseed exact-ID fixtures. See #{log_path}."
          puts "❌ #{lane_name} retry fixture reseed failed (#{log_path})"
          return false
        end
        if (pro_error = focused_runtime_smoke_pro_error(target, "#{lane_name} retry"))
          focused_outputs << pro_error
          File.write(log_path, focused_outputs.join("\n\n"))
          @errors << "#{pro_error} See #{log_path}."
          puts "❌ #{lane_name} retry Pro precheck failed (#{log_path})"
          return false
        end
        next
      end

      File.write(log_path, focused_outputs.join("\n\n"))
      unless focused_status.success?
        sample_suffix = File.exist?(focused_sample_path) ? " Resource sample: #{focused_sample_path}" : ''
        @errors << "Focused #{lane_name} runtime smoke failed. See #{log_path}.#{sample_suffix}"
        puts "❌ #{lane_name} smoke failed (#{log_path})"
        return false
      end
      break
    end

    puts "✅ focused #{lane_name} smoke passed (#{exact_ids.join(', ')})"
    true
  end

  def prepare_focused_runtime_smoke_retry!(target:, exact_ids:, lane_name:, focused_outputs:)
    return true unless lane_name == 'shared-bundle'

    cleanup_runtime_shared_bundle_fixture!
    resolved_ids = ensure_runtime_shared_bundle_fixture!(target)
    missing_ids = exact_ids - resolved_ids
    focused_outputs << "shared_bundle_retry_fixture_ids=#{resolved_ids.join(',')}"
    return true if missing_ids.empty?

    focused_outputs << "shared_bundle_retry_fixture_missing=#{missing_ids.join(',')}"
    false
  end

  def focused_runtime_smoke_timeout_seconds(exact_ids)
    [
      RUNTIME_SMOKE_FOCUSED_PASS_TIMEOUT_SECONDS,
      (Array(exact_ids).length * 150) + 90
    ].max
  end

  def focused_runtime_smoke_pro_error(target, lane_name)
    deadline = Time.now + 15.0
    snapshot = nil
    loop do
      snapshot = runtime_smoke_layout_snapshot(target)
      return nil if snapshot && snapshot['licenseIsPro'] == true

      break if Time.now >= deadline

      sleep 0.5
    end

    detail = snapshot.nil? ? 'snapshot unavailable' : "licenseIsPro=#{snapshot['licenseIsPro'].inspect}"
    "Focused #{lane_name} smoke requires a paid license or active Pro trial before moving exact IDs; #{detail}. #{runtime_smoke_target_process_detail(target)}".strip
  end

  def runtime_smoke_candidate_lines(target)
    metadata = app_bundle_metadata(target[:app_path])
    [
      "candidate_app_path=#{target[:app_path]}",
      "candidate_app_version=#{metadata[:short_version]}",
      "candidate_app_build=#{metadata[:build_version]}",
      "candidate_process_path=#{target[:process_path]}"
    ]
  end

  def internal_runtime_snapshot_supported?
    sdef_path = File.join(PROJECT_ROOT, 'Resources', "#{PROJECT_NAME}.sdef")
    return false unless File.exist?(sdef_path)

    source = File.read(sdef_path)
    source.include?('capture browse panel snapshot') &&
      source.include?('queue browse panel snapshot') &&
      source.include?('open settings window') &&
      source.include?('close settings window') &&
      source.include?('capture settings window snapshot') &&
      source.include?('queue settings window snapshot')
  rescue StandardError
    false
  end

  def resolve_runtime_screenshot_tool
    from_path = `command -v screenshot 2>/dev/null`.strip
    return from_path unless from_path.empty?

    %w[
      ~/Library/Python/3.13/bin/screenshot
      ~/Library/Python/3.12/bin/screenshot
      ~/Library/Python/3.11/bin/screenshot
      ~/Library/Python/3.10/bin/screenshot
      ~/Library/Python/3.9/bin/screenshot
    ].map { |path| File.expand_path(path) }.find { |path| File.executable?(path) }
  end

  def runtime_smoke_mode_status
    output, status = Open3.capture2e(SANEMASTER_CLI, 'mode', PROJECT_NAME, 'status')
    return nil unless status.success?

    text = output.downcase
    return :pro if text.include?('mode: pro')
    return :basic if text.include?('mode: basic')

    nil
  rescue StandardError
    nil
  end

  def runtime_smoke_layout_snapshot(target)
    return nil unless ensure_runtime_smoke_target_running!(target)

    expected_bundle_id = 'com.sanebar.app'
    deadline = Time.now + 12.0
    relaunched_after_wrong_target = false
    loop do
      output, status = capture2e_with_runtime_timeout(
        'osascript',
        '-e',
        %(set appTarget to ((POSIX file "#{target[:app_path]}" as alias) as text)),
        '-e',
        %(using terms from application id "#{expected_bundle_id}"),
        '-e',
        'tell application appTarget to layout snapshot',
        '-e',
        'end using terms from',
        timeout: 4,
        label: 'AppleScript layout snapshot'
      )
      if status.success?
        snapshot = JSON.parse(output)
        if target[:no_keychain] &&
           (!runtime_smoke_no_keychain_target_exclusive?(target) || snapshot['licenseIsPro'] != true)
          unless relaunched_after_wrong_target
            target[:relaunch] = true
            ensure_runtime_smoke_target_running!(target)
            relaunched_after_wrong_target = true
          end
        else
          return snapshot
        end
      end

      break if Time.now >= deadline

      sleep 0.5
    rescue JSON::ParserError
      break if Time.now >= deadline

      sleep 0.5
    end

    nil
  rescue JSON::ParserError, StandardError
    nil
  end

  def ensure_runtime_smoke_pro_mode!
    current_mode = runtime_smoke_mode_status
    return [nil, 'Runtime smoke could not determine the current fallback test mode.'] if current_mode.nil?
    return [nil, nil] if current_mode == :pro

    output, status = Open3.capture2e(SANEMASTER_CLI, 'mode', PROJECT_NAME, 'pro')
    return [:basic, nil] if status.success?

    [nil, "Runtime smoke could not switch fallback test mode to Pro: #{output.lines.last&.strip || output.strip}"]
  rescue StandardError => e
    [nil, "Runtime smoke could not switch fallback test mode to Pro: #{e.message}"]
  end

  def ensure_runtime_smoke_always_hidden_ready!(target)
    snapshot = runtime_smoke_layout_snapshot(target)
    return 'Runtime smoke could not read the target layout snapshot before Always Hidden checks.' if snapshot.nil?
    return nil if snapshot['licenseIsPro'] == true

    target[:relaunch] = true

    snapshot = runtime_smoke_layout_snapshot(target)
    return nil if snapshot && snapshot['licenseIsPro'] == true

    detail = snapshot.nil? ? 'snapshot unavailable after relaunch' : "licenseIsPro=#{snapshot['licenseIsPro'].inspect}"
    "Runtime smoke requires a paid license or active Pro trial for Always Hidden checks; the mini runtime target stayed in Basic (#{detail})."
  end

  def restore_runtime_smoke_mode(mode)
    return if mode.nil?

    Open3.capture2e(SANEMASTER_CLI, 'mode', mode.to_s)
  rescue StandardError
    nil
  end

  def runtime_smoke_uses_no_keychain?(launch_output)
    launch_output.include?('fresh build verified, no-keychain')
  end

  def runtime_smoke_relaunch_command(target)
    command = ['open', '--fresh']
    command += ['--env', 'SANEAPPS_DISABLE_KEYCHAIN=1'] if target[:no_keychain]
    command << target[:app_path]
    launch_args = ['--sane-skip-app-move']
    launch_args << '--sane-no-keychain' if target[:no_keychain]
    command += ['--args', *launch_args]
    command
  end

  def launch_runtime_smoke_target!(target)
    if target[:no_keychain]
      binary = target[:process_path]
      return false unless binary && File.executable?(binary)

      Process.detach(
        Process.spawn(
          { 'SANEAPPS_DISABLE_KEYCHAIN' => '1' },
          binary,
          '--sane-skip-app-move',
          '--sane-no-keychain',
          out: File::NULL,
          err: File::NULL
        )
      )
      return true
    end

    system(*runtime_smoke_relaunch_command(target), out: File::NULL, err: File::NULL)
  rescue StandardError
    false
  end

  def runtime_smoke_target(launch_output:)
    launched_path = launch_output.lines.reverse.find { |line| line.include?('📱 Launching:') }
    launched_path = launched_path&.split('📱 Launching:', 2)&.last&.strip
    unsigned_fallback = launch_output.include?('Unsigned fallback active:')
    no_keychain = runtime_smoke_uses_no_keychain?(launch_output)
    system_app_path = "/Applications/#{PROJECT_NAME}.app"
    system_process_path = File.join(system_app_path, 'Contents', 'MacOS', PROJECT_NAME)
    launched_target = nil

    unless launched_path.to_s.empty?
      launched_target = {
        app_path: launched_path,
        process_path: File.join(launched_path, 'Contents', 'MacOS', PROJECT_NAME),
        relaunch: false,
        no_keychain: no_keychain,
        note: 'using the app that test_mode just launched'
      }
    end

    if unsigned_fallback && File.exist?(system_app_path) && developer_id_signed?(system_app_path)
      if launched_target
        launched_meta = app_bundle_metadata(launched_target[:app_path])
        system_meta = app_bundle_metadata(system_app_path)

        if same_release_build?(launched_meta, system_meta)
          return {
            app_path: system_app_path,
            process_path: system_process_path,
            relaunch: true,
            no_keychain: no_keychain,
            note: "using installed signed app for smoke because unsigned fallback build #{format_bundle_metadata(launched_meta)} matches /Applications/#{PROJECT_NAME}.app"
          }
        end

        launched_target[:note] = "keeping the launched fallback app because /Applications/#{PROJECT_NAME}.app is #{format_bundle_metadata(system_meta)} and the launched build is #{format_bundle_metadata(launched_meta)}"
        return launched_target
      end

      return {
        app_path: system_app_path,
        process_path: system_process_path,
        relaunch: true,
        no_keychain: no_keychain,
        note: 'using installed signed app for smoke because test_mode did not report a launched app path'
      }
    end

    return launched_target if launched_target

    nil
  end

  def ensure_runtime_smoke_target_running!(target)
    if target[:relaunch]
      return false unless terminate_runtime_smoke_target_processes!(target)

      launched = launch_runtime_smoke_target!(target)
      return false unless launched
      sleep 1.5 if target[:no_keychain]
    end

    deadline = Time.now + 8
    while Time.now < deadline
      all_matches = runtime_smoke_target_processes(target, require_no_keychain: false)
      matches = runtime_smoke_target_processes(target)
      if matches.length == 1
        if target[:no_keychain]
          if all_matches.length == 1
            target[:relaunch] = false
            return true
          end
        else
          target[:relaunch] = false
          return true
        end
      end
      return false if matches.length > 1

      if target[:no_keychain] && !all_matches.empty?
        # Launch Services can briefly keep the old instance around. Keep polling,
        # but do not accept a real-keychain process for release smoke.
        sleep 0.5
        next
      end

      sleep 0.5
    end

    false
  end

  def runtime_smoke_no_keychain_target_exclusive?(target)
    return true unless target[:no_keychain]

    all_matches = runtime_smoke_target_processes(target, require_no_keychain: false)
    no_keychain_matches = runtime_smoke_target_processes(target, require_no_keychain: true)
    all_matches.length == 1 && no_keychain_matches.length == 1
  end

  def terminate_runtime_smoke_target_processes!(target)
    pids = runtime_smoke_target_pids(target)
    return true if pids.empty?

    signal_runtime_smoke_target_pids(pids, 'TERM')
    return true if wait_for_runtime_smoke_target_exit!(target, seconds: 3.0)

    signal_runtime_smoke_target_pids(pids, 'KILL')
    wait_for_runtime_smoke_target_exit!(target, seconds: 3.0)
  end

  def runtime_smoke_target_pids(target)
    runtime_smoke_target_processes(target, require_no_keychain: false).map do |line|
      pid = line.split(/\s+/, 2).first.to_i
      pid.positive? ? pid : nil
    end.compact
  end

  def signal_runtime_smoke_target_pids(pids, signal)
    pids.each do |pid|
      Process.kill(signal, pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
  end

  def wait_for_runtime_smoke_target_exit!(target, seconds:)
    deadline = Time.now + seconds
    loop do
      return true if runtime_smoke_target_processes(target, require_no_keychain: false).empty?
      return false if Time.now >= deadline

      sleep 0.2
    end
  end

  def runtime_smoke_target_processes(target, require_no_keychain: target[:no_keychain])
    processes, status = Open3.capture2e('ps', 'ax', '-o', 'pid=,command=')
    return [] unless status.success?

    processes.lines.each_with_object([]) do |line, result|
      pid, command = line.strip.split(/\s+/, 2)
      next unless pid && command
      next unless command.split(/\s+/, 2).first.to_s == target[:process_path]
      next if require_no_keychain && !command.include?('--sane-no-keychain')

      result << "#{pid} #{command}"
    end
  end

  def runtime_smoke_target_process_detail(target)
    matches = runtime_smoke_target_processes(target, require_no_keychain: false)
    return 'process=none' if matches.empty?

    "process=#{matches.join(' | ')}"
  rescue StandardError => e
    "process=unavailable(#{e.class}: #{e.message})"
  end

  def validate_runtime_smoke_target(target)
    metadata = app_bundle_metadata(target[:app_path])
    expected_bundle_id = 'com.sanebar.app'

    if metadata[:bundle_id].to_s != expected_bundle_id
      system_meta = app_bundle_metadata("/Applications/#{PROJECT_NAME}.app")
      detail = system_meta.empty? ? '' : " Signed /Applications target is #{format_bundle_metadata(system_meta)}."
      return "Runtime smoke requires signed release bundle #{expected_bundle_id}; got #{format_bundle_metadata(metadata)}.#{detail}"
    end

    auth_value = accessibility_auth_value_for(expected_bundle_id)
    return nil if auth_value == 2

    auth_detail = auth_value.nil? ? 'missing' : auth_value.to_s
    "Runtime smoke target #{expected_bundle_id} is not Accessibility-granted in TCC (auth_value=#{auth_detail})."
  end

  def ensure_runtime_shared_bundle_fixture!(target)
    fixture_log = []
    fixture_log << "app_path=#{RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH}"

    unless runtime_shared_bundle_fixture_running? || start_runtime_shared_bundle_fixture!(fixture_log)
      File.write(RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
      return []
    end

    ids = wait_for_runtime_shared_bundle_fixture_ids(target, fixture_log)
    File.write(RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
    ids
  end

  def prelaunch_runtime_shared_bundle_fixture!
    fixture_log = ["app_path=#{RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH}", 'prelaunch=1']
    cleanup_runtime_shared_bundle_fixture!
    start_runtime_shared_bundle_fixture!(fixture_log)
    File.write(RUNTIME_SHARED_BUNDLE_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
  end

  def start_runtime_shared_bundle_fixture!(fixture_log)
    return false unless build_runtime_shared_bundle_fixture!(fixture_log)

    launched = system('open', RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH, out: File::NULL, err: File::NULL)
    fixture_log << "open=#{launched ? 'ok' : 'failed'}"
    return false unless launched

    sleep 1

    runtime_shared_bundle_fixture_running?
  end

  def build_runtime_shared_bundle_fixture!(fixture_log)
    app_contents = File.join(RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH, 'Contents')
    executable_dir = File.join(app_contents, 'MacOS')
    executable_path = File.join(executable_dir, 'SaneBarSharedFixture')
    FileUtils.rm_rf(RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH)
    FileUtils.mkdir_p(executable_dir)
    write_runtime_fixture_bundle_icon!(
      app_contents,
      symbol_name: 'square.grid.2x2.fill',
      background_hex: '#2F7D72',
      fixture_log: fixture_log
    )
    File.write(File.join(app_contents, 'Info.plist'), runtime_shared_bundle_fixture_plist)
    File.write(RUNTIME_SHARED_BUNDLE_FIXTURE_SOURCE_PATH, runtime_shared_bundle_fixture_source)

    output, status = Open3.capture2e('swiftc', RUNTIME_SHARED_BUNDLE_FIXTURE_SOURCE_PATH, '-o', executable_path)
    fixture_log << "swiftc_status=#{status.exitstatus}"
    fixture_log << output.strip unless output.strip.empty?
    return false unless status.success?

    FileUtils.chmod('+x', executable_path)
    true
  rescue StandardError => e
    fixture_log << "build_error=#{e.class}: #{e.message}"
    false
  end

  def wait_for_runtime_shared_bundle_fixture_ids(target, fixture_log)
    deadline = Time.now + 30
    ids = []
    while Time.now < deadline
      refresh_output, refresh_status = refresh_runtime_smoke_icon_inventory(target)
      fixture_log << "refresh_status=#{refresh_status&.exitstatus}"
      fixture_log << refresh_output.lines.grep(/sharedfixture/i).join.strip unless refresh_output.to_s.lines.grep(/sharedfixture/i).empty?
      fixture_log << "fixture_process=#{runtime_shared_bundle_fixture_process_detail}"
      ids = runtime_smoke_available_shared_bundle_candidate_ids(
        target,
        required_ids: RUNTIME_SHARED_BUNDLE_FIXTURE_IDS
      )
      fixture_log << "attempt_ids=#{ids.join(',')}" unless ids.empty?
      break if ids.length >= RUNTIME_SHARED_BUNDLE_FIXTURE_IDS.length

      sleep 0.5
    end

    fixture_log << "required_ids=#{RUNTIME_SHARED_BUNDLE_FIXTURE_IDS.join(',')}"
    fixture_log << "resolved_ids=#{ids.join(',')}"
    ids
  end

  def refresh_runtime_smoke_icon_inventory(target)
    script_target = %(application id "com.sanebar.app")
    capture2e_with_runtime_timeout(
      '/usr/bin/osascript',
      '-e',
      "tell #{script_target} to list authoritative icon zones",
      timeout: 8,
      label: 'AppleScript inventory'
    )
  rescue StandardError
    ['', nil]
  end

  def runtime_fixture_process_detail(process_name, app_path: nil)
    executable_path = app_path ? File.join(app_path, 'Contents', 'MacOS', process_name) : nil
    output, status = Open3.capture2e('ps', 'ax', '-o', 'pid=,comm=,command=')
    return 'none' unless status.success?

    matches = output.lines.each_with_object([]) do |line, process_matches|
      pid, comm, command = line.strip.split(/\s+/, 3)
      next unless pid && command

      executable = command.split(/\s+/, 2).first.to_s
      names_match = File.basename(comm.to_s) == process_name || File.basename(executable) == process_name
      path_matches = executable_path && executable == executable_path
      next unless names_match || path_matches

      process_matches << "#{pid} #{command}"
    end
    matches.empty? ? 'none' : matches.join(' | ')
  rescue StandardError
    'unavailable'
  end

  def runtime_shared_bundle_fixture_process_detail
    runtime_fixture_process_detail(
      'SaneBarSharedFixture',
      app_path: RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH
    )
  end

  def runtime_shared_bundle_fixture_running?
    runtime_shared_bundle_fixture_process_detail != 'none'
  end

  def cleanup_runtime_shared_bundle_fixture!
    Open3.capture2e('/usr/bin/killall', 'SaneBarSharedFixture')
  rescue StandardError
    nil
  end

  def ensure_runtime_host_exact_id_fixture!(target)
    fixture_log = []
    fixture_log << "app_path=#{RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH}"

    unless start_runtime_host_exact_id_fixture!(fixture_log)
      File.write(RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
      return []
    end

    ids = wait_for_runtime_host_exact_id_fixture_ids(target, fixture_log)
    File.write(RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
    ids
  end

  def start_runtime_host_exact_id_fixture!(fixture_log)
    Open3.capture2e('/usr/bin/killall', 'SaneBarHostExactIDFixture')
    return false unless build_runtime_host_exact_id_fixture!(fixture_log)

    launched = system('open', RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH, out: File::NULL, err: File::NULL)
    fixture_log << "open=#{launched ? 'ok' : 'failed'}"
    return false unless launched

    sleep 1
    runtime_host_exact_id_fixture_running?
  end

  def build_runtime_host_exact_id_fixture!(fixture_log)
    app_contents = File.join(RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH, 'Contents')
    executable_dir = File.join(app_contents, 'MacOS')
    executable_path = File.join(executable_dir, 'SaneBarHostExactIDFixture')
    FileUtils.rm_rf(RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH)
    FileUtils.mkdir_p(executable_dir)
    write_runtime_fixture_bundle_icon!(
      app_contents,
      symbol_name: 'target',
      background_hex: '#3166B8',
      fixture_log: fixture_log
    )
    File.write(File.join(app_contents, 'Info.plist'), runtime_host_exact_id_fixture_plist)
    File.write(RUNTIME_HOST_EXACT_ID_FIXTURE_SOURCE_PATH, runtime_host_exact_id_fixture_source)

    output, status = Open3.capture2e('swiftc', RUNTIME_HOST_EXACT_ID_FIXTURE_SOURCE_PATH, '-o', executable_path)
    fixture_log << "swiftc_status=#{status.exitstatus}"
    fixture_log << output.strip unless output.strip.empty?
    return false unless status.success?

    FileUtils.chmod('+x', executable_path)
    true
  rescue StandardError => e
    fixture_log << "build_error=#{e.class}: #{e.message}"
    false
  end

  def wait_for_runtime_host_exact_id_fixture_ids(target, fixture_log)
    deadline = Time.now + 30
    ids = []
    while Time.now < deadline
      refresh_output, refresh_status = refresh_runtime_smoke_icon_inventory(target)
      fixture_log << "refresh_status=#{refresh_status&.exitstatus}"
      fixture_log << refresh_output.lines.grep(/hostsentinel/i).join.strip unless refresh_output.to_s.lines.grep(/hostsentinel/i).empty?
      fixture_log << "fixture_process=#{runtime_host_exact_id_fixture_process_detail}"
      ids = runtime_smoke_available_required_candidate_ids(
        target,
        required_ids: RUNTIME_HOST_EXACT_ID_FIXTURE_IDS
      )
      fixture_log << "attempt_ids=#{ids.join(',')}" unless ids.empty?
      break unless ids.empty?

      sleep 0.5
    end

    fixture_log << "required_ids=#{RUNTIME_HOST_EXACT_ID_FIXTURE_IDS.join(',')}"
    fixture_log << "resolved_ids=#{ids.join(',')}"
    ids
  end

  def runtime_host_exact_id_fixture_process_detail
    runtime_fixture_process_detail(
      'SaneBarHostExactIDFixture',
      app_path: RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH
    )
  end

  def runtime_host_exact_id_fixture_running?
    runtime_host_exact_id_fixture_process_detail != 'none'
  end

  def cleanup_runtime_host_exact_id_fixture!
    Open3.capture2e('/usr/bin/killall', 'SaneBarHostExactIDFixture')
  rescue StandardError
    nil
  end

  def runtime_host_exact_id_fixture_plist
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>SaneBarHostExactIDFixture</string>
        <key>CFBundleIdentifier</key>
        <string>#{RUNTIME_HOST_EXACT_ID_FIXTURE_ID}</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundleName</key>
        <string>SaneBarHostExactIDFixture</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSUIElement</key>
        <true/>
      </dict>
      </plist>
    PLIST
  end

  def runtime_host_exact_id_fixture_source
    <<~SWIFT
      import AppKit

      final class Delegate: NSObject, NSApplicationDelegate {
          var item: NSStatusItem?

          func fixtureImage(_ name: String) -> NSImage? {
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
              image?.isTemplate = true
              return image
          }

          func applicationDidFinishLaunching(_ notification: Notification) {
              NSApp.applicationIconImage = fixtureImage("target")
              let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
              statusItem.button?.image = fixtureImage("target")
              statusItem.button?.imagePosition = .imageLeading
              statusItem.button?.title = "Host"
              statusItem.button?.toolTip = "SaneBar Host Exact ID Fixture"
              statusItem.button?.identifier = NSUserInterfaceItemIdentifier("com.sanebar.hostsentinel.statusItem")
              let menu = NSMenu()
              menu.addItem(NSMenuItem(title: "SaneBar Host Fixture", action: nil, keyEquivalent: ""))
              menu.addItem(NSMenuItem(title: "Activation Probe", action: nil, keyEquivalent: ""))
              statusItem.menu = menu
              item = statusItem
          }
      }

      let app = NSApplication.shared
      let delegate = Delegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)
      app.run()
    SWIFT
  end

  def ensure_runtime_dynamic_helper_wake_fixture!(target)
    fixture_log = []
    fixture_log << "app_path=#{RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH}"
    fixture_log << "external_process=#{runtime_dynamic_helper_external_process_detail}"

    if runtime_dynamic_helper_external_running?
      ids = wait_for_runtime_dynamic_helper_fixture_ids(target, fixture_log)
      unless ids.empty?
        File.write(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
        return ids
      end
    end

    unless runtime_dynamic_helper_fixture_running? || start_runtime_dynamic_helper_fixture!(fixture_log)
      File.write(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
      return []
    end

    ids = wait_for_runtime_dynamic_helper_fixture_ids(target, fixture_log)
    File.write(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
    ids
  end

  def prelaunch_runtime_dynamic_helper_fixture!
    fixture_log = ["app_path=#{RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH}", 'prelaunch=1']
    cleanup_runtime_dynamic_helper_fixture!
    if runtime_dynamic_helper_external_running?
      fixture_log << "external_process=#{runtime_dynamic_helper_external_process_detail}"
      fixture_log << 'prelaunch_skipped=external-helper-running'
      File.write(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
      return
    end

    start_runtime_dynamic_helper_fixture!(fixture_log)
    File.write(RUNTIME_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
  end

  def start_runtime_dynamic_helper_fixture!(fixture_log)
    return false unless build_runtime_dynamic_helper_fixture!(fixture_log)

    launched = system('open', '-n', RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH, out: File::NULL, err: File::NULL)
    fixture_log << "open=#{launched ? 'ok' : 'failed'}"
    return false unless launched

    sleep 1

    runtime_dynamic_helper_fixture_running?
  end

  def build_runtime_dynamic_helper_fixture!(fixture_log)
    app_contents = File.join(RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH, 'Contents')
    executable_dir = File.join(app_contents, 'MacOS')
    executable_path = File.join(executable_dir, 'SaneBarDynamicHelperFixture')
    FileUtils.rm_rf(RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH)
    FileUtils.mkdir_p(executable_dir)
    write_runtime_fixture_bundle_icon!(
      app_contents,
      symbol_name: 'moon.fill',
      background_hex: '#5641A3',
      fixture_log: fixture_log
    )
    File.write(File.join(app_contents, 'Info.plist'), runtime_dynamic_helper_fixture_plist)
    File.write(RUNTIME_DYNAMIC_HELPER_FIXTURE_SOURCE_PATH, runtime_dynamic_helper_fixture_source)

    output, status = Open3.capture2e('swiftc', RUNTIME_DYNAMIC_HELPER_FIXTURE_SOURCE_PATH, '-o', executable_path)
    fixture_log << "swiftc_status=#{status.exitstatus}"
    fixture_log << output.strip unless output.strip.empty?
    return false unless status.success?

    FileUtils.chmod('+x', executable_path)
    true
  rescue StandardError => e
    fixture_log << "build_error=#{e.class}: #{e.message}"
    false
  end

  def wait_for_runtime_dynamic_helper_fixture_ids(target, fixture_log)
    deadline = Time.now + 30
    ids = []
    while Time.now < deadline
      refresh_output, refresh_status = refresh_runtime_smoke_icon_inventory(target)
      fixture_log << "refresh_status=#{refresh_status&.exitstatus}"
      fixture_log << refresh_output.lines.grep(/Lungo|sindresorhus/i).join.strip unless refresh_output.to_s.lines.grep(/Lungo|sindresorhus/i).empty?
      fixture_log << "fixture_process=#{runtime_dynamic_helper_fixture_process_detail}"
      ids = runtime_smoke_available_required_candidate_ids(
        target,
        required_ids: RUNTIME_DYNAMIC_HELPER_FIXTURE_IDS
      )
      fixture_log << "attempt_ids=#{ids.join(',')}" unless ids.empty?
      break if ids.length >= RUNTIME_DYNAMIC_HELPER_FIXTURE_IDS.length

      sleep 0.5
    end

    fixture_log << "required_ids=#{RUNTIME_DYNAMIC_HELPER_FIXTURE_IDS.join(',')}"
    fixture_log << "resolved_ids=#{ids.join(',')}"
    ids
  end

  def runtime_dynamic_helper_fixture_process_detail
    runtime_fixture_process_detail(
      'SaneBarDynamicHelperFixture',
      app_path: RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH
    )
  end

  def runtime_dynamic_helper_fixture_running?
    runtime_dynamic_helper_fixture_process_detail != 'none'
  end

  def runtime_dynamic_helper_external_process_detail
    runtime_fixture_process_detail('Lungo')
  end

  def runtime_dynamic_helper_external_running?
    runtime_dynamic_helper_external_process_detail != 'none'
  end

  def cleanup_runtime_dynamic_helper_fixture!
    Open3.capture2e('/usr/bin/killall', 'SaneBarDynamicHelperFixture')
  rescue StandardError
    nil
  end

  def runtime_dynamic_helper_fixture_plist
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>SaneBarDynamicHelperFixture</string>
        <key>CFBundleIdentifier</key>
        <string>#{RUNTIME_DYNAMIC_HELPER_FIXTURE_ID}</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundleName</key>
        <string>Lungo</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSUIElement</key>
        <true/>
      </dict>
      </plist>
    PLIST
  end

  def runtime_dynamic_helper_fixture_source
    <<~SWIFT
      import AppKit

      final class Delegate: NSObject, NSApplicationDelegate {
          var item: NSStatusItem?

          func fixtureImage(_ name: String) -> NSImage? {
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
              image?.isTemplate = true
              return image
          }

          func applicationDidFinishLaunching(_ notification: Notification) {
              NSApp.applicationIconImage = fixtureImage("moon.fill")
              let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
              statusItem.button?.image = fixtureImage("moon.fill")
              statusItem.button?.imagePosition = .imageLeading
              statusItem.button?.title = "Lungo"
              statusItem.button?.toolTip = "Lungo"
              statusItem.button?.identifier = NSUserInterfaceItemIdentifier("com.sindresorhus.Lungo-setapp.statusItem")
              item = statusItem
          }
      }

      let app = NSApplication.shared
      let delegate = Delegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)
      app.run()
    SWIFT
  end

  def runtime_shared_bundle_fixture_plist
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>SaneBarSharedFixture</string>
        <key>CFBundleIdentifier</key>
        <string>#{RUNTIME_SHARED_BUNDLE_FIXTURE_ID}</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundleName</key>
        <string>SaneBarSharedFixture</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSUIElement</key>
        <true/>
      </dict>
      </plist>
    PLIST
  end

  def runtime_shared_bundle_fixture_source
    <<~SWIFT
      import AppKit

      final class Delegate: NSObject, NSApplicationDelegate {
          var items: [NSStatusItem] = []

          func fixtureImage(for title: String) -> NSImage? {
              let symbolName: String
              switch title {
              case "SBF-A": symbolName = "circle.grid.2x2.fill"
              case "SBF-B": symbolName = "square.grid.2x2.fill"
              case "SBF-D": symbolName = "circle.hexagongrid.fill"
              case "SBF-E": symbolName = "square.grid.3x3.fill"
              default: symbolName = "diamond.grid.3x3.fill"
              }
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
              image?.isTemplate = true
              return image
          }

          func fixtureMenu(for title: String) -> NSMenu {
              let menu = NSMenu()
              menu.addItem(NSMenuItem(title: "SaneBar Shared Fixture \\(title)", action: nil, keyEquivalent: ""))
              menu.addItem(NSMenuItem(title: "Activation Probe \\(title)", action: nil, keyEquivalent: ""))
              return menu
          }

          func applicationDidFinishLaunching(_ notification: Notification) {
              NSApp.applicationIconImage = fixtureImage(for: "SBF-A")
              for title in ["SBF-A", "SBF-B", "SBF-C", "SBF-D", "SBF-E"] {
                  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                  item.button?.image = fixtureImage(for: title)
                  item.button?.imagePosition = .imageLeading
                  item.button?.title = title
                  item.button?.toolTip = "SaneBar Shared Fixture \\(title)"
                  item.button?.identifier = NSUserInterfaceItemIdentifier("com.sanebar.sharedfixture.\\(title)")
                  item.button?.setAccessibilityIdentifier("com.sanebar.sharedfixture.\\(title)")
                  item.menu = fixtureMenu(for: title)
                  items.append(item)
              }
          }
      }

      let app = NSApplication.shared
      let delegate = Delegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)
      app.run()
    SWIFT
  end
end
