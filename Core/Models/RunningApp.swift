import AppKit

// MARK: - AppCategory (Smart Groups)

/// App categories matching Apple's Launchpad categories exactly
enum AppCategory: String, CaseIterable, Sendable {
    // Apple Launchpad categories (in their display order)
    case productivity = "Productivity"
    case social = "Social"
    case utilities = "Utilities"
    case creativity = "Creativity"
    case entertainment = "Entertainment"
    case infoAndReading = "Information & Reading"
    case finance = "Finance"
    case shopping = "Shopping"
    case healthAndFitness = "Health & Fitness"
    case travel = "Travel"
    case games = "Games"
    case foodAndDrinks = "Food & Drinks"
    // Additional categories for menu bar apps
    case developerTools = "Developer Tools"
    case system = "System"
    case other = "Other"

    /// Map LSApplicationCategoryType to our smart category
    static func from(categoryType: String?) -> AppCategory {
        guard let type = categoryType?.lowercased() else { return .other }

        // Map Apple's category identifiers to Launchpad groups
        if type.contains("productivity") || type.contains("business") { return .productivity }
        if type.contains("social") { return .social }
        if type.contains("utilities") { return .utilities }
        if type.contains("graphics") || type.contains("design") || type.contains("photo") ||
           type.contains("video") || type.contains("music") { return .creativity }
        if type.contains("entertainment") || type.contains("lifestyle") { return .entertainment }
        if type.contains("news") || type.contains("reference") || type.contains("education") ||
           type.contains("weather") || type.contains("book") { return .infoAndReading }
        if type.contains("finance") { return .finance }
        if type.contains("shopping") { return .shopping }
        if type.contains("health") || type.contains("fitness") { return .healthAndFitness }
        if type.contains("travel") || type.contains("navigation") { return .travel }
        if type.contains("games") || type.contains("game") { return .games }
        if type.contains("food") || type.contains("drink") { return .foodAndDrinks }
        if type.contains("developer") { return .developerTools }

        return .other
    }

    /// Icon for the category (SF Symbol)
    var iconName: String {
        switch self {
        case .productivity: return "checkmark.circle"
        case .social: return "bubble.left.and.bubble.right"
        case .utilities: return "wrench.and.screwdriver"
        case .creativity: return "paintbrush"
        case .entertainment: return "tv"
        case .infoAndReading: return "book"
        case .finance: return "dollarsign.circle"
        case .shopping: return "cart"
        case .healthAndFitness: return "heart"
        case .travel: return "airplane"
        case .games: return "gamecontroller"
        case .foodAndDrinks: return "fork.knife"
        case .developerTools: return "hammer"
        case .system: return "gearshape"
        case .other: return "square.grid.2x2"
        }
    }
}

// MARK: - RunningApp Model

/// Represents a running app that might have a menu bar icon
/// Note: @unchecked Sendable because NSImage is thread-safe but not marked Sendable
struct RunningApp: Identifiable, Hashable, @unchecked Sendable {
    enum Policy: String, Codable, Sendable {
        case regular
        case accessory
        case prohibited
        case unknown
    }

    /// Owning app/process bundle identifier (e.g. com.apple.systemuiserver).
    /// This is the identifier we should use for activation/move operations.
    let bundleId: String
    let name: String
    let icon: NSImage?
    /// Pre-calculated thumbnail for efficient UI rendering
    let iconThumbnail: NSImage?
    let policy: Policy
    let category: AppCategory
    let xPosition: CGFloat?
    let width: CGFloat?

    /// For system-owned menu extras (Control Center/SystemUIServer): the specific menu extra identifier
    /// e.g., "com.apple.menuextra.battery", "com.apple.menuextra.wifi"
    ///
    /// For some third-party status items, this may also contain a stable AX identifier if provided.
    let menuExtraIdentifier: String?

    /// For non-system apps that expose multiple status items under the same bundle id,
    /// this identifies which AX child we represent.
    let statusItemIndex: Int?

    /// Whether this is an individual system menu extra item (Battery, Wi‑Fi, etc.)
    var isControlCenterItem: Bool {
        (bundleId == "com.apple.controlcenter" || bundleId == "com.apple.systemuiserver") && (menuExtraIdentifier?.hasPrefix("com.apple.menuextra.") ?? false)
    }

