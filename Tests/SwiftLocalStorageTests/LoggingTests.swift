import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

@Suite("Logging")
struct LoggingTests {

    final class CapturingLogger: StorageLogger, @unchecked Sendable {
        private let lock = NSLock()
        private var _lines: [(String, StorageLogLevel)] = []
        var lines: [(String, StorageLogLevel)] { lock.withLock { _lines } }

        func log(_ line: String, level: StorageLogLevel) {
            lock.withLock { _lines.append((line, level)) }
        }
    }

    private func storage(level: StorageLogLevel, logger: CapturingLogger) -> LocalStorage {
        LocalStorage(
            configuration: .init(isStoredInMemoryOnly: true, logger: logger, logLevel: level),
            engine: InMemoryStorageEngine()
        )
    }

    @Test("writes are logged with key and size but never the payload")
    func noPayload() async throws {
        let logger = CapturingLogger()
        let storage = storage(level: .debug, logger: logger)
        let secret = User(id: UUID(), name: "TopSecretName", email: "secret@example.com")

        try await storage.save(secret)
        _ = try await storage.fetch(User.self, id: secret.id)
        try await storage.set("hunter2-value", forKey: "pw")

        let text = logger.lines.map(\.0).joined(separator: "\n")
        #expect(text.contains("save"))
        #expect(text.contains("bytes"))
        #expect(text.contains("kv|pw"))
        #expect(!text.contains("TopSecretName"))
        #expect(!text.contains("secret@example.com"))
        #expect(!text.contains("hunter2-value"))
    }

    @Test("queries log their options at debug level")
    func queryLogging() async throws {
        let logger = CapturingLogger()
        let storage = storage(level: .debug, logger: logger)

        _ = try await storage.fetch(User.self, options: FetchOptions(sort: .newestFirst, limit: 5, offset: 10))
        _ = try await storage.fetch(User.self)

        let lines = logger.lines.map(\.0)
        #expect(lines.contains { $0.contains("sort=newestFirst offset=10 limit=5") })
        #expect(lines.contains { $0.contains("sort=oldestFirst offset=0") && !$0.contains("limit") })
    }

    @Test("the level filters lines")
    func filtering() async throws {
        let logger = CapturingLogger()
        let storage = storage(level: .info, logger: logger)
        let user = User.make()

        try await storage.save(user)  // info
        _ = try await storage.fetch(User.self, id: user.id)  // debug: filtered

        #expect(logger.lines.map(\.1) == [.info])
    }

    @Test("logging is off by default")
    func offByDefault() async throws {
        let logger = CapturingLogger()
        var configuration = LocalStorageConfiguration.inMemory
        configuration.logger = logger
        let storage = LocalStorage(configuration: configuration, engine: InMemoryStorageEngine())

        try await storage.save(User.make())

        #expect(logger.lines.isEmpty)
    }

    @Test("failures are logged at error level")
    func errors() async throws {
        let logger = CapturingLogger()
        let engine = InMemoryStorageEngine()
        let storage = LocalStorage(
            configuration: .init(logger: logger, logLevel: .error), engine: engine
        )
        let id = UUID()
        await engine.insertRaw(Data("not json".utf8), typeName: StorageKey.typeName(of: User.self), id: id.uuidString)

        _ = try? await storage.fetch(User.self, id: id)

        #expect(logger.lines.count == 1)
        #expect(logger.lines.first?.1 == .error)
        #expect(logger.lines.first?.0.contains("decode") == true)
        #expect(logger.lines.first?.0.contains("not json") == false)
    }

    @Test("levels are ordered quietest to loudest")
    func ordering() {
        #expect(StorageLogLevel.allCases == [.none, .error, .info, .debug])
        #expect(StorageLogLevel.error < .debug)
    }

    @Test("built-in sinks accept every level without crashing")
    func sinks() {
        for level in StorageLogLevel.allCases {
            NoopStorageLogger().log("x", level: level)
            OSLogStorageLogger(category: "tests").log("x", level: level)
        }
    }
}
