# frozen_string_literal: true

class WakeLayoutProbe
  private

  def capture(*cmd)
    out, status = Open3.capture2e(*cmd)
    log("$ #{cmd.join(' ')}")
    log(out.strip) unless out.strip.empty?
    [out, status]
  end

  def log(line)
    @lines << "[#{Time.now.utc.iso8601}] #{line}"
  end

  def persist_log!
    FileUtils.mkdir_p(File.dirname(@log_path))
    File.write(@log_path, @lines.join("\n") + "\n")
  end

  def cliclick_path
    cliclick = ['/opt/homebrew/bin/cliclick', '/usr/local/bin/cliclick']
      .find { |path| File.executable?(path) }
    raise 'Wake probe requires cliclick on the Mini to park the pointer away from the menu bar' unless cliclick
    cliclick
  end

  def cursor_position
    out, status = capture(cliclick_path, 'p')
    raise "Could not read pointer position: #{out}" unless status.success?
    match = out.strip.match(/\A(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)\z/)
    raise "Could not parse pointer position: #{out.inspect}" unless match
    { x: match[1].to_f, y: match[2].to_f }
  end

  def assert_cursor_stable!(baseline, label:, tolerance: 3.0)
    current = cursor_position
    drift = Math.sqrt(((current[:x] - baseline[:x])**2) + ((current[:y] - baseline[:y])**2))
    raise "Passive wake recovery moved cursor during #{label}: #{baseline.inspect} -> #{current.inspect} (#{drift.round(2)}px)" if drift > tolerance
    {
      status: 'passed',
      baseline: baseline,
      current: current,
      tolerance: tolerance,
      completed_scenario: 'passive wake recovery did not physically move the cursor'
    }
  end

  def write_artifact!(payload)
    payload[:candidate] = runtime_candidate_metadata
    if @visible_zone_proofs.any?
      completed = visible_zone_completed_scenarios
      required = visible_zone_required_scenarios
      payload[:visible_zone_persistence] = {
        status: (required - completed).empty? ? 'pass' : 'fail',
        completed_scenarios: completed,
        proofs: @visible_zone_proofs
      }
    end
    if @hidden_zone_proofs.any?
      completed = hidden_zone_completed_scenarios
      required = hidden_zone_required_scenarios
      payload[:hidden_zone_persistence] = {
        status: (required - completed).empty? ? 'pass' : 'fail',
        completed_scenarios: completed,
        proofs: @hidden_zone_proofs
      }
      unless @dynamic_helper_ids.empty?
        dynamic_required = dynamic_helper_required_scenarios
        payload[:dynamic_helper_wake_drift] = {
          status: (dynamic_required - completed).empty? ? 'pass' : 'fail',
          required_ids: @dynamic_helper_ids,
          completed_scenarios: completed,
          proofs: @hidden_zone_proofs
        }
      end
    end
    FileUtils.mkdir_p(File.dirname(@artifact_path))
    File.write(@artifact_path, JSON.pretty_generate(payload) + "\n")
  end

  def runtime_candidate_metadata
    info_plist = File.join(@app_path.to_s, 'Contents', 'Info.plist')
    {
      app_path: @app_path,
      app_version: plist_value(info_plist, 'CFBundleShortVersionString'),
      app_build: plist_value(info_plist, 'CFBundleVersion')
    }
  end

  def plist_value(info_plist, key)
    return nil unless File.exist?(info_plist)

    out, status = Open3.capture2e('/usr/libexec/PlistBuddy', '-c', "Print :#{key}", info_plist)
    status.success? ? out.strip : nil
  end

  def visible_zone_required_scenarios
    [
      'baseline visible icon-zone snapshot before display sleep',
      'fresh authoritative icon-zone snapshot at 1s after wake',
      'fresh authoritative icon-zone snapshot at 5s after wake',
      'fresh authoritative icon-zone snapshot at 15s after wake',
      'visible required IDs remain visible and are not moved into Hidden or Always Hidden'
    ]
  end

  def visible_zone_completed_scenarios
    @visible_zone_proofs.flat_map do |proof|
      [proof[:completed_scenario], *Array(proof[:completed_scenarios])]
    end.compact.map(&:to_s).uniq
  end

  def hidden_zone_required_scenarios
    [
      'baseline hidden icon-zone snapshot before display sleep',
      'fresh authoritative icon-zone snapshot at 1s after wake',
      'fresh authoritative icon-zone snapshot at 5s after wake',
      'fresh authoritative icon-zone snapshot at 15s after wake',
      'hidden required IDs remain hidden and are not moved into Visible or Always Hidden'
    ]
  end

  def dynamic_helper_required_scenarios
    [
      'dynamic helper required IDs are present before wake',
      'dynamic helper required IDs remain in intended zones after wake',
      'helper-specific Hidden to Visible drift is rejected as a release blocker'
    ]
  end

  def hidden_zone_completed_scenarios
    @hidden_zone_proofs.flat_map do |proof|
      [proof[:completed_scenario], *Array(proof[:completed_scenarios])]
    end.compact.map(&:to_s).uniq
  end
end
