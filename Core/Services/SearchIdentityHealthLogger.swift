import Foundation
import os.log

enum SearchIdentityHealthLogger {
    static func log(apps: [RunningApp], context: String, logger: Logger) {
        guard !apps.isEmpty else {
            logger.debug("Find Icon list empty (\(context, privacy: .public))")
            return
        }

        var countsById: [String: Int] = [:]
        countsById.reserveCapacity(apps.count)
        for app in apps {
            countsById[app.id, default: 0] += 1
        }

        let uniqueCount = countsById.count
        let duplicateIds = countsById.filter { $0.value > 1 }

        logger.debug("Find Icon \(context, privacy: .public): count=\(apps.count, privacy: .public) uniqueIds=\(uniqueCount, privacy: .public) dupIds=\(duplicateIds.count, privacy: .public)")

        if !duplicateIds.isEmpty {
            let sample = duplicateIds.prefix(10).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            logger.error("Find Icon \(context, privacy: .public): DUPLICATE ids detected: \(sample, privacy: .private)")
        }

        for app in apps.prefix(12) {
            logger.debug("Find Icon sample (\(context, privacy: .public)): id=\(app.id, privacy: .private) bundleId=\(app.bundleId, privacy: .private) menuExtraId=\(app.menuExtraIdentifier ?? "nil", privacy: .private) name=\(app.name, privacy: .private)")
        }
    }
}
