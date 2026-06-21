import AppKit

enum MenuBarAppearanceSuppressionPolicy {
    enum OverlaySuppressionReason: Equatable {
        case fullscreenContentWindow
        case systemSpaceControl
        case thinTopHost
    }

    nonisolated static func shouldSuppressOverlay(
        frontmostPID: pid_t?,
        frontmostBundleID: String?,
        frontmostIsAccessoryApp: Bool = false,
        frontmostHasFullscreenAXWindow: Bool = false,
        targetScreenFrame: CGRect?,
        windowInfos: [[String: Any]],
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        overlaySuppressionReason(
            frontmostPID: frontmostPID,
            frontmostBundleID: frontmostBundleID,
            frontmostIsAccessoryApp: frontmostIsAccessoryApp,
            frontmostHasFullscreenAXWindow: frontmostHasFullscreenAXWindow,
            targetScreenFrame: targetScreenFrame,
            windowInfos: windowInfos,
            selfPID: selfPID
        ) != nil
    }

    nonisolated static func overlaySuppressionReason(
        frontmostPID: pid_t?,
        frontmostBundleID: String?,
        frontmostIsAccessoryApp: Bool = false,
        frontmostHasFullscreenAXWindow: Bool = false,
        targetScreenFrame: CGRect?,
        windowInfos: [[String: Any]],
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> OverlaySuppressionReason? {
        guard let frontmostPID,
              let bundleID = frontmostBundleID else {
            return nil
        }

        guard frontmostPID != selfPID else { return nil }
        if frontmostHasFullscreenAXWindow && !frontmostIsAccessoryApp {
            return .fullscreenContentWindow
        }
        guard let targetScreenFrame else { return nil }

        func number(_ value: Any?) -> CGFloat? {
            switch value {
            case let number as NSNumber:
                return CGFloat(truncating: number)
            case let value as CGFloat:
                return value
            case let value as Double:
                return value
            case let value as Int:
                return CGFloat(value)
            default:
                return nil
            }
        }

        func bool(_ value: Any?) -> Bool? {
            switch value {
            case let number as NSNumber:
                return number.boolValue
            case let value as Bool:
                return value
            default:
                return nil
            }
        }

        let targetFrame = targetScreenFrame.standardized
        let minimumCoveredWidth = targetFrame.width * 0.97
        let maximumHorizontalDrift: CGFloat = 8
        let maximumTopDrift: CGFloat = 8
        let maximumFullscreenMenuBarOffset: CGFloat = 48
        let suppressThinTopHost = !bundleID.hasPrefix("com.apple.")

        func isSystemSpaceControlWindow(_ info: [String: Any]) -> Bool {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { return false }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            let ownerName = info[kCGWindowOwnerName as String] as? String
            let dockIsFrontmost = bundleID == "com.apple.dock" && ownerPID == frontmostPID
            let isDockWindow = dockIsFrontmost || ownerName == "Dock"
            guard isDockWindow else { return false }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                return false
            }

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            let coveredRect = rect.intersection(targetFrame)
            let isOnscreen = bool(info[kCGWindowIsOnscreen as String]) ?? true
            let alpha = number(info[kCGWindowAlpha as String]) ?? 1
            let layer = number(info[kCGWindowLayer as String]) ?? 0
            guard isOnscreen, alpha > 0 else { return false }
            // Normal desktop has a Dock-owned full-screen layer-20 window; Mission Control adds layer 18.
            guard dockIsFrontmost || layer < 20 else { return false }
            guard abs(rect.minX - targetFrame.minX) <= maximumHorizontalDrift else { return false }
            guard abs(rect.minY - targetFrame.minY) <= maximumTopDrift else { return false }
            guard coveredRect.width >= minimumCoveredWidth else { return false }
            return coveredRect.height >= targetFrame.height * 0.6
        }

        func isCompanionContentWindow(_ info: [String: Any], excluding thinRect: CGRect) -> Bool {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { return false }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard ownerPID == frontmostPID else { return false }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                return false
            }

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            guard rect != thinRect else { return false }
            let isOnscreen = bool(info[kCGWindowIsOnscreen as String]) ?? true
            let alpha = number(info[kCGWindowAlpha as String]) ?? 1
            let layer = number(info[kCGWindowLayer as String]) ?? 0
            guard isOnscreen else { return false }
            guard alpha > 0 else { return false }
            guard layer == 0 else { return false }

            let coveredRect = rect.intersection(targetFrame)
            guard coveredRect.width >= targetFrame.width * 0.25 else { return false }
            guard coveredRect.height >= 80 else { return false }
            guard rect.minY >= targetFrame.minY + 20 || rect.height >= targetFrame.height * 0.5 else { return false }
            return true
        }

