import SwiftUI

@main
struct PTOHubApp: App {
    @UIApplicationDelegateAdaptor(PTOHubAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    @State private var session: AppSession?
    @State private var configurationError: String?

    var body: some View {
        Group {
            if let session {
                SessionRootView(session: session)
                    .task { await session.bootstrap() }
                    .onReceive(NotificationCenter.default.publisher(for: .pushRouteReceived)) { note in
                        if let route = note.object as? AppRoute { session.route(route) }
                    }
            } else if let configurationError {
                ContentUnavailableView(
                    "Configuration Required",
                    systemImage: "wrench.and.screwdriver",
                    description: Text(configurationError)
                )
                .padding()
            } else {
                ProgressView("Starting Staff Hub…")
            }
        }
        .task {
            guard session == nil, configurationError == nil else { return }
            do {
                session = try AppEnvironment.makeSession()
            } catch {
                configurationError = error.localizedDescription
            }
        }
    }
}
