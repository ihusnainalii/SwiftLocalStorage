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
    let hub = ChangeHub()

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
        var newKeys = try await perform("save \(typeName) ×\(writes.count) (\(writes.byteCount) bytes)", level: .info) {
            try await engine.upsert(writes, now: timestamp)
        }
        // A key inserted by this batch is `.inserted` the first time it appears, `.updated` after.
        let changes = zip(values, writes).map { value, write -> RawChange in
            newKeys.remove(write.key) != nil ? .inserted(value) : .updated(value)
        }
        hub.publish(changes, to: typeName)
    }

    /// The stored value with `id`, or `nil` if there is none.
    public func fetch<T: Identifiable & Codable & Sendable>(_ type: T.Type, id: T.ID) async throws -> T? {
        try await value(type, key: StorageKey.entity(type, id: id))
    }

    /// Every stored value of `type`, oldest first.
    public func fetch<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws -> [T] {
        try await fetch(type, options: .default)
    }

    /// Stored values of `type`, sorted and sliced by `options` inside the store, so only the
    /// requested values are loaded and decoded.
    public func fetch<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, options: FetchOptions
    ) async throws -> [T] {
        let typeName = StorageKey.typeName(of: type)
        let records = try await perform("fetch \(typeName) \(options.logDescription)", level: .debug) {
            try await engine.records(
                kind: .entity, typeName: typeName, now: now(),
                sort: options.sort, limit: options.limit, offset: options.offset
            )
        }
        return try records.map { try decode(type, from: $0) }
    }

    /// Stored values of `type` matching `isIncluded`, then sorted and sliced by `options`.
    ///
    /// DTO fields live inside encoded payloads, so the filter runs in memory: every live value of
    /// `type` is loaded and decoded first. Prefer ``fetch(_:options:)`` when you don't need a filter.
    public func fetch<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, where isIncluded: (T) throws -> Bool, options: FetchOptions = .default
    ) async throws -> [T] {
        // ponytail: decode-all + in-memory filter; add stored-field indexes if large types need it.
        let all = try await fetch(type, options: FetchOptions(sort: options.sort))
        let sliced = try all.filter(isIncluded).dropFirst(options.offset)
        return Array(options.limit.map { sliced.prefix($0) } ?? sliced)
    }

    /// Page `page` (1-based) of `pageSize` values of `type`, with the totals for paging UI.
    public func page<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, page: Int, pageSize: Int, sort: StorageSort = .oldestFirst
    ) async throws -> StoragePage<T> {
        precondition(page >= 1, "page is 1-based")
        precondition(pageSize >= 1, "pageSize must be at least 1")
        let items = try await fetch(type, options: FetchOptions(sort: sort, limit: pageSize, offset: (page - 1) * pageSize))
        let total = try await count(type)
        return StoragePage(items: items, page: page, pageSize: pageSize, totalCount: total)
    }

    /// How many values of `type` are stored.
    public func count<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws -> Int {
        let typeName = StorageKey.typeName(of: type)
        return try await perform("count \(typeName)", level: .debug) {
            try await engine.count(kind: .entity, typeName: typeName, now: now())
        }
    }

    /// Whether a value of `type` with `id` is stored.
    public func exists<T: Identifiable & Codable & Sendable>(_ type: T.Type, id: T.ID) async throws -> Bool {
        try await liveRecord(forKey: StorageKey.entity(type, id: id)) != nil
    }

    /// Deletes the value with `id`. Deleting a missing ID is a no-op.
    public func delete<T: Identifiable & Codable & Sendable>(_ type: T.Type, id: T.ID) async throws {
        try await delete(type, keys: [StorageKey.entity(type, id: id)])
    }

    /// Deletes every given value by ID in one operation. Missing values are ignored.
    public func delete<T: Identifiable & Codable & Sendable>(_ values: [T]) async throws {
        try await delete(T.self, keys: values.map { StorageKey.entity(T.self, id: $0.id) })
    }

    private func delete<T: Identifiable & Codable & Sendable>(_ type: T.Type, keys: [String]) async throws {
        let typeName = StorageKey.typeName(of: type)
        // `.deleted` carries the stored value, so read it first — but only if someone is watching.
        var deleted: [T] = []
        if hub.hasObservers(typeName) {
            for key in keys {
                // An undecodable record is still deleted; it just has no value to report.
                if let value = try? await value(type, key: key) { deleted.append(value) }
            }
        }
        try await perform(keys.count == 1 ? "delete \(keys[0])" : "delete ×\(keys.count)", level: .info) {
            try await engine.delete(keys: keys)
        }
        hub.publish(deleted.map { .deleted($0) }, to: typeName)
    }

    /// Metadata for the value with `id`, including when it has expired; `nil` if there is none.
    public func metadata<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, id: T.ID
    ) async throws -> StorageMetadata? {
        let key = StorageKey.entity(type, id: id)
        guard let record = try await perform("metadata \(key)", level: .debug, { try await engine.record(forKey: key) }) else { return nil }
        return StorageMetadata(
            createdAt: record.createdAt, updatedAt: record.updatedAt, expiresAt: record.expiresAt,
            size: record.payload.count, isExpired: record.isExpired(at: now())
        )
    }

    /// Deletes every stored value of `type`.
    public func deleteAll<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws {
        let typeName = StorageKey.typeName(of: type)
        try await perform("delete all \(typeName)", level: .info) {
            try await engine.deleteAll(kind: .entity, typeName: typeName)
        }
        hub.publish([.cleared], to: typeName)
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
        try await perform("set \(write.key) (\(write.payload.count) bytes)", level: .info) {
            try await engine.upsert([write], now: timestamp)
        }
    }

    /// The value stored under `key`, or `nil` if there is none.
    public func get<V: Codable & Sendable>(_ type: V.Type, forKey key: String) async throws -> V? {
        try await value(type, key: StorageKey.keyValue(key))
    }

    /// Removes the value stored under `key`. Removing a missing key is a no-op.
    public func remove(forKey key: String) async throws {
        let storageKey = StorageKey.keyValue(key)
        try await perform("remove \(storageKey)", level: .info) { try await engine.delete(keys: [storageKey]) }
    }

    // MARK: - Maintenance

    /// Deletes every expired record (entities and key-value entries); returns how many.
    ///
    /// Reads already skip and purge expired records, so this is only needed to reclaim space.
    @discardableResult
    public func removeExpired() async throws -> Int {
        let removed = try await perform("remove expired", level: .info) { try await engine.deleteExpired(now: now()) }
        if removed > 0 { hub.publishToAll(.expired) }
        return removed
    }

    /// Deletes everything in this store — entities and key-value entries alike.
    public func removeAll() async throws {
        try await perform("remove all", level: .info) { try await engine.deleteAll() }
        hub.publishToAll(.cleared)
    }

    // MARK: - Observation

    /// Every change to stored values of `type` made through this storage, as it happens.
    ///
    /// ```swift
    /// for await change in storage.changes(of: User.self) { ... }
    /// ```
    ///
    /// Events arrive after each write commits. The stream buffers every event and ends when the
    /// consuming task is cancelled.
    public func changes<T: Identifiable & Codable & Sendable>(of type: T.Type) -> AsyncStream<StorageChange<T>> {
        changes(of: type, bufferingPolicy: .unbounded)
    }

    /// The current values of `type` (sorted and sliced by `options`), then the values again after
    /// every change to the type — a live query for SwiftUI:
    ///
    /// ```swift
    /// .task {
    ///     for try await users in storage.updates(of: User.self) { self.users = users }
    /// }
    /// ```
    ///
    /// Bursts of writes are coalesced into one refetch. If the consumer falls behind, it receives
    /// the newest result.
    public func updates<T: Identifiable & Codable & Sendable>(
        of type: T.Type, options: FetchOptions = .default
    ) -> AsyncThrowingStream<[T], any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Subscribe before the first fetch so no change can slip between the two.
            let changes = self.changes(of: type, bufferingPolicy: .bufferingNewest(1))
            let task = Task {
                do {
                    continuation.yield(try await self.fetch(type, options: options))
                    for await _ in changes {
                        continuation.yield(try await self.fetch(type, options: options))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every stored value of `type`, oldest first, loaded `batchSize` at a time as the loop
    /// advances, so large types are never fully in memory.
    public func all<T: Identifiable & Codable & Sendable>(_ type: T.Type, batchSize: Int = 100) -> StorageSequence<T> {
        precondition(batchSize >= 1, "batchSize must be at least 1")
        return StorageSequence(storage: self, batchSize: batchSize)
    }

    func changes<T: Identifiable & Codable & Sendable>(
        of type: T.Type, bufferingPolicy: AsyncStream<StorageChange<T>>.Continuation.BufferingPolicy
    ) -> AsyncStream<StorageChange<T>> {
        let typeName = StorageKey.typeName(of: type)
        let hub = hub
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let token = hub.subscribe(typeName: typeName) { raw in
                if let change = StorageChange<T>(raw) { continuation.yield(change) }
            }
            continuation.onTermination = { _ in hub.unsubscribe(typeName: typeName, token: token) }
        }
    }

    // MARK: - Internals

    /// The record for `key` unless it has expired, in which case it is deleted and `nil` returned.
    func liveRecord(forKey key: String) async throws -> RecordSnapshot? {
        try await perform("read \(key)", level: .debug) {
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
            log(.error, "encode \(T.self) failed: \(Swift.type(of: error))")
            throw LocalStorageError.encodingFailed(underlying: error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from record: RecordSnapshot) throws -> T {
        do {
            return try configuration.decoder.decode(type, from: record.payload)
        } catch {
            log(.error, "decode \(record.key) as \(T.self) failed: \(Swift.type(of: error))")
            throw LocalStorageError.decodingFailed(key: record.key, underlying: error)
        }
    }

    /// Checks cancellation up front, maps every engine error to ``LocalStorageError``, and logs
    /// `operation` at `level` on success or at `.error` on failure.
    @discardableResult
    func perform<R>(
        _ operation: @autoclosure () -> String,
        level: StorageLogLevel,
        _ body: () async throws -> R
    ) async throws -> R {
        guard !Task.isCancelled else {
            log(.error, "\(operation()) cancelled")
            throw LocalStorageError.cancelled
        }
        do {
            let result = try await body()
            log(level, operation())
            return result
        } catch {
            // Engines never throw LocalStorageError, so every error here is a store failure.
            // Only the error's type: its description could echo stored data.
            log(.error, "\(operation()) failed: \(Swift.type(of: error))")
            throw LocalStorageError.persistenceFailed(underlying: error)
        }
    }

    /// Emits `line` if `level` passes the configured filter; builds nothing otherwise.
    func log(_ level: StorageLogLevel, _ line: @autoclosure () -> String) {
        guard level != .none, level <= configuration.logLevel else { return }
        configuration.logger.log("[SwiftLocalStorage] \(line())", level: level)
    }
}

extension [RecordWrite] {
    fileprivate var byteCount: Int { reduce(0) { $0 + $1.payload.count } }
}

extension FetchOptions {
    fileprivate var logDescription: String {
        "sort=\(sort) offset=\(offset)" + (limit.map { " limit=\($0)" } ?? "")
    }
}
