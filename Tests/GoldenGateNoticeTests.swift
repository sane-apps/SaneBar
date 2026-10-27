import Foundation
@testable import SaneBar
import Testing

struct GoldenGateNoticeTests {
    private func settingsFile(_ ids: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sanebar-\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: ["alwaysHiddenPinnedItemIds": ids])
        try data.write(to: url)
        return url
    }

    @Test("Names each always-hidden app once and skips Apple items and unknown apps")
    func namesHiddenApps() throws {
        let url = try settingsFile([
            "com.apple.finder",
            "com.apple.finder::statusItem:1",
            "com.apple.menuextra.battery",
            "com.example.not-installed",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(GoldenGateNotice.hiddenAppNames(settingsURL: url) == ["Finder"])
    }

    @Test("A missing settings file gives no names")
    func missingSettings() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString).json")
        #expect(GoldenGateNotice.hiddenAppNames(settingsURL: url).isEmpty)
    }
}
