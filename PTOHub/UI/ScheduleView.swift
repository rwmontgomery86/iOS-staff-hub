import SwiftUI

struct ScheduleView: View {
    @Bindable var session: AppSession
    @State private var createPresented = false
    @State private var editingShift: ScheduledShift?

    private var snapshot: DomainSnapshot? { session.snapshot }
    private var visibleShifts: [ScheduledShift] {
        guard let snapshot, let profile = session.identity?.profile else { return [] }
        return snapshot.shifts.filter { shift in
            if profile.role.isManager { return shift.status != .cancelled }
            return shift.employeeID == profile.id && shift.status == .published
        }
    }
    private var groups: [(DateOnly, [ScheduledShift])] {
        Dictionary(grouping: visibleShifts, by: \.shiftDate)
            .map { ($0.key, $0.value.sorted { $0.startsAt < $1.startsAt }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        Group {
            if let snapshot {
                List {
                    if groups.isEmpty {
                        ContentUnavailableView(
                            "No scheduled shifts",
                            systemImage: "calendar.badge.clock",
                            description: Text("Published shifts will appear here.")
                        )
                    } else {
                        ForEach(groups, id: \.0) { date, shifts in
                            Section(AppDateFormatter.fullDate(date, timeZone: snapshot.business.timeZone)) {
                                ForEach(shifts) { shift in
                                    Button {
                                        if session.canManage && !isLocked(shift, snapshot: snapshot) {
                                            editingShift = shift
                                        }
                                    } label: {
                                        ShiftRow(
                                            shift: shift,
                                            employee: snapshot.profiles.first(where: { $0.id == shift.employeeID }),
                                            timeZone: snapshot.business.timeZone,
                                            manager: session.canManage,
                                            locked: isLocked(shift, snapshot: snapshot)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!session.canManage || isLocked(shift, snapshot: snapshot))
                                }
                            }
                        }
                    }
                }
                .refreshable { await session.refresh() }
                .sheet(isPresented: $createPresented) {
                    ScheduleForm(session: session, snapshot: snapshot)
                }
                .sheet(item: $editingShift) { shift in
                    ShiftEditForm(session: session, snapshot: snapshot, shift: shift)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            if session.canManage {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add Shift", systemImage: "plus") { createPresented = true }
                        .disabled(!session.canMutate)
                }
            }
        }
    }

    private func isLocked(_ shift: ScheduledShift, snapshot: DomainSnapshot) -> Bool {
        shift.shiftDate < .today(in: snapshot.business.timeZone)
            || snapshot.timesheets.contains(where: { $0.scheduledShiftID == shift.id })
    }
}

private struct ShiftRow: View {
    let shift: ScheduledShift
    let employee: StaffProfile?
    let timeZone: TimeZone
    let manager: Bool
    let locked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(shift.title.isEmpty ? "Scheduled shift" : shift.title).font(.headline)
                    if shift.status == .draft {
                        Text("DRAFT").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                if manager, let employee { Text(employee.name).font(.subheadline) }
                Text("\(AppDateFormatter.time(shift.startsAt, timeZone: timeZone))–\(AppDateFormatter.time(shift.endsAt, timeZone: timeZone))")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !shift.breaks.isEmpty {
                    Text(shift.breaks.map { "\($0.durationMinutes)m \($0.type.label.lowercased())" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notes = shift.notes, !notes.isEmpty {
                    Label(notes, systemImage: "note.text").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if locked { Image(systemName: "lock.fill").foregroundStyle(.tertiary).accessibilityLabel("Locked") }
            else if manager { Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true) }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct ScheduleForm: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: AppSession
    let snapshot: DomainSnapshot
    @State private var employeeID: UUID?
    @State private var recurrence = false
    @State private var weekdays: Set<Int> = []
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var hasEndDate = false
    @State private var startTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var endTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now
    @State private var title = "Office shift"
    @State private var notes = ""
    @State private var published = true
    @State private var includesMeal = true
    @State private var error: String?

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Team member") {
                    Picker("Employee", selection: $employeeID) {
                        Text("Choose employee").tag(UUID?.none)
                        ForEach(snapshot.profiles.filter { $0.status == .active }) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                }
                Section("Timing") {
                    Toggle("Repeat weekly", isOn: $recurrence)
                    DatePicker(recurrence ? "Starts" : "Date", selection: $startDate, displayedComponents: .date)
                    if recurrence {
                        HStack {
                            ForEach(0..<7, id: \.self) { day in
                                Button(weekdayLabels[day]) {
                                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(weekdays.contains(day) ? .accentColor : .gray.opacity(0.35))
                                .accessibilityLabel(Calendar.current.weekdaySymbols[day])
                                .accessibilityAddTraits(weekdays.contains(day) ? .isSelected : [])
                            }
                        }
                        Toggle("End repeating shifts", isOn: $hasEndDate)
                        if hasEndDate { DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date) }
                    }
                    DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End time", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section("Details") {
                    TextField("Label", text: $title)
                    TextField("Manager notes", text: $notes, axis: .vertical)
                    Toggle("30-minute unpaid meal", isOn: $includesMeal)
                    Toggle("Publish immediately", isOn: $published)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle("New Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(employeeID == nil || session.isMutating)
                }
            }
        }
    }

    private func save() {
        guard let employeeID else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.business.timeZone
        let startDay = DateOnly(date: startDate, calendar: calendar)
        let selectedWeekdays = recurrence ? Array(weekdays).sorted() : [calendar.component(.weekday, from: startDate) - 1]
        guard !selectedWeekdays.isEmpty else { error = "Choose at least one weekday."; return }
        guard endTime > startTime else { error = "End time must be after start time."; return }
        let draft = ScheduleDraft(
            employeeID: employeeID,
            weekdays: selectedWeekdays,
            startTime: clockString(startTime, timeZone: snapshot.business.timeZone),
            endTime: clockString(endTime, timeZone: snapshot.business.timeZone),
            effectiveStart: startDay,
            effectiveEnd: recurrence && hasEndDate ? DateOnly(date: endDate, calendar: calendar) : (recurrence ? nil : startDay),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.nilIfBlank,
            status: published ? .published : .draft,
            breaks: includesMeal ? [.init(type: .unpaidMeal, durationMinutes: 30, startOffsetMinutes: 240)] : []
        )
        Task {
            do { try await session.createSchedule(draft); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct ShiftEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: AppSession
    let snapshot: DomainSnapshot
    let shift: ScheduledShift
    @State private var employeeID: UUID
    @State private var shiftDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var title: String
    @State private var notes: String
    @State private var status: ShiftStatus
    @State private var error: String?

    init(session: AppSession, snapshot: DomainSnapshot, shift: ScheduledShift) {
        self.session = session
        self.snapshot = snapshot
        self.shift = shift
        _employeeID = State(initialValue: shift.employeeID)
        _shiftDate = State(initialValue: shift.shiftDate.date(in: snapshot.business.timeZone))
        _startTime = State(initialValue: shift.startsAt)
        _endTime = State(initialValue: shift.endsAt)
        _title = State(initialValue: shift.title)
        _notes = State(initialValue: shift.notes ?? "")
        _status = State(initialValue: shift.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Employee", selection: $employeeID) {
                    ForEach(snapshot.profiles.filter { $0.status == .active }) { Text($0.name).tag($0.id) }
                }
                DatePicker("Date", selection: $shiftDate, displayedComponents: .date)
                DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                TextField("Label", text: $title)
                TextField("Manager notes", text: $notes, axis: .vertical)
                Picker("Status", selection: $status) {
                    Text("Draft").tag(ShiftStatus.draft)
                    Text("Published").tag(ShiftStatus.published)
                    Text("Cancelled").tag(ShiftStatus.cancelled)
                }
                if shift.seriesID != nil {
                    Text("This changes only this occurrence in the repeating series.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle("Edit Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(session.isMutating) }
            }
        }
    }

    private func save() {
        guard endTime > startTime else { error = "End time must be after start time."; return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.business.timeZone
        let update = ScheduledShiftUpdate(
            shiftID: shift.id,
            employeeID: employeeID,
            shiftDate: DateOnly(date: shiftDate, calendar: calendar),
            startTime: clockString(startTime, timeZone: snapshot.business.timeZone),
            endTime: clockString(endTime, timeZone: snapshot.business.timeZone),
            title: title,
            notes: notes.nilIfBlank,
            status: status,
            breaks: shift.breaks.map { .init(type: $0.type, durationMinutes: $0.durationMinutes, startOffsetMinutes: nil) }
        )
        Task {
            do { try await session.updateShift(update); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private func clockString(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
