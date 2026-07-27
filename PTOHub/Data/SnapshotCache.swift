import Foundation

protocol SnapshotCaching: Sendable {
    func load(userID: UUID, businessID: UUID) async throws -> DomainSnapshot?
    func save(_ snapshot: DomainSnapshot, userID: UUID, businessID: UUID) async throws
    func removeAll(userID: UUID) async throws
}
actor SnapshotCache: SnapshotCaching {
    private let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.rootURL = base.appending(path: "PTOHub/Snapshots", directoryHint: .isDirectory)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(userID: UUID, businessID: UUID) async throws -> DomainSnapshot? {
        let url = fileURL(userID: userID, businessID: businessID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(DomainSnapshot.self, from: Data(contentsOf: url))
    }

    func save(_ snapshot: DomainSnapshot, userID: UUID, businessID: UUID) async throws {
        let directory = rootURL.appending(path: userID.uuidString.lowercased(), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        let url = fileURL(userID: userID, businessID: businessID)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func removeAll(userID: UUID) async throws {
        let directory = rootURL.appending(path: userID.uuidString.lowercased(), directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func fileURL(userID: UUID, businessID: UUID) -> URL {
        rootURL
            .appending(path: userID.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "\(businessID.uuidString.lowercased()).json")
    }
}
