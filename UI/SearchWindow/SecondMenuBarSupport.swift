enum IconZone {
    case visible, hidden, alwaysHidden
}

enum SecondMenuBarDropResolver {
    static func sourceForDragID(
        _ sourceID: String,
        visible: [RunningApp],
        hidden: [RunningApp],
        alwaysHidden: [RunningApp]
    ) -> (app: RunningApp, zone: IconZone)? {
        if let app = visible.first(where: { $0.uniqueId == sourceID }) {
            return (app, .visible)
        }
        if let app = hidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .hidden)
        }
        if let app = alwaysHidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .alwaysHidden)
        }
        return nil
    }
}

enum SecondMenuBarLayout {
    static func rowStateLabel(isOn: Bool) -> String {
        isOn ? "On" : "Off"
    }

    static func shouldShowVisibleZone(
        includeVisibleIcons: Bool
    ) -> Bool {
        includeVisibleIcons
    }

    static func shouldShowAlwaysHiddenZone(
        alwaysHiddenZoneEnabled: Bool,
        includeAlwaysHiddenIcons: Bool
    ) -> Bool {
        alwaysHiddenZoneEnabled && includeAlwaysHiddenIcons
    }
}
