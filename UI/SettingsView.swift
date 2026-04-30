import AppKit
import SaneUI
import SwiftUI

struct SettingsView: View {
    enum SettingsTab: String, SaneSettingsTab {
        case control = "Control"
        case rules = "Rules"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case health = "Health"
        case license = "License"
        case about = "About"

        var icon: String {
            switch self {
            case .control: "switch.2"
            case .rules: "wand.and.stars"
            case .appearance: "paintpalette"
            case .shortcuts: "keyboard"
            case .health: "stethoscope"
            case .license: "key.fill"
            case .about: "questionmark.circle"
            }
        }

        var iconColor: Color {
            switch self {
            case .control:
                SaneSettingsIconSemantic.general.color
            case .rules:
                SaneSettingsIconSemantic.rules.color
            case .appearance:
                SaneSettingsIconSemantic.appearance.color
            case .shortcuts:
                SaneSettingsIconSemantic.shortcuts.color
            case .health:
                .green
            case .license:
                SaneSettingsIconSemantic.license.color
            case .about:
                SaneSettingsIconSemantic.about.color
            }
        }
    }

    var defaultTab: SettingsTab = .control

    var body: some View {
        SaneSettingsContainer(defaultTab: defaultTab, windowSizing: .embedded) { tab in
            switch tab {
            case .control:
                GeneralSettingsView()
                    .navigationTitle("Control")
            case .rules:
                RulesSettingsView()
                    .navigationTitle("Rules")
            case .appearance:
                AppearanceSettingsView()
                    .navigationTitle("Appearance")
            case .shortcuts:
                ShortcutsSettingsView()
                    .navigationTitle("Shortcuts")
            case .health:
                HealthSettingsView()
                    .navigationTitle("Health")
            case .license:
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        LicenseSettingsView<SaneBarLicenseSettingsAdapter>(
                            licenseService: SaneBarLicenseSettingsAdapter.shared,
                            style: .panel
                        )
                            .frame(maxWidth: 420, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("License")
            case .about:
                AboutSettingsView()
                    .navigationTitle("About")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            SettingsResizeGrip()
                .frame(width: 22, height: 22)
                .padding(.trailing, 7)
                .padding(.bottom, 7)
                .saneHelp("Drag the corner to resize Settings.")
        }
    }
}

private struct SettingsResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsResizeGripView {
        SettingsResizeGripView()
    }

    func updateNSView(_ nsView: SettingsResizeGripView, context: Context) {
        nsView.needsDisplay = true
    }
}

private final class SettingsResizeGripView: NSView {
    private var initialFrame: NSRect?
    private var initialMouseLocation: NSPoint?

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityRole(.handle)
        setAccessibilityLabel("Resize Settings window")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath()
        path.lineWidth = 1.15
        path.lineCapStyle = .round

        for offset in [5.0, 10.0, 15.0] {
            path.move(to: NSPoint(x: bounds.maxX - CGFloat(offset), y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: CGFloat(offset)))
        }

        NSColor.white.withAlphaComponent(0.34).setStroke()
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        initialFrame = window?.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let initialFrame,
            let initialMouseLocation
        else { return }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        let minContentSize = window.contentMinSize
        let minFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: minContentSize)
        ).size
        let newWidth = max(minFrameSize.width, initialFrame.width + deltaX)
        let newHeight = max(minFrameSize.height, initialFrame.height - deltaY)
        let frame = NSRect(
            x: initialFrame.minX,
            y: initialFrame.maxY - newHeight,
            width: newWidth,
            height: newHeight
        )
        window.setFrame(frame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        initialFrame = nil
        initialMouseLocation = nil
    }
}

#Preview {
    SettingsView()
}
