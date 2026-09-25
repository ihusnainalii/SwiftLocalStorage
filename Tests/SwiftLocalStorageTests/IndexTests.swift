import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

/// An indexed DTO: string, integer and optional-date indexes.
struct Member: Codable, Identifiable, Sendable, Equatable, LocalStorageNaming, LocalStorageIndexed {
    static var storageTypeName: String { "Member" }
    static var storageIndexes: [StorageIndex<Member>] {
        [.string("role") { $0.role }, .number("age") { $0.age }, .number("joined") { $0.joined }]
    }

    let id: Int
    var role: String
    var age: Int
    var joined: Date?
}

/// The same stored type before it declared indexes.
struct PlainMember: Codable, Identifiable, Sendable, LocalStorageNaming {
    static var storageTypeName: String { "Member" }
    let id: Int
    var role: String
    var age: Int
    var joined: Date?
}

/// The same stored type with a different declaration (`age` moved to the first slot).
struct ReindexedMember: Codable, Identifiable, Sendable, Equatable, LocalStorageNaming, LocalStorageIndexed {
    static var storageTypeName: String { "Member" }
    static var storageIndexes: [StorageIndex<ReindexedMember>] { [.number("age") { $0.age }] }
    let id: Int
    var role: String
    var age: Int
    var joined: Date?
}

/// Bool, Date and Double indexes.
struct Reading: Codable, Identifiable, Sendable, Equatable, LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<Reading>] {
        [.number("valid") { $0.valid }, .number("at") { $0.at }, .number("value") { $0.value }]
    }
    let id: Int
    var valid: Bool
    var at: Date
    var value: Double
}

@Suite("Indexed fields")
struct IndexTests {

    typealias Engine = EngineContractTests.Engine

    private static let day = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Five members saved in id order.
    private func seeded(_ engine: Engine, clock: TestDateClock = TestDateClock()) async throws -> LocalStorage {
        let storage = try engine.storage(clock: clock)
        try await storage.save([
            Member(id: 1, role: "admin", age: 40, joined: Self.day),
            Member(id: 2, role: "member", age: 25, joined: Self.day + 86_400),
            Member(id: 3, role: "admin", age: 31, joined: nil),
            Member(id: 4, role: "member", age: 18, joined: Self.day - 86_400),
            Member(id: 5, role: "guest", age: 25, joined: Self.day),
        ])
        return storage
    }

    private func ids(
        _ storage: LocalStorage, _ filters: [StorageFilter], _ order: StorageIndexOrder? = nil,
        _ options: FetchOptions = .default
    ) async throws -> [Int] {
        try await storage.fetch(Member.self, matching: filters, orderedBy: order, options: options).map(\.id)
    }