    /// Unique identifier for deduplication/UI identity - uses menuExtraIdentifier if present
    var uniqueId: String {
        if let menuExtraIdentifier {
            // Preserve legacy identity for Apple menu extras so groups/tiles remain stable.
            if menuExtraIdentifier.hasPrefix("com.apple.menuextra.") {
                return menuExtraIdentifier
            }
            // Third-party AX identifiers are not guaranteed to be globally unique.
            return "\(bundleId)::axid:\(menuExtraIdentifier)"
        }
        if let statusItemIndex {
            return "\(bundleId)::statusItem:\(statusItemIndex)"
        }
        return bundleId
    }

    /// SwiftUI identity: must be unique per tile.
    /// For menu extras this is the `uniqueId`; for normal apps it's the bundle id.
    var id: String { uniqueId }

    /// A resized thumbnail of the app icon for efficient grid rendering.
    /// This is generated on-demand and should ideally be cached.
    func thumbnail(size: CGFloat) -> NSImage? {
        guard let icon = icon else { return nil }
        
        // If the icon is already a template (SFSymbol), just return it
        if icon.isTemplate { return icon }

        let targetSize = NSSize(width: size, height: size)
        
        // Check if we already have a representation of this size
        if icon.size == targetSize { return icon }

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        thumbnail.isTemplate = icon.isTemplate
        
        return thumbnail
    }

    /// Return a copy of this app with a pre-calculated thumbnail
    func withThumbnail(size: CGFloat) -> RunningApp {
        if let thumbnail = self.thumbnail(size: size) {
            // Since RunningApp is a struct, we need to use a private init or make it a var.
            // But let's just use a specialized init for this.
            return RunningApp(
                id: bundleId,
                name: name,
                icon: icon,
                iconThumbnail: thumbnail,
                policy: policy,
                category: category,
                menuExtraIdentifier: menuExtraIdentifier,
                statusItemIndex: statusItemIndex,
                xPosition: xPosition,
                width: width
            )
        }
        return self
    }

    private init(id: String, name: String, icon: NSImage?, iconThumbnail: NSImage?, policy: Policy, category: AppCategory, menuExtraIdentifier: String?, statusItemIndex: Int?, xPosition: CGFloat?, width: CGFloat?) {
        self.bundleId = id
        self.name = name
        self.icon = icon
        self.iconThumbnail = iconThumbnail
        self.policy = policy
        self.category = category
        self.menuExtraIdentifier = menuExtraIdentifier
        self.statusItemIndex = statusItemIndex
        self.xPosition = xPosition
        self.width = width
    }

    init(id: String, name: String, icon: NSImage?, policy: Policy = .regular, category: AppCategory = .other, menuExtraIdentifier: String? = nil, statusItemIndex: Int? = nil, xPosition: CGFloat? = nil, width: CGFloat? = nil) {
        self.bundleId = id
        self.name = name
        self.icon = icon
        self.iconThumbnail = nil // Will be set by specialized inits if needed
        self.policy = policy
        self.category = category
        self.menuExtraIdentifier = menuExtraIdentifier
        self.statusItemIndex = statusItemIndex
        self.xPosition = xPosition
        self.width = width
    }

    /// Create a Control Center item with an SF Symbol icon
    static func controlCenterItem(name: String, identifier: String, xPosition: CGFloat? = nil, width: CGFloat? = nil) -> RunningApp {
        menuExtraItem(ownerBundleId: "com.apple.controlcenter", name: name, identifier: identifier, xPosition: xPosition, width: width)
    }

    /// Create a system-owned menu extra item (e.g. Wi‑Fi, Battery) with an SF Symbol icon.
    /// This is used to represent individual items owned by system processes like Control Center or SystemUIServer.
    static func menuExtraItem(ownerBundleId: String, name: String, identifier: String, xPosition: CGFloat? = nil, width: CGFloat? = nil) -> RunningApp {
        let resolvedName = displayNameForMenuExtra(identifier) ?? sanitizeMenuExtraLabel(name) ?? (identifier.components(separatedBy: ".").last ?? "Menu Extra")
        let symbolName = iconForMenuExtra(identifier)

        var icon: NSImage?
        if let baseIcon = NSImage(systemSymbolName: symbolName, accessibilityDescription: resolvedName) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            icon = baseIcon.withSymbolConfiguration(config)
        }

