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
    // Use osascript via Process (no quoting/escaping issues).
    // Automation permissions are usually granted to the hosting app (Terminal/iTerm/VS Code).
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        print("❌ Failed to run osascript: \(error)")
        return false
    }
    process.waitUntilExit()

    let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outData, encoding: .utf8) ?? ""
    let errorOutput = String(data: errData, encoding: .utf8) ?? ""
    let combined = (output + "\n" + errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)

    if process.terminationStatus == 0 {
        return true
    }

    // Common failure: macOS blocks Apple Events until user allows Automation permission.
    // Error number -1743: "Not authorized to send Apple events".
    if combined.contains("-1743") || combined.localizedCaseInsensitiveContains("Not authorized") {
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "(unknown)"
        print("\n❌ macOS blocked this test: the app running this terminal session is not allowed to control SaneBar.")
        print("\nYou appear to be running from: TERM_PROGRAM=\(termProgram)")
        print("\nFix (one-time):")
        print("1) Open System Settings → Privacy & Security → Automation")
        print("2) Find the app you are actually using (Terminal / iTerm / Visual Studio Code)")
        print("3) Turn ON permission to control ‘SaneBar’")
        print("\nAlso required for moving icons:")
        print("4) Privacy & Security → Accessibility → turn ON that same app")
        print("\nThen re-run this script.")

        _ = shell("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Automation'")
        _ = shell("open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'")
        return false
    }

    print("❌ AppleScript failed (exit \(process.terminationStatus)). Output:\n\(combined)")
    return false
}

// MARK: - Main

print("🔨 --- [ MANUAL UI VERIFICATION ] ---")

// 1. Verify Process
print("📦 Checking if SaneBar is running...")
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.sanebar.app")
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
