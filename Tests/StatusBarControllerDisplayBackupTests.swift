import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerDisplayBackupTests", .serialized)
struct StatusBarControllerDisplayBackupTests {
    @Test("Ordinal seeds are not pixel-like", arguments: [0.0, 1.0, 2.0])
    func ordinalsNotPixelLike(_ value: Double) {
        #expect(!StatusBarController.isPixelLikePosition(value))
    }

    @Test("AH sentinel (10000) is not pixel-like")
    func ahSentinelNotPixelLike() {
        #expect(!StatusBarController.isPixelLikePosition(10000))
    }

    @Test("nil is not pixel-like")
    func nilNotPixelLike() {
        #expect(!StatusBarController.isPixelLikePosition(nil))
    }

    @Test("Typical pixel offsets are pixel-like", arguments: [207.0, 400.0, 800.0, 1200.0, 2400.0])
    func pixelOffsetsArePixelLike(_ value: Double) {
        #expect(StatusBarController.isPixelLikePosition(value))
    }

    @Test("Same screen width is not a significant change")
    func sameWidthNotSignificant() {
        #expect(!StatusBarController.isSignificantWidthChange(stored: 1440, current: 1440))
    }

    @Test("Small width change (<10%) is not significant")
    func smallChangeNotSignificant() {
        // 5% change: 1440 → 1512
        #expect(!StatusBarController.isSignificantWidthChange(stored: 1440, current: 1512))
    }

    @Test("Large width change (>10%) is significant")
    func largeChangeIsSignificant() {
        // 1440 → 2560 (78% change)
        #expect(StatusBarController.isSignificantWidthChange(stored: 1440, current: 2560))
    }

    @Test("Zero stored width is not a significant change")
    func zeroStoredNotSignificant() {
        #expect(!StatusBarController.isSignificantWidthChange(stored: 0, current: 1440))
    }

    @Test("Boundary: exactly 10% change is not significant")
    func boundaryTenPercent() {
        // Exactly 10%: 1000 → 1100
        #expect(!StatusBarController.isSignificantWidthChange(stored: 1000, current: 1100))
    }

    @Test("Just over 10% change is significant")
    func justOverTenPercent() {
        // 10.1%: 1000 → 1101
        #expect(StatusBarController.isSignificantWidthChange(stored: 1000, current: 1101))
    }

    @Test("Display reset triggers for significant change on single display with pixel positions")
    func shouldResetForDisplayChangeSingleDisplay() {
        let shouldReset = StatusBarController.shouldResetForDisplayChange(
            storedWidth: 1440,
            currentWidth: 2560,
            hasPixelPositions: true,
            screenCount: 1
        )
        #expect(shouldReset)
    }

    @Test("Display reset is suppressed on multi-display setups")
    func shouldNotResetForDisplayChangeMultiDisplay() {
        let shouldReset = StatusBarController.shouldResetForDisplayChange(
            storedWidth: 1440,
            currentWidth: 2560,
            hasPixelPositions: true,
            screenCount: 2
        )
        #expect(!shouldReset)
    }

    @Test("Display reset is suppressed when positions are ordinal-like")
    func shouldNotResetWithoutPixelPositions() {
        let shouldReset = StatusBarController.shouldResetForDisplayChange(
            storedWidth: 1440,
            currentWidth: 2560,
            hasPixelPositions: false,
            screenCount: 1
        )
        #expect(!shouldReset)
    }

    @Test("Display reset is suppressed when change is below threshold")
    func shouldNotResetBelowThreshold() {
        let shouldReset = StatusBarController.shouldResetForDisplayChange(
            storedWidth: 1440,
            currentWidth: 1512,
            hasPixelPositions: true,
            screenCount: 1
        )
        #expect(!shouldReset)
    }

    @Test("Display backup width buckets are stable")
    func displayBackupWidthBuckets() {
        #expect(StatusBarController.displayWidthBucket(2559.6) == 2560)
        #expect(StatusBarController.displayWidthBucket(1439.2) == 1439)
    }

    @Test("Display backup keys are width-bucketed")
    func displayBackupKeyUsesBucket() {
        let keyA = StatusBarController.displayPositionBackupKey(for: 2559.6, slot: "main")
        let keyB = StatusBarController.displayPositionBackupKey(for: 2560.2, slot: "main")
        let separatorKey = StatusBarController.displayPositionBackupKey(for: 2559.6, slot: "separator")

        #expect(keyA == keyB)
        #expect(keyA != separatorKey)
    }

