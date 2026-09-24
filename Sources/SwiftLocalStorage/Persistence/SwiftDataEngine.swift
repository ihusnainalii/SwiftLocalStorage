import Foundation
import SwiftData

/// The SwiftData-backed ``StorageEngine``. All `ModelContext` access is isolated to this actor;
/// only ``RecordSnapshot`` values leave it.
@ModelActor
actor SwiftDataEngine: StorageEngine {

    /// Opens (or creates) the container described by `configuration`.
    static func make(configuration: LocalStorageConfiguration) throws -> SwiftDataEngine {
        let schema = Schema(versionedSchema: StorageSchemaV1.self)
        let modelConfiguration = ModelConfiguration(
            configuration.name,
            schema: schema,
            isStoredInMemoryOnly: configuration.isStoredInMemoryOnly
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: StorageMigrationPlan.self,
            configurations: [modelConfiguration]
        )
        return SwiftDataEngine(modelContainer: container)
    }

    func upsert(_ writes: [RecordWrite], now: Date) async throws {
        do {
            for write in writes {
                if let existing = try model(forKey: write.key) {
                    existing.kind = write.kind.rawValue
                    existing.typeName = write.typeName
                    existing.payload = write.payload
                    existing.updatedAt = now
                    existing.expiresAt = write.expiresAt
                } else {
                    modelContext.insert(StoredRecord(
                        key: write.key, kind: write.kind.rawValue, typeName: write.typeName,
                        payload: write.payload, schemaVersion: 1,
                        createdAt: now, updatedAt: now, expiresAt: write.expiresAt
                    ))
                }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func record(forKey key: String) async throws -> RecordSnapshot? {
        try model(forKey: key).map(Self.snapshot)
    }

    func records(kind: RecordKind, typeName: String, now: Date) async throws -> [RecordSnapshot] {
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.kind == kindRaw && $0.typeName == typeName },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.includePendingChanges = true
        let models = try modelContext.fetch(descriptor)

        // Lazy purge: expired rows of this type are removed as a side effect of reading them.
        let expired = models.filter { Self.isExpired($0, at: now) }
        if !expired.isEmpty {
            expired.forEach(modelContext.delete)
            try modelContext.save()
        }
        return models.filter { !Self.isExpired($0, at: now) }.map(Self.snapshot)
    }

    func count(kind: RecordKind, typeName: String, now: Date) async throws -> Int {
        let kindRaw = kind.rawValue
        let distantFuture = Date.distantFuture
        return try modelContext.fetchCount(FetchDescriptor<StoredRecord>(
            predicate: #Predicate {
                $0.kind == kindRaw && $0.typeName == typeName && ($0.expiresAt ?? distantFuture) > now
            }
        ))
    }

    func delete(keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        try modelContext.delete(model: StoredRecord.self, where: #Predicate { keys.contains($0.key) })
        try modelContext.save()
    }

    func deleteAll(kind: RecordKind, typeName: String) async throws {
        let kindRaw = kind.rawValue
        try modelContext.delete(
            model: StoredRecord.self,
            where: #Predicate { $0.kind == kindRaw && $0.typeName == typeName }
        )
        try modelContext.save()
    }

    func deleteExpired(now: Date) async throws -> Int {
        let distantFuture = Date.distantFuture
        let predicate = #Predicate<StoredRecord> { ($0.expiresAt ?? distantFuture) <= now }
        let count = try modelContext.fetchCount(FetchDescriptor(predicate: predicate))
        guard count > 0 else { return 0 }
        try modelContext.delete(model: StoredRecord.self, where: predicate)
        try modelContext.save()
        return count
    }

    func deleteAll() async throws {
        try modelContext.delete(model: StoredRecord.self)
        try modelContext.save()
    }

    // MARK: - Helpers

    private func model(forKey key: String) throws -> StoredRecord? {
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func isExpired(_ model: StoredRecord, at now: Date) -> Bool {
        model.expiresAt.map { $0 <= now } ?? false
    }

    private static func snapshot(_ model: StoredRecord) -> RecordSnapshot {
        RecordSnapshot(
            key: model.key,
            kind: RecordKind(rawValue: model.kind) ?? .entity,
            typeName: model.typeName,
            payload: model.payload,
            schemaVersion: model.schemaVersion,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            expiresAt: model.expiresAt
        )
    }
}
