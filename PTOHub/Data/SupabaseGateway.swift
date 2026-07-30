import Foundation
@preconcurrency import Supabase

enum AuthSessionEmission: Equatable, Sendable {
    case authenticated(UUID)
    case signedOut
    case awaitingRefresh

    init(userID: UUID?, isExpired: Bool) {
        guard let userID else {
            self = .signedOut
            return
        }
        self = isExpired ? .awaitingRefresh : .authenticated(userID)
    }
}

actor SupabaseGateway: BackendServicing {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserID() async -> UUID? {
        try? await client.auth.session.user.id
    }

    func authUserChanges() async -> AsyncStream<UUID?> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (_, session) in changes {
                    if Task.isCancelled { break }
                    switch AuthSessionEmission(
                        userID: session?.user.id,
                        isExpired: session?.isExpired ?? false
                    ) {
                    case let .authenticated(userID):
                        continuation.yield(userID)
                    case .signedOut:
                        continuation.yield(nil)
                    case .awaitingRefresh:
                        continue
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signIn(email: String, password: String) async throws -> UUID {
        let session = try await client.auth.signIn(email: email, password: password)
        return session.user.id
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func loadIdentity(authUserID: UUID) async throws -> AuthenticatedIdentity {
        let profileDTO: ProfileDTO = try await client
            .from("profiles")
            .select()
            .eq("auth_user_id", value: authUserID.uuidString)
            .single()
            .execute()
            .value
        let businessDTOs: [BusinessDTO] = try await client
            .from("businesses")
            .select("id, slug, name, city, theme_key, timezone")
            .order("name")
            .execute()
            .value
        return AuthenticatedIdentity(
            authUserID: authUserID,
            profile: profileDTO.model,
            businesses: businessDTOs.map(\.model)
        )
    }

    func loadSnapshot(profile: StaffProfile, business: Business) async throws -> DomainSnapshot {
        let from = DateOnly.today(in: business.timeZone).adding(days: -14, in: business.timeZone)
        let to = DateOnly.today(in: business.timeZone).adding(days: 112, in: business.timeZone)

        let profileDTOs: [ProfileDTO]
        let requestDTOs: [PTORequestDTO]
        let ledgerDTOs: [LedgerEntryDTO]
        let shiftDTOs: [ScheduledShiftDTO]
        if profile.role.isManager {
            profileDTOs = try await client.from("profiles").select()
                .eq("business_id", value: business.id.uuidString)
                .order("full_name").execute().value
            requestDTOs = try await client.from("pto_requests")
                .select("*, request_days(*)")
                .eq("business_id", value: business.id.uuidString)
                .order("submitted_at", ascending: false).execute().value
            ledgerDTOs = try await client.from("pto_ledger").select()
                .eq("business_id", value: business.id.uuidString)
                .order("effective_date", ascending: false).execute().value
            shiftDTOs = try await client.from("scheduled_shifts")
                .select("*, scheduled_breaks(*)")
                .eq("business_id", value: business.id.uuidString)
                .gte("shift_date", value: from.description)
                .lte("shift_date", value: to.description)
                .order("starts_at").execute().value
        } else {
            profileDTOs = try await client.from("profiles").select()
                .eq("business_id", value: business.id.uuidString)
                .eq("id", value: profile.id.uuidString)
                .order("full_name").execute().value
            requestDTOs = try await client.from("pto_requests")
                .select("*, request_days(*)")
                .eq("business_id", value: business.id.uuidString)
                .eq("employee_id", value: profile.id.uuidString)
                .order("submitted_at", ascending: false).execute().value
            ledgerDTOs = try await client.from("pto_ledger").select()
                .eq("business_id", value: business.id.uuidString)
                .eq("employee_id", value: profile.id.uuidString)
                .order("effective_date", ascending: false).execute().value
            shiftDTOs = try await client.from("scheduled_shifts")
                .select("*, scheduled_breaks(*)")
                .eq("business_id", value: business.id.uuidString)
                .eq("employee_id", value: profile.id.uuidString)
                .gte("shift_date", value: from.description)
                .lte("shift_date", value: to.description)
                .order("starts_at").execute().value
        }
        let blackoutDTOs: [BlackoutDTO] = try await client
            .from("blackout_periods")
            .select("id, business_id, name, start_date, end_date, reason, cancelled_at")
            .eq("business_id", value: business.id.uuidString)
            .order("start_date")
            .execute()
            .value
        let timesheetDTOs: [TimesheetDTO]
        if profile.role.isManager {
            timesheetDTOs = try await client
                .from("timesheets")
                .select("*, actual_breaks(*)")
                .eq("business_id", value: business.id.uuidString)
                .gte("started_at", value: from.date(in: business.timeZone).ISO8601Format())
                .order("started_at", ascending: false)
                .limit(250)
                .execute()
                .value
        } else {
            timesheetDTOs = []
        }
        let notificationDTOs: [NotificationDTO] = try await client
            .from("notifications")
            .select()
            .eq("profile_id", value: profile.id.uuidString)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        let settingsDTO: PolicySettingsDTO = try await client
            .from("policy_settings")
            .select("planned_notice_days, allowed_request_hours")
            .eq("id", value: true)
            .single()
            .execute()
            .value
        let tierDTOs: [PolicyTierDTO] = try await client
            .from("policy_tiers")
            .select()
            .order("min_months")
            .execute()
            .value

        return DomainSnapshot(
            savedAt: Date(),
            business: business,
            profiles: profileDTOs.map(\.model),
            requests: requestDTOs.map(\.model),
            ledger: ledgerDTOs.map(\.model),
            blackouts: blackoutDTOs.filter { $0.cancelledAt == nil }.map(\.model),
            shifts: shiftDTOs.map(\.model),
            timesheets: timesheetDTOs.map(\.model),
            notifications: notificationDTOs.map(\.model),
            policy: settingsDTO.model,
            tiers: tierDTOs.map(\.model)
        )
    }

    func submitRequest(profile: StaffProfile, draft: PTORequestDraft) async throws {
        let payload = PTORequestInsert(
            employeeID: profile.id,
            businessID: profile.businessID,
            category: draft.category,
            status: .draft,
            privateNote: draft.privateNote
        )
        let created: IDResponse = try await client
            .from("pto_requests")
            .insert(payload)
            .select("id")
            .single()
            .execute()
            .value
        let dayPayloads = draft.days.map { RequestDayInsert(requestID: created.id, date: $0.date.description, hours: $0.hours) }
        try await client.from("request_days").insert(dayPayloads).execute()
        try await client.from("pto_requests")
            .update(StatusOnlyUpdate(status: .pending))
            .eq("id", value: created.id.uuidString)
            .execute()
    }

    func cancelRequest(id: UUID) async throws {
        try await client.from("pto_requests")
            .update(StatusOnlyUpdate(status: .cancelled))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func decideRequest(id: UUID, status: PTORequestStatus, note: String?) async throws {
        let validatedNote = try RequestDecisionValidator.validatedNote(for: status, note: note)
        try await client.from("pto_requests")
            .update(RequestDecisionUpdate(status: status, decisionNote: validatedNote))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func createSchedule(businessID: UUID, actorID: UUID, draft: ScheduleDraft) async throws {
        let payload = ScheduleSeriesInsert(
            businessID: businessID,
            employeeID: draft.employeeID,
            weekdays: draft.weekdays,
            localStartTime: draft.startTime,
            localEndTime: draft.endTime,
            effectiveStart: draft.effectiveStart.description,
            effectiveEnd: draft.effectiveEnd?.description,
            breakTemplate: draft.breaks,
            status: draft.status == .published ? "published" : "draft",
            title: draft.title,
            notes: draft.notes,
            createdBy: actorID
        )
        try await client.from("schedule_series").insert(payload).execute()
    }

    func updateShift(_ update: ScheduledShiftUpdate) async throws {
        let params = UpdateShiftParameters(
            shiftID: update.shiftID,
            employeeID: update.employeeID,
            shiftDate: update.shiftDate.description,
            localStartTime: update.startTime,
            localEndTime: update.endTime,
            title: update.title,
            notes: update.notes ?? "",
            status: update.status.rawValue,
            breaks: update.breaks
        )
        try await client.rpc("update_scheduled_shift", params: params).execute()
    }

    func markNotificationsRead(profileID: UUID) async throws {
        try await client.from("notifications")
            .update(NotificationReadUpdate(readAt: Date().ISO8601Format()))
            .eq("profile_id", value: profileID.uuidString)
            .is("read_at", value: nil)
            .execute()
    }

    func registerMobileDevice(installationID: UUID, token: String, environment: String, bundleID: String) async throws {
        try await client.rpc(
            "register_mobile_device",
            params: RegisterDeviceParameters(
                installationID: installationID,
                token: token,
                environment: environment,
                bundleID: bundleID
            )
        ).execute()
    }

    func unregisterMobileDevice(installationID: UUID, bundleID: String) async throws {
        try await client.rpc(
            "unregister_mobile_device",
            params: UnregisterDeviceParameters(installationID: installationID, bundleID: bundleID)
        ).execute()
    }

    func attendanceEvents(businessID: UUID) async -> AsyncStream<Void> {
        let channelSuffix = businessID.uuidString.lowercased()
        let sheetChannel = client.channel("attendance-sheets-\(channelSuffix)")
        let sheets = sheetChannel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "timesheets",
            filter: .eq("business_id", value: businessID.uuidString)
        )
        let breakChannel = client.channel("attendance-breaks-\(channelSuffix)")
        let breaks = breakChannel.postgresChange(AnyAction.self, schema: "public", table: "actual_breaks")

        return AsyncStream { continuation in
            // Subscribe independently so a delayed or rejected break subscription cannot
            // prevent timesheet events—or the fallback heartbeat—from reaching the UI.
            let sheetSubscriptionTask = Task { try? await sheetChannel.subscribeWithError() }
            let breakSubscriptionTask = Task { try? await breakChannel.subscribeWithError() }
            let sheetTask = Task {
                for await _ in sheets {
                    if Task.isCancelled { break }
                    continuation.yield(())
                }
            }
            let breakTask = Task {
                for await _ in breaks {
                    if Task.isCancelled { break }
                    continuation.yield(())
                }
            }
            // Postgres Changes is the fast path. This heartbeat keeps foregrounded manager
            // attendance current while Realtime is reconnecting or a subscription is delayed.
            let heartbeatTask = Task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) }
                    catch { break }
                    guard !Task.isCancelled else { break }
                    continuation.yield(())
                }
            }
            continuation.onTermination = { [client] _ in
                sheetSubscriptionTask.cancel()
                breakSubscriptionTask.cancel()
                sheetTask.cancel()
                breakTask.cancel()
                heartbeatTask.cancel()
                Task {
                    await client.removeChannel(sheetChannel)
                    await client.removeChannel(breakChannel)
                }
            }
        }
    }
}

