import Foundation
import SwiftData

/// The SwiftData-backed ``StorageEngine``. All `ModelContext` access is isolated to this actor;
/// only ``RecordSnapshot`` values leave it.
@ModelActor
actor SwiftDataEngine: StorageEngine {

    /// Opens (or creates) the container described by `configuration`.
    static func make(configuration: LocalStorageConfiguration) throws -> SwiftDataEngine {
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
            for write in writes {
                if let existing = try model(forKey: write.key) {
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
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
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
        try modelContext.fetchCount(FetchDescriptor<StoredRecord>(
            predicate: Self.livePredicate(kind: kind, typeName: typeName, now: now, index: index)
        ))
    }

    /// Live records of one kind + type, narrowed by `index` when given. Unused conditions are
    /// switched off with captured flags, so one predicate shape covers every query.
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
        // A missing number never satisfies a bound: it's coalesced to the far end of the range.
        let low = -Double.greatestFiniteMagnitude
        let high = Double.greatestFiniteMagnitude
        let s0 = index.strings[0], s1 = index.strings[1], s2 = index.strings[2]
        let hasS0 = s0 != nil, hasS1 = s1 != nil, hasS2 = s2 != nil
        let min0 = index.minimums[0] ?? low, min1 = index.minimums[1] ?? low, min2 = index.minimums[2] ?? low
        let hasMin0 = index.minimums[0] != nil, hasMin1 = index.minimums[1] != nil, hasMin2 = index.minimums[2] != nil
        let max0 = index.maximums[0] ?? high, max1 = index.maximums[1] ?? high, max2 = index.maximums[2] ?? high
        let hasMax0 = index.maximums[0] != nil, hasMax1 = index.maximums[1] != nil, hasMax2 = index.maximums[2] != nil
        return #Predicate<StoredRecord> { record in
            record.kind == kindRaw && record.typeName == typeName && (record.expiresAt ?? distantFuture) > now
                && (!hasS0 || record.s0 == s0) && (!hasS1 || record.s1 == s1) && (!hasS2 || record.s2 == s2)
                && (!hasMin0 || (record.n0 ?? low) >= min0) && (!hasMax0 || (record.n0 ?? high) <= max0)
                && (!hasMin1 || (record.n1 ?? low) >= min1) && (!hasMax1 || (record.n1 ?? high) <= max1)
                && (!hasMin2 || (record.n2 ?? low) >= min2) && (!hasMax2 || (record.n2 ?? high) <= max2)
        }
    }

    private static func sortDescriptors(_ order: IndexQuery.Order) -> [SortDescriptor<StoredRecord>] {
        let direction: SortOrder = order.ascending ? .forward : .reverse
        let key: SortDescriptor<StoredRecord> = switch (order.slot, order.isString) {
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
