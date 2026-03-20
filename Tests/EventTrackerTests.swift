@testable import SaneBar
import XCTest

final class EventTrackerTests: XCTestCase {
    func testTelemetryPayloadIncludesDimensionsAndTargets() {
        let payload = EventTracker.telemetryPayload(
            event: "update_install_started",
            tier: "pro",
            targetVersion: "2.1.33",
            targetBuild: "2133",
            appVersion: "2.1.32",
            build: "2132",
            osVersion: "15.3.1",
            channel: "direct"
        )

        XCTAssertEqual(payload["app"], "sanebar")
        XCTAssertEqual(payload["event"], "update_install_started")
        XCTAssertEqual(payload["app_version"], "2.1.32")
        XCTAssertEqual(payload["build"], "2132")
        XCTAssertEqual(payload["os_version"], "15.3.1")
        XCTAssertEqual(payload["platform"], "macos")
        XCTAssertEqual(payload["channel"], "direct")
        XCTAssertEqual(payload["tier"], "pro")
        XCTAssertEqual(payload["target_version"], "2.1.33")
        XCTAssertEqual(payload["target_build"], "2133")
    }

    func testTelemetryPayloadInfersTierFromEventName() {
        let payload = EventTracker.telemetryPayload(
            event: "app_launch_free",
            tier: nil,
            targetVersion: nil,
            targetBuild: nil,
            appVersion: "2.1.33",
            build: "2133",
            osVersion: "15.3.1",
            channel: "app_store"
        )

        XCTAssertEqual(payload["tier"], "free")
        XCTAssertEqual(payload["channel"], "app_store")
        XCTAssertNil(payload["target_version"])
        XCTAssertNil(payload["target_build"])
    }
}
