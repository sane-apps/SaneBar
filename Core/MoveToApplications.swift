#if os(macOS)
    import AppKit

    /// Shared move-to-Applications prompt for all SaneApps.
    ///
    /// Usage: Call `SaneAppMover.moveToApplicationsFolderIfNeeded()` in
    /// `applicationDidFinishLaunching` (wrapped in `#if !DEBUG`).
    ///
    /// Returns `true` if the app is being moved (caller should return early).
    ///
    /// How it works:
    /// 1. Checks if the app is already in /Applications — exits early if so
    /// 2. Shows a native alert asking the user to move
    /// 3. Tries a direct FileManager move first (works if user has write access)
    /// 4. Falls back to AppleScript `with administrator privileges` (shows password prompt)
    /// 5. Relaunches from /Applications on success
    enum SaneAppMover {
        @discardableResult
        static func moveToApplicationsFolderIfNeeded() -> Bool {
            let appPath = Bundle.main.bundlePath
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? "This app"

            guard !appPath.hasPrefix("/Applications") else { return false }

            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "Move to Applications?"
            alert.informativeText = "\(appName) works best from your Applications folder. Move it there now? You may be asked for your password."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Not Now")

            guard alert.runModal() == .alertFirstButtonReturn else { return false }

            let destPath = "/Applications/\(appName).app"
            let fm = FileManager.default

            // Try direct move first (no admin needed if user owns /Applications)
            var moved = false
            do {
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(atPath: destPath)
                }
                try fm.moveItem(atPath: appPath, toPath: destPath)
                moved = true
            } catch {
                // Direct move failed — need admin privileges
            }

            if !moved {
                let escapedAppPath = appPath.replacingOccurrences(of: "'", with: "'\\''")
                let escapedDestPath = destPath.replacingOccurrences(of: "'", with: "'\\''")
                let script = "do shell script \"rm -rf '\(escapedDestPath)' && mv '\(escapedAppPath)' '\(escapedDestPath)'\" with administrator privileges"

                let osa = Process()
                osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                osa.arguments = ["-e", script]
                do {
                    try osa.run()
                    osa.waitUntilExit()
                    guard osa.terminationStatus == 0 else {
                        // User cancelled the admin prompt
                        return false
                    }
                } catch {
                    return false
                }
            }

            // Relaunch from /Applications
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = [destPath]
                try task.run()
            } catch {}
            NSApp.terminate(nil)
            return true
        }
    }
#endif
