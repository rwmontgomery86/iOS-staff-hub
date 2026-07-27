import Foundation
import Observation
import UIKit
import UserNotifications

extension Notification.Name {
    static let pushTokenReceived = Notification.Name("PTOHub.pushTokenReceived")
    static let pushRouteReceived = Notification.Name("PTOHub.pushRouteReceived")
}

enum PushRouter {
    static func route(userInfo: [AnyHashable: Any]) -> AppRoute {
        let kind = userInfo["kind"] as? String
        let requestID = (userInfo["requestId"] as? String).flatMap(UUID.init(uuidString:))
        return requestID.map(AppRoute.request) ?? (kind == "schedule" ? .schedule : .inbox)
    }
}

@MainActor
@Observable
final class PushRegistrationManager: NSObject, UNUserNotificationCenterDelegate {
    private(set) var token: String?
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    let installationID: UUID

    override init() {
        let key = "pto-hub.installation-id"
        if let value = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: value) {
            installationID = id
        } else {
            let id = UUID()
            installationID = id
            UserDefaults.standard.set(id.uuidString, forKey: key)
        }
        super.init()
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(
            forName: .pushTokenReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.object as? String else { return }
            MainActor.assumeIsolated { self?.token = token }
        }
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                authorizationStatus = granted ? .authorized : .denied
            } catch {
                authorizationStatus = .denied
            }
        }
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = PushRouter.route(userInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            NotificationCenter.default.post(name: .pushRouteReceived, object: route)
        }
    }
}

final class PTOHubAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .pushTokenReceived, object: token)
    }
}
