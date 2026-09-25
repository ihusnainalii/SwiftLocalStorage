import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

/// A DTO whose single string index may be missing.
struct Label: Codable, Identifiable, Sendable, Equatable, LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<Label>] {
        [.string("name") { $0.name }, .number("rank") { $0.rank }]
    }
    let id: Int
    var name: String?
    var rank: Int
}

@Suite("Index string filters")
struct IndexFilterTests {

    typealias Engine = EngineContractTests.Engine

    /// ids 1…5: "admin", "admin-ops", "Admin", "member", nil — ranks 50, 40, 30, 20, 10.
    private func seeded(_ engine: Engine) async throws -> LocalStorage {
        let storage = try engine.storage()
        try await storage.save([
            Label(id: 1, name: "admin", rank: 50),
            Label(id: 2, name: "admin-ops", rank: 40),
            Label(id: 3, name: "Admin", rank: 30),
            Label(id: 4, name: "member", rank: 20),
            Label(id: 5, name: nil, rank: 10),
        ])
        return storage
    }

    private func ids(_ storage: LocalStorage, _ filters: [StorageFilter]) async throws -> [Int] {
        try await storage.fetch(Label.self, matching: filters).map(\.id)
    }

    @Test("hasPrefix is case-sensitive and skips missing values", arguments: Engine.allCases)
    func prefix(engine: Engine) async throws {
        let storage = try await seeded(engine)
        #expect(try await ids(storage, [.hasPrefix("name", "admin")]) == [1, 2])
        #expect(try await ids(storage, [.hasPrefix("name", "")]) == [1, 2, 3, 4])
        #expect(try await ids(storage, [.hasPrefix("name", "zzz")]).isEmpty)
    }

    @Test("oneOf matches any listed value; an empty list matches nothing", arguments: Engine.allCases)
    func oneOf(engine: Engine) async throws {
        let storage = try await seeded(engine)
        #expect(try await ids(storage, [.oneOf("name", ["admin", "member"])]) == [1, 4])
        #expect(try await ids(storage, [.oneOf("name", [])]).isEmpty)
        #expect(try await storage.count(Label.self, matching: [.oneOf("name", [])]) == 0)
    }

    @Test("string conditions on one index intersect", arguments: Engine.allCases)
    func intersections(engine: Engine) async throws {
        let storage = try await seeded(engine)
        #expect(try await ids(storage, [.equals("name", "admin"), .oneOf("name", ["admin", "member"])]) == [1])
        #expect(try await ids(storage, [.equals("name", "admin"), .equals("name", "member")]).isEmpty)
        #expect(try await ids(storage, [.oneOf("name", ["admin", "Admin"]), .hasPrefix("name", "a")]) == [1])
        #expect(try await ids(storage, [.hasPrefix("name", "ad"), .hasPrefix("name", "admin")]) == [1, 2])
        #expect(try await ids(storage, [.hasPrefix("name", "admin"), .hasPrefix("name", "ad")]) == [1, 2])
        #expect(try await ids(storage, [.hasPrefix("name", "ad"), .hasPrefix("name", "me")]).isEmpty)
    }

    @Test("string filters combine with number conditions, order, limit, count and page", arguments: Engine.allCases)
    func combined(engine: Engine) async throws {
        let storage = try await seeded(engine)
        let filters: [StorageFilter] = [.hasPrefix("name", "a"), .atLeast("rank", 40)]

        #expect(try await ids(storage, filters) == [1, 2])
        let ordered = try await storage.fetch(
            Label.self, matching: [.oneOf("name", ["admin", "admin-ops", "member"])],
            orderedBy: .ascending("rank"), options: FetchOptions(limit: 2)
        )
        #expect(ordered.map(\.id) == [4, 2])
        #expect(try await storage.count(Label.self, matching: filters) == 2)

        let page = try await storage.page(
            Label.self, matching: [.hasPrefix("name", "")], orderedBy: .descending("rank"), page: 2, pageSize: 3
        )
        #expect(page.items.map(\.id) == [4])
        #expect(page.totalCount == 4)
    }

    @Test("a query that matches nothing still pages cleanly", arguments: Engine.allCases)
    func emptyPage(engine: Engine) async throws {
        let storage = try await seeded(engine)
        let page = try await storage.page(Label.self, matching: [.oneOf("name", [])], page: 1, pageSize: 10)
        #expect(page.items.isEmpty)
        #expect(page.totalCount == 0)
    }

    // MARK: - Indexed live queries

    @Test("indexed updates emit filtered, ordered, limited results after each write", arguments: Engine.allCases)
    func liveQuery(engine: Engine) async throws {
        let storage = try await seeded(engine)
        var results = storage.updates(
            of: Label.self, matching: [.hasPrefix("name", "a")], orderedBy: .descending("rank"),
            options: FetchOptions(limit: 2)
        ).makeAsyncIterator()
        #expect(try await results.next()?.map(\.id) == [1, 2])

        try await storage.save(Label(id: 6, name: "alpha", rank: 99))
        #expect(try await results.next()?.map(\.id) == [6, 1])

        try await storage.save(Label(id: 7, name: "zulu", rank: 100))  // doesn't match: same result
        #expect(try await results.next()?.map(\.id) == [6, 1])
    }

    @Test("indexed updates re-index records written without the declaration", arguments: Engine.allCases)
    func liveQueryReindexes(engine: Engine) async throws {
        let storage = try engine.storage()
        var results = storage.updates(of: Member.self, matching: [.equals("role", "admin")]).makeAsyncIterator()
        #expect(try await results.next() == [])

        // Events are typed, so the unindexed write alone doesn't wake the stream; the next Member
        // write does, and its refetch re-indexes the older record too.
        try await storage.save(PlainMember(id: 1, role: "admin", age: 30, joined: nil))
        try await storage.save(Member(id: 2, role: "admin", age: 40, joined: nil))
        #expect(try await results.next()?.map(\.id) == [1, 2])
    }

    @Test("indexed updates finish with the error when the store fails")
    func liveQueryFailure() async throws {
        let storage = LocalStorage(configuration: .inMemory, engine: ErrorTests.FailingEngine(), now: { Date() })
        var results = storage.updates(of: Label.self, matching: [.oneOf("name", ["a"])]).makeAsyncIterator()

        await #expect {
            _ = try await results.next()
        } throws: { ($0 as? LocalStorageError)?.code == .persistenceFailed }
    }

    @Test("repository forwards indexed updates")
    func repositoryLiveQuery() async throws {
        let storage = try await seeded(.inMemory)
        var results = storage.repository(Label.self).updates(matching: [.equals("name", "member")]).makeAsyncIterator()
        #expect(try await results.next()?.map(\.id) == [4])
    }
}
