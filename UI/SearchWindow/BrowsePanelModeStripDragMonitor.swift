import AppKit

enum BrowsePanelModeStripDragMonitor {
    @MainActor
    static func install(clearDragState: @escaping @MainActor () -> Void) -> (local: Any?, global: Any?) {
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .keyDown]
        ) { event in
            if event.type == .leftMouseUp
                || event.type == .rightMouseUp
                || (event.type == .keyDown && event.keyCode == 53) {
                Task { @MainActor in
                    clearDragState()
                }
            }
            return event
        }

        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp]
        ) { _ in
            Task { @MainActor in
                clearDragState()
            }
        }

        return (local, global)
    }

    @MainActor
    static func remove(local: inout Any?, global: inout Any?) {
        if let monitor = local {
            NSEvent.removeMonitor(monitor)
            local = nil
        }
        if let monitor = global {
            NSEvent.removeMonitor(monitor)
            global = nil
        }
    }
}
