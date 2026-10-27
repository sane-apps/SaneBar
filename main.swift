import AppKit
import Foundation
import ServiceManagement


let app = NSApplication.shared

let args = CommandLine.arguments
if args.contains("--unregister") {
    print("[SaneBar] Unregistering from background services...")
    do {
        try SMAppService.mainApp.unregister()
        print("[SaneBar] Successfully unregistered.")
    } catch {
        print("[SaneBar] Failed to unregister: \(error)")
    }
    exit(0)
}

app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .darkAqua)

let bundleId = Bundle.main.bundleIdentifier ?? "(unknown)"
#if PRODDEBUG
#elseif DEBUG
    if bundleId == "com.sanebar.app" {
        let env = ProcessInfo.processInfo.environment
        if env["SANEBAR_ALLOW_PROD_BUNDLE"] != "1" {
            fatalError("Debug build is using production bundle ID (com.sanebar.app). Use ProdDebug config or set SANEBAR_ALLOW_PROD_BUNDLE=1.")
        }
    }
#else
    let expectedBundleId = "com.sanebar.app"
    if bundleId != expectedBundleId {
        fatalError("Release build must use production bundle ID (\(expectedBundleId)). Found: \(bundleId)")
    }
#endif

if GoldenGateNotice.applies {
    let notice = GoldenGateNoticeDelegate()
    app.delegate = notice
    app.run()
    exit(0)
}

SaneBarAppDelegate.installNoKeychainAutomationSignalGuardIfNeeded()

let delegate = SaneBarAppDelegate()
app.delegate = delegate
app.run()
