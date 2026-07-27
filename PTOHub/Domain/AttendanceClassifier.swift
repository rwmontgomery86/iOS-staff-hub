import Foundation

enum AttendanceClassifier {
    static func records(
        profiles: [StaffProfile],
        shifts: [ScheduledShift],
        timesheets: [Timesheet],
        date: DateOnly,
        timeZone: TimeZone = .current
    ) -> [AttendanceRecord] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return profiles.filter { $0.status == .active }.map { profile in
            guard profile.employmentType == .hourly else {
                return AttendanceRecord(profile: profile, state: .noClockRequired, shift: nil, timesheet: nil)
            }
            let shift = shifts
                .filter { $0.employeeID == profile.id && $0.shiftDate == date && $0.status == .published }
                .sorted { $0.startsAt < $1.startsAt }
                .first
            let sheet = timesheets
                .filter { $0.employeeID == profile.id && DateOnly(date: $0.startedAt, calendar: calendar) == date && $0.status != .void }
                .sorted { $0.startedAt > $1.startedAt }
                .first
            let state: AttendanceState
            if let sheet, sheet.status == .inProgress {
                state = sheet.breaks.contains(where: { $0.endedAt == nil }) ? .onBreak : .clockedIn
            } else if sheet?.endedAt != nil {
                state = .clockedOut
            } else if shift != nil {
                state = .notStarted
            } else {
                state = .notScheduled
            }
            return AttendanceRecord(profile: profile, state: state, shift: shift, timesheet: sheet)
        }
        .sorted { lhs, rhs in
            let order: [AttendanceState] = [.clockedIn, .onBreak, .clockedOut, .notStarted, .notScheduled, .noClockRequired]
            let left = order.firstIndex(of: lhs.state) ?? order.count
            let right = order.firstIndex(of: rhs.state) ?? order.count
            return left == right ? lhs.profile.name < rhs.profile.name : left < right
        }
    }
}
