import Foundation

struct BusinessDTO: Decodable, Sendable {
    let id: UUID
    let slug: String
    let name: String
    let city: String
    let themeKey: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case id, slug, name, city, timezone
        case themeKey = "theme_key"
    }

    var model: Business {
        Business(id: id, slug: slug, name: name, city: city, themeKey: themeKey, timeZoneIdentifier: timezone)
    }
}
struct ProfileDTO: Decodable, Sendable {
    let id: UUID
    let authUserID: UUID?
    let businessID: UUID
    let fullName: String
    let email: String
    let role: AppRole
    let jobTitle: String?
    let hireDate: String
    let employmentType: EmploymentType
    let fullTime: Bool
    let status: EmploymentStatus
    let avatarColor: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role, status
        case authUserID = "auth_user_id"
        case businessID = "business_id"
        case fullName = "full_name"
        case jobTitle = "job_title"
        case hireDate = "hire_date"
        case employmentType = "employment_type"
        case fullTime = "full_time"
        case avatarColor = "avatar_color"
    }

    var model: StaffProfile {
        StaffProfile(
            id: id,
            authUserID: authUserID,
            businessID: businessID,
            name: fullName,
            email: email,
            role: role,
            jobTitle: jobTitle ?? "",
            hireDate: DateOnly(hireDate) ?? DateOnly(year: 1970, month: 1, day: 1),
            employmentType: employmentType,
            fullTime: fullTime,
            status: status,
            avatarColor: avatarColor ?? "#557e70"
        )
    }
}

struct PolicySettingsDTO: Decodable, Sendable {
    let plannedNoticeDays: Int
    let allowedRequestHours: [Int]

    enum CodingKeys: String, CodingKey {
        case plannedNoticeDays = "planned_notice_days"
        case allowedRequestHours = "allowed_request_hours"
    }

    var model: PolicySettings {
        PolicySettings(plannedNoticeDays: plannedNoticeDays, allowedRequestHours: allowedRequestHours)
    }
}

struct PolicyTierDTO: Decodable, Sendable {
    let id: Int
    let tierKey: String
    let label: String
    let minMonths: Int
    let maxMonths: Int?
    let hoursPerPayPeriod: Double
    let balanceCap: Double

    enum CodingKeys: String, CodingKey {
        case id, label
        case tierKey = "tier_key"
        case minMonths = "min_months"
        case maxMonths = "max_months"
        case hoursPerPayPeriod = "hours_per_pay_period"
        case balanceCap = "balance_cap"
    }

    var model: PolicyTier {
        PolicyTier(
            id: id,
            key: tierKey,
            label: label,
            minimumMonths: minMonths,
            maximumMonths: maxMonths,
            hoursPerPayPeriod: hoursPerPayPeriod,
            balanceCap: balanceCap
        )
    }
}

struct RequestDayDTO: Decodable, Sendable {
    let id: UUID
    let ptoDate: String
    let hours: Double

    enum CodingKeys: String, CodingKey {
        case id, hours
        case ptoDate = "pto_date"
    }

    var model: RequestDay {
        RequestDay(id: id, date: DateOnly(ptoDate) ?? DateOnly(year: 1970, month: 1, day: 1), hours: Int(hours))
    }
}

struct PTORequestDTO: Decodable, Sendable {
    let id: UUID
    let employeeID: UUID
    let businessID: UUID
    let category: PTOCategory
    let status: PTORequestStatus
    let privateNote: String?
    let decisionNote: String?
    let submittedAt: String
    let decidedAt: String?
    let decidedBy: UUID?
    let shortNotice: Bool
    let requestDays: [RequestDayDTO]

    enum CodingKeys: String, CodingKey {
        case id, category, status
        case employeeID = "employee_id"
        case businessID = "business_id"
        case privateNote = "private_note"
        case decisionNote = "decision_note"
        case submittedAt = "submitted_at"
        case decidedAt = "decided_at"
        case decidedBy = "decided_by"
        case shortNotice = "short_notice"
        case requestDays = "request_days"
    }

    var model: PTORequest {
        PTORequest(
            id: id,
            employeeID: employeeID,
            businessID: businessID,
            category: category,
            status: status,
            days: requestDays.map(\.model).sorted { $0.date < $1.date },
            privateNote: privateNote,
            decisionNote: decisionNote,
            submittedAt: AppDateFormatter.parseTimestamp(submittedAt) ?? .distantPast,
            decidedAt: AppDateFormatter.parseTimestamp(decidedAt),
            decidedBy: decidedBy,
            shortNotice: shortNotice
        )
    }
}

struct LedgerEntryDTO: Decodable, Sendable {
    let id: UUID
    let employeeID: UUID
    let businessID: UUID
    let entryType: String
    let effectiveDate: String
    let hours: Double
    let description: String
    let requestID: UUID?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, hours, description
        case employeeID = "employee_id"
        case businessID = "business_id"
        case entryType = "entry_type"
        case effectiveDate = "effective_date"
        case requestID = "request_id"
        case createdAt = "created_at"
    }

    var model: LedgerEntry {
        LedgerEntry(
            id: id,
            employeeID: employeeID,
            businessID: businessID,
            type: entryType,
            effectiveDate: DateOnly(effectiveDate) ?? DateOnly(year: 1970, month: 1, day: 1),
            hours: hours,
            description: description,
            requestID: requestID,
            createdAt: AppDateFormatter.parseTimestamp(createdAt) ?? .distantPast
        )
    }
}

