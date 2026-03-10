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

    @Test("Builds synthetic third-party identifier from label when explicitly allowed")
    func buildsSyntheticThirdPartyIdentifierFromLabel() {
        let id = AccessibilityService.canonicalMenuExtraIdentifier(
            ownerBundleId: "at.obdev.littlesnitch.agent",
            rawIdentifier: nil,
            rawLabel: "Little Snitch",
            width: 18,
            allowThirdPartyLabelFallback: true
        )
        #expect(id == "at.obdev.littlesnitch.agent.menuextra.little-snitch")
    }

    @Test("Third-party top-bar fallback rejects ordinary app menu rows")
    func thirdPartyTopBarFallbackRejectsStandardAppMenuRows() {
        #expect(
            !AccessibilityService.shouldAcceptThirdPartyTopBarFallbackItem(
                rawIdentifier: "_NS:1118",
                rawSubrole: nil
            )
        )
        #expect(
            !AccessibilityService.shouldAcceptThirdPartyTopBarFallbackItem(
                rawIdentifier: nil,
                rawSubrole: nil
            )
        )
    }

    @Test("Third-party top-bar fallback keeps real helper-host identifiers")
    func thirdPartyTopBarFallbackKeepsRealHelperIdentifiers() {
        #expect(
            AccessibilityService.shouldAcceptThirdPartyTopBarFallbackItem(
                rawIdentifier: "com.obdev.LittleSnitchUIAgent-Item-0",
                rawSubrole: nil
            )
        )
        #expect(
            AccessibilityService.shouldAcceptThirdPartyTopBarFallbackItem(
                rawIdentifier: nil,
                rawSubrole: "AXMenuExtra"
            )
        )
    }

    @Test("Scanned Spotlight item normalizes to canonical menu extra identifier")
    func scannedSpotlightItemUsesCanonicalIdentifier() {
        let id = AccessibilityService.resolvedScannedMenuExtraIdentifier(
            ownerBundleId: "com.apple.Spotlight",
            axIdentifier: nil,
            rawTitle: "Spotlight",
            rawDescription: "Search",
            width: 32
        )
        #expect(id == "com.apple.menuextra.spotlight")
    }

    @Test("Scanned third-party item keeps nil when no identifier is exposed")
    func scannedThirdPartyItemDoesNotInventIdentifierWithoutFallback() {
        let id = AccessibilityService.resolvedScannedMenuExtraIdentifier(
            ownerBundleId: "eu.exelban.Stats",
            axIdentifier: nil,
            rawTitle: "Stats",
            rawDescription: nil,
            width: 24
        )
        #expect(id == nil)
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
            Case(
                ownerBundleId: "at.obdev.littlesnitch.agent",
                rawIdentifier: nil,
                rawLabel: "Little Snitch",
                width: 18,
                expected: "at.obdev.littlesnitch.agent.menuextra.little-snitch",
                name: "Little Snitch current helper can synthesize identifier from label"
            ),
        ]

        for item in cases {
            let actual = AccessibilityService.canonicalMenuExtraIdentifier(
                ownerBundleId: item.ownerBundleId,
                rawIdentifier: item.rawIdentifier,
                rawLabel: item.rawLabel,
                width: item.width,
                allowThirdPartyLabelFallback: item.ownerBundleId == "at.obdev.littlesnitch.agent"
            )
            #expect(actual == item.expected, "\(item.name): expected \(item.expected ?? "nil"), got \(actual ?? "nil")")
        }
    }

    @Test("Bundle fallback smoke matrix for helper-hosted extras")
    func bundleFallbackSmokeMatrix() {
        let cases: [(raw: String?, expected: String?, name: String)] = [
            ("com.obdev.LittleSnitchUIAgent-Item-0", "com.obdev.LittleSnitchUIAgent", "Little Snitch AX item"),
            ("com.obdev.LittleSnitchUIAgent", "com.obdev.LittleSnitchUIAgent", "Little Snitch direct bundle"),
            ("at.obdev.littlesnitch.agent-Item-0", "at.obdev.littlesnitch.agent", "Little Snitch current AX item"),
            ("at.obdev.littlesnitch.agent", "at.obdev.littlesnitch.agent", "Little Snitch current direct bundle"),
            ("com.apple.menuextra.clock", nil, "Apple menu extra should not map to app bundle"),
            ("invalid identifier with spaces", nil, "Invalid identifier rejected"),
        ]

        for item in cases {
            let actual = AccessibilityService.bundleIdentifierFallback(fromAXIdentifier: item.raw)
            #expect(actual == item.expected, "\(item.name): expected \(item.expected ?? "nil"), got \(actual ?? "nil")")
        }
    }
}
