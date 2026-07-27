import Foundation

enum AppRole: String, Codable, CaseIterable, Sendable {
    case employee
    case officeManager = "office_manager"
    case ownerAdmin = "owner_admin"

    var isManager: Bool { self != .employee }

    var label: String {
        switch self {
        case .employee: "Employee"
        case .officeManager: "Office Manager"
        case .ownerAdmin: "Owner / Admin"
        }
    }
}

enum EmploymentType: String, Codable, Sendable {
    case hourly
    case salaried
}

enum EmploymentStatus: String, Codable, Sendable {
    case active
    case leave
    case separated
}

enum PTOCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case vacation
    case personal
    case illness
    case bereavement

    var id: String { rawValue }
    var isPlanned: Bool { self == .vacation || self == .personal }
    var label: String { rawValue.capitalized }
}

enum PTORequestStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case pending
    case approved
    case rejected
    case cancelled

    var label: String { rawValue.capitalized }
}

enum ShiftStatus: String, Codable, Sendable {
    case draft
    case published
    case cancelled
}

enum BreakType: String, Codable, CaseIterable, Identifiable, Sendable {
    case paidRest = "paid_rest"
    case unpaidMeal = "unpaid_meal"

    var id: String { rawValue }
    var label: String { self == .paidRest ? "Paid rest" : "Unpaid meal" }
}

enum TimesheetStatus: String, Codable, Sendable {
    case inProgress = "in_progress"
    case pending
    case approved
    case void
}

enum NotificationKind: String, Codable, Sendable {
    case request
    case balance
    case blackout
    case system
    case schedule
    case timeclock
}

struct DateOnly: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ value: String) {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    func adding(days: Int, in timeZone: TimeZone = .current) -> DateOnly {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let value = calendar.date(byAdding: .day, value: days, to: date(in: timeZone)) ?? date(in: timeZone)
        return DateOnly(date: value, calendar: calendar)
    }

    static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> DateOnly {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return DateOnly(date: now, calendar: calendar)
    }
}

struct Business: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let slug: String
    let name: String
    let city: String
    let themeKey: String
    let timeZoneIdentifier: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

struct StaffProfile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let authUserID: UUID?
    let businessID: UUID
    let name: String
    let email: String
    let role: AppRole
    let jobTitle: String
    let hireDate: DateOnly
    let employmentType: EmploymentType
    let fullTime: Bool
    let status: EmploymentStatus
    let avatarColor: String

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct PolicySettings: Hashable, Codable, Sendable {
    let plannedNoticeDays: Int
    let allowedRequestHours: [Int]

    static let fallback = PolicySettings(plannedNoticeDays: 30, allowedRequestHours: [4, 8])
}

struct PolicyTier: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let key: String
    let label: String
    let minimumMonths: Int
    let maximumMonths: Int?
    let hoursPerPayPeriod: Double
    let balanceCap: Double
}

struct RequestDay: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let date: DateOnly
    let hours: Int
}

struct PTORequest: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let employeeID: UUID
    let businessID: UUID
    let category: PTOCategory
    let status: PTORequestStatus
    let days: [RequestDay]
    let privateNote: String?
    let decisionNote: String?
    let submittedAt: Date
    let decidedAt: Date?
    let decidedBy: UUID?
    let shortNotice: Bool

    var hours: Int { days.reduce(0) { $0 + $1.hours } }
    var firstDate: DateOnly? { days.map(\.date).min() }
}

struct LedgerEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let employeeID: UUID
    let businessID: UUID
    let type: String
    let effectiveDate: DateOnly
    let hours: Double
    let description: String
    let requestID: UUID?
    let createdAt: Date
}

struct BlackoutPeriod: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let businessID: UUID
    let name: String
    let startDate: DateOnly
    let endDate: DateOnly
    let reason: String

    func contains(_ date: DateOnly) -> Bool { startDate <= date && date <= endDate }
}

