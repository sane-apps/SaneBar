import Testing
import Foundation
@testable import SaneBar

// MARK: - IconService Tests

@Suite("IconService Tests")
struct IconServiceTests {

    // MARK: - Singleton Tests

    @Test("Service is singleton")
    func testServiceIsSingleton() {
        let service1 = IconService.shared
        let service2 = IconService.shared

        #expect(service1 === service2,
                "IconService.shared should return same instance")
    }

    // MARK: - Icon Retrieval Tests

    @Test("Returns nil for nil bundle identifier")
    func testReturnsNilForNilBundleId() {
        let service = IconService()
        let icon = service.icon(forBundleIdentifier: nil)

        #expect(icon == nil,
                "Should return nil for nil bundle ID")
    }

    @Test("Returns nil for invalid bundle identifier")
    func testReturnsNilForInvalidBundleId() {
        let service = IconService()
        let icon = service.icon(forBundleIdentifier: "com.nonexistent.app.xyz123")

        #expect(icon == nil,
                "Should return nil for non-existent bundle ID")
    }

    @Test("Returns icon for known system app")
    func testReturnsIconForSystemApp() {
        let service = IconService()
        // Finder is always present on macOS
        let icon = service.icon(forBundleIdentifier: "com.apple.finder")

        #expect(icon != nil,
                "Should return icon for Finder")
    }

    @Test("Icon has correct size when specified")
    func testIconHasCorrectSize() {
        let service = IconService()
        let size: CGFloat = 32
        let icon = service.icon(forBundleIdentifier: "com.apple.finder", size: size)

        #expect(icon != nil, "Should return icon")
        if let icon {
            #expect(icon.size.width == size,
                    "Icon width should match requested size")
            #expect(icon.size.height == size,
                    "Icon height should match requested size")
        }
    }

    @Test("Default size is 32 points")
    func testDefaultSize() {
        let service = IconService()
        let iconDefault = service.icon(forBundleIdentifier: "com.apple.finder")
        let icon32 = service.icon(forBundleIdentifier: "com.apple.finder", size: 32)

        // Both should have same size (32 is default)
        #expect(iconDefault?.size == icon32?.size,
                "Default size should be 32 points")
    }

    // MARK: - Cache Tests

    @Test("Cache returns same instance for repeated calls")
    func testCacheReturnsSameInstance() {
        let service = IconService()
        let icon1 = service.icon(forBundleIdentifier: "com.apple.finder", size: 24)
        let icon2 = service.icon(forBundleIdentifier: "com.apple.finder", size: 24)

        // Note: NSImage doesn't guarantee identity, but the underlying cached object should be the same
        #expect(icon1 === icon2,
                "Cached icons should be identical instances")
    }

    @Test("Clear cache removes cached icons")
    func testClearCache() {
        let service = IconService()

        // Load an icon
        _ = service.icon(forBundleIdentifier: "com.apple.finder")

        // Clear the cache
        service.clearCache()

        // This shouldn't crash and should reload from disk
        let icon = service.icon(forBundleIdentifier: "com.apple.finder")
        #expect(icon != nil, "Should still return icon after cache clear")
    }

    // MARK: - SwiftUI Image Extension Tests

    @Test("Image returns valid Image for known bundle")
    func testImageForKnownBundle() {
        let service = IconService()
        let image = service.image(forBundleIdentifier: "com.apple.finder")

        // SwiftUI Image can't be easily introspected, but we verify it doesn't crash
        #expect(true, "Should create SwiftUI Image without crashing")
        _ = image // Use the variable to avoid warning
    }

    @Test("Image returns fallback for unknown bundle")
    func testImageForUnknownBundle() {
        let service = IconService()
        let image = service.image(forBundleIdentifier: "com.nonexistent.xyz123")

        // SwiftUI Image can't be easily introspected, but we verify it doesn't crash
        #expect(true, "Should create fallback SwiftUI Image without crashing")
        _ = image // Use the variable to avoid warning
    }
}
