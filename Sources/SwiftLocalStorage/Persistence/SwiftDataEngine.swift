import Foundation
import SwiftData

/// The SwiftData-backed ``StorageEngine``. All `ModelContext` access is isolated to this actor;
/// only ``RecordSnapshot`` values leave it.
@ModelActor
actor SwiftDataEngine: StorageEngine {

    /// Serialises container creation. Building the versioned schemas and migration plan
    /// concurrently races inside SwiftData/CoreData on macOS 15 ("model is still editable",
    /// then a crash), e.g. when several stores open at launch or tests run in parallel.
    private static let openLock = NSLock()

    /// Opens (or creates) the container described by `configuration`.
    static func make(configuration: LocalStorageConfiguration) throws -> SwiftDataEngine {
        // ponytail: one process-wide lock; opening is a one-off per store, so contention is moot.
        try openLock.withLock { try open(configuration) }
    }

    private static func open(_ configuration: LocalStorageConfiguration) throws -> SwiftDataEngine {
        let schema = Schema(versionedSchema: CurrentStorageSchema.self)
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

    /// The last `sequence` handed out; loaded lazily from the store on first insert.
    private var lastSequence: Int?

    private func nextSequence() throws -> Int {
        if lastSequence == nil {
            var descriptor = FetchDescriptor<StoredRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
            descriptor.fetchLimit = 1
            lastSequence = try modelContext.fetch(descriptor).first?.sequence ?? 0
        }
        lastSequence! += 1
        return lastSequence!
    }

    func upsert(_ writes: [RecordWrite], now: Date) async throws -> Set<String> {
        let sequenceBeforeBatch = lastSequence
        var inserted = Set<String>()
        do {
            // One lookup for the whole batch: a fetch per write rescans the pending inserts,
            // which made large batches quadratic.
            var existingModels = try models(forKeys: Array(Set(writes.map(\.key))))
            for write in writes {
                if let existing = existingModels[write.key] {
                    existing.kind = write.kind.rawValue
                    existing.typeName = write.typeName
                    existing.payload = write.payload
                    existing.schemaVersion = write.schemaVersion
                    existing.updatedAt = now
                    existing.expiresAt = write.expiresAt
                    existing.apply(write.index)
                } else {
                    let model = StoredRecord(
                        key: write.key, kind: write.kind.rawValue, typeName: write.typeName,
                        payload: write.payload, schemaVersion: write.schemaVersion,
                        createdAt: now, updatedAt: now, expiresAt: write.expiresAt,
                        sequence: try nextSequence()
                    )
                    model.apply(write.index)
                    modelContext.insert(model)
                    existingModels[write.key] = model
                    inserted.insert(write.key)
                }
            }
            try modelContext.save()
            return inserted
        } catch {
            modelContext.rollback()
            lastSequence = sequenceBeforeBatch
            throw error
        }
    }

    func rewrite(key: String, payload: Data, schemaVersion: Int, index: IndexValues?) async throws {
        guard let record = try model(forKey: key) else { return }
        record.payload = payload
        record.schemaVersion = schemaVersion
        if let index { record.apply(index) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func record(forKey key: String) async throws -> RecordSnapshot? {
        try model(forKey: key).map(Self.snapshot)
    }

    func staleIndexKeys(typeName: String, signature: String) async throws -> [String] {
        let entity = RecordKind.entity.rawValue
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate {
                $0.kind == entity && $0.typeName == typeName && ($0.indexSignature ?? "") != signature
            })
        return try modelContext.fetch(descriptor).map(\.key)
    }

    func setIndex(key: String, values: IndexValues) async throws {
        guard let record = try model(forKey: key) else { return }
        record.apply(values)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func records(
        kind: RecordKind, typeName: String, now: Date,
        sort: StorageSort, limit: Int?, offset: Int, index: IndexQuery?
    ) async throws -> [RecordSnapshot] {
        let kindRaw = kind.rawValue
        let distantFuture = Date.distantFuture

        // Lazy purge: expired rows of this type are removed as a side effect of reading them.
        let expired = #Predicate<StoredRecord> {
            $0.kind == kindRaw && $0.typeName == typeName && ($0.expiresAt ?? distantFuture) <= now
        }
        if try modelContext.fetchCount(FetchDescriptor(predicate: expired)) > 0 {
            try modelContext.delete(model: StoredRecord.self, where: expired)
            try modelContext.save()
        }

        // SwiftData treats fetchLimit == 0 as "no limit", so answer limit 0 here.
        if limit == 0 { return [] }

        // Filter, sort and slice in the store, so only the requested rows are loaded.
        var descriptor = FetchDescriptor<StoredRecord>(
            predicate: Self.livePredicate(kind: kind, typeName: typeName, now: now, index: index),
            sortBy: index?.order.map(Self.sortDescriptors) ?? Self.sortDescriptors(sort)
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(Self.snapshot)
    }

    private static func sortDescriptors(_ sort: StorageSort) -> [SortDescriptor<StoredRecord>] {
        switch sort {
        case .oldestFirst:
            [SortDescriptor(\.createdAt), SortDescriptor(\.sequence)]
        case .newestFirst:
            [SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.sequence, order: .reverse)]
        case .recentlyUpdated:
            [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.sequence, order: .reverse)]
        case .leastRecentlyUpdated:
            [SortDescriptor(\.updatedAt), SortDescriptor(\.sequence)]
        }
    }

    func count(kind: RecordKind, typeName: String, now: Date, index: IndexQuery?) async throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<StoredRecord>(
                predicate: Self.livePredicate(kind: kind, typeName: typeName, now: now, index: index)
            ))
    }

    /// Live records of one kind + type, narrowed by `index` when given.
    private static func livePredicate(
        kind: RecordKind, typeName: String, now: Date, index: IndexQuery?
    ) -> Predicate<StoredRecord> {
        let kindRaw = kind.rawValue
        let distantFuture = Date.distantFuture
        guard let index else {
            return #Predicate {
                $0.kind == kindRaw && $0.typeName == typeName && ($0.expiresAt ?? distantFuture) > now
            }
        }
        // Built from expressions rather than `#Predicate`: only the active conditions are included,
        // which keeps the query small and the type checker out of a combinatorial expression.
        return Predicate { record in
            var terms: [any StandardPredicateExpression<Bool>] = [
                PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(root: record, keyPath: \.kind),
                    rhs: PredicateExpressions.build_Arg(kindRaw)),
                PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(root: record, keyPath: \.typeName),
                    rhs: PredicateExpressions.build_Arg(typeName)),
                PredicateExpressions.build_Comparison(
                    lhs: PredicateExpressions.build_NilCoalesce(
                        lhs: PredicateExpressions.build_KeyPath(root: record, keyPath: \.expiresAt),
                        rhs: PredicateExpressions.build_Arg(distantFuture)),
                    rhs: PredicateExpressions.build_Arg(now), op: .greaterThan),
            ]
            for slot in 0..<IndexValues.slots {
                terms += stringTerms(
                    record, stringSlots[slot], values: index.values[slot], prefix: index.prefixes[slot])
                terms += numberTerms(record, numberSlots[slot], min: index.minimums[slot], max: index.maximums[slot])
            }
            return terms.dropFirst().reduce(terms[0], and)
        }
    }

    private static let stringSlots: [KeyPath<StoredRecord, String?> & Sendable] = [\.s0, \.s1, \.s2]
    private static let numberSlots: [KeyPath<StoredRecord, Double?> & Sendable] = [\.n0, \.n1, \.n2]

    /// A missing string never matches. Values compare against the optional column directly, and a
    /// prefix is a binary range `[prefix, prefix + U+10FFFF)`: CoreData can't translate `IN` or
    /// `BEGINSWITH` over a nil-coalesced column.
    private static func stringTerms(
        _ record: PredicateExpressions.Variable<StoredRecord>, _ slot: KeyPath<StoredRecord, String?> & Sendable,
        values: [String]?, prefix: String?
    ) -> [any StandardPredicateExpression<Bool>] {
        let value = PredicateExpressions.build_KeyPath(root: record, keyPath: slot)
        var terms: [any StandardPredicateExpression<Bool>] = []
        if let values {
            terms.append(
                PredicateExpressions.build_contains(
                    PredicateExpressions.build_Arg(values.map(Optional.some)), value))
        }
        if let prefix {
            let present = PredicateExpressions.build_NilCoalesce(lhs: value, rhs: PredicateExpressions.build_Arg(""))
            terms.append(
                PredicateExpressions.build_NotEqual(lhs: value, rhs: PredicateExpressions.build_NilLiteral()))
            terms.append(
                PredicateExpressions.build_Comparison(
                    lhs: present, rhs: PredicateExpressions.build_Arg(prefix), op: .greaterThanOrEqual))
            terms.append(
                PredicateExpressions.build_Comparison(
                    lhs: present, rhs: PredicateExpressions.build_Arg(prefix + "\u{10FFFF}"), op: .lessThan))
        }
        return terms
    }

    /// A missing number never satisfies a bound: it's coalesced to the far end of the range.
    private static func numberTerms(
        _ record: PredicateExpressions.Variable<StoredRecord>, _ slot: KeyPath<StoredRecord, Double?> & Sendable,
        min: Double?, max: Double?
    ) -> [any StandardPredicateExpression<Bool>] {
        let value = PredicateExpressions.build_KeyPath(root: record, keyPath: slot)
        var terms: [any StandardPredicateExpression<Bool>] = []
        if let min {
            terms.append(
                PredicateExpressions.build_Comparison(
                    lhs: PredicateExpressions.build_NilCoalesce(
                        lhs: value, rhs: PredicateExpressions.build_Arg(-Double.greatestFiniteMagnitude)),
                    rhs: PredicateExpressions.build_Arg(min), op: .greaterThanOrEqual))
        }
        if let max {
            terms.append(
                PredicateExpressions.build_Comparison(
                    lhs: PredicateExpressions.build_NilCoalesce(
                        lhs: value, rhs: PredicateExpressions.build_Arg(Double.greatestFiniteMagnitude)),
                    rhs: PredicateExpressions.build_Arg(max), op: .lessThanOrEqual))
        }
        return terms
    }

    private static func and(
        _ lhs: any StandardPredicateExpression<Bool>, _ rhs: any StandardPredicateExpression<Bool>
    ) -> any StandardPredicateExpression<Bool> {
        func conjoin<L: StandardPredicateExpression<Bool>, R: StandardPredicateExpression<Bool>>(
            _ lhs: L, _ rhs: R
        ) -> any StandardPredicateExpression<Bool> {
            PredicateExpressions.build_Conjunction(lhs: lhs, rhs: rhs)
        }
        return conjoin(lhs, rhs)
    }

    private static func sortDescriptors(_ order: IndexQuery.Order) -> [SortDescriptor<StoredRecord>] {
        let direction: SortOrder = order.ascending ? .forward : .reverse
        let key: SortDescriptor<StoredRecord> =
            switch (order.slot, order.isString) {
            case (0, true): SortDescriptor(\.s0, order: direction)
            case (1, true): SortDescriptor(\.s1, order: direction)
            case (2, true): SortDescriptor(\.s2, order: direction)
            case (0, false): SortDescriptor(\.n0, order: direction)
            case (1, false): SortDescriptor(\.n1, order: direction)
            default: SortDescriptor(\.n2, order: direction)
            }
        // Ties keep insertion order in both directions (a stable sort).
        return [key, SortDescriptor(\.sequence)]
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

    /// The stored models for `keys`, fetched in chunks that stay under SQLite's variable limit.
    private func models(forKeys keys: [String]) throws -> [String: StoredRecord] {
        var result: [String: StoredRecord] = [:]
        for start in stride(from: 0, to: keys.count, by: 500) {
            let chunk = Array(keys[start..<min(start + 500, keys.count)])
            for model in try modelContext.fetch(
                FetchDescriptor(predicate: #Predicate<StoredRecord> { chunk.contains($0.key) }))
            {
                result[model.key] = model
            }
        }
        return result
    }

    private func model(forKey key: String) throws -> StoredRecord? {
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
