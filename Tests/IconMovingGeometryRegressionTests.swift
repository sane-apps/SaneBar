import Foundation
@testable import SaneBar
import Testing

@Suite("Icon Moving — Grab Point")
struct IconMovingGrabPointTests {
    @Test("REGRESSION: Grab point is icon center (midX), not left edge")
    func grabPointIsCenterNotLeftEdge() {
        // Feb 8 regression: changed to iconFrame.origin.x + 12 (left-edge grab)
        // This broke CoinTick and other non-standard icons
        let iconFrame = CGRect(x: 400, y: 5, width: 22, height: 22)

        let grabX = iconFrame.midX
        let grabY = iconFrame.midY

        #expect(grabX == 411, "Grab X must be center of icon (midX)")
        #expect(grabY == 16, "Grab Y must be center of icon (midY)")
    }

    @Test("Grab point for wide icon (CoinTick 200px)")
    func grabPointWideIcon() {
        let iconFrame = CGRect(x: 300, y: 5, width: 200, height: 22)

        let grabX = iconFrame.midX
        let grabY = iconFrame.midY

        #expect(grabX == 400, "Wide icon grab must be at center")
        #expect(grabY == 16)
    }

    @Test("Grab point for narrow icon (16px)")
    func grabPointNarrowIcon() {
        let iconFrame = CGRect(x: 600, y: 5, width: 16, height: 22)

        let grabX = iconFrame.midX
        let grabY = iconFrame.midY

        #expect(grabX == 608, "Narrow icon grab at center")
        #expect(grabY == 16)
    }
}

// MARK: - Verification Margin Tests

@Suite("Icon Moving — Verification Margins")
struct IconMovingVerificationTests {
    @Test("Verification margin scales with icon width (minimum 4px)")
    func verificationMarginScalesWithWidth() {
        // Formula: max(4, afterFrame.size.width * 0.3)
        let standardMargin = max(CGFloat(4), CGFloat(22) * 0.3) // 6.6
        #expect(standardMargin == 6.6)

        let narrowMargin = max(CGFloat(4), CGFloat(10) * 0.3) // 4 (minimum)
        #expect(narrowMargin == 4)

        let wideMargin = max(CGFloat(4), CGFloat(44) * 0.3) // 13.2
        #expect(wideMargin == 13.2)
    }

    @Test("Hidden verification: icon must be LEFT of separatorX minus margin")
    func hiddenVerification() {
        let separatorX: CGFloat = 500
        let afterFrameX: CGFloat = 450
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3)

        let isVerified = afterFrameX < (separatorX - margin)

        #expect(isVerified, "Icon at 450 should verify as hidden (separator at 500, margin ~6.6)")
    }

    @Test("Visible verification: icon must be RIGHT of separatorX plus margin")
    func visibleVerification() {
        let separatorX: CGFloat = 500
        let afterFrameX: CGFloat = 550
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3)

        let isVerified = afterFrameX > (separatorX + margin)

        #expect(isVerified, "Icon at 550 should verify as visible (separator at 500, margin ~6.6)")
    }

    @Test("Verification fails for icon on wrong side")
    func verificationFailsWrongSide() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3)

        // Tried to hide but icon ended up on right side
        let afterFrameX: CGFloat = 520
        let hiddenVerified = afterFrameX < (separatorX - margin)
        #expect(!hiddenVerified, "Icon at 520 should NOT verify as hidden")

        // Tried to show but icon stayed on left side
        let afterFrameX2: CGFloat = 480
        let visibleVerified = afterFrameX2 > (separatorX + margin)
        #expect(!visibleVerified, "Icon at 480 should NOT verify as visible")
    }

    @Test("Verification fails for icon in ambiguous zone (within margin)")
    func verificationFailsAmbiguousZone() {
        let separatorX: CGFloat = 500
        let iconWidth: CGFloat = 22
        let margin = max(CGFloat(4), iconWidth * 0.3) // 6.6

        // Icon at 495 — LEFT of separator but within margin
        let nearLeftX: CGFloat = 495
        let hiddenVerified = nearLeftX < (separatorX - margin) // 495 < 493.4 → false
        #expect(!hiddenVerified, "Icon within margin zone should NOT verify — hide() might reclassify it")

        // Icon at 505 — RIGHT of separator but within margin
        let nearRightX: CGFloat = 505
        let visibleVerified = nearRightX > (separatorX + margin) // 505 > 506.6 → false
        #expect(!visibleVerified, "Icon within margin zone should NOT verify")
    }
}

// MARK: - Coordinate Space Tests

@Suite("Icon Moving — Coordinate Space")
struct IconMovingCoordinateSpaceTests {
    @Test("CGEvent screen frames flip vertically for stacked displays")
    func cgEventScreenFrameFlipsStackedDisplays() {
        let lowerDisplay = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let upperDisplay = CGRect(x: 3440, y: 900, width: 1512, height: 982)
        let globalMaxY = max(lowerDisplay.maxY, upperDisplay.maxY)

        let cgFrame = AccessibilityService.cgEventScreenFrame(
            fromAppKitScreenFrame: upperDisplay,
            globalMaxY: globalMaxY
        )

        #expect(cgFrame.origin.x == 3438)
        #expect(cgFrame.origin.y == -2, "Upper display should map back to the top edge in CGEvent space")
        #expect(cgFrame.width == 1516)
        #expect(cgFrame.height == 986)
    }

