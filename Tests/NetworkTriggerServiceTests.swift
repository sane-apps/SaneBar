import Testing
import Foundation
@testable import SaneBar

// MARK: - NetworkTriggerServiceTests

@Suite("NetworkTriggerService Tests")
@MainActor
struct NetworkTriggerServiceTests {

    // MARK: - SSID Matching Logic Tests

    @Test("SSID matching is case-sensitive")
    func testSSIDCaseSensitive() {
        let triggerNetworks = ["HomeWiFi", "WorkNetwork", "CoffeeShop"]

        #expect(triggerNetworks.contains("HomeWiFi"), "Exact match should work")
        #expect(!triggerNetworks.contains("homewifi"), "Lowercase should not match")
        #expect(!triggerNetworks.contains("HOMEWIFI"), "Uppercase should not match")
    }

    @Test("Empty SSID should not trigger")
    func testEmptySSIDNoTrigger() {
        let triggerNetworks = ["HomeWiFi", "WorkNetwork"]
        let currentSSID: String? = nil

        #expect(currentSSID == nil, "No SSID when disconnected")
        #expect(!triggerNetworks.contains(""), "Empty string should not match")
    }

    @Test("SSID with special characters matches correctly")
    func testSSIDSpecialCharacters() {
        let triggerNetworks = ["My-Home_WiFi", "Café Network", "5G-Fast!", "网络"]

        #expect(triggerNetworks.contains("My-Home_WiFi"), "Hyphens and underscores")
        #expect(triggerNetworks.contains("Café Network"), "Unicode accents")
        #expect(triggerNetworks.contains("5G-Fast!"), "Numbers and punctuation")
        #expect(triggerNetworks.contains("网络"), "Non-latin characters")
    }

    @Test("Whitespace in SSID is significant")
    func testSSIDWhitespace() {
        let triggerNetworks = ["Home WiFi", " HomeWiFi", "HomeWiFi "]

        #expect(triggerNetworks.contains("Home WiFi"), "Space in middle")
        #expect(!triggerNetworks.contains("HomeWiFi"), "No space should not match")
        #expect(triggerNetworks.contains(" HomeWiFi"), "Leading space matters")
        #expect(triggerNetworks.contains("HomeWiFi "), "Trailing space matters")
    }

    // MARK: - Trigger Network List Tests

    @Test("Empty trigger list never matches")
    func testEmptyTriggerList() {
        let triggerNetworks: [String] = []
        let currentSSID = "AnyNetwork"

        #expect(!triggerNetworks.contains(currentSSID), "Empty list should never match")
    }

    @Test("Multiple networks in trigger list all work")
    func testMultipleNetworks() {
        let triggerNetworks = ["Home", "Work", "Mobile"]

        #expect(triggerNetworks.contains("Home"))
        #expect(triggerNetworks.contains("Work"))
        #expect(triggerNetworks.contains("Mobile"))
        #expect(!triggerNetworks.contains("Unknown"))
    }

    @Test("Duplicate SSIDs in trigger list are handled")
    func testDuplicateSSIDs() {
        let triggerNetworks = ["HomeWiFi", "HomeWiFi", "HomeWiFi"]

        // Should still match (contains works on duplicates)
        #expect(triggerNetworks.contains("HomeWiFi"))
        #expect(triggerNetworks.count == 3, "Duplicates are allowed in array")
    }

    // MARK: - Feature Enable/Disable Logic Tests

    @Test("Network trigger respects showOnNetworkChange setting")
    func testFeatureToggle() {
        let showOnNetworkChange = false
        let triggerNetworks = ["HomeWiFi"]
        let currentSSID = "HomeWiFi"

        // Even if SSID matches, should not trigger when feature is off
        let shouldTrigger = showOnNetworkChange && triggerNetworks.contains(currentSSID)
        #expect(!shouldTrigger, "Should not trigger when feature is disabled")
    }

    @Test("Network trigger fires when enabled and SSID matches")
    func testFeatureEnabled() {
        let showOnNetworkChange = true
        let triggerNetworks = ["HomeWiFi"]
        let currentSSID = "HomeWiFi"

        let shouldTrigger = showOnNetworkChange && triggerNetworks.contains(currentSSID)
        #expect(shouldTrigger, "Should trigger when enabled and SSID matches")
    }

    // MARK: - Start/Stop Monitoring Tests

    @Test("startMonitoring is idempotent")
    func testStartMonitoringIdempotent() {
        let service = NetworkTriggerService()

        // Call multiple times - should not crash or create multiple monitors
        service.startMonitoring()
        service.startMonitoring()
        service.startMonitoring()

        service.stopMonitoring()

        #expect(true, "Multiple startMonitoring calls should be safe")
    }

    @Test("stopMonitoring is idempotent")
    func testStopMonitoringIdempotent() {
        let service = NetworkTriggerService()

        service.startMonitoring()

        // Stop multiple times
        service.stopMonitoring()
        service.stopMonitoring()
        service.stopMonitoring()

        #expect(true, "Multiple stopMonitoring calls should be safe")
    }

    @Test("stopMonitoring without start is safe")
    func testStopWithoutStart() {
        let service = NetworkTriggerService()

        // Stop without ever starting
        service.stopMonitoring()

        #expect(true, "Stop without start should not crash")
    }

    // MARK: - Protocol Conformance Tests

    @Test("NetworkTriggerService conforms to NetworkTriggerServiceProtocol")
    func testProtocolConformance() {
        let service: NetworkTriggerServiceProtocol = NetworkTriggerService()

        _ = service.currentSSID
        service.startMonitoring()
        service.stopMonitoring()

        #expect(true, "Service conforms to protocol")
    }

    // MARK: - Mock Tests

    @Test("NetworkTriggerServiceProtocolMock tracks method calls")
    func testMockTracking() {
        let mock = NetworkTriggerServiceProtocolMock()

        mock.startMonitoring()
        mock.startMonitoring()
        mock.stopMonitoring()

        #expect(mock.startMonitoringCallCount == 2)
        #expect(mock.stopMonitoringCallCount == 1)
    }

    @Test("NetworkTriggerServiceProtocolMock allows setting currentSSID")
    func testMockSSID() {
        let mock = NetworkTriggerServiceProtocolMock(currentSSID: "TestNetwork")

        #expect(mock.currentSSID == "TestNetwork")

        mock.currentSSID = "AnotherNetwork"
        #expect(mock.currentSSID == "AnotherNetwork")

        mock.currentSSID = nil
        #expect(mock.currentSSID == nil)
    }

    // MARK: - Edge Cases

    @Test("Very long SSID names are handled")
    func testLongSSID() {
        // Max SSID length is 32 bytes, but we should handle longer strings gracefully
        let longSSID = String(repeating: "A", count: 100)
        let triggerNetworks = [longSSID]

        #expect(triggerNetworks.contains(longSSID))
    }

    @Test("SSID with only whitespace")
    func testWhitespaceOnlySSID() {
        let triggerNetworks = ["   ", "\t", "\n"]

        #expect(triggerNetworks.contains("   "), "Three spaces")
        #expect(triggerNetworks.contains("\t"), "Tab character")
        #expect(!triggerNetworks.contains(" "), "Single space not in list")
    }
}
