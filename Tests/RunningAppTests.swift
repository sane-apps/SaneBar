import Foundation
import Testing

struct RunningAppTests {
    @Test("RunningApp caches expensive NSRunningApplication metadata")
    func testRunningAppCachesMetadata() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Core/Models/RunningApp.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(source.contains("private struct CachedMetadata"))
        #expect(source.contains("private static let metadataCacheLock = NSLock()"))
        #expect(source.contains("private static var metadataCache: [String: CachedMetadata] = [:]"))
        #expect(source.contains("private static func cachedMetadata("))
        #expect(source.contains("let metadata = Self.cachedMetadata("))
    }
}
