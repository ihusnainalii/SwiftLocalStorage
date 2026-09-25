import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

// Three shapes of the same stored type, all under the storage name "Person".

/// v1: what an old app build stored (not versioned, so version 1).
struct PersonV1: Codable, Identifiable, Sendable, Equatable, LocalStorageNaming {
    static var storageTypeName: String { "Person" }
    let id: Int
    var name: String
}

/// v2: `name` renamed to `fullName`.
struct PersonV2: Codable, Identifiable, Sendable, Equatable, LocalStorageNaming, LocalStorageVersioned {
    static var storageTypeName: String { "Person" }
    static var storageVersion: Int { 2 }
    let id: Int
    var fullName: String
}

/// v3 (current): adds a required `role`.
struct PersonV3: Codable, Identifiable, Sendable, Equatable, LocalStorageNaming, LocalStorageVersioned {
    static var storageTypeName: String { "Person" }
    static var storageVersion: Int { 3 }
    let id: Int
    var fullName: String
    var role: String
}

@Suite("DTO migrations")
struct DTOMigrationTests {

    typealias Engine = EngineContractTests.Engine

    /// v1 → v2 typed, v2 → v3 on raw JSON; `calls` counts step invocations.
    static func steps(calls: Counter = Counter()) -> [StorageMigration] {
        [
            StorageMigration(PersonV3.self, from: 1) { (old: PersonV1) in
                calls.increment()
                return PersonV2(id: old.id, fullName: old.name)
            },
            StorageMigration(PersonV3.self, from: 2) { json in
                calls.increment()
                var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
                object["role"] = "member"
                return try JSONSerialization.data(withJSONObject: object)
            },
        ]
    }

    private func storage(
        _ engine: Engine, migrations: [StorageMigration] = steps(), clock: TestDateClock = TestDateClock()
    ) throws -> LocalStorage {
        let configuration = LocalStorageConfiguration(isStoredInMemoryOnly: true, migrations: migrations)
        return switch engine {
        case .swiftData: try LocalStorage(configuration: configuration, now: { clock.now })
        case .inMemory: LocalStorage(configuration: configuration, engine: InMemoryStorageEngine(), now: { clock.now })
        }
    }

    private func migrationError(_ body: () async throws -> Void) async -> (key: String, underlying: any Error)? {
        do {
            try await body()
        } catch LocalStorageError.migrationFailed(let key, let underlying) {
            return (key, underlying)
        } catch {
            Issue.record("expected migrationFailed, got \(error)")
        }
        return nil
    }

    @Test("save records the type's version; unversioned types are version 1", arguments: Engine.allCases)
    func versionsOnSave(engine: Engine) async throws {
        let storage = try storage(engine)
        try await storage.save(PersonV1(id: 1, name: "Old"))
        try await storage.save(PersonV3(id: 2, fullName: "New", role: "admin"))

        #expect(try await storage.metadata(PersonV1.self, id: 1)?.version == 1)
        #expect(try await storage.metadata(PersonV3.self, id: 2)?.version == 3)

        try await storage.save(PersonV3(id: 1, fullName: "Overwritten", role: "admin"))
        #expect(try await storage.metadata(PersonV3.self, id: 1)?.version == 3)
    }

    @Test("reads upgrade old records through the whole chain, once", arguments: Engine.allCases)
    func lazyChain(engine: Engine) async throws {
        let clock = TestDateClock()
        let calls = Counter()
        let storage = try storage(engine, migrations: Self.steps(calls: calls), clock: clock)
        try await storage.save(PersonV1(id: 1, name: "Ada"))
        let before = try #require(try await storage.metadata(PersonV1.self, id: 1))
        clock.advance(by: 60)

        #expect(try await storage.fetch(PersonV3.self, id: 1) == PersonV3(id: 1, fullName: "Ada", role: "member"))
        #expect(calls.value == 2)

        let after = try #require(try await storage.metadata(PersonV3.self, id: 1))
        #expect(after.version == 3)
        #expect(
            (after.createdAt, after.updatedAt, after.expiresAt) == (
                before.createdAt, before.updatedAt, before.expiresAt
            ))

