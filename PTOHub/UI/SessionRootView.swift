import SwiftUI

struct SessionRootView: View {
    @Bindable var session: AppSession
    @State private var accountPresented = false

    var body: some View {
        Group {
            switch session.phase {
            case .restoring:
                ProgressView("Restoring your session…")
            case .loading where session.identity == nil:
                ProgressView("Loading Staff Hub…")
            case .signedOut:
                LoginView(session: session)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Staff Hub is unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await session.refresh() } }
                    Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                }
            case .loading, .ready:
                authenticatedContent
            }
        }
        .tint(BusinessTheme.theme(for: session.selectedBusiness?.themeKey).accent)
        .alert("Staff Hub", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.clearError() } }
        )) {
            Button("OK", role: .cancel) { session.clearError() }
        } message: {
            Text(session.lastError ?? "")
        }
        .sheet(isPresented: $accountPresented) {
            AccountView(session: session)
        }
    }

    private var authenticatedContent: some View {
        VStack(spacing: 0) {
            if session.isOffline { OfflineBanner(savedAt: session.snapshot?.savedAt) }
            TabView(selection: $session.selectedTab) {
                NavigationStack {
                    HomeView(session: session)
                        .toolbar { accountToolbar }
                }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppRoute.home)

                NavigationStack {
                    ScheduleView(session: session)
                        .toolbar { accountToolbar }
                }
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppRoute.schedule)

                NavigationStack {
                    TimeOffView(session: session)
                        .toolbar { accountToolbar }
                }
                .tabItem { Label(session.canManage ? "Requests" : "Time Off", systemImage: "airplane") }
                .tag(AppRoute.timeOff)

                NavigationStack {
                    InboxView(session: session)
                        .toolbar { accountToolbar }
                }
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(session.snapshot?.notifications.filter(\.isUnread).count ?? 0)
                .tag(AppRoute.inbox)
            }
        }
    }

    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { accountPresented = true } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Account")
        }
    }
}

private struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: AppSession

    var body: some View {
        NavigationStack {
            List {
                if let identity = session.identity {
                    Section {
                        LabeledContent("Name", value: identity.profile.name)
                        LabeledContent("Role", value: identity.profile.role.label)
                        LabeledContent("Email", value: identity.profile.email)
                        if session.isDemo {
                            Label("Simulator demo · local data only", systemImage: "testtube.2")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Account")
                    }
                }
                if session.canSwitchBusinesses, let identity = session.identity {
                    Section("Business") {
                        ForEach(identity.businesses) { business in
                            Button {
                                Task {
                                    await session.selectBusiness(business)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(business.name)
                                    Spacer()
                                    if business.id == session.selectedBusinessID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Notifications") {
                    Button("Enable Notifications", systemImage: "bell.badge") {
                        Task { await session.requestPushPermission() }
                    }
                    .disabled(session.isOffline || session.isDemo)
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await session.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
