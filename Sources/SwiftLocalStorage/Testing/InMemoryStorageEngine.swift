import Foundation

/// A dictionary-backed ``StorageEngine`` for tests: no SwiftData, no disk.
///
/// Use it with `LocalStorage(configuration:engine:now:)` to test code that depends on
/// ``LocalStorage`` without a `ModelContainer`, or to inject records directly (e.g. a corrupt
/// payload) via ``insertRaw(_:)``.
@_spi(SwiftLocalStorageTesting) public actor InMemoryStorageEngine: StorageEngine {

    private var rows: [String: RecordSnapshot] = [:]
    /// Monotonic tiebreaker so records written in the same instant keep insertion order.
    private var order: [String: Int] = [:]
    private var sequence = 0

    @_spi(SwiftLocalStorageTesting) public init() {}

    /// Stores raw bytes under an entity key for `typeName` / `id`, bypassing encoding.
    @_spi(SwiftLocalStorageTesting) public func insertRaw(
        _ payload: Data, typeName: String, id: String, at now: Date = Date()
    ) {
        let key = StorageKey.entity(typeName: typeName, id: id)
        store(RecordWrite(key: key, kind: .entity, typeName: typeName, payload: payload), now: now)
    }

    func upsert(_ writes: [RecordWrite], now: Date) async throws {
        writes.forEach { store($0, now: now) }
    }

    func record(forKey key: String) async throws -> RecordSnapshot? {
        rows[key]
    }

    func records(kind: RecordKind, typeName: String, now: Date) async throws -> [RecordSnapshot] {
        let matching = rows.values.filter { $0.kind == kind && $0.typeName == typeName }
        matching.filter { $0.isExpired(at: now) }.forEach { remove($0.key) }
        return matching
            .filter { !$0.isExpired(at: now) }
            .sorted { ($0.createdAt, order[$0.key] ?? 0) < ($1.createdAt, order[$1.key] ?? 0) }
    }

    func count(kind: RecordKind, typeName: String, now: Date) async throws -> Int {
        rows.values.count { $0.kind == kind && $0.typeName == typeName && !$0.isExpired(at: now) }
    }

    func delete(keys: [String]) async throws {
        keys.forEach(remove)
    }

    func deleteAll(kind: RecordKind, typeName: String) async throws {
        rows.values.filter { $0.kind == kind && $0.typeName == typeName }.forEach { remove($0.key) }
    }

    func deleteExpired(now: Date) async throws -> Int {
        let expired = rows.values.filter { $0.isExpired(at: now) }
        expired.forEach { remove($0.key) }
        return expired.count
    }

    func deleteAll() async throws {
        rows.removeAll()
        order.removeAll()
    }

    private func store(_ write: RecordWrite, now: Date) {
        let createdAt = rows[write.key]?.createdAt ?? now
        if order[write.key] == nil {
            sequence += 1
            order[write.key] = sequence
        }
        rows[write.key] = RecordSnapshot(
            key: write.key, kind: write.kind, typeName: write.typeName, payload: write.payload,
            schemaVersion: 1, createdAt: createdAt, updatedAt: now, expiresAt: write.expiresAt
        )
    }

    private func remove(_ key: String) {
        rows[key] = nil
        order[key] = nil
    }
}