        if icon == nil {
            icon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: resolvedName)
        }

        return RunningApp(
            id: ownerBundleId,
            name: resolvedName,
            icon: icon,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: identifier,
            statusItemIndex: nil,
            xPosition: xPosition,
            width: width
        )
    }

    private static func displayNameForMenuExtra(_ identifier: String) -> String? {
        switch identifier {
        case "com.apple.menuextra.battery": return "Battery"
        case "com.apple.menuextra.wifi": return "Wi-Fi"
        case "com.apple.menuextra.bluetooth": return "Bluetooth"
        case "com.apple.menuextra.clock": return "Clock"
        case "com.apple.menuextra.airdrop": return "AirDrop"
        case "com.apple.menuextra.focusmode": return "Focus"
        case "com.apple.menuextra.controlcenter": return "Control Center"
        case "com.apple.menuextra.display": return "Display"
        case "com.apple.menuextra.sound": return "Sound"
        case "com.apple.menuextra.airplay": return "AirPlay"
        default:
            return nil
        }
    }

    private static func sanitizeMenuExtraLabel(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Remove control characters and SF Symbols private-use glyphs.
        func isControlScalar(_ value: UInt32) -> Bool {
            value < 0x20 || (value >= 0x7F && value <= 0x9F)
        }

        func isPrivateUseScalar(_ value: UInt32) -> Bool {
            // Unicode Private Use Areas
            // - BMP:          U+E000 ... U+F8FF
            // - Plane 15:     U+F0000 ... U+FFFFD
            // - Plane 16:     U+100000 ... U+10FFFD
            (value >= 0xE000 && value <= 0xF8FF) ||
            (value >= 0xF0000 && value <= 0xFFFFD) ||
            (value >= 0x100000 && value <= 0x10FFFD)
        }

        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(trimmed.unicodeScalars.count)

        for scalar in trimmed.unicodeScalars {
            let v = scalar.value
            if isControlScalar(v) || isPrivateUseScalar(v) { continue }
            scalars.append(scalar)
        }

        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Map menu extra identifiers to SF Symbols
    private static func iconForMenuExtra(_ identifier: String) -> String {
        switch identifier {
        case "com.apple.menuextra.battery": return "battery.100"
        case "com.apple.menuextra.wifi": return "wifi"
        case "com.apple.menuextra.bluetooth": return "bluetooth"
        case "com.apple.menuextra.clock": return "clock"
        case "com.apple.menuextra.airdrop": return "airdrop"
        case "com.apple.menuextra.focusmode": return "moon.fill"
        case "com.apple.menuextra.controlcenter": return "switch.2"
        case "com.apple.menuextra.display": return "display"
        case "com.apple.menuextra.sound": return "speaker.wave.2"
        case "com.apple.menuextra.airplay": return "airplayvideo"
        default: return "circle.grid.2x2"
        }
    }

    init(app: NSRunningApplication, statusItemIndex: Int? = nil, menuExtraIdentifier: String? = nil, xPosition: CGFloat? = nil, width: CGFloat? = nil) {
        self.bundleId = app.bundleIdentifier ?? UUID().uuidString
        self.name = app.localizedName ?? "Unknown"
        self.icon = app.icon
        self.iconThumbnail = nil
        self.xPosition = xPosition
        self.width = width

        switch app.activationPolicy {
        case .regular:
            self.policy = .regular
        case .accessory:
            self.policy = .accessory
        case .prohibited:
            self.policy = .prohibited
        @unknown default:
            self.policy = .unknown
        }

        // Detect category from app bundle
        self.category = Self.detectCategory(for: app)

        // Regular apps may still provide a stable AX identifier per status item.
        self.menuExtraIdentifier = menuExtraIdentifier
        self.statusItemIndex = statusItemIndex
    }

    /// Detect app category from bundle's Info.plist
    private static func detectCategory(for app: NSRunningApplication) -> AppCategory {
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName?.lowercased() ?? ""

        // MARK: - Apple System Apps
        if bundleId.hasPrefix("com.apple.") {
            // System utilities (Control Center, Finder, etc.)
            if bundleId.contains("controlcenter") || bundleId.contains("SystemPreferences") ||
               bundleId.contains("Finder") || bundleId.contains("systempreferences") ||
               bundleId.contains("Spotlight") || bundleId.contains("SystemUIServer") ||
               bundleId.contains("dock") || bundleId.contains("loginwindow") {
                return .system
            }
            // Creativity (Music, Photos, GarageBand, etc.)
            if bundleId.contains("Music") || bundleId.contains("iTunes") ||
               bundleId.contains("Photos") || bundleId.contains("GarageBand") ||
               bundleId.contains("iMovie") || bundleId.contains("FinalCut") {
                return .creativity
            }
            // Productivity
            if bundleId.contains("Safari") || bundleId.contains("Mail") ||
               bundleId.contains("Calendar") || bundleId.contains("Notes") ||
               bundleId.contains("Reminders") || bundleId.contains("Pages") ||
               bundleId.contains("Numbers") || bundleId.contains("Keynote") {
                return .productivity
            }
            // Social
            if bundleId.contains("Messages") || bundleId.contains("FaceTime") {
                return .social
            }
            // Information & Reading
            if bundleId.contains("News") || bundleId.contains("Weather") ||
               bundleId.contains("Books") || bundleId.contains("Stocks") {
                return .infoAndReading
            }
            // Developer Tools
            if bundleId.contains("Xcode") || bundleId.contains("Terminal") ||
               bundleId.contains("Instruments") || bundleId.contains("FileMerge") {
                return .developerTools
            }
            // Default Apple apps to System
            return .system
        }

        // MARK: - Common Third-Party Menu Bar Apps

        // Developer Tools
        if bundleId.contains("github") || bundleId.contains("gitlab") ||
           bundleId.contains("docker") || bundleId.contains("iterm") ||
           bundleId.contains("vscode") || bundleId.contains("jetbrains") ||
           bundleId.contains("sublime") || bundleId.contains("tower") ||
           bundleId.contains("cursor") || bundleId.contains("fig") ||
           appName.contains("xcode") || appName.contains("terminal") {
            return .developerTools
        }

        // Utilities (launchers, clipboard managers, window managers, etc.)
        if bundleId.contains("1password") || bundleId.contains("bitwarden") ||
           bundleId.contains("lastpass") || bundleId.contains("dashlane") ||
           bundleId.contains("dropbox") || bundleId.contains("google.drive") ||
           bundleId.contains("onedrive") || bundleId.contains("icloud") ||
           bundleId.contains("alfred") || bundleId.contains("raycast") ||
           bundleId.contains("bartender") || bundleId.contains("cleanmymac") ||
           bundleId.contains("amphetamine") || bundleId.contains("caffeine") ||
           bundleId.contains("rectangle") || bundleId.contains("magnet") ||
           bundleId.contains("clipboard") || bundleId.contains("paste") ||
           bundleId.contains("vpn") || bundleId.contains("nordvpn") ||
           bundleId.contains("expressvpn") || bundleId.contains("mullvad") ||
           bundleId.contains("wireguard") || bundleId.contains("tunnelblick") ||
           bundleId.contains("littlesnitch") || appName.contains("vpn") {
            return .utilities
        }

        // Productivity (note-taking, task management, office apps)
        if bundleId.contains("notion") || bundleId.contains("obsidian") ||
           bundleId.contains("todoist") || bundleId.contains("things") ||
           bundleId.contains("omnifocus") || bundleId.contains("fantastical") ||
           bundleId.contains("spark") || bundleId.contains("airmail") {
            return .productivity
        }

        // Social / Communication
        if bundleId.contains("slack") || bundleId.contains("discord") ||
           bundleId.contains("zoom") || bundleId.contains("teams") ||
           bundleId.contains("skype") || bundleId.contains("telegram") ||
           bundleId.contains("whatsapp") || bundleId.contains("signal") ||
           bundleId.contains("messenger") || appName.contains("chat") {
            return .social
        }

        // Creativity (music, video, design)
        if bundleId.contains("spotify") || bundleId.contains("soundcloud") ||
           bundleId.contains("audiohijack") || bundleId.contains("airfoil") ||
           bundleId.contains("adobe") || bundleId.contains("sketch") ||
           bundleId.contains("figma") || bundleId.contains("affinity") ||
           appName.contains("music") || appName.contains("audio") {
            return .creativity
        }

        // Finance
        if bundleId.contains("coinbase") || bundleId.contains("exodus") ||
           bundleId.contains("ledger") || bundleId.contains("crypto") ||
           appName.contains("wallet") || appName.contains("bitcoin") ||
           appName.contains("trading") || appName.contains("stock") {
            return .finance
        }

        // Health & Fitness
        if bundleId.contains("strava") || bundleId.contains("fitness") ||
           bundleId.contains("workout") || appName.contains("health") {
            return .healthAndFitness
        }

        // Try to read LSApplicationCategoryType from bundle
        if let bundleURL = app.bundleURL,
           let bundle = Bundle(url: bundleURL),
           let categoryType = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            return AppCategory.from(categoryType: categoryType)
        }

        return .other
    }
}
