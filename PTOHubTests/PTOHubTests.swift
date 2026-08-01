import XCTest
@testable import PTOHub

final class PTOHubTests: XCTestCase {
    func testDateOnlyOrderingAndAddition() {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let date = DateOnly(year: 2026, month: 12, day: 31)
        XCTAssertEqual(date.adding(days: 1, in: timeZone), DateOnly(year: 2027, month: 1, day: 1))
        XCTAssertLessThan(date, DateOnly(year: 2027, month: 1, day: 1))
    }

    func testRequestValidatorRejectsDuplicateDates() {
        let day = DateOnly(year: 2026, month: 9, day: 15)
        let draft = PTORequestDraft(category: .illness, days: [(day, 4), (day, 4)], privateNote: "Medical appointment")
        XCTAssertThrowsError(
            try PTORequestValidator.validate(
                draft: draft,
                available: 40,
                alreadyReserved: 0,
                blackouts: [],
                policy: .fallback,
                today: DateOnly(year: 2026, month: 8, day: 1)
            )
        )
    }

    func testRequestValidatorRequiresPrivateNoteForIllness() {
        let draft = PTORequestDraft(
            category: .illness,
            days: [(DateOnly(year: 2026, month: 8, day: 2), 8)],
            privateNote: nil
        )
        XCTAssertThrowsError(
            try PTORequestValidator.validate(
                draft: draft,
                available: 40,
                alreadyReserved: 0,
                blackouts: [],
                policy: .fallback,
                today: DateOnly(year: 2026, month: 8, day: 1)
            )
        )
    }

    func testRejectionRequiresAndTrimsDecisionReason() throws {
        XCTAssertThrowsError(
            try RequestDecisionValidator.validatedNote(for: .rejected, note: "  \n ")
        ) { error in
            XCTAssertEqual(
                error as? ValidationError,
                ValidationError("Enter a reason before rejecting this request.")
            )
        }
        XCTAssertEqual(
            try RequestDecisionValidator.validatedNote(for: .rejected, note: "  Coverage unavailable  \n"),
            "Coverage unavailable"
        )
        XCTAssertNil(try RequestDecisionValidator.validatedNote(for: .approved, note: "Ignored"))
    }

    func testPTOBalanceReservationAndProjectedBalanceRules() {
        let employeeID = UUID(), businessID = UUID()
        let entries = [
            ledger(employeeID: employeeID, businessID: businessID, type: "accrual", hours: 24),
            ledger(employeeID: employeeID, businessID: businessID, type: "usage", hours: -8),
        ]
        let future = DateOnly(year: 2026, month: 10, day: 1)
        let requests = [request(employeeID: employeeID, businessID: businessID, status: .approved, date: future, hours: 8)]
        XCTAssertEqual(PTOCalculation.balance(entries: entries, employeeID: employeeID), 16)
        XCTAssertEqual(PTOCalculation.reservedHours(requests: requests, employeeID: employeeID, today: DateOnly(year: 2026, month: 9, day: 1)), 8)

        let draft = PTORequestDraft(category: .vacation, days: [(future.adding(days: 1), 8)], privateNote: nil)
        XCTAssertThrowsError(try PTORequestValidator.validate(
            draft: draft,
            available: 16,
            alreadyReserved: 12,
            blackouts: [],
            policy: .fallback,
            today: DateOnly(year: 2026, month: 9, day: 1)
        ))
    }

    func testRequestValidatorRejectsPlannedBlackoutDates() {
        let businessID = UUID()
        let date = DateOnly(year: 2026, month: 10, day: 15)
        let blackout = BlackoutPeriod(
            id: UUID(), businessID: businessID, name: "Coverage", startDate: date,
            endDate: date.adding(days: 2), reason: "Patient volume"
        )
        let draft = PTORequestDraft(category: .vacation, days: [(date, 8)], privateNote: nil)
        XCTAssertThrowsError(try PTORequestValidator.validate(
            draft: draft,
            available: 40,
            alreadyReserved: 0,
            blackouts: [blackout],
            policy: .fallback,
            today: DateOnly(year: 2026, month: 9, day: 1)
        ))
    }