private struct IDResponse: Decodable, Sendable { let id: UUID }

private struct PTORequestInsert: Encodable, Sendable {
    let employeeID: UUID
    let businessID: UUID
    let category: PTOCategory
    let status: PTORequestStatus
    let privateNote: String?
    enum CodingKeys: String, CodingKey {
        case category, status
        case employeeID = "employee_id"
        case businessID = "business_id"
        case privateNote = "private_note"
    }
}

private struct RequestDayInsert: Encodable, Sendable {
    let requestID: UUID
    let date: String
    let hours: Int
    enum CodingKeys: String, CodingKey {
        case hours
        case requestID = "request_id"
        case date = "pto_date"
    }
}

private struct StatusOnlyUpdate: Encodable, Sendable { let status: PTORequestStatus }

private struct RequestDecisionUpdate: Encodable, Sendable {
    let status: PTORequestStatus
    let decisionNote: String?
    enum CodingKeys: String, CodingKey {
        case status
        case decisionNote = "decision_note"
    }
}

private struct ScheduleSeriesInsert: Encodable, Sendable {
    let businessID: UUID
    let employeeID: UUID
    let weekdays: [Int]
    let localStartTime: String
    let localEndTime: String
    let effectiveStart: String
    let effectiveEnd: String?
    let breakTemplate: [ScheduleBreakDraft]
    let status: String
    let title: String
    let notes: String?
    let createdBy: UUID
    enum CodingKeys: String, CodingKey {
        case weekdays, status, title, notes
        case businessID = "business_id"
        case employeeID = "employee_id"
        case localStartTime = "local_start_time"
        case localEndTime = "local_end_time"
        case effectiveStart = "effective_start"
        case effectiveEnd = "effective_end"
        case breakTemplate = "break_template"
        case createdBy = "created_by"
    }
}

