import Foundation

struct AuthenticatedIdentity: Sendable {
    let authUserID: UUID
    let profile: StaffProfile
    let businesses: [Business]
}
protocol BackendServicing: Sendable {
    func currentUserID() async -> UUID?
    func authUserChanges() async -> AsyncStream<UUID?>
    func signIn(email: String, password: String) async throws -> UUID
    func signOut() async throws
    func loadIdentity(authUserID: UUID) async throws -> AuthenticatedIdentity
    func loadSnapshot(profile: StaffProfile, business: Business) async throws -> DomainSnapshot
    func submitRequest(profile: StaffProfile, draft: PTORequestDraft) async throws
    func cancelRequest(id: UUID) async throws
    func decideRequest(id: UUID, status: PTORequestStatus, note: String?) async throws
    func createSchedule(businessID: UUID, actorID: UUID, draft: ScheduleDraft) async throws
    func updateShift(_ update: ScheduledShiftUpdate) async throws
    func markNotificationsRead(profileID: UUID) async throws
    func registerMobileDevice(installationID: UUID, token: String, environment: String, bundleID: String) async throws
    func unregisterMobileDevice(installationID: UUID, bundleID: String) async throws
    func attendanceEvents(businessID: UUID) async -> AsyncStream<Void>
}
