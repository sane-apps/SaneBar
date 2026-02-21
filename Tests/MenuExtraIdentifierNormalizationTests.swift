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

    @Test("Compatibility smoke matrix for tricky menu-extra identifiers")
    func compatibilitySmokeMatrix() {
        struct Case {
            let ownerBundleId: String
            let rawIdentifier: String?
            let rawLabel: String?
            let width: CGFloat
            let expected: String?
            let name: String
        }

        let cases: [Case] = [
            Case(
                ownerBundleId: "com.apple.controlcenter",
                rawIdentifier: nil,
                rawLabel: "Wi-Fi",
                width: 18,
                expected: "com.apple.menuextra.wifi",
                name: "Apple Wi-Fi label fallback"
            ),
            Case(
                ownerBundleId: "com.apple.controlcenter",
                rawIdentifier: "Now Playing",
                rawLabel: nil,
                width: 20,
                expected: "com.apple.menuextra.now-playing",
                name: "Apple now playing identifier alias"
            ),
            Case(
                ownerBundleId: "com.apple.systemuiserver",
                rawIdentifier: "com.apple.menuextra.Bluetooth",
                rawLabel: "Bluetooth",
                width: 16,
                expected: "com.apple.menuextra.bluetooth",
                name: "Apple canonical identifier lowercasing"
            ),
            Case(
                ownerBundleId: "com.obdev.LittleSnitchUIAgent",
                rawIdentifier: "com.obdev.LittleSnitchUIAgent-Item-0",
                rawLabel: "Little Snitch",
                width: 18,
                expected: "com.obdev.LittleSnitchUIAgent-Item-0",
                name: "Little Snitch third-party identifier preserved"
            ),
        ]

        for item in cases {
            let actual = AccessibilityService.canonicalMenuExtraIdentifier(
                ownerBundleId: item.ownerBundleId,
                rawIdentifier: item.rawIdentifier,
                rawLabel: item.rawLabel,
                width: item.width
            )
            #expect(actual == item.expected, "\(item.name): expected \(item.expected ?? "nil"), got \(actual ?? "nil")")
        }
    }

    @Test("Bundle fallback smoke matrix for helper-hosted extras")
    func bundleFallbackSmokeMatrix() {
        let cases: [(raw: String?, expected: String?, name: String)] = [
            ("com.obdev.LittleSnitchUIAgent-Item-0", "com.obdev.LittleSnitchUIAgent", "Little Snitch AX item"),
            ("com.obdev.LittleSnitchUIAgent", "com.obdev.LittleSnitchUIAgent", "Little Snitch direct bundle"),
            ("com.apple.menuextra.clock", nil, "Apple menu extra should not map to app bundle"),
            ("invalid identifier with spaces", nil, "Invalid identifier rejected"),
        ]

        for item in cases {
            let actual = AccessibilityService.bundleIdentifierFallback(fromAXIdentifier: item.raw)
            #expect(actual == item.expected, "\(item.name): expected \(item.expected ?? "nil"), got \(actual ?? "nil")")
        }
    }
}
