import CoreGraphics
import Foundation
@testable import SaneBar
import Testing

/// Plan A — CHANGE A regression lock.
///
/// `currentLiveAlwaysHiddenSeparatorFrame()` previously gated liveness behind a
/// redundant `length <= 1000` clause that could NEVER pass for a hidden
/// always-hidden separator (length 10000), silently blocking outbound
/// Always-Hidden moves (#155/#156/#166). Liveness is now judged solely by the
/// screen-relative `statusItemWindowFrameIsReadableLive` policy. These pure
/// tests lock that the decision is screen-relative only — never length, never
/// sign — and that off-screen rejection is preserved.
@Suite("AH Separator Liveness — Length Tolerance")
struct AlwaysHiddenSeparatorLivenessTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("Live AH separator window in its menu-bar band reads live regardless of item length")
    func liveWindowInBandReadsLive() {
        // A status-item window whose true frame sits in the band. The item's
        // logical `length` (10000 while hidden) is irrelevant to this decision —
        // only the window frame matters.
        let frame = CGRect(x: 1300, y: 878, width: 14, height: 22)

        #expect(
            MenuBarMoveGeometryPolicy.statusItemWindowFrameIsReadableLive(
                frame: frame, screenFrame: screenFrame
            )
        )
    }

    @Test("Off-screen AH separator window is rejected regardless of length")
    func offScreenWindowIsRejected() {
        // Pushed off-screen (origin far right of its screen's max X). Off-screen
        // rejection must still hold even though the length cap is gone.
        let frame = CGRect(x: 5000, y: 878, width: 14, height: 22)

        #expect(
            !MenuBarMoveGeometryPolicy.statusItemWindowFrameIsReadableLive(
                frame: frame, screenFrame: screenFrame
            )
        )
    }

    @Test("A parked offscreen window (y=-22) is rejected even with positive X")
    func parkedOffscreenWindowIsRejected() {
        let frame = CGRect(x: 400, y: -22, width: 14, height: 22)

        #expect(
            !MenuBarMoveGeometryPolicy.statusItemWindowFrameIsReadableLive(
                frame: frame, screenFrame: screenFrame
            )
        )
    }

    @Test("Negative-X left-of-primary display still reads live (no sign checks)")
    func negativeXLeftDisplayReadsLive() {
        // Display arranged LEFT of the primary: global X is negative. Invariant
        // #2 — liveness is screen-relative, never a sign check.
        let leftScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -200, y: 878, width: 14, height: 22)

        #expect(
            MenuBarMoveGeometryPolicy.statusItemWindowFrameIsReadableLive(
                frame: frame, screenFrame: leftScreen
            )
        )
    }

    // MARK: - nil `window.screen` recovery (the external-monitor strand)

    // Root cause of the recovery strand: AppKit returns `NSWindow.screen == nil`
    // whenever the window frame doesn't intersect a screen rect (off-edge hidden
    // separator, external-display topology churn). The live readers fed that nil
    // straight into `statusItemFrameLooksLive`, which short-circuits to false, so a
    // window with a perfectly live frame was demoted to `.stale`/`.missing` and
    // recovery looped forever reporting `separatorStatusItemWindowValid: false` on
    // `isOnExternalMonitor`. `resolvedScreenFrameForStatusItemWindow` recovers the
    // dropped screen-relative judgement WITHOUT weakening off-screen rejection.

    @Test("nil window.screen: live frame is recovered against the matching candidate screen")
    func nilScreenLiveFrameRecoveredFromCandidate() {
        // External display arranged right of a built-in. The window's TRUE frame
        // sits in the external display's menu-bar band but AppKit dropped `.screen`.
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let liveOnExternal = CGRect(x: 3200, y: 1058, width: 14, height: 22)

        let resolved = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: liveOnExternal,
            attachedScreenFrame: nil,
            candidateScreenFrames: [builtIn, external]
        )

        #expect(resolved == external)
        #expect(
            MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
                frame: liveOnExternal, screenFrame: resolved
            )
        )
    }

    @Test("nil window.screen: an off-screen frame matches NO candidate band and stays rejected")
    func nilScreenOffScreenFrameStaysRejected() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        // Pushed far off the right edge of both displays' bands (the genuinely
        // off-screen case) — recovery must NOT manufacture liveness here.
        let parkedOffEdge = CGRect(x: 9000, y: 1058, width: 14, height: 22)

        let resolved = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: parkedOffEdge,
            attachedScreenFrame: nil,
            candidateScreenFrames: [builtIn, external]
        )

        #expect(resolved == nil)
        #expect(
            !MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
                frame: parkedOffEdge, screenFrame: resolved
            )
        )
    }

    @Test("nil window.screen: a vertically-parked (y=-22) frame stays rejected")
    func nilScreenVerticallyParkedFrameStaysRejected() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Horizontally inside the band but parked below it (the #152 off-menu-bar
        // y=-22 signature) — must not be recovered as live.
        let parkedBelow = CGRect(x: 400, y: -22, width: 14, height: 22)

        let resolved = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: parkedBelow,
            attachedScreenFrame: nil,
            candidateScreenFrames: [builtIn]
        )

        #expect(resolved == nil)
    }

    @Test("Attached window.screen is always honored verbatim (no candidate scan)")
    func attachedScreenHonoredVerbatim() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 1300, y: 878, width: 14, height: 22)

        // Even with other candidates present, an attached screen wins outright.
        let resolved = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: frame,
            attachedScreenFrame: builtIn,
            candidateScreenFrames: [external, builtIn]
        )

        #expect(resolved == builtIn)
    }

    @Test("Negative-X left-of-primary display is recovered when window.screen is nil")
    func nilScreenNegativeXLeftDisplayRecovered() {
        // Invariant #2: liveness is screen-relative, never a sign check — and that
        // must hold through the nil-screen recovery path too.
        let leftScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let liveOnLeft = CGRect(x: -200, y: 878, width: 14, height: 22)

        let resolved = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: liveOnLeft,
            attachedScreenFrame: nil,
            candidateScreenFrames: [primary, leftScreen]
        )

        #expect(resolved == leftScreen)
    }

    @Test("Readable-live wrapper matches the canonical liveness policy")
    func wrapperMatchesCanonicalPolicy() {
        let cases = [
            CGRect(x: 1300, y: 878, width: 14, height: 22),
            CGRect(x: 5000, y: 878, width: 14, height: 22),
            CGRect(x: 400, y: -22, width: 14, height: 22)
        ]
        for frame in cases {
            #expect(
                MenuBarMoveGeometryPolicy.statusItemWindowFrameIsReadableLive(
                    frame: frame, screenFrame: screenFrame
                ) == MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
                    frame: frame, screenFrame: screenFrame
                )
            )
        }
    }
}