struct BlackoutDTO: Decodable, Sendable {
    let id: UUID
    let businessID: UUID
    let name: String
    let startDate: String
    let endDate: String
    let reason: String
    let cancelledAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, reason
        case businessID = "business_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case cancelledAt = "cancelled_at"
    }

    var model: BlackoutPeriod {
        BlackoutPeriod(
            id: id,
            businessID: businessID,
            name: name,
            startDate: DateOnly(startDate) ?? DateOnly(year: 1970, month: 1, day: 1),
            endDate: DateOnly(endDate) ?? DateOnly(year: 1970, month: 1, day: 1),
            reason: reason
        )
    }
}

struct ScheduledBreakDTO: Decodable, Sendable {
    let id: UUID
    let shiftID: UUID
    let breakType: BreakType
    let startsAt: String?
    let durationMinutes: Int

    enum CodingKeys: String, CodingKey {
        case id
        case shiftID = "shift_id"
        case breakType = "break_type"
        case startsAt = "starts_at"
        case durationMinutes = "duration_minutes"
    }

    var model: ScheduledBreak {
        ScheduledBreak(
            id: id,
            shiftID: shiftID,
            type: breakType,
            startsAt: AppDateFormatter.parseTimestamp(startsAt),
            durationMinutes: durationMinutes
        )
    }
}

struct ScheduledShiftDTO: Decodable, Sendable {
    let id: UUID
    let seriesID: UUID?
    let businessID: UUID
    let employeeID: UUID
    let shiftDate: String
    let startsAt: String
    let endsAt: String
    let status: ShiftStatus
    let title: String
    let notes: String?
    let warningFlags: [String]
    let isSeriesOverride: Bool
    let scheduledBreaks: [ScheduledBreakDTO]

    enum CodingKeys: String, CodingKey {
        case id, status, title, notes
        case seriesID = "series_id"
        case businessID = "business_id"
        case employeeID = "employee_id"
        case shiftDate = "shift_date"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case warningFlags = "warning_flags"
        case isSeriesOverride = "is_series_override"
        case scheduledBreaks = "scheduled_breaks"
    }

    var model: ScheduledShift {
        ScheduledShift(
            id: id,
            seriesID: seriesID,
            businessID: businessID,
            employeeID: employeeID,
            shiftDate: DateOnly(shiftDate) ?? DateOnly(year: 1970, month: 1, day: 1),
            startsAt: AppDateFormatter.parseTimestamp(startsAt) ?? .distantPast,
            endsAt: AppDateFormatter.parseTimestamp(endsAt) ?? .distantPast,
            status: status,
            title: title,
            notes: notes,
            warningFlags: warningFlags,
            isSeriesOverride: isSeriesOverride,
            breaks: scheduledBreaks.map(\.model)
        )
    }
}

struct ActualBreakDTO: Decodable, Sendable {
    let id: UUID
    let breakType: BreakType
    let startedAt: String
    let endedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case breakType = "break_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    var model: ActualBreak {
        ActualBreak(
            id: id,
            type: breakType,
            startedAt: AppDateFormatter.parseTimestamp(startedAt) ?? .distantPast,
            endedAt: AppDateFormatter.parseTimestamp(endedAt)
        )
    }
}

struct TimesheetDTO: Decodable, Sendable {
    let id: UUID
    let businessID: UUID
    let employeeID: UUID
    let scheduledShiftID: UUID?
    let status: TimesheetStatus
    let startedAt: String
    let endedAt: String?
    let warningFlags: [String]
    let systemClosed: Bool
    let actualBreaks: [ActualBreakDTO]

    enum CodingKeys: String, CodingKey {
        case id, status
        case businessID = "business_id"
        case employeeID = "employee_id"
        case scheduledShiftID = "scheduled_shift_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case warningFlags = "warning_flags"
        case systemClosed = "system_closed"
        case actualBreaks = "actual_breaks"
    }

    var model: Timesheet {
        Timesheet(
            id: id,
            businessID: businessID,
            employeeID: employeeID,
            scheduledShiftID: scheduledShiftID,
            status: status,
            startedAt: AppDateFormatter.parseTimestamp(startedAt) ?? .distantPast,
            endedAt: AppDateFormatter.parseTimestamp(endedAt),
            warningFlags: warningFlags,
            systemClosed: systemClosed,
            breaks: actualBreaks.map(\.model)
        )
    }
}

struct NotificationDTO: Decodable, Sendable {
    let id: UUID
    let profileID: UUID
    let kind: NotificationKind
    let title: String
    let body: String
    let requestID: UUID?
    let readAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case profileID = "profile_id"
        case requestID = "request_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var model: AppNotification {
        AppNotification(
            id: id,
            profileID: profileID,
            kind: kind,
            title: title,
            body: body,
            requestID: requestID,
            readAt: AppDateFormatter.parseTimestamp(readAt),
            createdAt: AppDateFormatter.parseTimestamp(createdAt) ?? .distantPast
        )
    }
}
