import AppKit


enum AppCategory: String, CaseIterable, Sendable {
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
    case developerTools = "Developer Tools"
    case system = "System"
    case other = "Other"

    static func from(categoryType: String?) -> AppCategory {
        guard let type = categoryType?.lowercased() else { return .other }

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

    var iconName: String {
        switch self {
        case .productivity: "checkmark.circle"
        case .social: "bubble.left.and.bubble.right"
        case .utilities: "wrench.and.screwdriver"
        case .creativity: "paintbrush"
        case .entertainment: "tv"
        case .infoAndReading: "book"
        case .finance: "dollarsign.circle"
        case .shopping: "cart"
        case .healthAndFitness: "heart"
        case .travel: "airplane"
        case .games: "gamecontroller"
        case .foodAndDrinks: "fork.knife"
        case .developerTools: "hammer"
        case .system: "gearshape"
        case .other: "square.grid.2x2"
        }
    }
}


struct RunningApp: Identifiable, Hashable, @unchecked Sendable {
    enum Policy: String, Codable, Sendable {
        case regular
        case accessory
        case prohibited
        case unknown
    }

    private struct CachedMetadata {
        let name: String
        let icon: NSImage?
        let category: AppCategory
        var lastAccess: UInt64
    }

    private static let metadataCacheLock = NSLock()
    private static let metadataCacheMaxEntries = 128
    private static nonisolated(unsafe) var metadataCacheClock: UInt64 = 0
    private static nonisolated(unsafe) var metadataCache: [String: CachedMetadata] = [:]

    internal nonisolated static func metadataCacheEvictionVictim(
        accessOrder: [String: UInt64],
        preserving keyToPreserve: String
    ) -> String? {
        accessOrder
            .filter { $0.key != keyToPreserve }
            .min { $0.value < $1.value }?
            .key
    }

    let bundleId: String
    let name: String
    let icon: NSImage?
    let policy: Policy
    let category: AppCategory
    let xPosition: CGFloat?
    let width: CGFloat?

    var preferredCenterX: CGFloat? {
        guard let xPosition else { return nil }
        guard let width, width > 0 else { return xPosition }
        return xPosition + (width / 2)
    }

    let menuExtraIdentifier: String?

    let statusItemIndex: Int?

    var hasPreciseMenuBarIdentity: Bool {
        menuExtraIdentifier != nil || statusItemIndex != nil
    }

    private static let unmovableMenuExtraIds: Set<String> = [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter"
    ]

    private static let unmovableNames: Set<String> = [
        "Clock", "Control Center"
    ]

    var isUnmovableSystemItem: Bool {
        if let id = menuExtraIdentifier, Self.unmovableMenuExtraIds.contains(id) {
            return true
        }
        if bundleId == "com.apple.controlcenter", Self.unmovableNames.contains(name) {
            return true
        }
        return false
    }

    var uniqueId: String {
        if let menuExtraIdentifier {
            if menuExtraIdentifier.hasPrefix("com.apple.menuextra.") {
                return menuExtraIdentifier
            }
            return "\(bundleId)::axid:\(menuExtraIdentifier)"
        }
        if let statusItemIndex {
            return "\(bundleId)::statusItem:\(statusItemIndex)"
        }
        return bundleId
    }

    var id: String { uniqueId }

