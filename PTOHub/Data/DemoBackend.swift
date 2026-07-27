#if DEBUG && targetEnvironment(simulator)
import Foundation

actor DemoBackend: BackendServicing {
    let identity: AuthenticatedIdentity
    private var snapshots: [UUID: DomainSnapshot]

    init(role: AppRole) {
        let fixture = DemoFixture.make(role: role)
        identity = fixture.identity
        snapshots = fixture.snapshots
    }

    func currentUserID() async -> UUID? { identity.authUserID }
    func authUserChanges() async -> AsyncStream<UUID?> { AsyncStream { $0.finish() } }
    func signIn(email: String, password: String) async throws -> UUID { identity.authUserID }
    func signOut() async throws {}

    func loadIdentity(authUserID: UUID) async throws -> AuthenticatedIdentity {
        guard authUserID == identity.authUserID else { throw DemoError.unknownIdentity }
        return identity
    }

    func loadSnapshot(profile: StaffProfile, business: Business) async throws -> DomainSnapshot {
        guard let stored = snapshots[business.id] else { throw DemoError.unknownBusiness }
        let employeeOnly = profile.role == .employee
        return DomainSnapshot(
            savedAt: .now,
            business: stored.business,
            profiles: stored.profiles,
            requests: employeeOnly ? stored.requests.filter { $0.employeeID == profile.id } : stored.requests,
            ledger: employeeOnly ? stored.ledger.filter { $0.employeeID == profile.id } : stored.ledger,
            blackouts: stored.blackouts,
            shifts: employeeOnly ? stored.shifts.filter { $0.employeeID == profile.id && $0.status == .published } : stored.shifts,
            timesheets: employeeOnly ? stored.timesheets.filter { $0.employeeID == profile.id } : stored.timesheets,
            notifications: stored.notifications.filter { $0.profileID == profile.id },
            policy: stored.policy,
            tiers: stored.tiers
        )
    }

    func submitRequest(profile: StaffProfile, draft: PTORequestDraft) async throws {
        guard var snapshot = snapshots[profile.businessID] else { throw DemoError.unknownBusiness }
        let firstAllowed = DateOnly.today(in: snapshot.business.timeZone).adding(days: snapshot.policy.plannedNoticeDays)
        let request = PTORequest(
            id: UUID(), employeeID: profile.id, businessID: profile.businessID, category: draft.category,
            status: .pending,
            days: draft.days.map { RequestDay(id: UUID(), date: $0.date, hours: $0.hours) },
            privateNote: draft.privateNote, decisionNote: nil, submittedAt: .now,
            decidedAt: nil, decidedBy: nil,
            shortNotice: draft.days.contains { $0.date < firstAllowed }
        )
        snapshot = snapshot.replacing(requests: snapshot.requests + [request])
        snapshots[profile.businessID] = snapshot
    }

    func cancelRequest(id: UUID) async throws {
        try updateRequest(id: id) { request in
            request.replacing(status: .cancelled, decisionNote: request.decisionNote, decidedBy: nil)
        }
    }

    func decideRequest(id: UUID, status: PTORequestStatus, note: String?) async throws {
        guard status == .approved || status == .rejected else { throw DemoError.invalidDecision }
        try updateRequest(id: id) { [actorID = identity.profile.id] request in
            request.replacing(status: status, decisionNote: note, decidedBy: actorID)
        }
    }

    func createSchedule(businessID: UUID, actorID: UUID, draft: ScheduleDraft) async throws {
        guard var snapshot = snapshots[businessID] else { throw DemoError.unknownBusiness }
        let shiftID = UUID()
        let startsAt = DemoFixture.date(draft.effectiveStart, clock: draft.startTime, timeZone: snapshot.business.timeZone)
        let endsAt = DemoFixture.date(draft.effectiveStart, clock: draft.endTime, timeZone: snapshot.business.timeZone)
        let shift = ScheduledShift(
            id: shiftID, seriesID: draft.effectiveEnd == draft.effectiveStart ? nil : UUID(),
            businessID: businessID, employeeID: draft.employeeID, shiftDate: draft.effectiveStart,
            startsAt: startsAt, endsAt: endsAt, status: draft.status, title: draft.title,
            notes: draft.notes, warningFlags: [], isSeriesOverride: false,
            breaks: draft.breaks.map {
                ScheduledBreak(
                    id: UUID(), shiftID: shiftID, type: $0.type,
                    startsAt: $0.startOffsetMinutes.map { startsAt.addingTimeInterval(Double($0 * 60)) },
                    durationMinutes: $0.durationMinutes
                )
            }
        )
        snapshot = snapshot.replacing(shifts: snapshot.shifts + [shift])
        snapshots[businessID] = snapshot
    }

    func updateShift(_ update: ScheduledShiftUpdate) async throws {
        for businessID in Array(snapshots.keys) {
            guard var snapshot = snapshots[businessID],
                  let index = snapshot.shifts.firstIndex(where: { $0.id == update.shiftID }) else { continue }
            let old = snapshot.shifts[index]
            let startsAt = DemoFixture.date(update.shiftDate, clock: update.startTime, timeZone: snapshot.business.timeZone)
            let endsAt = DemoFixture.date(update.shiftDate, clock: update.endTime, timeZone: snapshot.business.timeZone)
            var shifts = snapshot.shifts
            shifts[index] = ScheduledShift(
                id: old.id, seriesID: old.seriesID, businessID: old.businessID,
                employeeID: update.employeeID, shiftDate: update.shiftDate, startsAt: startsAt,
                endsAt: endsAt, status: update.status, title: update.title, notes: update.notes,
                warningFlags: old.warningFlags, isSeriesOverride: old.seriesID != nil,
                breaks: old.breaks
            )
            snapshot = snapshot.replacing(shifts: shifts)
            snapshots[businessID] = snapshot
            return
        }
        throw DemoError.unknownShift
    }

    func markNotificationsRead(profileID: UUID) async throws {
        for businessID in Array(snapshots.keys) {
            guard var snapshot = snapshots[businessID] else { continue }
            let updated = snapshot.notifications.map { notification in
                guard notification.profileID == profileID else { return notification }
                return AppNotification(
                    id: notification.id, profileID: notification.profileID, kind: notification.kind,
                    title: notification.title, body: notification.body, requestID: notification.requestID,
                    readAt: notification.readAt ?? .now, createdAt: notification.createdAt
                )
            }
            snapshot = snapshot.replacing(notifications: updated)
            snapshots[businessID] = snapshot
        }
    }

    func registerMobileDevice(installationID: UUID, token: String, environment: String, bundleID: String) async throws {}
    func unregisterMobileDevice(installationID: UUID, bundleID: String) async throws {}
    func attendanceEvents(businessID: UUID) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    private func updateRequest(id: UUID, transform: (PTORequest) -> PTORequest) throws {
        for businessID in Array(snapshots.keys) {
            guard var snapshot = snapshots[businessID],
                  let index = snapshot.requests.firstIndex(where: { $0.id == id }) else { continue }
            var requests = snapshot.requests
            requests[index] = transform(requests[index])
            snapshot = snapshot.replacing(requests: requests)
            snapshots[businessID] = snapshot
            return
        }
        throw DemoError.unknownRequest
    }
}

