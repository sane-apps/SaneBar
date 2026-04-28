import AppKit
import os.log

private let menuExtraFramesLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.MenuExtraFrames")

extension AccessibilityService {
    nonisolated static func resolvedStatusItemIndex(
        midXs: [CGFloat],
        statusItemIndex: Int?,
        preferredCenterX: CGFloat?,
        hintTolerance: CGFloat = 18
    ) -> Int? {
        guard !midXs.isEmpty else { return nil }

        if let statusItemIndex, midXs.indices.contains(statusItemIndex) {
            guard let preferredCenterX else {
                return statusItemIndex
            }

            let hintedMidX = midXs[statusItemIndex]
            if abs(hintedMidX - preferredCenterX) <= hintTolerance {
                return statusItemIndex
            }
        }

        return preferredStatusItemIndex(midXs: midXs, preferredCenterX: preferredCenterX)
    }

    nonisolated static func preferredStatusItemIndex(midXs: [CGFloat], preferredCenterX: CGFloat?) -> Int? {
        guard !midXs.isEmpty else { return nil }
        guard let preferredCenterX else { return 0 }
        return midXs.enumerated().min { lhs, rhs in
            let lhsDistance = abs(lhs.element - preferredCenterX)
            let rhsDistance = abs(rhs.element - preferredCenterX)
            if lhsDistance == rhsDistance {
                return lhs.offset < rhs.offset
            }
            return lhsDistance < rhsDistance
        }?.offset
    }

    nonisolated func getMenuBarIconFrameOnScreen(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        preferredCenterX: CGFloat? = nil,
        attempts: Int = 20,
        interval: TimeInterval = 0.05
    ) -> CGRect? {
        for attempt in 1 ... attempts {
            guard let frame = getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            ) else {
                return nil
            }

            let center = CGPoint(x: frame.midX, y: frame.midY)
            let isOnScreen = Self.isAccessibilityPointOnAnyScreen(
                center,
                screenFrames: NSScreen.screens.map(\.frame)
            )

            if isOnScreen {
                Thread.sleep(forTimeInterval: 0.08)
                if let recheck = getMenuBarIconFrame(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX
                ),
                   abs(recheck.origin.x - frame.origin.x) < 2 {
                    return recheck
                }
                menuExtraFramesLogger.debug("getMenuBarIconFrameOnScreen: position unstable (attempt \(attempt))")
                continue
            }

            menuExtraFramesLogger.debug("getMenuBarIconFrameOnScreen: frame off-screen (attempt \(attempt), x=\(frame.origin.x, privacy: .public), y=\(frame.origin.y, privacy: .public))")
            Thread.sleep(forTimeInterval: interval)
        }
        return nil
    }
}
