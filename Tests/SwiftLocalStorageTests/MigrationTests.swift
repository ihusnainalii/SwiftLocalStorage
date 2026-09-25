import Foundation
import SwiftData
import Testing
@testable import SwiftLocalStorage

@Suite("Schema migration", .serialized)
struct MigrationTests {

    /// Deletes a SQLite store and its sidecar files.
    private func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    @Test("a V1 store opens under V2, keeps its records and orders new ones after them")
    func v1ToV2() async throws {
        let name = "SwiftLocalStorageTests-Migration"
        let v1Schema = Schema(versionedSchema: StorageSchemaV1.self)
        let v1Configuration = ModelConfiguration(name, schema: v1Schema)
        removeStore(at: v1Configuration.url)
        defer { removeStore(at: v1Configuration.url) }

        // Write a store exactly as v0.1–v0.2.2 did.
        let legacy = User.make("Legacy")
        do {
            let container = try ModelContainer(for: v1Schema, configurations: [v1Configuration])
            let context = ModelContext(container)
            let created = Date(timeIntervalSinceReferenceDate: 700_000_000)
            context.insert(StorageSchemaV1.StoredRecord(
                key: StorageKey.entity(User.self, id: legacy.id), kind: RecordKind.entity.rawValue,
                typeName: StorageKey.typeName(of: User.self), payload: try JSONEncoder().encode(legacy),
                schemaVersion: 1, createdAt: created, updatedAt: created, expiresAt: nil
            ))
            try context.save()
        }

        // Open it with the current code: the migration plan upgrades it in place.
        let storage = try LocalStorage(configuration: .init(name: name))
        #expect(try await storage.fetch(User.self, id: legacy.id) == legacy)

        let batch = (0..<5).map { User.make("New\($0)") }
        try await storage.save(batch)
        #expect(try await storage.fetch(User.self).map(\.id) == [legacy.id] + batch.map(\.id))
    }
}
