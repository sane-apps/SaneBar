# frozen_string_literal: true

class ProjectQA
  private

  def runtime_smoke_expected_modes(target)
    commands = applescript_commands_for_app(target[:app_path])
    modes = []
    modes << 'secondMenuBar' if commands.include?('show second menu bar')
    modes << 'findIcon' if commands.include?('open icon panel')
    modes << 'settings' if commands.include?('open settings window')
    modes
  end

  def runtime_probe_no_keychain_env(target)
    return {} unless target[:no_keychain]

    {
      'SANEAPPS_DISABLE_KEYCHAIN' => '1',
      'SANEBAR_PROBE_FORCE_NO_KEYCHAIN' => '1'
    }
  end

def runtime_smoke_available_required_candidate_ids(target, required_ids:)
  snapshot = runtime_smoke_layout_snapshot(target) || {}
  allow_always_hidden = snapshot['licenseIsPro'] == true
  zones = runtime_smoke_list_icon_zones(target)
  required_ids.select do |required_id|
    zone = zones.find { |item| item[:unique_id] == required_id }
    next false unless zone
    next false unless zone[:movable]

    allow_always_hidden || zone[:zone] != 'alwaysHidden'
  end
end

def runtime_smoke_available_shared_bundle_candidate_ids(target, required_ids:)
  snapshot = runtime_smoke_layout_snapshot(target) || {}
  allow_always_hidden = snapshot['licenseIsPro'] == true
  zones = runtime_smoke_list_icon_zones(target)
  candidates = []
  required_ids.each do |required_id|
    zone = zones.find { |item| item[:unique_id] == required_id }
    next unless zone
    next unless zone[:movable]
    next unless allow_always_hidden || zone[:zone] != 'alwaysHidden'

    candidates << zone
  end
  grouped = candidates.group_by { |item| item[:bundle] }
  shared_group = grouped.values.find { |items| items.length >= 2 }
  return [] unless shared_group

  shared_group.map { |item| item[:unique_id] }
end

def runtime_smoke_list_icon_zone_ids(target)
  runtime_smoke_list_icon_zones(target).map { |item| item[:unique_id] }
end

def runtime_smoke_list_icon_zones(target)
  return [] unless ensure_runtime_smoke_target_running!(target)

  expected_bundle_id = 'com.sanebar.app'
  output, status = Open3.capture2e(
    'osascript',
    '-e',
    %(set appTarget to ((POSIX file "#{target[:app_path]}" as alias) as text)),
    '-e',
    %(using terms from application id "#{expected_bundle_id}"),
    '-e',
    'tell application appTarget to list icon zones',
    '-e',
    'end using terms from'
  )
  return [] unless status.success?

  output.lines.map do |line|
    zone, movable, bundle, unique_id, name = line.strip.split("\t", 5)
    next nil if unique_id.nil? || unique_id.empty?

    {
      zone: zone,
      movable: movable == 'true',
      bundle: bundle,
      unique_id: unique_id,
      name: name
    }
  end.compact
rescue StandardError
  []
end

def applescript_commands_for_app(app_path)


    sdef_path = File.join(app_path, 'Contents', 'Resources', "#{PROJECT_NAME}.sdef")
    return [] unless File.exist?(sdef_path)

    File.read(sdef_path).scan(/<command name="([^"]+)"/).flatten
  rescue StandardError
    []
  end

  def developer_id_signed?(app_path)
    output, status = Open3.capture2e('codesign', '-dv', '--verbose=2', app_path)
    return false unless status.success? || !output.to_s.empty?

    output.lines.any? { |line| line.start_with?('Authority=Developer ID Application:') }
  end

  def app_bundle_metadata(app_path)
    info_plist = File.join(app_path, 'Contents', 'Info.plist')
    return {} unless File.exist?(info_plist)

    {
      short_version: plist_value(info_plist, 'CFBundleShortVersionString'),
      build_version: plist_value(info_plist, 'CFBundleVersion'),
      bundle_id: plist_value(info_plist, 'CFBundleIdentifier')
    }
  end

  def plist_value(info_plist, key)
    output, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", info_plist)
    return nil unless status.success?

    output.lines.last&.strip
  rescue StandardError
    nil
  end

  def accessibility_auth_value_for(bundle_id)
    db_paths = [
      '/Library/Application Support/com.apple.TCC/TCC.db',
      File.expand_path('~/Library/Application Support/com.apple.TCC/TCC.db')
    ]

    db_paths.each do |db_path|
      next unless File.exist?(db_path)

      escaped_bundle = bundle_id.gsub("'", "''")
      output, status = Open3.capture2e(
        'sqlite3',
        db_path,
        "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='#{escaped_bundle}' ORDER BY auth_value DESC;"
      )
      next unless status.success?

      value = output.lines.map(&:strip).find { |line| !line.empty? }
      return value.to_i unless value.nil?
    end

    nil
  rescue StandardError
    nil
  end

  def same_release_build?(left, right)
    left_short = left[:short_version].to_s
    left_build = left[:build_version].to_s
    right_short = right[:short_version].to_s
    right_build = right[:build_version].to_s

    return false if left_short.empty? || left_build.empty? || right_short.empty? || right_build.empty?

    left_short == right_short && left_build == right_build
  end

  def format_bundle_metadata(metadata)
    short = metadata[:short_version].to_s
    build = metadata[:build_version].to_s
    bundle = metadata[:bundle_id].to_s
    parts = []
    parts << (short.empty? ? 'unknown version' : "v#{short}")
    parts << (build.empty? ? 'unknown build' : "build #{build}")
    parts << (bundle.empty? ? 'unknown bundle id' : bundle)
    parts.join(', ')
  end

  def capture2e_with_progress(env, *cmd, heartbeat_label:)
    output = +''
    status = nil
    started_at = Time.now
    last_output_at = Time.now
    last_heartbeat_at = Time.at(0)

    Open3.popen2e(env, *cmd) do |_stdin, stdout_err, wait_thr|
      loop do
        ready = IO.select([stdout_err], nil, nil, 1)
        if ready
          begin
            chunk = normalize_output_chunk(stdout_err.read_nonblock(4096))
            output << chunk
            print chunk
            $stdout.flush
            last_output_at = Time.now unless chunk.empty?
          rescue IO::WaitReadable
            nil
          rescue EOFError
            nil
          end
        end

        if wait_thr.join(0)
          status = wait_thr.value
          break
        end

        next unless (Time.now - last_output_at) >= RUNTIME_SMOKE_HEARTBEAT_SECONDS
        next unless (Time.now - last_heartbeat_at) >= RUNTIME_SMOKE_HEARTBEAT_SECONDS

        elapsed = (Time.now - started_at).round(1)
        puts "   … #{heartbeat_label} still running (#{elapsed}s)"
        last_heartbeat_at = Time.now
      end

      loop do
        chunk = normalize_output_chunk(stdout_err.read_nonblock(4096))
        output << chunk
        print chunk
        $stdout.flush
      rescue IO::WaitReadable
        break
      rescue EOFError
        break
      end
    end

    [output, status]
  end

  def normalize_output_chunk(chunk)
    normalized = chunk.dup
    normalized.force_encoding(Encoding::UTF_8)
    return normalized if normalized.valid_encoding?

    chunk.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace, replace: '?')
  rescue StandardError
    chunk.to_s.encode(Encoding::UTF_8, Encoding::BINARY, invalid: :replace, undef: :replace, replace: '?')
  end
end
