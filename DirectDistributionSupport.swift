#if os(macOS) && !APP_STORE && !SETAPP
import AppKit
import SaneUI

enum SaneAppMover {
    struct Prompt: Sendable {
        let messageText: String
        let informativeText: String
        let moveButtonTitle: String
        let cancelButtonTitle: String
    }

    private static var osascriptExecutableURL: URL {
        URL(fileURLWithPath: "/usr/bin/osascript")
    }

    @MainActor
    @discardableResult
    static func moveToApplicationsFolderIfNeeded(prompt: Prompt) -> Bool {
        if ProcessInfo.processInfo.environment["SANEAPPS_SKIP_MOVE_TO_APPLICATIONS"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--sane-skip-app-move") {
            return false
        }

        let appPath = Bundle.main.bundlePath
        let appBundleName = URL(fileURLWithPath: appPath).lastPathComponent
        guard !SaneInstallLocation.isInApplicationsDirectory(appPath) else { return false }

        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = prompt.messageText
        alert.informativeText = prompt.informativeText.replacingOccurrences(of: "{appName}", with: appBundleName)
        alert.alertStyle = .informational
        alert.addButton(withTitle: prompt.moveButtonTitle)
        alert.addButton(withTitle: prompt.cancelButtonTitle)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let destinationPath = "/Applications/\(appBundleName)"
        let fileManager = FileManager.default
        var moved = false

        do {
            if fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
            }
            try fileManager.moveItem(atPath: appPath, toPath: destinationPath)
            moved = true
        } catch {
            moved = false
        }

        if !moved {
            let escapedSourcePath = appPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedDestinationPath = destinationPath.replacingOccurrences(of: "'", with: "'\\''")
            let script = "do shell script \"rm -rf '\(escapedDestinationPath)' && mv '\(escapedSourcePath)' '\(escapedDestinationPath)'\" with administrator privileges"

            let osa = Process()
            osa.executableURL = osascriptExecutableURL
            osa.arguments = ["-e", script]
            do {
                try osa.run()
                osa.waitUntilExit()
                guard osa.terminationStatus == 0 else { return false }
            } catch {
                return false
            }
        }

        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", destinationPath]
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return false }
        } catch {
            return false
        }

        NSApp.terminate(nil)
        return true
    }
}
#endif
