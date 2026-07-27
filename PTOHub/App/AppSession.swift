import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    enum Phase: Equatable {
        case restoring
        case signedOut
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .restoring
    private(set) var identity: AuthenticatedIdentity?
    private(set) var snapshot: DomainSnapshot?
    private(set) var selectedBusinessID: UUID?
    private(set) var isOffline = false
    private(set) var isDemo = false
    private(set) var isMutating = false
    private(set) var lastError: String?
    var selectedTab: AppRoute = .home
    var presentedRequestID: UUID?

    var selectedBusiness: Business? {
        guard let selectedBusinessID else { return nil }
        return identity?.businesses.first(where: { $0.id == selectedBusinessID })
    }

    var canManage: Bool { identity?.profile.role.isManager ?? false }
    var canSwitchBusinesses: Bool { identity?.profile.role == .ownerAdmin }
    var canMutate: Bool { (isDemo || network.isOnline) && phase == .ready && !isMutating }

    let configuration: AppConfiguration

    private let backend: any BackendServicing
    private let cache: any SnapshotCaching
    private let network: NetworkMonitor
    private let push: PushRegistrationManager
#if DEBUG && targetEnvironment(simulator)
    private var demoBackend: DemoBackend?
#endif
    private var authTask: Task<Void, Never>?
    private var attendanceTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var hasBootstrapped = false
    private var restoringUserID: UUID?

    init(
        configuration: AppConfiguration,
        backend: any BackendServicing,
        cache: any SnapshotCaching,
        network: NetworkMonitor,
        push: PushRegistrationManager
    ) {
        self.configuration = configuration
        self.backend = backend
        self.cache = cache
        self.network = network
        self.push = push
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-demo") {
            phase = .signedOut
            return
        }
#endif
        isOffline = !network.isOnline
        authTask = Task { [weak self, backend] in
            let changes = await backend.authUserChanges()
            for await userID in changes {
                guard !Task.isCancelled else { return }
                await self?.handleAuthUser(userID)
            }
        }
        networkTask = Task { [weak self, network] in
            let changes = network.updates()
            for await isOnline in changes {
                guard !Task.isCancelled else { return }
                await self?.handleNetworkChange(isOnline)
            }
        }
        if let userID = await backend.currentUserID() {
            await restoreAuthenticatedSession(userID: userID)
        } else {
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            lastError = "Enter your email and password."
            return
        }
        guard network.isOnline else {
            lastError = "An internet connection is required to sign in."
            return
        }
        phase = .loading
        lastError = nil
#if DEBUG && targetEnvironment(simulator)
        demoBackend = nil
#endif
        isDemo = false
        do {
            let userID = try await backend.signIn(email: email, password: password)
            await restoreAuthenticatedSession(userID: userID)
        } catch {
            phase = .signedOut
            lastError = userFacing(error)
        }
    }

#if DEBUG && targetEnvironment(simulator)
    func signInDemo(role: AppRole) async {
        let demo = DemoBackend(role: role)
        demoBackend = demo
        isDemo = true
        isOffline = false
        lastError = nil
        phase = .loading
        do {
            let userID = await demo.currentUserID()!
            let loadedIdentity = try await demo.loadIdentity(authUserID: userID)
            identity = loadedIdentity
            selectedBusinessID = BusinessSelection.preferredBusinessID(
                profile: loadedIdentity.profile,
                businesses: loadedIdentity.businesses,
                savedBusinessID: nil
            )
            await loadSnapshot(showLoading: true)
            startAttendanceUpdates()
        } catch {
            phase = .failed(userFacing(error))
        }
    }
