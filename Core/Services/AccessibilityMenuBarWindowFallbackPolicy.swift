import AppKit

// MARK: - WindowServer Menu Bar Fallbacks

enum AccessibilityMenuBarWindowFallbackPolicy {
    typealias MenuBarItemPosition = AccessibilityService.MenuBarItemPosition
    typealias WindowBackedStatusItem = AccessibilityMenuBarScanningService.WindowBackedStatusItem

    private nonisolated static let knownThirdPartyTopBarFallbackBundles: [String] = [
        "com.obdev.LittleSnitchUIAgent",
        "at.obdev.littlesnitch",
        "at.obdev.littlesnitch.agent",
        "at.obdev.littlesnitch.daemon",
        "at.obdev.littlesnitch.networkmonitor"
    ]

    internal nonisolated static func windowBackedMenuBarItems(candidatePIDs: Set<pid_t>) -> [WindowBackedStatusItem] {
        guard !candidatePIDs.isEmpty,
              let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return windowBackedMenuBarItems(fromWindowInfos: infos, candidatePIDs: candidatePIDs)
    }

    internal nonisolated static func topBarHostPIDs(candidatePIDs: Set<pid_t>) -> Set<pid_t> {
        guard !candidatePIDs.isEmpty,
              let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        let minimumWidth = (NSScreen.screens.map(\.frame.width).max() ?? 0) * 0.7
        return topBarHostPIDs(
            fromWindowInfos: infos,
            candidatePIDs: candidatePIDs,
            minimumWidth: minimumWidth
        )
    }

    internal nonisolated static func mergeSystemWideMenuBarItem(
        _ item: MenuBarItemPosition,
        into appPositions: inout [String: MenuBarItemPosition]
    ) {
        let key = item.app.uniqueId
        if appPositions[key] != nil {
            return
        }

        if item.app.menuExtraIdentifier == nil {
            // Bundle-level fallback items are discovery-only. If the same bundle
            // already has a more precise AX or WindowServer match, prefer that.
            if appPositions.values.contains(where: { $0.app.bundleId == item.app.bundleId }) {
                return
            }

            appPositions[key] = item
            return
        }

        // Precise menu-extra identities should replace coarse owner-only fallbacks
        // for the same bundle so we do not render duplicate entries.
        let coarseKeys = appPositions.compactMap { candidate -> String? in
            guard candidate.value.app.bundleId == item.app.bundleId,
                  candidate.value.app.menuExtraIdentifier == nil else {
                return nil
            }
            return candidate.key
        }
        for coarseKey in coarseKeys {
            appPositions.removeValue(forKey: coarseKey)
        }

        appPositions[key] = item
    }

    internal nonisolated static func systemWideFallbackCandidatePIDs(
        axResolvedPIDs: Set<pid_t>,
        knownNoExtrasPIDs: Set<pid_t>,
        windowBackedPIDs: Set<pid_t>,
        topBarHostPIDs: Set<pid_t>
    ) -> Set<pid_t> {
        knownNoExtrasPIDs
            .union(windowBackedPIDs)
            .union(topBarHostPIDs)
            .subtracting(axResolvedPIDs)
    }

    internal nonisolated static func windowBackedMenuBarItems(
        fromWindowInfos infos: [[String: Any]],
        candidatePIDs: Set<pid_t>
    ) -> [WindowBackedStatusItem] {
        guard !candidatePIDs.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }

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

        var framesByPID: [pid_t: [CGRect]] = [:]

        for info in infos {
            guard !Task.isCancelled else { return [] }
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard candidatePIDs.contains(ownerPID) else { continue }

            guard let layerValue = info[kCGWindowLayer as String] as? NSNumber else { continue }
            let layer = layerValue.intValue
            guard layer == 24 || layer == 25 else { continue }

            if let alphaValue = info[kCGWindowAlpha as String] as? NSNumber,
               alphaValue.doubleValue <= 0 {
                continue
            }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }

