import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

@Suite("Cache expiration & metadata")
struct CacheTests {

    @Test(
        "expiration resolves to an absolute date",
        arguments: [
            (CacheExpiration.never, nil),
            (.seconds(30), 30),
            (.minutes(10), 600),
            (.hours(1), 3_600),
            (.days(2), 172_800),
        ] as [(CacheExpiration, TimeInterval?)])
    func resolves(expiration: CacheExpiration, offset: TimeInterval?) {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        #expect(expiration.expiresAt(from: now) == offset.map { now + $0 })
    }

    @Test(".date expires at that date")
    func fixedDate() {
        let date = Date(timeIntervalSinceReferenceDate: 42)
        #expect(CacheExpiration.date(date).expiresAt(from: .distantPast) == date)
    }

    @Test("a value is readable before expiry and absent after it")
    func hitThenMiss() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        let user = User.make()
        try await storage.save(user, expiration: .minutes(10))

        clock.advance(by: 599)
        #expect(try await storage.fetch(User.self, id: user.id) == user)
        #expect(try await storage.exists(User.self, id: user.id))

        clock.advance(by: 1)
        #expect(try await storage.fetch(User.self, id: user.id) == nil)
        #expect(try await storage.exists(User.self, id: user.id) == false)
    }

    @Test("fetch all and count skip expired values")
    func listingsSkipExpired() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        let fresh = User.make("Fresh")
        let stale = User.make("Stale")
        try await storage.save(fresh)
        try await storage.save(stale, expiration: .seconds(5))

        clock.advance(by: 10)

        #expect(try await storage.count(User.self) == 1)
        #expect(try await storage.fetch(User.self) == [fresh])
    }

    @Test("reading an expired value purges it")
    func lazyPurge() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        let user = User.make()
        try await storage.save(user, expiration: .seconds(1))
        clock.advance(by: 2)

        _ = try await storage.fetch(User.self, id: user.id)

        #expect(try await storage.metadata(User.self, id: user.id) == nil)
    }

    @Test("re-saving refreshes the expiration")
    func refresh() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        let user = User.make()
        try await storage.save(user, expiration: .seconds(10))
        clock.advance(by: 8)
        try await storage.save(user)  // now .never

        clock.advance(by: 1_000)

        #expect(try await storage.fetch(User.self, id: user.id) == user)
    }

    @Test("key-value entries expire too")
    func keyValueExpiry() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        try await storage.set("token-ish", forKey: "k", expiration: .hours(1))

        clock.advance(by: 3_601)

        #expect(try await storage.get(String.self, forKey: "k") == nil)
    }

    @Test("metadata reports dates, size and expiry, even once expired")
    func metadata() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        let user = User.make()
        let start = clock.now
        try await storage.save(user, expiration: .seconds(60))

        let fresh = try #require(try await storage.metadata(User.self, id: user.id))
        #expect(fresh.createdAt == start)
        #expect(fresh.updatedAt == start)
        #expect(fresh.expiresAt == start + 60)
        #expect(fresh.size == (try JSONEncoder().encode(user)).count)
        #expect(fresh.isExpired == false)

        clock.advance(by: 61)
        #expect(try await storage.metadata(User.self, id: user.id)?.isExpired == true)
        #expect(try await storage.metadata(User.self, id: UUID()) == nil)
    }

    @Test("removeExpired deletes only expired records and returns the count")
    func removeExpired() async throws {
        let clock = TestDateClock()
        let storage = try makeStorage(clock: clock)
        try await storage.save([User.make("A"), User.make("B")], expiration: .seconds(5))
        try await storage.save(User.make("Keep"))
        try await storage.set(1, forKey: "old", expiration: .seconds(5))
        try await storage.set(2, forKey: "new")

        clock.advance(by: 6)

        #expect(try await storage.removeExpired() == 3)
        #expect(try await storage.removeExpired() == 0)
        #expect(try await storage.count(User.self) == 1)
        #expect(try await storage.get(Int.self, forKey: "new") == 2)
    }

    @Test("the in-memory engine honours expiration the same way")
    func inMemoryEngineParity() async throws {
        let clock = TestDateClock()
        let storage = LocalStorage(engine: InMemoryStorageEngine(), now: { clock.now })
        let user = User.make()
        try await storage.save(user, expiration: .seconds(5))
        try await storage.save(User.make("Keep"))

        clock.advance(by: 6)

        #expect(try await storage.fetch(User.self, id: user.id) == nil)
        #expect(try await storage.count(User.self) == 1)
        #expect(try await storage.removeExpired() == 0)
    }
}
