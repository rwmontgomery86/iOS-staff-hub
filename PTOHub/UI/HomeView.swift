import SwiftUI

struct HomeView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            if let snapshot = session.snapshot, let profile = session.identity?.profile {
                if profile.role.isManager {
                    ManagerTodayView(session: session, snapshot: snapshot)
                } else {
                    EmployeeHomeView(session: session, snapshot: snapshot, profile: profile)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(session.canManage ? "Today" : "Home")
        .refreshable { await session.refresh() }
    }
}

private struct EmployeeHomeView: View {
    @Bindable var session: AppSession
    let snapshot: DomainSnapshot
    let profile: StaffProfile
    @State private var requestPresented = false

    private var today: DateOnly { .today(in: snapshot.business.timeZone) }
    private var balance: Double { PTOCalculation.balance(entries: snapshot.ledger, employeeID: profile.id) }
    private var reserved: Double { PTOCalculation.reservedHours(requests: snapshot.requests, employeeID: profile.id, today: today) }
    private var nextShift: ScheduledShift? {
        snapshot.shifts.filter {
            $0.employeeID == profile.id && $0.status == .published && $0.endsAt > .now
        }.min { $0.startsAt < $1.startsAt }
    }
    private var nextPTO: PTORequest? {
        snapshot.requests.filter {
            $0.employeeID == profile.id && $0.status == .approved && ($0.firstDate ?? .init(year: 1970, month: 1, day: 1)) >= today
        }.min { ($0.firstDate ?? today) < ($1.firstDate ?? today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                welcome
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    MetricCard(title: "Available PTO", value: "\(balance.formatted(.number.precision(.fractionLength(1))))h", detail: "Current ledger balance", icon: "hourglass", tint: theme.accent)
                    MetricCard(title: "Reserved", value: "\(reserved.formatted(.number.precision(.fractionLength(1))))h", detail: "Pending and approved", icon: "lock", tint: theme.secondary)
                }
                Button {
                    requestPresented = true
                } label: {
                    Label("Request Time Off", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!session.canMutate)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Coming up").font(.title2.weight(.semibold))
                    if let nextShift {
                        HomeRow(
                            icon: "calendar.badge.clock",
                            title: "Next shift",
                            subtitle: "\(AppDateFormatter.fullDate(nextShift.shiftDate, timeZone: snapshot.business.timeZone)) · \(AppDateFormatter.time(nextShift.startsAt, timeZone: snapshot.business.timeZone))–\(AppDateFormatter.time(nextShift.endsAt, timeZone: snapshot.business.timeZone))"
                        )
                    } else {
                        HomeRow(icon: "calendar", title: "No upcoming shift", subtitle: "Published shifts will appear here.")
                    }
                    if let nextPTO, let date = nextPTO.firstDate {
                        HomeRow(icon: "airplane", title: "Approved time off", subtitle: "\(AppDateFormatter.fullDate(date, timeZone: snapshot.business.timeZone)) · \(nextPTO.hours) hours")
                    } else {
                        HomeRow(icon: "checkmark.circle", title: "No approved PTO ahead", subtitle: "You’re all caught up.")
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color(hex: 0xF8F6F0))
        .sheet(isPresented: $requestPresented) {
            PTORequestForm(session: session, snapshot: snapshot, profile: profile)
        }
    }

    private var welcome: some View {
        HStack(spacing: 14) {
            BrandLogo(business: snapshot.business).frame(width: 110, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back, \(profile.firstName)")
                    .font(.system(.title, design: .serif, weight: .semibold))
                Text(snapshot.business.name).foregroundStyle(.secondary)
            }
        }
    }

    private var theme: BusinessTheme { .theme(for: snapshot.business.themeKey) }
}

private struct HomeRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct ManagerTodayView: View {
    @Bindable var session: AppSession
    let snapshot: DomainSnapshot

    private var records: [AttendanceRecord] {
        AttendanceClassifier.records(
            profiles: snapshot.profiles,
            shifts: snapshot.shifts,
            timesheets: snapshot.timesheets,
            date: .today(in: snapshot.business.timeZone),
            timeZone: snapshot.business.timeZone
        )
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    BrandLogo(business: snapshot.business).frame(width: 105, height: 64)
                    VStack(alignment: .leading) {
                        Text(snapshot.business.name).font(.headline)
                        Text("Live attendance").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(AttendanceState.allCases, id: \.self) { state in
                let matching = records.filter { $0.state == state }
                if !matching.isEmpty {
                    Section("\(state.label) · \(matching.count)") {
                        ForEach(matching) { record in
                            AttendanceRow(record: record, timeZone: snapshot.business.timeZone)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct AttendanceRow: View {
    let record: AttendanceRecord
    let timeZone: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: record.profile)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.profile.name).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(statusColor).frame(width: 10, height: 10).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.profile.name), \(record.state.label), \(detail)")
    }

    private var detail: String {
        if record.state == .noClockRequired { return record.profile.jobTitle }
        if let sheet = record.timesheet, record.state == .clockedIn || record.state == .onBreak {
            return "Since \(AppDateFormatter.time(sheet.startedAt, timeZone: timeZone))"
        }
        if let shift = record.shift {
            return "\(AppDateFormatter.time(shift.startsAt, timeZone: timeZone))–\(AppDateFormatter.time(shift.endsAt, timeZone: timeZone))"
        }
        return record.profile.jobTitle
    }

    private var statusColor: Color {
        switch record.state {
        case .clockedIn: .green
        case .onBreak: .orange
        case .clockedOut: .blue
        case .notStarted: .yellow
        case .notScheduled, .noClockRequired: .gray
        }
    }
}
