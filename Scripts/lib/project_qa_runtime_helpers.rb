# frozen_string_literal: true

class ProjectQA
  PREFERRED_RUNTIME_SMOKE_ALWAYS_HIDDEN_BUNDLE = 'com.sanebar.sharedfixture'

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

def ensure_runtime_smoke_representative_zones_ready!(target)
  required_zones = %w[visible hidden alwaysHidden]
  minimum_counts = { 'alwaysHidden' => 3 }
  warm_runtime_smoke_candidate_pool!(target)
  initial_counts = runtime_smoke_representative_zone_counts(target)
  sleep 3 if required_zones.any? { |zone| initial_counts.fetch(zone, 0).zero? }

  (required_zones - ['alwaysHidden']).each do |zone|
    next if runtime_smoke_representative_zone_counts(target).fetch(zone, 0).positive?

    error = seed_runtime_smoke_zone!(target, zone)
    return error if error
  end

  preferred_error = seed_runtime_smoke_preferred_always_hidden_candidate!(target)
  return preferred_error if preferred_error

  required_zones.each do |zone|
    next if runtime_smoke_representative_zone_counts(target).fetch(zone, 0).positive?

    error = seed_runtime_smoke_zone!(target, zone)
    return error if error
  end

  minimum_counts.each do |zone, minimum|
    while runtime_smoke_representative_zone_counts(target).fetch(zone, 0) < minimum
      error = seed_runtime_smoke_zone!(target, zone)
      return error if error
    end
  end

  required_zones.each do |zone|
    next if runtime_smoke_representative_zone_counts(target).fetch(zone, 0).positive?

    error = seed_runtime_smoke_zone!(target, zone)
    return error if error
  end

  counts = runtime_smoke_representative_zone_counts(target)
  missing = required_zones.select { |zone| counts.fetch(zone, 0).zero? }
  under_minimum = minimum_counts.select { |zone, minimum| counts.fetch(zone, 0) < minimum }
  return "Runtime smoke could not seed minimum representative candidates #{under_minimum.inspect} (candidate=#{counts})." unless under_minimum.empty?
  return nil if missing.empty?

  "Runtime smoke could not seed representative movable candidates for #{missing.join(', ')} (candidate=#{counts})."
end

def seed_runtime_smoke_preferred_always_hidden_candidate!(target)
  last_error = nil
  failed_donor_ids = []

  3.times do |attempt|
    candidates = runtime_smoke_representative_zone_candidates(target)
    preferred = candidates.select { |item| item[:bundle].to_s == PREFERRED_RUNTIME_SMOKE_ALWAYS_HIDDEN_BUNDLE }
    return nil if preferred.empty?
    return nil if preferred.any? { |item| item[:zone].to_s == 'alwaysHidden' }

    donors = preferred
             .select { |item| item[:zone].to_s != 'alwaysHidden' }
             .reject { |item| failed_donor_ids.include?(item[:unique_id]) }
             .sort_by { |item| item[:zone].to_s == 'hidden' ? 0 : 1 }
    donor = donors.first
    return nil unless donor

    output, status = runtime_smoke_move_icon(target, 'move icon to always hidden', donor[:unique_id])
    if status.success?
      sleep 0.8
      return nil
    end

    failed_donor_ids << donor[:unique_id]
    last_error = output.lines.last&.strip || output.strip
    sleep(1.2 + (attempt * 0.8))
  end

  "Runtime smoke failed to seed preferred always-hidden fixture #{PREFERRED_RUNTIME_SMOKE_ALWAYS_HIDDEN_BUNDLE}: #{last_error}"
end

def runtime_smoke_representative_zone_counts(target)
  runtime_smoke_representative_zone_candidates(target)
    .group_by { |item| item[:zone].to_s }
    .transform_values(&:length)
end

def runtime_smoke_representative_zone_candidates(target)
  runtime_smoke_list_icon_zones(target).select do |item|
    item[:movable] &&
      %w[visible hidden alwaysHidden].include?(item[:zone].to_s) &&
      !item[:bundle].to_s.start_with?('com.sanebar.app') &&
      !runtime_smoke_move_candidate_denied?(item)
  end
