import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

/// The same behavior, asserted against every engine: the in-memory test double must be a faithful
/// stand-in for the SwiftData engine, or tests written against it prove nothing.
@Suite("Engine contract")
struct EngineContractTests {

    enum Engine: String, CaseIterable, CustomTestStringConvertible {
        case swiftData, inMemory
        var testDescription: String { rawValue }

        func storage(clock: TestDateClock = TestDateClock()) throws -> LocalStorage {
            switch self {
            case .swiftData: try LocalStorage(configuration: .inMemory, now: { clock.now })
            case .inMemory: LocalStorage(engine: InMemoryStorageEngine(), now: { clock.now })
            }
        }
    }

    @Test("CRUD round-trip", arguments: Engine.allCases)
    func crud(engine: Engine) async throws {
        let storage = try engine.storage()
        var user = User.make()

        try await storage.save(user)
        user.name = "Renamed"
        try await storage.save(user)

        #expect(try await storage.fetch(User.self, id: user.id) == user)
        #expect(try await storage.count(User.self) == 1)
        try await storage.delete(User.self, id: user.id)
        #expect(try await storage.exists(User.self, id: user.id) == false)
    }

    @Test("fetch all is ordered by creation, then insertion", arguments: Engine.allCases)
    func ordering(engine: Engine) async throws {
        let clock = TestDateClock()
        let storage = try engine.storage(clock: clock)
        let first = User.make("First"), second = User.make("Second"), third = User.make("Third")

        try await storage.save([first, second])      // same instant
        clock.advance(by: 1)
        try await storage.save(third)
        try await storage.save(first)                  // update keeps createdAt

        #expect(try await storage.fetch(User.self).map(\.name) == ["First", "Second", "Third"])
    }

    @Test("a batch with a repeated ID keeps the last value", arguments: Engine.allCases)
    func duplicateIDsInBatch(engine: Engine) async throws {
        let storage = try engine.storage()
        let id = UUID()

        try await storage.save([User(id: id, name: "A", email: "a"), User(id: id, name: "B", email: "b")])

        #expect(try await storage.count(User.self) == 1)
        #expect(try await storage.fetch(User.self, id: id)?.name == "B")
    }

    @Test("fetch all purges expired values", arguments: Engine.allCases)
    func fetchAllPurges(engine: Engine) async throws {
        let clock = TestDateClock()
        let storage = try engine.storage(clock: clock)
        let keep = User.make("Keep"), drop = User.make("Drop")
        try await storage.save(keep)
        try await storage.save(drop, expiration: .seconds(1))
        clock.advance(by: 2)

        #expect(try await storage.fetch(User.self) == [keep])
        #expect(try await storage.metadata(User.self, id: drop.id) == nil)
        #expect(try await storage.removeExpired() == 0)
    }

    @Test("deleteAll is scoped to one type; removeAll clears everything", arguments: Engine.allCases)
    func deletion(engine: Engine) async throws {
        let storage = try engine.storage()
        try await storage.save([User.make("A"), User.make("B")])
        try await storage.save(Product(id: 1, title: "Lamp"))
        try await storage.set(true, forKey: "flag")

        try await storage.deleteAll(User.self)
        #expect(try await storage.count(User.self) == 0)
        #expect(try await storage.count(Product.self) == 1)
        #expect(try await storage.get(Bool.self, forKey: "flag") == true)

        try await storage.removeAll()
        #expect(try await storage.count(Product.self) == 0)
        #expect(try await storage.get(Bool.self, forKey: "flag") == nil)
    }

    @Test("key-value entries are invisible to entity listings", arguments: Engine.allCases)
    func namespaces(engine: Engine) async throws {
        let storage = try engine.storage()
        try await storage.set("x", forKey: "a")
        try await storage.set("y", forKey: "b")

        #expect(try await storage.count(User.self) == 0)
        #expect(try await storage.fetch(User.self).isEmpty)
    }
}
