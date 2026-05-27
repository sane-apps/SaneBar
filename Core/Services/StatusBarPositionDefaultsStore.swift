import AppKit

enum StatusBarPositionDefaultsStore {
    static func isInvalidPosition(_ value: Any?) -> Bool {
        guard let number = numericPositionValue(value) else { return false }
        return !number.isFinite || number < 0
    }

    static func isTooSmallAlwaysHiddenPosition(_ value: Any?) -> Bool {
        guard let number = numericPositionValue(value), number.isFinite else { return false }
        return number > 0 && number < StatusBarPositionStore.minimumSafeAlwaysHiddenPosition
    }

    static func hasInvalidPositionValue(forAutosaveName autosaveName: String) -> Bool {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return isInvalidPosition(values.appValue) || isInvalidPosition(values.byHostValue)
    }

    static func hasTooSmallAlwaysHiddenPosition(forAutosaveName autosaveName: String) -> Bool {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return isTooSmallAlwaysHiddenPosition(values.appValue) || isTooSmallAlwaysHiddenPosition(values.byHostValue)
    }

    // MARK: - Preferred Position Storage

    nonisolated static func preferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    nonisolated static func byHostAutosaveName(for autosaveName: String) -> String {
        // macOS stores autosave keys in ByHost global prefs using a suffixed
        // v6 token (e.g. SaneBar_Main -> SaneBar_main_v6).
        guard let underscore = autosaveName.firstIndex(of: "_") else {
            return "\(autosaveName)_v6"
        }
        let prefix = autosaveName[..<underscore]
        var suffix = String(autosaveName[autosaveName.index(after: underscore)...])
        if let first = suffix.first {
            suffix.replaceSubrange(suffix.startIndex ... suffix.startIndex, with: String(first).lowercased())
        }
        return "\(prefix)_\(suffix)_v6"
    }

