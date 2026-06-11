import AppKit

// MARK: - Accessibility Interaction Policy

enum AccessibilityInteractionPolicy {
    enum MoveTargetLane {
        case hidden
        case hiddenFromAlwaysHidden
        case alwaysHidden
        case visible
        case visibleFromAlwaysHidden
    }

    nonisolated static func shouldFallbackToAXAfterHardwareAttempt(
        success: Bool,
        verificationSummary: String,
        isItemOnScreen: Bool,
        isRightClick: Bool
    ) -> Bool {
        guard isItemOnScreen else { return false }
        if success, verificationSummary.hasPrefix("verified") {
            return false
        }
        if success, isRightClick {
            return false
        }
        return true
    }

    nonisolated static func cgEventScreenFrame(
        fromAppKitScreenFrame screenFrame: CGRect,
        globalMaxY: CGFloat,
        inset: CGFloat = 2
    ) -> CGRect {
        let cgMinY = globalMaxY - screenFrame.maxY
        return CGRect(
            x: screenFrame.minX,
            y: cgMinY,
            width: screenFrame.width,
            height: screenFrame.height
        ).insetBy(dx: -inset, dy: -inset)
    }

    nonisolated static func isCGEventPointOnAnyScreen(
        _ point: CGPoint,
        screenFrames: [CGRect],
        globalMaxY: CGFloat,
        inset: CGFloat = 2
    ) -> Bool {
        screenFrames.contains {
            let appKitFrame = $0.insetBy(dx: -inset, dy: -inset)
            let cgEventFrame = cgEventScreenFrame(fromAppKitScreenFrame: $0, globalMaxY: globalMaxY, inset: inset)
            return cgEventFrame.contains(point) || appKitFrame.contains(point)
        }
    }

    nonisolated static func resolvedGlobalAccessibilityPoint(
        _ point: CGPoint,
        screenFrames: [CGRect],
        preferredScreenFrame: CGRect? = nil,
        inset: CGFloat = 2
    ) -> CGPoint {
        guard !screenFrames.isEmpty else { return point }

        if let preferredScreenFrame {
            let preferredLocalFrame = CGRect(
                x: 0,
                y: 0,
                width: preferredScreenFrame.width,
                height: preferredScreenFrame.height
            ).insetBy(dx: -inset, dy: -inset)

            if preferredLocalFrame.contains(point) {
                let rebased = CGPoint(x: preferredScreenFrame.minX + point.x, y: point.y)
                if preferredScreenFrame.insetBy(dx: -inset, dy: -inset).contains(rebased) {
                    return rebased
                }
            }

            if preferredScreenFrame.insetBy(dx: -inset, dy: -inset).contains(point) {
                return point
            }
        }

        if screenFrames.contains(where: { $0.insetBy(dx: -inset, dy: -inset).contains(point) }) {
            return point
        }

        let localMatches = screenFrames.compactMap { screenFrame -> CGPoint? in
            let localFrame = CGRect(
                x: 0,
                y: 0,
                width: screenFrame.width,
                height: screenFrame.height
            ).insetBy(dx: -inset, dy: -inset)
            guard localFrame.contains(point) else { return nil }
            return CGPoint(x: screenFrame.minX + point.x, y: point.y)
        }

        guard !localMatches.isEmpty else { return point }
        return localMatches.min { abs($0.x - point.x) < abs($1.x - point.x) } ?? point
    }

    nonisolated static func isAccessibilityPointOnAnyScreen(
        _ point: CGPoint,
        screenFrames: [CGRect],
        preferredScreenFrame: CGRect? = nil,
        inset: CGFloat = 2
    ) -> Bool {
        let resolved = resolvedGlobalAccessibilityPoint(
            point,
            screenFrames: screenFrames,
            preferredScreenFrame: preferredScreenFrame,
            inset: inset
        )
        return screenFrames.contains { $0.insetBy(dx: -inset, dy: -inset).contains(resolved) }
    }

