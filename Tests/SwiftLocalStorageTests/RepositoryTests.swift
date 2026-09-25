import Foundation
import Testing
@testable import SwiftLocalStorage

@Suite("Repository")
struct RepositoryTests {

    @Test("repository forwards every operation to its storage")
    func forwards() async throws {
        let storage = try makeStorage()
        let users = storage.repository(User.self)
        let a = User.make("A")
        let b = User.make("B")
        let c = User.make("C")

        try await users.save(a)
        try await users.save([b, c])
        #expect(try await users.count() == 3)
        #expect(try await users.fetch(id: a.id) == a)
        #expect(try await users.exists(id: b.id))
        #expect(try await users.metadata(id: a.id)?.size ?? 0 > 0)
        #expect(try await users.metadata(id: UUID()) == nil)
        #expect(Set(try await users.fetchAll().map(\.id)) == [a.id, b.id, c.id])

        try await users.delete(id: a.id)
        #expect(try await users.fetch(id: a.id) == nil)

        try await users.deleteAll()
        #expect(try await users.count() == 0)
    }
}