end

# Right after a fresh launch the app's zone classification can briefly report
# few classifiable items while menu bar geometry settles. Refresh the icon
# inventory and wait for a workable candidate pool before seeding instead of
# concluding from a starved snapshot.
def warm_runtime_smoke_candidate_pool!(target, minimum_candidates: 4, attempts: 4)
  attempts.times do |attempt|
    return if runtime_smoke_representative_zone_candidates(target).length >= minimum_candidates

    refresh_runtime_smoke_icon_inventory(target)
    sleep(1.5 + attempt)
  end
end

def runtime_smoke_candidate_pool_summary(target)
  runtime_smoke_representative_zone_candidates(target)
    .map { |item| "#{item[:zone]}:#{item[:unique_id]}" }
    .join(', ')
end

def seed_runtime_smoke_zone!(target, missing_zone)
  command = {
    'visible' => 'move icon to visible',
    'hidden' => 'move icon to hidden',
    'alwaysHidden' => 'move icon to always hidden'
  }.fetch(missing_zone)
  last_error = nil
  failed_donor_ids = []

  5.times do |attempt|
    candidates = runtime_smoke_representative_zone_candidates(target)
    counts = candidates.group_by { |item| item[:zone].to_s }.transform_values(&:length)
    before_target_count = counts.fetch(missing_zone, 0)
    donor_zone = runtime_smoke_donor_zone_for_missing_zone(missing_zone, counts, candidates, failed_donor_ids)
    unless donor_zone
      return "Runtime smoke cannot seed #{missing_zone}; no donor zone can remain populated (candidate=#{counts}; pool=#{runtime_smoke_candidate_pool_summary(target)})."
    end

    donors = candidates
             .select { |item| item[:zone].to_s == donor_zone }
             .reject { |item| failed_donor_ids.include?(item[:unique_id]) }
             .sort_by { |item| runtime_smoke_seed_donor_rank(item, donor_zone) }
    donor = donors.first
    return "Runtime smoke cannot seed #{missing_zone}; no movable donor found in #{donor_zone}." unless donor

    output, status = runtime_smoke_move_icon(target, command, donor[:unique_id])
    if status.success?
      sleep 0.8
      after_count = runtime_smoke_representative_zone_counts(target).fetch(missing_zone, 0)
      return nil if after_count > before_target_count

      failed_donor_ids << donor[:unique_id] unless failed_donor_ids.include?(donor[:unique_id])
      last_error = "from #{donor_zone} using #{donor[:unique_id]}: command returned success but #{missing_zone} count stayed #{after_count}"
      sleep(0.8 + (attempt * 0.6))
      next
    end

    failed_donor_ids << donor[:unique_id] unless failed_donor_ids.include?(donor[:unique_id])
    last_error = "from #{donor_zone} using #{donor[:unique_id]}: #{output.lines.last&.strip || output.strip}"
    sleep(0.8 + (attempt * 0.6))
  end

  "Runtime smoke failed to seed #{missing_zone} #{last_error}"
end

def runtime_smoke_seed_donor_rank(item, donor_zone = nil)
  bundle = item[:bundle].to_s
  # Donating OUT of alwaysHidden must not yank the shared fixture: the
  # preferred-always-hidden step wants it there, and taking it first creates
  # a seeding ping-pong. Everywhere else the fixture is the preferred donor
  # so seeding does not shuffle the user's real menu bar arrangement.
  if donor_zone.to_s == 'alwaysHidden'
    return 0 if !bundle.start_with?('com.apple.') && bundle != 'com.sanebar.sharedfixture'
    return 1 if bundle == 'com.sanebar.sharedfixture'
  else
    return 0 if bundle == 'com.sanebar.sharedfixture'
    return 1 if !bundle.start_with?('com.apple.')
  end
  return 2 if bundle.start_with?('com.apple.')

  3
end