    nonisolated static func isAccessibilityPointOnAnyScreen(_ point: CGPoint) -> Bool {
        isAccessibilityPointOnAnyScreen(
            point,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }

    nonisolated static func normalizedEventY(rawY: CGFloat, globalMaxY: CGFloat, anchorY: CGFloat) -> CGFloat {
        let flippedY = globalMaxY - rawY

        // AX values may arrive in either AppKit-unflipped or CoreGraphics-flipped space.
        // Use the menu bar anchor to pick whichever candidate is closer to reality.
        let chosenY = abs(rawY - anchorY) <= abs(flippedY - anchorY) ? rawY : flippedY

        let minY: CGFloat = 1
        let maxY = max(minY, globalMaxY - 1)
        return min(max(chosenY, minY), maxY)
    }

    nonisolated static func normalizedCGEventPoint(
        fromAccessibilityPoint point: CGPoint,
        preferredScreenFrame: CGRect? = nil
    ) -> CGPoint {
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        let globalPoint = resolvedGlobalAccessibilityPoint(
            point,
            screenFrames: NSScreen.screens.map(\.frame),
            preferredScreenFrame: preferredScreenFrame
        )
        let rawY = point.y
        let anchorY: CGFloat = 15
        let clampedY = normalizedEventY(rawY: rawY, globalMaxY: globalMaxY, anchorY: anchorY)
        return CGPoint(x: globalPoint.x, y: clampedY)
    }

    /// Shared zone-edge verification used after cmd-drag moves.
    /// Uses icon midpoint (same basis as UI zone classification) to avoid
    /// false negatives when macOS lands just to the right of the separator.
    nonisolated static func frameIsInTargetZone(
        afterFrame: CGRect,
        separatorX: CGFloat,
        toHidden: Bool,
        margin: CGFloat = 6,
        alwaysHiddenBoundaryX: CGFloat? = nil
    ) -> Bool {
        let midpointX = afterFrame.midX
        let threshold = separatorX - margin
        guard toHidden else {
            guard let alwaysHiddenBoundaryX,
                  alwaysHiddenBoundaryX.isFinite,
                  alwaysHiddenBoundaryX > separatorX
            else {
                return midpointX >= threshold
            }
            let laneWidth = alwaysHiddenBoundaryX - separatorX
            guard laneWidth > 0 else { return midpointX >= threshold }
            let laneMargin = min(margin, max(1, laneWidth * 0.25))
            let lowerBound = separatorX + laneMargin
            let upperBound = alwaysHiddenBoundaryX - laneMargin
            guard lowerBound < upperBound else {
                return midpointX > separatorX && midpointX < alwaysHiddenBoundaryX
            }
            return midpointX >= lowerBound && midpointX <= upperBound
        }
        guard let alwaysHiddenBoundaryX,
              alwaysHiddenBoundaryX.isFinite,
              alwaysHiddenBoundaryX > 0
        else {
            guard midpointX < threshold else {
                return false
            }
            return true
        }
        let laneWidth = separatorX - alwaysHiddenBoundaryX
        guard laneWidth > 0 else {
            return midpointX < threshold
        }
        let laneMargin = min(margin, max(1, laneWidth * 0.25))
        let lowerBound = alwaysHiddenBoundaryX + laneMargin
        let upperBound = separatorX - laneMargin
        guard lowerBound < upperBound else {
            return midpointX > alwaysHiddenBoundaryX && midpointX < separatorX
        }
        return midpointX >= lowerBound && midpointX <= upperBound
    }

    nonisolated static func frameIsInTargetLane(
        afterFrame: CGRect,
        targetLane: MoveTargetLane,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?,
        margin: CGFloat = 6
    ) -> Bool {
        switch targetLane {
        case .visible, .visibleFromAlwaysHidden:
            frameIsInTargetZone(
                afterFrame: afterFrame,
                separatorX: separatorX,
                toHidden: false,
                margin: margin,
                alwaysHiddenBoundaryX: visibleBoundaryX
            )

        case .hidden, .hiddenFromAlwaysHidden:
            frameIsInTargetZone(
                afterFrame: afterFrame,
                separatorX: separatorX,
                toHidden: true,
                margin: margin,
                alwaysHiddenBoundaryX: visibleBoundaryX
            )

        case .alwaysHidden:
            frameIsInTargetZone(
                afterFrame: afterFrame,
                separatorX: separatorX,
                toHidden: true,
                margin: margin,
                alwaysHiddenBoundaryX: nil
            )
        }
    }

    /// Detect direction mismatches for post-drag verification without penalizing
    /// idempotent moves where the icon already started on the target side.
    /// This avoids false negatives when a visible->visible reorder shifts left
    /// while still remaining in the visible zone.
    nonisolated static func hasDirectionMismatch(
        beforeFrame: CGRect,
        afterFrame: CGRect,
        separatorX: CGFloat,
        toHidden: Bool,
        margin: CGFloat = 6,
        tolerance: CGFloat = 2
    ) -> Bool {
        let startedInTargetZone = frameIsInTargetZone(
            afterFrame: beforeFrame,
            separatorX: separatorX,
            toHidden: toHidden,
            margin: margin
        )
        if startedInTargetZone {
            return false
        }

        let deltaX = afterFrame.midX - beforeFrame.midX
        if toHidden {
            return deltaX > tolerance
        }
        return deltaX < -tolerance
    }

    nonisolated static func hasDirectionMismatch(
        beforeFrame: CGRect,
        afterFrame: CGRect,
        separatorX: CGFloat,
        targetLane: MoveTargetLane,
        visibleBoundaryX: CGFloat?,
        margin: CGFloat = 6,
        tolerance: CGFloat = 2
    ) -> Bool {
        let startedInTargetLane = frameIsInTargetLane(
            afterFrame: beforeFrame,
            targetLane: targetLane,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX,
            margin: margin
        )
        if startedInTargetLane {
            return false
        }

        let deltaX = afterFrame.midX - beforeFrame.midX
        switch targetLane {
        case .visible, .visibleFromAlwaysHidden:
            return deltaX < -tolerance

        case .alwaysHidden:
            return deltaX > tolerance

        case .hidden, .hiddenFromAlwaysHidden:
            if let visibleBoundaryX,
               visibleBoundaryX.isFinite,
               visibleBoundaryX > 0,
               visibleBoundaryX < separatorX {
                if beforeFrame.midX < visibleBoundaryX {
                    return deltaX < -tolerance
                }
                if beforeFrame.midX > separatorX {
                    return deltaX > tolerance
                }
                return false
            }
            return deltaX > tolerance
        }
    }

    nonisolated static func shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
        staleSeparatorX: CGFloat,
        staleFrame: CGRect,
        freshSeparatorX: CGFloat,
        freshVisibleBoundaryX: CGFloat,
        refreshedFrame: CGRect
    ) -> Bool {
        guard staleSeparatorX.isFinite,
              freshSeparatorX.isFinite,
              freshVisibleBoundaryX.isFinite,
              staleSeparatorX > 0,
              freshSeparatorX > 0,
              freshVisibleBoundaryX > freshSeparatorX
        else {
            return false
        }

        let staleShortfall = staleSeparatorX - staleFrame.midX
        guard staleShortfall > 0, staleShortfall <= 160 else { return false }

        // Fresh geometry must move materially left before we trust it as a real
        // post-drag re-layout rather than the same stale separator snapshot.
        guard freshSeparatorX + 12 < staleSeparatorX else { return false }

        return frameIsInTargetZone(
            afterFrame: refreshedFrame,
            separatorX: freshSeparatorX,
            toHidden: false
        )
    }