    func testRequestPermissionPreventsSelfApprovalAndRequiresOwnerForManagers() {
        let businessID = UUID()
        let employee = profile(id: UUID(), businessID: businessID, employmentType: .hourly)
        let officeManager = profile(id: UUID(), businessID: businessID, employmentType: .salaried, role: .officeManager)
        let owner = profile(id: UUID(), businessID: businessID, employmentType: .salaried, role: .ownerAdmin)
        let employeeRequest = request(employeeID: employee.id, businessID: businessID, status: .pending)
        let managerRequest = request(employeeID: officeManager.id, businessID: businessID, status: .pending)
        let selfRequest = request(employeeID: officeManager.id, businessID: businessID, status: .pending)

        XCTAssertTrue(RequestPermission.canReview(request: employeeRequest, requester: employee, actor: officeManager))
        XCTAssertFalse(RequestPermission.canReview(request: managerRequest, requester: officeManager, actor: officeManager))
        XCTAssertFalse(RequestPermission.canReview(request: selfRequest, requester: officeManager, actor: officeManager))
        XCTAssertTrue(RequestPermission.canReview(request: managerRequest, requester: officeManager, actor: owner))
    }

    func testRequestCancellationRequiresOwnershipAndFutureDate() {
        let businessID = UUID()
        let employee = profile(id: UUID(), businessID: businessID, employmentType: .hourly)
        let other = profile(id: UUID(), businessID: businessID, employmentType: .hourly)
        let today = DateOnly(year: 2026, month: 9, day: 1)
        let future = request(employeeID: employee.id, businessID: businessID, status: .approved, date: today.adding(days: 1))
        let past = request(employeeID: employee.id, businessID: businessID, status: .approved, date: today.adding(days: -1))

        XCTAssertTrue(RequestPermission.canCancel(request: future, profile: employee, today: today))
        XCTAssertFalse(RequestPermission.canCancel(request: future, profile: other, today: today))
        XCTAssertFalse(RequestPermission.canCancel(request: past, profile: employee, today: today))
    }

    func testAttendanceClassifierDistinguishesActiveBreakAndSalary() {
        let businessID = UUID()
        let hourly = profile(id: UUID(), businessID: businessID, employmentType: .hourly)
        let salaried = profile(id: UUID(), businessID: businessID, employmentType: .salaried)
        let activeBreak = ActualBreak(id: UUID(), type: .unpaidMeal, startedAt: .now, endedAt: nil)
        let sheet = Timesheet(
            id: UUID(), businessID: businessID, employeeID: hourly.id, scheduledShiftID: nil,
            status: .inProgress, startedAt: .now, endedAt: nil, warningFlags: [], systemClosed: false,
            breaks: [activeBreak]
        )
        let records = AttendanceClassifier.records(
            profiles: [hourly, salaried], shifts: [], timesheets: [sheet], date: DateOnly(date: .now)
        )
        XCTAssertEqual(records.first(where: { $0.profile.id == hourly.id })?.state, .onBreak)
        XCTAssertEqual(records.first(where: { $0.profile.id == salaried.id })?.state, .noClockRequired)
    }

    func testAttendanceClassificationUsesBusinessTimezoneAtDateBoundary() {
        let businessID = UUID(), employeeID = UUID()
        let employee = profile(id: employeeID, businessID: businessID, employmentType: .hourly)
        let instant = ISO8601DateFormatter().date(from: "2026-08-02T05:00:00Z")!
        let sheet = Timesheet(
            id: UUID(), businessID: businessID, employeeID: employeeID, scheduledShiftID: nil,
            status: .inProgress, startedAt: instant, endedAt: nil, warningFlags: [], systemClosed: false,
            breaks: []
        )
        let records = AttendanceClassifier.records(
            profiles: [employee], shifts: [], timesheets: [sheet],
            date: DateOnly(year: 2026, month: 8, day: 1),
            timeZone: TimeZone(identifier: "Pacific/Honolulu")!
        )
        XCTAssertEqual(records.first?.state, .clockedIn)
    }

