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
    /// `typeName → fromVersion → step`, built once from the configuration.
    let migrations: [String: [Int: StorageMigration]]
    /// Types whose stored index values this instance has verified against a declaration.
    let indexedSignatures = IndexedSignatures()

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
        var table: [String: [Int: StorageMigration]] = [:]
        for step in configuration.migrations {
            precondition(
                table[step.typeName]?[step.fromVersion] == nil,
                "Duplicate StorageMigration for \(step.typeName) from version \(step.fromVersion)"
            )
            table[step.typeName, default: [:]][step.fromVersion] = step
        }
        migrations = table
    }

    // MARK: - Entities

    /// Inserts `value`, or replaces the stored value with the same ID (keeping its `createdAt`).
    ///
    /// - Parameters:
    ///   - value: the value to store, keyed by its type and `id`.
    ///   - expiration: after this, reads treat the value as absent.
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
                kind: .entity, typeName: typeName, payload: try encode(value), expiresAt: expiresAt,
                schemaVersion: StorageKey.version(of: T.self), index: indexValues(for: value)
            )
        }
        var newKeys = try await perform("save \(typeName) ×\(writes.count) (\(writes.byteCount) bytes)", level: .info) {
            try await engine.upsert(writes, now: timestamp)
        }
        if let first = writes.first { indexedSignatures.wrote(typeName, first.index?.signature) }
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
                sort: options.sort, limit: options.limit, offset: options.offset, index: nil
            )
        }
        var values: [T] = []
        values.reserveCapacity(records.count)
        for record in records {
            values.append(try await decode(type, from: record))
        }
        return values
    }

    /// Stored values of `type` matching `isIncluded`, then sorted and sliced by `options`.
    ///
    /// DTO fields live inside encoded payloads, so the filter runs in memory: values are loaded
    /// and decoded 500 at a time in `options.sort` order, stopping as soon as `offset + limit`
    /// matches are found. For hot queries on large types, filter on an index with
    /// ``fetch(_:matching:orderedBy:options:)`` instead.
    ///
    /// With `.recentlyUpdated` / `.leastRecentlyUpdated`, a value updated by another task during
    /// the walk can move across a batch boundary and be seen twice or missed.
    public func fetch<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, where isIncluded: (T) throws -> Bool, options: FetchOptions = .default
    ) async throws -> [T] {
        let wanted = options.limit.map { options.offset + $0 }
        if wanted == 0 { return [] }
        var matches: [T] = []
        try await walk(StorageKey.typeName(of: type), sort: options.sort) { batch in
            for record in batch {
                let value = try await decode(type, from: record)
                guard try isIncluded(value) else { continue }
                matches.append(value)
                if matches.count == wanted { return false }
            }
            return true
        }
        return Array(matches.dropFirst(options.offset))
    }

    /// Records per store call in a batched walk (`fetch(_:where:options:)`, `migrateAll(_:)`).
    static let walkBatchSize = 500

    /// Visits the live records of `typeName` in `sort` order, ``walkBatchSize`` at a time, until
    /// `body` returns `false` or the records run out. The whole walk uses one `now`, so a record
    /// expiring mid-walk can't be purged and shift the offsets.
    private func walk(
        _ typeName: String, sort: StorageSort, _ body: ([RecordSnapshot]) async throws -> Bool
    ) async throws {
        let start = now()
        var offset = 0
        while true {
            let batch = try await perform("fetch \(typeName) batch at \(offset)", level: .debug) {
                try await engine.records(
                    kind: .entity, typeName: typeName, now: start,
                    sort: sort, limit: Self.walkBatchSize, offset: offset, index: nil
                )
            }
            guard try await body(batch), batch.count == Self.walkBatchSize else { return }
            offset += batch.count
        }
    }

    /// Page `page` (1-based) of `pageSize` values of `type`, with the totals for paging UI.
    public func page<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, page: Int, pageSize: Int, sort: StorageSort = .oldestFirst
    ) async throws -> StoragePage<T> {
        precondition(page >= 1, "page is 1-based")
        precondition(pageSize >= 1, "pageSize must be at least 1")
        let items = try await fetch(
            type, options: FetchOptions(sort: sort, limit: pageSize, offset: (page - 1) * pageSize))
        let total = try await count(type)
        return StoragePage(items: items, page: page, pageSize: pageSize, totalCount: total)
    }

    /// How many values of `type` are stored.
    public func count<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws -> Int {
        let typeName = StorageKey.typeName(of: type)
        return try await perform("count \(typeName)", level: .debug) {
            try await engine.count(kind: .entity, typeName: typeName, now: now(), index: nil)
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
        guard let record = try await perform("metadata \(key)", level: .debug, { try await engine.record(forKey: key) })
        else { return nil }
        return StorageMetadata(
            createdAt: record.createdAt, updatedAt: record.updatedAt, expiresAt: record.expiresAt,
            size: record.payload.count, isExpired: record.isExpired(at: now()), version: record.schemaVersion
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
            expiresAt: expiration.expiresAt(from: timestamp), schemaVersion: StorageKey.version(of: V.self)
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

    // MARK: - Indexed queries

    /// Values of `type` matching every condition in `filters` (ANDed), ordered by an indexed field
    /// when `order` is given (else by `options.sort`), sliced by `options` — all inside the store.
    ///
    /// ```swift
    /// let admins = try await storage.fetch(User.self, matching: [.equals("role", "admin")],
    ///                                      orderedBy: .descending("lastSeen"))
    /// ```
    public func fetch<T: Identifiable & Codable & Sendable & LocalStorageIndexed>(
        _ type: T.Type, matching filters: [StorageFilter], orderedBy order: StorageIndexOrder? = nil,
        options: FetchOptions = .default
    ) async throws -> [T] {
        let typeName = StorageKey.typeName(of: type)
        let query = try await indexQuery(type, filters: filters, order: order)
        if query.matchesNothing { return [] }
        let records = try await perform("fetch \(typeName) indexed \(options.logDescription)", level: .debug) {
            try await engine.records(
                kind: .entity, typeName: typeName, now: now(),
                sort: options.sort, limit: options.limit, offset: options.offset, index: query
            )
        }
        var values: [T] = []
        values.reserveCapacity(records.count)
        for record in records {
            values.append(try await decode(type, from: record))
        }
        return values
    }

    /// How many live values of `type` match every condition in `filters`.
    public func count<T: Identifiable & Codable & Sendable & LocalStorageIndexed>(
        _ type: T.Type, matching filters: [StorageFilter]
    ) async throws -> Int {
        let typeName = StorageKey.typeName(of: type)
        let query = try await indexQuery(type, filters: filters, order: nil)
        if query.matchesNothing { return 0 }
        return try await perform("count \(typeName) indexed", level: .debug) {
            try await engine.count(kind: .entity, typeName: typeName, now: now(), index: query)
        }
    }

    /// Page `page` (1-based) of the values of `type` matching `filters`, with totals.
    public func page<T: Identifiable & Codable & Sendable & LocalStorageIndexed>(
        _ type: T.Type, matching filters: [StorageFilter], orderedBy order: StorageIndexOrder? = nil,
        page: Int, pageSize: Int
    ) async throws -> StoragePage<T> {
        precondition(page >= 1, "page is 1-based")
        precondition(pageSize >= 1, "pageSize must be at least 1")
        let items = try await fetch(
            type, matching: filters, orderedBy: order,
            options: FetchOptions(limit: pageSize, offset: (page - 1) * pageSize)
        )
        let total = try await count(type, matching: filters)
        return StoragePage(items: items, page: page, pageSize: pageSize, totalCount: total)
    }

    /// Resolves `filters` / `order` against `type`'s declaration, first re-indexing — once per
    /// type per instance — records saved before the type was indexed or with another declaration.
    private func indexQuery<T: Identifiable & Codable & Sendable & LocalStorageIndexed>(
        _ type: T.Type, filters: [StorageFilter], order: StorageIndexOrder?
    ) async throws -> IndexQuery {
        let layout = IndexLayout(type)
        let query = layout.query(filters: filters, order: order)
        let typeName = StorageKey.typeName(of: type)
        guard !indexedSignatures.isCurrent(typeName, layout.signature) else { return query }

        let stale = try await perform("check index \(typeName)", level: .debug) {
            try await engine.staleIndexKeys(typeName: typeName, signature: layout.signature)
        }
        for key in stale {
            guard let record = try await perform("read \(key)", level: .debug, { try await engine.record(forKey: key) })
            else {
                continue
            }
            let value = try await decode(type, from: record)
            try await perform("reindex \(key)", level: .info) {
                try await engine.setIndex(key: key, values: layout.values(for: value))
            }
        }
        indexedSignatures.markCurrent(typeName, layout.signature)
        return query
    }

    // MARK: - Migration

    /// Upgrades every live stored value of `type` whose version is older than
    /// ``LocalStorageVersioned/storageVersion``; returns how many were upgraded. Reads already
    /// migrate lazily — call this to do it all up front, e.g. at launch after a release.
    ///
    /// Stops at the first record that fails to migrate or decode, throwing its error.
    @discardableResult
    public func migrateAll<T: Identifiable & Codable & Sendable>(_ type: T.Type) async throws -> Int {
        let typeName = StorageKey.typeName(of: type)
        let current = StorageKey.version(of: type)
        log(.info, "migrate all \(typeName)")
        var upgraded = 0
        // Walks in creation order; a write-back keeps a record's creation time and sequence, so
        // batches never shift under it.
        try await walk(typeName, sort: .oldestFirst) { batch in
            for record in batch where record.schemaVersion != current {
                _ = try await decode(type, from: record)
                upgraded += 1
            }
            return true
        }
        return upgraded
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
        return try await decode(type, from: record)
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try configuration.encoder.encode(value)
        } catch {
            log(.error, "encode \(T.self) failed: \(Swift.type(of: error))")
            throw LocalStorageError.encodingFailed(underlying: error)
        }
    }

    /// Decodes `record` as `T`, first upgrading an older payload through the registered
    /// migrations and writing the upgraded payload back (timestamps untouched, no change events).
    private func decode<T: Decodable>(_ type: T.Type, from record: RecordSnapshot) async throws -> T {
        let current = StorageKey.version(of: type)
        guard record.schemaVersion != current else {
            return try decodePayload(type, record.payload, key: record.key)
        }
        let upgraded = try migrate(record, to: current)
        let value = try decodePayload(type, upgraded, key: record.key)
        try await perform("migrate \(record.key) v\(record.schemaVersion)→v\(current)", level: .info) {
            try await engine.rewrite(
                key: record.key, payload: upgraded, schemaVersion: current, index: indexValues(for: value)
            )
        }
        if let index = indexValues(for: value) { indexedSignatures.wrote(record.typeName, index.signature) }
        return value
    }

    /// Runs the steps `record.schemaVersion → … → current` in memory.
    private func migrate(_ record: RecordSnapshot, to current: Int) throws -> Data {
        func fail(_ error: any Error) -> LocalStorageError {
            log(.error, "migrate \(record.key) v\(record.schemaVersion)→v\(current) failed: \(Swift.type(of: error))")
            return .migrationFailed(key: record.key, underlying: error)
        }
        guard record.schemaVersion < current else {
            throw fail(StorageMigrationError.storedVersionNewer(stored: record.schemaVersion, current: current))
        }
        var payload = record.payload
        for version in record.schemaVersion..<current {
            guard let step = migrations[record.typeName]?[version] else {
                throw fail(StorageMigrationError.missingStep(typeName: record.typeName, from: version))
            }
            do {
                payload = try step.transform(payload, configuration.decoder, configuration.encoder)
            } catch {
                throw fail(error)
            }
        }
        return payload
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, _ payload: Data, key: String) throws -> T {
        do {
            return try configuration.decoder.decode(type, from: payload)
        } catch {
            log(.error, "decode \(key) as \(T.self) failed: \(Swift.type(of: error))")
            throw LocalStorageError.decodingFailed(key: key, underlying: error)
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
