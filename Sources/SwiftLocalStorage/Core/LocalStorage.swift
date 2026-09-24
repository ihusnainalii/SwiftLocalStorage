import Foundation

/// Persists `Codable` DTOs locally — no `@Model` types required.
///
/// ```swift
/// let storage = try LocalStorage()
/// try await storage.save(user)
/// let user = try await storage.fetch(User.self, id: userID)
/// ```
///
/// Two addressing schemes share one store without colliding:
/// - **Entities** (`Identifiable & Codable`) are addressed by type + ID.
/// - **Key-value** entries (any `Codable`) are addressed by a string key.
///
/// Every method is safe to call concurrently from any task. Errors are always
/// ``LocalStorageError``; a missing record is `nil`, not an error.
public final class LocalStorage: Sendable {

    let configuration: LocalStorageConfiguration
    let engine: any StorageEngine
    let now: @Sendable () -> Date

    /// Opens (or creates) the SwiftData store described by `configuration`.
    ///
    /// - Throws: ``LocalStorageError/containerInitializationFailed(underlying:)``.
    public convenience init(configuration: LocalStorageConfiguration = .init()) throws {
        try self.init(configuration: configuration, now: { Date() })
    }

    init(
        configuration: LocalStorageConfiguration,
        engine: any StorageEngine,
        now: @escaping @Sendable () -> Date
    ) {
        self.configuration = configuration
        self.engine = engine
        self.now = now
    }

    // MARK: - Entities

    /// Inserts `value`, or replaces the stored value with the same ID (keeping its `createdAt`).
    ///
    /// - Parameter expiration: after this, reads treat the value as absent.
    public func save<T: Identifiable & Codable & Sendable>(
        _ value: T, expiration: CacheExpiration = .never
    ) async throws {
        try await save([value], expiration: expiration)
    }

    /// Saves every value in one transaction: all are stored or none are.
    public func save<T: Identifiable & Codable & Sendable>(
        _ values: [T], expiration: CacheExpiration = .never
    ) async throws {
        let typeName = StorageKey.typeName(of: T.self)
        let timestamp = now()
        let expiresAt = expiration.expiresAt(from: timestamp)
        let writes = try values.map { value in
            RecordWrite(
                key: StorageKey.entity(typeName: typeName, id: String(describing: value.id)),
                kind: .entity, typeName: typeName, payload: try encode(value), expiresAt: expiresAt
            )
        }
        try await perform { try await engine.upsert(writes, now: timestamp) }
    }

    /// The stored value with `id`, or `nil` if there is none.
    public func fetch<T: Identifiable & Codable & Sendable>(_ type: T.Type, id: T.ID) async throws -> T? {
        try await value(type, key: StorageKey.entity(type, id: id))
    }

    /// Every stored value of `type`, oldest first.
    public func fetch<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws -> [T] {
        let typeName = StorageKey.typeName(of: type)
        let records = try await perform {
            try await engine.records(kind: .entity, typeName: typeName, now: now())
        }
        return try records.map { try decode(type, from: $0) }
    }

    /// How many values of `type` are stored.
    public func count<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws -> Int {
        let typeName = StorageKey.typeName(of: type)
        return try await perform {
            try await engine.count(kind: .entity, typeName: typeName, now: now())
        }
    }

    /// Whether a value of `type` with `id` is stored.
    public func exists<T: Identifiable & Codable & Sendable>(_ type: T.Type, id: T.ID) async throws -> Bool {
        try await liveRecord(forKey: StorageKey.entity(type, id: id)) != nil
    }

    /// Deletes the value with `id`. Deleting a missing ID is a no-op.
    public func delete<T: Identifiable & Codable & Sendable>(_ type: T.Type, id: T.ID) async throws {
        let key = StorageKey.entity(type, id: id)
        try await perform { try await engine.delete(keys: [key]) }
    }

