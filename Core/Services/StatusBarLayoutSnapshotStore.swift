import Foundation

enum StatusBarLayoutSnapshotStore {
    nonisolated static func captureLayoutSnapshot() -> SaneBarLayoutSnapshot {
        let defaults = UserDefaults.standard
        var spacerPositions: [Int: Double] = [:]
        for index in 0 ..< StatusBarController.maxSpacerCount {
            if let position = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.spacerAutosaveName(index: index)) {
                spacerPositions[index] = position
            }
        }

        return SaneBarLayoutSnapshot(
            mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName),
            separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName),
            alwaysHiddenSeparatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName),
            spacerPositions: spacerPositions,
            calibratedScreenWidth: StatusBarPositionDefaultsStore.numericPositionValue(defaults.object(forKey: StatusBarPositionStore.screenWidthKey)),
            displayBackups: StatusBarPositionDefaultsStore.displayBackupSnapshots()
        )
    }

    nonisolated static func applyLayoutSnapshot(_ snapshot: SaneBarLayoutSnapshot) {
        StatusBarPositionDefaultsStore.applyPreferredPosition(snapshot.mainPosition, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.applyPreferredPosition(snapshot.separatorPosition, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        StatusBarPositionDefaultsStore.applyPreferredPosition(snapshot.alwaysHiddenSeparatorPosition, forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName)

        for index in 0 ..< StatusBarController.maxSpacerCount {
            StatusBarPositionDefaultsStore.applyPreferredPosition(snapshot.spacerPositions[index], forAutosaveName: StatusBarPositionStore.spacerAutosaveName(index: index))
        }

        let defaults = UserDefaults.standard
        if let calibratedScreenWidth = snapshot.calibratedScreenWidth {
            defaults.set(calibratedScreenWidth, forKey: StatusBarPositionStore.screenWidthKey)
        } else {
            defaults.removeObject(forKey: StatusBarPositionStore.screenWidthKey)
        }

        StatusBarPositionDefaultsStore.clearDisplayPositionBackups()
        for backup in snapshot.displayBackups {
            guard let mainPosition = backup.mainPosition,
                  let separatorPosition = backup.separatorPosition,
                  StatusBarPositionStore.hasRestorableDisplayBackup(mainBackup: mainPosition, separatorBackup: separatorPosition),
                  separatorPosition > mainPosition,
                  StatusBarPositionStore.fitsDisplayBackupWithinScreenWidth(
                      mainBackup: mainPosition,
                      separatorBackup: separatorPosition,
                      screenWidth: Double(backup.widthBucket)
                  )
            else { continue }

            defaults.set(mainPosition, forKey: StatusBarPositionStore.displayPositionBackupKey(for: backup.widthBucket, slot: "main"))
            defaults.set(separatorPosition, forKey: StatusBarPositionStore.displayPositionBackupKey(for: backup.widthBucket, slot: "separator"))
        }
    }

}
