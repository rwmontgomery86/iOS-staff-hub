import Foundation

@MainActor
enum AppEnvironment {
    static func makeSession() throws -> AppSession {
        let configuration = try AppConfiguration.load()
        let backend = SupabaseGateway(client: configuration.makeClient())
        return AppSession(
            configuration: configuration,
            backend: backend,
            cache: SnapshotCache(),
            network: NetworkMonitor(),
            push: PushRegistrationManager()
        )
    }
}
