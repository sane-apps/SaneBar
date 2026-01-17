import AppKit
import Foundation

// Entry point for SaneBar
// Using manual main.swift instead of @main to control initialization timing

let app = NSApplication.shared

// CRITICAL: Set activation policy to .accessory BEFORE app.run()
// This ensures NSStatusItem windows are created at window layer 25 (status bar layer)
// instead of layer 0 (regular window layer). Setting this in applicationDidFinishLaunching
// is TOO LATE - the window layer is determined when the run loop starts.
app.setActivationPolicy(.accessory)

// SAFETY: Enforce bundle ID separation between dev and release builds
let bundleId = Bundle.main.bundleIdentifier ?? "(unknown)"
let env = ProcessInfo.processInfo.environment
#if DEBUG
if bundleId == "com.sanebar.app" && env["SANEBAR_ALLOW_PROD_BUNDLE"] != "1" {
	fatalError("Debug build is using production bundle ID (com.sanebar.app). Set SANEBAR_ALLOW_PROD_BUNDLE=1 to override.")
}
#else
if bundleId != "com.sanebar.app" {
	fatalError("Release build must use production bundle ID (com.sanebar.app). Found: \(bundleId)")
}
#endif

let delegate = SaneBarAppDelegate()
app.delegate = delegate
app.run()