    func testBusinessDecodingPreservesTimezoneAndTheme() throws {
        let id = UUID()
        let json = """
        {"id":"\(id)","slug":"griffin-eye-care","name":"Griffin Eye Care","city":"Griffin","theme_key":"griffin-eye-care","timezone":"America/New_York"}
        """.data(using: .utf8)!
        let business = try JSONDecoder().decode(BusinessDTO.self, from: json).model
        XCTAssertEqual(business.themeKey, "griffin-eye-care")
        XCTAssertEqual(business.timeZone.identifier, "America/New_York")
    }

    func testSnapshotCacheIsIsolatedByUserAndBusiness() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCache(rootURL: root)
        let userA = UUID(), userB = UUID(), businessA = UUID(), businessB = UUID()
        let snapshot = emptySnapshot(businessID: businessA)
        try await cache.save(snapshot, userID: userA, businessID: businessA)
        let matching = try await cache.load(userID: userA, businessID: businessA)
        let otherBusiness = try await cache.load(userID: userA, businessID: businessB)
        let otherUser = try await cache.load(userID: userB, businessID: businessA)
        XCTAssertNotNil(matching)
        XCTAssertNil(otherBusiness)
        XCTAssertNil(otherUser)
        try await cache.removeAll(userID: userA)
        let removed = try await cache.load(userID: userA, businessID: businessA)
        XCTAssertNil(removed)
    }

    func testOwnerBusinessSelectionRestoresOnlyAnAuthorizedBusiness() {
        let home = business(name: "Griffin")
        let saved = business(name: "Senoia")
        let unknown = UUID()
        let owner = profile(id: UUID(), businessID: home.id, employmentType: .salaried, role: .ownerAdmin)
        let employee = profile(id: UUID(), businessID: home.id, employmentType: .hourly)

        XCTAssertEqual(BusinessSelection.preferredBusinessID(profile: owner, businesses: [home, saved], savedBusinessID: saved.id), saved.id)
        XCTAssertEqual(BusinessSelection.preferredBusinessID(profile: owner, businesses: [home, saved], savedBusinessID: unknown), home.id)
        XCTAssertEqual(BusinessSelection.preferredBusinessID(profile: employee, businesses: [home, saved], savedBusinessID: saved.id), home.id)
    }

    func testPushRoutingUsesRequestThenScheduleThenInbox() {
        let requestID = UUID()
        XCTAssertEqual(PushRouter.route(userInfo: ["kind": "request", "requestId": requestID.uuidString]), .request(requestID))
        XCTAssertEqual(PushRouter.route(userInfo: ["kind": "schedule"]), .schedule)
        XCTAssertEqual(PushRouter.route(userInfo: ["kind": "system"]), .inbox)
    }

    func testExpiredInitialAuthSessionWaitsForRefreshBeforeAuthenticating() {
        let userID = UUID()

        XCTAssertEqual(
            AuthSessionEmission(userID: userID, isExpired: true),
            .awaitingRefresh
        )
        XCTAssertEqual(
            AuthSessionEmission(userID: userID, isExpired: false),
            .authenticated(userID)
        )
        XCTAssertEqual(
            AuthSessionEmission(userID: nil, isExpired: false),
            .signedOut
        )
    }

    func testScheduleWeekUsesSundayThroughSaturdayBoundaries() {
        let timeZone = TimeZone(identifier: "America/New_York")!
        let saturday = DateOnly(year: 2026, month: 8, day: 1)
        let start = SchedulePresentation.weekStart(containing: saturday, timeZone: timeZone)
        let days = SchedulePresentation.weekDays(starting: start, timeZone: timeZone)

        XCTAssertEqual(start, DateOnly(year: 2026, month: 7, day: 26))
        XCTAssertEqual(days.last, saturday)
        XCTAssertEqual(days.count, 7)
    }

    func testScheduleVisibilityIsRoleSpecific() {
        let businessID = UUID()
        let employee = profile(id: UUID(), businessID: businessID, employmentType: .hourly)
        let manager = profile(id: UUID(), businessID: businessID, employmentType: .salaried, role: .officeManager)
        let coworkerID = UUID()
        let ownPublished = scheduledShift(employeeID: employee.id, businessID: businessID, status: .published)
        let ownDraft = scheduledShift(employeeID: employee.id, businessID: businessID, status: .draft)
        let coworker = scheduledShift(employeeID: coworkerID, businessID: businessID, status: .published)
        let cancelled = scheduledShift(employeeID: coworkerID, businessID: businessID, status: .cancelled)

        XCTAssertEqual(SchedulePresentation.visibleShifts(from: [ownPublished, ownDraft, coworker, cancelled], for: employee), [ownPublished])
        XCTAssertEqual(Set(SchedulePresentation.visibleShifts(from: [ownPublished, ownDraft, coworker, cancelled], for: manager)), Set([ownPublished, ownDraft, coworker]))
    }

    @MainActor
    func testPersistedSessionRestoresOnBootstrapAndOrdinaryRelaunch() async throws {
        let fixture = sessionFixture()
        let backend = SessionTestBackend(userID: fixture.userID, identity: fixture.identity, snapshot: fixture.snapshot)
        let cache = SessionTestCache()

        let first = makeSession(backend: backend, cache: cache)
        await first.bootstrap()
        XCTAssertEqual(first.phase, .ready)
        XCTAssertEqual(first.identity?.authUserID, fixture.userID)

        let relaunched = makeSession(backend: backend, cache: cache)
        await relaunched.bootstrap()
        XCTAssertEqual(relaunched.phase, .ready)
        XCTAssertEqual(relaunched.identity?.authUserID, fixture.userID)
    }

    @MainActor
    func testExplicitSignOutClearsSessionAndCachedUserData() async throws {
        let fixture = sessionFixture()
        let backend = SessionTestBackend(userID: fixture.userID, identity: fixture.identity, snapshot: fixture.snapshot)
        let cache = SessionTestCache()
        let session = makeSession(backend: backend, cache: cache)
        await session.bootstrap()

        await session.signOut()

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(session.identity)
        XCTAssertNil(session.snapshot)
        let didSignOut = await backend.didSignOut()
        let removedUsers = await cache.removedUsers()
        XCTAssertTrue(didSignOut)
        XCTAssertEqual(removedUsers, [fixture.userID])
    }

