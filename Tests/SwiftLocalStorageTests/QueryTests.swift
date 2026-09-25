import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

@Suite("Queries: sort, slice, filter, pages")
struct QueryTests {

    typealias Engine = EngineContractTests.Engine

    /// Saves A, B, C one second apart, then B again (so B is the most recently updated).
    private func seeded(_ engine: Engine) async throws -> (LocalStorage, TestDateClock, [User]) {
        let clock = TestDateClock()
        let storage = try engine.storage(clock: clock)
        let users = ["A", "B", "C"].map(User.make)
        for user in users {
            try await storage.save(user)
            clock.advance(by: 1)
        }
        try await storage.save(users[1])
        return (storage, clock, users)
    }

    private func names(_ storage: LocalStorage, _ options: FetchOptions) async throws -> [String] {
        try await storage.fetch(User.self, options: options).map(\.name)
    }

    @Test("every sort order", arguments: Engine.allCases)
    func sorts(engine: Engine) async throws {
        let (storage, _, _) = try await seeded(engine)

        #expect(try await names(storage, .init(sort: .oldestFirst)) == ["A", "B", "C"])
        #expect(try await names(storage, .init(sort: .newestFirst)) == ["C", "B", "A"])
        #expect(try await names(storage, .init(sort: .recentlyUpdated)) == ["B", "C", "A"])
        #expect(try await names(storage, .init(sort: .leastRecentlyUpdated)) == ["A", "C", "B"])
        #expect(try await storage.fetch(User.self).map(\.name) == ["A", "B", "C"])
    }

    @Test("ties are broken by insertion order in both directions", arguments: Engine.allCases)
    func ties(engine: Engine) async throws {
        let storage = try engine.storage()
        let users = (0..<20).map { User.make("U\($0)") }
        try await storage.save(users)  // one createdAt for all

        #expect(try await names(storage, .init(sort: .oldestFirst)) == users.map(\.name))
        #expect(try await names(storage, .init(sort: .newestFirst)) == users.reversed().map(\.name))
    }

    @Test("limit and offset slice after sorting", arguments: Engine.allCases)
    func slicing(engine: Engine) async throws {
        let (storage, _, _) = try await seeded(engine)

        #expect(try await names(storage, .init(limit: 2)) == ["A", "B"])
        #expect(try await names(storage, .init(limit: 2, offset: 1)) == ["B", "C"])
        #expect(try await names(storage, .init(sort: .newestFirst, limit: 1)) == ["C"])
        #expect(try await names(storage, .init(limit: 0)) == [])
        #expect(try await names(storage, .init(offset: 3)) == [])
        #expect(try await names(storage, .init(limit: 10, offset: 2)) == ["C"])
    }

    @Test("expired values never appear in slices", arguments: Engine.allCases)
    func expiredExcluded(engine: Engine) async throws {
        let clock = TestDateClock()
        let storage = try engine.storage(clock: clock)
        try await storage.save(User.make("Expiring"), expiration: .seconds(1))
        clock.advance(by: 1)
        try await storage.save(User.make("Live"))
        clock.advance(by: 1)

        #expect(try await names(storage, .init(limit: 1)) == ["Live"])
        #expect(try await storage.page(User.self, page: 1, pageSize: 10).totalCount == 1)
    }

    @Test("pages carry items and totals", arguments: Engine.allCases)
    func pages(engine: Engine) async throws {
        let storage = try engine.storage()
        let users = (1...7).map { User.make("U\($0)") }
        try await storage.save(users)

        let first = try await storage.page(User.self, page: 1, pageSize: 3)
        #expect(first.items.map(\.name) == ["U1", "U2", "U3"])
        #expect((first.page, first.pageSize, first.totalCount, first.totalPages) == (1, 3, 7, 3))
        #expect(first.hasNextPage)

        let last = try await storage.page(User.self, page: 3, pageSize: 3)
        #expect(last.items.map(\.name) == ["U7"])
        #expect(!last.hasNextPage)

        let pastEnd = try await storage.page(User.self, page: 4, pageSize: 3)
        #expect(pastEnd.items.isEmpty)
        #expect(pastEnd.totalCount == 7)
        #expect(!pastEnd.hasNextPage)

        let newest = try await storage.page(User.self, page: 1, pageSize: 2, sort: .newestFirst)
        #expect(newest.items.map(\.name) == ["U7", "U6"])
    }

    @Test("page math", arguments: [(0, 10, 0), (10, 10, 1), (11, 10, 2), (1, 1, 1), (25, 5, 5)])
    func pageMath(total: Int, size: Int, pages: Int) {
        let page = StoragePage<Int>(items: [], page: 1, pageSize: size, totalCount: total)
        #expect(page.totalPages == pages)
        #expect(page.hasNextPage == (pages > 1))
    }

    @Test("an empty store has no pages", arguments: Engine.allCases)
    func emptyPages(engine: Engine) async throws {
        let page = try await engine.storage().page(User.self, page: 1, pageSize: 10)
        #expect(page == StoragePage(items: [], page: 1, pageSize: 10, totalCount: 0))
        #expect(page.totalPages == 0)
    }

    @Test("filters run on DTO fields, then sort and slice", arguments: Engine.allCases)
    func filtering(engine: Engine) async throws {
        let storage = try engine.storage()
        try await storage.save((1...10).map { Product(id: $0, title: $0.isMultiple(of: 2) ? "even" : "odd") })

        let evens = try await storage.fetch(Product.self, where: { $0.title == "even" })
        #expect(evens.map(\.id) == [2, 4, 6, 8, 10])

        let slice = try await storage.fetch(
            Product.self, where: { $0.id > 3 }, options: FetchOptions(sort: .newestFirst, limit: 2, offset: 1)
        )
        #expect(slice.map(\.id) == [9, 8])
        #expect(try await storage.fetch(Product.self, where: { _ in false }).isEmpty)
    }

    @Test("an error thrown by the filter propagates unchanged")
    func throwingFilter() async throws {
        struct Stop: Error {}
        let storage = try EngineContractTests.Engine.inMemory.storage()
        try await storage.save(Product(id: 1, title: "x"))

        await #expect(throws: Stop.self) {
            _ = try await storage.fetch(Product.self, where: { _ in throw Stop() })
        }
    }

    @Test("repository forwards queries")
    func repository() async throws {
        let (storage, _, _) = try await seeded(.swiftData)
        let users = storage.repository(User.self)

        #expect(try await users.fetchAll(options: .init(sort: .newestFirst)).map(\.name) == ["C", "B", "A"])
        #expect(try await users.fetch(where: { $0.name != "B" }).map(\.name) == ["A", "C"])
        #expect(try await users.page(2, pageSize: 2).items.map(\.name) == ["C"])
    }

    @Test("default options are the plain fetch order")
    func defaults() {
        #expect(FetchOptions.default == FetchOptions(sort: .oldestFirst, limit: nil, offset: 0))
        #expect(StorageSort.allCases.count == 4)
    }
}
