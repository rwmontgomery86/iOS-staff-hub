import SwiftUI

struct ScheduleView: View {
    @Bindable var session: AppSession
    @State private var createPresented = false
    @State private var editingShift: ScheduledShift?
    @State private var detailShift: ScheduledShift?
    @State private var weekStart: DateOnly?
    @State private var selectedDate: DateOnly?
    @State private var isWideLayout = false
    @AppStorage("schedule-rotation-hint-dismissed") private var rotationHintDismissed = false

    private var snapshot: DomainSnapshot? { session.snapshot }
    private var visibleShifts: [ScheduledShift] {
        guard let snapshot, let profile = session.identity?.profile else { return [] }
        return SchedulePresentation.visibleShifts(from: snapshot.shifts, for: profile)
    }

    var body: some View {
        Group {
            if let snapshot {
                GeometryReader { geometry in
                    let wide = geometry.size.width >= 700
                    VStack(spacing: 0) {
                        if !wide, !rotationHintDismissed {
                            rotationHint
                        }
                        if wide {
                            weeklyView(snapshot: snapshot)
                        } else if session.canManage {
                            managerDailyView(snapshot: snapshot)
                        } else {
                            employeeAgenda(snapshot: snapshot)
                        }
                    }
                    .onAppear { isWideLayout = wide }
                    .onChange(of: geometry.size.width) { _, width in isWideLayout = width >= 700 }
                }
                .onAppear { openOnToday(snapshot: snapshot) }
                .onChange(of: snapshot.business.id) { _, _ in openOnToday(snapshot: snapshot) }
                .sheet(isPresented: $createPresented) {
                    ScheduleForm(session: session, snapshot: snapshot)
                }
                .sheet(item: $editingShift) { shift in
                    ShiftEditForm(session: session, snapshot: snapshot, shift: shift)
                }
                .sheet(item: $detailShift) { shift in
                    ShiftDetailView(
                        shift: shift,
                        employee: snapshot.profiles.first(where: { $0.id == shift.employeeID }),
                        timeZone: snapshot.business.timeZone,
                        locked: isLocked(shift, snapshot: snapshot)
                    )
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Schedule")
        .toolbar(isWideLayout ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if session.canManage && !isWideLayout {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Shift", systemImage: "plus") { createPresented = true }
                        .disabled(!session.canMutate)
                }
            }
        }
    }

    private var rotationHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.landscape.rotate")
            Text("Rotate for weekly view")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Dismiss", systemImage: "xmark") { rotationHintDismissed = true }
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .foregroundStyle(Color(hex: 0x273F38))
        .background(Color(hex: 0xE9EFEB))
        .accessibilityElement(children: .contain)
    }

    private func weeklyView(snapshot: DomainSnapshot) -> some View {
        let timeZone = snapshot.business.timeZone
        let start = weekStart ?? SchedulePresentation.weekStart(containing: .today(in: timeZone), timeZone: timeZone)
        let days = SchedulePresentation.weekDays(starting: start, timeZone: timeZone)
        let today = DateOnly.today(in: timeZone)
        return ScrollView {
            VStack(spacing: 18) {
                wideScheduleHeader(start: start, end: days.last ?? start, timeZone: timeZone)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 7), spacing: 0) {
                    ForEach(days, id: \.self) { date in
                        WeekdayColumn(
                            date: date,
                            shifts: shifts(on: date),
                            profiles: snapshot.profiles,
                            timeZone: timeZone,
                            isToday: date == today,
                            manager: session.canManage,
                            isLocked: { isLocked($0, snapshot: snapshot) },
                            onTap: { open($0, snapshot: snapshot) }
                        )
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await session.refresh() }
    }

    private func managerDailyView(snapshot: DomainSnapshot) -> some View {
        let timeZone = snapshot.business.timeZone
        let active = selectedDate ?? .today(in: timeZone)
        let start = weekStart ?? SchedulePresentation.weekStart(containing: active, timeZone: timeZone)
        let days = SchedulePresentation.weekDays(starting: start, timeZone: timeZone)
        let dayShifts = shifts(on: active)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                scheduleHeader(start: start, end: days.last ?? start, timeZone: timeZone)
                DateStrip(days: days, selectedDate: active, today: .today(in: timeZone), timeZone: timeZone) { selectedDate = $0 }
                HStack {
                    Text(AppDateFormatter.fullDate(active, timeZone: timeZone))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(dayShifts.isEmpty ? "Open day" : "\(dayShifts.count) scheduled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if dayShifts.isEmpty {
                    ContentUnavailableView(
                        "Open day",
                        systemImage: "sun.max",
                        description: Text("No team shifts are scheduled.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(dayShifts) { shift in
                        shiftButton(shift, snapshot: snapshot)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground).opacity(0.45))
        .refreshable { await session.refresh() }
    }

    private func employeeAgenda(snapshot: DomainSnapshot) -> some View {
        let timeZone = snapshot.business.timeZone
        let today = DateOnly.today(in: timeZone)
        let upcoming = visibleShifts.filter { $0.shiftDate >= today }.sorted { ($0.shiftDate, $0.startsAt) < ($1.shiftDate, $1.startsAt) }
        let groups = Dictionary(grouping: upcoming, by: \.shiftDate).sorted { $0.key < $1.key }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your upcoming shifts")
                        .font(.title2.weight(.semibold))
                    Text("A calm look at what’s ahead.")
                        .foregroundStyle(.secondary)
                }
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No upcoming shifts",
                        systemImage: "calendar.badge.clock",
                        description: Text("Published shifts will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(groups, id: \.key) { date, shifts in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppDateFormatter.fullDate(date, timeZone: timeZone))
                                .font(.headline)
                            ForEach(shifts) { shift in shiftButton(shift, snapshot: snapshot) }
                        }
                        .padding()
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .padding()
        }
        .background(Color(.secondarySystemBackground).opacity(0.45))
        .refreshable { await session.refresh() }
    }

    private func scheduleHeader(start: DateOnly, end: DateOnly, timeZone: TimeZone) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.canManage ? "Team week" : "Your week")
                    .font(.title2.weight(.semibold))
                Text("\(shortDate(start, timeZone: timeZone)) – \(shortDate(end, timeZone: timeZone))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Previous week", systemImage: "chevron.left") { moveWeek(by: -7, timeZone: timeZone) }.labelStyle(.iconOnly)
            Button("Today") { openOnToday(timeZone: timeZone) }.buttonStyle(.bordered)
            Button("Next week", systemImage: "chevron.right") { moveWeek(by: 7, timeZone: timeZone) }.labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
    }