    @Test("equality on string and number indexes", arguments: Engine.allCases)
    func equality(engine: Engine) async throws {
        let storage = try await seeded(engine)

        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3])
        #expect(try await ids(storage, [.equals("age", 25)]) == [2, 5])
        #expect(try await ids(storage, [.equals("role", "nobody")]) == [])
        #expect(try await ids(storage, []) == [1, 2, 3, 4, 5])
    }

    @Test("ranges, and conditions ANDed across and within indexes", arguments: Engine.allCases)
    func ranges(engine: Engine) async throws {
        let storage = try await seeded(engine)

        #expect(try await ids(storage, [.atLeast("age", 30)]) == [1, 3])
        #expect(try await ids(storage, [.atMost("age", 25)]) == [2, 4, 5])
        #expect(try await ids(storage, [.between("age", 20...35)]) == [2, 3, 5])
        #expect(try await ids(storage, [.equals("role", "member"), .atLeast("age", 20)]) == [2])
        #expect(try await ids(storage, [.atLeast("age", 20), .atMost("age", 30)]) == [2, 5])
        #expect(try await ids(storage, [.between("joined", Self.day...(Self.day + 86_400))]) == [1, 2, 5])
    }

    @Test("a missing index value never matches a condition on it", arguments: Engine.allCases)
    func nilValues(engine: Engine) async throws {
        let storage = try await seeded(engine)

        #expect(try await ids(storage, [.atMost("joined", Self.day + 999_999)]).contains(3) == false)
        #expect(try await ids(storage, [.atLeast("joined", Date.distantPast)]).contains(3) == false)
    }

    @Test("ordering by an index: ties keep insertion order, missing values first ascending", arguments: Engine.allCases)
    func ordering(engine: Engine) async throws {
        let storage = try await seeded(engine)

        #expect(try await ids(storage, [], .ascending("age")) == [4, 2, 5, 3, 1])
        #expect(try await ids(storage, [], .descending("age")) == [1, 3, 2, 5, 4])
        #expect(try await ids(storage, [], .ascending("role")) == [1, 3, 5, 2, 4])
        #expect(try await ids(storage, [], .ascending("joined")) == [3, 4, 1, 5, 2])
        #expect(try await ids(storage, [], .descending("joined")) == [2, 1, 5, 4, 3])
        #expect(try await ids(storage, [.equals("role", "admin")], .ascending("age")) == [3, 1])
    }

    @Test("limit, offset, counts and pages apply to the filtered set", arguments: Engine.allCases)
    func slicing(engine: Engine) async throws {
        let storage = try await seeded(engine)

        #expect(
            try await ids(storage, [.atMost("age", 31)], .ascending("age"), FetchOptions(limit: 2, offset: 1)) == [
                2, 5,
            ])
        #expect(try await storage.count(Member.self, matching: [.atLeast("age", 25)]) == 4)
        #expect(try await storage.count(Member.self, matching: []) == 5)

        let page = try await storage.page(
            Member.self, matching: [.atLeast("age", 25)], orderedBy: .descending("age"), page: 2, pageSize: 3)
        #expect(page.items.map(\.id) == [5])
        #expect((page.totalCount, page.totalPages, page.hasNextPage) == (4, 2, false))
    }

    @Test("expired records are excluded from indexed results and counts", arguments: Engine.allCases)
    func expiry(engine: Engine) async throws {
        let clock = TestDateClock()
        let storage = try await seeded(engine, clock: clock)
        try await storage.save(Member(id: 6, role: "admin", age: 50), expiration: .seconds(1))
        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3, 6])

        clock.advance(by: 2)

        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3])
        #expect(try await storage.count(Member.self, matching: [.equals("role", "admin")]) == 2)
    }

    @Test("updates re-index; deletes drop out", arguments: Engine.allCases)
    func updates(engine: Engine) async throws {
        let storage = try await seeded(engine)
        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3])

        try await storage.save(Member(id: 2, role: "admin", age: 26))
        try await storage.delete(Member.self, id: 1)

        #expect(try await ids(storage, [.equals("role", "admin")]) == [2, 3])
        #expect(try await ids(storage, [.equals("age", 26)]) == [2])
    }

    @Test("records saved before the type was indexed are re-indexed on the first query", arguments: Engine.allCases)
    func reindexUnindexed(engine: Engine) async throws {
        let storage = try engine.storage()
        try await storage.save([
            PlainMember(id: 1, role: "admin", age: 40), PlainMember(id: 2, role: "member", age: 20),
        ])

        #expect(try await ids(storage, [.equals("role", "admin")]) == [1])
        #expect(try await ids(storage, [], .descending("age")) == [1, 2])
    }

    @Test("changing the declaration re-indexes stale records", arguments: Engine.allCases)
    func reindexChangedDeclaration(engine: Engine) async throws {
        let storage = try await seeded(engine)
        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3])  // Member layout

        let olderThan30 = try await storage.fetch(ReindexedMember.self, matching: [.atLeast("age", 30)])

        #expect(olderThan30.map(\.id) == [1, 3])
    }

    @Test("alternating declarations and unindexed saves after a check stay correct", arguments: Engine.allCases)
    func staleAfterCheck(engine: Engine) async throws {
        let storage = try await seeded(engine)
        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3])  // checked as Member
        #expect(try await storage.fetch(ReindexedMember.self, matching: [.atLeast("age", 30)]).map(\.id) == [1, 3])

        // Back to Member: its records were re-indexed with the other declaration meanwhile.
        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3])

        // A save through the unindexed twin after the check must not leave a stale record behind.
        try await storage.save(PlainMember(id: 9, role: "admin", age: 60))
        #expect(try await ids(storage, [.equals("role", "admin")]) == [1, 3, 9])
    }

    @Test("Bool, Date and Double indexes", arguments: Engine.allCases)
    func otherNumbers(engine: Engine) async throws {
        let storage = try engine.storage()
        try await storage.save([
            Reading(id: 1, valid: true, at: Self.day, value: 1.5),
            Reading(id: 2, valid: false, at: Self.day + 60, value: -3),
            Reading(id: 3, valid: true, at: Self.day + 120, value: 99.25),
        ])
        func ids(_ filters: [StorageFilter], _ order: StorageIndexOrder? = nil) async throws -> [Int] {
            try await storage.fetch(Reading.self, matching: filters, orderedBy: order).map(\.id)
        }

        #expect(try await ids([.equals("valid", true)]) == [1, 3])
        #expect(try await ids([.equals("valid", false)]) == [2])
        #expect(try await ids([.equals("at", Self.day + 60)]) == [2])
        #expect(try await ids([.atLeast("value", 0.0)], .descending("value")) == [3, 1])
        #expect(try await ids([.equals("value", 99.25)]) == [3])
    }

    @Test("a DTO migration write-back stores fresh index values")
    func migrationReindexes() async throws {
        struct IndexedPerson: Codable, Identifiable, Sendable, LocalStorageNaming, LocalStorageVersioned,
            LocalStorageIndexed
        {
            static var storageTypeName: String { "Person" }
            static var storageVersion: Int { 2 }
            static var storageIndexes: [StorageIndex<IndexedPerson>] { [.string("fullName") { $0.fullName }] }
            let id: Int
            var fullName: String
        }
        let engine = InMemoryStorageEngine()
        let storage = LocalStorage(
            configuration: .init(migrations: [
                StorageMigration(IndexedPerson.self, from: 1) { (old: PersonV1) in
                    PersonV2(id: old.id, fullName: old.name)
                }
            ]),
            engine: engine
        )
        try await storage.save(PersonV1(id: 1, name: "Ada"))
        let signature = IndexLayout(IndexedPerson.self).signature
        #expect(try await engine.staleIndexKeys(typeName: "Person", signature: signature).count == 1)

        _ = try await storage.fetch(IndexedPerson.self, id: 1)  // migrates + writes back

        #expect(try await engine.staleIndexKeys(typeName: "Person", signature: signature).isEmpty)
        #expect(try await storage.fetch(IndexedPerson.self, matching: [.equals("fullName", "Ada")]).map(\.id) == [1])
    }

    @Test("repository forwards indexed queries")
    func repository() async throws {
        let storage = try await seeded(.inMemory)
        let members = storage.repository(Member.self)

        #expect(
            try await members.fetch(matching: [.equals("role", "admin")], orderedBy: .descending("age")).map(\.id) == [
                1, 3,
            ])
        #expect(try await members.count(matching: [.equals("role", "member")]) == 2)
        #expect(
            try await members.page(matching: [], orderedBy: .ascending("age"), page: 1, pageSize: 2).items.map(\.id)
                == [4, 2])
    }

    @Test("every number type maps to its Double value")
    func numberConversions() {
        #expect(Int32(-7).storageIndexValue == -7)
        #expect(Int64(1 << 40).storageIndexValue == Double(1 << 40))
        #expect(UInt(9).storageIndexValue == 9)
        #expect(Float(2.5).storageIndexValue == 2.5)
        #expect(true.storageIndexValue == 1 && false.storageIndexValue == 0)
        #expect(Date(timeIntervalSinceReferenceDate: 42).storageIndexValue == 42)
    }

    @Test("filters and layouts resolve names to slots and signatures")
    func layout() {
        let layout = IndexLayout(Member.self)
        #expect(layout.signature == "role:s|age:n|joined:n")

        let query = layout.query(
            filters: [.equals("role", "admin"), .between("age", 18...30), .atMost("age", 25)],
            order: .descending("joined"))
        #expect(query.values == [["admin"], nil, nil])
        #expect(query.prefixes == [nil, nil, nil])
        #expect(!query.matchesNothing)
        #expect(query.minimums == [nil, 18, nil])
        #expect(query.maximums == [nil, 25, nil])
        #expect(query.order == IndexQuery.Order(slot: 2, isString: false, ascending: false))
        #expect(StorageFilter.equals("x", 1) == StorageFilter.equals("x", 1.0))
    }
}