private enum DemoError: LocalizedError {
    case unknownIdentity, unknownBusiness, unknownRequest, unknownShift, invalidDecision

    var errorDescription: String? {
        switch self {
        case .unknownIdentity: "The demo identity could not be loaded."
        case .unknownBusiness: "The demo business could not be loaded."
        case .unknownRequest: "The demo request could not be found."
        case .unknownShift: "The demo shift could not be found."
        case .invalidDecision: "Demo requests can only be approved or rejected."
        }
    }
}

private struct DemoFixture {
    let identity: AuthenticatedIdentity
    let snapshots: [UUID: DomainSnapshot]

    static let griffinID = id("10000000-0000-0000-0000-000000000001")
    static let senoiaID = id("10000000-0000-0000-0000-000000000002")
    static let maxaraID = id("10000000-0000-0000-0000-000000000003")
    static let mayaID = id("20000000-0000-0000-0000-000000000001")
    static let elenaID = id("20000000-0000-0000-0000-000000000002")
    static let ownerID = id("20000000-0000-0000-0000-000000000003")
    static let jordanID = id("20000000-0000-0000-0000-000000000004")
    static let averyID = id("20000000-0000-0000-0000-000000000005")
    static let samID = id("20000000-0000-0000-0000-000000000006")

    static func make(role: AppRole) -> DemoFixture {
        let griffin = Business(id: griffinID, slug: "griffin-eye-care", name: "Griffin Eye Care", city: "Griffin, Georgia", themeKey: "griffin-eye-care", timeZoneIdentifier: "America/New_York")
        let senoia = Business(id: senoiaID, slug: "senoia-eye-care", name: "Senoia Eye Care", city: "Senoia, Georgia", themeKey: "senoia-eye-care", timeZoneIdentifier: "America/New_York")
        let maxara = Business(id: maxaraID, slug: "maxara", name: "Maxara", city: "Georgia", themeKey: "maxara", timeZoneIdentifier: "America/New_York")
        let griffinProfiles = profiles(for: griffin)
        let selectedProfile: StaffProfile
        switch role {
        case .employee: selectedProfile = griffinProfiles.first { $0.id == mayaID }!
        case .officeManager: selectedProfile = griffinProfiles.first { $0.id == elenaID }!
        case .ownerAdmin: selectedProfile = griffinProfiles.first { $0.id == ownerID }!
        }
        let businesses = role == .ownerAdmin ? [griffin, senoia, maxara] : [griffin]
        let identity = AuthenticatedIdentity(
            authUserID: selectedProfile.authUserID!, profile: selectedProfile, businesses: businesses
        )
        return DemoFixture(
            identity: identity,
            snapshots: Dictionary(uniqueKeysWithValues: businesses.map { business in
                (business.id, snapshot(for: business, profiles: business.id == griffinID ? griffinProfiles : profiles(for: business)))
            })
        )
    }