    private func wideScheduleHeader(start: DateOnly, end: DateOnly, timeZone: TimeZone) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.canManage ? "Schedule" : "Your week")
                    .font(.title2.weight(.semibold))
                Text("\(shortDate(start, timeZone: timeZone)) – \(shortDate(end, timeZone: timeZone))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Previous week", systemImage: "chevron.left") { moveWeek(by: -7, timeZone: timeZone) }
                .labelStyle(.iconOnly)
            Button("Today") { openOnToday(timeZone: timeZone) }
            Button("Next week", systemImage: "chevron.right") { moveWeek(by: 7, timeZone: timeZone) }
                .labelStyle(.iconOnly)
            if session.canManage {
                Button("Add Shift", systemImage: "plus") { createPresented = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canMutate)
            }
        }
        .buttonStyle(.bordered)
    }

    private func shiftButton(_ shift: ScheduledShift, snapshot: DomainSnapshot) -> some View {
        Button { open(shift, snapshot: snapshot) } label: {
            ShiftRow(
                shift: shift,
                employee: snapshot.profiles.first(where: { $0.id == shift.employeeID }),
                timeZone: snapshot.business.timeZone,
                manager: session.canManage,
                locked: isLocked(shift, snapshot: snapshot)
            )
        }
        .buttonStyle(.plain)
    }

    private func shifts(on date: DateOnly) -> [ScheduledShift] {
        visibleShifts.filter { $0.shiftDate == date }.sorted { $0.startsAt < $1.startsAt }
    }

    private func open(_ shift: ScheduledShift, snapshot: DomainSnapshot) {
        if session.canManage && !isLocked(shift, snapshot: snapshot) { editingShift = shift }
        else { detailShift = shift }
    }

    private func openOnToday(snapshot: DomainSnapshot) { openOnToday(timeZone: snapshot.business.timeZone) }

    private func openOnToday(timeZone: TimeZone) {
        let today = DateOnly.today(in: timeZone)
        selectedDate = today
        weekStart = SchedulePresentation.weekStart(containing: today, timeZone: timeZone)
    }

    private func moveWeek(by days: Int, timeZone: TimeZone) {
        let current = weekStart ?? SchedulePresentation.weekStart(containing: .today(in: timeZone), timeZone: timeZone)
        let next = current.adding(days: days, in: timeZone)
        weekStart = next
        selectedDate = next
    }

    private func shortDate(_ date: DateOnly, timeZone: TimeZone) -> String {
        date.date(in: timeZone).formatted(.dateTime.month(.abbreviated).day())
    }

    private func isLocked(_ shift: ScheduledShift, snapshot: DomainSnapshot) -> Bool {
        shift.shiftDate < .today(in: snapshot.business.timeZone)
            || snapshot.timesheets.contains(where: { $0.scheduledShiftID == shift.id })
    }
}

