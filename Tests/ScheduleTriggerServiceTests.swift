import Foundation
import Testing
@testable import SaneBar

@Suite("ScheduleTriggerService Tests")
struct ScheduleTriggerServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )) ?? Date()
    }

    @Test("Weekday schedule matches inside configured range")
    func weekdayScheduleMatches() {
        // Monday, 2026-02-16 10:30 UTC
        let date = makeDate(2026, 2, 16, 10, 30)
        let result = ScheduleTriggerService.isWithinSchedule(
            date: date,
            weekdays: [2, 3, 4, 5, 6], // Mon-Fri
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            calendar: calendar
        )
        #expect(result)
    }

    @Test("Schedule does not match on unselected weekday")
    func weekdayScheduleExcludesUnselectedDay() {
        // Sunday, 2026-02-15 10:30 UTC
        let date = makeDate(2026, 2, 15, 10, 30)
        let result = ScheduleTriggerService.isWithinSchedule(
            date: date,
            weekdays: [2, 3, 4, 5, 6], // Mon-Fri
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            calendar: calendar
        )
        #expect(!result)
    }

    @Test("Overnight schedule handles before and after midnight")
    func overnightScheduleWorks() {
        // Monday 23:00 UTC and Monday 03:00 UTC
        let lateNight = makeDate(2026, 2, 16, 23, 0)
        let earlyMorning = makeDate(2026, 2, 16, 3, 0)

        let lateResult = ScheduleTriggerService.isWithinSchedule(
            date: lateNight,
            weekdays: [2],
            startHour: 22,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            calendar: calendar
        )
        let earlyResult = ScheduleTriggerService.isWithinSchedule(
            date: earlyMorning,
            weekdays: [2],
            startHour: 22,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            calendar: calendar
        )

        #expect(lateResult)
        #expect(earlyResult)
    }

    @Test("Equal start/end means full-day schedule for selected weekdays")
    func equalTimesMeansFullDay() {
        let date = makeDate(2026, 2, 17, 2, 15) // Tuesday
        let result = ScheduleTriggerService.isWithinSchedule(
            date: date,
            weekdays: [3], // Tuesday
            startHour: 0,
            startMinute: 0,
            endHour: 0,
            endMinute: 0,
            calendar: calendar
        )
        #expect(result)
    }

    @Test("Empty weekday list never matches")
    func emptyWeekdayListNeverMatches() {
        let date = makeDate(2026, 2, 17, 12, 0)
        let result = ScheduleTriggerService.isWithinSchedule(
            date: date,
            weekdays: [],
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            calendar: calendar
        )
        #expect(!result)
    }
}
