import Foundation
import SwiftData
import Testing
@testable import SwiftLocalStorage

/// Opens real store files written by older releases with the current schema.
///
/// The fixtures were generated once by the old schema versions and are copied into place here,
/// so no old model class is instantiated in this process: SwiftData can't host containers of
/// several schema versions with one entity name side by side, and the app never does.
@Suite("Schema migration", .serialized)
struct MigrationTests {

    /// `User` under its default storage name, re-declared with an index to exercise re-indexing.
    struct IndexedUser: Codable, Identifiable, Sendable, Equatable, LocalStorageNaming, LocalStorageIndexed {
        static var storageTypeName: String { StorageKey.typeName(of: User.self) }
        static var storageIndexes: [StorageIndex<IndexedUser>] { [.string("name") { $0.name }] }
        let id: UUID
        var name: String
        var email: String
    }

    /// Copies `fixture` to the default location of a store named `name` and opens it.
    private func openFixture(_ fixture: String, as name: String) throws -> (LocalStorage, URL) {
        let destination = ModelConfiguration(name).url
        removeStore(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let source = try #require(
            Bundle.module.url(forResource: fixture, withExtension: "store", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: source, to: destination)
        return (try LocalStorage(configuration: .init(name: name)), destination)
    }

    private func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    @Test("a v0.1–v0.2.2 store (schema V1) opens, keeps its records and orders new ones after them")
    func fromV1() async throws {
        let (storage, url) = try openFixture("schema-v1", as: "SwiftLocalStorageTests-FromV1")
        defer { removeStore(at: url) }
        let legacyID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let legacy = try #require(try await storage.fetch(User.self, id: legacyID))
        #expect(legacy.name == "LegacyV1")

        let batch = (0..<5).map { User.make("New\($0)") }
        try await storage.save(batch)
        #expect(try await storage.fetch(User.self).map(\.id) == [legacyID] + batch.map(\.id))
    }

    @Test("a v0.2.3–v0.5 store (schema V2) opens with its insertion order and gets indexed on first query")
    func fromV2() async throws {
        let (storage, url) = try openFixture("schema-v2", as: "SwiftLocalStorageTests-FromV2")
        defer { removeStore(at: url) }

        // Same createdAt; the stored sequence keeps A before B.
        #expect(try await storage.fetch(User.self).map(\.name) == ["LegacyA", "LegacyB"])

        // Records written before indexes existed are re-indexed, then filtered in the store.
        let matches = try await storage.fetch(IndexedUser.self, matching: [.equals("name", "LegacyB")])
        #expect(matches.map(\.name) == ["LegacyB"])
        #expect(try await storage.count(IndexedUser.self, matching: [.equals("name", "LegacyA")]) == 1)
    }
}