    @Test("Display backup scoped keys separate same-width screens")
    func displayBackupScopedKeysSeparateSameWidthScreens() {
        let keyA = StatusBarController.displayPositionBackupKey(
            for: 1728,
            screenSignature: "d111-h1117-plain",
            slot: "main"
        )
        let keyB = StatusBarController.displayPositionBackupKey(
            for: 1728,
            screenSignature: "d222-h1117-plain",
            slot: "main"
        )

        #expect(keyA != keyB)
        #expect(
            !StatusBarController.shouldAllowLegacyDisplayBackupFallback(
                widthBucket: 1728,
                activeWidthBuckets: [1728, 1728]
            )
        )
        #expect(
            StatusBarController.shouldAllowLegacyDisplayBackupFallback(
                widthBucket: 1728,
                activeWidthBuckets: [1728, 1920]
            )
        )
    }

    @Test("Display backup restore requires pixel-like values for both separators")
    func displayBackupRestoreRequiresPixelValues() {
        #expect(StatusBarController.hasRestorableDisplayBackup(mainBackup: 420, separatorBackup: 840))
        #expect(!StatusBarController.hasRestorableDisplayBackup(mainBackup: 1, separatorBackup: 840))
        #expect(!StatusBarController.hasRestorableDisplayBackup(mainBackup: 420, separatorBackup: nil))
    }

    @Test("Launch-safe display backup rejects far-left main positions")
    func launchSafeDisplayBackupRejectsFarLeftMainPositions() {
        #expect(
            StatusBarController.isLaunchSafeDisplayBackup(
                mainBackup: 180,
                separatorBackup: 220,
                screenWidth: 1470,
                screenHasTopSafeAreaInset: true
            )
        )
        #expect(
            !StatusBarController.isLaunchSafeDisplayBackup(
                mainBackup: 216,
                separatorBackup: 249,
                screenWidth: 1512,
                screenHasTopSafeAreaInset: true
            )
        )
        #expect(
            StatusBarController.isLaunchSafeDisplayBackup(
                mainBackup: 144,
                separatorBackup: 262,
                screenWidth: 1920,
                screenHasTopSafeAreaInset: false
            )
        )
        #expect(
            !StatusBarController.isLaunchSafeDisplayBackup(
                mainBackup: 200,
                separatorBackup: 318,
                screenWidth: 1920,
                screenHasTopSafeAreaInset: false
            )
        )
        #expect(
            !StatusBarController.isLaunchSafeDisplayBackup(
                mainBackup: 180,
                separatorBackup: 160,
                screenWidth: 1512,
                screenHasTopSafeAreaInset: true
            )
        )
        #expect(
            !StatusBarController.isLaunchSafeDisplayBackup(
                mainBackup: 144,
                separatorBackup: 5897,
                screenWidth: 1920,
                screenHasTopSafeAreaInset: false
            )
        )
    }

    @Test("Reanchored preferred positions preserve lane width while moving toward Control Center")
    func reanchoredPreferredPositionsPreserveLaneWidth() {
        let reanchored = StatusBarController.reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: 456,
            separatorPosition: 574,
            screenWidth: 1920,
            screenHasTopSafeAreaInset: false
        )

        #expect(reanchored != nil)
        #expect(
            reanchored?.main == StatusBarController.launchSafePreferredMainPositionLimit(
                for: 1920,
                screenHasTopSafeAreaInset: false
            )
        )
        #expect((reanchored?.separator ?? 0) - (reanchored?.main ?? 0) == 118)

        let clamped = StatusBarController.reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: 456,
            separatorPosition: 5897,
            screenWidth: 1920,
            screenHasTopSafeAreaInset: false
        )

        #expect(clamped != nil)
        #expect((clamped?.separator ?? 0) <= 1896)
    }

    @Test("Layout snapshot captures current preferred positions and display backups")
    func captureLayoutSnapshotReadsPersistedState() {
        let originalSnapshot = StatusBarController.captureLayoutSnapshot()
        defer {
            StatusBarController.applyLayoutSnapshot(originalSnapshot)
        }

        StatusBarController.applyLayoutSnapshot(
            SaneBarLayoutSnapshot(
                mainPosition: 420.0,
                separatorPosition: 390.0,
                alwaysHiddenSeparatorPosition: nil,
                spacerPositions: [0: 360.0],
                calibratedScreenWidth: 1512.0,
                displayBackups: [
                    .init(widthBucket: 1512, mainPosition: 180.0, separatorPosition: 300.0),
                ]
            )
        )

        let snapshot = StatusBarController.captureLayoutSnapshot()

        #expect(snapshot.calibratedScreenWidth == 1512.0)
        #expect(snapshot.mainPosition == 420.0)
        #expect(snapshot.separatorPosition == 390.0)
        #expect(snapshot.spacerPositions[0] == 360.0)
        #expect(snapshot.displayBackups.contains {
            $0.widthBucket == 1512 && $0.mainPosition == 180.0 && $0.separatorPosition == 300.0
        })
    }

    @Test("Applying a layout snapshot restores positions and replaces display backups")
    func applyLayoutSnapshotWritesPersistedState() {
        let defaults = UserDefaults.standard
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let spacerKey = "NSStatusItem Preferred Position \(StatusBarController.spacerAutosaveName(index: 0))"
        let staleBackupMainKey = StatusBarController.displayPositionBackupKey(for: 1440, slot: "main")
        let staleBackupSeparatorKey = StatusBarController.displayPositionBackupKey(for: 1440, slot: "separator")
        let freshBackupMainKey = StatusBarController.displayPositionBackupKey(for: 1512, slot: "main")
        let freshBackupSeparatorKey = StatusBarController.displayPositionBackupKey(for: 1512, slot: "separator")
        let keys = [screenWidthKey, mainKey, separatorKey, spacerKey, staleBackupMainKey, staleBackupSeparatorKey, freshBackupMainKey, freshBackupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(111.0, forKey: staleBackupMainKey)
        defaults.set(112.0, forKey: staleBackupSeparatorKey)

        StatusBarController.applyLayoutSnapshot(
            SaneBarLayoutSnapshot(
                mainPosition: 420.0,
                separatorPosition: 390.0,
                alwaysHiddenSeparatorPosition: 10000.0,
                spacerPositions: [0: 360.0],
                calibratedScreenWidth: 1512.0,
                displayBackups: [
                    .init(widthBucket: 1512, mainPosition: 430.0, separatorPosition: 480.0),
                ]
            )
        )

        #expect((defaults.object(forKey: screenWidthKey) as? NSNumber)?.doubleValue == 1512.0)
        #expect((defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue == 420.0)
        #expect((defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue == 390.0)
        #expect((defaults.object(forKey: spacerKey) as? NSNumber)?.doubleValue == 360.0)
        #expect(defaults.object(forKey: staleBackupMainKey) == nil)
        #expect(defaults.object(forKey: staleBackupSeparatorKey) == nil)
        #expect((defaults.object(forKey: freshBackupMainKey) as? NSNumber)?.doubleValue == 430.0)
        #expect((defaults.object(forKey: freshBackupSeparatorKey) as? NSNumber)?.doubleValue == 480.0)
    }

    @Test("Applying a layout snapshot drops impossible display backups")
    func applyLayoutSnapshotDropsImpossibleDisplayBackups() {
        let defaults = UserDefaults.standard
        let invalidBackupMainKey = StatusBarController.displayPositionBackupKey(for: 1920, slot: "main")
        let invalidBackupSeparatorKey = StatusBarController.displayPositionBackupKey(for: 1920, slot: "separator")
        let keys = [invalidBackupMainKey, invalidBackupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        StatusBarController.applyLayoutSnapshot(
            SaneBarLayoutSnapshot(
                mainPosition: 420.0,
                separatorPosition: 390.0,
                alwaysHiddenSeparatorPosition: 10000.0,
                spacerPositions: [:],
                calibratedScreenWidth: 1920.0,
                displayBackups: [
                    .init(widthBucket: 1920, mainPosition: 144.0, separatorPosition: 5897.0),
                ]
            )
        )

        #expect(defaults.object(forKey: invalidBackupMainKey) == nil)
        #expect(defaults.object(forKey: invalidBackupSeparatorKey) == nil)
    }

}