    static func snapshot(for business: Business, profiles: [StaffProfile]) -> DomainSnapshot {
        let today = DateOnly.today(in: business.timeZone)
        let byRole = { (role: AppRole) in profiles.first { $0.role == role }! }
        let employee = byRole(.employee)
        let manager = byRole(.officeManager)
        let owner = byRole(.ownerAdmin)
        let hourly = profiles.filter { $0.role == .employee }
        let secondEmployee = hourly.dropFirst().first ?? employee
        let thirdEmployee = hourly.dropFirst(2).first ?? employee
        let fourthEmployee = hourly.dropFirst(3).first ?? employee

        let approvedID = UUID()
        let pendingID = UUID()
        let managerRequestID = UUID()
        let requests = [
            PTORequest(
                id: approvedID, employeeID: employee.id, businessID: business.id, category: .vacation,
                status: .approved, days: [RequestDay(id: UUID(), date: today.adding(days: 45), hours: 8)],
                privateNote: "Family trip", decisionNote: nil, submittedAt: .now.addingTimeInterval(-86_400),
                decidedAt: .now, decidedBy: manager.id, shortNotice: false
            ),
            PTORequest(
                id: pendingID, employeeID: secondEmployee.id, businessID: business.id, category: .personal,
                status: .pending, days: [RequestDay(id: UUID(), date: today.adding(days: 40), hours: 4)],
                privateNote: "Appointment", decisionNote: nil, submittedAt: .now,
                decidedAt: nil, decidedBy: nil, shortNotice: false
            ),
            PTORequest(
                id: managerRequestID, employeeID: manager.id, businessID: business.id, category: .vacation,
                status: .pending, days: [RequestDay(id: UUID(), date: today.adding(days: 55), hours: 8)],
                privateNote: "Planned travel", decisionNote: nil, submittedAt: .now,
                decidedAt: nil, decidedBy: nil, shortNotice: false
            ),
        ]

        let ledger = profiles.flatMap { profile -> [LedgerEntry] in
            guard profile.role != .ownerAdmin else { return [] }
            let balance = profile.role == .officeManager ? 72.0 : 48.0 + Double(abs(profile.id.hashValue % 24))
            return [LedgerEntry(
                id: UUID(), employeeID: profile.id, businessID: business.id, type: "opening_balance",
                effectiveDate: today.adding(days: -90), hours: balance,
                description: "Current PTO balance", requestID: nil, createdAt: .now.addingTimeInterval(-86_400 * 90)
            )]
        }

        let todayShiftIDs = (0..<3).map { _ in UUID() }
        var shifts = [
            shift(id: todayShiftIDs[0], business: business, employee: employee, date: today, start: "08:00", end: "17:00", title: "Patient care"),
            shift(id: todayShiftIDs[1], business: business, employee: secondEmployee, date: today, start: "08:30", end: "17:30", title: "Optical floor"),
            shift(id: todayShiftIDs[2], business: business, employee: thirdEmployee, date: today, start: "10:00", end: "18:00", title: "Front desk"),
            shift(id: UUID(), business: business, employee: employee, date: today.adding(days: 1), start: "09:00", end: "17:00", title: "Patient care"),
        ]
        if business.id != griffinID { shifts.removeLast() }

        let mayaSheet = Timesheet(
            id: UUID(), businessID: business.id, employeeID: employee.id, scheduledShiftID: todayShiftIDs[0],
            status: .inProgress, startedAt: date(today, clock: "08:03", timeZone: business.timeZone),
            endedAt: nil, warningFlags: [], systemClosed: false, breaks: []
        )
        let breakStart = date(today, clock: "12:10", timeZone: business.timeZone)
        let jordanSheet = Timesheet(
            id: UUID(), businessID: business.id, employeeID: secondEmployee.id, scheduledShiftID: todayShiftIDs[1],
            status: .inProgress, startedAt: date(today, clock: "08:27", timeZone: business.timeZone),
            endedAt: nil, warningFlags: [], systemClosed: false,
            breaks: [ActualBreak(id: UUID(), type: .unpaidMeal, startedAt: breakStart, endedAt: nil)]
        )
        let samSheet = Timesheet(
            id: UUID(), businessID: business.id, employeeID: fourthEmployee.id, scheduledShiftID: nil,
            status: .pending, startedAt: date(today, clock: "07:55", timeZone: business.timeZone),
            endedAt: date(today, clock: "12:00", timeZone: business.timeZone),
            warningFlags: ["off_schedule"], systemClosed: false, breaks: []
        )
        let notifications = [
            AppNotification(
                id: UUID(), profileID: employee.id, kind: .request, title: "PTO approved",
                body: "Your vacation request was approved.", requestID: approvedID,
                readAt: nil, createdAt: .now.addingTimeInterval(-3_600)
            ),
            AppNotification(
                id: UUID(), profileID: manager.id, kind: .request, title: "Request awaiting review",
                body: "\(secondEmployee.name) submitted a PTO request.", requestID: pendingID,
                readAt: nil, createdAt: .now.addingTimeInterval(-1_800)
            ),
            AppNotification(
                id: UUID(), profileID: owner.id, kind: .request, title: "Manager request awaiting review",
                body: "\(manager.name) submitted a PTO request.", requestID: managerRequestID,
                readAt: nil, createdAt: .now.addingTimeInterval(-900)
            ),
        ]
        let tiers = [
            PolicyTier(id: 1, key: "intro", label: "Intro", minimumMonths: 0, maximumMonths: 6, hoursPerPayPeriod: 1.85, balanceCap: 48),
            PolicyTier(id: 2, key: "established", label: "Established", minimumMonths: 6, maximumMonths: nil, hoursPerPayPeriod: 3.6923, balanceCap: 96),
        ]
        return DomainSnapshot(
            savedAt: .now, business: business, profiles: profiles, requests: requests, ledger: ledger,
            blackouts: [BlackoutPeriod(
                id: UUID(), businessID: business.id, name: "Peak coverage",
                startDate: today.adding(days: 70), endDate: today.adding(days: 75),
                reason: "Historically high patient volume"
            )],
            shifts: shifts, timesheets: [mayaSheet, jordanSheet, samSheet], notifications: notifications,
            policy: .fallback, tiers: tiers
        )
    }

