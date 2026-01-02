import SwiftUI

@main
struct SaneBarApp: App {
    // We don't want a standard window, we are a menu bar app.
    // 'application(_:didFinishLaunchingWithOptions:)' is handled by the adaptor or Init.
    
    @StateObject private var menuBarManager = MenuBarManager.shared
    
    var body: some Scene {
        // No WindowGroup needed for a pure menu bar app if we manage the status item manually.
        // However, SwiftUI's 'Settings' scene is useful.
        
        Settings {
            SettingsView()
        }
    }
    
    init() {
        // Initialize our bartender logic
        _ = MenuBarManager.shared
    }
}