private struct DateStrip: View {
    let days: [DateOnly]
    let selectedDate: DateOnly
    let today: DateOnly
    let timeZone: TimeZone
    let onSelect: (DateOnly) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { date in
                    Button { onSelect(date) } label: {
                        VStack(spacing: 4) {
                            Text(date.date(in: timeZone).formatted(.dateTime.weekday(.narrow))).font(.caption.weight(.semibold))
                            Text("\(date.day)").font(.headline)
                            Circle().frame(width: 4, height: 4).opacity(date == today ? 1 : 0)
                        }
                        .frame(width: 48, height: 64)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(date == selectedDate ? .white : .primary)
                    .background(date == selectedDate ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(AppDateFormatter.fullDate(date, timeZone: timeZone))
                    .accessibilityAddTraits(date == selectedDate ? .isSelected : [])
                }
            }
        }
    }
}

private struct WeekdayColumn: View {
    let date: DateOnly
    let shifts: [ScheduledShift]
    let profiles: [StaffProfile]
    let timeZone: TimeZone
    let isToday: Bool
    let manager: Bool
    let isLocked: (ScheduledShift) -> Bool
    let onTap: (ScheduledShift) -> Void

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 2) {
                Text(date.date(in: timeZone).formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold)).textCase(.uppercase)
                Text("\(date.day)").font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isToday ? Color.accentColor : .primary)
            Divider()
            VStack(spacing: 3) {
                ForEach(shifts) { shift in
                    Button { onTap(shift) } label: {
                        WeekShiftCard(
                            shift: shift,
                            employee: profiles.first(where: { $0.id == shift.employeeID }),
                            timeZone: timeZone,
                            manager: manager,
                            locked: isLocked(shift)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if shifts.isEmpty {
                    Text("Open")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .top)
            Spacer(minLength: 0)
            Text(shifts.isEmpty ? "No shifts" : "\(shifts.count) shift\(shifts.count == 1 ? "" : "s")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .top)
        .background(isToday ? Color.accentColor.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) { Divider() }
        .overlay { if isToday { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 1.5) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppDateFormatter.fullDate(date, timeZone: timeZone))
    }
}

private struct WeekShiftCard: View {
    let shift: ScheduledShift
    let employee: StaffProfile?
    let timeZone: TimeZone
    let manager: Bool
    let locked: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let employee {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hexString: employee.avatarColor))
                    .frame(width: 3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                if manager, let employee {
                    Text(employee.name.split(separator: " ").first.map(String.init) ?? employee.name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(AppDateFormatter.time(shift.startsAt, timeZone: timeZone))–\(AppDateFormatter.time(shift.endsAt, timeZone: timeZone))")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if shift.status == .draft || !shift.warningFlags.isEmpty || shift.isSeriesOverride {
                    HStack(spacing: 2) {
                        Image(systemName: shift.warningFlags.isEmpty ? "pencil.circle" : "exclamationmark.triangle")
                        Text(shift.status == .draft ? "Draft" : (shift.isSeriesOverride ? "Modified" : "Check"))
                    }
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(shift.warningFlags.isEmpty ? Color.secondary : Color.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
        .overlay(alignment: .topTrailing) {
            if locked { Image(systemName: "lock.fill").font(.system(size: 7)).foregroundStyle(.tertiary).padding(5) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ShiftDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let shift: ScheduledShift
    let employee: StaffProfile?
    let timeZone: TimeZone
    let locked: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Shift") {
                    if let employee { LabeledContent("Team member", value: employee.name) }
                    LabeledContent("Date", value: AppDateFormatter.fullDate(shift.shiftDate, timeZone: timeZone))
                    LabeledContent("Hours", value: "\(AppDateFormatter.time(shift.startsAt, timeZone: timeZone))–\(AppDateFormatter.time(shift.endsAt, timeZone: timeZone))")
                    LabeledContent("Status", value: shift.status.rawValue.capitalized)
                }
                if !shift.breaks.isEmpty {
                    Section("Breaks") {
                        ForEach(shift.breaks) { item in LabeledContent(item.type.label, value: "\(item.durationMinutes) min") }
                    }
                }
                if let notes = shift.notes, !notes.isEmpty { Section("Notes") { Text(notes) } }
                if locked { Section { Label("This shift is locked by date or timesheet activity.", systemImage: "lock.fill") } }
            }
            .navigationTitle(shift.title.isEmpty ? "Shift details" : shift.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
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