    nonisolated static func byHostPreferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(byHostAutosaveName(for: autosaveName))"
    }

    nonisolated static func shouldSeedPreferredPosition(appValue: Any?, byHostValue: Any?) -> Bool {
        if let appNumber = numericPositionValue(appValue), appNumber.isFinite {
            return false
        }
        if let byHostNumber = numericPositionValue(byHostValue), byHostNumber.isFinite {
            return false
        }
        return true
    }

    nonisolated static func numericPositionValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let stringValue = value as? String {
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    nonisolated static func preferredPositionValues(forAutosaveName autosaveName: String) -> (appValue: Any?, byHostValue: Any?) {
        let appKey = preferredPositionKey(for: autosaveName)
        let byHostKey = byHostPreferredPositionKey(for: autosaveName) as CFString
        let globalDomain = ".GlobalPreferences" as CFString
        let appValue = UserDefaults.standard.object(forKey: appKey)
        let byHostValue = CFPreferencesCopyValue(
            byHostKey,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (appValue, byHostValue)
    }

    nonisolated static func resolvedPreferredPosition(forAutosaveName autosaveName: String) -> Double? {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return numericPositionValue(values.appValue) ?? numericPositionValue(values.byHostValue)
    }

    nonisolated static func applyPreferredPosition(_ value: Double?, forAutosaveName autosaveName: String) {
        if let value {
            setPreferredPosition(value, forAutosaveName: autosaveName)
        } else {
            removePreferredPosition(forAutosaveName: autosaveName)
        }
    }

    nonisolated static func displayBackupSnapshots() -> [SaneBarLayoutSnapshot.DisplayBackup] {
        let defaults = UserDefaults.standard
        let prefix = "\(StatusBarPositionStore.positionBackupKeyPrefix)_"
        let backupKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }

        let bucketPattern = /SaneBar_Position_Backup_(\d+)_(main|separator)/
        var backups: [Int: SaneBarLayoutSnapshot.DisplayBackup] = [:]

        for key in backupKeys {
            guard let match = key.wholeMatch(of: bucketPattern),
                  let widthBucket = Int(match.1)
            else { continue }

            var backup = backups[widthBucket] ?? SaneBarLayoutSnapshot.DisplayBackup(
                widthBucket: widthBucket,
                mainPosition: nil,
                separatorPosition: nil
            )
            let position = numericPositionValue(defaults.object(forKey: key))
            if match.2 == "main" {
                backup.mainPosition = position
            } else {
                backup.separatorPosition = position
            }
            backups[widthBucket] = backup
        }

        return backups.values
            .filter { backup in
                guard let mainPosition = backup.mainPosition,
                      let separatorPosition = backup.separatorPosition,
                      StatusBarPositionStore.hasRestorableDisplayBackup(mainBackup: mainPosition, separatorBackup: separatorPosition),
                      separatorPosition > mainPosition
                else { return false }

                return StatusBarPositionStore.fitsDisplayBackupWithinScreenWidth(
                    mainBackup: mainPosition,
                    separatorBackup: separatorPosition,
                    screenWidth: Double(backup.widthBucket)
                )
            }
            .sorted { $0.widthBucket < $1.widthBucket }
    }

    nonisolated static func clearDisplayPositionBackups() {
        let defaults = UserDefaults.standard
        let prefix = "\(StatusBarPositionStore.positionBackupKeyPrefix)_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    nonisolated static func clearHistoricalAutosaveNamespaces() {
        for version in StatusBarPositionStore.baseAutosaveVersion ... StatusBarPositionStore.maxAutosaveVersion {
            for autosaveName in StatusBarPositionStore.autosaveNamesForCleanup(version: version) {
                removePreferredPosition(forAutosaveName: autosaveName)
            }
        }
        _ = removeAllAppKeys(matchingPrefixes: [
            "NSStatusItem Preferred Position SaneBar_",
            "NSStatusItem Visible SaneBar_",
            "NSStatusItem VisibleCC SaneBar_"
        ])
        _ = removeAllByHostPreferredPositionOverrides()
        _ = removeAllByHostVisibilityOverrides()
    }

    nonisolated static func nextFreshAutosaveVersion(after currentVersion: Int) -> Int {
        let normalizedVersion = max(StatusBarPositionStore.baseAutosaveVersion, currentVersion)
        if normalizedVersion >= StatusBarPositionStore.maxAutosaveVersion {
            return StatusBarPositionStore.baseAutosaveVersion
        }
        return normalizedVersion + 1
    }

    nonisolated static func removeDisplayPositionBackup(
        for width: Double,
        referenceScreen: NSScreen? = nil
    ) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: StatusBarPositionStore.displayPositionBackupKey(for: width, referenceScreen: referenceScreen, slot: "main"))
        defaults.removeObject(forKey: StatusBarPositionStore.displayPositionBackupKey(for: width, referenceScreen: referenceScreen, slot: "separator"))
        defaults.removeObject(forKey: StatusBarPositionStore.displayPositionBackupKey(for: width, slot: "main"))
        defaults.removeObject(forKey: StatusBarPositionStore.displayPositionBackupKey(for: width, slot: "separator"))
    }

    nonisolated static func setPreferredPosition(_ value: Double, forAutosaveName autosaveName: String) {
        let appKey = preferredPositionKey(for: autosaveName)
        UserDefaults.standard.set(value, forKey: appKey)
        UserDefaults.standard.synchronize()
        setByHostPreferredPosition(value, forAutosaveName: autosaveName)
    }

    nonisolated static func removePreferredPosition(forAutosaveName autosaveName: String) {
        let appKey = preferredPositionKey(for: autosaveName)
        UserDefaults.standard.removeObject(forKey: appKey)
        UserDefaults.standard.synchronize()
        removeByHostPreferredPosition(forAutosaveName: autosaveName)
    }

    nonisolated static func setByHostPreferredPosition(_ value: Double, forAutosaveName autosaveName: String) {
        let key = byHostPreferredPositionKey(for: autosaveName) as CFString
        let globalDomain = ".GlobalPreferences" as CFString
        CFPreferencesSetValue(
            key,
            value as NSNumber,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    nonisolated static func removeByHostPreferredPosition(forAutosaveName autosaveName: String) {
        let key = byHostPreferredPositionKey(for: autosaveName) as CFString
        let globalDomain = ".GlobalPreferences" as CFString
        CFPreferencesSetValue(
            key,
            nil,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    nonisolated static func removeAllAppKeys(matchingPrefixes prefixes: [String]) -> Bool {
        let defaults = UserDefaults.standard
        let keysToRemove = defaults.dictionaryRepresentation().keys.filter { key in
            prefixes.contains(where: { key.hasPrefix($0) })
        }
        guard !keysToRemove.isEmpty else { return false }

        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        return true
    }

    nonisolated static func removeAllByHostPreferredPositionOverrides() -> Bool {
        removeAllByHostKeys(matchingPrefixes: [
            "NSStatusItem Preferred Position SaneBar_"
        ])
    }

    /// Enumerate ALL ByHost keys matching SaneBar visibility prefixes and remove them.
    /// This catches every variant macOS may write — known casing, legacy lowercased,
    /// future `_vN` suffixes, spacer items, and macOS 26's `VisibleCC` keys.
    nonisolated static func removeAllByHostVisibilityOverrides() -> Bool {
        removeAllByHostKeys(matchingPrefixes: [
            "NSStatusItem Visible SaneBar_",
            "NSStatusItem VisibleCC SaneBar_"
        ])
    }

    nonisolated static func removeAllByHostKeys(matchingPrefixes prefixes: [String]) -> Bool {
        let globalDomain = ".GlobalPreferences" as CFString
        guard let allKeys = CFPreferencesCopyKeyList(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] else { return false }

        let keysToRemove = allKeys.filter { key in
            prefixes.contains(where: { key.hasPrefix($0) })
        }
        guard !keysToRemove.isEmpty else { return false }

        for key in keysToRemove {
            CFPreferencesSetValue(
                key as CFString,
                nil,
                globalDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        CFPreferencesSynchronize(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return true
    }

}