    /// Deletes every given value by ID in one operation. Missing values are ignored.
    public func delete<T: Identifiable & Codable & Sendable>(_ values: [T]) async throws {
        let keys = values.map { StorageKey.entity(T.self, id: $0.id) }
        try await perform { try await engine.delete(keys: keys) }
    }

    /// Metadata for the value with `id`, including when it has expired; `nil` if there is none.
    public func metadata<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, id: T.ID
    ) async throws -> StorageMetadata? {
        let key = StorageKey.entity(type, id: id)
        guard let record = try await perform({ try await engine.record(forKey: key) }) else { return nil }
        return StorageMetadata(
            createdAt: record.createdAt, updatedAt: record.updatedAt, expiresAt: record.expiresAt,
            size: record.payload.count, isExpired: record.isExpired(at: now())
        )
    }

    /// Deletes every stored value of `type`.
    public func deleteAll<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws {
        let typeName = StorageKey.typeName(of: type)
        try await perform { try await engine.deleteAll(kind: .entity, typeName: typeName) }
    }

    // MARK: - Key-value

    /// Stores `value` under `key`, replacing any previous value.
    ///
    /// Not for secrets: use the Keychain for tokens and passwords.
    public func set<V: Codable & Sendable>(
        _ value: V, forKey key: String, expiration: CacheExpiration = .never
    ) async throws {
        let timestamp = now()
        let write = RecordWrite(
            key: StorageKey.keyValue(key), kind: .keyValue,
            typeName: StorageKey.typeName(of: V.self), payload: try encode(value),
            expiresAt: expiration.expiresAt(from: timestamp)
        )
        try await perform { try await engine.upsert([write], now: timestamp) }
    }

    /// The value stored under `key`, or `nil` if there is none.
    public func get<V: Codable & Sendable>(_ type: V.Type, forKey key: String) async throws -> V? {
        try await value(type, key: StorageKey.keyValue(key))
    }

    /// Removes the value stored under `key`. Removing a missing key is a no-op.
    public func remove(forKey key: String) async throws {
        let storageKey = StorageKey.keyValue(key)
        try await perform { try await engine.delete(keys: [storageKey]) }
    }

    // MARK: - Maintenance

    /// Deletes every expired record (entities and key-value entries); returns how many.
    ///
    /// Reads already skip and purge expired records, so this is only needed to reclaim space.
    @discardableResult
    public func removeExpired() async throws -> Int {
        try await perform { try await engine.deleteExpired(now: now()) }
    }

    /// Deletes everything in this store — entities and key-value entries alike.
    public func removeAll() async throws {
        try await perform { try await engine.deleteAll() }
    }

    // MARK: - Internals

    /// The record for `key` unless it has expired, in which case it is deleted and `nil` returned.
    func liveRecord(forKey key: String) async throws -> RecordSnapshot? {
        try await perform {
            guard let record = try await engine.record(forKey: key) else { return nil }
            guard !record.isExpired(at: now()) else {
                try await engine.delete(keys: [key])
                return nil
            }
            return record
        }
    }

    private func value<T: Decodable>(_ type: T.Type, key: String) async throws -> T? {
        guard let record = try await liveRecord(forKey: key) else { return nil }
        return try decode(type, from: record)
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try configuration.encoder.encode(value)
        } catch {
            throw LocalStorageError.encodingFailed(underlying: error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from record: RecordSnapshot) throws -> T {
        do {
            return try configuration.decoder.decode(type, from: record.payload)
        } catch {
            throw LocalStorageError.decodingFailed(key: record.key, underlying: error)
        }
    }

    /// Checks cancellation up front and maps every engine error to ``LocalStorageError``.
    func perform<R>(_ body: () async throws -> R) async throws -> R {
        guard !Task.isCancelled else { throw LocalStorageError.cancelled }
        do {
            return try await body()
        } catch let error as LocalStorageError {
            throw error
        } catch {
            throw LocalStorageError.persistenceFailed(underlying: error)
        }
    }
}