#endif

    func signOut() async {
        let oldIdentity = identity
        attendanceTask?.cancel()
        attendanceTask = nil
        if !isDemo, let token = push.token {
            _ = token
            try? await backend.unregisterMobileDevice(
                installationID: push.installationID,
                bundleID: Bundle.main.bundleIdentifier ?? "com.griffineyecare.ptohub"
            )
        }
        if !isDemo {
            try? await backend.signOut()
            if let oldIdentity { try? await cache.removeAll(userID: oldIdentity.authUserID) }
        }
#if DEBUG && targetEnvironment(simulator)
        demoBackend = nil
#endif
        isDemo = false
        identity = nil
        selectedBusinessID = nil
        snapshot = nil
        phase = .signedOut
        isOffline = false
    }

    func refresh() async {
        guard identity != nil, selectedBusiness != nil else { return }
        if isDemo {
            await loadSnapshot(showLoading: false)
            return
        }
        guard network.isOnline else {
            isOffline = true
            return
        }
        await loadSnapshot(showLoading: snapshot == nil)
    }

    func selectBusiness(_ business: Business) async {
        guard canSwitchBusinesses, identity?.businesses.contains(business) == true else { return }
        selectedBusinessID = business.id
        if let profileID = identity?.profile.id {
            UserDefaults.standard.set(business.id.uuidString, forKey: "selected-business-\(profileID)")
        }
        snapshot = nil
        startAttendanceUpdates()
        await loadSnapshot(showLoading: true)
        await syncPushRegistration()
    }

    func submitRequest(_ draft: PTORequestDraft) async throws {
        try await performMutation {
            guard let profile = self.identity?.profile else { throw AppError.notAuthenticated }
            try await self.activeBackend.submitRequest(profile: profile, draft: draft)
        }
    }

    func cancelRequest(_ request: PTORequest) async throws {
        try await performMutation {
            try await self.activeBackend.cancelRequest(id: request.id)
        }
    }

    func decideRequest(_ request: PTORequest, status: PTORequestStatus, note: String?) async throws {
        let validatedNote = try RequestDecisionValidator.validatedNote(for: status, note: note)
        try await performMutation {
            try await self.activeBackend.decideRequest(id: request.id, status: status, note: validatedNote)
        }
    }

    func createSchedule(_ draft: ScheduleDraft) async throws {
        try await performMutation {
            guard let identity = self.identity, let business = self.selectedBusiness else {
                throw AppError.notAuthenticated
            }
            try await self.activeBackend.createSchedule(
                businessID: business.id,
                actorID: identity.profile.id,
                draft: draft
            )
        }
    }

    func updateShift(_ update: ScheduledShiftUpdate) async throws {
        try await performMutation { try await self.activeBackend.updateShift(update) }
    }

    func markAllNotificationsRead() async throws {
        try await performMutation(refreshAfter: true) {
            guard let profileID = self.identity?.profile.id else { throw AppError.notAuthenticated }
            try await self.activeBackend.markNotificationsRead(profileID: profileID)
        }
    }

    func route(_ route: AppRoute) {
        switch route {
        case .request(let id):
            selectedTab = .timeOff
            presentedRequestID = id
        case .schedule:
            selectedTab = .schedule
        case .home, .timeOff, .inbox:
            selectedTab = route
        }
    }

    func syncPushRegistration() async {
        guard !isDemo else { return }
        guard network.isOnline,
              identity != nil,
              let token = push.token,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        do {
            try await backend.registerMobileDevice(
                installationID: push.installationID,
                token: token,
                environment: pushEnvironment,
                bundleID: bundleID
            )
        } catch {
            lastError = "Notifications could not be enabled. You can retry from the account menu."
        }
    }

    func requestPushPermission() async {
        if isDemo {
            lastError = "Push notifications are disabled in simulator demo mode."
            return
        }
        guard network.isOnline else {
            lastError = "Connect to the internet before enabling notifications."
            return
        }
        await push.requestAuthorization()
        await syncPushRegistration()
    }

    func clearError() { lastError = nil }

    private var pushEnvironment: String {
#if DEBUG
        "sandbox"
#else
        "production"
#endif
    }

    private var activeBackend: any BackendServicing {
#if DEBUG && targetEnvironment(simulator)
        demoBackend ?? backend
#else
        backend
#endif
    }

    private func restoreAuthenticatedSession(userID: UUID) async {
        guard restoringUserID != userID else { return }
        restoringUserID = userID
        defer { restoringUserID = nil }
        phase = .loading
        do {
            let loadedIdentity = try await backend.loadIdentity(authUserID: userID)
            identity = loadedIdentity
            selectedBusinessID = preferredBusiness(for: loadedIdentity)
            await loadSnapshot(showLoading: true)
            startAttendanceUpdates()
            await syncPushRegistration()
        } catch {
            phase = .failed(userFacing(error))
        }
    }

    private func preferredBusiness(for identity: AuthenticatedIdentity) -> UUID? {
        let saved = UserDefaults.standard.string(forKey: "selected-business-\(identity.profile.id)").flatMap(UUID.init)
        return BusinessSelection.preferredBusinessID(
            profile: identity.profile,
            businesses: identity.businesses,
            savedBusinessID: saved
        )
    }

    private func loadSnapshot(showLoading: Bool) async {
        guard let identity, let business = selectedBusiness else { return }
        if showLoading { phase = .loading }
        do {
            let loaded = try await activeBackend.loadSnapshot(profile: identity.profile, business: business)
            snapshot = loaded
            if !isDemo { try await cache.save(loaded, userID: identity.authUserID, businessID: business.id) }
            isOffline = false
            phase = .ready
            lastError = nil
        } catch {
            if !isDemo, let cached = try? await cache.load(userID: identity.authUserID, businessID: business.id) {
                snapshot = cached
                isOffline = true
                phase = .ready
                lastError = "Showing the last saved update."
            } else {
                phase = .failed(userFacing(error))
            }
        }
    }

    private func performMutation(
        refreshAfter: Bool = true,
        operation: () async throws -> Void
    ) async throws {
        guard canMutate else { throw AppError.offlineMutation }
        isMutating = true
        defer { isMutating = false }
        do {
            try await operation()
            if refreshAfter { await loadSnapshot(showLoading: false) }
        } catch {
            lastError = userFacing(error)
            throw error
        }
    }

    private func startAttendanceUpdates() {
        attendanceTask?.cancel()
        guard let business = selectedBusiness, canManage else { return }
        let source = activeBackend
        attendanceTask = Task { [weak self, source] in
            let changes = await source.attendanceEvents(businessID: business.id)
            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.scheduleRealtimeRefresh()
            }
        }
    }

    private func scheduleRealtimeRefresh() {
        guard network.isOnline else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func handleAuthUser(_ userID: UUID?) async {
        guard !isDemo else { return }
        if let userID {
            if identity?.authUserID != userID { await restoreAuthenticatedSession(userID: userID) }
        } else {
            attendanceTask?.cancel()
            identity = nil
            selectedBusinessID = nil
            snapshot = nil
            phase = .signedOut
        }
    }

    private func handleNetworkChange(_ online: Bool) async {
        if isDemo {
            isOffline = false
            return
        }
        let wasOffline = isOffline
        isOffline = !online
        if online, wasOffline, identity != nil {
            await refresh()
            await syncPushRegistration()
        }
    }

    private func userFacing(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

enum AppError: LocalizedError {
    case notAuthenticated
    case offlineMutation

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Your session has expired. Please sign in again."
        case .offlineMutation: "This action requires an internet connection."
        }
    }
}
