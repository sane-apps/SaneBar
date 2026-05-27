import Foundation

extension SaneBarSettings {
    func preservingAutomation(from current: SaneBarSettings) -> SaneBarSettings {
        var next = self
        next.showOnAppLaunch = current.showOnAppLaunch
        next.triggerApps = current.triggerApps
        next.appLaunchTriggerAction = current.appLaunchTriggerAction
        next.appLaunchTriggerProfileId = current.appLaunchTriggerProfileId
        next.showOnLowBattery = current.showOnLowBattery
        next.batteryThreshold = current.batteryThreshold
        next.batteryTriggerAction = current.batteryTriggerAction
        next.batteryTriggerProfileId = current.batteryTriggerProfileId
        next.showOnNetworkChange = current.showOnNetworkChange
        next.triggerNetworks = current.triggerNetworks
        next.networkTriggerAction = current.networkTriggerAction
        next.networkTriggerProfileId = current.networkTriggerProfileId
        next.showOnFocusModeChange = current.showOnFocusModeChange
        next.triggerFocusModes = current.triggerFocusModes
        next.focusTriggerAction = current.focusTriggerAction
        next.focusTriggerProfileId = current.focusTriggerProfileId
        next.showOnSchedule = current.showOnSchedule
        next.scheduleWeekdays = current.scheduleWeekdays
        next.scheduleStartHour = current.scheduleStartHour
        next.scheduleStartMinute = current.scheduleStartMinute
        next.scheduleEndHour = current.scheduleEndHour
        next.scheduleEndMinute = current.scheduleEndMinute
        next.scheduleTriggerAction = current.scheduleTriggerAction
        next.scheduleTriggerProfileId = current.scheduleTriggerProfileId
        next.scriptTriggerEnabled = current.scriptTriggerEnabled
        next.scriptTriggerPath = current.scriptTriggerPath
        next.scriptTriggerInterval = current.scriptTriggerInterval
        return next
    }

    func preservingProtectedSettings(from current: SaneBarSettings) -> SaneBarSettings {
        var next = self
        if current.requireAuthToShowHiddenIcons, !next.requireAuthToShowHiddenIcons {
            next.requireAuthToShowHiddenIcons = true
        }
        return next
    }

    func preservingLocalLifecycleState(from current: SaneBarSettings) -> SaneBarSettings {
        var next = self
        next.hasCompletedOnboarding = current.hasCompletedOnboarding
        next.hasSeenFreemiumIntro = current.hasSeenFreemiumIntro
        next.hasCompletedHealthWizard = current.hasCompletedHealthWizard
        next.layoutRescueRestorePoint = current.layoutRescueRestorePoint
        next.layoutRescueRestorePointCreatedAt = current.layoutRescueRestorePointCreatedAt
        return next
    }
}
