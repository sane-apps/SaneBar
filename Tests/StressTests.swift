import Testing
import Foundation
import AppKit
@testable import SaneBar

// MARK: - Mock Infrastructure

@MainActor
class MockStatusItem: StatusItemProtocol {
    var length: CGFloat = 20.0
}

// MARK: - Stress Tests

@Suite("HidingService Stress Tests")
struct HidingServiceStressTests {

    @Test("Rapid toggling maintains consistent state")
    @MainActor
    func testRapidToggling() async {
        let service = HidingService()
        let mockItem = MockStatusItem()
        service.configure(delimiterItem: mockItem)
        
        // Hostile behavior: 50 rapid toggles
        // using TaskGroup to simulate concurrency
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask { @MainActor in
                    // Add random jitter to simulate real-world chaos
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...10_000_000))
                    await service.toggle()
                }
            }
        }
        
        // Allow dust to settle
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Verification
        let length = mockItem.length
        let state = service.state
        
        // Invariant check: Length must match state
        if state == .hidden {
            #expect(length == 10_000, "If state is hidden, length must be 10,000")
        } else {
            #expect(length == 20, "If state is expanded, length must be 20")
        }
    }
    
    @Test("Conflicting show/hide calls resolve safely")
    @MainActor
    func testConflictingActions() async {
        let service = HidingService()
        let mockItem = MockStatusItem()
        service.configure(delimiterItem: mockItem)
        
        await withTaskGroup(of: Void.self) { group in
            // 25 threads trying to SHOW
            for _ in 0..<25 {
                group.addTask { @MainActor in
                    await service.show()
                }
            }
            // 25 threads trying to HIDE
            for _ in 0..<25 {
                group.addTask { @MainActor in
                    await service.hide()
                }
            }
        }
        
        // Verification: Service should not be stuck in animating state
        #expect(!service.isAnimating, "Service should not remain in animating state")
        
        // Invariant check
        if service.state == .hidden {
            #expect(mockItem.length == 10_000)
        } else {
            #expect(mockItem.length == 20)
        }
    }
}
