import Foundation
@testable import SaneBar
import Testing

struct UpgradePathTests {
    static let settingsSavedBy2190 = """
    {"alwaysHiddenPinnedItemIds":["com.apple.finder::statusItem:0","com.apple.menuextra.battery"],"alwaysHiddenSectionEnabled":true,"appLaunchTriggerAction":"Show Icons","autoRehide":true,"batteryThreshold":20,"batteryTriggerAction":"Show Icons","checkForUpdatesAutomatically":true,"disableOnExternalMonitor":false,"dividerStyle":"slash","findIconRehideDelay":15,"focusTriggerAction":"Show Icons","gestureToggles":false,"hasCompletedHealthWizard":true,"hasCompletedOnboarding":true,"hasSeenFreemiumIntro":true,"hideAllOtherMenuBarItems":false,"hideAllOtherVisibleItemIds":[],"hideApplicationMenusOnInlineReveal":true,"hideMainIcon":false,"hoverDelay":2,"iconGroups":[],"iconHotkeys":{},"layoutMode":"Stability","leftClickOpensBrowseIcons":false,"menuBarAppearance":{"borderColor":"#808080","borderWidth":1,"cornerRadius":8,"hasBorder":false,"hasRoundedCorners":false,"hasShadow":false,"isEnabled":false,"shadowOpacity":0.3,"tintColor":"#000000","tintColorDark":"#FFFFFF","tintOpacity":0.15,"tintOpacityDark":0.15,"useLiquidGlass":true},"menuBarIconStyle":"filter","networkTriggerAction":"Show Icons","rehideDelay":5,"rehideOnAppChange":false,"requireAuthToShowHiddenIcons":false,"scheduleEndHour":17,"scheduleEndMinute":0,"scheduleStartHour":9,"scheduleStartMinute":0,"scheduleTriggerAction":"Show Icons","scheduleWeekdays":[2,3,4,5,6],"scriptTriggerEnabled":false,"scriptTriggerInterval":10,"scriptTriggerPath":"","secondMenuBarShowAlwaysHidden":false,"secondMenuBarShowVisible":true,"showDockIcon":false,"showOnAppLaunch":false,"showOnClick":false,"showOnFocusModeChange":false,"showOnHover":false,"showOnLowBattery":false,"showOnNetworkChange":false,"showOnSchedule":false,"showOnScroll":false,"showOnUserDrag":true,"spacerCount":0,"spacerStyle":"line","spacerWidth":"normal","triggerApps":[],"triggerFocusModes":[],"triggerNetworks":[],"useDirectionalScroll":false,"useSecondMenuBar":false}
    """

    @Test("Settings saved by 2.1.90 still load in 2.1.91 and feed the macOS 27 notice")
    func settingsFrom2190SurviveUpgrade() throws {
        let data = Data(Self.settingsSavedBy2190.utf8)
        let settings = try JSONDecoder().decode(SaneBarSettings.self, from: data)
        #expect(settings.alwaysHiddenPinnedItemIds == ["com.apple.finder::statusItem:0", "com.apple.menuextra.battery"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sanebar-2190-\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(GoldenGateNotice.hiddenAppNames(settingsURL: url) == ["Finder"])
    }
}
