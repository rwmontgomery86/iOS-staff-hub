import SwiftUI

struct InboxView: View {
    @Bindable var session: AppSession

    var body: some View {
        Group {
            if let snapshot = session.snapshot {
                List {
                    if snapshot.notifications.isEmpty {
                        ContentUnavailableView(
                            "Inbox is clear",
                            systemImage: "tray",
                            description: Text("PTO and schedule updates will appear here.")
                        )
                    } else {
                        ForEach(snapshot.notifications) { notification in
                            Button {
                                if let id = notification.requestID { session.route(.request(id)) }
                                else if notification.kind == .schedule { session.route(.schedule) }
                            } label: {
                                NotificationRow(notification: notification)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { await session.refresh() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Mark All Read") {
                    Task { try? await session.markAllNotificationsRead() }
                }
                .disabled(session.isOffline || session.snapshot?.notifications.contains(where: \.isUnread) != true)
            }
        }
    }
}
private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(notification.title).font(.headline)
                Text(notification.body).font(.subheadline).foregroundStyle(.secondary)
                Text(notification.createdAt, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if notification.isUnread {
                Circle().fill(.tint).frame(width: 9, height: 9).accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch notification.kind {
        case .request: "airplane"
        case .schedule: "calendar"
        case .timeclock: "clock"
        case .balance: "hourglass"
        case .blackout: "exclamationmark.shield"
        case .system: "bell"
        }
    }
}