    /// Shared target X selection for Cmd+drag moves.
    /// Each lane uses its own insertion policy so we do not conflate regular
    /// hidden drags with always-hidden drags.
    nonisolated static func moveTargetX(
        targetLane: MoveTargetLane,
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        let moveOffset = max(30, iconWidth + 20)

        switch targetLane {
        case .hidden:
            // No clamp = direct hidden move.
            let farHiddenX = separatorX - max(80, iconWidth + 60)
            guard let ahBoundary = visibleBoundaryX else {
                // Wide text-style extras can stop in the regular hidden lane unless we
                // drag much deeper into the always-hidden section.
                let wideAlwaysHiddenThreshold: CGFloat = 56
                if iconWidth >= wideAlwaysHiddenThreshold {
                    let wideAlwaysHiddenOffset = max(180, (iconWidth * 3) + 30)
                    return separatorX - wideAlwaysHiddenOffset
                }
                return farHiddenX
            }

            // Hidden lane is between AH separator right edge and main separator left edge.
            let hiddenLaneWidth = separatorX - ahBoundary
            guard hiddenLaneWidth > 0 else {
                return farHiddenX
            }
            let laneMidX = ahBoundary + (hiddenLaneWidth * 0.5)
            let laneMargin = min(CGFloat(6), max(CGFloat(1), hiddenLaneWidth * 0.25))
            let minRegularHiddenX = ahBoundary + laneMargin
            let separatorSafety = max(20, (iconWidth * 0.5) + 12)
            let boundedSeparatorSafety = min(separatorSafety, max(laneMargin, hiddenLaneWidth * 0.45))
            let maxRegularHiddenX = separatorX - boundedSeparatorSafety

            // If the lane is too narrow for the normal bias/safety margins, target
            // the actual lane midpoint instead of falling into always-hidden space.
            let narrowRegularHiddenLaneThreshold = max(CGFloat(24), (iconWidth * 0.5) + 12)
            if hiddenLaneWidth <= narrowRegularHiddenLaneThreshold {
                return laneMidX
            }
            guard minRegularHiddenX <= maxRegularHiddenX else {
                return laneMidX
            }
            // Bias toward the main separator side of the hidden lane so a
            // subsequent re-hide transition doesn't nudge the icon into the
            // always-hidden section.
            let rightBiasInset = max(6, min(20, iconWidth * 0.45))
            let preferredRegularHiddenX = maxRegularHiddenX - rightBiasInset
            let boundedPreferredX = min(max(preferredRegularHiddenX, minRegularHiddenX), maxRegularHiddenX)

            // Keep the deeper fallback available for wide icons where the
            // separator-side bias can under-move native text-style extras.
            let wideRegularHiddenThreshold: CGFloat = 56
            let fallbackRegularHiddenX = min(max(farHiddenX, minRegularHiddenX), maxRegularHiddenX)
            return iconWidth >= wideRegularHiddenThreshold ? fallbackRegularHiddenX : boundedPreferredX

        case .hiddenFromAlwaysHidden:
            let farHiddenX = separatorX - max(80, iconWidth + 60)
            guard let ahBoundary = visibleBoundaryX else {
                return farHiddenX
            }
            let hiddenLaneWidth = separatorX - ahBoundary
            guard hiddenLaneWidth > 0 else {
                return farHiddenX
            }
            return ahBoundary + (hiddenLaneWidth * 0.5)

        case .alwaysHidden:
            // Always-hidden insertion should stay close to the AH separator instead
            // of using the deeper generic hidden target, which can overshoot across
            // sibling icons and fail exact-identity verification.
            return separatorX - moveOffset

        case .visibleFromAlwaysHidden:
            return visibleInsertionTargetX(
                iconWidth: iconWidth,
                separatorX: separatorX,
                visibleBoundaryX: visibleBoundaryX
            )

        case .visible:
            return visibleInsertionTargetX(
                iconWidth: iconWidth,
                separatorX: separatorX,
                visibleBoundaryX: visibleBoundaryX
            )
        }
    }

