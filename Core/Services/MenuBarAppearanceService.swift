import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarAppearance")

// MARK: - MenuBarAppearanceSettings

/// Settings for customizing the menu bar appearance
struct MenuBarAppearanceSettings: Codable, Sendable, Equatable {
    /// Whether custom appearance is enabled
    var isEnabled: Bool = false

    /// Use Liquid Glass effect (macOS 26+ only, falls back to tint on older systems)
    var useLiquidGlass: Bool = true

    /// Tint color for light mode (hex string like "#FF0000")
    var tintColor: String = "#000000"

    /// Tint opacity for light mode (0.0 - 1.0)
    var tintOpacity: Double = 0.15

    /// Tint color for dark mode (hex string)
    var tintColorDark: String = "#FFFFFF"

    /// Tint opacity for dark mode (0.0 - 1.0)
    var tintOpacityDark: Double = 0.15

    /// Whether to add a shadow below the menu bar
    var hasShadow: Bool = false

    /// Shadow opacity (0.0 - 1.0)
    var shadowOpacity: Double = 0.3

    /// Whether to add a bottom border
    var hasBorder: Bool = false

    /// Border color (hex string)
    var borderColor: String = "#808080"

    /// Border width
    var borderWidth: Double = 1.0

    /// Whether to use rounded corners on the overlay
    var hasRoundedCorners: Bool = false

    /// Corner radius
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
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.tintColorDark = tintColorDark
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
        tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor) ?? "#000000"
        tintOpacity = try container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? 0.15
        tintColorDark = try container.decodeIfPresent(String.self, forKey: .tintColorDark) ?? "#FFFFFF"
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

    /// Check if running on macOS 26+ for Liquid Glass support (and compiled with Swift 6.2+)
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
}

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
            }
        }

        // Refresh overlay when system appearance changes (light ↔ dark)
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Force SwiftUI to re-evaluate colorScheme by toggling window appearance
                self?.overlayWindow?.appearance = NSApp.effectiveAppearance
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
            }
        }
    }

    // MARK: - Public API

    func updateAppearance(_ settings: MenuBarAppearanceSettings) {
        if settings.isEnabled {
            ensureOverlayExists()
            overlayViewModel?.settings = settings
            show()
        } else {
            hide()
        }
    }

    func show() {
        overlayWindow?.orderFront(nil)
    }

    func hide() {
        overlayWindow?.orderOut(nil)
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
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Set SwiftUI view as content
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: menuBarFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        overlayWindow = window

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

// MARK: - MenuBarOverlayViewModel

/// Observable model to share settings between service and view
@Observable
@MainActor
final class MenuBarOverlayViewModel {
    var settings = MenuBarAppearanceSettings()
    var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
}

// MARK: - MenuBarOverlayView

/// SwiftUI view that renders the menu bar overlay with tint, shadow, border effects
struct MenuBarOverlayView: View {
    var viewModel: MenuBarOverlayViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// Active tint color based on current system appearance
    private var activeTintColor: String {
        colorScheme == .dark ? viewModel.settings.tintColorDark : viewModel.settings.tintColor
    }

    /// Active tint opacity based on current system appearance.
    /// When Reduce Transparency is enabled, the menu bar background becomes a solid opaque fill
    /// instead of blur — low-opacity tints are invisible on solid backgrounds. Use at least 50%
    /// opacity to ensure the tint is perceptible while not completely obscuring icons.
    private var activeTintOpacity: Double {
        let baseOpacity = colorScheme == .dark
            ? viewModel.settings.tintOpacityDark
            : viewModel.settings.tintOpacity
        if viewModel.reduceTransparency {
            return max(baseOpacity, 0.5)
        }
        return baseOpacity
    }

    var body: some View {
        GeometryReader { _ in
            let horizontalInset: CGFloat = viewModel.settings.hasRoundedCorners
                ? min(10, max(4, viewModel.settings.cornerRadius * 0.75))
                : 0

            ZStack(alignment: .bottom) {
                // Main appearance layer
                mainAppearanceLayer

                // Border layer
                if viewModel.settings.hasBorder {
                    Rectangle()
                        .fill(Color(hex: viewModel.settings.borderColor))
                        .frame(height: viewModel.settings.borderWidth)
                }
            }
            .padding(.horizontal, horizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(overlayShape)
            .shadow(
                color: viewModel.settings.hasShadow ? .black.opacity(viewModel.settings.shadowOpacity) : .clear,
                radius: viewModel.settings.hasShadow ? 4 : 0,
                y: viewModel.settings.hasShadow ? 2 : 0
            )
        }
        .allowsHitTesting(false) // Ensure clicks pass through
    }

    @ViewBuilder
    private var mainAppearanceLayer: some View {
        if viewModel.settings.useLiquidGlass, MenuBarAppearanceSettings.supportsLiquidGlass {
            liquidGlassLayer
        } else {
            // Fallback tint layer for older macOS
            Rectangle()
                .fill(Color(hex: activeTintColor).opacity(activeTintOpacity))
        }
    }

    @ViewBuilder
    private var liquidGlassLayer: some View {
        #if swift(>=6.2)
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(Glass.regular)
                    // Ensure chosen tint color/strength is always applied.
                    // (Glass.tint() doesn't reliably reflect custom colors in all cases.)
                    .overlay(
                        Color(hex: activeTintColor)
                            .opacity(activeTintOpacity)
                    )
            } else {
                fallbackTintLayer
            }
        #else
            // Glass APIs require Swift 6.2+ SDK (Xcode 26+)
            fallbackTintLayer
        #endif
    }

    private var fallbackTintLayer: some View {
        Rectangle()
            .fill(Color(hex: activeTintColor).opacity(activeTintOpacity))
    }

    private var overlayShape: some Shape {
        if viewModel.settings.hasRoundedCorners {
            AnyShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: viewModel.settings.cornerRadius,
                    bottomTrailingRadius: viewModel.settings.cornerRadius
                )
            )
        } else {
            AnyShape(Rectangle())
        }
    }
}

// MARK: - AnyShape

/// Type-erased shape for conditional shape rendering
struct AnyShape: Shape, @unchecked Sendable {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init(_ shape: some Shape) {
        // Capture shape value, not reference
        let shapeCopy = shape
        pathBuilder = { rect in
            shapeCopy.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert Color to hex string (e.g., "#FF5500")
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return "#000000"
        }

        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