    static func profiles(for business: Business) -> [StaffProfile] {
        let suffix = business.id == griffinID ? "" : " \(business.name.split(separator: " ").first!)"
        let base = business.id == griffinID ? 0 : (business.id == senoiaID ? 100 : 200)
        return [
            profile(id: base == 0 ? mayaID : generatedID(base + 1), auth: generatedID(1_000 + base + 1), business: business, name: "Maya Thompson\(suffix)", role: .employee, title: "Optician", employment: .hourly, color: "#557E70"),
            profile(id: base == 0 ? jordanID : generatedID(base + 2), auth: generatedID(1_000 + base + 2), business: business, name: "Jordan Lee\(suffix)", role: .employee, title: "Optometric Technician", employment: .hourly, color: "#B27052"),
            profile(id: base == 0 ? averyID : generatedID(base + 3), auth: generatedID(1_000 + base + 3), business: business, name: "Avery King\(suffix)", role: .employee, title: "Patient Coordinator", employment: .hourly, color: "#6D7993"),
            profile(id: base == 0 ? samID : generatedID(base + 4), auth: generatedID(1_000 + base + 4), business: business, name: "Sam Rivera\(suffix)", role: .employee, title: "Optician", employment: .hourly, color: "#9C7A4D"),
            profile(id: base == 0 ? elenaID : generatedID(base + 5), auth: generatedID(1_000 + base + 5), business: business, name: "Elena Brooks\(suffix)", role: .officeManager, title: "Office Manager", employment: .salaried, color: "#4C6575"),
            profile(id: base == 0 ? ownerID : generatedID(base + 6), auth: generatedID(1_000 + base + 6), business: business, name: "Dr. Ross Montgomery", role: .ownerAdmin, title: "Owner", employment: .salaried, color: "#453B3D"),
        ]
    }