    private nonisolated static func visibleInsertionTargetX(
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        let nearSeparatorOffset = max(CGFloat(8), min(CGFloat(24), iconWidth * 0.35))
        guard let boundary = visibleBoundaryX else {
            return separatorX + 1
        }
        let visibleLaneWidth = boundary - separatorX
        guard visibleLaneWidth > 1 else {
            return separatorX + 1
        }
        // Aim for the middle of the visible lane, not the separator edge: the
        // menu bar reflows during the drag (the separator shifts right as the
        // item inserts), so a target hugging the pre-drag separator edge can
        // settle just left of the post-reflow separator and fail strict
        // live-boundary verification. Narrow lanes degrade to the old
        // near-separator offset.
        let minX = separatorX + min(nearSeparatorOffset, max(CGFloat(1), visibleLaneWidth * 0.35))
        let mainSafety = max(nearSeparatorOffset, (iconWidth * 0.5) + 8)
        let maxX = max(boundary - mainSafety, minX)
        let laneMidX = separatorX + (visibleLaneWidth * 0.5)
        return min(max(laneMidX, minX), maxX)
    }

    nonisolated static func moveTargetX(
        toHidden: Bool,
        iconWidth: CGFloat,
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) -> CGFloat {
        moveTargetX(
            targetLane: toHidden ? .hidden : .visible,
            iconWidth: iconWidth,
            separatorX: separatorX,
            visibleBoundaryX: visibleBoundaryX
        )
    }

    nonisolated static func cmdDragStepCount(distance: CGFloat) -> Int {
        let normalizedDistance = max(0, distance)
        let proposedSteps = Int(ceil(normalizedDistance / 22))
        return min(max(proposedSteps, 10), 14)
    }
}
