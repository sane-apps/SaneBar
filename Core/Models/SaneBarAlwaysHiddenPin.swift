import Foundation

enum SaneBarAlwaysHiddenPin: Hashable {
    case menuExtra(String)
    case axId(bundleId: String, axId: String)
    case statusItem(bundleId: String, index: Int)
    case bundleId(String)

    var bundleId: String? {
        switch self {
        case .menuExtra:
            nil
        case let .axId(bundleId, _):
            bundleId
        case let .statusItem(bundleId, _):
            bundleId
        case let .bundleId(bundleId):
            bundleId
        }
    }
}

extension MenuBarManager {
    typealias AlwaysHiddenPin = SaneBarAlwaysHiddenPin
}