            guard width > 0, height > 0 else { continue }
            guard height <= 60 else { continue }
            guard width <= 500 else { continue }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            framesByPID[ownerPID, default: []].append(frame)
        }

        return framesByPID
            .sorted { $0.key < $1.key }
            .flatMap { pid, frames in
                let orderedFrames = frames.sorted {
                    if $0.midX == $1.midX {
                        return $0.width < $1.width
                    }
                    return $0.midX < $1.midX
                }
                let shouldAssignFallbackIndex = orderedFrames.count > 1
                return orderedFrames.enumerated().map { index, frame in
                    WindowBackedStatusItem(
                        pid: pid,
                        frame: frame,
                        fallbackIndex: shouldAssignFallbackIndex ? index : nil
                    )
                }
            }
    }

    internal nonisolated static func representativeWindowBackedFramesByPID(
        _ items: [WindowBackedStatusItem]
    ) -> [pid_t: CGRect] {
        items.reduce(into: [pid_t: CGRect]()) { partial, item in
            if let existing = partial[item.pid] {
                if item.frame.midX > existing.midX {
                    partial[item.pid] = item.frame
                }
            } else {
                partial[item.pid] = item.frame
            }
        }
    }

    internal nonisolated static func topBarHostPIDs(
        fromWindowInfos infos: [[String: Any]],
        candidatePIDs: Set<pid_t>,
        minimumWidth: CGFloat
    ) -> Set<pid_t> {
        guard !candidatePIDs.isEmpty else { return [] }
        guard !Task.isCancelled else { return [] }

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

        var matches = Set<pid_t>()

        for info in infos {
            guard !Task.isCancelled else { return [] }
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard candidatePIDs.contains(ownerPID) else { continue }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }

            guard y <= 1 else { continue }
            guard height >= 20, height <= 40 else { continue }
            guard width >= minimumWidth else { continue }
            matches.insert(ownerPID)
        }

        return matches
    }

    internal nonisolated static func scanMenuBarOwnerPIDs(candidatePIDs: [pid_t]) async -> [pid_t] {
        guard !Task.isCancelled else { return [] }

        let axPIDs = await withTaskGroup(of: pid_t?.self) { group in
            for pid in candidatePIDs {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let appElement = AXUIElementCreateApplication(pid)
                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
                    if result == .success {
                        return pid
                    }
                    return nil
                }
            }

            var pids: [pid_t] = []
            pids.reserveCapacity(candidatePIDs.count)
            for await pid in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let pid = pid {
                    pids.append(pid)
                }
            }
            return pids
        }
        guard !Task.isCancelled else { return [] }

        let windowBackedPIDs = Set(windowBackedMenuBarItems(candidatePIDs: Set(candidatePIDs)).map(\.pid))
        guard !Task.isCancelled else { return [] }
        let topBarPIDs = Set(
            topBarHostPIDs(candidatePIDs: Set(candidatePIDs)).compactMap { pid -> pid_t? in
                guard !Task.isCancelled else { return nil }
                guard let app = NSRunningApplication(processIdentifier: pid),
                      let bundleID = AccessibilityMenuBarScanningService.resolvedBundleIdentifier(for: app) else {
                    return nil
                }

                let fallbackItems = AccessibilityMenuExtraService.enumerateMenuExtraItems(
                    pid: pid,
                    ownerBundleId: bundleID,
                    allowThirdPartyMenuBarFallback: true
                )
                guard shouldIncludeThirdPartyTopBarOwner(
                    bundleID: bundleID,
                    fallbackItemsCount: fallbackItems.count
                ) else {
                    return nil
                }
                return pid
            }
        )
        return Array(Set(axPIDs).union(windowBackedPIDs).union(topBarPIDs))
    }

    internal nonisolated static func shouldAllowThirdPartyTopBarFallback(bundleID: String) -> Bool {
        knownThirdPartyTopBarFallbackBundles.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    internal nonisolated static func shouldIncludeThirdPartyTopBarOwner(
        bundleID: String,
        fallbackItemsCount: Int
    ) -> Bool {
        fallbackItemsCount > 0 || shouldAllowThirdPartyTopBarFallback(bundleID: bundleID)
    }

    internal nonisolated static func scanMenuBarAppMinXPositions(candidatePIDs: [pid_t]) async -> [(pid: pid_t, x: CGFloat)] {
        guard !Task.isCancelled else { return [] }

        return await withTaskGroup(of: (pid: pid_t, x: CGFloat)?.self) { group in
            for pid in candidatePIDs {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let appElement = AXUIElementCreateApplication(pid)

                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
                    guard result == .success, let bar = extrasBar else { return nil }
                    guard let barElement = safeAXUIElement(bar) else { return nil }

                    let childResult = AccessibilityBoundedAXChildFetch.children(
                        of: barElement,
                        maxCount: AccessibilityMenuExtraService.maxCollectedMenuExtraItems
                    )
                    guard !childResult.truncated else { return nil }
                    let items = childResult.children
                    guard !items.isEmpty else { return nil }

                    var minX: CGFloat?
                    for item in items {
                        guard !Task.isCancelled else { return nil }
                        var positionValue: CFTypeRef?
                        let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)

                        var xPos: CGFloat = 0

                        if posResult == .success, let posValue = positionValue,
                           let axPosValue = safeAXValue(posValue) {
                            var point = CGPoint.zero
                            if AXValueGetValue(axPosValue, .cgPoint, &point) {
                                xPos = point.x
                            }
                        }

                        if let existing = minX {
                            if xPos < existing {
                                minX = xPos
                            }
                        } else {
                            minX = xPos
                        }
                    }

                    if let minX {
                        return (pid: pid, x: minX)
                    }
                    return nil
                }
            }

            var results: [(pid: pid_t, x: CGFloat)] = []
            results.reserveCapacity(candidatePIDs.count)
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
    }}
