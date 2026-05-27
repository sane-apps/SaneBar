import Foundation

enum GeneralSettingsBrowseLeftClickMode: String, CaseIterable, Identifiable {
    case toggleHidden
    case openBrowseIcons

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .toggleHidden: "Toggle Hidden"
        case .openBrowseIcons: "Open Browse"
        }
    }
}

enum GeneralSettingsSecondMenuBarPreset: String, CaseIterable, Identifiable {
    case minimal
    case balanced
    case power

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .minimal: "Hidden Row"
        case .balanced: "Hidden + Visible"
        case .power: "All Rows"
        }
    }

    static func resolve(showVisible: Bool, showAlwaysHidden: Bool) -> Self {
        switch (showVisible, showAlwaysHidden) {
        case (false, false):
            .minimal
        case (true, false):
            .balanced
        case (true, true), (false, true):
            .power
        }
    }
}
