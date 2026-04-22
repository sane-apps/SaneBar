import AppKit
import ApplicationServices

extension AccessibilityService {
    internal nonisolated static func recommendedSystemWideSampleStep(
        candidateCount: Int,
        totalScreenWidth: CGFloat
    ) -> CGFloat {
        _ = candidateCount // reserved for future fallback-owner-specific tuning
        if totalScreenWidth >= 3200 {
            return 8
        }
        return 6
    }

    internal struct SystemWideHitSample: Equatable, Sendable {
        let pid: pid_t
        let bundleID: String
        let appName: String
        let lineY: CGFloat
        let x: CGFloat
        let role: String
        let subrole: String
        let rawIdentifier: String?
        let rawTitle: String?
        let rawDescription: String?
    }

    internal struct SystemWideMenuBarSegment: Equatable, Sendable {
        let pid: pid_t
        let bundleID: String
        let appName: String
        let lineY: CGFloat
        let startX: CGFloat
        let endX: CGFloat
        let rawIdentifier: String?
        let rawTitle: String?
        let rawDescription: String?
    }

    internal nonisolated static func systemWideVisibleMenuBarItems(
        candidatePIDs: Set<pid_t>,
        sampleStep: CGFloat = 4,
        anchorY: CGFloat = 15
    ) -> [MenuBarItemPosition] {
        guard !candidatePIDs.isEmpty else { return [] }

        func axString(_ value: CFTypeRef?) -> String? {
            if let string = value as? String { return string }
            if let attributed = value as? NSAttributedString { return attributed.string }
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        let step = Int(max(1, sampleStep.rounded(.toNearestOrAwayFromZero)))
        var samples: [SystemWideHitSample] = []
        samples.reserveCapacity(Int((NSScreen.screens.reduce(CGFloat(0)) { $0 + $1.frame.width } / max(1, sampleStep)).rounded(.up)))

        for screen in NSScreen.screens {
            let lineY = screen.frame.minY + anchorY
            let startX = Int(screen.frame.minX.rounded(.down))
            let endX = Int((screen.frame.maxX - 1).rounded(.down))
            for rawX in stride(from: startX, through: endX, by: step) {
                var hitElement: AXUIElement?
                let error = AXUIElementCopyElementAtPosition(systemWide, Float(rawX), Float(lineY), &hitElement)
                guard error == .success, let hitElement else { continue }

                var pid: pid_t = 0
                AXUIElementGetPid(hitElement, &pid)
                guard candidatePIDs.contains(pid),
                      let app = NSRunningApplication(processIdentifier: pid),
                      let bundleID = resolvedBundleIdentifier(for: app),
                      bundleID != Bundle.main.bundleIdentifier else {
                    continue
                }

                var roleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(hitElement, kAXRoleAttribute as CFString, &roleValue)
                let role = axString(roleValue) ?? ""
                guard role == (kAXMenuBarItemRole as String) || role == "AXMenuBarItem" else { continue }

                var subroleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(hitElement, kAXSubroleAttribute as CFString, &subroleValue)
                let subrole = axString(subroleValue) ?? ""
                guard subrole == "AXMenuExtra" else { continue }

                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(hitElement, kAXIdentifierAttribute as CFString, &identifierValue)

                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(hitElement, kAXTitleAttribute as CFString, &titleValue)

                var descriptionValue: CFTypeRef?
                AXUIElementCopyAttributeValue(hitElement, kAXDescriptionAttribute as CFString, &descriptionValue)

                samples.append(
                    SystemWideHitSample(
                        pid: pid,
                        bundleID: bundleID,
                        appName: app.localizedName ?? bundleID,
                        lineY: lineY,
                        x: CGFloat(rawX),
                        role: role,
                        subrole: subrole,
                        rawIdentifier: axString(identifierValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                        rawTitle: axString(titleValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                        rawDescription: axString(descriptionValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
        }

        let segments = systemWideMenuBarSegments(from: samples, sampleStep: sampleStep)
        return resolvedSystemWideMenuBarItems(from: segments, sampleStep: sampleStep)
    }

    internal nonisolated static func systemWideMenuBarSegments(
        from samples: [SystemWideHitSample],
        sampleStep: CGFloat = 4
    ) -> [SystemWideMenuBarSegment] {
        guard !samples.isEmpty else { return [] }

        let sortedSamples = samples.sorted {
            if $0.lineY != $1.lineY { return $0.lineY < $1.lineY }
            return $0.x < $1.x
        }

        var segments: [SystemWideMenuBarSegment] = []
        var current = sortedSamples[0]
        var segmentStartX = current.x
        var segmentEndX = current.x

        func flushCurrent() {
            segments.append(
                SystemWideMenuBarSegment(
                    pid: current.pid,
                    bundleID: current.bundleID,
                    appName: current.appName,
                    lineY: current.lineY,
                    startX: segmentStartX,
                    endX: segmentEndX,
                    rawIdentifier: current.rawIdentifier,
                    rawTitle: current.rawTitle,
                    rawDescription: current.rawDescription
                )
            )
        }

        for sample in sortedSamples.dropFirst() {
            let isContiguous = sample.lineY == current.lineY &&
                sample.pid == current.pid &&
                sample.bundleID == current.bundleID &&
                sample.role == current.role &&
                sample.subrole == current.subrole &&
                sample.rawIdentifier == current.rawIdentifier &&
                sample.rawTitle == current.rawTitle &&
                sample.rawDescription == current.rawDescription &&
                sample.x <= (segmentEndX + max(1, sampleStep))

            if isContiguous {
                segmentEndX = sample.x
                continue
            }

            flushCurrent()
            current = sample
            segmentStartX = sample.x
            segmentEndX = sample.x
        }

        flushCurrent()
        return segments
    }

    internal nonisolated static func resolvedSystemWideMenuBarItems(
        from segments: [SystemWideMenuBarSegment],
        sampleStep: CGFloat = 4
    ) -> [MenuBarItemPosition] {
        guard !segments.isEmpty else { return [] }

        let countByBundle = Dictionary(grouping: segments, by: \.bundleID).mapValues(\.count)
        var seenKeys = Set<String>()
        var resolved: [MenuBarItemPosition] = []

        for segment in segments {
            let width = max(1, (segment.endX - segment.startX) + max(1, sampleStep))
            let identifierLabel = [segment.rawTitle, segment.rawDescription]
                .compactMap { value -> String? in
                    guard let value else { return nil }
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                .first
            let displayLabel = identifierLabel ?? segment.appName

            let identifier = canonicalMenuExtraIdentifier(
                ownerBundleId: segment.bundleID,
                rawIdentifier: segment.rawIdentifier,
                rawLabel: identifierLabel,
                width: width,
                allowThirdPartyLabelFallback: true
            )

            let appModel: RunningApp
            if let identifier {
                if segment.bundleID.hasPrefix("com.apple.") {
                    appModel = RunningApp.menuExtraItem(
                        ownerBundleId: segment.bundleID,
                        name: displayLabel,
                        identifier: identifier,
                        xPosition: segment.startX,
                        width: width
                    )
                } else if let app = NSRunningApplication(processIdentifier: segment.pid) {
                    appModel = RunningApp(
                        app: app,
                        resolvedBundleId: segment.bundleID,
                        menuExtraIdentifier: identifier,
                        xPosition: segment.startX,
                        width: width
                    )
                } else {
                    appModel = RunningApp(
                        id: segment.bundleID,
                        name: displayLabel,
                        icon: nil,
                        policy: .accessory,
                        category: segment.bundleID.hasPrefix("com.apple.") ? .system : .other,
                        menuExtraIdentifier: identifier,
                        xPosition: segment.startX,
                        width: width
                    )
                }
            } else {
                guard countByBundle[segment.bundleID] == 1 else { continue }

                if let app = NSRunningApplication(processIdentifier: segment.pid) {
                    appModel = RunningApp(
                        app: app,
                        resolvedBundleId: segment.bundleID,
                        xPosition: segment.startX,
                        width: width
                    )
                } else {
                    appModel = RunningApp(
                        id: segment.bundleID,
                        name: displayLabel,
                        icon: nil,
                        policy: .accessory,
                        category: segment.bundleID.hasPrefix("com.apple.") ? .system : .other,
                        xPosition: segment.startX,
                        width: width
                    )
                }
            }

            let key = appModel.uniqueId
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            resolved.append(MenuBarItemPosition(app: appModel, x: segment.startX, width: width))
        }

        return resolved.sorted { $0.x < $1.x }
    }
}
