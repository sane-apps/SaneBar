# frozen_string_literal: true

# Runtime fixture overrides and the generated Swift source for the
# shared-bundle QA fixture. This file is required AFTER
# project_qa_runtime_fixtures.rb and overrides legacy definitions there (that
# file is over the Rule #10 split limit and cannot be edited until it is
# split; the overridden method bodies there are dead).
class ProjectQA
  private

  def owned_runtime_fixture_process_detail(executable_name, app_path:)
    matches = owned_runtime_fixture_processes(executable_name, app_path: app_path)
    matches.empty? ? 'none' : matches.join(' | ')
  rescue StandardError
    'unavailable'
  end

  def owned_runtime_fixture_processes(executable_name, app_path:)
    expected = owned_runtime_fixture_executable_path(app_path, executable_name)
    output, status = Open3.capture2e('ps', 'ax', '-o', 'pid=,command=')
    return [] unless status.success?

    output.lines.each_with_object([]) do |line, matches|
      pid, command = line.strip.split(/\s+/, 2)
      next unless pid && command

      executable_path = command.split(/\s+/, 2).first.to_s
      next unless File.basename(executable_path) == executable_name
      next unless owned_runtime_fixture_executable_path(File.dirname(File.dirname(File.dirname(executable_path))), executable_name) == expected

      matches << "#{pid} #{command}"
    end
  end

  def owned_runtime_fixture_executable_path(app_path, executable_name)
    path = File.join(app_path, 'Contents', 'MacOS', executable_name)
    File.realpath(path)
  rescue StandardError
    File.expand_path(path)
  end

  def runtime_shared_bundle_fixture_process_detail
    owned_runtime_fixture_process_detail(
      'SaneBarSharedFixture',
      app_path: RUNTIME_SHARED_BUNDLE_FIXTURE_APP_PATH
    )
  end

  def runtime_dynamic_helper_fixture_process_detail
    owned_runtime_fixture_process_detail(
      'SaneBarDynamicHelperFixture',
      app_path: RUNTIME_DYNAMIC_HELPER_FIXTURE_APP_PATH
    )
  end

  def runtime_host_exact_id_fixture_process_detail
    owned_runtime_fixture_process_detail(
      'SaneBarHostExactIDFixture',
      app_path: RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH
    )
  end

  # Prelaunch alongside the other fixtures: the ad-hoc /tmp app needs minutes
  # of settle time before its status item resolves in scans (Gatekeeper
  # assessment + registration latency), and launching it only inside the
  # host exact-id smoke left it a 30s window that reliably missed.
  def prelaunch_runtime_host_exact_id_fixture!
    return if runtime_host_exact_id_fixture_running?

    fixture_log = ['prelaunch=1', "app_path=#{RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH}"]
    start_runtime_host_exact_id_fixture!(fixture_log)
    File.write(RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
  rescue StandardError
    nil
  end

  # Override: reuse an already-running host fixture instead of killing and
  # relaunching it (the restart resets the settle clock that prelaunch paid
  # for), and give id resolution a wider window.
  def ensure_runtime_host_exact_id_fixture!(target)
    fixture_log = []
    fixture_log << "app_path=#{RUNTIME_HOST_EXACT_ID_FIXTURE_APP_PATH}"

    if runtime_host_exact_id_fixture_running?
      fixture_log << 'reuse=already-running'
    else
      unless start_runtime_host_exact_id_fixture!(fixture_log)
        File.write(RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
        return []
      end
    end

    ids = wait_for_runtime_host_exact_id_fixture_ids(target, fixture_log, deadline_seconds: 90)
    File.write(RUNTIME_HOST_EXACT_ID_FIXTURE_LOG_PATH, fixture_log.join("\n") + "\n")
    ids
  end

  # Override: parameterized deadline (legacy hardcoded 30s).
  def wait_for_runtime_host_exact_id_fixture_ids(target, fixture_log, deadline_seconds: 90)
    deadline = Time.now + deadline_seconds
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
              // Five items, not three: the seeding donor pool needs headroom
              // because individual fixture items intermittently miss a scan
              // pass, and the zone minimums (1 visible + 1 hidden + 3
              // alwaysHidden) require five candidates.
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
