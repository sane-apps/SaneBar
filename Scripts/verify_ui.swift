#!/usr/bin/swift

import Foundation
import AppKit

// MARK: - Helpers

func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/bash"
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    return (output, task.terminationStatus)
}

func runAppleScript(_ script: String) -> Bool {
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        scriptObject.executeAndReturnError(&error)
        if let err = error {
            print("❌ AppleScript Error: \(err)")
            return false
        }
        return true
    }
    return false
}

// MARK: - Main

print("🔨 --- [ MANUAL UI VERIFICATION ] ---")

// 1. Verify Process
print("📦 Checking if SaneBar is running...")
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.sanevideo.SaneBar")
guard let app = apps.first else {
    print("❌ SaneBar is not running. Please run './Scripts/SaneMaster.rb launch' first.")
    exit(1)
}
print("✅ SaneBar is running (PID: \(app.processIdentifier))")

// 2. Test AppleScript Commands (Simulating Menu Clicks)

print("Testing 'toggle' command...")
if runAppleScript("tell application \"SaneBar\" to toggle") {
    print("✅ Toggle command sent successfully")
} else {
    print("❌ Toggle command failed")
    exit(1)
}
Thread.sleep(forTimeInterval: 1.0)

print("Testing 'show hidden' command...")
if runAppleScript("tell application \"SaneBar\" to show hidden") {
    print("✅ Show command sent successfully")
} else {
    print("❌ Show command failed")
    exit(1)
}
Thread.sleep(forTimeInterval: 1.0)

print("Testing 'hide items' command...")
if runAppleScript("tell application \"SaneBar\" to hide items") {
    print("✅ Hide command sent successfully")
} else {
    print("❌ Hide command failed")
    exit(1)
}

print("\n🎉 UI Verification Passed: App is responsive and handling commands!")