#if DEBUG && targetEnvironment(simulator)
    func testDemoEmployeeLoadsOnlyTheirOperationalDataAndCanSubmitLocally() async throws {
        let backend = DemoBackend(role: .employee)
        let currentUserID = await backend.currentUserID()
        let userID = try XCTUnwrap(currentUserID)
        let identity = try await backend.loadIdentity(authUserID: userID)
        let business = try XCTUnwrap(identity.businesses.first)
        let before = try await backend.loadSnapshot(profile: identity.profile, business: business)

        XCTAssertEqual(identity.profile.role, .employee)
        XCTAssertTrue(before.requests.allSatisfy { $0.employeeID == identity.profile.id })
        XCTAssertTrue(before.shifts.allSatisfy { $0.employeeID == identity.profile.id && $0.status == .published })

        let requestDate = DateOnly.today(in: business.timeZone).adding(days: 35)
        try await backend.submitRequest(
            profile: identity.profile,
            draft: PTORequestDraft(category: .vacation, days: [(requestDate, 8)], privateNote: "Demo request")
        )
        let after = try await backend.loadSnapshot(profile: identity.profile, business: business)
        XCTAssertEqual(after.requests.count, before.requests.count + 1)
        XCTAssertEqual(after.requests.last?.status, .pending)
    }

    func testDemoManagerCanApproveAndOwnerCanSwitchBusinesses() async throws {
        let managerBackend = DemoBackend(role: .officeManager)
        let currentManagerID = await managerBackend.currentUserID()
        let managerID = try XCTUnwrap(currentManagerID)
        let manager = try await managerBackend.loadIdentity(authUserID: managerID)
        let managerBusiness = try XCTUnwrap(manager.businesses.first)
        let before = try await managerBackend.loadSnapshot(profile: manager.profile, business: managerBusiness)
        let employeeRequest = try XCTUnwrap(before.requests.first {
            $0.status == .pending && $0.employeeID != manager.profile.id
        })
        try await managerBackend.decideRequest(id: employeeRequest.id, status: .approved, note: nil)
        let after = try await managerBackend.loadSnapshot(profile: manager.profile, business: managerBusiness)
        XCTAssertEqual(after.requests.first(where: { $0.id == employeeRequest.id })?.status, .approved)

        let ownerBackend = DemoBackend(role: .ownerAdmin)
        let currentOwnerID = await ownerBackend.currentUserID()
        let ownerID = try XCTUnwrap(currentOwnerID)
        let owner = try await ownerBackend.loadIdentity(authUserID: ownerID)
        XCTAssertEqual(owner.businesses.count, 3)
        for business in owner.businesses {
            let snapshot = try await ownerBackend.loadSnapshot(profile: owner.profile, business: business)
            XCTAssertEqual(snapshot.business.id, business.id)
        }
    }
