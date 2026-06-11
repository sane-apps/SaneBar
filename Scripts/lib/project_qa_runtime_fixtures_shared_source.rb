# frozen_string_literal: true

# Generated Swift source for the shared-bundle QA fixture.
# This file is required AFTER project_qa_runtime_fixtures.rb and overrides the
# legacy 3-item definition there (that file is over the Rule #10 split limit
# and cannot be edited until it is split; the legacy method body is dead).
class ProjectQA
  private

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
