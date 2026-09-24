import Foundation
import Testing
@testable import SwiftLocalStorage

@Suite("Concurrency")
struct ConcurrencyTests {

    @Test("100 concurrent saves all land")
    func concurrentSaves() async throws {
        let storage = try makeStorage()
        let users = (0..<100).map { User.make("U\($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for user in users {
                group.addTask { try await storage.save(user) }
            }
            try await group.waitForAll()
        }

        #expect(try await storage.count(User.self) == 100)
    }

    @Test("100 concurrent reads return the stored value")
    func concurrentReads() async throws {
        let storage = try makeStorage()
        let user = User.make()
        try await storage.save(user)

        let results = try await withThrowingTaskGroup(of: User?.self) { group in
            for _ in 0..<100 {
                group.addTask { try await storage.fetch(User.self, id: user.id) }
            }
            return try await group.reduce(into: [User?]()) { $0.append($1) }
        }

        #expect(results.count == 100)
        #expect(results.allSatisfy { $0 == user })
    }

    @Test("concurrent mixed reads and writes stay consistent")
    func mixed() async throws {
        let storage = try makeStorage()
        let users = (0..<50).map { User.make("U\($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for user in users {
                group.addTask { try await storage.save(user) }
                group.addTask { _ = try await storage.fetch(User.self) }
                group.addTask { try await storage.set(user.name, forKey: user.id.uuidString) }
            }
            try await group.waitForAll()
        }

        #expect(try await storage.count(User.self) == 50)
        for user in users {
            #expect(try await storage.get(String.self, forKey: user.id.uuidString) == user.name)
        }
    }
}