    static func profile(id: UUID, auth: UUID, business: Business, name: String, role: AppRole, title: String, employment: EmploymentType, color: String) -> StaffProfile {
        StaffProfile(
            id: id, authUserID: auth, businessID: business.id, name: name,
            email: name.lowercased().replacingOccurrences(of: " ", with: ".") + "@demo.ptohub",
            role: role, jobTitle: title, hireDate: DateOnly(year: 2020, month: 1, day: 15),
            employmentType: employment, fullTime: true, status: .active, avatarColor: color
        )
    }

    static func shift(id: UUID, business: Business, employee: StaffProfile, date shiftDate: DateOnly, start: String, end: String, title: String) -> ScheduledShift {
        let startDate = date(shiftDate, clock: start, timeZone: business.timeZone)
        return ScheduledShift(
            id: id, seriesID: nil, businessID: business.id, employeeID: employee.id,
            shiftDate: shiftDate, startsAt: startDate,
            endsAt: date(shiftDate, clock: end, timeZone: business.timeZone),
            status: .published, title: title, notes: "Demo schedule",
            warningFlags: [], isSeriesOverride: false,
            breaks: [ScheduledBreak(
                id: UUID(), shiftID: id, type: .unpaidMeal,
                startsAt: startDate.addingTimeInterval(4 * 3_600), durationMinutes: 30
            )]
        )
    }

    static func date(_ day: DateOnly, clock: String, timeZone: TimeZone) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day,
            hour: parts.first ?? 9, minute: parts.count > 1 ? parts[1] : 0
        )) ?? .now
    }

    private static func id(_ value: String) -> UUID { UUID(uuidString: value)! }
    private static func generatedID(_ value: Int) -> UUID {
        id(String(format: "30000000-0000-0000-0000-%012d", value))
    }
}

private extension DomainSnapshot {
    func replacing(
        requests: [PTORequest]? = nil,
        shifts: [ScheduledShift]? = nil,
        notifications: [AppNotification]? = nil
    ) -> DomainSnapshot {
        DomainSnapshot(
            savedAt: .now, business: business, profiles: profiles,
            requests: requests ?? self.requests, ledger: ledger, blackouts: blackouts,
            shifts: shifts ?? self.shifts, timesheets: timesheets,
            notifications: notifications ?? self.notifications, policy: policy, tiers: tiers
        )
    }
}

private extension PTORequest {
    func replacing(status: PTORequestStatus, decisionNote: String?, decidedBy: UUID?) -> PTORequest {
        PTORequest(
            id: id, employeeID: employeeID, businessID: businessID, category: category,
            status: status, days: days, privateNote: privateNote, decisionNote: decisionNote,
            submittedAt: submittedAt, decidedAt: decidedBy == nil ? decidedAt : .now,
            decidedBy: decidedBy, shortNotice: shortNotice
        )
    }
}
#endif
