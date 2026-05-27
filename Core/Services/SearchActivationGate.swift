import Foundation
import os.log

final class SearchActivationGate {
    private let debounceInterval: TimeInterval
    private let logger: Logger
    private var inFlightAppID: String?
    private var lastActivatedAppID: String?
    private var lastActivationAt: Date = .distantPast

    init(
        debounceInterval: TimeInterval,
        logger: Logger = Logger(subsystem: "com.sanebar.app", category: "SearchActivationGate")
    ) {
        self.debounceInterval = debounceInterval
        self.logger = logger
    }

    func begin(for appUniqueID: String, nameForLog: String? = nil, now: Date = Date()) -> Bool {
        if let inFlightAppID {
            if let nameForLog {
                logger.info("Skipping activation for \(nameForLog, privacy: .private): \(inFlightAppID, privacy: .private) is already in progress")
            } else {
                logger.info("Skipping activation: \(inFlightAppID, privacy: .private) is already in progress")
            }
            return false
        }

        if lastActivatedAppID == appUniqueID,
           now.timeIntervalSince(lastActivationAt) < debounceInterval {
            if let nameForLog {
                logger.info("Debounced duplicate activation for \(nameForLog, privacy: .private)")
            } else {
                logger.info("Debounced duplicate activation for \(appUniqueID, privacy: .private)")
            }
            return false
        }

        inFlightAppID = appUniqueID
        return true
    }

    func finish(for appUniqueID: String, at finishedAt: Date = Date()) {
        inFlightAppID = nil
        lastActivatedAppID = appUniqueID
        lastActivationAt = finishedAt
    }
}
