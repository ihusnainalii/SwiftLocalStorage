import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

@Suite("Observation")
struct ObservationTests {

    typealias Engine = EngineContractTests.Engine

    // Events are published before the write call returns and streams buffer them, so a test can
    // write first and then read the iterator: no sleeps, no timing.

    @Test("save emits inserted, then updated", arguments: Engine.allCases)
    func insertedThenUpdated(engine: Engine) async throws {
        let storage = try engine.storage()
        var changes = storage.changes(of: User.self).makeAsyncIterator()
        var user = User.make()

        try await storage.save(user)
        user.name = "Renamed"
        try await storage.save(user)

        #expect(await changes.next() == .inserted(User(id: user.id, name: "Ada", email: user.email)))
        #expect(await changes.next() == .updated(user))
    }

    @Test("a batch emits one event per value, in order", arguments: Engine.allCases)
    func batch(engine: Engine) async throws {
        let storage = try engine.storage()
        let existing = User.make("Existing")
        try await storage.save(existing)
        var changes = storage.changes(of: User.self).makeAsyncIterator()
        let fresh = User.make("Fresh")
        var twice = User.make("Twice")

        var renamed = twice
        renamed.name = "Twice-2"
        try await storage.save([fresh, existing, twice, renamed])
        twice = renamed

        #expect(await changes.next() == .inserted(fresh))
        #expect(await changes.next() == .updated(existing))
        #expect(await changes.next() == .inserted(User(id: twice.id, name: "Twice", email: twice.email)))
        #expect(await changes.next() == .updated(renamed))
    }

    @Test("delete emits the stored value; missing IDs emit nothing", arguments: Engine.allCases)
    func deletes(engine: Engine) async throws {
        let storage = try engine.storage()
        let a = User.make("A")
        let b = User.make("B")
        try await storage.save([a, b])
        var changes = storage.changes(of: User.self).makeAsyncIterator()

        try await storage.delete(User.self, id: UUID())  // missing: no event
        var staleCopy = a
        staleCopy.name = "caller's stale copy"
        try await storage.delete([staleCopy, User.make("Ghost")])  // ghost: no event
        try await storage.delete(User.self, id: b.id)

        #expect(await changes.next() == .deleted(a))  // the stored value
        #expect(await changes.next() == .deleted(b))
    }

    @Test("deleteAll and removeAll emit cleared; removeExpired emits expired", arguments: Engine.allCases)
    func bulk(engine: Engine) async throws {
        let clock = TestDateClock()
        let storage = try engine.storage(clock: clock)
        var users = storage.changes(of: User.self).makeAsyncIterator()
        var products = storage.changes(of: Product.self).makeAsyncIterator()

        try await storage.deleteAll(User.self)  // User only
        try await storage.save(Product(id: 1, title: "x"), expiration: .seconds(1))
        clock.advance(by: 2)
        #expect(try await storage.removeExpired() == 1)  // everyone
        #expect(try await storage.removeExpired() == 0)  // nothing removed: no event
        try await storage.removeAll()  // everyone

        #expect(await users.next() == .cleared)
        #expect(await users.next() == .expired)
        #expect(await users.next() == .cleared)
        #expect(await products.next() == .inserted(Product(id: 1, title: "x")))
        #expect(await products.next() == .expired)
        #expect(await products.next() == .cleared)
    }

    @Test("observers only see their own type")
    func typeIsolation() async throws {
        let storage = try Engine.inMemory.storage()
        var users = storage.changes(of: User.self).makeAsyncIterator()

        try await storage.save(Product(id: 1, title: "x"))
        try await storage.set("kv", forKey: "k")  // key-value: no event
        let user = User.make()
        try await storage.save(user)

        #expect(await users.next() == .inserted(user))
    }

    @Test("failed writes emit nothing")
    func failures() async throws {
        let storage = LocalStorage(configuration: .inMemory, engine: ErrorTests.FailingEngine(), now: { Date() })
        let received = Counter()
        let token = storage.hub.subscribe(typeName: StorageKey.typeName(of: User.self)) { _ in received.increment() }
        defer { storage.hub.unsubscribe(typeName: StorageKey.typeName(of: User.self), token: token) }

        _ = try? await storage.save(User.make())
        _ = try? await storage.deleteAll(User.self)
        _ = try? await storage.removeAll()

        #expect(received.value == 0)
    }

