import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

@Suite("Entity storage")
struct EntityStorageTests {

    @Test("save then fetch by ID round-trips the DTO")
    func saveAndFetch() async throws {
        let storage = try makeStorage()
        let user = User.make()

        try await storage.save(user)

        #expect(try await storage.fetch(User.self, id: user.id) == user)
    }

    @Test("fetch of a missing ID returns nil")
    func fetchMissing() async throws {
        let storage = try makeStorage()
        #expect(try await storage.fetch(User.self, id: UUID()) == nil)
    }

    @Test("saving an existing ID updates it and preserves createdAt")
    func upsert() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        var user = User.make()
        try await storage.save(user)
        let key = StorageKey.entity(User.self, id: user.id)
        let created = try #require(try await storage.liveRecord(forKey: key)).createdAt

        clock.advance(by: 60)
        user.name = "Grace"
        try await storage.save(user)

        #expect(try await storage.fetch(User.self, id: user.id)?.name == "Grace")
        #expect(try await storage.count(User.self) == 1)
        let record = try #require(try await storage.liveRecord(forKey: key))
        #expect(record.createdAt == created)
        #expect(record.updatedAt == created + 60)
    }

    @Test("fetch all returns every value in insertion order")
    func fetchAll() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        let users = ["A", "B", "C"].map(User.make)
        for user in users {
            try await storage.save(user)
            clock.advance(by: 1)
        }

        #expect(try await storage.fetch(User.self) == users)
    }

    @Test("batch save stores every value")
    func batchSave() async throws {
        let storage = try makeStorage()
        let users = (0..<50).map { User.make("U\($0)") }

        try await storage.save(users)

        #expect(try await storage.count(User.self) == 50)
        #expect(Set(try await storage.fetch(User.self).map(\.id)) == Set(users.map(\.id)))
    }

    @Test("count and exists reflect stored values")
    func countAndExists() async throws {
        let storage = try makeStorage()
        let user = User.make()
        #expect(try await storage.count(User.self) == 0)
        #expect(try await storage.exists(User.self, id: user.id) == false)

        try await storage.save(user)

        #expect(try await storage.count(User.self) == 1)
        #expect(try await storage.exists(User.self, id: user.id))
    }

    @Test("delete removes one value; deleting a missing ID is a no-op")
    func delete() async throws {
        let storage = try makeStorage()
        let a = User.make("A"), b = User.make("B")
        try await storage.save([a, b])

        try await storage.delete(User.self, id: a.id)
        try await storage.delete(User.self, id: UUID())

        #expect(try await storage.fetch(User.self) == [b])
    }

    @Test("deleteAll removes one type only")
    func deleteAll() async throws {
        let storage = try makeStorage()
        try await storage.save([User.make("A"), User.make("B")])
        try await storage.save(Product(id: 1, title: "Book"))

        try await storage.deleteAll(User.self)

        #expect(try await storage.count(User.self) == 0)
        #expect(try await storage.count(Product.self) == 1)
    }

    @Test("types sharing an ID never collide")
    func keyIsolation() async throws {
        let storage = try makeStorage()
        try await storage.save(Product(id: 123, title: "Lamp"))
        try await storage.save(Order(id: 123, total: 9.5))
        try await storage.set("kv", forKey: "123")

        #expect(try await storage.fetch(Product.self, id: 123)?.title == "Lamp")
        #expect(try await storage.fetch(Order.self, id: 123)?.total == 9.5)
        #expect(try await storage.get(String.self, forKey: "123") == "kv")
        #expect(try await storage.count(Product.self) == 1)
    }

    @Test("removeAll clears entities and key-value entries")
    func removeAll() async throws {
        let storage = try makeStorage()
        try await storage.save(User.make())
        try await storage.set(1, forKey: "n")

        try await storage.removeAll()

        #expect(try await storage.count(User.self) == 0)
        #expect(try await storage.get(Int.self, forKey: "n") == nil)
    }

    @Test("a named on-disk store persists across instances")
    func persistsAcrossInstances() async throws {
        // Fixed name: one on-disk store is reused (and emptied) on every run.
        let name = "SwiftLocalStorageTests-Persistence"
        let user = User.make()
        do {
            let storage = try LocalStorage(configuration: .init(name: name))
            try await storage.removeAll()
            try await storage.save(user)
        }
        let reopened = try LocalStorage(configuration: .init(name: name))
        #expect(try await reopened.fetch(User.self, id: user.id) == user)
        try await reopened.removeAll()
    }
}
