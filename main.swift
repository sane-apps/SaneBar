import AppKit
import Foundation
import ServiceManagement

// Entry point for SaneBar
// Using manual main.swift instead of @main to control initialization timing

let app = NSApplication.shared

// Handle command line arguments
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

// CRITICAL: Set activation policy to .accessory BEFORE app.run()
// This ensures NSStatusItem windows are created at window layer 25 (status bar layer)
// instead of layer 0 (regular window layer). Setting this in applicationDidFinishLaunching
// is TOO LATE - the window layer is determined when the run loop starts.
app.setActivationPolicy(.accessory)

// SAFETY: Enforce bundle ID separation between dev and release builds
// ProdDebug config uses production bundle ID intentionally (for testing with real permissions)
let bundleId = Bundle.main.bundleIdentifier ?? "(unknown)"
#if PRODDEBUG
// ProdDebug: production bundle ID is expected — no check needed
#elseif DEBUG
    if bundleId == "com.sanebar.app" {
        let env = ProcessInfo.processInfo.environment
        if env["SANEBAR_ALLOW_PROD_BUNDLE"] != "1" {
            fatalError("Debug build is using production bundle ID (com.sanebar.app). Use ProdDebug config or set SANEBAR_ALLOW_PROD_BUNDLE=1.")
        }
    }
#else
    if bundleId != "com.sanebar.app" {
        fatalError("Release build must use production bundle ID (com.sanebar.app). Found: \(bundleId)")
    }
#endif

let delegate = SaneBarAppDelegate()
app.delegate = delegate
app.run()
