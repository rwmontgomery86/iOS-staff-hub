import SwiftUI

struct TimeOffView: View {
    enum ManagerSection: String, CaseIterable { case approvals = "Team Approvals", mine = "My Time Off" }
    enum StatusFilter: String, CaseIterable { case all = "All", pending = "Pending", approved = "Approved", rejected = "Rejected", cancelled = "Cancelled" }

    @Bindable var session: AppSession
    @State private var managerSection: ManagerSection = .approvals
    @State private var filter: StatusFilter = .all
    @State private var requestPresented = false
    @State private var reviewRequest: PTORequest?

    private var snapshot: DomainSnapshot? { session.snapshot }
    private var profile: StaffProfile? { session.identity?.profile }

    var body: some View {
        Group {
            if let snapshot, let profile {
                List {
                    if profile.role.isManager {
                        Picker("Request view", selection: $managerSection) {
                            ForEach(ManagerSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                    if !profile.role.isManager || managerSection == .mine {
                        balanceSection(snapshot: snapshot, profile: profile)
                    }
                    filterSection
                    let requests = visibleRequests(snapshot: snapshot, profile: profile)
                    if requests.isEmpty {
                        ContentUnavailableView(
                            "No matching requests",
                            systemImage: "calendar.badge.minus",
                            description: Text("Try another filter or create a request.")
                        )
                    } else {
                        Section(profile.role.isManager && managerSection == .approvals ? "Requests to review" : "Request history") {
                            ForEach(requests) { request in
                                RequestRow(
                                    request: request,
                                    employee: snapshot.profiles.first(where: { $0.id == request.employeeID }),
                                    showEmployee: profile.role.isManager && managerSection == .approvals
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if canReview(request, snapshot: snapshot, actor: profile) { reviewRequest = request }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canCancel(request, snapshot: snapshot, profile: profile) {
                                        Button("Cancel", role: .destructive) { cancel(request) }
                                            .disabled(!session.canMutate)
                                    }
                                }
                            }
                        }
                    }
                    if !profile.role.isManager || managerSection == .mine {
                        ledgerSection(snapshot: snapshot, profile: profile)
                    }
                }
                .refreshable { await session.refresh() }
                .sheet(isPresented: $requestPresented) {
                    PTORequestForm(session: session, snapshot: snapshot, profile: profile)
                }
                .sheet(item: $reviewRequest) { request in
                    ApprovalView(
                        session: session,
                        request: request,
                        employee: snapshot.profiles.first(where: { $0.id == request.employeeID })
                    )
                }
                .onAppear {
                    if let id = session.presentedRequestID,
                       let request = snapshot.requests.first(where: { $0.id == id }),
                       canReview(request, snapshot: snapshot, actor: profile) {
                        reviewRequest = request
                    }
                    session.presentedRequestID = nil
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(session.canManage ? "Requests" : "Time Off")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("New Request", systemImage: "plus") { requestPresented = true }
                    .disabled(!session.canMutate)
            }
        }
    }

    private func balanceSection(snapshot: DomainSnapshot, profile: StaffProfile) -> some View {
        let available = PTOCalculation.balance(entries: snapshot.ledger, employeeID: profile.id)
        let reserved = PTOCalculation.reservedHours(
            requests: snapshot.requests,
            employeeID: profile.id,
            today: .today(in: snapshot.business.timeZone)
        )
        return Section("Balance") {
            LabeledContent("Available", value: "\(available.formatted(.number.precision(.fractionLength(1)))) hours")
            LabeledContent("Reserved", value: "\(reserved.formatted(.number.precision(.fractionLength(1)))) hours")
            LabeledContent("Projected", value: "\((available - reserved).formatted(.number.precision(.fractionLength(1)))) hours")
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Status", selection: $filter) {
                ForEach(StatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func ledgerSection(snapshot: DomainSnapshot, profile: StaffProfile) -> some View {
        Section("Balance History") {
            let entries = snapshot.ledger.filter { $0.employeeID == profile.id }.prefix(20)
            if entries.isEmpty {
                Text("No balance activity yet.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries)) { entry in
                    LabeledContent {
                        Text(entry.hours, format: .number.sign(strategy: .always()).precision(.fractionLength(1))) + Text("h")
                    } label: {
                        Text(entry.description)
                        Text(entry.effectiveDate.date().formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        }
    }

    private func visibleRequests(snapshot: DomainSnapshot, profile: StaffProfile) -> [PTORequest] {
        snapshot.requests.filter { request in
            let correctOwner = !profile.role.isManager || managerSection == .mine
                ? request.employeeID == profile.id
                : request.employeeID != profile.id
            let correctStatus = filter == .all || request.status.rawValue == filter.rawValue.lowercased()
            return correctOwner && correctStatus
        }
    }

    private func canReview(_ request: PTORequest, snapshot: DomainSnapshot, actor: StaffProfile) -> Bool {
        guard managerSection == .approvals else { return false }
        let requester = snapshot.profiles.first(where: { $0.id == request.employeeID })
        return RequestPermission.canReview(request: request, requester: requester, actor: actor)
    }

    private func canCancel(_ request: PTORequest, snapshot: DomainSnapshot, profile: StaffProfile) -> Bool {
        RequestPermission.canCancel(
            request: request,
            profile: profile,
            today: .today(in: snapshot.business.timeZone)
        )
    }

    private func cancel(_ request: PTORequest) {
        Task { try? await session.cancelRequest(request) }
    }
}

private struct RequestRow: View {
    let request: PTORequest
    let employee: StaffProfile?
    let showEmployee: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showEmployee, let employee { ProfileAvatar(profile: employee) }
            VStack(alignment: .leading, spacing: 5) {
                Text(showEmployee ? (employee?.name ?? "Team member") : request.category.label).font(.headline)
                if showEmployee { Text(request.category.label).font(.subheadline) }
                Text(request.days.sorted { $0.date < $1.date }.map { "\($0.date.date().formatted(date: .abbreviated, time: .omitted)) · \($0.hours)h" }.joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.secondary)
                if request.shortNotice { Label("Short notice", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange) }
                if let note = request.decisionNote, !note.isEmpty { Text("Manager: \(note)").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(request.status.label)
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(statusColor.opacity(0.14), in: Capsule())
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch request.status {
        case .approved: .green
        case .pending, .draft: .orange
        case .rejected, .cancelled: .red
        }
    }
}

private struct RequestDraftDay: Identifiable {
    let id = UUID()
    var date: Date
    var hours: Int
}

struct PTORequestForm: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: AppSession
    let snapshot: DomainSnapshot
    let profile: StaffProfile
    @State private var category: PTOCategory = .vacation
    @State private var days: [RequestDraftDay]
    @State private var note = ""
    @State private var error: String?

    init(session: AppSession, snapshot: DomainSnapshot, profile: StaffProfile) {
        self.session = session
        self.snapshot = snapshot
        self.profile = profile
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.business.timeZone
        let initial = calendar.date(byAdding: .day, value: snapshot.policy.plannedNoticeDays, to: .now) ?? .now
        _days = State(initialValue: [.init(date: initial, hours: snapshot.policy.allowedRequestHours.first ?? 8)])
    }

    private var available: Double { PTOCalculation.balance(entries: snapshot.ledger, employeeID: profile.id) }
    private var reserved: Double {
        PTOCalculation.reservedHours(requests: snapshot.requests, employeeID: profile.id, today: .today(in: snapshot.business.timeZone))
    }
    private var requested: Int { days.reduce(0) { $0 + $1.hours } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(PTOCategory.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Dates") {
                    ForEach($days) { $day in
                        VStack(alignment: .leading) {
                            DatePicker("Date", selection: $day.date, in: Date.now..., displayedComponents: .date)
                            Picker("Hours", selection: $day.hours) {
                                ForEach(snapshot.policy.allowedRequestHours, id: \.self) { Text("\($0) hours").tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .swipeActions {
                            if days.count > 1 {
                                Button("Remove", role: .destructive) { days.removeAll { $0.id == day.id } }
                            }
                        }
                    }
                    Button("Add Another Date", systemImage: "plus") {
                        let next = Calendar.current.date(byAdding: .day, value: 1, to: days.last?.date ?? .now) ?? .now
                        days.append(.init(date: next, hours: snapshot.policy.allowedRequestHours.first ?? 8))
                    }
                }
                Section("Private note") {
                    TextField("Required for illness and bereavement", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                    Text("Only authorized managers can see this note.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Projected Balance") {
                    LabeledContent("Available", value: "\(available.formatted(.number.precision(.fractionLength(1))))h")
                    LabeledContent("Already reserved", value: "−\(reserved.formatted(.number.precision(.fractionLength(1))))h")
                    LabeledContent("This request", value: "−\(requested)h")
                    LabeledContent("After request", value: "\((available - reserved - Double(requested)).formatted(.number.precision(.fractionLength(1))))h")
                }
                if category.isPlanned {
                    Section {
                        Text("Vacation and personal requests require \(snapshot.policy.plannedNoticeDays) days’ notice and cannot overlap a blackout period.")
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle("Request Time Off")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Submit") { submit() }.disabled(session.isMutating) }
            }
        }
    }

    private func submit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.business.timeZone
        let draft = PTORequestDraft(
            category: category,
            days: days.map { (DateOnly(date: $0.date, calendar: calendar), $0.hours) },
            privateNote: note.nilIfBlank
        )
        do {
            try PTORequestValidator.validate(
                draft: draft,
                available: available,
                alreadyReserved: reserved,
                blackouts: snapshot.blackouts,
                policy: snapshot.policy,
                today: .today(in: snapshot.business.timeZone)
            )
        } catch {
            self.error = error.localizedDescription
            return
        }
        Task {
            do { try await session.submitRequest(draft); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct ApprovalView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: AppSession
    let request: PTORequest
    let employee: StaffProfile?
    @State private var rejectionNote = ""
    @State private var error: String?
    @FocusState private var rejectionNoteFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Team member", value: employee?.name ?? "Team member")
                    LabeledContent("Category", value: request.category.label)
                    LabeledContent("Total", value: "\(request.hours) hours")
                    ForEach(request.days.sorted { $0.date < $1.date }) { day in
                        LabeledContent(day.date.date().formatted(date: .complete, time: .omitted), value: "\(day.hours)h")
                    }
                }
                if let note = request.privateNote, !note.isEmpty {
                    Section("Private employee note") { Text(note) }
                }
                Section {
                    TextField("Required rejection reason", text: $rejectionNote, axis: .vertical)
                        .lineLimit(3...5)
                        .focused($rejectionNoteFocused)
                        .onChange(of: rejectionNote) { _, _ in error = nil }
                } header: {
                    Text("Reject with note")
                } footer: {
                    Text("A reason is required and will be shown to the employee.")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Section {
                    Button("Approve Request", systemImage: "checkmark.circle.fill") { decide(.approved) }
                        .disabled(session.isMutating)
                    Button("Reject Request", systemImage: "xmark.circle.fill", role: .destructive) { decide(.rejected) }
                        .disabled(session.isMutating)
                }
            }
            .navigationTitle("Review Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func decide(_ status: PTORequestStatus) {
        let validatedNote: String?
        do {
            validatedNote = try RequestDecisionValidator.validatedNote(for: status, note: rejectionNote)
        } catch {
            self.error = error.localizedDescription
            if status == .rejected { rejectionNoteFocused = true }
            return
        }

        Task {
            do {
                try await session.decideRequest(request, status: status, note: validatedNote)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
