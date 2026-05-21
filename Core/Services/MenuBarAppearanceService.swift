import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarAppearance")

// MARK: - MenuBarAppearanceServiceProtocol

/// @mockable
@MainActor
protocol MenuBarAppearanceServiceProtocol {
    func updateAppearance(_ settings: MenuBarAppearanceSettings)
    func show()
    func hide()
}

// MARK: - MenuBarAppearanceService

/// Service that applies visual styling to the menu bar using a transparent overlay window.
///
/// Creates a window positioned exactly over the menu bar region and applies tint,
/// shadow, border, and rounded corner effects. The overlay is click-through so it
/// doesn't interfere with normal menu bar interactions.
@MainActor
final class MenuBarAppearanceService: ObservableObject, MenuBarAppearanceServiceProtocol {
    // MARK: - Properties

    private var overlayWindow: NSWindow?
    private var overlayViewModel: MenuBarOverlayViewModel?
    private var screenObserver: Any?
    private var appearanceObserver: Any?
    private var accessibilityObserver: Any?
    private var appActivationObserver: Any?
    private var activeSpaceObserver: Any?
    private var didWakeObserver: Any?
    private var screensDidWakeObserver: Any?
    private var sessionDidBecomeActiveObserver: Any?
    private var pendingOverlayRefreshWorkItems: [DispatchWorkItem] = []
    private var visibilityReconciliationTimer: Timer?

    // MARK: - Initialization

    init() {
        // Screen observer is only set up when overlay is created
    }