#endif

    private func profile(
        id: UUID,
        businessID: UUID,
        employmentType: EmploymentType,
        role: AppRole = .employee
    ) -> StaffProfile {
        StaffProfile(
            id: id, authUserID: UUID(), businessID: businessID, name: "Test Employee",
            email: "employee-\(id)@example.test", role: role, jobTitle: "Team Member",
            hireDate: DateOnly(year: 2020, month: 1, day: 1), employmentType: employmentType,
            fullTime: true, status: .active, avatarColor: "#557e70"
        )
    }

    private func business(name: String) -> Business {
        Business(
            id: UUID(), slug: name.lowercased(), name: name, city: "Test", themeKey: name.lowercased(),
            timeZoneIdentifier: "America/New_York"
        )
    }

    private func ledger(employeeID: UUID, businessID: UUID, type: String, hours: Double) -> LedgerEntry {
        LedgerEntry(
            id: UUID(), employeeID: employeeID, businessID: businessID, type: type,
            effectiveDate: DateOnly(year: 2026, month: 1, day: 1), hours: hours,
            description: type, requestID: nil, createdAt: .now
        )
    }

    private func request(
        employeeID: UUID,
        businessID: UUID,
        status: PTORequestStatus,
        date: DateOnly = DateOnly(year: 2026, month: 10, day: 1),
        hours: Int = 8
    ) -> PTORequest {
        PTORequest(
            id: UUID(), employeeID: employeeID, businessID: businessID, category: .vacation,
            status: status, days: [.init(id: UUID(), date: date, hours: hours)], privateNote: nil,
            decisionNote: nil, submittedAt: .now, decidedAt: nil, decidedBy: nil, shortNotice: false
        )
    }

    private func emptySnapshot(businessID: UUID) -> DomainSnapshot {
        DomainSnapshot(
            savedAt: .now,
            business: Business(
                id: businessID, slug: "test", name: "Test", city: "Test", themeKey: "test",
                timeZoneIdentifier: "America/New_York"
            ),
            profiles: [], requests: [], ledger: [], blackouts: [], shifts: [], timesheets: [],
            notifications: [], policy: .fallback, tiers: []
        )
    }

    private func scheduledShift(employeeID: UUID, businessID: UUID, status: ShiftStatus) -> ScheduledShift {
        ScheduledShift(
            id: UUID(), seriesID: nil, businessID: businessID, employeeID: employeeID,
            shiftDate: DateOnly(year: 2026, month: 8, day: 1), startsAt: .now,
            endsAt: .now.addingTimeInterval(8 * 60 * 60), status: status,
            title: "Office shift", notes: nil, warningFlags: [], isSeriesOverride: false, breaks: []
        )
    }

    private func sessionFixture() -> (userID: UUID, identity: AuthenticatedIdentity, snapshot: DomainSnapshot) {
        let userID = UUID()
        let business = business(name: "Griffin")
        let staff = StaffProfile(
            id: UUID(), authUserID: userID, businessID: business.id, name: "Session Tester",
            email: "session@example.test", role: .employee, jobTitle: "Optician",
            hireDate: DateOnly(year: 2020, month: 1, day: 1), employmentType: .hourly,
            fullTime: true, status: .active, avatarColor: "#557e70"
        )
        let identity = AuthenticatedIdentity(authUserID: userID, profile: staff, businesses: [business])
        let snapshot = DomainSnapshot(
            savedAt: .now, business: business, profiles: [staff], requests: [], ledger: [],
            blackouts: [], shifts: [], timesheets: [], notifications: [], policy: .fallback, tiers: []
        )
        return (userID, identity, snapshot)
    }

    @MainActor
    private func makeSession(backend: SessionTestBackend, cache: SessionTestCache) -> AppSession {
        AppSession(
            configuration: AppConfiguration(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "test-key",
                webURL: URL(string: "https://example.test")!
            ),
            backend: backend,
            cache: cache,
            network: NetworkMonitor(),
            push: PushRegistrationManager()
        )
    }
}

