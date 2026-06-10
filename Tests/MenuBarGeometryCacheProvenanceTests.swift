@testable import SaneBar
import Testing

@MainActor
struct MenuBarGeometryCacheProvenanceTests {
    @Test("Cached geometry is served under the same display configuration")
    func cachedGeometryServedUnderSameConfiguration() {
        let cache = MenuBarGeometryCache()
        cache.configFingerprintProvider = { "config-A" }

        cache.lastKnownSeparatorX = 1200
        cache.lastKnownMainStatusItemX = 1400

        #expect(cache.lastKnownSeparatorX == 1200)
        #expect(cache.lastKnownMainStatusItemX == 1400)
    }

    @Test("Cached geometry expires when the display configuration changes")
    func cachedGeometryExpiresAcrossConfigurations() {
        let cache = MenuBarGeometryCache()
        var config = "config-A"
        cache.configFingerprintProvider = { config }

        cache.lastKnownSeparatorX = 1200
        cache.lastKnownSeparatorRightEdgeX = 1220
        cache.lastKnownMainStatusItemX = 1400
        cache.lastKnownAlwaysHiddenSeparatorX = 800
        cache.lastKnownAlwaysHiddenSeparatorRightEdgeX = 814

        config = "config-B"

        #expect(cache.lastKnownSeparatorX == nil)
        #expect(cache.lastKnownSeparatorRightEdgeX == nil)
        #expect(cache.lastKnownMainStatusItemX == nil)
        #expect(cache.lastKnownAlwaysHiddenSeparatorX == nil)
        #expect(cache.lastKnownAlwaysHiddenSeparatorRightEdgeX == nil)
    }

    @Test("Geometry cached under a restored configuration is served again")
    func cachedGeometryReturnsWhenConfigurationRestored() {
        let cache = MenuBarGeometryCache()
        var config = "config-A"
        cache.configFingerprintProvider = { config }

        cache.lastKnownSeparatorX = 1200
        config = "config-B"
        #expect(cache.lastKnownSeparatorX == nil)

        config = "config-A"
        #expect(cache.lastKnownSeparatorX == 1200)
    }

    @Test("Writes under a new configuration replace stale entries")
    func writesUnderNewConfigurationReplaceStaleEntries() {
        let cache = MenuBarGeometryCache()
        var config = "config-A"
        cache.configFingerprintProvider = { config }

        cache.lastKnownSeparatorX = 1200
        config = "config-B"
        cache.lastKnownSeparatorX = 900

        #expect(cache.lastKnownSeparatorX == 900)
        config = "config-A"
        #expect(cache.lastKnownSeparatorX == nil)
    }

    @Test("Entry lookup is config-exact")
    func entryLookupIsConfigExact() {
        let entry = MenuBarGeometryCache.Entry(value: 42, configID: "config-A")
        #expect(MenuBarGeometryCache.entryValueIfCurrent(entry, currentConfigID: "config-A") == 42)
        #expect(MenuBarGeometryCache.entryValueIfCurrent(entry, currentConfigID: "config-B") == nil)
        #expect(MenuBarGeometryCache.entryValueIfCurrent(nil, currentConfigID: "config-A") == nil)
    }
}
