# frozen_string_literal: true

class ProjectQA
  private

  def ensure_runtime_visible_dynamic_helper_wake_fixture!(target)
    fixture_log = []
    fixture_log << "app_path=#{RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH}"
    fixture_log << "external_process=#{runtime_visible_dynamic_helper_external_process_detail}"

    if runtime_visible_dynamic_helper_external_running?
      ids = wait_for_runtime_visible_dynamic_helper_fixture_ids(target, fixture_log)
      unless ids.empty?
        File.write(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
        return ids
      end
    end

    unless runtime_visible_dynamic_helper_fixture_running? || start_runtime_visible_dynamic_helper_fixture!(fixture_log)
      File.write(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
      return []
    end

    ids = wait_for_runtime_visible_dynamic_helper_fixture_ids(target, fixture_log)
    ids = ensure_runtime_visible_dynamic_helper_fixture_visible!(target, ids, fixture_log)
    File.write(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
    ids
  end

  def prelaunch_runtime_visible_dynamic_helper_fixture!
    fixture_log = ["app_path=#{RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH}", 'prelaunch=1']
    cleanup_runtime_visible_dynamic_helper_fixture!
    if runtime_visible_dynamic_helper_external_running?
      fixture_log << "external_process=#{runtime_visible_dynamic_helper_external_process_detail}"
      fixture_log << 'prelaunch_skipped=external-visible-helper-running'
      File.write(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
      return
    end

    start_runtime_visible_dynamic_helper_fixture!(fixture_log)
    File.write(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
  end

  def start_runtime_visible_dynamic_helper_fixture!(fixture_log)
    return false unless build_runtime_visible_dynamic_helper_fixture!(fixture_log)

    launched = system('open', '-n', RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH, out: File::NULL, err: File::NULL)
    fixture_log << "open=#{launched ? 'ok' : 'failed'}"
    return false unless launched

    sleep 1

    runtime_visible_dynamic_helper_fixture_running?
  end

  def build_runtime_visible_dynamic_helper_fixture!(fixture_log)
    app_contents = File.join(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH, 'Contents')
    executable_dir = File.join(app_contents, 'MacOS')
    executable_path = File.join(executable_dir, 'SaneBarVisibleDynamicHelperFixture')
    FileUtils.rm_rf(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH)
    FileUtils.mkdir_p(executable_dir)
    write_runtime_fixture_bundle_icon!(
      app_contents,
      symbol_name: 'timer',
      background_hex: '#A6542B',
      fixture_log: fixture_log
    )
    File.write(File.join(app_contents, 'Info.plist'), runtime_visible_dynamic_helper_fixture_plist)
    File.write(RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_SOURCE_PATH, runtime_visible_dynamic_helper_fixture_source)

    output, status = Open3.capture2e('swiftc', RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_SOURCE_PATH, '-o', executable_path)
    fixture_log << "swiftc_status=#{status.exitstatus}"
    fixture_log << output.strip unless output.strip.empty?
    return false unless status.success?

    FileUtils.chmod('+x', executable_path)
    true
  rescue StandardError => e
    fixture_log << "build_error=#{e.class}: #{e.message}"
    false
  end

  def wait_for_runtime_visible_dynamic_helper_fixture_ids(target, fixture_log)
    deadline = Time.now + 30
    ids = []
    while Time.now < deadline
      refresh_output, refresh_status = refresh_runtime_smoke_icon_inventory(target)
      fixture_log << "refresh_status=#{refresh_status&.exitstatus}"
      unless refresh_output.to_s.lines.grep(/SwiftBar|ameba/i).empty?
        fixture_log << refresh_output.lines.grep(/SwiftBar|ameba/i).join.strip
      end
      fixture_log << "fixture_process=#{runtime_visible_dynamic_helper_fixture_process_detail}"
      ids = runtime_smoke_available_required_candidate_ids(
        target,
        required_ids: RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_IDS
      )
      fixture_log << "attempt_ids=#{ids.join(',')}" unless ids.empty?
      break if ids.length >= RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_IDS.length

      sleep 0.5
    end

    fixture_log << "required_ids=#{RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_IDS.join(',')}"
    fixture_log << "resolved_ids=#{ids.join(',')}"
    ids
  end

  def ensure_runtime_visible_dynamic_helper_fixture_visible!(target, ids, fixture_log)
    required = Array(ids).map(&:to_s).reject(&:empty?).uniq
    return [] if required.empty?

    # Placing the visible helper is fixture SETUP, not the assertion. The move is a
    # CGEvent Cmd-drag, which SaneBar itself reports needs a brief settle "right after
    # wake or a display change" (-2700) — and this runs right after the startup probe
    # churns the menu bar. The old budget (3 attempts ~0.5s apart, ~1.5s total) gave up
    # before the bar settled, so the Visible->Hidden wake-drift assertion never ran and
    # the whole probe failed on setup. Spread the retries over a longer window with a
    # real settle between tries so setup is reliable; this does not weaken the assertion.
    deadline = Time.now + 60
    last_problem = nil
    move_attempts = Hash.new(0)
    max_move_attempts = 12

    while Time.now < deadline
      zones = runtime_smoke_list_icon_zones(target)
      by_id = zones.each_with_object({}) { |item, map| map[item[:unique_id].to_s] = item }
      missing = required.reject { |identifier| by_id.key?(identifier) }
      non_visible = required.select { |identifier| by_id[identifier] && by_id[identifier][:zone] != 'visible' }
      if missing.empty? && non_visible.empty?
        fixture_log << "visible_ids=#{required.join(',')}"
        return required
      end

      non_visible.each do |identifier|
        next if move_attempts[identifier] >= max_move_attempts

        output, status = runtime_smoke_move_icon(target, 'move icon to visible', identifier)
        move_attempts[identifier] += 1
        fixture_log << "move_visible=#{identifier}:#{status&.success? ? 'ok' : 'failed'}(attempt #{move_attempts[identifier]})"
        fixture_log << output.lines.last.to_s.strip unless output.to_s.strip.empty?
      end

      last_problem = "missing=#{missing.join(',')} non_visible=#{non_visible.join(',')}"
      sleep 2
    end

    fixture_log << "visible_settle_failed=#{last_problem}"
    []
  end

  def runtime_visible_dynamic_helper_fixture_process_detail
    owned_runtime_fixture_process_detail(
      'SaneBarVisibleDynamicHelperFixture',
      app_path: RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_APP_PATH
    )
  end

  def runtime_visible_dynamic_helper_fixture_running?
    runtime_visible_dynamic_helper_fixture_process_detail != 'none'
  end

  def runtime_visible_dynamic_helper_external_process_detail
    runtime_fixture_process_detail('SwiftBar')
  end

  def runtime_visible_dynamic_helper_external_running?
    runtime_visible_dynamic_helper_external_process_detail != 'none'
  end

  def cleanup_runtime_visible_dynamic_helper_fixture!
    Open3.capture2e('/usr/bin/killall', 'SaneBarVisibleDynamicHelperFixture')
  rescue StandardError
    nil
  end

  def runtime_visible_dynamic_helper_fixture_plist
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>SaneBarVisibleDynamicHelperFixture</string>
        <key>CFBundleIdentifier</key>
        <string>#{RUNTIME_VISIBLE_DYNAMIC_HELPER_FIXTURE_ID}</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundleName</key>
        <string>SwiftBar</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSUIElement</key>
        <true/>
      </dict>
      </plist>
    PLIST
  end

  def runtime_visible_dynamic_helper_fixture_source
    <<~SWIFT
      import AppKit

      final class Delegate: NSObject, NSApplicationDelegate {
          var item: NSStatusItem?
          var timer: Timer?
          var tickCount = 0

          func fixtureImage(_ name: String) -> NSImage? {
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
              image?.isTemplate = true
              return image
          }

          func applicationDidFinishLaunching(_ notification: Notification) {
              NSApp.applicationIconImage = fixtureImage("timer")
              let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
              statusItem.button?.image = fixtureImage("timer")
              statusItem.button?.imagePosition = .imageLeading
              statusItem.button?.title = "11"
              statusItem.button?.toolTip = "SwiftBar dynamic counter"
              statusItem.button?.identifier = NSUserInterfaceItemIdentifier("com.ameba.SwiftBar.dynamicCounter")
              let menu = NSMenu()
              menu.addItem(NSMenuItem(title: "SwiftBar Fixture", action: nil, keyEquivalent: ""))
              menu.addItem(NSMenuItem(title: "Dynamic Counter", action: nil, keyEquivalent: ""))
              statusItem.menu = menu
              item = statusItem
              timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                  self?.advanceCounter()
              }
          }

          func advanceCounter() {
              tickCount += 1
              item?.button?.image = fixtureImage(tickCount.isMultiple(of: 2) ? "timer" : "timer.circle.fill")
              item?.button?.title = tickCount.isMultiple(of: 2) ? "_" : "11"
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
