import CoreGraphics
import Foundation

enum MenuBarVisibleLaneCrowdingHint {
    static let notification = Notification.Name(
        "MenuBarManager.visibleLaneCrowdingNotification"
    )
    static let bundleIDKey = "bundleID"
    static let menuExtraIDKey = "menuExtraID"
    static let statusItemIndexKey = "statusItemIndex"
    static let separatorRightEdgeKey = "separatorRightEdgeX"
    static let visibleBoundaryKey = "visibleBoundaryX"

    static func postCandidate(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        separatorRightEdgeX: CGFloat,
        visibleBoundaryX: CGFloat?
    ) {
        var userInfo: [String: Any] = [
            bundleIDKey: bundleID,
            separatorRightEdgeKey: Double(separatorRightEdgeX)
        ]
        if let menuExtraId {
            userInfo[menuExtraIDKey] = menuExtraId
        }
        if let statusItemIndex {
            userInfo[statusItemIndexKey] = statusItemIndex
        }
        if let visibleBoundaryX {
            userInfo[visibleBoundaryKey] = Double(visibleBoundaryX)
        }

        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: userInfo
        )
    }
}
