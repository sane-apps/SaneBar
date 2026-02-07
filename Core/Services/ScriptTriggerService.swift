import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "ScriptTriggerService")

// MARK: - ScriptTriggerService

/// Service that runs a user-defined shell script on a timer to control menu bar visibility.
/// Exit code 0 = show hidden items, non-zero = hide.
@MainActor
final class ScriptTriggerService {
    // MARK: - Dependencies

    private weak var menuBarManager: MenuBarManager?
    private var timer: Timer?

    // MARK: - Configuration

    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard timer == nil else { return } // Already running
        guard let manager = menuBarManager else { return }

        let interval = max(1.0, manager.settings.scriptTriggerInterval)
        logger.info("Starting script trigger (interval: \(interval)s)")

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runScript()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        logger.info("Stopped script trigger")
    }

    /// Restart with updated interval
    func restartIfRunning() {
        guard timer != nil else { return }
        stopMonitoring()
        startMonitoring()
    }

    // MARK: - Script Execution

    private func runScript() {
        guard let manager = menuBarManager else { return }
        let path = manager.settings.scriptTriggerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        // Verify script exists and is executable
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            logger.warning("Script trigger: file not found at \(path, privacy: .public)")
            return
        }
        guard fm.isExecutableFile(atPath: path) else {
            logger.warning("Script trigger: file not executable at \(path, privacy: .public)")
            return
        }

        // Run on background thread — only capture the path string, not the manager
        let scriptPath = path
        Task.detached(priority: .utility) { [weak self] in
            let exitCode = Self.executeScript(at: scriptPath)

            await MainActor.run { [weak self] in
                self?.handleScriptResult(exitCode: exitCode)
            }
        }
    }

    /// Sentinel value: script was killed by timeout (not a real exit code).
    private nonisolated static let timeoutExitCode: Int32 = -99

    /// Execute script synchronously on a background thread. Returns exit code.
    private nonisolated static func executeScript(at path: String) -> Int32 {
        let process = Process()
        // Execute the file directly instead of via /bin/sh -c (avoids shell injection)
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []

        // Timeout: kill if it takes too long
        let timedOut = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        timedOut.initialize(to: false)
        let timeoutItem = DispatchWorkItem { [weak process] in
            if let process, process.isRunning {
                logger.warning("Script trigger: timed out after 5s, killing")
                timedOut.pointee = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0, execute: timeoutItem)

        do {
            try process.run()
            process.waitUntilExit()
            timeoutItem.cancel()
            let wasTimeout = timedOut.pointee
            timedOut.deallocate()
            return wasTimeout ? timeoutExitCode : process.terminationStatus
        } catch {
            timeoutItem.cancel()
            timedOut.deallocate()
            logger.error("Script trigger: failed to run: \(error.localizedDescription, privacy: .public)")
            return -1
        }
    }

    /// Handle script result on the main actor
    private func handleScriptResult(exitCode: Int32) {
        guard let manager = menuBarManager else { return }

        // Timeout — ignore entirely (don't flip state based on a killed script)
        if exitCode == Self.timeoutExitCode {
            logger.warning("Script trigger: ignoring result (script was killed by timeout)")
            return
        }

        if exitCode == 0 {
            // Respect Touch ID lock — script can't bypass auth
            if manager.settings.requireAuthToShowHiddenIcons {
                logger.info("Script trigger: exit 0 but auth required, skipping show")
                return
            }
            if manager.hidingService.state == .hidden {
                logger.info("Script trigger: exit 0, showing hidden items")
                manager.showHiddenItems()
            }
        } else {
            if manager.hidingService.state != .hidden {
                logger.info("Script trigger: exit \(exitCode), hiding items")
                manager.hideHiddenItems()
            }
        }
    }
}