    init(id: String, name: String, icon: NSImage?, policy: Policy = .regular, category: AppCategory = .other, menuExtraIdentifier: String? = nil, statusItemIndex: Int? = nil, xPosition: CGFloat? = nil, width: CGFloat? = nil) {
        bundleId = id
        self.name = name
        self.icon = icon
        self.policy = policy
        self.category = category
        self.menuExtraIdentifier = menuExtraIdentifier
        self.statusItemIndex = statusItemIndex
        self.xPosition = xPosition
        self.width = width
    }

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
        case "com.apple.menuextra.battery": "Battery"
        case "com.apple.menuextra.wifi": "Wi-Fi"
        case "com.apple.menuextra.bluetooth": "Bluetooth"
        case "com.apple.menuextra.clock": "Clock"
        case "com.apple.menuextra.airdrop": "AirDrop"
        case "com.apple.menuextra.focusmode": "Focus"
        case "com.apple.menuextra.controlcenter": "Control Center"
        case "com.apple.menuextra.display": "Display"
        case "com.apple.menuextra.sound": "Sound"
        case "com.apple.menuextra.airplay": "AirPlay"
        case "com.apple.menuextra.now-playing": "Now Playing"
        case "com.apple.menuextra.siri": "Siri"
        case "com.apple.menuextra.spotlight": "Spotlight"
        default:
            nil
        }
    }

    private static func sanitizeMenuExtraLabel(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        func isControlScalar(_ value: UInt32) -> Bool {
            value < 0x20 || (value >= 0x7F && value <= 0x9F)
        }

        func isPrivateUseScalar(_ value: UInt32) -> Bool {
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

    private static func iconForMenuExtra(_ identifier: String) -> String {
        switch identifier {
        case "com.apple.menuextra.battery": "battery.100"
        case "com.apple.menuextra.wifi": "wifi"
        case "com.apple.menuextra.bluetooth": "bluetooth"
        case "com.apple.menuextra.clock": "clock"
        case "com.apple.menuextra.airdrop": "airdrop"
        case "com.apple.menuextra.focusmode": "moon.fill"
        case "com.apple.menuextra.controlcenter": "switch.2"
        case "com.apple.menuextra.display": "display"
        case "com.apple.menuextra.sound": "speaker.wave.2"
        case "com.apple.menuextra.airplay": "airplayvideo"
        case "com.apple.menuextra.now-playing": "music.note"
        case "com.apple.menuextra.siri": "sparkles"
        case "com.apple.menuextra.spotlight": "magnifyingglass"
        default: "circle.grid.2x2"
        }
    }

    init(app: NSRunningApplication, statusItemIndex: Int? = nil, menuExtraIdentifier: String? = nil, xPosition: CGFloat? = nil, width: CGFloat? = nil) {
        bundleId = app.bundleIdentifier ?? UUID().uuidString
        let metadata = Self.cachedMetadata(for: app, resolvedBundleId: bundleId)
        name = metadata.name
        icon = metadata.icon
        self.xPosition = xPosition
        self.width = width

        switch app.activationPolicy {
        case .regular:
            policy = .regular
        case .accessory:
            policy = .accessory
        case .prohibited:
            policy = .prohibited
        @unknown default:
            policy = .unknown
        }

        category = metadata.category

        self.menuExtraIdentifier = menuExtraIdentifier
        self.statusItemIndex = statusItemIndex
    }

    init(app: NSRunningApplication, resolvedBundleId: String, statusItemIndex: Int? = nil, menuExtraIdentifier: String? = nil, xPosition: CGFloat? = nil, width: CGFloat? = nil) {
        bundleId = resolvedBundleId
        let metadata = Self.cachedMetadata(for: app, resolvedBundleId: resolvedBundleId)
        name = metadata.name
        icon = metadata.icon
        self.xPosition = xPosition
        self.width = width

        switch app.activationPolicy {
        case .regular:
            policy = .regular
        case .accessory:
            policy = .accessory
        case .prohibited:
            policy = .prohibited
        @unknown default:
            policy = .unknown
        }

        category = metadata.category
        self.menuExtraIdentifier = menuExtraIdentifier
        self.statusItemIndex = statusItemIndex
    }

    private static func detectCategory(
        bundleId: String,
        appName: String,
        bundleURL: URL?
    ) -> AppCategory {


        if bundleId.hasPrefix("com.apple.") {
            if bundleId.contains("controlcenter") || bundleId.contains("SystemPreferences") ||
                bundleId.contains("Finder") || bundleId.contains("systempreferences") ||
                bundleId.contains("Spotlight") || bundleId.contains("SystemUIServer") ||
                bundleId.contains("dock") || bundleId.contains("loginwindow") {
                return .system
            }
            if bundleId.contains("Music") || bundleId.contains("iTunes") ||
                bundleId.contains("Photos") || bundleId.contains("GarageBand") ||
                bundleId.contains("iMovie") || bundleId.contains("FinalCut") {
                return .creativity
            }
            if bundleId.contains("Safari") || bundleId.contains("Mail") ||
                bundleId.contains("Calendar") || bundleId.contains("Notes") ||
                bundleId.contains("Reminders") || bundleId.contains("Pages") ||
                bundleId.contains("Numbers") || bundleId.contains("Keynote") {
                return .productivity
            }
            if bundleId.contains("Messages") || bundleId.contains("FaceTime") {
                return .social
            }
            if bundleId.contains("News") || bundleId.contains("Weather") ||
                bundleId.contains("Books") || bundleId.contains("Stocks") {
                return .infoAndReading
            }
            if bundleId.contains("Xcode") || bundleId.contains("Terminal") ||
                bundleId.contains("Instruments") || bundleId.contains("FileMerge") {
                return .developerTools
            }
            return .system
        }


        if bundleId.contains("github") || bundleId.contains("gitlab") ||
            bundleId.contains("docker") || bundleId.contains("iterm") ||
            bundleId.contains("vscode") || bundleId.contains("jetbrains") ||
            bundleId.contains("sublime") || bundleId.contains("tower") ||
            bundleId.contains("cursor") || bundleId.contains("fig") ||
            appName.contains("xcode") || appName.contains("terminal") {
            return .developerTools
        }

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

        if bundleId.contains("notion") || bundleId.contains("obsidian") ||
            bundleId.contains("todoist") || bundleId.contains("things") ||
            bundleId.contains("omnifocus") || bundleId.contains("fantastical") ||
            bundleId.contains("spark") || bundleId.contains("airmail") {
            return .productivity
        }

        if bundleId.contains("slack") || bundleId.contains("discord") ||
            bundleId.contains("zoom") || bundleId.contains("teams") ||
            bundleId.contains("skype") || bundleId.contains("telegram") ||
            bundleId.contains("whatsapp") || bundleId.contains("signal") ||
            bundleId.contains("messenger") || appName.contains("chat") {
            return .social
        }

        if bundleId.contains("spotify") || bundleId.contains("soundcloud") ||
            bundleId.contains("audiohijack") || bundleId.contains("airfoil") ||
            bundleId.contains("adobe") || bundleId.contains("sketch") ||
            bundleId.contains("figma") || bundleId.contains("affinity") ||
            appName.contains("music") || appName.contains("audio") {
            return .creativity
        }

        if bundleId.contains("coinbase") || bundleId.contains("exodus") ||
            bundleId.contains("ledger") || bundleId.contains("crypto") ||
            appName.contains("wallet") || appName.contains("bitcoin") ||
            appName.contains("trading") || appName.contains("stock") {
            return .finance
        }

        if bundleId.contains("strava") || bundleId.contains("fitness") ||
            bundleId.contains("workout") || appName.contains("health") {
            return .healthAndFitness
        }

        if let bundleURL,
           let bundle = Bundle(url: bundleURL),
           let categoryType = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            return AppCategory.from(categoryType: categoryType)
        }

        return .other
    }

    private static func metadataCacheKey(
        for app: NSRunningApplication,
        resolvedBundleId: String?
    ) -> String {
        if let resolvedBundleId, !resolvedBundleId.isEmpty {
            return resolvedBundleId
        }
        if let bundleId = app.bundleIdentifier, !bundleId.isEmpty {
            return bundleId
        }
        return "pid:\(app.processIdentifier)"
    }

    private static func cachedMetadata(
        for app: NSRunningApplication,
        resolvedBundleId: String?
    ) -> CachedMetadata {
        let cacheKey = metadataCacheKey(for: app, resolvedBundleId: resolvedBundleId)

        metadataCacheLock.lock()
        metadataCacheClock &+= 1
        if var cached = metadataCache[cacheKey] {
            cached.lastAccess = metadataCacheClock
            metadataCache[cacheKey] = cached
            metadataCacheLock.unlock()
            return cached
        }
        metadataCacheLock.unlock()

        let bundleId = resolvedBundleId ?? app.bundleIdentifier ?? ""
        let metadata = CachedMetadata(
            name: app.localizedName ?? "Unknown",
            icon: app.icon,
            category: detectCategory(
                bundleId: bundleId,
                appName: (app.localizedName ?? "").lowercased(),
                bundleURL: app.bundleURL
            ),
            lastAccess: 0
        )

        metadataCacheLock.lock()
        metadataCacheClock &+= 1
        if var cached = metadataCache[cacheKey] {
            cached.lastAccess = metadataCacheClock
            metadataCache[cacheKey] = cached
            metadataCacheLock.unlock()
            return cached
        }
        var stored = metadata
        stored.lastAccess = metadataCacheClock
        if metadataCache.count >= metadataCacheMaxEntries,
           let victim = metadataCacheEvictionVictim(
               accessOrder: metadataCache.mapValues(\.lastAccess),
               preserving: cacheKey
           ) {
            metadataCache.removeValue(forKey: victim)
        }
        metadataCache[cacheKey] = stored
        metadataCacheLock.unlock()
        return stored
    }
}
