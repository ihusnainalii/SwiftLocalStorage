import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

@Suite("Errors & cancellation")
struct ErrorTests {

    struct FailingEncoder: StorageEncoder {
        struct Boom: Error {}
        func encode<T: Encodable>(_ value: T) throws -> Data { throw Boom() }
    }

    @Test("a corrupt payload throws decodingFailed with the record key")
    func corruptPayload() async throws {
        let engine = InMemoryStorageEngine()
        let storage = LocalStorage(engine: engine)
        let id = UUID()
        await engine.insertRaw(
            Data("{ invalid JSON".utf8), typeName: StorageKey.typeName(of: User.self), id: id.uuidString
        )

        do {
            _ = try await storage.fetch(User.self, id: id)
            Issue.record("expected decodingFailed")
        } catch let LocalStorageError.decodingFailed(key, _) {
            #expect(key == StorageKey.entity(User.self, id: id))
        }
    }

    @Test("an encoder failure throws encodingFailed and writes nothing")
    func encodingFailure() async throws {
        let engine = InMemoryStorageEngine()
        let storage = LocalStorage(configuration: .init(encoder: FailingEncoder()), engine: engine)

        await #expect {
            try await storage.save(User.make())
        } throws: { ($0 as? LocalStorageError)?.code == .encodingFailed }
        #expect(try await storage.count(User.self) == 0)
    }

    @Test("a cancelled task throws cancelled and writes nothing")
    func cancellation() async throws {
        let storage = try makeStorage()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await storage.save(User.make())
        }

        await #expect {
            try await task.value
        } throws: { ($0 as? LocalStorageError)?.code == .cancelled }
        #expect(try await storage.count(User.self) == 0)
    }

    @Test("every error case maps to its code", arguments: [
        (LocalStorageError.encodingFailed(underlying: CancellationError()), LocalStorageError.Code.encodingFailed),
        (.decodingFailed(key: "k", underlying: CancellationError()), .decodingFailed),
        (.persistenceFailed(underlying: CancellationError()), .persistenceFailed),
        (.containerInitializationFailed(underlying: CancellationError()), .containerInitializationFailed),
        (.cancelled, .cancelled),
    ])
    func codes(error: LocalStorageError, code: LocalStorageError.Code) {
        #expect(error.code == code)
    }
}
