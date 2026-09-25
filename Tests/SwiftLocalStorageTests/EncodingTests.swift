import Foundation
import Testing
@testable import SwiftLocalStorage

@Suite("Encoding & DTO evolution")
struct EncodingTests {

    enum Status: String, Codable, Sendable { case active, banned }

    struct Rich: Codable, Identifiable, Sendable, Equatable {
        struct Address: Codable, Sendable, Equatable {
            var city: String
            var zip: String?
        }
        let id: String
        var status: Status
        var tags: [String]
        var address: Address
        var nickname: String?
        var joined: Date
        var homepage: URL
        var scores: [String: Double]
    }

    /// Custom `Codable`: encoded as a single string.
    struct Point: Codable, Identifiable, Sendable, Equatable {
        var id: String { "\(x),\(y)" }
        var x: Int, y: Int

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
        init(from decoder: any Decoder) throws {
            let parts = try decoder.singleValueContainer().decode(String.self).split(separator: ",")
            x = Int(parts[0])!
            y = Int(parts[1])!
        }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(id)
        }
    }

    @Test("nested objects, arrays, optionals, enums, dates and URLs round-trip")
    func richRoundTrip() async throws {
        let storage = try makeStorage()
        let value = Rich(
            id: "r1", status: .banned, tags: ["a", "b"], address: .init(city: "Lahore", zip: nil),
            nickname: nil, joined: Date(timeIntervalSince1970: 1_700_000_000.123),
            homepage: URL(string: "https://example.com/p?q=1")!, scores: ["x": 1.5]
        )

        try await storage.save(value)

        #expect(try await storage.fetch(Rich.self, id: "r1") == value)
    }

    @Test("custom Codable types round-trip")
    func customCodable() async throws {
        let storage = try makeStorage()
        try await storage.save(Point(x: 3, y: 4))
        #expect(try await storage.fetch(Point.self, id: "3,4") == Point(x: 3, y: 4))
    }

    struct UserV1: Codable, Identifiable, Sendable, LocalStorageNaming {
        static var storageTypeName: String { "User" }
        let id: Int
        var name: String
    }

    struct UserV2: Codable, Identifiable, Sendable, LocalStorageNaming {
        static var storageTypeName: String { "User" }
        let id: Int
        var name: String
        var avatar: URL?  // new optional field: compatible
    }

    struct UserV3: Codable, Identifiable, Sendable, LocalStorageNaming {
        static var storageTypeName: String { "User" }
        let id: Int
        var name: String
        var age: Int  // new required field: incompatible
    }

    @Test("adding an optional field decodes old records")
    func compatibleEvolution() async throws {
        let storage = try makeStorage()
        try await storage.save(UserV1(id: 1, name: "Ada"))

        let upgraded = try #require(try await storage.fetch(UserV2.self, id: 1))
        #expect(upgraded.name == "Ada")
        #expect(upgraded.avatar == nil)
    }

    @Test("adding a required field surfaces decodingFailed, not a crash")
    func incompatibleEvolution() async throws {
        let storage = try makeStorage()
        try await storage.save(UserV1(id: 1, name: "Ada"))

        await #expect {
            _ = try await storage.fetch(UserV3.self, id: 1)
        } throws: { ($0 as? LocalStorageError)?.code == .decodingFailed }
    }

    @Test("default type name is module-qualified")
    func typeNames() {
        #expect(StorageKey.typeName(of: User.self) == String(reflecting: User.self))
        #expect(StorageKey.typeName(of: User.self).contains("."))
        #expect(StorageKey.typeName(of: UserV1.self) == "User")
    }
}