    /// Clean up resources - call before releasing service
    func teardown() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            appearanceObserver = nil
        }
        if let observer = accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            accessibilityObserver = nil
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        if let observer = activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activeSpaceObserver = nil
        }
        if let observer = didWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            didWakeObserver = nil
        }
        if let observer = screensDidWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            screensDidWakeObserver = nil
        }
        if let observer = sessionDidBecomeActiveObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sessionDidBecomeActiveObserver = nil
        }
        cancelPendingOverlayVisibilityRefreshes()
        stopVisibilityReconciliationTimer()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    // MARK: - Screen Observer

    private func setupScreenObserver() {
        guard screenObserver == nil else { return }

        // Re-position overlay when screens change
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionOverlay()
                self?.scheduleOverlayVisibilityRefreshes()
            }
        }

        // Refresh overlay when system appearance changes (light ↔ dark)
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyResolvedAppearance()
            }
        }

        // Refresh overlay when accessibility display settings change (Reduce Transparency toggle)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.overlayViewModel?.reduceTransparency =
                    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                self?.updateWindowLevel()
                self?.refreshOverlayVisibility()
            }
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleOverlayVisibilityRefreshes()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleOverlayVisibilityRefreshes()
            }
        }

        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionOverlay()
                self?.scheduleOverlayVisibilityRefreshes()
            }
        }

        screensDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionOverlay()
                self?.scheduleOverlayVisibilityRefreshes()
            }
        }

        sessionDidBecomeActiveObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionOverlay()
                self?.scheduleOverlayVisibilityRefreshes()
            }
        }
    }

    // MARK: - Public API

    func updateAppearance(_ settings: MenuBarAppearanceSettings) {
        if settings.isEnabled {
            ensureOverlayExists()
            startVisibilityReconciliationTimer()
            overlayViewModel?.settings = settings
            updateWindowLevel()
            refreshOverlayVisibility()
        } else {
            overlayViewModel?.settings = settings
            stopVisibilityReconciliationTimer()
            hide()
        }
    }

    func show() {
        refreshOverlayVisibility()
    }

    func hide() {
        overlayWindow?.orderOut(nil)
    }

    func refreshAfterStatusItemRecovery() {
        repositionOverlay()
        scheduleOverlayVisibilityRefreshes()
    }

    private func refreshOverlayVisibility() {
        guard let window = overlayWindow else { return }
        guard overlayViewModel?.settings.isEnabled == true else {
            window.orderOut(nil)
            return
        }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let suppressionReason = Self.overlaySuppressionReason(
            frontmostPID: frontmostApp?.processIdentifier,
            frontmostBundleID: frontmostApp?.bundleIdentifier,
            frontmostIsAccessoryApp: frontmostApp?.activationPolicy != .regular,
            targetScreenFrame: preferredMenuBarScreen()?.frame,
            windowInfos: currentWindowInfos()
        )

        if suppressionReason != nil {
            logger.debug("Suppressing menu bar appearance overlay: \(String(describing: suppressionReason), privacy: .public)")
            window.orderOut(nil)
            return
        }

        applyResolvedAppearance()
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    private func scheduleOverlayVisibilityRefreshes() {
        cancelPendingOverlayVisibilityRefreshes()
        refreshOverlayVisibility()

        for delay in Self.overlayVisibilityRefreshRetryDelays {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.refreshOverlayVisibility()
                }
            }
            pendingOverlayRefreshWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelPendingOverlayVisibilityRefreshes() {
        pendingOverlayRefreshWorkItems.forEach { $0.cancel() }
        pendingOverlayRefreshWorkItems.removeAll()
    }

    private func startVisibilityReconciliationTimer() {
        guard visibilityReconciliationTimer == nil else { return }

        let timer = Timer(timeInterval: Self.overlayVisibilityReconciliationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshOverlayVisibility()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        visibilityReconciliationTimer = timer
    }

    private func stopVisibilityReconciliationTimer() {
        visibilityReconciliationTimer?.invalidate()
        visibilityReconciliationTimer = nil
    }

    internal nonisolated static let overlayVisibilityRefreshRetryDelays: [TimeInterval] = [
        0.15,
        0.5,
        1.5,
        3.0
    ]

    internal nonisolated static let overlayVisibilityReconciliationInterval: TimeInterval = 0.5

    private func currentWindowInfos() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    internal nonisolated static func shouldSuppressOverlay(
        frontmostPID: pid_t?,
        frontmostBundleID: String?,
        frontmostIsAccessoryApp: Bool = false,
        targetScreenFrame: CGRect?,
        windowInfos: [[String: Any]],
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        overlaySuppressionReason(
            frontmostPID: frontmostPID,
            frontmostBundleID: frontmostBundleID,
            frontmostIsAccessoryApp: frontmostIsAccessoryApp,
            targetScreenFrame: targetScreenFrame,
            windowInfos: windowInfos,
            selfPID: selfPID
        ) != nil
    }

    internal enum OverlaySuppressionReason: Equatable {
        case fullscreenContentWindow
        case thinTopHost
    }

    internal nonisolated static func overlaySuppressionReason(
        frontmostPID: pid_t?,
        frontmostBundleID: String?,
        frontmostIsAccessoryApp: Bool = false,
        targetScreenFrame: CGRect?,
        windowInfos: [[String: Any]],
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> OverlaySuppressionReason? {
        guard let frontmostPID,
              let bundleID = frontmostBundleID,
              let targetScreenFrame else {
            return nil
        }

        guard frontmostPID != selfPID else { return nil }

        func number(_ value: Any?) -> CGFloat? {
            switch value {
            case let number as NSNumber:
                return CGFloat(truncating: number)
            case let value as CGFloat:
                return value
            case let value as Double:
                return value
            case let value as Int:
                return CGFloat(value)
            default:
                return nil
            }
        }

        func bool(_ value: Any?) -> Bool? {
            switch value {
            case let number as NSNumber:
                return number.boolValue
            case let value as Bool:
                return value
            default:
                return nil
            }
        }

        let targetFrame = targetScreenFrame.standardized
        let minimumCoveredWidth = targetFrame.width * 0.97
        let maximumHorizontalDrift: CGFloat = 8
        let maximumTopDrift: CGFloat = 8
        let suppressThinTopHost = !bundleID.hasPrefix("com.apple.")

        func isCompanionContentWindow(_ info: [String: Any], excluding thinRect: CGRect) -> Bool {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { return false }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard ownerPID == frontmostPID else { return false }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                return false
            }

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            guard rect != thinRect else { return false }
            let isOnscreen = bool(info[kCGWindowIsOnscreen as String]) ?? true
            let alpha = number(info[kCGWindowAlpha as String]) ?? 1
            let layer = number(info[kCGWindowLayer as String]) ?? 0
            guard isOnscreen else { return false }
            guard alpha > 0 else { return false }
            guard layer == 0 else { return false }

            let coveredRect = rect.intersection(targetFrame)
            guard coveredRect.width >= targetFrame.width * 0.25 else { return false }
            guard coveredRect.height >= 80 else { return false }
            guard rect.minY >= targetFrame.minY + 20 || rect.height >= targetFrame.height * 0.5 else { return false }
            return true
        }

        for info in windowInfos {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard ownerPID == frontmostPID else { continue }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }

            let rect = CGRect(x: x, y: y, width: width, height: height).standardized
            let coveredRect = rect.intersection(targetFrame)
            let isOnscreen = bool(info[kCGWindowIsOnscreen as String]) ?? true
            let alpha = number(info[kCGWindowAlpha as String]) ?? 1
            let layer = number(info[kCGWindowLayer as String]) ?? 0
            guard isOnscreen, alpha > 0 else { continue }

            guard layer == 0 else { continue }
            guard abs(rect.minX - targetFrame.minX) <= maximumHorizontalDrift else { continue }
            guard abs(rect.minY - targetFrame.minY) <= maximumTopDrift else { continue }
            if !frontmostIsAccessoryApp,
               coveredRect.width >= minimumCoveredWidth,
               coveredRect.height >= targetFrame.height * 0.9 {
                return .fullscreenContentWindow
            }
            guard suppressThinTopHost else { continue }
            guard height >= 20, height <= 26 else { continue }
            guard coveredRect.width >= minimumCoveredWidth else { continue }
            guard !windowInfos.contains(where: { isCompanionContentWindow($0, excluding: rect) }) else { continue }
            return .thinTopHost
        }

        return nil
    }

    private func applyResolvedAppearance() {
        guard let window = overlayWindow else { return }

        let resolvedAppearance = Self.resolvedOverlayAppearance(
            from: NSApp.effectiveAppearance,
            systemInterfaceStyleName: Self.currentSystemInterfaceStyleName()
        )
        window.appearance = resolvedAppearance
        window.contentView?.appearance = resolvedAppearance
        overlayViewModel?.isDarkAppearance = Self.isDarkAppearance(resolvedAppearance)
    }

    @MainActor
    func captureSnapshotPNG(to path: String) -> Bool {
        guard let window = overlayWindow,
              window.isVisible,
              let contentView = window.contentView else {
            return false
        }

        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let bounds = contentView.bounds.integral
        guard bounds.width > 0,
              bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds),
              let outputURL = Self.snapshotOutputURL(for: path) else {
            return false
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: outputURL, options: .atomic)
            return true
        } catch {
            logger.error("appearance overlay snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func snapshotOutputURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    internal nonisolated static let supportedOverlayAppearances: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]

    private nonisolated static func currentSystemInterfaceStyleName() -> String? {
        UserDefaults(suiteName: UserDefaults.globalDomain)?
            .string(forKey: "AppleInterfaceStyle")
    }

    internal nonisolated static func resolvedOverlayAppearance(
        from appearance: NSAppearance?,
        systemInterfaceStyleName: String? = nil
    ) -> NSAppearance? {
        if let systemInterfaceStyleName {
            let currentMatch = appearance?.bestMatch(from: supportedOverlayAppearances)
            let highContrast = currentMatch == .accessibilityHighContrastAqua ||
                currentMatch == .accessibilityHighContrastDarkAqua
            let normalizedStyleName = systemInterfaceStyleName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let resolvedName: NSAppearance.Name
            if normalizedStyleName == "dark" {
                resolvedName = highContrast ? .accessibilityHighContrastDarkAqua : .darkAqua
            } else if normalizedStyleName == "light" {
                resolvedName = highContrast ? .accessibilityHighContrastAqua : .aqua
            } else {
                return resolvedOverlayAppearance(from: appearance)
            }
            return NSAppearance(named: resolvedName) ?? appearance
        }

        guard let appearance else { return nil }
        guard let matchedName = appearance.bestMatch(from: supportedOverlayAppearances) else {
            return appearance
        }
        return NSAppearance(named: matchedName) ?? appearance
    }

    internal nonisolated static func isDarkAppearance(_ appearance: NSAppearance?) -> Bool {
        let match = resolvedOverlayAppearance(from: appearance)?
            .bestMatch(from: supportedOverlayAppearances)
        return match == .darkAqua || match == .accessibilityHighContrastDarkAqua
    }

    internal nonisolated static func resolvedTintColorHex(
        settings: MenuBarAppearanceSettings,
        isDarkAppearance: Bool
    ) -> String {
        isDarkAppearance ? settings.tintColorDark : settings.tintColor
    }

    internal nonisolated static func resolvedTintColorHex(
        settings: MenuBarAppearanceSettings,
        appearance: NSAppearance?,
        systemInterfaceStyleName: String? = nil
    ) -> String {
        resolvedTintColorHex(
            settings: settings,
            isDarkAppearance: isDarkAppearance(
                resolvedOverlayAppearance(
                    from: appearance,
                    systemInterfaceStyleName: systemInterfaceStyleName
                )
            )
        )
    }

    internal nonisolated static func resolvedTintOpacity(
        settings: MenuBarAppearanceSettings,
        isDarkAppearance: Bool,
        reduceTransparency: Bool
    ) -> Double {
        let baseOpacity = isDarkAppearance ? settings.tintOpacityDark : settings.tintOpacity
        return reduceTransparency ? max(baseOpacity, 0.5) : baseOpacity
    }

    internal nonisolated static func resolvedOverlayWindowLevel(
        settings: MenuBarAppearanceSettings,
        reduceTransparency: Bool
    ) -> NSWindow.Level {
        let useGlass = settings.useLiquidGlass &&
            MenuBarAppearanceSettings.supportsLiquidGlass &&
            !reduceTransparency
        return useGlass ? .statusBar - 1 : .statusBar
    }

    // MARK: - Window Level

    /// Adjust the overlay window level based on the active appearance mode.
    ///
    /// Liquid Glass composites naturally with layers underneath, so the overlay
    /// sits *below* status items (`.statusBar - 1`) to avoid obscuring icons.
    ///
    /// A plain tint rectangle, on the other hand, is hidden behind the opaque
    /// menu bar background at that level — only a 1px sliver shows at the bottom.
    /// Raising the overlay to `.statusBar` puts the tint *above* the background
    /// so icons show through the semi-transparent colour.
    private func updateWindowLevel() {
        guard let window = overlayWindow, let vm = overlayViewModel else { return }

        let newLevel = Self.resolvedOverlayWindowLevel(
            settings: vm.settings,
            reduceTransparency: vm.reduceTransparency
        )
        if window.level != newLevel {
            window.level = newLevel
            logger.debug("Overlay window level → \(newLevel.rawValue)")
        }
    }

    // MARK: - Overlay Management

    private func ensureOverlayExists() {
        guard overlayWindow == nil else { return }

        // Set up screen observer now that we need the overlay
        setupScreenObserver()

        let menuBarFrame = calculateMenuBarFrame()

        // Create observable viewModel and view
        let viewModel = MenuBarOverlayViewModel()
        overlayViewModel = viewModel
        let view = MenuBarOverlayView(viewModel: viewModel)

        // Create window
        let window = NSPanel(
            contentRect: menuBarFrame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window to be transparent and click-through
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Keep the overlay BELOW the actual menu bar content (status items), otherwise
        // Liquid Glass can visually obscure icons.
        window.level = .statusBar - 1
        window.ignoresMouseEvents = true // Click-through
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Set SwiftUI view as content
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: menuBarFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        overlayWindow = window
        applyResolvedAppearance()

        logger.info("Created menu bar overlay window at \(NSStringFromRect(menuBarFrame))")
    }

    private func repositionOverlay() {
        guard let window = overlayWindow else { return }
        let newFrame = calculateMenuBarFrame()
        window.setFrame(newFrame, display: true)
        logger.debug("Repositioned overlay to \(NSStringFromRect(newFrame))")
    }

    private func preferredMenuBarScreen() -> NSScreen? {
        if let screen = MenuBarManager.shared.mainStatusItem?.button?.window?.screen {
            return screen
        }
        if let screen = MenuBarManager.shared.separatorItem?.button?.window?.screen {
            return screen
        }
        if let screen = overlayWindow?.screen {
            return screen
        }
        return NSScreen.screens.first ?? NSScreen.main
    }

    private func calculateMenuBarFrame() -> NSRect {
        guard let screen = preferredMenuBarScreen() else {
            return NSRect(x: 0, y: 0, width: 1920, height: 24)
        }

        // On notched Macs, visibleFrame.maxY is below the notch area
        // We need to use frame.maxY to get the true top of screen
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Menu bar height: difference between screen top and visible area top
        // This accounts for both regular menu bars AND notched displays
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY

        // Fallback to system thickness if calculation seems wrong
        let finalHeight = menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness

        logger.debug("""
        Menu bar frame calculation: screen=\(NSStringFromRect(screenFrame)), \
        visible=\(NSStringFromRect(visibleFrame)), height=\(finalHeight)
        """)

        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - finalHeight,
            width: screenFrame.width,
            height: finalHeight
        )
    }
}