struct ScheduledBreak: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let shiftID: UUID
    let type: BreakType
    let startsAt: Date?
    let durationMinutes: Int
}

struct ScheduledShift: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let seriesID: UUID?
    let businessID: UUID
    let employeeID: UUID
    let shiftDate: DateOnly
    let startsAt: Date
    let endsAt: Date
    let status: ShiftStatus
    let title: String
    let notes: String?
    let warningFlags: [String]
    let isSeriesOverride: Bool
    let breaks: [ScheduledBreak]
}

struct ActualBreak: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let type: BreakType
    let startedAt: Date
    let endedAt: Date?
}

struct Timesheet: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let businessID: UUID
    let employeeID: UUID
    let scheduledShiftID: UUID?
    let status: TimesheetStatus
    let startedAt: Date
    let endedAt: Date?
    let warningFlags: [String]
    let systemClosed: Bool
    let breaks: [ActualBreak]
}

struct AppNotification: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let profileID: UUID
    let kind: NotificationKind
    let title: String
    let body: String
    let requestID: UUID?
    let readAt: Date?
    let createdAt: Date

    var isUnread: Bool { readAt == nil }
}

enum AttendanceState: String, Codable, CaseIterable, Sendable {
    case clockedIn
    case onBreak
    case clockedOut
    case notStarted
    case notScheduled
    case noClockRequired

    var label: String {
        switch self {
        case .clockedIn: "Clocked in"
        case .onBreak: "On break"
        case .clockedOut: "Clocked out"
        case .notStarted: "Not started"
        case .notScheduled: "Not scheduled"
        case .noClockRequired: "No clock required"
        }
    }
}

struct AttendanceRecord: Identifiable, Hashable, Sendable {
    let profile: StaffProfile
    let state: AttendanceState
    let shift: ScheduledShift?
    let timesheet: Timesheet?

    var id: UUID { profile.id }
}

struct DomainSnapshot: Codable, Sendable {
    let savedAt: Date
    let business: Business
    let profiles: [StaffProfile]
    let requests: [PTORequest]
    let ledger: [LedgerEntry]
    let blackouts: [BlackoutPeriod]
    let shifts: [ScheduledShift]
    let timesheets: [Timesheet]
    let notifications: [AppNotification]
    let policy: PolicySettings
    let tiers: [PolicyTier]
}

struct PTORequestDraft: Sendable {
    var category: PTOCategory
    var days: [(date: DateOnly, hours: Int)]
    var privateNote: String?
}

struct ScheduleBreakDraft: Codable, Hashable, Sendable {
    var type: BreakType
    var durationMinutes: Int
    var startOffsetMinutes: Int?
}

struct ScheduleDraft: Sendable {
    var employeeID: UUID
    var weekdays: [Int]
    var startTime: String
    var endTime: String
    var effectiveStart: DateOnly
    var effectiveEnd: DateOnly?
    var title: String
    var notes: String?
    var status: ShiftStatus
    var breaks: [ScheduleBreakDraft]
}

struct ScheduledShiftUpdate: Sendable {
    var shiftID: UUID
    var employeeID: UUID
    var shiftDate: DateOnly
    var startTime: String
    var endTime: String
    var title: String
    var notes: String?
    var status: ShiftStatus
    var breaks: [ScheduleBreakDraft]
}

enum AppRoute: Hashable, Sendable {
    case home
    case schedule
    case timeOff
    case inbox
    case request(UUID)
}

enum BusinessSelection {
    static func preferredBusinessID(
        profile: StaffProfile,
        businesses: [Business],
        savedBusinessID: UUID?
    ) -> UUID? {
        if profile.role == .ownerAdmin,
           let savedBusinessID,
           businesses.contains(where: { $0.id == savedBusinessID }) {
            return savedBusinessID
        }
        return businesses.first(where: { $0.id == profile.businessID })?.id ?? businesses.first?.id
    }
}
