import Foundation
import os.log

private let eventLogger = Logger(subsystem: "com.sanebar.app", category: "EventTracker")

/// Anonymous aggregate event tracking via sane-dist Worker.
/// Fire-and-forget, silent failure — must never affect app behavior.
enum EventTracker {
    private static let endpoint = "https://dist.saneapps.com/api/event"

    static func log(_ event: String) async {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "app", value: "sanebar"),
            URLQueryItem(name: "event", value: event)
        ]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
        eventLogger.debug("Event logged: \(event)")
    }
}
