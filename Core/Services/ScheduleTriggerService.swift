import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "ScheduleTrigger")

// MARK: - ScheduleTriggerService

/// Service that reveals hidden icons when local time enters a configured schedule window.
///
/// Behavior:
/// - Checks once per minute
/// - Triggers only on transition "outside -> inside" to avoid repeated reveals
/// - Supports overnight windows (e.g. 22:00 -> 06:00)
@MainActor
final class ScheduleTriggerService {
    private weak var menuBarManager: MenuBarManager?
    private var timer: Timer?
    private var wasInScheduleWindow = false

    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    func startMonitoring() {
        guard timer == nil else { return }
        guard menuBarManager != nil else { return }

        evaluateScheduleTransition()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateScheduleTransition()
            }
        }
        logger.info("Started schedule trigger monitoring")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        wasInScheduleWindow = false
        logger.info("Stopped schedule trigger monitoring")
    }

    func restartIfRunning() {
        guard timer != nil else { return }
        stopMonitoring()
        startMonitoring()
    }

    private func evaluateScheduleTransition(now: Date = Date()) {
        guard let manager = menuBarManager else { return }
        guard manager.settings.showOnSchedule else { return }

        let isInWindow = Self.isWithinSchedule(
            date: now,
            weekdays: manager.settings.scheduleWeekdays,
            startHour: manager.settings.scheduleStartHour,
            startMinute: manager.settings.scheduleStartMinute,
            endHour: manager.settings.scheduleEndHour,
            endMinute: manager.settings.scheduleEndMinute,
            calendar: .current
        )

        if isInWindow, !wasInScheduleWindow {
            logger.info("Schedule trigger entered active window - showing hidden items")
            manager.showHiddenItems()
        }
        wasInScheduleWindow = isInWindow
    }

    nonisolated static func isWithinSchedule(
        date: Date,
        weekdays: [Int],
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        calendar: Calendar
    ) -> Bool {
        guard !weekdays.isEmpty else { return false }

        let allowedDays = Set(weekdays.filter { (1 ... 7).contains($0) })
        guard !allowedDays.isEmpty else { return false }

        let clampedStartHour = min(max(startHour, 0), 23)
        let clampedEndHour = min(max(endHour, 0), 23)
        let clampedStartMinute = min(max(startMinute, 0), 59)
        let clampedEndMinute = min(max(endMinute, 0), 59)

        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else {
            return false
        }

        let nowMinutes = (hour * 60) + minute
        let startMinutes = (clampedStartHour * 60) + clampedStartMinute
        let endMinutes = (clampedEndHour * 60) + clampedEndMinute

        guard allowedDays.contains(weekday) else { return false }

        if startMinutes == endMinutes {
            // Same start/end means full-day schedule for selected weekdays.
            return true
        }

        if startMinutes < endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }

        // Overnight window (e.g. 22:00 -> 06:00)
        return nowMinutes >= startMinutes || nowMinutes < endMinutes
    }
}
