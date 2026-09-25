import Foundation

/// What a record is: a DTO addressed by type + ID, or a value addressed by a free-form key.
enum RecordKind: String, Sendable {
    case entity
    case keyValue = "kv"
}

/// A record to insert or replace. The engine owns `createdAt` / `updatedAt`.
struct RecordWrite: Sendable, Equatable {
    var key: String
    var kind: RecordKind
    var typeName: String
    var payload: Data
    var expiresAt: Date?
    /// The DTO version of `payload` (see ``LocalStorageVersioned``).
    var schemaVersion = 1
    /// Index slot values when the type is ``LocalStorageIndexed``; `nil` clears them.
    var index: IndexValues?
}

/// An immutable copy of a stored record — never a live `@Model` object, so it can leave the actor.
struct RecordSnapshot: Sendable, Equatable {
    var key: String
    var kind: RecordKind
    var typeName: String
    var payload: Data
    var schemaVersion: Int
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?

    func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

/// The record-level persistence port behind ``LocalStorage``. It deals in keys and bytes only;
/// encoding, key building and expiry policy live in ``LocalStorage``.
///
/// Default: ``SwiftDataEngine``. Tests: `InMemoryStorageEngine`.
///
/// Every method that takes `now` treats rows with `expiresAt <= now` as absent.
protocol StorageEngine: Sendable {
    /// Inserts or replaces every write atomically: either all land or none do.
    /// - Returns: the keys that did not exist before (the rest were updates).
    @discardableResult
    func upsert(_ writes: [RecordWrite], now: Date) async throws -> Set<String>

    /// Replaces only the payload and its version (a migration write-back) and, when `index` is
    /// given, the index slots: timestamps, expiry and sequence are untouched. A missing key is a no-op.
    func rewrite(key: String, payload: Data, schemaVersion: Int, index: IndexValues?) async throws

    /// Keys of entity records of `typeName` whose index signature isn't `signature` (including
    /// records never indexed), expired or not.
    func staleIndexKeys(typeName: String, signature: String) async throws -> [String]

    /// Replaces only the index slots of `key`. A missing key is a no-op.
    func setIndex(key: String, values: IndexValues) async throws

    /// The record for `key`, expired or not.
    func record(forKey key: String) async throws -> RecordSnapshot?

    /// Live records of one kind + type matching `index` (if any), in `index.order` when given or
    /// else `sort` order (ties broken by insertion order), skipping `offset` and returning at most
    /// `limit`. Expired rows of the type are purged as a side effect.
    func records(
        kind: RecordKind, typeName: String, now: Date,
        sort: StorageSort, limit: Int?, offset: Int, index: IndexQuery?
    ) async throws -> [RecordSnapshot]

    /// Number of live records of one kind + type matching `index` (if any).
    func count(kind: RecordKind, typeName: String, now: Date, index: IndexQuery?) async throws -> Int

    /// Deletes the given keys; missing keys are ignored.
    func delete(keys: [String]) async throws

    /// Deletes every record of one kind + type, expired or not.
    func deleteAll(kind: RecordKind, typeName: String) async throws

    /// Deletes every record with `expiresAt <= now`; returns how many.
    func deleteExpired(now: Date) async throws -> Int

    /// Deletes everything.
    func deleteAll() async throws
}