    @Test("streams unsubscribe when cancelled or released")
    func unsubscribe() async throws {
        let storage = try Engine.inMemory.storage()
        let typeName = StorageKey.typeName(of: User.self)

        let task = Task { for await _ in storage.changes(of: User.self) {} }
        while !storage.hub.hasObservers(typeName) { await Task.yield() }
        task.cancel()
        await task.value
        #expect(!storage.hub.hasObservers(typeName))

        do { _ = storage.changes(of: User.self) }  // released without iterating
        #expect(!storage.hub.hasObservers(typeName))
    }

    @Test("updates emits the current result, then again after each change", arguments: Engine.allCases)
    func liveQuery(engine: Engine) async throws {
        let storage = try engine.storage()
        let first = User.make("First")
        try await storage.save(first)
        var results = storage.updates(of: User.self, options: FetchOptions(sort: .newestFirst)).makeAsyncIterator()

        #expect(try await results.next()?.map(\.name) == ["First"])

        try await storage.save(User.make("Second"))
        #expect(try await results.next()?.map(\.name) == ["Second", "First"])

        try await storage.delete(User.self, id: first.id)
        #expect(try await results.next()?.map(\.name) == ["Second"])
    }

    @Test("updates coalesces a burst of writes")
    func coalescing() async throws {
        let storage = try Engine.inMemory.storage()
        var results = storage.updates(of: User.self).makeAsyncIterator()
        #expect(try await results.next() == [])

        let burst = (0..<50).map { User.make("U\($0)") }
        for user in burst { try await storage.save(user) }

        var emissions = 0
        var latest: [User] = []
        while latest.count < 50, let next = try await results.next() {
            latest = next
            emissions += 1
        }
        #expect(latest.map(\.id) == burst.map(\.id))
        #expect(emissions < 50)  // not one refetch per write
    }

    @Test("all() yields every value in batches and stops early when asked", arguments: Engine.allCases)
    func batches(engine: Engine) async throws {
        let storage = try engine.storage()
        let users = (0..<25).map { User.make("U\($0)") }
        try await storage.save(users)

        var seen: [User] = []
        for try await user in storage.all(User.self, batchSize: 10) { seen.append(user) }
        #expect(seen == users)

        var firstFive: [User] = []
        for try await user in storage.repository(User.self).all(batchSize: 3) {
            firstFive.append(user)
            if firstFive.count == 5 { break }
        }
        #expect(firstFive == Array(users.prefix(5)))

        var none = 0
        for try await _ in storage.all(Product.self) { none += 1 }
        #expect(none == 0)
    }

    @Test("all() reads one batch per step")
    func batchReads() async throws {
        final class Lines: StorageLogger, @unchecked Sendable {
            private let lock = NSLock()
            private var _lines: [String] = []
            var lines: [String] { lock.withLock { _lines } }
            func log(_ line: String, level: StorageLogLevel) { lock.withLock { _lines.append(line) } }
        }
        let lines = Lines()
        let storage = LocalStorage(
            configuration: .init(isStoredInMemoryOnly: true, logger: lines, logLevel: .debug),
            engine: InMemoryStorageEngine()
        )
        try await storage.save((0..<25).map { User.make("U\($0)") })

        for try await _ in storage.all(User.self, batchSize: 10) {}

        #expect(lines.lines.filter { $0.contains("limit=10") }.count == 3)  // 10 + 10 + 5
    }

    @Test("updates finishes with the error when the store fails")
    func liveQueryFailure() async throws {
        let storage = LocalStorage(configuration: .inMemory, engine: ErrorTests.FailingEngine(), now: { Date() })
        var results = storage.updates(of: User.self).makeAsyncIterator()

        await #expect {
            _ = try await results.next()
        } throws: { ($0 as? LocalStorageError)?.code == .persistenceFailed }
    }

    @Test("repository forwards observation")
    func repository() async throws {
        let storage = try Engine.inMemory.storage()
        let users = storage.repository(User.self)
        var changes = users.changes().makeAsyncIterator()
        var results = users.updates().makeAsyncIterator()
        #expect(try await results.next() == [])

        let user = User.make()
        try await users.save(user)

        #expect(await changes.next() == .inserted(user))
        #expect(try await results.next() == [user])
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
