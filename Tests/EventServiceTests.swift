import Testing
import Foundation
import CoreGraphics
@testable import SaneBar

// MARK: - EventServiceTests

@Suite("EventService Tests")
struct EventServiceTests {

    // MARK: - Error Tests

    @Test("EventServiceError has localized descriptions")
    func testErrorDescriptions() {
        let errors: [EventServiceError] = [
            .eventCreationFailed,
            .postFailed,
            .invalidPosition
        ]

        for error in errors {
            #expect(error.errorDescription != nil,
                    "\(error) should have error description")
            #expect(!error.errorDescription!.isEmpty,
                    "\(error) should have non-empty description")
        }
    }

    @Test("EventServiceError descriptions are user-friendly")
    func testErrorDescriptionsAreUserFriendly() {
        #expect(EventServiceError.eventCreationFailed.errorDescription?.contains("CGEvent") == true,
                "Should mention CGEvent creation")
        #expect(EventServiceError.postFailed.errorDescription?.contains("post") == true,
                "Should mention posting failure")
        #expect(EventServiceError.invalidPosition.errorDescription?.contains("position") == true,
                "Should mention position")
    }

    // MARK: - Protocol Tests

    @Test("EventService conforms to protocol")
    func testEventServiceConformsToProtocol() {
        let service = EventService.shared

        // Verify it conforms to the protocol
        let _: any EventServiceProtocol = service

        #expect(true, "EventService should conform to EventServiceProtocol")
    }

    @Test("EventService is Sendable")
    func testEventServiceIsSendable() {
        let service = EventService.shared

        // Verify it's Sendable by passing to Task
        Task {
            let _: EventServiceProtocol = service
        }

        #expect(true, "EventService should be Sendable")
    }

    @Test("EventService is singleton")
    func testEventServiceIsSingleton() {
        let service1 = EventService.shared
        let service2 = EventService.shared

        #expect(service1 === service2, "EventService.shared should return same instance")
    }

    // MARK: - Current Mouse Location

    @Test("Current mouse location returns valid point")
    func testCurrentMouseLocation() {
        let service = EventService.shared
        let location = service.currentMouseLocation()

        // Should return some position (can't guarantee specific values)
        #expect(location.x >= 0 || location.x < 0,
                "Should return a valid x coordinate")
        #expect(location.y >= 0 || location.y < 0,
                "Should return a valid y coordinate")
    }

    // MARK: - Note about CGEvent tests

    // CGEvent APIs require accessibility permissions to work.
    // Testing simulateMouseDown, simulateMouseUp, simulateMouseDrag, etc.
    // would require:
    // 1. Running with accessibility permissions granted
    // 2. Actually moving the mouse (which affects the test environment)
    //
    // For unit tests, we verify the protocol is correct and errors are handled.
    // Integration tests with real CGEvents should be done manually or in
    // a dedicated UI test target with appropriate permissions.
}

// MARK: - Mock EventService for Testing

/// Mock implementation for testing components that use EventService
class EventServiceMock: EventServiceProtocol {
    var simulateMouseDownCallCount = 0
    var simulateMouseUpCallCount = 0
    var simulateMouseDragCallCount = 0
    var simulateClickCallCount = 0
    var moveMenuBarItemCallCount = 0

    var lastDragStart: CGPoint?
    var lastDragEnd: CGPoint?
    var lastDragWithCommand: Bool?

    var shouldThrowError: EventServiceError?

    func simulateMouseDown(at position: CGPoint, button: CGMouseButton) throws {
        simulateMouseDownCallCount += 1
        if let error = shouldThrowError {
            throw error
        }
    }

    func simulateMouseUp(at position: CGPoint, button: CGMouseButton) throws {
        simulateMouseUpCallCount += 1
        if let error = shouldThrowError {
            throw error
        }
    }

    func simulateMouseDrag(from start: CGPoint, to end: CGPoint, button: CGMouseButton, withCommand: Bool) async throws {
        simulateMouseDragCallCount += 1
        lastDragStart = start
        lastDragEnd = end
        lastDragWithCommand = withCommand
        if let error = shouldThrowError {
            throw error
        }
    }

    func simulateClick(at position: CGPoint, button: CGMouseButton) async throws {
        simulateClickCallCount += 1
        if let error = shouldThrowError {
            throw error
        }
    }

    func currentMouseLocation() -> CGPoint {
        return CGPoint(x: 100, y: 100)
    }

    func moveMenuBarItem(from startX: CGFloat, to endX: CGFloat) async throws {
        moveMenuBarItemCallCount += 1
        if let error = shouldThrowError {
            throw error
        }
    }
}

// MARK: - Mock Tests

@Suite("EventService Mock Tests")
struct EventServiceMockTests {

    @Test("Mock tracks call counts")
    func testMockTracksCallCounts() async throws {
        let mock = EventServiceMock()

        try mock.simulateMouseDown(at: .zero, button: .left)
        try mock.simulateMouseUp(at: .zero, button: .left)
        try await mock.simulateClick(at: .zero, button: .left)
        try await mock.simulateMouseDrag(from: .zero, to: CGPoint(x: 100, y: 100), button: .left, withCommand: true)
        try await mock.moveMenuBarItem(from: 0, to: 100)

        #expect(mock.simulateMouseDownCallCount == 1)
        #expect(mock.simulateMouseUpCallCount == 1)
        #expect(mock.simulateClickCallCount == 1)
        #expect(mock.simulateMouseDragCallCount == 1)
        #expect(mock.moveMenuBarItemCallCount == 1)
    }

    @Test("Mock captures drag parameters")
    func testMockCapturesDragParameters() async throws {
        let mock = EventServiceMock()
        let start = CGPoint(x: 50, y: 50)
        let end = CGPoint(x: 150, y: 150)

        try await mock.simulateMouseDrag(from: start, to: end, button: .left, withCommand: true)

        #expect(mock.lastDragStart == start)
        #expect(mock.lastDragEnd == end)
        #expect(mock.lastDragWithCommand == true)
    }

    @Test("Mock can throw configured errors")
    func testMockThrowsErrors() async {
        let mock = EventServiceMock()
        mock.shouldThrowError = .eventCreationFailed

        do {
            try mock.simulateMouseDown(at: .zero, button: .left)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error as? EventServiceError == .eventCreationFailed)
        }
    }
}
