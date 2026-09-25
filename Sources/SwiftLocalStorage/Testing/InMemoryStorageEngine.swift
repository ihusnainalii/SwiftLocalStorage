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
    private var indexes: [String: IndexValues] = [:]

    @_spi(SwiftLocalStorageTesting) public init() {}

    /// Stores raw bytes under an entity key for `typeName` / `id`, bypassing encoding.
    @_spi(SwiftLocalStorageTesting) public func insertRaw(
        _ payload: Data, typeName: String, id: String, version: Int = 1, at now: Date = Date()
    ) {
        let key = StorageKey.entity(typeName: typeName, id: id)
        store(
            RecordWrite(key: key, kind: .entity, typeName: typeName, payload: payload, schemaVersion: version), now: now
        )
    }

    func upsert(_ writes: [RecordWrite], now: Date) async throws -> Set<String> {
        var inserted = Set<String>()
        for write in writes {
            if rows[write.key] == nil { inserted.insert(write.key) }
            store(write, now: now)
        }
        return inserted
    }

    func rewrite(key: String, payload: Data, schemaVersion: Int, index: IndexValues?) async throws {
        guard rows[key] != nil else { return }
        rows[key]?.payload = payload
        rows[key]?.schemaVersion = schemaVersion
        if let index { indexes[key] = index }
    }

    func staleIndexKeys(typeName: String, signature: String) async throws -> [String] {
        rows.values
            .filter { $0.kind == .entity && $0.typeName == typeName && indexes[$0.key]?.signature != signature }
            .map(\.key)
    }

    func setIndex(key: String, values: IndexValues) async throws {
        guard rows[key] != nil else { return }
        indexes[key] = values
    }

    func record(forKey key: String) async throws -> RecordSnapshot? {
        rows[key]
    }

    func records(
        kind: RecordKind, typeName: String, now: Date,
        sort: StorageSort, limit: Int?, offset: Int, index: IndexQuery?
    ) async throws -> [RecordSnapshot] {
        let matching = rows.values.filter { $0.kind == kind && $0.typeName == typeName }
        matching.filter { $0.isExpired(at: now) }.forEach { remove($0.key) }
        let live = matching.filter { !$0.isExpired(at: now) && (index?.matches(indexes[$0.key]) ?? true) }
        let sorted = live.sorted { lhs, rhs in
            let (l, r) = (order[lhs.key] ?? 0, order[rhs.key] ?? 0)
            if let indexOrder = index?.order {
                return indexPrecedes(indexes[lhs.key], l, indexes[rhs.key], r, by: indexOrder)
            }
            return switch sort {
            case .oldestFirst: (lhs.createdAt, l) < (rhs.createdAt, r)
            case .newestFirst: (lhs.createdAt, l) > (rhs.createdAt, r)
            case .recentlyUpdated: (lhs.updatedAt, l) > (rhs.updatedAt, r)
            case .leastRecentlyUpdated: (lhs.updatedAt, l) < (rhs.updatedAt, r)
            }
        }
        let sliced = sorted.dropFirst(offset)
        return Array(limit.map { sliced.prefix($0) } ?? sliced)
    }

    func count(kind: RecordKind, typeName: String, now: Date, index: IndexQuery?) async throws -> Int {
        rows.values.count {
            $0.kind == kind && $0.typeName == typeName && !$0.isExpired(at: now)
                && (index?.matches(indexes[$0.key]) ?? true)
        }
    }

    /// SQLite order: a missing value sorts before any value; ties keep insertion order.
    private func indexPrecedes(
        _ lhs: IndexValues?, _ lhsOrder: Int, _ rhs: IndexValues?, _ rhsOrder: Int, by order: IndexQuery.Order
    ) -> Bool {
        func compare<V: Comparable>(_ a: V?, _ b: V?) -> Bool? {
            switch (a, b) {
            case (nil, nil): nil
            case (nil, _): order.ascending
            case (_, nil): !order.ascending
            case (let a?, let b?): a == b ? nil : (a < b) == order.ascending
            }
        }
        let decided =
            order.isString
            ? compare(lhs?.strings[order.slot], rhs?.strings[order.slot])
            : compare(lhs?.numbers[order.slot], rhs?.numbers[order.slot])
        return decided ?? (lhsOrder < rhsOrder)
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
        indexes.removeAll()
    }

    private func store(_ write: RecordWrite, now: Date) {
        let createdAt = rows[write.key]?.createdAt ?? now
        if order[write.key] == nil {
            sequence += 1
            order[write.key] = sequence
        }
        rows[write.key] = RecordSnapshot(
            key: write.key, kind: write.kind, typeName: write.typeName, payload: write.payload,
            schemaVersion: write.schemaVersion, createdAt: createdAt, updatedAt: now, expiresAt: write.expiresAt
        )
        indexes[write.key] = write.index
    }

    private func remove(_ key: String) {
        rows[key] = nil
        order[key] = nil
        indexes[key] = nil
    }
}
