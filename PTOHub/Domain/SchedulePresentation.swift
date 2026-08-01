import Foundation

enum SchedulePresentation {
    static func weekStart(containing date: DateOnly, timeZone: TimeZone) -> DateOnly {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekday = calendar.component(.weekday, from: date.date(in: timeZone))
        return date.adding(days: -(weekday - 1), in: timeZone)
    }

    static func weekDays(starting start: DateOnly, timeZone: TimeZone) -> [DateOnly] {
        (0..<7).map { start.adding(days: $0, in: timeZone) }
    }

    static func visibleShifts(
        from shifts: [ScheduledShift],
        for profile: StaffProfile
    ) -> [ScheduledShift] {
        shifts.filter { shift in
            if profile.role.isManager { return shift.status != .cancelled }
            return shift.employeeID == profile.id && shift.status == .published
        }
    }
}