        _ = try await storage.fetch(PersonV3.self, id: 1)
        #expect(calls.value == 2)  // written back: no re-run
    }

    @Test("list, page and filter reads migrate too", arguments: Engine.allCases)
    func listReads(engine: Engine) async throws {
        let storage = try storage(engine)
        try await storage.save([PersonV1(id: 1, name: "A"), PersonV1(id: 2, name: "B")])
        try await storage.save(PersonV3(id: 3, fullName: "C", role: "admin"))

        #expect(try await storage.fetch(PersonV3.self).map(\.fullName) == ["A", "B", "C"])
        #expect(try await storage.page(PersonV3.self, page: 1, pageSize: 2).items.map(\.role) == ["member", "member"])
        #expect(try await storage.fetch(PersonV3.self, where: { $0.role == "admin" }).map(\.id) == [3])
    }

    @Test("migration write-backs emit no change events", arguments: Engine.allCases)
    func noEvents(engine: Engine) async throws {
        let storage = try storage(engine)
        try await storage.save(PersonV1(id: 1, name: "Ada"))
        let received = Counter()
        let token = storage.hub.subscribe(typeName: "Person") { _ in received.increment() }
        defer { storage.hub.unsubscribe(typeName: "Person", token: token) }

        _ = try await storage.fetch(PersonV3.self, id: 1)
        _ = try await storage.migrateAll(PersonV3.self)

        #expect(received.value == 0)
    }

    @Test("a missing step fails and leaves the record untouched", arguments: Engine.allCases)
    func missingStep(engine: Engine) async throws {
        let storage = try storage(engine, migrations: [Self.steps()[1]])  // only 2 → 3
        try await storage.save(PersonV1(id: 1, name: "Ada"))

        let failure = await migrationError { _ = try await storage.fetch(PersonV3.self, id: 1) }

        #expect(failure?.key == StorageKey.entity(typeName: "Person", id: "1"))
        #expect(failure?.underlying as? StorageMigrationError == .missingStep(typeName: "Person", from: 1))
        #expect(try await storage.metadata(PersonV1.self, id: 1)?.version == 1)
        #expect(try await storage.fetch(PersonV1.self, id: 1) == PersonV1(id: 1, name: "Ada"))
    }

    @Test("a record newer than the app fails instead of being misread", arguments: Engine.allCases)
    func newerRecord(engine: Engine) async throws {
        let storage = try storage(engine)
        try await storage.save(PersonV3(id: 1, fullName: "Ada", role: "admin"))

        let failure = await migrationError { _ = try await storage.fetch(PersonV2.self, id: 1) }

        #expect(failure?.underlying as? StorageMigrationError == .storedVersionNewer(stored: 3, current: 2))
    }

    @Test("a throwing step surfaces its error; the record is untouched", arguments: Engine.allCases)
    func throwingStep(engine: Engine) async throws {
        struct Refused: Error {}
        let storage = try storage(
            engine,
            migrations: [
                StorageMigration(PersonV2.self, from: 1) { (_: PersonV1) -> PersonV2 in throw Refused() }
            ])
        try await storage.save(PersonV1(id: 1, name: "Ada"))

        let failure = await migrationError { _ = try await storage.fetch(PersonV2.self, id: 1) }

        #expect(failure?.underlying is Refused)
        #expect(try await storage.metadata(PersonV1.self, id: 1)?.version == 1)
    }

    @Test("a step producing the wrong shape fails to decode; the record is untouched", arguments: Engine.allCases)
    func wrongShape(engine: Engine) async throws {
        let storage = try storage(
            engine,
            migrations: [
                StorageMigration(PersonV2.self, from: 1) { _ in Data("{}".utf8) }
            ])
        try await storage.save(PersonV1(id: 1, name: "Ada"))

        await #expect {
            _ = try await storage.fetch(PersonV2.self, id: 1)
        } throws: { ($0 as? LocalStorageError)?.code == .decodingFailed }
        #expect(try await storage.metadata(PersonV1.self, id: 1)?.version == 1)
    }

    @Test("key-value entries migrate by their value type", arguments: Engine.allCases)
    func keyValue(engine: Engine) async throws {
        struct PrefsV1: Codable, Sendable, LocalStorageNaming {
            static var storageTypeName: String { "Prefs" }
            var dark: Bool
        }
        struct PrefsV2: Codable, Sendable, Equatable, LocalStorageNaming, LocalStorageVersioned {
            static var storageTypeName: String { "Prefs" }
            static var storageVersion: Int { 2 }
            var theme: String
        }
        let calls = Counter()
        let storage = try storage(
            engine,
            migrations: [
                StorageMigration(PrefsV2.self, from: 1) { (old: PrefsV1) in
                    calls.increment()
                    return PrefsV2(theme: old.dark ? "dark" : "light")
                }
            ])
        try await storage.set(PrefsV1(dark: true), forKey: "prefs")

        #expect(try await storage.get(PrefsV2.self, forKey: "prefs") == PrefsV2(theme: "dark"))
        #expect(try await storage.get(PrefsV2.self, forKey: "prefs") == PrefsV2(theme: "dark"))
        #expect(calls.value == 1)
    }

    @Test("migrateAll upgrades every outdated record and is idempotent", arguments: Engine.allCases)
    func migrateAll(engine: Engine) async throws {
        let storage = try storage(engine)
        try await storage.save([PersonV1(id: 1, name: "A"), PersonV1(id: 2, name: "B"), PersonV1(id: 3, name: "C")])
        try await storage.save(PersonV3(id: 4, fullName: "D", role: "admin"))

        #expect(try await storage.migrateAll(PersonV3.self) == 3)
        #expect(try await storage.migrateAll(PersonV3.self) == 0)
        for id in 1...4 {
            #expect(try await storage.metadata(PersonV3.self, id: id)?.version == 3)
        }
    }

    @Test("migrateAll walks more records than one batch", arguments: Engine.allCases)
    func migrateAllBatches(engine: Engine) async throws {
        let storage = try storage(engine)
        try await storage.save((1...1_200).map { PersonV1(id: $0, name: "P\($0)") })

        #expect(try await storage.migrateAll(PersonV3.self) == 1_200)
        #expect(try await storage.migrateAll(PersonV3.self) == 0)
        #expect(try await storage.metadata(PersonV3.self, id: 1_200)?.version == 3)
    }

    @Test("migrateAll stops at the first failure")
    func migrateAllFailure() async throws {
        let storage = try storage(.inMemory, migrations: [])
        try await storage.save(PersonV1(id: 1, name: "A"))

        await #expect {
            try await storage.migrateAll(PersonV3.self)
        } throws: { ($0 as? LocalStorageError)?.code == .migrationFailed }
    }

    @Test("records written before versioning existed read as version 1")
    func legacyRecords() async throws {
        let engine = InMemoryStorageEngine()
        let storage = LocalStorage(configuration: .init(migrations: Self.steps()), engine: engine)
        let legacy = try JSONEncoder().encode(PersonV1(id: 7, name: "Legacy"))
        await engine.insertRaw(legacy, typeName: "Person", id: "7")  // no version given

        #expect(try await storage.fetch(PersonV3.self, id: 7)?.fullName == "Legacy")
    }
}
