import CoreGraphics
@testable import SaneBar
import Testing

@Suite("Menu Extra Identifier Normalization")
struct MenuExtraIdentifierNormalizationTests {
    @Test("Keeps canonical Apple menu extra identifiers")
    func keepsCanonicalAppleIdentifier() {
        let id = AccessibilityService.canonicalMenuExtraIdentifier(
            ownerBundleId: "com.apple.controlcenter",
            rawIdentifier: "com.apple.menuextra.wifi",
            rawLabel: "Wi-Fi",
            width: 16
        )
        #expect(id == "com.apple.menuextra.wifi")
    }

    @Test("Maps Siri from label fallback when AXIdentifier is missing")
    func mapsSiriFromLabelFallback() {
        let id = AccessibilityService.canonicalMenuExtraIdentifier(
            ownerBundleId: "com.apple.controlcenter",
            rawIdentifier: nil,
            rawLabel: "Siri",
            width: 18
        )
        #expect(id == "com.apple.menuextra.siri")
    }

    @Test("Rejects zero-width Apple extras with no identifier")
    func rejectsZeroWidthUnknownAppleExtra() {
        let id = AccessibilityService.canonicalMenuExtraIdentifier(
            ownerBundleId: "com.apple.controlcenter",
            rawIdentifier: nil,
            rawLabel: nil,
            width: 0
        )
        #expect(id == nil)
    }

    @Test("Preserves non-Apple identifiers")
    func preservesNonAppleIdentifier() {
        let id = AccessibilityService.canonicalMenuExtraIdentifier(
            ownerBundleId: "com.vendor.menuagent",
            rawIdentifier: "com.vendor.menuagent.status",
            rawLabel: "Vendor Status",
            width: 20
        )
        #expect(id == "com.vendor.menuagent.status")
    }

    @Test("Extracts bundle identifier from Item suffix")
    func extractsBundleIdentifierFromItemSuffix() {
        let bundle = AccessibilityService.bundleIdentifierFallback(
            fromAXIdentifier: "com.obdev.LittleSnitchUIAgent-Item-0"
        )
        #expect(bundle == "com.obdev.LittleSnitchUIAgent")
    }

    @Test("Ignores Apple menu-extra identifiers for bundle fallback")
    func ignoresAppleMenuExtraForBundleFallback() {
        let bundle = AccessibilityService.bundleIdentifierFallback(
            fromAXIdentifier: "com.apple.menuextra.battery"
        )
        #expect(bundle == nil)
    }
}