def runtime_smoke_donor_zone_for_missing_zone(missing_zone, counts, candidates = nil, failed_donor_ids = [])
  preferred = case missing_zone
              when 'alwaysHidden' then %w[hidden visible]
              when 'hidden' then %w[visible alwaysHidden]
              else %w[hidden alwaysHidden]
              end
  preferred.find do |zone|
    next false unless counts.fetch(zone, 0) > 1
    next true unless candidates

    candidates.any? { |item| item[:zone].to_s == zone && !failed_donor_ids.include?(item[:unique_id]) }
  end
end

def runtime_smoke_move_icon(target, command, unique_id)
  wait_for_runtime_smoke_move_ready!(target)

  expected_bundle_id = 'com.sanebar.app'
  escaped = unique_id.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  Open3.capture2e(
    'osascript',
    '-e',
    %(set appTarget to ((POSIX file "#{target[:app_path]}" as alias) as text)),
    '-e',
    %(using terms from application id "#{expected_bundle_id}"),
    '-e',
    %(tell application appTarget to #{command} "#{escaped}"),
    '-e',
    'end using terms from'
  )
end

def wait_for_runtime_smoke_move_ready!(target)
  deadline = Time.now + 6
  while Time.now < deadline
    snapshot = runtime_smoke_layout_snapshot(target)
    if snapshot &&
       snapshot['isMoveInProgress'] != true &&
       snapshot['isBrowseVisible'] != true &&
       snapshot['isBrowseSessionActive'] != true &&
       snapshot['isMenuOpen'] != true
      return true
    end
    sleep 0.25
  end

  true
end

def runtime_smoke_move_candidate_denied?(item)
  # Left-side application menus (File/Edit/View…) can be misread by the AX
  # scanner as menu bar icons when an app like WhatsApp is frontmost. They are
  # never legitimate move donors: a Cmd+drag on them reports success but moves
  # nothing, which burns every seeding attempt.
  return true if item[:unique_id].to_s.include?('::axid:com.apple.menu.')

  # The visible-dynamic QA fixture is bundled as com.ameba.SwiftBar. When the
  # fixture owns that identity (fixture running, real SwiftBar absent) it is a
  # legitimate, expendable donor; denying it starves the seeding pool below
  # the 5 candidates the zone minimums require on hosts where every real
  # third-party item is denied.
  if item[:bundle].to_s.strip.casecmp('com.ameba.swiftbar').zero? &&
     runtime_visible_dynamic_helper_fixture_running? &&
     !runtime_visible_dynamic_helper_external_running?
    return false
  end

  bundle = item[:bundle].to_s.strip.downcase
  %w[
    com.apple.controlcenter
    com.apple.systemuiserver
    com.apple.Spotlight
    com.apple.SSMenuAgent
    com.apple.menuextra.focusmode
    com.openai.codex
    com.ameba.SwiftBar
    com.setapp.DesktopClient.SetappLauncher
    com.sindresorhus.Lungo-setapp
    cc.ffitch.shottr
    com.yujitach.MenuMeters
    com.yonilevy.cryptoticker
  ].any? { |value| value.downcase == bundle }
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

    accessibility_auth_value_via_loopback(bundle_id)
  rescue StandardError
    nil
  end

  # TCC.db is Full Disk Access protected. On the approved Air fallback the GUI
  # session host may lack FDA while sshd has it, so the read falls back to
  # loopback SSH (same pattern as the protected universalaccess writes).
  def accessibility_auth_value_via_loopback(bundle_id)
    escaped_bundle = bundle_id.gsub("'", "''")
    query = "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='#{escaped_bundle}' ORDER BY auth_value DESC;"
    [
      '/Library/Application Support/com.apple.TCC/TCC.db',
      File.expand_path('~/Library/Application Support/com.apple.TCC/TCC.db')
    ].each do |db_path|
      output, status = Open3.capture2e(
        '/usr/bin/ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3', 'localhost',
        'sqlite3', "'#{db_path.gsub("'", "'\\\\''")}'", "\"#{query}\""
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
