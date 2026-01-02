import AppKit
import SwiftUI

// MARK: - IconServiceProtocol

/// @mockable
protocol IconServiceProtocol: Sendable {
    func icon(forBundleIdentifier bundleId: String?) -> NSImage?
    func icon(forBundleIdentifier bundleId: String?, size: CGFloat) -> NSImage?
}

// MARK: - IconService

/// Service for fetching app icons from bundle identifiers
final class IconService: IconServiceProtocol, @unchecked Sendable {

    // MARK: - Singleton

    static let shared = IconService()

    // MARK: - Cache

    private let cache = NSCache<NSString, NSImage>()

    // MARK: - Initialization

    init() {
        cache.countLimit = 100
    }

    // MARK: - Icon Retrieval

    /// Get icon for a bundle identifier
    /// - Parameter bundleId: The bundle identifier (e.g., "com.apple.Safari")
    /// - Returns: The app icon, or nil if not found
    func icon(forBundleIdentifier bundleId: String?) -> NSImage? {
        icon(forBundleIdentifier: bundleId, size: 32)
    }

    /// Get icon for a bundle identifier at a specific size
    /// - Parameters:
    ///   - bundleId: The bundle identifier
    ///   - size: The desired icon size in points
    /// - Returns: The app icon at the specified size, or nil if not found
    func icon(forBundleIdentifier bundleId: String?, size: CGFloat) -> NSImage? {
        guard let bundleId else { return nil }

        // Check cache first
        let cacheKey = "\(bundleId)_\(size)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Get app URL from bundle identifier
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }

        // Get icon from app path
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        // Resize to requested size
        let resized = resizeIcon(icon, to: size)

        // Cache the result
        cache.setObject(resized, forKey: cacheKey)

        return resized
    }

    // MARK: - Helpers

    private func resizeIcon(_ icon: NSImage, to size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)

        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high

        icon.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: icon.size),
            operation: .copy,
            fraction: 1.0
        )

        resizedImage.unlockFocus()

        return resizedImage
    }

    /// Clear the icon cache
    func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - SwiftUI Image Extension

extension IconService {
    /// Get a SwiftUI Image for a bundle identifier
    /// - Parameters:
    ///   - bundleId: The bundle identifier
    ///   - size: The desired size
    /// - Returns: A SwiftUI Image, or a placeholder if not found
    func image(forBundleIdentifier bundleId: String?, size: CGFloat = 24) -> Image {
        if let nsImage = icon(forBundleIdentifier: bundleId, size: size) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "app.badge")
    }
}
