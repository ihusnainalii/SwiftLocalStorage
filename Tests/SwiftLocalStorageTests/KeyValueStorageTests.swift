import Foundation
import Testing
@testable import SwiftLocalStorage

@Suite("Key-value storage")
struct KeyValueStorageTests {

    @Test("set then get round-trips a Codable value")
    func setGet() async throws {
        let storage = try makeStorage()
        let settings = AppSettings(darkMode: true, fontSize: 14)

        try await storage.set(settings, forKey: "settings")

        #expect(try await storage.get(AppSettings.self, forKey: "settings") == settings)
    }

    @Test("primitive values round-trip", arguments: ["hello", "", "émoji 🚀"])
    func primitives(value: String) async throws {
        let storage = try makeStorage()
        try await storage.set(value, forKey: "k")
        #expect(try await storage.get(String.self, forKey: "k") == value)
    }

    @Test("set overwrites; get of a missing key is nil")
    func overwrite() async throws {
        let storage = try makeStorage()
        try await storage.set(1, forKey: "n")
        try await storage.set(2, forKey: "n")

        #expect(try await storage.get(Int.self, forKey: "n") == 2)
        #expect(try await storage.get(Int.self, forKey: "missing") == nil)
    }

    @Test("remove deletes the value; removing a missing key is a no-op")
    func remove() async throws {
        let storage = try makeStorage()
        try await storage.set(true, forKey: "flag")

        try await storage.remove(forKey: "flag")
        try await storage.remove(forKey: "never-set")

        #expect(try await storage.get(Bool.self, forKey: "flag") == nil)
    }

    @Test("reading with the wrong type throws decodingFailed")
    func wrongType() async throws {
        let storage = try makeStorage()
        try await storage.set("text", forKey: "k")

        await #expect {
            _ = try await storage.get(Int.self, forKey: "k")
        } throws: { ($0 as? LocalStorageError)?.code == .decodingFailed }
    }
}