private struct UpdateShiftParameters: Encodable, Sendable {
    let shiftID: UUID
    let employeeID: UUID
    let shiftDate: String
    let localStartTime: String
    let localEndTime: String
    let title: String
    let notes: String
    let status: String
    let breaks: [ScheduleBreakDraft]
    enum CodingKeys: String, CodingKey {
        case shiftID = "p_shift_id"
        case employeeID = "p_employee_id"
        case shiftDate = "p_shift_date"
        case localStartTime = "p_local_start_time"
        case localEndTime = "p_local_end_time"
        case title = "p_title"
        case notes = "p_notes"
        case status = "p_status"
        case breaks = "p_breaks"
    }
}

private struct NotificationReadUpdate: Encodable, Sendable {
    let readAt: String
    enum CodingKeys: String, CodingKey { case readAt = "read_at" }
}

private struct RegisterDeviceParameters: Encodable, Sendable {
    let installationID: UUID
    let token: String
    let environment: String
    let bundleID: String
    enum CodingKeys: String, CodingKey {
        case installationID = "p_installation_id"
        case token = "p_apns_token"
        case environment = "p_environment"
        case bundleID = "p_bundle_id"
    }
}

private struct UnregisterDeviceParameters: Encodable, Sendable {
    let installationID: UUID
    let bundleID: String
    enum CodingKeys: String, CodingKey {
        case installationID = "p_installation_id"
        case bundleID = "p_bundle_id"
    }
}