private actor SessionTestCache: SnapshotCaching {
    private var snapshots: [String: DomainSnapshot] = [:]
    private var removed: [UUID] = []

    func load(userID: UUID, businessID: UUID) async throws -> DomainSnapshot? { snapshots["\(userID)-\(businessID)"] }
    func save(_ snapshot: DomainSnapshot, userID: UUID, businessID: UUID) async throws { snapshots["\(userID)-\(businessID)"] = snapshot }
    func removeAll(userID: UUID) async throws { removed.append(userID) }
    func removedUsers() -> [UUID] { removed }
}

private actor SessionTestBackend: BackendServicing {
    private var userID: UUID?
    private let identity: AuthenticatedIdentity
    private let snapshot: DomainSnapshot
    private var signedOut = false

    init(userID: UUID, identity: AuthenticatedIdentity, snapshot: DomainSnapshot) {
        self.userID = userID
        self.identity = identity
        self.snapshot = snapshot
    }

    func currentUserID() async -> UUID? { userID }
    func authUserChanges() async -> AsyncStream<UUID?> { AsyncStream { _ in } }
    func signIn(email: String, password: String) async throws -> UUID { identity.authUserID }
    func signOut() async throws { signedOut = true; userID = nil }
    func loadIdentity(authUserID: UUID) async throws -> AuthenticatedIdentity { identity }
    func loadSnapshot(profile: StaffProfile, business: Business) async throws -> DomainSnapshot { snapshot }
    func submitRequest(profile: StaffProfile, draft: PTORequestDraft) async throws {}
    func cancelRequest(id: UUID) async throws {}
    func decideRequest(id: UUID, status: PTORequestStatus, note: String?) async throws {}
    func createSchedule(businessID: UUID, actorID: UUID, draft: ScheduleDraft) async throws {}
    func updateShift(_ update: ScheduledShiftUpdate) async throws {}
    func markNotificationsRead(profileID: UUID) async throws {}
    func registerMobileDevice(installationID: UUID, token: String, environment: String, bundleID: String) async throws {}
    func unregisterMobileDevice(installationID: UUID, bundleID: String) async throws {}
    func attendanceEvents(businessID: UUID) async -> AsyncStream<Void> { AsyncStream { _ in } }
    func didSignOut() -> Bool { signedOut }
}
