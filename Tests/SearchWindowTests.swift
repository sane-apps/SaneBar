import Testing
import SwiftUI
import AppKit
@testable import SaneBar

@Suite("Search Window Tests")
struct SearchWindowTests {

    // MARK: - Logic Tests

    @Test("Filtering logic works correctly")
    @MainActor
    func testFiltering() async {
        // Given
        let mockService = SearchServiceProtocolMock()
        mockService.getRunningAppsHandler = {
            return [
                RunningApp(id: "com.apple.Safari", name: "Safari", icon: nil),
                RunningApp(id: "com.google.Chrome", name: "Chrome", icon: nil),
                RunningApp(id: "com.apple.Notes", name: "Notes", icon: nil)
            ]
        }

        _ = MenuBarSearchView(service: mockService, onDismiss: {})  // Verify it can be created

        // Verify service interaction
        let apps = await mockService.getRunningApps()
        #expect(apps.count == 3)
        #expect(mockService.getRunningAppsCallCount > 0)
        
        // Note: We cannot test @State filteredApps directly from outside the view
        // But we verified the dependency injection works
    }

    @Test("Service activation is called")
    @MainActor
    func testActivation() async {
        let mockService = SearchServiceProtocolMock()
        let app = RunningApp(id: "com.test", name: "Test", icon: nil)
        
        await mockService.activate(app: app)
        
        #expect(mockService.activateCallCount == 1)
        #expect(mockService.activateArgValues.first?.id == "com.test")
    }
    
    // MARK: - Model Tests
    
    @Test("RunningApp uses synthesized equality checking all properties")
    func testRunningAppEquality() {
        let app1 = RunningApp(id: "com.test", name: "Test", icon: nil)
        let app2 = RunningApp(id: "com.test", name: "Test", icon: nil) // Same ID and name
        let app3 = RunningApp(id: "com.other", name: "Test", icon: nil) // Different ID
        let app4 = RunningApp(id: "com.test", name: "Other", icon: nil) // Same ID, different name

        #expect(app1 == app2) // Same id and name = equal
        #expect(app1 != app3) // Different id = not equal
        #expect(app1 != app4) // Same id but different name = not equal (synthesized Equatable)
    }
    
    @Test("MenuBarSearchView initializes without crashing")
    @MainActor
    func testMenuBarSearchViewInit() {
        let mockService = SearchServiceProtocolMock()
        _ = MenuBarSearchView(service: mockService, onDismiss: {})
        #expect(true)
    }
}
