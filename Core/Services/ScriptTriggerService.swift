import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "ScriptTriggerService")


@MainActor
final class ScriptTriggerService {

    private weak var menuBarManager: MenuBarManager?
    private var timer: Timer?


    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }


    func startMonitoring() {
        guard timer == nil else { return }
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

    func restartIfRunning() {
        guard timer != nil else { return }
        stopMonitoring()
        startMonitoring()
    }


    private func runScript() {
        guard let manager = menuBarManager else { return }
        let path = manager.settings.scriptTriggerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            logger.warning("Script trigger: file not found at \(path, privacy: .public)")
            return
        }
        guard fm.isExecutableFile(atPath: path) else {
            logger.warning("Script trigger: file not executable at \(path, privacy: .public)")
            return
        }

        let scriptPath = path
        Task.detached(priority: .utility) { [weak self] in
            let exitCode = Self.executeScript(at: scriptPath)

            await MainActor.run { [weak self] in
                self?.handleScriptResult(exitCode: exitCode)
            }
        }
    }

    private nonisolated static let timeoutExitCode: Int32 = -99

    private nonisolated static func executeScript(at path: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = []

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

    private func handleScriptResult(exitCode: Int32) {
        guard let manager = menuBarManager else { return }

        if exitCode == Self.timeoutExitCode {
            logger.warning("Script trigger: ignoring result (script was killed by timeout)")
            return
        }

        if exitCode == 0 {
            if manager.settings.requireAuthToShowHiddenIcons {
                logger.info("Script trigger: exit 0 but auth required, skipping show")
                return
            }
            if manager.hidingService.state == .hidden {
                logger.info("Script trigger: exit 0, showing hidden items")
                manager.visibilityWorkflow.showHiddenItems()
            }
        } else {
            if manager.hidingService.state != .hidden {
                logger.info("Script trigger: exit \(exitCode), hiding items")
                manager.visibilityWorkflow.hideHiddenItems()
            }
        }
    }
}