        func isFullscreenTransitionTopHost(_ info: [String: Any]) -> Bool {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { return false }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard ownerPID == frontmostPID else { return false }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                return false
            }

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            let coveredRect = rect.intersection(targetFrame)
            let isOnscreen = bool(info[kCGWindowIsOnscreen as String]) ?? true
            let alpha = number(info[kCGWindowAlpha as String]) ?? 1
            let layer = number(info[kCGWindowLayer as String]) ?? 0
            guard isOnscreen else { return false }
            guard alpha <= 0.01 else { return false }
            guard layer > 0 else { return false }
            guard abs(rect.minX - targetFrame.minX) <= maximumHorizontalDrift else { return false }
            guard abs(rect.minY - targetFrame.minY) <= maximumTopDrift else { return false }
            guard coveredRect.width >= minimumCoveredWidth else { return false }
            return height >= 40 && height <= 120
        }

        let hasFullscreenTransitionTopHost = windowInfos.contains(where: isFullscreenTransitionTopHost)
        if windowInfos.contains(where: isSystemSpaceControlWindow) {
            return .systemSpaceControl
        }

        for info in windowInfos {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard ownerPID == frontmostPID else { continue }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            let coveredRect = rect.intersection(targetFrame)
            let isOnscreen = bool(info[kCGWindowIsOnscreen as String]) ?? true
            let alpha = number(info[kCGWindowAlpha as String]) ?? 1
            let layer = number(info[kCGWindowLayer as String]) ?? 0
            guard isOnscreen, alpha > 0 else { continue }

            guard layer == 0 else { continue }
            guard abs(rect.minX - targetFrame.minX) <= maximumHorizontalDrift else { continue }
            let isTopAligned = abs(rect.minY - targetFrame.minY) <= maximumTopDrift
            let isMenuBarOffset = hasFullscreenTransitionTopHost &&
                rect.minY >= targetFrame.minY &&
                rect.minY <= targetFrame.minY + maximumFullscreenMenuBarOffset
            guard isTopAligned || isMenuBarOffset else { continue }
            let isTopAlignedFullscreen = isTopAligned &&
                coveredRect.height >= targetFrame.height * 0.9
            let isMenuBarOffsetFullscreen = isMenuBarOffset &&
                coveredRect.height >= targetFrame.height * 0.95
            if !frontmostIsAccessoryApp,
               coveredRect.width >= minimumCoveredWidth,
               isTopAlignedFullscreen || isMenuBarOffsetFullscreen {
                return .fullscreenContentWindow
            }
            guard suppressThinTopHost, isTopAligned else { continue }
            guard height >= 20, height <= 26 else { continue }
            guard coveredRect.width >= minimumCoveredWidth else { continue }
            guard !windowInfos.contains(where: { isCompanionContentWindow($0, excluding: rect) }) else { continue }
            return .thinTopHost
        }

        return nil
    }

    nonisolated static func applicationHasFullscreenAXWindow(processIdentifier: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows) == .success,
              let windows = rawWindows as? [AXUIElement] else {
            return false
        }

        for window in windows {
            var rawFullscreen: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &rawFullscreen) == .success else {
                continue
            }
            if let isFullscreen = rawFullscreen as? Bool, isFullscreen {
                return true
            }
        }

        return false
    }
}