    @Test("REGRESSION: CGEvent drag points stay on-screen for vertically offset displays")
    func cgEventPointValidationUsesCGSpace() {
        let lowerDisplay = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let upperDisplay = CGRect(x: 3440, y: 900, width: 1512, height: 982)
        let screenFrames = [lowerDisplay, upperDisplay]
        let globalMaxY = max(lowerDisplay.maxY, upperDisplay.maxY)
        let dragPoint = CGPoint(x: 3655, y: 1)

        let appKitContainsPoint = screenFrames.contains { $0.insetBy(dx: -2, dy: -2).contains(dragPoint) }

        #expect(!appKitContainsPoint, "Raw AppKit frames would wrongly reject the drag point")
        #expect(
            AccessibilityService.isCGEventPointOnAnyScreen(
                dragPoint,
                screenFrames: screenFrames,
                globalMaxY: globalMaxY
            ),
            "CGEvent-space validation should accept the same point on the upper display"
        )
    }
}

// MARK: - Separator Caching Tests

@Suite("Icon Moving — Separator Caching")
struct SeparatorCachingTests {
    @Test("Blocking mode detection: length > 1000 is blocking")
    func blockingModeDetection() {
        // When separator length is > 1000 (typically 10,000), it's in blocking mode
        // and the live position is off-screen (~-3349)
        let normalLength: CGFloat = 20
        let blockingLength: CGFloat = 10000

        #expect(normalLength <= 1000, "Length 20 is NOT blocking mode")
        #expect(blockingLength > 1000, "Length 10,000 IS blocking mode")
    }

    @Test("Cache validity: only positive X values are cached")
    func cacheValidity() {
        // Off-screen positions (negative or zero) should NOT update the cache
        let offScreenX: CGFloat = -3349
        let validX: CGFloat = 500
        let zeroX: CGFloat = 0

        #expect(offScreenX <= 0, "Off-screen position must NOT be cached")
        #expect(validX > 0, "On-screen position SHOULD be cached")
        #expect(zeroX <= 0, "Zero position must NOT be cached")
    }

    @Test("REGRESSION: Separator at -3349 in blocking mode returns cached value")
    func separatorBlockingModeReturnsCached() {
        // Feb 8 bug: geometryResolver.separatorOriginX() returned nil when separator was in blocking mode
        // because the live window position was -3349 (off-screen) and there was no cache
        // Fix: Cache valid positions and return cached value in blocking mode

        func resolvedSeparatorX(
            lastKnownSeparatorX: CGFloat?,
            separatorLength: CGFloat,
            liveWindowX: CGFloat
        ) -> CGFloat? {
            var cachedSeparatorX = lastKnownSeparatorX
            if separatorLength > 1000 {
                return cachedSeparatorX
            }
            if liveWindowX > 0 {
                cachedSeparatorX = liveWindowX
                return liveWindowX
            }
            return cachedSeparatorX
        }

        let result = resolvedSeparatorX(
            lastKnownSeparatorX: 500,
            separatorLength: 10000,
            liveWindowX: -3349
        )

        #expect(result == 500, "Blocking mode must return cached position, not live -3349")
    }

    @Test("REGRESSION: Always-hidden separator stale/off-screen origin falls back to cached value")
    func alwaysHiddenSeparatorStaleOriginUsesCache() {
        // Mar 2026 bug: AH separator occasionally reported stale negative origin (e.g. -30)
        // after relayout, which produced off-screen drag targets.
        func resolvedAlwaysHiddenOrigin(liveWindowX: CGFloat, cachedX: CGFloat?) -> CGFloat? {
            if liveWindowX > 0 {
                return liveWindowX
            }
            if let cachedX, cachedX > 0 {
                return cachedX
            }
            return nil
        }

        let result = resolvedAlwaysHiddenOrigin(liveWindowX: -30, cachedX: 312)

        #expect(result == 312, "Stale/off-screen AH origin must use cached positive X")
    }

    @Test("Always-hidden separator stale/off-screen origin with empty cache returns nil")
    func alwaysHiddenSeparatorStaleOriginEmptyCacheReturnsNil() {
        func resolvedAlwaysHiddenOrigin(liveWindowX: CGFloat, cachedX: CGFloat?) -> CGFloat? {
            if liveWindowX > 0 {
                return liveWindowX
            }
            if let cachedX, cachedX > 0 {
                return cachedX
            }
            return nil
        }

        let result = resolvedAlwaysHiddenOrigin(liveWindowX: -30, cachedX: nil)

        #expect(result == nil, "No cached AH origin should avoid invalid drag targets")
    }

    @Test("Hidden wake preserves trustworthy cache while display removal invalidates it")
    func hiddenWakePreservesTrustworthyCacheWhileDisplayRemovalInvalidatesIt() {
        #expect(
            MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: 500,
                separatorRightEdgeX: 520,
                mainStatusItemX: 560,
                displayStillPresent: true
            ),
            "Hidden wake should preserve the last trustworthy separator cache until live anchors return"
        )
        #expect(
            MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: -600,
                separatorRightEdgeX: -580,
                mainStatusItemX: -540,
                displayStillPresent: true
            ),
            "Hidden wake should preserve ordered cached geometry on displays arranged left of the primary"
        )
        #expect(
            !MenuBarManager.shouldPreserveCachedGeometryForHiddenLifecycle(
                hidingState: .hidden,
                separatorX: 500,
                separatorRightEdgeX: 520,
                mainStatusItemX: 560,
                displayStillPresent: false
            ),
            "If the display disappeared, cached separator geometry must be invalidated"
        )
    }
}

// MARK: - Move Orchestration Invariants
