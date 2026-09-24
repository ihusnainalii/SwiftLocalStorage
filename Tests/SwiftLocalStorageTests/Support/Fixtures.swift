import Foundation
@_spi(SwiftLocalStorageTesting) @testable import SwiftLocalStorage

struct User: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var email: String

    static func make(_ name: String = "Ada") -> User {
        User(id: UUID(), name: name, email: "\(name.lowercased())@example.com")
    }
}

struct Product: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    var title: String
}

struct Order: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    var total: Double
}

struct AppSettings: Codable, Sendable, Equatable {
    var darkMode: Bool
    var fontSize: Int
}

/// A mutable wall clock for expiration tests.
final class TestDateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

/// Opens a fresh in-memory SwiftData-backed storage.
func makeStorage(clock: TestDateClock? = nil) throws -> LocalStorage {
    guard let clock else { return try LocalStorage(configuration: .inMemory) }
    return try LocalStorage(configuration: .inMemory, now: { clock.now })
}
