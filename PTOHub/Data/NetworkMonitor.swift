import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.staffhub.ptohub.network")
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.setOnline(online) }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    func updates() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(isOnline)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    private func setOnline(_ online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        for continuation in continuations.values { continuation.yield(online) }
    }
}
