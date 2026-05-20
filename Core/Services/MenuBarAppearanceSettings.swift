import Foundation

/// Settings for customizing the menu bar appearance.
struct MenuBarAppearanceSettings: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    var useLiquidGlass: Bool = true
    var tintColor: String = "#000000"
    var tintOpacity: Double = 0.15
    var tintColorDark: String = "#FFFFFF"
    var tintOpacityDark: Double = 0.15
    var hasShadow: Bool = false
    var shadowOpacity: Double = 0.3
    var hasBorder: Bool = false
    var borderColor: String = "#808080"
    var borderWidth: Double = 1.0
    var hasRoundedCorners: Bool = false
    var cornerRadius: Double = 8.0

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case useLiquidGlass
        case tintColor
        case tintOpacity
        case tintColorDark
        case tintOpacityDark
        case hasShadow
        case shadowOpacity
        case hasBorder
        case borderColor
        case borderWidth
        case hasRoundedCorners
        case cornerRadius
    }

    init(
        isEnabled: Bool = false,
        useLiquidGlass: Bool = true,
        tintColor: String = "#000000",
        tintOpacity: Double = 0.15,
        tintColorDark: String = "#FFFFFF",
        tintOpacityDark: Double = 0.15,
        hasShadow: Bool = false,
        shadowOpacity: Double = 0.3,
        hasBorder: Bool = false,
        borderColor: String = "#808080",
        borderWidth: Double = 1.0,
        hasRoundedCorners: Bool = false,
        cornerRadius: Double = 8.0
    ) {
        self.isEnabled = isEnabled
        self.useLiquidGlass = useLiquidGlass
        self.tintColor = Self.normalizedHexColor(tintColor, fallback: "#000000")
        self.tintOpacity = tintOpacity
        self.tintColorDark = Self.normalizedHexColor(tintColorDark, fallback: "#FFFFFF")
        self.tintOpacityDark = tintOpacityDark
        self.hasShadow = hasShadow
        self.shadowOpacity = shadowOpacity
        self.hasBorder = hasBorder
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.hasRoundedCorners = hasRoundedCorners
        self.cornerRadius = cornerRadius
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        useLiquidGlass = try container.decodeIfPresent(Bool.self, forKey: .useLiquidGlass) ?? true
        tintColor = Self.normalizedHexColor(
            try container.decodeIfPresent(String.self, forKey: .tintColor),
            fallback: "#000000"
        )
        tintOpacity = try container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? 0.15
        tintColorDark = Self.normalizedHexColor(
            try container.decodeIfPresent(String.self, forKey: .tintColorDark),
            fallback: "#FFFFFF"
        )
        tintOpacityDark = try container.decodeIfPresent(Double.self, forKey: .tintOpacityDark) ?? 0.15
        hasShadow = try container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? false
        shadowOpacity = try container.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.3
        hasBorder = try container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? false
        borderColor = try container.decodeIfPresent(String.self, forKey: .borderColor) ?? "#808080"
        borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 1.0
        hasRoundedCorners = try container.decodeIfPresent(Bool.self, forKey: .hasRoundedCorners) ?? false
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 8.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(useLiquidGlass, forKey: .useLiquidGlass)
        try container.encode(tintColor, forKey: .tintColor)
        try container.encode(tintOpacity, forKey: .tintOpacity)
        try container.encode(tintColorDark, forKey: .tintColorDark)
        try container.encode(tintOpacityDark, forKey: .tintOpacityDark)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(shadowOpacity, forKey: .shadowOpacity)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(borderColor, forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(hasRoundedCorners, forKey: .hasRoundedCorners)
        try container.encode(cornerRadius, forKey: .cornerRadius)
    }

    static var supportsLiquidGlass: Bool {
        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                return true
            }
            return false
        #else
            return false
        #endif
    }

    private static func normalizedHexColor(_ value: String?, fallback: String) -> String {
        let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        let normalized: String
        switch hex.count {
        case 3:
            normalized = hex.map { "\($0)\($0)" }.joined()
        case 6:
            normalized = hex
        case 8:
            normalized = String(hex.suffix(6))
        default:
            return fallback
        }

        guard normalized.allSatisfy(\.isHexDigit) else { return fallback }
        return "#\(normalized.uppercased())"
    }
}
