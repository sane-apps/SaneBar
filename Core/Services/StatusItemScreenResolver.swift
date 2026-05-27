import AppKit
import CoreGraphics

@MainActor
final class StatusItemScreenResolver {
    private var lastKnownStatusItemDisplayID: CGDirectDisplayID?

    func screen(mainStatusItem: NSStatusItem?, separatorItem: NSStatusItem?) -> NSScreen? {
        if let liveScreen = mainStatusItem?.button?.window?.screen ??
            separatorItem?.button?.window?.screen {
            lastKnownStatusItemDisplayID = Self.displayID(liveScreen)
            return liveScreen
        }

        if let lastKnownStatusItemDisplayID,
           let cachedScreen = NSScreen.screens.first(where: { Self.displayID($0) == lastKnownStatusItemDisplayID }) {
            return cachedScreen
        }

        if let pointerScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            lastKnownStatusItemDisplayID = Self.displayID(pointerScreen)
            return pointerScreen
        }

        let mainScreen = NSScreen.main
        lastKnownStatusItemDisplayID = Self.displayID(mainScreen)
        return mainScreen
    }

    func lastKnownDisplayStillPresent() -> Bool {
        lastKnownStatusItemDisplayID.map { displayID in
            NSScreen.screens.contains { Self.displayID($0) == displayID }
        } ?? true
    }

    func isExternalScreen(_ screen: NSScreen?) -> Bool {
        guard let screen else { return true }
        guard let displayID = Self.displayID(screen) else { return true }
        return CGDisplayIsBuiltin(displayID) == 0
    }

    private static func displayID(_ screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
